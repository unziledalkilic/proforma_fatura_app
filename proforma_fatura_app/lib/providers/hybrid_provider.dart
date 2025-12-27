import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/hybrid_database_service.dart';
import '../services/firebase_service.dart';
import '../models/user.dart';
import '../models/customer.dart';
import '../models/product.dart';
import '../models/invoice.dart';
import '../models/company_info.dart';
import '../utils/id_converter.dart';
import '../utils/text_formatter.dart';

/// Hybrid Provider - SQLite (offline) + Firebase (online) desteği
class HybridProvider extends ChangeNotifier {
  final HybridDatabaseService _hybridService = HybridDatabaseService();
  final FirebaseService _firebaseService = FirebaseService();

  bool _isLoading = false;
  bool _isOnline = false;
  String? _error;
  DateTime? _lastSyncTime;
  Map<String, int> _syncStats = {};
  StreamSubscription<bool>? _connectivitySubscription;

  // Current user
  firebase_auth.User? _currentUser;
  User? _appUser;

  // Data lists
  List<Customer> _customers = [];
  List<Product> _products = [];
  List<Invoice> _invoices = [];
  CompanyInfo? _companyInfo;
  // Multi-company profiles
  List<CompanyInfo> _companies = [];
  CompanyInfo? _selectedCompany;

  // Getters
  bool get isLoading => _isLoading;
  bool get isOnline => _isOnline;
  String? get error => _error;
  DateTime? get lastSyncTime => _lastSyncTime;
  Map<String, int> get syncStats => _syncStats;
  firebase_auth.User? get currentUser => _currentUser;
  User? get appUser => _appUser;
  List<Customer> get customers => _customers;
  List<Product> get products => _products;
  List<Invoice> get invoices => _invoices;
  CompanyInfo? get companyInfo => _companyInfo;
  List<CompanyInfo> get companies => _companies;
  CompanyInfo? get selectedCompany => _selectedCompany;

  // Expose limited controls for settings actions
  FirebaseService get firebaseService => _firebaseService;
  void enablePullOnce() {
    _hybridService.setPullEnabled(true);
  }

  void disablePull() {
    _hybridService.setPullEnabled(false);
  }

  // Connectivity status
  String get connectivityStatus {
    if (_isOnline) {
      return 'Çevrimiçi';
    } else {
      return 'Çevrimdışı';
    }
  }

  // Pending sync count
  int get pendingSyncCount {
    return _syncStats['pending_operations'] ?? 0;
  }

  /// Initialize hybrid provider
  Future<void> initialize() async {
    _setLoading(true);
    try {
      // Initialize hybrid database service
      await _hybridService.initialize();
      _isOnline = _hybridService.isOnline;
      
      // Listen to connectivity changes
      _connectivitySubscription?.cancel();
      _connectivitySubscription = _hybridService.connectivityStream.listen((isOnline) {
        updateConnectivity(isOnline);
      });

      // Initialize Firebase service
      await _firebaseService.initialize();

      // Listen to auth state changes
      _firebaseService.auth.authStateChanges().listen(
        (firebase_auth.User? user) {
          _currentUser = user;
          if (user != null) {
            _appUser = _convertFirebaseUserToAppUser(user);
            _loadUserData();
          } else {
            _clearData();
          }
          notifyListeners();
        },
        onError: (error) {
          print('Firebase Auth State Listener Error: $error');
        },
      );

      // Update sync stats
      await _updateSyncStats();

      _setError(null);
    } catch (e) {
      _setError('Hybrid sistem başlatılamadı: $e');
    } finally {
      _setLoading(false);
    }
  }

