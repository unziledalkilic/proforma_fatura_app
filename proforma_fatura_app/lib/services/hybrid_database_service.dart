import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:http/http.dart' as http;
import '../models/customer.dart';
import '../models/product.dart';
import '../models/invoice.dart';
import '../models/invoice_item.dart';
import '../models/company_info.dart';
import '../utils/id_converter.dart';
import '../utils/error_handler.dart';
import '../utils/database_validator.dart';
import '../utils/database_maintenance.dart';

import 'firebase_service.dart';

/// Hybrid Database Service - SQLite (offline) + Firebase (online) senkronizasyonu
class HybridDatabaseService {
  static final HybridDatabaseService _instance =
      HybridDatabaseService._internal();
  factory HybridDatabaseService() => _instance;
  HybridDatabaseService._internal();

  static Database? _database;
  final FirebaseService _firebaseService = FirebaseService();
  bool _isOnline = false;
  final _connectivityStreamController = StreamController<bool>.broadcast();
  Stream<bool> get connectivityStream => _connectivityStreamController.stream;

  bool _pullEnabled = false; // SQLite birincil; Firebase çekme isteğe bağlı
  Timer? _syncTimer;
  Timer? _debounceSync;
  bool _isSyncInProgress = false;
  final List<String> _pendingSyncOperations = [];

  // Getters
  bool get isOnline => _isOnline;
  int get pendingSyncCount => _pendingSyncOperations.length;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  /// Initialize hybrid database service
  Future<void> initialize() async {
    await _checkConnectivity();
    await _firebaseService.initialize();
    _startConnectivityListener();
    _startPeriodicSync();
    await database;
    await _ensureInvoiceDetailTables();

    // Ensure deleted_records table exists
  }

  Future<Database> _initDatabase() async {
    String path = join(await getDatabasesPath(), 'proforma_fatura_hybrid.db');
    return await openDatabase(
      path,
      version: 13, // Incremented to trigger upgrade for company_id column
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    // Kullanıcılar tablosu
    await db.execute('''
      CREATE TABLE users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        firebase_id TEXT UNIQUE,
        username TEXT NOT NULL UNIQUE,
        email TEXT NOT NULL UNIQUE,
        password_hash TEXT,
        full_name TEXT,
        company_name TEXT,
        phone TEXT,
        address TEXT,
        tax_number TEXT,
        is_active INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        firebase_synced INTEGER DEFAULT 0,
        last_sync_time TEXT
      )
    ''');

    // Müşteriler tablosu
    await db.execute('''
      CREATE TABLE customers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        firebase_id TEXT UNIQUE,
        user_id INTEGER,
        name TEXT NOT NULL,
        email TEXT,
        phone TEXT,
        address TEXT,
        tax_number TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        firebase_synced INTEGER DEFAULT 0,
        last_sync_time TEXT,
        FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
      )
    ''');

    // Ürünler tablosu
    await db.execute('''
      CREATE TABLE products (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        firebase_id TEXT UNIQUE,
        user_id INTEGER,
        category_id INTEGER,
        company_id TEXT,
        name TEXT NOT NULL,
        description TEXT,
        price REAL NOT NULL,
        currency TEXT NOT NULL DEFAULT 'TRY',
        unit TEXT NOT NULL DEFAULT 'Adet',
        barcode TEXT,
        tax_rate REAL DEFAULT 18.0,
        is_active INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        firebase_synced INTEGER DEFAULT 0,
        last_sync_time TEXT,
        FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
      )
    ''');

    // Faturalar tablosu
    await db.execute('''
      CREATE TABLE invoices (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        firebase_id TEXT UNIQUE,
        user_id INTEGER,
        invoice_number TEXT NOT NULL,
        customer_id INTEGER,
        company_id TEXT,
        invoice_date TEXT NOT NULL,
        due_date TEXT NOT NULL,
        notes TEXT,
        terms TEXT,
        discount_rate REAL DEFAULT 0.0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        firebase_synced INTEGER DEFAULT 0,
        last_sync_time TEXT,
        FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE,
        FOREIGN KEY (customer_id) REFERENCES customers (id) ON DELETE CASCADE
      )
    ''');
    // Benzersiz fatura numarası (kullanıcı + fatura no)
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS ux_invoices_user_invoice_no ON invoices(user_id, invoice_number)',
    );

    // Fatura kalemleri tablosu
    await db.execute('''
      CREATE TABLE invoice_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        firebase_id TEXT UNIQUE,
        invoice_id INTEGER,
        product_id INTEGER,
        quantity REAL NOT NULL,
        unit_price REAL NOT NULL,
        discount_rate REAL DEFAULT 0.0,
        tax_rate REAL DEFAULT 0.0,
        notes TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        firebase_synced INTEGER DEFAULT 0,
        last_sync_time TEXT,
        FOREIGN KEY (invoice_id) REFERENCES invoices (id) ON DELETE CASCADE,
        FOREIGN KEY (product_id) REFERENCES products (id) ON DELETE CASCADE
      )
    ''');

    // Şirket bilgileri tablosu
    await db.execute('''
      CREATE TABLE company_info (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        firebase_id TEXT UNIQUE,
        user_id INTEGER,
        name TEXT NOT NULL,
        address TEXT,
        phone TEXT,
        email TEXT,
        website TEXT,
        tax_number TEXT,
        logo TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        firebase_synced INTEGER DEFAULT 0,
        last_sync_time TEXT,
        FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
      )
    ''');

    // Senkronizasyon log tablosu
    await db.execute('''
      CREATE TABLE sync_log (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        table_name TEXT NOT NULL,
        record_id INTEGER NOT NULL,
        operation TEXT NOT NULL,
        timestamp TEXT NOT NULL,
        synced INTEGER DEFAULT 0,
        error_message TEXT
      )
    ''');

    // Silme işlemleri için bekleyen kayıtlar (tombstone)
    await db.execute('''
      CREATE TABLE IF NOT EXISTS deleted_records (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        table_name TEXT NOT NULL,
        firebase_id TEXT NOT NULL,
        timestamp TEXT NOT NULL,
        synced INTEGER DEFAULT 0
      )
    ''');

    // İndeksler
    await _createIndexes(db);
  }

  /// Check if a column exists in a table
  Future<bool> _columnExists(
    Database db,
    String tableName,
    String columnName,
  ) async {
    try {
      final result = await db.rawQuery('PRAGMA table_info($tableName)');
      return result.any((column) => column['name'] == columnName);
    } catch (e) {
      debugPrint('❌ Error checking column existence: $e');
      return false;
    }
  }

  Future<void> _createIndexes(Database db) async {
    // Firebase ID indeksleri
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_users_firebase_id ON users(firebase_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_customers_firebase_id ON customers(firebase_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_products_firebase_id ON products(firebase_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_invoices_firebase_id ON invoices(firebase_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_invoice_items_firebase_id ON invoice_items(firebase_id)',
    );

    // Sync durumu indeksleri
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_customers_sync ON customers(firebase_synced)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_products_sync ON products(firebase_synced)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_invoices_sync ON invoices(firebase_synced)',
    );

    // User ID indeksleri
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_customers_user_id ON customers(user_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_products_user_id ON products(user_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_invoices_user_id ON invoices(user_id)',
    );
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS ux_invoices_user_invoice_no ON invoices(user_id, invoice_number)',
    );

    // Doğal anahtarlar için ek unique indeksler (mümkün olduğunda)
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS ux_customers_user_email ON customers(user_id, email)',
    );

    // Products company_id index - check if column exists first
    if (await _columnExists(db, 'products', 'company_id')) {
      await db.execute(
        'CREATE UNIQUE INDEX IF NOT EXISTS ux_products_user_company_barcode ON products(user_id, company_id, barcode)',
      );
      // İsim bazlı ürün unique (barcode yoksa) – NULL değerler unique'i bozmaz
      await db.execute(
        'CREATE UNIQUE INDEX IF NOT EXISTS ux_products_user_company_name ON products(user_id, company_id, name)',
      );
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_products_company_id ON products(company_id)',
      );
    }

    // Create index for invoices company_id - check if column exists first
    if (await _columnExists(db, 'invoices', 'company_id')) {
      try {
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_invoices_company_id ON invoices(company_id)',
        );
      } catch (e) {
        debugPrint('⚠️ Could not create idx_invoices_company_id: $e');
        // Column might not exist yet, skip this index
      }
    }
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    debugPrint('🔄 Database upgrade: $oldVersion -> $newVersion');

    if (oldVersion < 3) {
      // Add sync columns to existing tables
      await db.execute('ALTER TABLE customers ADD COLUMN firebase_id TEXT');
      await db.execute(
        'ALTER TABLE customers ADD COLUMN firebase_synced INTEGER DEFAULT 0',
      );
      await db.execute('ALTER TABLE customers ADD COLUMN last_sync_time TEXT');

      await db.execute('ALTER TABLE products ADD COLUMN firebase_id TEXT');
      await db.execute(
        'ALTER TABLE products ADD COLUMN firebase_synced INTEGER DEFAULT 0',
      );
      await db.execute('ALTER TABLE products ADD COLUMN last_sync_time TEXT');

      await db.execute('ALTER TABLE invoices ADD COLUMN firebase_id TEXT');
      await db.execute(
        'ALTER TABLE invoices ADD COLUMN firebase_synced INTEGER DEFAULT 0',
      );
      await db.execute('ALTER TABLE invoices ADD COLUMN last_sync_time TEXT');

      await _createIndexes(db);
    }

    if (oldVersion < 4) {
      // Model mapping düzeltmesi için tabloları yeniden oluştur
      debugPrint(
        '🗑 Eski tabloları temizleniyor (userId -> user_id mapping fix)',
      );

      // Tüm tabloları sil ve yeniden oluştur
      await db.execute('DROP TABLE IF EXISTS sync_log');
      await db.execute('DROP TABLE IF EXISTS invoice_items');
      await db.execute('DROP TABLE IF EXISTS invoices');
      await db.execute('DROP TABLE IF EXISTS products');
      await db.execute('DROP TABLE IF EXISTS customers');
      await db.execute('DROP TABLE IF EXISTS company_info');
      await db.execute('DROP TABLE IF EXISTS users');

      // Tabloları yeniden oluştur
      await _onCreate(db, newVersion);

      debugPrint('✅ Tablolar yeniden oluşturuldu');
    }

    if (oldVersion < 5) {
      // Field mapping düzeltmesi için tabloları yeniden oluştur
      debugPrint('🗑 Field mapping düzeltmesi (camelCase -> snake_case)');

      // Tüm tabloları sil ve yeniden oluştur
      await db.execute('DROP TABLE IF EXISTS sync_log');
      await db.execute('DROP TABLE IF EXISTS invoice_items');
      await db.execute('DROP TABLE IF EXISTS invoices');
      await db.execute('DROP TABLE IF EXISTS products');
      await db.execute('DROP TABLE IF EXISTS customers');
      await db.execute('DROP TABLE IF EXISTS company_info');
      await db.execute('DROP TABLE IF EXISTS users');

      // Tabloları yeniden oluştur
      await _onCreate(db, newVersion);

      debugPrint('✅ Field mapping düzeltildi');
    }

    if (oldVersion < 6) {
      // Tax office alanları kaldırıldı
      debugPrint('🗑 Tax office alanları kaldırılıyor');

      // Tüm tabloları sil ve yeniden oluştur
      await db.execute('DROP TABLE IF EXISTS sync_log');
      await db.execute('DROP TABLE IF EXISTS invoice_items');
      await db.execute('DROP TABLE IF EXISTS invoices');
      await db.execute('DROP TABLE IF EXISTS products');
      await db.execute('DROP TABLE IF EXISTS customers');
      await db.execute('DROP TABLE IF EXISTS company_info');
      await db.execute('DROP TABLE IF EXISTS users');

      // Tabloları yeniden oluştur
      await _onCreate(db, newVersion);

      debugPrint('✅ Tax office alanları kaldırıldı');
    }

    if (oldVersion < 7) {
      // Tüm model SQLite uyumsuzlukları düzeltildi
      debugPrint('🗑 SQLite uyumsuzlukları düzeltiliyor');

      // Tüm tabloları sil ve yeniden oluştur
      await db.execute('DROP TABLE IF EXISTS sync_log');
      await db.execute('DROP TABLE IF EXISTS invoice_items');
      await db.execute('DROP TABLE IF EXISTS invoices');
      await db.execute('DROP TABLE IF EXISTS products');
      await db.execute('DROP TABLE IF EXISTS customers');
      await db.execute('DROP TABLE IF EXISTS company_info');
      await db.execute('DROP TABLE IF EXISTS users');

      // Tabloları yeniden oluştur
      await _onCreate(db, newVersion);

      debugPrint('✅ SQLite uyumsuzlukları düzeltildi');
    }

    if (oldVersion < 8) {
      // user_id NULL sorunu düzeltildi
      debugPrint('🗑 user_id NULL sorunu düzeltiliyor');

      // Tüm tabloları sil ve yeniden oluştur
      await db.execute('DROP TABLE IF EXISTS sync_log');
      await db.execute('DROP TABLE IF EXISTS invoice_items');
      await db.execute('DROP TABLE IF EXISTS invoices');
      await db.execute('DROP TABLE IF EXISTS products');
      await db.execute('DROP TABLE IF EXISTS customers');
      await db.execute('DROP TABLE IF EXISTS company_info');
      await db.execute('DROP TABLE IF EXISTS users');

      // Tabloları yeniden oluştur
      await _onCreate(db, newVersion);

      debugPrint('✅ user_id NULL sorunu düzeltildi');
    }

    if (oldVersion < 9) {
      // Kapsamlı ID dönüşüm düzeltmeleri
      debugPrint('🗑 Kapsamlı ID dönüşüm düzeltmeleri uygulanıyor');

      // Tüm tabloları sil ve yeniden oluştur
      await db.execute('DROP TABLE IF EXISTS sync_log');
      await db.execute('DROP TABLE IF EXISTS invoice_items');
      await db.execute('DROP TABLE IF EXISTS invoices');
      await db.execute('DROP TABLE IF EXISTS products');
      await db.execute('DROP TABLE IF EXISTS customers');
      await db.execute('DROP TABLE IF EXISTS company_info');
      await db.execute('DROP TABLE IF EXISTS users');

      // Tabloları yeniden oluştur
      await _onCreate(db, newVersion);

      debugPrint('✅ Kapsamlı ID dönüşüm düzeltmeleri tamamlandı');
    }