  /// Convert Firebase User to App User
  User _convertFirebaseUserToAppUser(firebase_auth.User firebaseUser) {
    return User(
      id: null, // Local ID will be set after SQLite sync
      username: firebaseUser.email?.split('@').first ?? 'user',
      email: firebaseUser.email ?? '',
      passwordHash: '',
      fullName:
          firebaseUser.displayName ??
          firebaseUser.email?.split('@').first ??
          'User',
      companyName: null,
      phone: firebaseUser.phoneNumber,
      address: null,
      isActive: true,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }

  // ==================== AUTHENTICATION ====================

  Future<bool> registerUser(
    String email,
    String password,
    String name, [
    String? phone,
  ]) async {
    _setLoading(true);
    _setError(null);
    try {
      final userCredential = await _firebaseService.registerUser(
        email,
        password,
        name,
        phone,
      );
      if (userCredential != null || _firebaseService.auth.currentUser != null) {
        return true;
      } else {
        _setError('Kayıt işlemi başarısız');
        return false;
      }
    } catch (e) {
      _setError('Kayıt hatası: $e');
      return false;
    } finally {
      _setLoading(false);
    }
  }

  Future<bool> loginUser(String email, String password) async {
    _setLoading(true);
    _setError(null);
    try {
      final userCredential = await _firebaseService.loginUser(email, password);
      if (userCredential != null || _firebaseService.auth.currentUser != null) {
        return true;
      } else {
        _setError('Giriş başarısız');
        return false;
      }
    } catch (e) {
      _setError('Giriş hatası: $e');
      return false;
    } finally {
      _setLoading(false);
    }
  }

  Future<void> logoutUser() async {
    _setLoading(true);
    try {
      await _firebaseService.logoutUser();
      _clearData();
      _setError(null);
    } catch (e) {
      _setError('Çıkış hatası: $e');
    } finally {
      _setLoading(false);
    }
  }

  // ==================== CUSTOMER OPERATIONS ====================

  /// Manual sync trigger for testing
  Future<void> triggerManualSync() async {
    try {
      await _hybridService.triggerManualSync();
      notifyListeners();
    } catch (e) {
      _setError('Manuel senkronizasyon hatası: $e');
    }
  }

  Future<bool> addCustomer(Customer customer) async {
    _setLoading(true);
    try {
      // Add to local database first (works offline)
      final currentUserId = await _hybridService.getCurrentLocalUserId();

      if (currentUserId <= 0) {
        _setError('Geçersiz kullanıcı ID: $currentUserId');
        return false;
      }

      final enriched = customer.copyWith(userId: currentUserId.toString());
      final customerId = await _hybridService.insertCustomer(enriched);

      if (customerId > 0) {
        // Reload customers from local database
        await _loadCustomersFromLocal();
        _setError(null);
        return true;
      } else {
        _setError('Müşteri eklenemedi - veritabanı hatası');
        return false;
      }
    } catch (e) {
      _setError('Müşteri ekleme hatası: $e');
      return false;
    } finally {
      _setLoading(false);
      await _updateSyncStats();
    }
  }

  Future<bool> updateCustomer(Customer customer) async {
    _setLoading(true);
    try {
      final result = await _hybridService.updateCustomer(customer);

      if (result > 0) {
        await _loadCustomersFromLocal();
        _setError(null);
        return true;
      } else {
        _setError('Müşteri güncellenemedi');
        return false;
      }
    } catch (e) {
      _setError('Müşteri güncelleme hatası: $e');
      return false;
    } finally {
      _setLoading(false);
      await _updateSyncStats();
    }
  }

  Future<bool> deleteCustomer(int customerId) async {
    _setLoading(true);
    try {
      final result = await _hybridService.deleteCustomer(customerId);

      if (result > 0) {
        await _loadCustomersFromLocal();
        _setError(null);
        return true;
      } else {
        _setError('Müşteri silinemedi');
        return false;
      }
    } catch (e) {
      _setError('Müşteri silme hatası: $e');
      return false;
    } finally {
      _setLoading(false);
      await _updateSyncStats();
    }
  }

  // ==================== PRODUCT OPERATIONS ====================

  Future<bool> addProduct(Product product) async {
    _setLoading(true);
    try {
      final currentUserId = await _hybridService.getCurrentLocalUserId();
      final productWithUser = product.copyWith(
        userId: currentUserId.toString(),
      );

      final productId = await _hybridService.insertProduct(productWithUser);

      if (productId > 0) {
        await _loadProductsFromLocal();
        _setError(null);
        return true;
      } else {
        _setError('Ürün eklenemedi');
        return false;
      }
    } catch (e) {
      _setError('Ürün ekleme hatası: $e');
      return false;
    } finally {
      _setLoading(false);
      await _updateSyncStats();
    }
  }

  Future<bool> updateProduct(Product product) async {
    _setLoading(true);
    try {
      final result = await _hybridService.updateProduct(product);

      if (result > 0) {
        await _loadProductsFromLocal();
        _setError(null);
        return true;
      } else {
        _setError('Ürün güncellenemedi');
        return false;
      }
    } catch (e) {
      // DatabaseException UNIQUE ise kullanıcı dostu mesaj
      final msg = e.toString().toLowerCase().contains('unique')
          ? 'Bu şirkette aynı isimde bir ürün zaten var'
          : 'Ürün güncelleme hatası: $e';
      _setError(msg);
      return false;
    } finally {
      _setLoading(false);
      await _updateSyncStats();
    }
  }

  Future<bool> deleteProduct(int productId) async {
    _setLoading(true);
    try {
      final result = await _hybridService.deleteProduct(productId);

      if (result > 0) {
        await _loadProductsFromLocal();
        _setError(null);
        return true;
      } else {
        _setError('Ürün silinemedi');
        return false;
      }
    } catch (e) {
      _setError('Ürün silme hatası: $e');
      return false;
    } finally {
      _setLoading(false);
      await _updateSyncStats();
    }
  }

  /// Firebase ID ile ürünü sil (kolaylık için)
  Future<bool> deleteProductByFirebaseId(String firebaseId) async {
    _setLoading(true);
    try {
      final sqliteId = await _hybridService.deleteProductByFirebaseId(
        firebaseId,
      ); // returns affected rows
      if (sqliteId > 0) {
        await _loadProductsFromLocal();
        _setError(null);
        return true;
      }
      _setError('Ürün silinemedi');
      return false;
    } catch (e) {
      _setError('Ürün silme hatası: $e');
      return false;
    } finally {
      _setLoading(false);
      await _updateSyncStats();
    }
  }

  // ==================== INVOICE OPERATIONS ====================

  Future<bool> addInvoice(Invoice invoice) async {
    _setLoading(true);
    try {
      final invoiceId = await _hybridService.insertInvoice(invoice);

      if (invoiceId > 0) {
        await _loadInvoicesFromLocal();
        _setError(null);
        return true;
      } else {
        _setError('Fatura eklenemedi');
        return false;
      }
    } catch (e) {
      _setError('Fatura ekleme hatası: $e');
      return false;
    } finally {
      _setLoading(false);
      await _updateSyncStats();
    }
  }

  // ==================== SYNC OPERATIONS ====================

  /// Manual sync trigger
  Future<void> performSync() async {
    if (!_isOnline) {
      _setError('İnternet bağlantısı yok - senkronizasyon yapılamıyor');
      return;
    }

    _setLoading(true);
    try {
      await _hybridService.performManualSync();

      // Reload data after sync
      await _loadUserData();

      _lastSyncTime = DateTime.now();
      await _updateSyncStats();
      _setError(null);
    } catch (e) {
      _setError('Senkronizasyon hatası: $e');
    } finally {
      _setLoading(false);
    }
  }

  /// Database maintenance işlemi
  Future<Map<String, dynamic>> performMaintenance() async {
    _setLoading(true);
    try {
      final results = await _hybridService.runMaintenance();
      _setError(null);
      return results;
    } catch (e) {
      _setError('Database maintenance hatası: $e');
      return {'error': e.toString()};
    } finally {
      _setLoading(false);
    }
  }

  /// Database validation işlemi
  Future<Map<String, dynamic>> performValidation() async {
    _setLoading(true);
    try {
      final results = await _hybridService.runValidation();
      _setError(null);
      return results;
    } catch (e) {
      _setError('Database validation hatası: $e');
      return {'error': e.toString()};
    } finally {
      _setLoading(false);
    }
  }

  // ==================== COMPANY PROFILES ====================

  Future<void> loadCompanyProfiles() async {
    try {
      // Initialize empty list first to prevent null issues
      _companies = [];

      // 1) Local first - with more safety checks
      final localUserId = _appUser?.id;

      List<CompanyInfo> local = [];
      try {
        local = await _hybridService.getAllCompanyProfiles(userId: localUserId);
      } catch (e) {
        local = [];
      }

      // 2) Remote if online - with timeout
      List<CompanyInfo> remote = [];
      if (_isOnline) {
        try {
          // Add timeout to prevent hanging
          remote = await _firebaseService.getCompanyProfiles().timeout(
            const Duration(seconds: 10),
          );
        } catch (e) {
          remote = [];
        }
      }

      // 3) Simple merge - avoid complex operations that might crash
      final Set<String> seenIds = {};
      final List<CompanyInfo> mergedList = [];

      // Add local companies first
      for (final c in local) {
        if (c.name.trim().isNotEmpty) {
          final id = c.firebaseId ?? '${c.id}';
          if (!seenIds.contains(id)) {
            seenIds.add(id);
            mergedList.add(c);
          }
        }
      }

      // Add remote companies (only if not already seen)
      for (final c in remote) {
        if (c.name.trim().isNotEmpty) {
          final id = c.firebaseId ?? '${c.id}';
          if (!seenIds.contains(id)) {
            seenIds.add(id);
            mergedList.add(c);
          }
        }
      }

      _companies = mergedList;

      // Simple sort by name instead of date to avoid DateTime issues
      try {
        _companies.sort((a, b) => a.name.compareTo(b.name));
      } catch (e) {
        // Keep unsorted if sort fails
      }

      // Safe selection (auto-select first if exists)
      if (_selectedCompany == null && _companies.isNotEmpty) {
        _selectedCompany = _companies.first;
      }

      // Notify listeners at the end
      notifyListeners();
    } catch (e) {
      _setError('Şirket profilleri yüklenemedi: $e');

      // Ensure _companies is always initialized
      _companies = [];
      _selectedCompany = null;

      // Still notify listeners to update UI
      notifyListeners();
    }
  }

  Future<bool> addCompanyProfile(CompanyInfo company) async {
    _setLoading(true);
    try {
      // 1) Local insert (offline-first)
      final localId = await _hybridService.insertCompanyProfile(company);

      if (localId > 0) {
        // 2) Refresh list to include the new company
        await loadCompanyProfiles();
        _setError(null);
        return true;
      } else {
        _setError('Şirket SQLite\'a eklenemedi');
        return false;
      }
    } catch (e) {
      _setError('Şirket eklenemedi: $e');
      return false;
    } finally {
      _setLoading(false);
    }
  }

  Future<bool> updateCompanyProfile(CompanyInfo company) async {
    try {
      // 1) Local-first update so UI immediately reflects changes (including local logo path)
      final updated = await _hybridService.updateCompanyProfileLocal(company);
      if (updated > 0) {
        // 2) Best-effort remote update (non-blocking for UI correctness)
        try {
          await _firebaseService.updateCompanyProfile(company);
        } catch (_) {
          // Remote optional – ignore if fails (no storage etc.)
        }
        // 3) Reload list
        await loadCompanyProfiles();
        return true;
      } else {
        _setError('Şirket yerelde güncellenemedi');
      }
    } catch (e) {
      _setError('Şirket güncellenemedi: $e');
    }
    return false;
  }

  Future<bool> deleteCompanyProfile(String firebaseId) async {
    try {
      // Önce local ürünlerde company_id'yi null yap ki ürünler silinmesin
      await _hybridService.nullifyProductsCompany(firebaseId);

      final ok = await _firebaseService.deleteCompanyProfile(firebaseId);
      if (ok) {
        // Local company_info'dan da sil
        await _hybridService.deleteCompanyProfileByFirebaseId(firebaseId);
        await loadCompanyProfiles();
        if (_selectedCompany?.firebaseId == firebaseId) {
          _selectedCompany = _companies.isNotEmpty ? _companies.first : null;
        }
        // Ürünleri yeniden yükle
        await _loadProductsFromLocal();
        return true;
      }
    } catch (e) {
      _setError('Şirket silinemedi: $e');
    }
    return false;
  }

  void selectCompany(CompanyInfo? company) {
    _selectedCompany = company;
    notifyListeners();
  }

  /// Update connectivity status
  void updateConnectivity(bool isOnline) {
    _isOnline = isOnline;
    notifyListeners();
  }

  // ==================== USER PROFILE SYNC ====================

  /// Firestore'da kullanıcı dokümanı yoksa oluşturur
  Future<void> _ensureFirestoreUserDocument() async {
    if (_currentUser == null) return;
    try {
      final uid = _currentUser!.uid;
      final userRef = _firebaseService.firestore.collection('users').doc(uid);
      final snap = await userRef.get();
      if (!snap.exists) {
        await userRef.set({
          'email': _currentUser!.email,
          'name':
              _currentUser!.displayName ??
              _currentUser!.email?.split('@').first,
          'phone': _currentUser!.phoneNumber,
          'address': null,
          'createdAt': FieldValue.serverTimestamp(),
          'lastLogin': FieldValue.serverTimestamp(),
        });
      }
    } catch (e) {
      // Ignore Firestore errors
    }
  }

  /// Kullanıcı profil bilgilerini Firestore'dan güncelle
  Future<void> _updateUserProfileFromFirestore() async {
    if (_currentUser == null || _appUser == null) return;

    try {
      final userDoc = await _firebaseService.firestore
          .collection('users')
          .doc(_currentUser!.uid)
          .get();

      if (userDoc.exists) {
        final data = userDoc.data()!;
        final updatedUser = _appUser!.copyWith(
          fullName: data['name'] as String? ?? _appUser!.fullName,
          phone: data['phone'] as String? ?? _appUser!.phone,
          address: data['address'] as String? ?? _appUser!.address,
          updatedAt: DateTime.now(),
        );

        // Eğer veriler değiştiyse güncelle
        if (updatedUser.fullName != _appUser!.fullName ||
            updatedUser.phone != _appUser!.phone ||
            updatedUser.address != _appUser!.address) {
          _appUser = updatedUser;
          notifyListeners();
        }
      }
    } catch (e) {
      // Ignore Firestore errors
    }
  }

  // ==================== DATA LOADING ====================

  Future<void> _loadUserData() async {
    // Firestore kullanıcı kaydını garanti altına al
    await _ensureFirestoreUserDocument();

    // Kullanıcı profil bilgilerini Firestore'dan güncelle
    await _updateUserProfileFromFirestore();

    // Kullanıcı ID'si yoksa Firebase sync yap
    if (_appUser?.id == null) {
      // Sonsuz döngü olmaması için _loadUserData'ya tekrar çağrı yapmıyoruz
      await _syncFromFirebaseOnLogin();
      return;
    }

    // Önce yerel verileri yükle (hızlı gösterim için)
    await Future.wait([
      _loadCustomersFromLocal(),
      _loadProductsFromLocal(),
      _loadInvoicesFromLocal(),
      loadCompanyProfiles(), // Güvenli hale getirildi
    ]);

    // Eğer yerel veriler boş ise veya online ise Firebase'den sync yap
    if ((_customers.isEmpty || _products.isEmpty || _invoices.isEmpty) &&
        _isOnline) {
      await _syncFromFirebaseOnLogin();
    }
  }

  Future<void> _loadCustomersFromLocal() async {
    try {
      final userId = _appUser?.id;

      // Safety check to prevent crashes if appUser is null
      if (userId == null) {
        return;
      }

      final customers = await _hybridService.getAllCustomers(userId: userId);
      _customers = _dedupCustomers(customers);
      notifyListeners();
    } catch (e) {
      _setError('Müşteriler yüklenemedi: $e');
    }
  }

  /// Load products from local database
  Future<void> _loadProductsFromLocal() async {
    try {
      final userId = _appUser?.id;

      // Safety check to prevent crashes if appUser is null
      if (userId == null) {
        return;
      }

      final products = await _hybridService.getAllProducts(userId: userId);
      _products = products;
      notifyListeners();
    } catch (e) {
      _setError('Ürünler yüklenirken hata: $e');
    }
  }

  /// Load products for specific company from local database
  Future<void> loadProductsForCompany(String companyId) async {
    try {
      final userId = _appUser?.id;

      // Safety check to prevent crashes if appUser is null
      if (userId == null) {
        return;
      }

      final allProducts = await _hybridService.getAllProducts(userId: userId);
      _products = allProducts
          .where((product) => product.companyId == companyId)
          .toList();
      notifyListeners();
    } catch (e) {
      _setError('Şirket ürünleri yüklenirken hata: $e');
    }
  }

  /// Load invoices for specific company from local database
  Future<void> loadInvoicesForCompany(String companyId) async {
    try {
      final userId = _appUser?.id;

      // Safety check to prevent crashes if appUser is null
      if (userId == null) {
        return;
      }

      final allInvoices = await _hybridService.getAllInvoices(userId: userId);
      _invoices = allInvoices
          .where((invoice) => invoice.companyId == companyId)
          .toList();
      notifyListeners();
    } catch (e) {
      _setError('Şirket faturaları yüklenirken hata: $e');
    }
  }

  Future<void> _loadInvoicesFromLocal() async {
    try {
      final userId = _appUser?.id;
      final invoices = await _hybridService.getAllInvoices(userId: userId);
      _invoices = _dedupInvoices(invoices);
      notifyListeners();
    } catch (e) {
      _setError('Faturalar yüklenemedi: $e');
    }
  }

  // ==================== DEDUP HELPERS ====================

  List<Customer> _dedupCustomers(List<Customer> list) {
    final seen = <String, Customer>{};
    for (final c in list) {
      final key = ((c.id ?? '').isNotEmpty)
          ? c.id!
          : '${c.userId ?? ''}|${TextFormatter.normalizeForSearchTr(c.email ?? '')}|${TextFormatter.normalizeForSearchTr(c.phone ?? '')}|${TextFormatter.normalizeForSearchTr(c.taxNumber ?? '')}|${TextFormatter.normalizeForSearchTr(c.name)}';
      if (!seen.containsKey(key)) {
        seen[key] = c;
      }
    }
    return seen.values.toList(growable: false);
  }

  List<Product> _dedupProducts(List<Product> list) {
    final seen = <String, Product>{};
    for (final p in list) {
      final key = ((p.id ?? '').isNotEmpty)
          ? p.id!
          : '${p.userId}|${TextFormatter.normalizeForSearchTr(p.barcode ?? '')}|${TextFormatter.normalizeForSearchTr(p.name)}';
      if (!seen.containsKey(key)) {
        seen[key] = p;
      }
    }
    return seen.values.toList(growable: false);
  }

  List<Invoice> _dedupInvoices(List<Invoice> list) {
    final seen = <String, Invoice>{};
    for (final i in list) {
      // invoiceNumber her kullanıcı için benzersiz kabul edilir
      final key = i.invoiceNumber;
      if (!seen.containsKey(key)) {
        seen[key] = i;
      }
    }
    return seen.values.toList(growable: false);
  }

  Future<void> _updateSyncStats() async {
    try {
      _syncStats = await _hybridService.getSyncStats();
      notifyListeners();
    } catch (e) {
      // Ignore sync stats errors
    }
  }

  /// Firebase'den ilk giriş senkronizasyonu
  Future<void> _syncFromFirebaseOnLogin() async {
    if (!_isOnline || _currentUser == null) {
      return;
    }

    try {
      // Firebase'den verileri çek
      final firebaseCustomers = await _firebaseService.getCustomers();
      final firebaseProducts = await _firebaseService.getProducts();
      final firebaseInvoices = await _firebaseService.getInvoices();

      // Hybrid service ile SQLite'a da sync yap
      await _hybridService.performManualSync();

      // Kullanıcı ID'sini SQLite'dan al ve set et
      if (_appUser != null && _appUser!.id == null) {
        final localUserId = await _hybridService.getCurrentLocalUserId();
        _appUser = _appUser!.copyWith(id: localUserId);
      }

      // Kullanıcı ID'si set edildikten sonra verileri yükle
      await Future.wait([
        _loadCustomersFromLocal(),
        _loadProductsFromLocal(),
        _loadInvoicesFromLocal(),
      ]);
    } catch (e) {
      _setError('Veriler yüklenirken hata oluştu: $e');
    }
  }

  // ==================== UTILITY METHODS ====================

  void _setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }

  void _setError(String? error) {
    _error = error;
    notifyListeners();
  }

  void _clearData() {
    try {
      // Güvenli temizleme işlemleri
      _appUser = null;

      // Listeleri güvenli şekilde temizle
      try {
        if (_customers.isNotEmpty) {
          _customers.clear();
        }
      } catch (e) {
        _customers = [];
      }

      try {
        if (_products.isNotEmpty) {
          _products.clear();
        }
      } catch (e) {
        _products = [];
      }

      try {
        if (_invoices.isNotEmpty) {
          _invoices.clear();
        }
      } catch (e) {
        _invoices = [];
      }

      _companyInfo = null;

      // Sync stats'i güvenli şekilde temizle
      try {
        if (_syncStats.isNotEmpty) {
          _syncStats.clear();
        }
      } catch (e) {
        _syncStats = {};
      }

      // UI'ı güncelle
      notifyListeners();
    } catch (e) {
      // Hata olsa bile temel temizleme işlemlerini yap
      try {
        _appUser = null;
        _customers = [];
        _products = [];
        _invoices = [];
        _companyInfo = null;
        _syncStats = {};

        notifyListeners();
      } catch (finalError) {
        // Son çare - hiçbir şey yapma, sadece log'da tut
        print('Critical error in _clearData: $finalError');
      }
    }
  }