    if (oldVersion < 11) {
      // Add company_id to products and update unique indexes to be company-scoped
      try {
        await db.execute('ALTER TABLE products ADD COLUMN company_id TEXT');
      } catch (_) {}
      // Drop old unique indexes if they exist
      try {
        await db.execute('DROP INDEX IF EXISTS ux_products_user_barcode');
      } catch (_) {}
      try {
        await db.execute('DROP INDEX IF EXISTS ux_products_user_name');
      } catch (_) {}
      // Create new indexes
      await db.execute(
        'CREATE UNIQUE INDEX IF NOT EXISTS ux_products_user_company_barcode ON products(user_id, company_id, barcode)',
      );
      await db.execute(
        'CREATE UNIQUE INDEX IF NOT EXISTS ux_products_user_company_name ON products(user_id, company_id, name)',
      );
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_products_company_id ON products(company_id)',
      );
    }

    if (oldVersion < 12) {
      // Add company_id to invoices table
      try {
        await db.execute('ALTER TABLE invoices ADD COLUMN company_id TEXT');
        // Create index for invoices company_id only if column was added successfully
        if (await _columnExists(db, 'invoices', 'company_id')) {
          await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_invoices_company_id ON invoices(company_id)',
          );
        }
      } catch (e) {
        debugPrint('⚠️ Could not add company_id to invoices: $e');
      }
    }

    if (oldVersion < 13) {
      // Ensure company_id column exists in invoices table (double-check)
      try {
        if (!await _columnExists(db, 'invoices', 'company_id')) {
          await db.execute('ALTER TABLE invoices ADD COLUMN company_id TEXT');
        }
        // Ensure index exists only if column exists
        if (await _columnExists(db, 'invoices', 'company_id')) {
          try {
            await db.execute(
              'CREATE INDEX IF NOT EXISTS idx_invoices_company_id ON invoices(company_id)',
            );
          } catch (e) {
            debugPrint('⚠️ Could not create idx_invoices_company_id index: $e');
          }
        }
      } catch (e) {
        debugPrint('⚠️ Error ensuring company_id in invoices: $e');
      }
    }

    // deleted_records tablosu bazı sürümlerde eksik olabilir - garanti altına al
    try {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS deleted_records (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          table_name TEXT NOT NULL,
          firebase_id TEXT NOT NULL,
          timestamp TEXT NOT NULL,
          synced INTEGER DEFAULT 0
        )
      ''');
    } catch (_) {}

    // Benzersiz fatura numarası indeksi (user_id + invoice_number)
    try {
      await db.execute(
        'CREATE UNIQUE INDEX IF NOT EXISTS ux_invoices_user_invoice_no ON invoices(user_id, invoice_number)',
      );
    } catch (_) {}
  }

  /// Connectivity check - checks both network connection and actual internet access
  Future<void> _checkConnectivity() async {
    final wasOnline = _isOnline;
    try {
      final connectivityResult = await Connectivity().checkConnectivity();
      
      bool hasNetwork = false;
      if (connectivityResult is List) {
        hasNetwork = !connectivityResult.contains(ConnectivityResult.none);
      } else if (connectivityResult is ConnectivityResult) {
        hasNetwork = connectivityResult != ConnectivityResult.none;
      }

      if (!hasNetwork) {
        _isOnline = false;
      } else {
        // Check actual internet access by trying to reach a reliable server
        try {
          final response = await http
              .get(Uri.parse('https://www.google.com'))
              .timeout(const Duration(seconds: 10)); // Increased timeout
          _isOnline = response.statusCode == 200;
        } catch (e) {
          // If Google is blocked, try Firebase
          try {
            final response = await http
                .get(Uri.parse('https://firebase.googleapis.com'))
                .timeout(const Duration(seconds: 10));
            _isOnline = response.statusCode == 200 || response.statusCode == 404;
          } catch (e2) {
            // No actual internet access
            _isOnline = false;
            debugPrint('⚠️ No internet access: $e2');
          }
        }
      }
    } catch (e) {
      _isOnline = false;
      debugPrint('⚠️ Connectivity check error: $e');
    }

    // Notify listeners
    _connectivityStreamController.add(_isOnline);

    // Trigger sync if went online
    if (!wasOnline && _isOnline) {
      debugPrint('🌐 Back online - triggering sync');
      _performFullSync();
    }
  }

  /// Start connectivity listener
  void _startConnectivityListener() {
    Connectivity().onConnectivityChanged.listen((result) {
       // Re-check actual connectivity when network state changes
       debugPrint('📡 Network state changed: $result');
       _checkConnectivity();
    });
  }

  /// Start periodic sync timer
  void _startPeriodicSync() {
    // Hafif güvenlik ağı: 60 sn'de bir sadece gerekli ise çalıştır
    _syncTimer = Timer.periodic(const Duration(seconds: 60), (timer) async {
      if (!_isOnline) return;
      if (_pendingSyncOperations.isNotEmpty) {
        await _performFullSync();
      } else if (_pullEnabled) {
        // Yalnızca açıkça izin verilirse uzak çekme yap
        await _pullFromFirebase();
      }
    });
  }

  void _scheduleImmediateSync() {
    if (_debounceSync?.isActive == true) {
      _debounceSync!.cancel();
    }

    // Prevent duplicate syncs
    if (_isSyncInProgress) {
      debugPrint('⚠️ Sync already in progress, skipping immediate sync');
      return;
    }

    _debounceSync = Timer(const Duration(milliseconds: 500), () {
      // Safety check to prevent crashes if service is disposed
      if (_syncTimer != null && !_isSyncInProgress) {
        _performFullSync();
      }
    });
  }

  /// Stop sync timer
  void dispose() {
    _syncTimer?.cancel();
    _debounceSync?.cancel();
    _connectivityStreamController.close();
    _syncTimer = null;
    _debounceSync = null;
    _isSyncInProgress = false;
    _pendingSyncOperations.clear();
  }

  // ==================== CUSTOMER OPERATIONS ====================

  Future<int> insertCustomer(Customer customer) async {
    try {
      final db = await database;
      final now = DateTime.now().toIso8601String();
      final currentUserId = await _getCurrentSQLiteUserId();

      debugPrint('🔍 Inserting customer with user ID: $currentUserId');

      if (currentUserId <= 0) {
        debugPrint('❌ Invalid user ID: $currentUserId');
        return -1;
      }

      final customerMap = customer.toMap();
      customerMap['created_at'] = now;
      customerMap['updated_at'] = now;
      customerMap['firebase_synced'] = 0;
      customerMap['user_id'] = currentUserId;

      final id = await db.insert('customers', customerMap);
      debugPrint('✅ Customer inserted with ID: $id');

      // Add to sync queue
      await _addToSyncLog('customers', id, 'INSERT');

      // Try to sync immediately if online
      if (_isOnline) {
        // Fire and forget - don't block the UI
        _syncCustomerToFirebase(id).catchError((error) {
          debugPrint('❌ Customer Firebase sync error: $error');
          // Don't crash the app - just log the error
        });
      }

      return id;
    } catch (e) {
      debugPrint('❌ Error inserting customer: $e');
      return -1;
    }
  }

  Future<List<Customer>> getAllCustomers({int? userId}) async {
    final db = await database;
    String whereClause = '';
    List<dynamic> whereArgs = [];

    if (userId != null) {
      whereClause = 'WHERE user_id = ?';
      whereArgs = [userId];
    }

    final List<Map<String, dynamic>> maps = await db.rawQuery(
      'SELECT * FROM customers $whereClause ORDER BY name',
      whereArgs,
    );

    return List.generate(maps.length, (i) {
      final convertedMap = IdConverter.convertSqliteMap(maps[i]);
      return Customer.fromMap(convertedMap);
    });
  }

  Future<Customer?> getCustomerById(int id) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'customers',
      where: 'id = ?',
      whereArgs: [id],
    );

    if (maps.isNotEmpty) {
      final convertedMap = IdConverter.convertSqliteMap(maps.first);
      return Customer.fromMap(convertedMap);
    }
    return null;
  }

  Future<int> updateCustomer(Customer customer) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();

    final customerMap = customer.toMap();
    customerMap['updated_at'] = now;
    customerMap['firebase_synced'] = 0;

    // SQLite id alanına Firebase ID'yi koyma - sadece firebase_id alanına koy
    customerMap.remove('id'); // id alanını kaldır

    int result;
    // Firebase ID varsa onu kullan, yoksa SQLite ID'yi kullan
    if (customer.id != null &&
        !IdConverter.isValidSQLiteId(IdConverter.stringToInt(customer.id))) {
      // Firebase ID kullanarak güncelle
      result = await db.update(
        'customers',
        customerMap,
        where: 'firebase_id = ?',
        whereArgs: [customer.id],
      );
    } else {
      // SQLite ID kullanarak güncelle
      final customerId = IdConverter.stringToInt(customer.id);
      if (customerId != null) {
        result = await db.update(
          'customers',
          customerMap,
          where: 'id = ?',
          whereArgs: [customerId],
        );
      } else {
        debugPrint('❌ Geçersiz customer ID: ${customer.id}');
        return 0;
      }
    }

    // Add to sync queue - güvenli ID dönüşümü
    final customerId = IdConverter.stringToInt(customer.id);
    if (customerId != null) {
      await _addToSyncLog('customers', customerId, 'UPDATE');

      // Try to sync immediately if online
      if (_isOnline) {
        // Fire and forget - don't block the UI
        _syncCustomerToFirebase(customerId).catchError((error) {
          debugPrint('❌ Customer update Firebase sync error: $error');
          // Don't crash the app - just log the error
        });
      }
    } else {
      debugPrint('❌ Geçersiz customer ID: ${customer.id}');
    }

    return result;
  }

  Future<int> deleteCustomer(int id) async {
    final db = await database;

    // Firebase id'yi çek
    String? firebaseId;
    final row = await db.query(
      'customers',
      columns: ['firebase_id'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (row.isNotEmpty) firebaseId = row.first['firebase_id'] as String?;

    // Add to sync log before deletion
    await _addToSyncLog('customers', id, 'DELETE');

    final result = await db.delete(
      'customers',
      where: 'id = ?',
      whereArgs: [id],
    );

    // Try to sync deletion if online; değilse tombstone
    if (_isOnline && firebaseId != null && firebaseId.isNotEmpty) {
      await _firebaseService.deleteCustomer(firebaseId);
    } else if (firebaseId != null && firebaseId.isNotEmpty) {
      await db.insert('deleted_records', {
        'table_name': 'customers',
        'firebase_id': firebaseId,
        'timestamp': DateTime.now().toIso8601String(),
        'synced': 0,
      });
    }

    return result;
  }

  // ==================== PRODUCT OPERATIONS ====================

  Future<int> insertProduct(Product product) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    final currentUserId = await _getCurrentSQLiteUserId();

    final productMap = product.toMap();
    productMap['created_at'] = now;
    productMap['updated_at'] = now;
    productMap['firebase_synced'] = 0;
    productMap['user_id'] = currentUserId;

    final id = await db.insert('products', productMap);

    await _addToSyncLog('products', id, 'INSERT');

    if (_isOnline) {
      // Fire and forget - don't block the UI
      _syncProductToFirebase(id).catchError((error) {
        debugPrint('❌ Product Firebase sync error: $error');
        // Don't crash the app - just log the error
      });
    }

    return id;
  }

  Future<List<Product>> getAllProducts({int? userId}) async {
    final db = await database;
    String whereClause = '';
    List<dynamic> whereArgs = [];

    if (userId != null) {
      whereClause = 'WHERE user_id = ?';
      whereArgs = [userId];
    }

    final List<Map<String, dynamic>> maps = await db.rawQuery(
      'SELECT * FROM products $whereClause ORDER BY name',
      whereArgs,
    );

    return List.generate(maps.length, (i) {
      final convertedMap = IdConverter.convertSqliteMap(maps[i]);
      return Product.fromMap(convertedMap);
    });
  }

  Future<Product?> getProductById(int id) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'products',
      where: 'id = ?',
      whereArgs: [id],
    );

    if (maps.isNotEmpty) {
      final convertedMap = IdConverter.convertSqliteMap(maps.first);
      return Product.fromMap(convertedMap);
    }
    return null;
  }

  Future<int> updateProduct(Product product) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();

    final productMap = product.toMap();
    productMap['updated_at'] = now;
    productMap['firebase_synced'] = 0;

    // SQLite id alanına Firebase ID'yi koyma - sadece firebase_id alanına koy
    productMap.remove('id'); // id alanını kaldır

    // UNIQUE (user_id, company_id, name) ihlallerinde fallback: farklı company_id için update
    Future<int> _doUpdateById(int id) async {
      return db.update(
        'products',
        productMap,
        where: 'id = ?',
        whereArgs: [id],
      );
    }

    int result = 0;
    try {
      if (product.id != null &&
          !IdConverter.isValidSQLiteId(IdConverter.stringToInt(product.id))) {
        // Firebase ID ile güncelle
        result = await db.update(
          'products',
          productMap,
          where: 'firebase_id = ?',
          whereArgs: [product.id],
        );
      } else {
        final productId = IdConverter.stringToInt(product.id);
        if (productId != null) {
          result = await _doUpdateById(productId);
        } else {
          debugPrint('❌ Geçersiz product ID: ${product.id}');
          return 0;
        }
      }
    } on DatabaseException catch (e) {
      // Unique hata: aynı kullanıcı + şirket + ad kombinasyonu
      if (e.isUniqueConstraintError()) {
        // Hedef kaydı bulup merge mantığına geçebiliriz; şimdilik kullanıcıya hata dön
        debugPrint('⚠ UNIQUE violation on products: ${e.toString()}');
        rethrow;
      } else {
        rethrow;
      }
    }

    // Add to sync queue - güvenli ID dönüşümü
    final productId = IdConverter.stringToInt(product.id);
    if (productId != null) {
      await _addToSyncLog('products', productId, 'UPDATE');

      if (_isOnline) {
        // Fire and forget - don't block the UI
        _syncProductToFirebase(productId).catchError((error) {
          debugPrint('❌ Product update Firebase sync error: $error');
          // Don't crash the app - just log the error
        });
      }
    } else {
      debugPrint('❌ Geçersiz product ID: ${product.id}');
    }

    return result;
  }

  Future<int> deleteProduct(int id) async {
    final db = await database;
    String? firebaseId;
    final row = await db.query(
      'products',
      columns: ['firebase_id'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (row.isNotEmpty) firebaseId = row.first['firebase_id'] as String?;

    await _addToSyncLog('products', id, 'DELETE');

    final result = await db.delete(
      'products',
      where: 'id = ?',
      whereArgs: [id],
    );

    if (_isOnline && firebaseId != null && firebaseId.isNotEmpty) {
      await _firebaseService.deleteProduct(firebaseId);
    } else if (firebaseId != null && firebaseId.isNotEmpty) {
      await db.insert('deleted_records', {
        'table_name': 'products',
        'firebase_id': firebaseId,
        'timestamp': DateTime.now().toIso8601String(),
        'synced': 0,
      });
    }

    return result;
  }

  /// Firebase ID ile ürünü sil (lokal + uzak)
  Future<int> deleteProductByFirebaseId(String firebaseId) async {
    final db = await database;
    // SQLite ID'yi bul
    final row = await db.query(
      'products',
      columns: ['id'],
      where: 'firebase_id = ?',
      whereArgs: [firebaseId],
      limit: 1,
    );
    if (row.isEmpty) {
      return 0;
    }
    final sqliteId = row.first['id'] as int;
    return deleteProduct(sqliteId);
  }

  // ==================== INVOICE OPERATIONS ====================

  Future<int> insertInvoice(Invoice invoice) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    final currentUserId = await _getCurrentSQLiteUserId();

    final invoiceMap = invoice.toMap();
    invoiceMap['created_at'] = now;
    invoiceMap['updated_at'] = now;
    invoiceMap['firebase_synced'] = 0;
    invoiceMap['user_id'] = currentUserId;

    final invoiceId = await db.insert('invoices', invoiceMap);

    // Kalemler
    for (var item in invoice.items) {
      final itemMap = item.toMap();
      itemMap['invoice_id'] = invoiceId;
      itemMap['created_at'] = now;
      itemMap['updated_at'] = now;
      itemMap['firebase_synced'] = 0;
      await db.insert('invoice_items', itemMap);
    }

    // Detay tabloların varlığını bir daha garanti et (idempotent)
    await _ensureInvoiceDetailTables();

    // UI'dan gelen seçimleri yakala (farklı alan adlarını tolere ediyoruz)
    try {
      final dynamic dyn = invoice;
      final List<dynamic>? selections =
          (dyn as dynamic).termSelections as List<dynamic>? ??
          (dyn as dynamic).details as List<dynamic>? ??
          (dyn as dynamic).extraTerms as List<dynamic>?;

      if (selections != null && selections.isNotEmpty) {
        await _insertInvoiceTermSelections(db, invoiceId, selections);
      }
    } catch (e) {
      debugPrint(
        '⚠️ Fatura detay seçimleri eklenemedi (fatura yine de kaydedildi): $e',
      );
    }

    await _addToSyncLog('invoices', invoiceId, 'INSERT');

    if (_isOnline) {
      // Fire and forget - don't block the UI
      _syncInvoiceToFirebase(invoiceId).catchError((error) {
        debugPrint('❌ Invoice Firebase sync error: $error');
        // Don't crash the app - just log the error
      });
    }

    return invoiceId;
  }

  Future<List<Invoice>> getAllInvoices({int? userId}) async {
    final db = await database;
    String whereClause = '';
    List<dynamic> whereArgs = [];

    if (userId != null) {
      whereClause = 'WHERE i.user_id = ?';
      whereArgs = [userId];
    }

    final List<Map<String, dynamic>> invoiceMaps = await db.rawQuery('''
    SELECT i.*, c.name as customer_name, c.email as customer_email
    FROM invoices i
    LEFT JOIN customers c ON i.customer_id = c.id
    $whereClause
    ORDER BY i.created_at DESC
  ''', whereArgs);

    List<Invoice> invoices = [];
    for (var invoiceMap in invoiceMaps) {
      final convertedMap = IdConverter.convertSqliteMap(invoiceMap);

      final customer = await getCustomerById(
        int.parse(convertedMap['customer_id']),
      );
      if (customer != null) {
        final items = await getInvoiceItemsByInvoiceId(
          int.parse(convertedMap['id']),
        );

        // ✅ Terms bilgisi ekleniyor
        final termsTexts = await getInvoiceTermsTextByInvoiceId(
          int.parse(convertedMap['id']),
        );
        if (termsTexts.isNotEmpty) {
          convertedMap['terms'] = termsTexts.join('\n');
        }

        invoices.add(Invoice.fromMap(convertedMap, customer, items));
      }
    }

    return invoices;
  }

  Future<List<InvoiceItem>> getInvoiceItemsByInvoiceId(int invoiceId) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'invoice_items',
      where: 'invoice_id = ?',
      whereArgs: [invoiceId],
    );

    List<InvoiceItem> items = [];
    for (var map in maps) {
      final convertedMap = IdConverter.convertSqliteMap(map);

      final product = await getProductById(
        int.parse(convertedMap['product_id']),
      );
      if (product != null) {
        items.add(InvoiceItem.fromMap(convertedMap, product));
      }
    }

    return items;
  }

  Future<List<String>> getInvoiceTermsTextByInvoiceId(int invoiceId) async {
    final db = await database;
    final rows = await db.query(
      'invoice_term_selections',
      columns: ['text'],
      where: 'invoice_id = ?',
      whereArgs: [invoiceId],
      orderBy: 'id ASC',
    );

    return rows
        .map((e) {
          final txt = (e['text'] as String?)?.trim() ?? '';
          if (txt.isEmpty) return '';

          // KDV veya Vade farkı gibi yüzdelik alanlarda otomatik % ekle
          if (RegExp(r'^\d+(\.\d+)?$').hasMatch(txt)) {
            return '%$txt';
          }
          return txt;
        })
        .where((t) => t.isNotEmpty)
        .toList();
  }

  // ==================== SYNC OPERATIONS ====================

  Future<void> _addToSyncLog(
    String tableName,
    int recordId,
    String operation,
  ) async {
    try {
      // Check if operation is already pending
      final operationKey = '$tableName:$recordId:$operation';
      if (_pendingSyncOperations.contains(operationKey)) {
        debugPrint('⚠️ Operation already pending: $operationKey');
        return;
      }

      final db = await database;
      await db.insert('sync_log', {
        'table_name': tableName,
        'record_id': recordId,
        'operation': operation,
        'timestamp': DateTime.now().toIso8601String(),
        'synced': 0,
      });

      _pendingSyncOperations.add(operationKey);
      debugPrint('📝 Added to sync log: $operationKey');

      // Değişiklik olduğunda otomatik senkronizasyonu tetikle (debounce)
      // Safety check to prevent crashes if service is disposed
      if (_syncTimer != null) {
        _scheduleImmediateSync();
      }
    } catch (e) {
      debugPrint('❌ Error adding to sync log: $e');
      // Don't crash the app - just log the error
    }
  }

  Future<void> _performFullSync() async {
    if (!_isOnline || _isSyncInProgress) {
      debugPrint(
        '⚠️ Sync skipped: online=$_isOnline, inProgress=$_isSyncInProgress',
      );
      return;
    }

    // Safety check to prevent crashes if service is disposed
    if (_syncTimer == null) {
      debugPrint('⚠️ Service disposed, skipping sync');
      return;
    }

    _isSyncInProgress = true;
    debugPrint('🔄 Starting full sync...');

    try {
      debugPrint('🔄 Step 1: Syncing pending operations...');
      await _syncPendingOperations();

      if (_pullEnabled) {
        debugPrint('🔄 Step 2: Pulling from Firebase...');
        await _pullFromFirebase();
      }

      debugPrint('✅ Full sync completed successfully');
    } catch (e) {
      debugPrint('❌ Full sync error: $e');
      // Don't crash the app, just log the error
    } finally {
      _isSyncInProgress = false;
      debugPrint('🔄 Sync status reset: inProgress=false');
    }
  }

  /// Firebase'den çekmeyi (import) aç/kapat (varsayılan: kapalı)
  void setPullEnabled(bool enabled) {
    _pullEnabled = enabled;
  }

  Future<void> _syncPendingOperations() async {
    final db = await database;
    final pendingOps = await db.query(
      'sync_log',
      where: 'synced = 0',
      orderBy: 'timestamp ASC',
    );

    if (pendingOps.isEmpty) {
      debugPrint('📝 No pending sync operations found in sync_log table');

      // Check if we need to create sync operations for existing unsynced records
      debugPrint(
        '🔍 Checking for unsynced records that need sync operations...',
      );

      final unsyncedCustomers = await db.rawQuery(
        'SELECT COUNT(*) as count FROM customers WHERE firebase_synced = 0',
      );
      final unsyncedProducts = await db.rawQuery(
        'SELECT COUNT(*) as count FROM products WHERE firebase_synced = 0',
      );
      final unsyncedInvoices = await db.rawQuery(
        'SELECT COUNT(*) as count FROM invoices WHERE firebase_synced = 0',
      );

      final totalUnsynced =
          (unsyncedCustomers.first['count'] as int) +
          (unsyncedProducts.first['count'] as int) +
          (unsyncedInvoices.first['count'] as int);

      if (totalUnsynced > 0) {
        debugPrint(
          '📝 Found $totalUnsynced unsynced records, creating sync operations...',
        );

        // Create sync operations for unsynced records
        await _createSyncOperationsForUnsyncedRecords();
      } else {
        debugPrint('✅ All records are already synced');
      }

      return;
    }

    debugPrint('🔄 Processing ${pendingOps.length} pending sync operations...');

    for (var op in pendingOps) {
      try {
        final operationKey =
            '${op['table_name']}:${op['record_id']}:${op['operation']}';
        debugPrint('🔄 Processing: $operationKey');

        await _processSyncOperation(op);

        // Mark as synced
        await db.update(
          'sync_log',
          {'synced': 1},
          where: 'id = ?',
          whereArgs: [op['id']],
        );

        debugPrint('✅ Operation synced: $operationKey');
      } catch (e) {
        debugPrint('❌ Error processing operation ${op['id']}: $e');
        // Continue with next operation
      }
    }
  }

  Future<void> _processSyncOperation(Map<String, dynamic> operation) async {
    final tableName = operation['table_name'];
    final recordId = operation['record_id'];
    final operationType = operation['operation'];

    switch (tableName) {
      case 'customers':
        if (operationType == 'INSERT' || operationType == 'UPDATE') {
          await _syncCustomerToFirebase(recordId);
        } else if (operationType == 'DELETE') {
          await _syncCustomerDeletionToFirebase(recordId);
        }
        break;
      case 'products':
        if (operationType == 'INSERT' || operationType == 'UPDATE') {
          await _syncProductToFirebase(recordId);
        } else if (operationType == 'DELETE') {
          await _syncProductDeletionToFirebase(recordId);
        }
        break;
      case 'invoices':
        if (operationType == 'INSERT' || operationType == 'UPDATE') {
          await _syncInvoiceToFirebase(recordId);
        } else if (operationType == 'DELETE') {
          await _syncInvoiceDeletionToFirebase(recordId);
        }
        break;
    }
  }

  // Firebase sync methods
  Future<void> _syncCustomerToFirebase(int customerId) async {
    try {
      final customer = await getCustomerById(customerId);
      if (customer != null) {
        final db = await database;

        // Check if this Firebase ID already exists in another record
        String? firebaseId = customer.firebaseId;

        if (firebaseId == null || firebaseId.isEmpty) {
          // Try to find existing customer by email/phone/name
          firebaseId = await _firebaseService.findExistingCustomerId(
            email: customer.email,
            phone: customer.phone,
            taxNumber: customer.taxNumber,
            name: customer.name,
          );

          if (firebaseId == null) {
            // Create new customer in Firebase
            firebaseId = await _firebaseService.addCustomer(customer);
          }
        }

        if (firebaseId != null && firebaseId.isNotEmpty) {
          // Check if this Firebase ID already exists in another record
          final existingRecord = await db.query(
            'customers',
            where: 'firebase_id = ? AND id != ?',
            whereArgs: [firebaseId, customerId],
          );

          if (existingRecord.isNotEmpty) {
            // Merge records - update the existing record with current data
            debugPrint(
              '🔄 Merging duplicate customer records for Firebase ID: $firebaseId',
            );

            final existingId = existingRecord.first['id'] as int;
            final customerMap = customer.toMap();
            customerMap.remove('id');
            customerMap['firebase_id'] = firebaseId;
            customerMap['firebase_synced'] = 1;
            customerMap['last_sync_time'] = DateTime.now().toIso8601String();

            // Update the existing record
            await db.update(
              'customers',
              customerMap,
              where: 'id = ?',
              whereArgs: [existingId],
            );

            // Delete the duplicate record
            await db.delete(
              'customers',
              where: 'id = ?',
              whereArgs: [customerId],
            );

            debugPrint('✅ Customer records merged successfully');
          } else {
            // Update current record with Firebase ID
            await db.update(
              'customers',
              {
                'firebase_id': firebaseId,
                'firebase_synced': 1,
                'last_sync_time': DateTime.now().toIso8601String(),
              },
              where: 'id = ?',
              whereArgs: [customerId],
            );

            debugPrint('✅ Customer synced to Firebase: $firebaseId');
          }
        }
      }
    } catch (e) {
      debugPrint('❌ Error syncing customer to Firebase: $e');
      // Don't crash the app, just log the error
    }
  }

  Future<void> _insertInvoiceTermSelections(
    Database db,
    int invoiceId,
    List<dynamic> selections,
  ) async {
    if (selections.isEmpty) return;

    for (final s in selections) {
      int? termId;
      double? value;
      String? text;

      if (s is Map) {
        termId = (s['termId'] ?? s['term_id']) as int?;
        value = (s['value'] as num?)?.toDouble();
        text = (s['text'] ?? s['body'] ?? s['rendered'])?.toString();
      } else {
        try {
          termId = (s as dynamic).termId as int?;
          value = ((s as dynamic).value as num?)?.toDouble();
          text = (s as dynamic).text?.toString();
        } catch (_) {}
      }

      if (termId == null) continue;

      final safeText = (text == null || text.trim().isEmpty) ? '' : text.trim();

      await db.insert('invoice_term_selections', {
        'invoice_id': invoiceId,
        'term_id': termId,
        'value': value,
        'text': safeText, // NOT NULL kolonu
      });
    }
  }

  Future<void> _syncCustomerDeletionToFirebase(int customerId) async {
    try {
      final db = await database;
      final customer = await db.query(
        'customers',
        columns: ['firebase_id'],
        where: 'id = ?',
        whereArgs: [customerId],
      );

      if (customer.isNotEmpty && customer.first['firebase_id'] != null) {
        final firebaseId = customer.first['firebase_id'] as String;
        await _firebaseService.deleteCustomer(firebaseId);
        debugPrint(
          '✅ Müşteri silme Firebase\'e senkronize edildi: $firebaseId',
        );
      }
    } catch (e) {
      debugPrint('❌ Müşteri silme senkronizasyon hatası: $e');
      ErrorHandler.handleSyncError('Customer Deletion Sync', e);
    }
  }

  Future<void> _syncProductToFirebase(int productId) async {
    debugPrint('🔄 _syncProductToFirebase called for product ID: $productId');
    try {
      final product = await getProductById(productId);
      if (product != null) {
        debugPrint('📦 Product found: ${product.name} (ID: ${product.id})');
        final db = await database;

        // Check if this Firebase ID already exists in another record
        String? firebaseId = product.id;
        debugPrint('🔍 Current Firebase ID: $firebaseId');

        if (firebaseId == null ||
            firebaseId.isEmpty ||
            IdConverter.isValidSQLiteId(IdConverter.stringToInt(firebaseId))) {
          debugPrint(
            '🔄 Product needs new Firebase ID, searching for existing...',
          );
          // Try to find existing product by name and company
          firebaseId = await _firebaseService.findExistingProductId(
            name: product.name,
            companyId: product.companyId,
          );

          if (firebaseId == null) {
            debugPrint(
              '🆕 No existing product found, creating new in Firebase...',
            );
            // Create new product in Firebase
            firebaseId = await _firebaseService.addProduct(product);
            debugPrint('✅ Product created in Firebase with ID: $firebaseId');
          } else {
            debugPrint(
              '🔍 Existing product found in Firebase with ID: $firebaseId',
            );
          }
        }

        if (firebaseId != null && firebaseId.isNotEmpty) {
          debugPrint('🔄 Processing Firebase ID: $firebaseId');
          // Check if this Firebase ID already exists in another record
          final existingRecord = await db.query(
            'products',
            where: 'firebase_id = ? AND id != ?',
            whereArgs: [firebaseId, productId],
          );

          if (existingRecord.isNotEmpty) {
            // Merge records - update the existing record with current data
            debugPrint(
              '🔄 Merging duplicate product records for Firebase ID: $firebaseId',
            );

            final existingId = existingRecord.first['id'] as int;
            final productMap = product.toMap();
            productMap.remove('id');
            productMap['firebase_id'] = firebaseId;
            productMap['firebase_synced'] = 1;
            productMap['last_sync_time'] = DateTime.now().toIso8601String();

            // Update the existing record
            await db.update(
              'products',
              productMap,
              where: 'id = ?',
              whereArgs: [existingId],
            );

            // Delete the duplicate record
            await db.delete(
              'products',
              where: 'id = ?',
              whereArgs: [productId],
            );

            debugPrint('✅ Product records merged successfully');
          } else {
            // Update current record with Firebase ID
            debugPrint('🔄 Updating product with Firebase ID: $firebaseId');
            await db.update(
              'products',
              {
                'firebase_id': firebaseId,
                'firebase_synced': 1,
                'last_sync_time': DateTime.now().toIso8601String(),
              },
              where: 'id = ?',
              whereArgs: [productId],
            );

            debugPrint('✅ Product synced to Firebase: $firebaseId');
          }
        } else {
          debugPrint('❌ Failed to get Firebase ID for product');
        }
      } else {
        debugPrint('❌ Product not found for ID: $productId');
      }
    } catch (e) {
      debugPrint('❌ Error syncing product to Firebase: $e');
      // Don't crash the app, just log the error
    }
  }

  Future<void> _syncProductDeletionToFirebase(int productId) async {
    try {
      final db = await database;
      final product = await db.query(
        'products',
        columns: ['firebase_id'],
        where: 'id = ?',
        whereArgs: [productId],
      );

      if (product.isNotEmpty && product.first['firebase_id'] != null) {
        final firebaseId = product.first['firebase_id'] as String;
        await _firebaseService.deleteProduct(firebaseId);
        debugPrint('✅ Ürün silme Firebase\'e senkronize edildi: $firebaseId');
      }
    } catch (e) {
      debugPrint('❌ Ürün silme senkronizasyon hatası: $e');
      ErrorHandler.handleSyncError('Product Deletion Sync', e);
    }
  }

  Future<void> _syncInvoiceToFirebase(int invoiceId) async {
    try {
      final invoices = await getAllInvoices();
      final invoice = invoices.firstWhere(
        (i) => i.id == invoiceId.toString(),
        orElse: () => throw Exception('Invoice not found'),
      );

      final db = await database;

      // Check if this Firebase ID already exists in another record
      String? firebaseId = invoice.id;

      if (firebaseId == null ||
          firebaseId.isEmpty ||
          IdConverter.isValidSQLiteId(IdConverter.stringToInt(firebaseId))) {
        // Try to find existing invoice by invoice number
        firebaseId = await _firebaseService.findExistingInvoiceId(
          invoiceNumber: invoice.invoiceNumber,
        );

        if (firebaseId == null) {
          // Create new invoice in Firebase
          firebaseId = await _firebaseService.addInvoice(invoice);
        }
      }

      if (firebaseId != null && firebaseId.isNotEmpty) {
        // Check if this Firebase ID already exists in another record
        final existingRecord = await db.query(
          'invoices',
          where: 'firebase_id = ? AND id != ?',
          whereArgs: [firebaseId, invoiceId],
        );

        if (existingRecord.isNotEmpty) {
          // Merge records - update the existing record with current data
          debugPrint(
            '🔄 Merging duplicate invoice records for Firebase ID: $firebaseId',
          );

          final existingId = existingRecord.first['id'] as int;
          final invoiceMap = invoice.toMap();
          invoiceMap.remove('id');
          invoiceMap['firebase_id'] = firebaseId;
          invoiceMap['firebase_synced'] = 1;
          invoiceMap['last_sync_time'] = DateTime.now().toIso8601String();

          // Update the existing record
          await db.update(
            'invoices',
            invoiceMap,
            where: 'id = ?',
            whereArgs: [existingId],
          );

          // Delete the duplicate record
          await db.delete('invoices', where: 'id = ?', whereArgs: [invoiceId]);

          debugPrint('✅ Invoice records merged successfully');
        } else {
          // Update current record with Firebase ID
          await db.update(
            'invoices',
            {
              'firebase_id': firebaseId,
              'firebase_synced': 1,
              'last_sync_time': DateTime.now().toIso8601String(),
            },
            where: 'id = ?',
            whereArgs: [invoiceId],
          );

          debugPrint('✅ Invoice synced to Firebase: $firebaseId');
        }
      }
    } catch (e) {
      debugPrint('❌ Error syncing invoice to Firebase: $e');
      // Don't crash the app, just log the error
    }
  }

  Future<void> _syncInvoiceDeletionToFirebase(int invoiceId) async {
    try {
      final db = await database;
      final invoice = await db.query(
        'invoices',
        columns: ['firebase_id'],
        where: 'id = ?',
        whereArgs: [invoiceId],
      );

      if (invoice.isNotEmpty && invoice.first['firebase_id'] != null) {
        final firebaseId = invoice.first['firebase_id'] as String;
        await _firebaseService.deleteInvoice(firebaseId);
        debugPrint('✅ Fatura silme Firebase\'e senkronize edildi: $firebaseId');
      }
    } catch (e) {
      debugPrint('❌ Fatura silme senkronizasyon hatası: $e');
      ErrorHandler.handleSyncError('Invoice Deletion Sync', e);
    }
  }

  Future<void> _pullFromFirebase() async {
    try {
      // Pull customers from Firebase
      final firebaseCustomers = await _firebaseService.getCustomers();
      await _mergeFirebaseCustomers(firebaseCustomers);

      // Pull products from Firebase
      final firebaseProducts = await _firebaseService.getProducts();
      await _mergeFirebaseProducts(firebaseProducts);

      // Pull invoices from Firebase
      final firebaseInvoices = await _firebaseService.getInvoices();
      await _mergeFirebaseInvoices(firebaseInvoices);
    } catch (e) {
      // Log error silently - avoid print in production
      debugPrint('Pull from Firebase error: $e');
    }
  }

  Future<void> _mergeFirebaseCustomers(List<Customer> firebaseCustomers) async {
    final db = await database;

    // Mevcut kullanıcının SQLite ID'sini al
    final currentUserId = await _getCurrentSQLiteUserId();

    for (var customer in firebaseCustomers) {
      // 1) Doğal anahtar: user_id + email
      final byEmail = (customer.email ?? '').isNotEmpty
          ? await db.query(
              'customers',
              where: 'user_id = ? AND email = ?',
              whereArgs: [currentUserId, customer.email],
              limit: 1,
            )
          : <Map<String, dynamic>>[];
      // 2) Firebase id
      final byFid = await db.query(
        'customers',
        where: 'firebase_id = ?',
        whereArgs: [customer.id.toString()],
        limit: 1,
      );

      final customerMap = customer.toMap();
      // SQLite id alanına Firebase ID'yi koyma - sadece firebase_id alanına koy
      customerMap.remove('id'); // id alanını kaldır
      customerMap['firebase_id'] = customer.id.toString();
      customerMap['firebase_synced'] = 1;
      customerMap['last_sync_time'] = DateTime.now().toIso8601String();
      // Mevcut kullanıcının ID'sini ekle
      customerMap['user_id'] = currentUserId;

      if (byEmail.isEmpty && byFid.isEmpty) {
        // Firebase_id ile eşleşmedi, doğal anahtarlarla eşleştirmeyi dene
        Map<String, dynamic>? match;
        if ((customer.email ?? '').isNotEmpty) {
          final rows = await db.query(
            'customers',
            where:
                'user_id = ? AND email = ? AND (firebase_id IS NULL OR firebase_id = "")',
            whereArgs: [currentUserId, customer.email],
            limit: 1,
          );
          if (rows.isNotEmpty) match = rows.first;
        }
        if (match == null && (customer.phone ?? '').isNotEmpty) {
          final rows = await db.query(
            'customers',
            where:
                'user_id = ? AND phone = ? AND (firebase_id IS NULL OR firebase_id = "")',
            whereArgs: [currentUserId, customer.phone],
            limit: 1,
          );
          if (rows.isNotEmpty) match = rows.first;
        }
        if (match == null && (customer.taxNumber ?? '').isNotEmpty) {
          final rows = await db.query(
            'customers',
            where:
                'user_id = ? AND tax_number = ? AND (firebase_id IS NULL OR firebase_id = "")',
            whereArgs: [currentUserId, customer.taxNumber],
            limit: 1,
          );
          if (rows.isNotEmpty) match = rows.first;
        }

        if (match == null) {
          final rows = await db.query(
            'customers',
            where:
                'user_id = ? AND LOWER(name) = LOWER(?) AND (firebase_id IS NULL OR firebase_id = "")',
            whereArgs: [currentUserId, customer.name],
            limit: 1,
          );
          if (rows.isNotEmpty) match = rows.first;
        }

        if (match != null) {
          // Elde var olan kaydı güncelle (firebase_id bağla)
          await db.update(
            'customers',
            customerMap,
            where: 'id = ?',
            whereArgs: [match['id']],
          );
          debugPrint(
            '✅ Müşteri SQLite\'da eşleşti ve güncellendi: ${customer.name}',
          );
        } else {
          // Insert new customer
          await db.insert('customers', customerMap);
          debugPrint('✅ Müşteri SQLite\'a eklendi: ${customer.name}');
        }
      } else {
        final target = byEmail.isNotEmpty ? byEmail.first : byFid.first;
        await db.update(
          'customers',
          customerMap,
          where: 'id = ?',
          whereArgs: [target['id']],
        );
        debugPrint('✅ Müşteri SQLite\'da güncellendi: ${customer.name}');
      }
    }
  }

  Future<void> _mergeFirebaseProducts(List<Product> firebaseProducts) async {
    final db = await database;

    // Mevcut kullanıcının SQLite ID'sini al
    final currentUserId = await _getCurrentSQLiteUserId();

    for (var product in firebaseProducts) {
      final existing = await db.query(
        'products',
        where: 'firebase_id = ?',
        whereArgs: [product.id.toString()],
      );

      final productMap = product.toMap();
      // SQLite id alanına Firebase ID'yi koyma - sadece firebase_id alanına koy
      productMap.remove('id'); // id alanını kaldır
      productMap['firebase_id'] = product.id.toString();
      productMap['firebase_synced'] = 1;
      productMap['last_sync_time'] = DateTime.now().toIso8601String();
      // Mevcut kullanıcının ID'sini ekle
      productMap['user_id'] = currentUserId;
      // Şirket ID'sini ekle (varsa)
      if ((product.companyId ?? '').isNotEmpty) {
        productMap['company_id'] = product.companyId;
      }

      if (existing.isEmpty) {
        // Doğal anahtar eşleşmesi dene (barcode veya name+user)
        Map<String, dynamic>? match;
        if ((product.barcode ?? '').isNotEmpty) {
          final rows = await db.query(
            'products',
            where:
                'user_id = ? AND company_id ${product.companyId == null ? 'IS NULL' : '= ?'} AND barcode = ? AND (firebase_id IS NULL OR firebase_id = "")',
            whereArgs: product.companyId == null
                ? [currentUserId, product.barcode]
                : [currentUserId, product.companyId, product.barcode],
            limit: 1,
          );
          if (rows.isNotEmpty) match = rows.first;
        }
        if (match == null) {
          final rows = await db.query(
            'products',
            where:
                'user_id = ? AND company_id ${product.companyId == null ? 'IS NULL' : '= ?'} AND LOWER(name) = LOWER(?) AND (firebase_id IS NULL OR firebase_id = "")',
            whereArgs: product.companyId == null
                ? [currentUserId, product.name]
                : [currentUserId, product.companyId, product.name],
            limit: 1,
          );
          if (rows.isNotEmpty) match = rows.first;
        }

        if (match != null) {
          await db.update(
            'products',
            productMap,
            where: 'id = ?',
            whereArgs: [match['id']],
          );
          debugPrint(
            '✅ Ürün SQLite\'da eşleşti ve güncellendi: ${product.name}',
          );
        } else {
          try {
            await db.insert('products', productMap);
            debugPrint('✅ Ürün SQLite\'a eklendi: ${product.name}');
          } catch (e) {
            debugPrint('⚠ Ürün insert unique hatası, güncelleme deneniyor: $e');
            // Unique constraint tetiklendiyse, en yakın eşleşmeyi güncellemeyi dene
            await db.update(
              'products',
              productMap,
              where:
                  'user_id = ? AND company_id ${product.companyId == null ? 'IS NULL' : '= ?'} AND LOWER(name) = LOWER(?)',
              whereArgs: product.companyId == null
                  ? [currentUserId, product.name]
                  : [currentUserId, product.companyId, product.name],
            );
          }
        }
      } else {
        await db.update(
          'products',
          productMap,
          where: 'firebase_id = ?',
          whereArgs: [product.id.toString()],
        );
        debugPrint('✅ Ürün SQLite\'da güncellendi: ${product.name}');
      }
    }
  }

  Future<void> _mergeFirebaseInvoices(List<Invoice> firebaseInvoices) async {
    final db = await database;

    // Mevcut kullanıcının SQLite ID'sini al
    final currentUserId = await _getCurrentSQLiteUserId();

    for (var invoice in firebaseInvoices) {
      // 1) Önce user_id + invoice_number ile birebir eşleşme ara (en güvenli doğal anahtar)
      final existingByNumber = await db.query(
        'invoices',
        where: 'user_id = ? AND invoice_number = ?',
        whereArgs: [currentUserId, invoice.invoiceNumber],
        limit: 1,
      );
      // 2) Ardından firebase_id ile eşleşme dene
      final existingByFirebase = await db.query(
        'invoices',
        where: 'firebase_id = ?',
        whereArgs: [invoice.id.toString()],
        limit: 1,
      );

      final invoiceMap = invoice.toMap();
      // SQLite id alanına Firebase ID'yi koyma - sadece firebase_id alanına koy
      invoiceMap.remove('id'); // id alanını kaldır
      invoiceMap['firebase_id'] = invoice.id.toString();
      invoiceMap['firebase_synced'] = 1;
      invoiceMap['last_sync_time'] = DateTime.now().toIso8601String();
      // Mevcut kullanıcının ID'sini ekle
      invoiceMap['user_id'] = currentUserId;

      if (existingByNumber.isEmpty && existingByFirebase.isEmpty) {
        // Doğal anahtar eşleşmesi dene (fatura numarası)
        Map<String, dynamic>? match;
        if (existingByNumber.isNotEmpty) match = existingByNumber.first;

        int invoiceId;
        if (match != null) {
          await db.update(
            'invoices',
            invoiceMap,
            where: 'id = ?',
            whereArgs: [match['id']],
          );
          invoiceId = match['id'] as int;
          debugPrint(
            '✅ Fatura SQLite\'da eşleşti ve güncellendi: ${invoice.invoiceNumber}',
          );
        } else {
          invoiceId = await db.insert('invoices', invoiceMap);
          debugPrint('✅ Fatura SQLite\'a eklendi: ${invoice.invoiceNumber}');
        }

        // Insert invoice items
        for (var item in invoice.items) {
          final itemMap = item.toMap();
          // SQLite id alanına Firebase ID'yi koyma - sadece firebase_id alanına koy
          itemMap.remove('id'); // id alanını kaldır
          itemMap['invoice_id'] = invoiceId;
          itemMap['firebase_synced'] = 1;
          itemMap['last_sync_time'] = DateTime.now().toIso8601String();
          await db.insert('invoice_items', itemMap);
        }
      } else {
        // Hangisi bulunduysa onu güncelle
        final target = existingByNumber.isNotEmpty
            ? existingByNumber.first
            : existingByFirebase.first;
        await db.update(
          'invoices',
          invoiceMap,
          where: 'id = ?',
          whereArgs: [target['id']],
        );
        debugPrint('✅ Fatura SQLite\'da güncellendi: ${invoice.invoiceNumber}');
      }
    }
  }

  /// Manual sync trigger
  Future<void> performManualSync() async {
    await _performFullSync();
  }

  /// Mevcut kullanıcının SQLite (lokal) ID'sini dışarıya açan yardımcı metod
  Future<int> getCurrentLocalUserId() async {
    return _getCurrentSQLiteUserId();
  }

  /// Mevcut kullanıcının SQLite ID'sini al
  Future<int> _getCurrentSQLiteUserId() async {
    try {
      final db = await database;
      final currentUser = _firebaseService.currentUser;

      if (currentUser == null) {
        debugPrint('⚠️ No Firebase user, returning default user ID');
        return 1; // Default user ID
      }

      // Firebase UID'sine göre SQLite'daki user ID'yi bul
      final result = await db.query(
        'users',
        where: 'firebase_id = ?',
        whereArgs: [currentUser.uid],
        limit: 1,
      );

      if (result.isNotEmpty) {
        final userId = result.first['id'] as int;
        debugPrint('✅ Found existing user ID: $userId');
        return userId;
      }

      // Kullanıcı yoksa oluştur - Firestore'dan ek bilgileri çek
      String? phoneNumber;
      try {
        final userDoc = await _firebaseService.firestore
            .collection('users')
            .doc(currentUser.uid)
            .get();
        if (userDoc.exists) {
          phoneNumber = userDoc.data()?['phone'] as String?;
        }
      } catch (e) {
        debugPrint('Firestore kullanıcı bilgisi çekme hatası: $e');
      }

      final userId = await db.insert('users', {
        'firebase_id': currentUser.uid,
        'username': currentUser.email ?? 'user',
        'email': currentUser.email ?? '',
        'password_hash': '',
        'full_name': currentUser.displayName ?? '',
        'phone': phoneNumber,
        'is_active': 1,
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
        'firebase_synced': 1,
        'last_sync_time': DateTime.now().toIso8601String(),
      });

      debugPrint('✅ Yeni kullanıcı SQLite\'a eklendi: ID $userId');
      return userId;
    } catch (e) {
      debugPrint('❌ Error getting current SQLite user ID: $e');
      // Return default user ID to prevent crashes
      return 1;
    }
  }

  /// Get sync statistics
  Future<Map<String, int>> getSyncStats() async {
    final db = await database;

    final unsyncedCustomers = await db.rawQuery(
      'SELECT COUNT(*) as count FROM customers WHERE firebase_synced = 0',
    );
    final unsyncedProducts = await db.rawQuery(
      'SELECT COUNT(*) as count FROM products WHERE firebase_synced = 0',
    );
    final unsyncedInvoices = await db.rawQuery(
      'SELECT COUNT(*) as count FROM invoices WHERE firebase_synced = 0',
    );
    final pendingOperations = await db.rawQuery(
      'SELECT COUNT(*) as count FROM sync_log WHERE synced = 0',
    );

    return {
      'unsynced_customers': unsyncedCustomers.first['count'] as int,
      'unsynced_products': unsyncedProducts.first['count'] as int,
      'unsynced_invoices': unsyncedInvoices.first['count'] as int,
      'pending_operations': pendingOperations.first['count'] as int,
    };
  }

  /// Check synchronization health and status
  Future<Map<String, dynamic>> getSyncHealth() async {
    final stats = await getSyncStats();
    final totalPending = stats.values.reduce((a, b) => a + b);

    return {
      'is_online': _isOnline,
      'is_sync_in_progress': _isSyncInProgress,
      'sync_timer_active': _syncTimer?.isActive ?? false,
      'debounce_sync_active': _debounceSync?.isActive ?? false,
      'pending_operations_count': _pendingSyncOperations.length,
      'total_unsynced_records': totalPending,
      'stats': stats,
      'last_sync_time': DateTime.now().toIso8601String(),
    };
  }

  /// Force cleanup of pending operations
  Future<void> cleanupPendingOperations() async {
    debugPrint('🧹 Cleaning up pending sync operations...');
    _pendingSyncOperations.clear();

    final db = await database;
    await db.update('sync_log', {
      'synced': 1,
      'error_message': 'Cleaned up by user',
    }, where: 'synced = 0');

    debugPrint('✅ Pending operations cleaned up');
  }

  // ==================== MISSING METHODS ====================
  // ==================== COMPANY PROFILES (LOCAL FIRST) ====================

  Future<int> insertCompanyProfile(CompanyInfo company) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    final localUserId = await _getCurrentSQLiteUserId();

    final map = <String, Object?>{
      'firebase_id': company.firebaseId,
      'user_id': localUserId,
      'name': company.name,
      'address': company.address,
      'phone': company.phone,
      'email': company.email,
      'website': company.website,
      'tax_number': company.taxNumber,
      'logo': company.logo,
      'created_at': now,
      'updated_at': now,
      'firebase_synced': 0,
      'last_sync_time': null,
    };

    final id = await db.insert('company_info', map);

    // Push to Firebase if online (fire-and-forget)
    if (_isOnline) {
      try {
        final fbId = await _firebaseService.addCompanyProfile(
          CompanyInfo(
            id: id,
            firebaseId: null,
            userId: _firebaseService.currentUser?.uid,
            name: company.name,
            address: company.address,
            phone: company.phone,
            email: company.email,
            website: company.website,
            taxNumber: company.taxNumber,
            logo: company.logo,
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ),
        );
        if (fbId != null) {
          await db.update(
            'company_info',
            {
              'firebase_id': fbId,
              'firebase_synced': 1,
              'last_sync_time': DateTime.now().toIso8601String(),
            },
            where: 'id = ?',
            whereArgs: [id],
          );
        }
      } catch (e) {
        debugPrint('❌ Company push error: $e');
      }
    }

    return id;
  }

  Future<List<CompanyInfo>> getAllCompanyProfiles({int? userId}) async {
    final db = await database;
    final where = userId != null ? 'user_id = ?' : null;
    final args = userId != null ? [userId] : null;
    final rows = await db.query(
      'company_info',
      where: where,
      whereArgs: args,
      orderBy: 'created_at DESC',
    );
    return rows.map((e) => CompanyInfo.fromMap(e)).toList();
  }

  Future<int> updateCompanyProfileLocal(CompanyInfo company) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    final map = company.toMap()
      ..remove('id')
      ..['updated_at'] = now
      ..['firebase_synced'] = 0;
    return db.update(
      'company_info',
      map,
      where: 'id = ?',
      whereArgs: [company.id],
    );
  }

  Future<int> deleteCompanyProfileLocal(int id) async {
    final db = await database;
    return db.delete('company_info', where: 'id = ?', whereArgs: [id]);
  }

  /// Delete company profile by firebase_id (local)
  Future<int> deleteCompanyProfileByFirebaseId(String firebaseId) async {
    final db = await database;
    return db.delete(
      'company_info',
      where: 'firebase_id = ?',
      whereArgs: [firebaseId],
    );
  }

  /// Set products.company_id = NULL for a deleted company to preserve products
  Future<int> nullifyProductsCompany(String firebaseCompanyId) async {
    final db = await database;
    return db.update(
      'products',
      {
        'company_id': null,
        'updated_at': DateTime.now().toIso8601String(),
        'firebase_synced': 0,
      },
      where: 'company_id = ?',
      whereArgs: [firebaseCompanyId],
    );
  }

  /// Update invoice (items + term selections)
  Future<int> updateInvoice(Invoice invoice) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();

    final invoiceMap = invoice.toMap();
    invoiceMap['updated_at'] = now;
    invoiceMap['firebase_synced'] = 0;
    invoiceMap.remove('id'); // id alanını kaldır

    int result;

    if (invoice.id != null &&
        !IdConverter.isValidSQLiteId(IdConverter.stringToInt(invoice.id))) {
      // Firebase ID ile güncelle
      result = await db.update(
        'invoices',
        invoiceMap,
        where: 'firebase_id = ?',
        whereArgs: [invoice.id],
      );
    } else {
      // SQLite ID ile güncelle
      final invoiceIdInt = IdConverter.stringToInt(invoice.id);
      if (invoiceIdInt == null) {
        debugPrint('❌ Geçersiz invoice ID: ${invoice.id}');
        return 0;
      }

      result = await db.update(
        'invoices',
        invoiceMap,
        where: 'id = ?',
        whereArgs: [invoiceIdInt],
      );

      // === Term selections güncelleme ===
      try {
        await _ensureInvoiceDetailTables();

        final dynamic dyn = invoice;
        final List<dynamic>? selections =
            (dyn as dynamic).termSelections as List<dynamic>? ??
            (dyn as dynamic).details as List<dynamic>? ??
            (dyn as dynamic).extraTerms as List<dynamic>?;

        if (selections != null) {
          for (final s in selections) {
            int? termId;
            double? value;
            String? text;

            if (s is Map) {
              termId = (s['termId'] ?? s['term_id']) as int?;
              value = (s['value'] as num?)?.toDouble();
              text = (s['text'] ?? s['body'] ?? s['rendered'])?.toString();
            } else {
              try {
                termId = (s as dynamic).termId as int?;
                value = ((s as dynamic).value as num?)?.toDouble();
                text = (s as dynamic).text?.toString();
              } catch (_) {}
            }

            if (termId == null) continue;

            final safeText = (text == null || text.trim().isEmpty)
                ? ''
                : text.trim();

            await db.insert('invoice_term_selections', {
              'invoice_id': invoiceIdInt,
              'term_id': termId,
              'value': value,
              'text': safeText,
            });
            // value alanını da güncelle (saveInvoiceTermSelection sadece text yazıyorsa)
            await db.update(
              'invoice_term_selections',
              {'value': value},
              where: 'invoice_id = ? AND term_id = ?',
              whereArgs: [invoiceIdInt, termId],
            );
          }
        }
      } catch (e) {
        debugPrint('⚠️ Fatura detay seçimleri güncellenemedi: $e');
      }

      // Sync log
      await _addToSyncLog('invoices', invoiceIdInt, 'UPDATE');
      if (_isOnline) {
        _syncInvoiceToFirebase(invoiceIdInt).catchError((error) {
          debugPrint('❌ Invoice update Firebase sync error: $error');
          // Don't crash the app - just log the error
        });
      }
    }

    return result;
  }

  Future<Map<String, dynamic>> runMaintenance() async {
    final db = await database;
    return await DatabaseMaintenance.runFullMaintenance(db);
  }

  Future<Map<String, dynamic>> runValidation() async {
    final db = await database;
    return await DatabaseValidator.runFullValidation(db);
  }

  Future<int> deleteInvoice(int id) async {
    final db = await database;

    await _addToSyncLog('invoices', id, 'DELETE');
    await db.delete('invoice_items', where: 'invoice_id = ?', whereArgs: [id]);

    String? firebaseId;
    final row = await db.query(
      'invoices',
      columns: ['firebase_id'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (row.isNotEmpty) firebaseId = row.first['firebase_id'] as String?;

    final result = await db.delete(
      'invoices',
      where: 'id = ?',
      whereArgs: [id],
    );

    if (_isOnline && firebaseId != null && firebaseId.isNotEmpty) {
      await _firebaseService.deleteInvoice(firebaseId);
    } else if (firebaseId != null && firebaseId.isNotEmpty) {
      await db.insert('deleted_records', {
        'table_name': 'invoices',
        'firebase_id': firebaseId,
        'timestamp': DateTime.now().toIso8601String(),
        'synced': 0,
      });
    }

    return result;
  }

  Future<void> _ensureInvoiceDetailTables() async {
    final db = await database;

    await db.execute('''
    CREATE TABLE IF NOT EXISTS invoice_terms (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      term_key TEXT UNIQUE NOT NULL,
      title TEXT NOT NULL,
      body_template TEXT NOT NULL,
      requires_number INTEGER NOT NULL DEFAULT 0,
      number_label TEXT,
      unit TEXT,
      default_value REAL,
      is_active INTEGER NOT NULL DEFAULT 1
    )
  ''');

    await db.execute('''
    CREATE TABLE IF NOT EXISTS invoice_term_selections (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      invoice_id INTEGER NOT NULL,
      term_id INTEGER NOT NULL,
      value REAL,
      text TEXT NOT NULL,
      FOREIGN KEY (invoice_id) REFERENCES invoices(id) ON DELETE CASCADE,
      FOREIGN KEY (term_id) REFERENCES invoice_terms(id) ON DELETE RESTRICT
    )
  ''');

    await db.execute('''
    CREATE INDEX IF NOT EXISTS idx_invoice_term_sel_invoice
    ON invoice_term_selections(invoice_id)
  ''');

    await _seedDefaultInvoiceTerms(db);
  }

  Future<void> _seedDefaultInvoiceTerms(Database db) async {
    await db.rawInsert('''
    INSERT OR IGNORE INTO invoice_terms
    (term_key, title, body_template, requires_number, number_label, unit, default_value, is_active)
    VALUES
    ('TR_DELIVERY','Türkiye Teslimi','Yukarıdaki fiyatlar Türkiye teslim satış fiyatlarıdır.',0,NULL,NULL,NULL,1),
    ('KDV_INCLUDED','KDV Dahildir','Teklif toplamına %{value} KDV dahildir.',1,'KDV (%)','%',20,1),
    ('CARGO_BUYER','Kargo Ücreti','Kargo ücreti alıcıya aittir.',0,NULL,NULL,NULL,1),
    ('LATE_FEE','Vade Farkı','Fatura tarihinden itibaren ödeme vadesini aşan ödemelere aylık %{value} vade farkı uygulanır.',1,'Vade Farkı (%)','%',8,1),
    ('VALID_DAYS','Geçerlilik Süresi','Teklifin geçerlilik süresi {value} iş günüdür.',1,'Gün','gün',3,1)
  ''');
  }

  /// Manual sync trigger for testing
  Future<void> triggerManualSync() async {
    debugPrint('🔄 HybridDatabaseService.triggerManualSync() called');
    debugPrint('🔄 Manual sync triggered');
    debugPrint(
      '📊 Current status: online=$_isOnline, syncInProgress=$_isSyncInProgress',
    );

    if (!_isOnline) {
      debugPrint('⚠️ Cannot sync: offline');
      return;
    }

    try {
      debugPrint('🔄 Starting manual sync...');

      // Check current user
      final currentUser = _firebaseService.currentUser;
      debugPrint('👤 Current Firebase user: ${currentUser?.uid}');

      if (currentUser == null) {
        debugPrint('❌ No Firebase user found');
        return;
      }

      // Check database connection
      final db = await database;
      debugPrint('🗄️ Database connected successfully');

      // Clear pending operations to force fresh sync
      debugPrint('🧹 Clearing pending operations for fresh sync...');
      _pendingSyncOperations.clear();

      // Check pending operations
      final pendingOps = await db.query('sync_log', where: 'synced = 0');
      debugPrint('📝 Pending sync operations: ${pendingOps.length}');

      // Check unsynced records
      final unsyncedCustomers = await db.rawQuery(
        'SELECT COUNT(*) as count FROM customers WHERE firebase_synced = 0',
      );
      final unsyncedProducts = await db.rawQuery(
        'SELECT COUNT(*) as count FROM products WHERE firebase_synced = 0',
      );
      final unsyncedInvoices = await db.rawQuery(
        'SELECT COUNT(*) as count FROM invoices WHERE firebase_synced = 0',
      );

      debugPrint(
        '📊 Unsynced records: customers=${unsyncedCustomers.first['count']}, products=${unsyncedProducts.first['count']}, invoices=${unsyncedInvoices.first['count']}',
      );

      // Force sync all pending operations
      debugPrint('🔄 Calling _performFullSync()...');
      await _performFullSync();
      debugPrint('✅ _performFullSync() completed');

      debugPrint('✅ Manual sync completed');
    } catch (e) {
      debugPrint('❌ Manual sync error: $e');
      rethrow;
    }
  }

  /// Create sync operations for existing unsynced records
  Future<void> _createSyncOperationsForUnsyncedRecords() async {
    try {
      final db = await database;
      debugPrint('🔄 Creating sync operations for unsynced records...');

      // Get unsynced customers
      final unsyncedCustomers = await db.query(
        'customers',
        where: 'firebase_synced = 0',
      );
      for (var customer in unsyncedCustomers) {
        await _addToSyncLog('customers', customer['id'] as int, 'insert');
        debugPrint('📝 Added sync operation for customer: ${customer['id']}');
      }

      // Get unsynced products
      final unsyncedProducts = await db.query(
        'products',
        where: 'firebase_synced = 0',
      );
      for (var product in unsyncedProducts) {
        await _addToSyncLog('products', product['id'] as int, 'insert');
        debugPrint('📝 Added sync operation for product: ${product['id']}');
      }

      // Get unsynced invoices
      final unsyncedInvoices = await db.query(
        'invoices',
        where: 'firebase_synced = 0',
      );
      for (var invoice in unsyncedInvoices) {
        await _addToSyncLog('invoices', invoice['id'] as int, 'insert');
        debugPrint('📝 Added sync operation for invoice: ${invoice['id']}');
      }

      debugPrint(
        '✅ Created sync operations for ${unsyncedCustomers.length + unsyncedProducts.length + unsyncedInvoices.length} records',
      );
    } catch (e) {
      debugPrint('❌ Error creating sync operations: $e');
    }
  }
}