  void clearError() {
    _setError(null);
  }

  // ==================== CATEGORY METHODS ====================

  List<String> get categories => [
    'Elektronik',
    'Gıda',
    'Tekstil',
    'Otomotiv',
    'Sağlık',
    'Eğitim',
    'Diğer',
  ];

  // ==================== FILTER METHODS ====================

  List<Product> getProductsByCategory(String category) {
    if (category == 'Tümü') return _products;
    return _products.where((product) => product.category == category).toList();
  }

  List<Customer> searchCustomers(String query) {
    if (query.isEmpty) return _customers;
    final q = TextFormatter.normalizeForSearchTr(query);
    return _customers.where((customer) {
      final name = TextFormatter.normalizeForSearchTr(customer.name);
      final email = TextFormatter.normalizeForSearchTr(customer.email ?? '');
      return name.contains(q) || email.contains(q);
    }).toList();
  }

  List<Product> searchProducts(String query) {
    if (query.isEmpty) return _products;
    final q = TextFormatter.normalizeForSearchTr(query);
    return _products.where((product) {
      final name = TextFormatter.normalizeForSearchTr(product.name);
      final desc = TextFormatter.normalizeForSearchTr(
        product.description ?? '',
      );
      return name.contains(q) || desc.contains(q);
    }).toList();
  }

  // ==================== STATISTICS ====================

  Map<String, dynamic> get statistics {
    return {
      'total_customers': _customers.length,
      'total_products': _products.length,
      'total_invoices': _invoices.length,
      'is_online': _isOnline,
      'last_sync': _lastSyncTime?.toIso8601String(),
      'pending_sync_count': pendingSyncCount,
    };
  }

  // ==================== MISSING METHODS FOR COMPATIBILITY ====================

  /// Load customers (compatibility method)
  Future<void> loadCustomers() async {
    await _loadCustomersFromLocal();
  }

  /// Load products (compatibility method)
  Future<void> loadProducts() async {
    await _loadProductsFromLocal();
  }

  /// Load invoices (compatibility method)
  Future<void> loadInvoices() async {
    await _loadInvoicesFromLocal();
  }

  /// Load company info (compatibility method)
  Future<void> loadCompanyInfo() async {
    try {
      _setLoading(true);
      // Company info is loaded during initialization
      // This is just for compatibility
      _setError(null);
    } catch (e) {
      _setError('Şirket bilgileri yüklenemedi: $e');
    } finally {
      _setLoading(false);
    }
  }

  /// Load categories (compatibility method)
  Future<void> loadCategories() async {
    // Categories are static in hybrid provider
    // This is just for compatibility
  }

  /// Manuel Firebase sync (test için)
  Future<void> forceFirebaseSync() async {
    await _syncFromFirebaseOnLogin();
  }

  /// Search invoices (compatibility method)
  List<Invoice> searchInvoices(String query) {
    if (query.isEmpty) return _invoices;

    final q = TextFormatter.normalizeForSearchTr(query);
    return _invoices.where((invoice) {
      final inv = TextFormatter.normalizeForSearchTr(invoice.invoiceNumber);
      final cname = TextFormatter.normalizeForSearchTr(invoice.customer.name);
      return inv.contains(q) || cname.contains(q);
    }).toList();
  }

  /// Update profile (compatibility method)
  Future<bool> updateProfile(User user) async {
    try {
      _setLoading(true);

      // Update Firebase user profile
      final currentUser = _firebaseService.auth.currentUser;
      if (currentUser != null) {
        await currentUser.updateDisplayName(user.fullName);
        await currentUser.updateEmail(user.email);

        // Update Firestore user document with additional info
        try {
          await _firebaseService.firestore
              .collection('users')
              .doc(currentUser.uid)
              .update({
                'name': user.fullName,
                'phone': user.phone,
                'address': user.address,
                'updatedAt': FieldValue.serverTimestamp(),
              });
        } catch (firestoreError) {
          // Ignore Firestore errors
        }

        // Update local user data
        _appUser = user;
        notifyListeners();

        return true;
      }

      return false;
    } catch (e) {
      _setError('Profil güncellenemedi: $e');
      return false;
    } finally {
      _setLoading(false);
    }
  }

  /// Logout user (compatibility method)
  Future<void> logout() async {
    try {
      _setLoading(true);

      // Firebase'den çıkış yap
      try {
        await _firebaseService.auth.signOut();
      } catch (e) {
        // Firebase çıkış hatası kritik değil, devam et
        print('Firebase logout error (non-critical): $e');
      }

      // Tüm verileri temizle
      _clearData();
    } catch (e) {
      print('Logout error: $e');
      _setError('Çıkış yapılamadı: $e');

      // Hata olsa bile verileri temizlemeye çalış
      try {
        _clearData();
      } catch (clearError) {
        print('Data cleanup error: $clearError');
      }
    } finally {
      _setLoading(false);
    }
  }

  /// Delete invoice (compatibility method)
  Future<bool> deleteInvoice(String invoiceId) async {
    try {
      _setLoading(true);

      // Convert string ID to int for local database - güvenli dönüşüm
      final id = IdConverter.stringToInt(invoiceId);
      if (id == null) {
        _setError('Geçersiz fatura ID: $invoiceId');
        return false;
      }

      final result = await _hybridService.deleteInvoice(id);

      if (result > 0) {
        await _loadInvoicesFromLocal();
        await _updateSyncStats();
        return true;
      }

      return false;
    } catch (e) {
      _setError('Fatura silinemedi: $e');
      return false;
    } finally {
      _setLoading(false);
    }
  }

  /// Update invoice (compatibility method)
  Future<bool> updateInvoice(Invoice invoice) async {
    try {
      _setLoading(true);

      final result = await _hybridService.updateInvoice(invoice);

      if (result > 0) {
        await _loadInvoicesFromLocal();
        await _updateSyncStats();
        return true;
      }

      return false;
    } catch (e) {
      _setError('Fatura güncellenemedi: $e');
      return false;
    } finally {
      _setLoading(false);
    }
  }

  // === Invoice Terms helpers ===
  Future<List<String>> getInvoiceTermsTextByInvoiceId(int invoiceId) {
    return _hybridService.getInvoiceTermsTextByInvoiceId(invoiceId);
  }

  /// Save company info (compatibility method)
  Future<bool> saveCompanyInfo(CompanyInfo companyInfo) async {
    try {
      _setLoading(true);

      // Save to Firebase
      await _firebaseService.saveCompanyInfo(companyInfo);

      // Update local data
      _companyInfo = companyInfo;
      notifyListeners();

      return true;
    } catch (e) {
      _setError('Şirket bilgileri kaydedilemedi: $e');
      return false;
    } finally {
      _setLoading(false);
    }
  }

  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    _hybridService.dispose();
    super.dispose();
  }
}
