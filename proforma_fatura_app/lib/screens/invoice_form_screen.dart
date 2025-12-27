import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/customer.dart';
import '../models/invoice.dart';
import '../models/invoice_item.dart';
import '../models/product.dart';
import '../providers/hybrid_provider.dart';
import '../utils/text_formatter.dart';
import 'pdf_preview_screen.dart';
import '../widgets/company_logo_avatar.dart';

// ✅ Eklendi: DB erişimi için
import '../services/hybrid_database_service.dart';
import '../services/currency_service.dart';

class InvoiceFormScreen extends StatefulWidget {
  final Invoice? invoice; // Düzenleme modu için

  const InvoiceFormScreen({super.key, this.invoice});

  @override
  State<InvoiceFormScreen> createState() => _InvoiceFormScreenState();
}

class _InvoiceFormScreenState extends State<InvoiceFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _invoiceNumberController = TextEditingController();

  // Alıcı bilgileri için controller'lar
  final _customerNameController = TextEditingController();
  final _customerAddressController = TextEditingController();
  final _customerPhoneController = TextEditingController();
  final _customerEmailController = TextEditingController();
  final _customerTaxNumberController = TextEditingController();

  // Kayıtlı müşteri seçimi için
  String? _selectedCustomerId;
  bool _isLoading = false;

  // Ürün seçimi için
  List<InvoiceItem> _invoiceItems = [];
  final _quantityController = TextEditingController();
  final _unitPriceController = TextEditingController();
  final _discountRateController = TextEditingController();
  final _taxRateController = TextEditingController();
  final _itemNotesController = TextEditingController();
  Product? _selectedProduct;
  // Satıcı şirket seçimi
  String? _selectedCompanyId; // firebaseId veya null

  // ✅ Eklendi: Fatura Para Birimi
  String _invoiceCurrency = 'TRY';
  
  // ✅ Eklendi: Ürün girişindeki anlık para birimi seçimi
  String? _itemCurrency;

  // ✅ Eklendi: Fatura Detayları (invoice_terms) UI state
  List<Map<String, dynamic>> _terms = []; // invoice_terms satırları
  final Map<int, double?> _termValues = {}; // term_id -> sayı (gerekiyorsa)
  final Set<int> _selectedTermIds = <int>{}; // seçili term_id'ler

  // Para birimi sembolü getir
  String _getCurrencySymbol(String currency) {
    switch (currency.toUpperCase()) {
      case 'TRY':
        return '₺';
      case 'USD':
        return '\$';
      case 'EUR':
        return '€';
      case 'GBP':
        return '£';
      default:
        return currency;
    }
  }

  @override
  void initState() {
    super.initState();
    debugPrint('🔄 InvoiceFormScreen initState başladı');

    // Düzenleme modu ise mevcut fatura bilgilerini yükle
    if (widget.invoice != null) {
      _loadInvoiceData(widget.invoice!);
    } else {
      try {
        _invoiceNumberController.text =
            'PF-${DateTime.now().year}${DateTime.now().month.toString().padLeft(2, '0')}${DateTime.now().day.toString().padLeft(2, '0')}-${(1000 + DateTime.now().millisecondsSinceEpoch % 9000)}';
        debugPrint(
          '✅ Fatura numarası oluşturuldu: ${_invoiceNumberController.text}',
        );
      } catch (e) {
        debugPrint('❌ Fatura numarası oluşturma hatası: $e');
      }
    }

    // Müşterileri ve ürünleri yükle
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadCustomers();
      _loadProducts();
      context.read<HybridProvider>().loadCompanyProfiles();
      // ✅ Eklendi: Fatura Detayları (şablon) yükle
      _loadTerms();
      // (Opsiyonel) düzenleme modunda varsa seçili maddeleri yükleme ileride eklenebilir
    });

    debugPrint('✅ InvoiceFormScreen initState tamamlandı');
  }

  // ✅ Eklendi: invoice_terms'ü DB'den çek
  Future<void> _loadTerms() async {
    try {
      final db = await HybridDatabaseService().database;
      final rows = await db.query(
        'invoice_terms',
        where: 'is_active = 1',
        orderBy: 'title',
      );
      setState(() {
        _terms = rows;
        // Varsayılan değerleri hazırla
        for (final r in rows) {
          final id = r['id'] as int;
          final def = r['default_value'] as num?;
          _termValues[id] = def?.toDouble();
        }
      });
    } catch (e) {
      debugPrint('❌ invoice_terms yüklenemedi: $e');
    }
  }

  // ✅ Eklendi: şablon metninden nihai metni üret
  String _buildFinalText(Map<String, dynamic> term, double? value) {
    String s = (term['body_template'] as String?) ?? '';
    final requires = (term['requires_number'] ?? 0) == 1;
    if (requires) {
      final v = value ?? (term['default_value'] as num?)?.toDouble() ?? 0;
      final formatted = (v % 1 == 0) ? v.toStringAsFixed(0) : v.toString();
      s = s.replaceAll('%{value}', formatted).replaceAll('{value}', formatted);
    }
    return s;
  }

  // ✅ Eklendi: Fatura genel kur sembolü (ilk ürüne göre)
  String get _invoiceCurrencySymbol {
    if (_invoiceItems.isEmpty) return '₺';
    // İlk ürünün para birimini baz al
    return _getCurrencySymbol(_invoiceItems.first.product?.currency ?? 'TRY');
  }

  // ✅ Eklendi: seçilen maddeleri invoice_term_selections tablosuna yaz
  Future<void> _saveInvoiceTermsToDb(int invoiceId) async {
    final db = await HybridDatabaseService().database;
    await db.transaction((txn) async {
      // Eski seçimleri sil
      await txn.delete(
        'invoice_term_selections',
        where: 'invoice_id = ?',
        whereArgs: [invoiceId],
      );

      // Seçilileri ekle
      for (final t in _terms) {
        final id = t['id'] as int;
        if (!_selectedTermIds.contains(id)) continue;
        final val = _termValues[id];
        final text = _buildFinalText(t, val);
        await txn.insert('invoice_term_selections', {
          'invoice_id': invoiceId,
          'term_id': id,
          'value': val,
          'text': text,
        });
      }
    });
  }

  Future<void> _loadCustomers() async {
    final hybridProvider = context.read<HybridProvider>();
    await hybridProvider.loadCustomers();
  }

  Future<void> _loadProducts() async {
    final hybridProvider = context.read<HybridProvider>();
    await hybridProvider.loadProducts();
  }

  void _loadInvoiceData(Invoice invoice) {
    // Fatura bilgilerini yükle
    _invoiceNumberController.text = invoice.invoiceNumber;
    _invoiceCurrency = invoice.currency; // ✅ Yüklendi

    // Müşteri bilgilerini yükle
    _customerNameController.text = invoice.customer.name;
    _customerAddressController.text = invoice.customer.address ?? '';
    _customerPhoneController.text = invoice.customer.phone ?? '';
    _customerEmailController.text = invoice.customer.email ?? '';
    _customerTaxNumberController.text = invoice.customer.taxNumber ?? '';

    _selectedCustomerId = invoice.customer.id.toString();

    // Fatura ürünlerini yükle
    _invoiceItems = List.from(invoice.items);

    debugPrint('✅ Fatura bilgileri yüklendi: ${invoice.id}');
    debugPrint('📄 Fatura numarası: ${invoice.invoiceNumber}');
    debugPrint('📦 Ürün sayısı: ${invoice.items.length}');

    // Debug: Mevcut ürünlerin invoiceId'lerini kontrol et
    for (int i = 0; i < invoice.items.length; i++) {
      debugPrint(
        '  Mevcut ürün $i: ${invoice.items[i].productName ?? invoice.items[i].product?.name ?? 'Ürün'}, InvoiceId: ${invoice.items[i].invoiceId}',
      );
    }
  }

  @override
  void dispose() {
    debugPrint('🔄 InvoiceFormScreen dispose başladı');
    _invoiceNumberController.dispose();
    _customerNameController.dispose();
    _customerAddressController.dispose();
    _customerPhoneController.dispose();
    _customerEmailController.dispose();
    _customerTaxNumberController.dispose();

    _quantityController.dispose();
    _unitPriceController.dispose();
    _discountRateController.dispose();
    _taxRateController.dispose();
    _itemNotesController.dispose();
    super.dispose();
    debugPrint('✅ InvoiceFormScreen dispose tamamlandı');
  }

  void _onCustomerSelected(String? customerId) {
    setState(() {
      _selectedCustomerId = customerId;
    });

    if (customerId != null) {
      // Seçilen müşterinin bilgilerini yükle
      final hybridProvider = context.read<HybridProvider>();
      final customer = hybridProvider.customers.firstWhere(
        (c) => c.id.toString() == customerId,
      );

      _customerNameController.text = customer.name;
      _customerAddressController.text = customer.address ?? '';
      _customerPhoneController.text = customer.phone ?? '';
      _customerEmailController.text = customer.email ?? '';
      _customerTaxNumberController.text = customer.taxNumber ?? '';
    } else {
      // Müşteri seçimi temizlendiğinde formu temizle
      _customerNameController.clear();
      _customerAddressController.clear();
      _customerPhoneController.clear();
      _customerEmailController.clear();
      _customerTaxNumberController.clear();
    }
  }

  void _onProductSelected(Product? product) {
    setState(() {
      _selectedProduct = product;
      if (product != null) {
        _unitPriceController.text = product.price.toString();
        _taxRateController.text = '18'; // Varsayılan KDV oranı
        _itemCurrency = product.currency; // ✅ Varsayılan olarak ürünün para birimi
      } else {
        _unitPriceController.clear();
        _taxRateController.clear();
        _itemCurrency = null; // ✅ Seçim yok
      }
    });
  }

  // ✅ Eklendi: Para birimi ve kur çevirici diyaloğu
  void _showCurrencyConversionDialog() {
    if (_selectedProduct == null) return;

    final currentPrice = double.tryParse(_unitPriceController.text) ?? 0;
    final sourceCurrency = _itemCurrency ?? _selectedProduct!.currency;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Para Birimi Çevir'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Dönüştürmek istediğiniz para birimini seçin.\nFiyat güncel kura göre otomatik hesaplanacaktır.',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            ...['TRY', 'USD', 'EUR', 'GBP'].map((targetCurrency) {
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: Colors.blue.withOpacity(0.1),
                  child: Text(_getCurrencySymbol(targetCurrency)),
                ),
                title: Text('$targetCurrency (${_getCurrencySymbol(targetCurrency)})'),
                trailing: sourceCurrency == targetCurrency
                    ? const Icon(Icons.check_circle, color: Colors.green)
                    : const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () async {
                  Navigator.pop(ctx);
                  if (sourceCurrency != targetCurrency) {
                    // Çeviri yap
                    final converted = await CurrencyService.convertCurrency(
                      currentPrice,
                      sourceCurrency,
                      targetCurrency,
                    );
                    
                    if (converted != null) {
                      setState(() {
                        _unitPriceController.text = converted.toStringAsFixed(2);
                        _itemCurrency = targetCurrency;
                      });
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Fiyat $targetCurrency kuruna çevrildi',
                          ),
                          backgroundColor: Colors.green,
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Kur bilgisi alınamadı!'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  }
                },
              );
            }).toList(),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('İptal'),
          ),
        ],
      ),
    );
  }

  void _addProductToInvoice() {
    if (_selectedProduct == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Lütfen bir ürün seçin'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final quantity = double.tryParse(_quantityController.text) ?? 0;
    final unitPrice = double.tryParse(_unitPriceController.text) ?? 0;
    final discountRate = double.tryParse(_discountRateController.text);
    final taxRate = double.tryParse(_taxRateController.text) ?? 0;

    if (quantity <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Miktar 0\'dan büyük olmalıdır'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (unitPrice <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Birim fiyat 0\'dan büyük olmalıdır'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final invoiceItem = InvoiceItem(
      invoiceId: null, // Fatura kaydedilirken atanacak
      product: _selectedProduct!,
      quantity: quantity,
      unitPrice: unitPrice,
      discountRate: discountRate,
      taxRate: taxRate,
      currency: _itemCurrency ?? _selectedProduct!.currency, // ✅ Para birimi
      notes: _itemNotesController.text.trim().isEmpty
          ? null
          : _itemNotesController.text.trim(),
    );

    setState(() {
      _invoiceItems.add(invoiceItem);
    });

    // Formu temizle
    _quantityController.clear();
    _unitPriceController.clear();
    _discountRateController.clear();
    _taxRateController.clear();
    _itemNotesController.clear();
    _selectedProduct = null;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Ürün faturaya eklendi'),
        backgroundColor: Colors.green,
      ),
    );
  }

  void _removeProductFromInvoice(int index) {
    setState(() {
      _invoiceItems.removeAt(index);
    });
  }

  double _calculateSubtotal() {
    return _invoiceItems.fold(0.0, (sum, item) => sum + item.subtotal);
  }

  double _calculateTotalDiscount() {
    return _invoiceItems.fold(0.0, (sum, item) => sum + item.discountAmount);
  }

  double _calculateTotalTax() {
    return _invoiceItems.fold(0.0, (sum, item) => sum + item.taxAmount);
  }

  double _calculateTotal() {
    return _invoiceItems.fold(0.0, (sum, item) => sum + item.totalAmount);
  }

  Future<void> _saveInvoice() async {
    debugPrint('🔄 _saveInvoice başladı');

    if (!_formKey.currentState!.validate()) {
      debugPrint('❌ Form validasyonu başarısız');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Lütfen kırmızı ile işaretlenen zorunlu alanları doldurunuz.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (_invoiceItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('En az bir ürün eklemelisiniz'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final hybridProvider = context.read<HybridProvider>();

      // Önce müşteriyi kaydet (eğer yeni müşteriyse)
      Customer customer;
      if (_selectedCustomerId != null) {
        // Mevcut müşteri seçilmişse
        customer = hybridProvider.customers.firstWhere(
          (c) => c.id.toString() == _selectedCustomerId,
        );
      } else {
        // Yeni müşteri oluştur
        customer = Customer(
          name: _customerNameController.text.trim(),
          email: _customerEmailController.text.trim(),
          phone: _customerPhoneController.text.trim(),
          address: _customerAddressController.text.trim(),
          taxNumber: _customerTaxNumberController.text.trim(),
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        // Müşteriyi veritabanına kaydet
        final success = await hybridProvider.addCustomer(customer);
        if (!success) {
          throw Exception('Müşteri kaydedilemedi');
        }

        // Yeni eklenen müşteriyi al
        customer = hybridProvider.customers.last;
      }

      // Fatura oluştur veya güncelle
      Invoice invoice;
      bool success;

      if (widget.invoice != null) {
        // Düzenleme modu - mevcut faturayı güncelle
        debugPrint('🔄 Fatura güncelleme başladı');
        debugPrint('📄 Orijinal fatura ID: ${widget.invoice!.id}');
        debugPrint(
          '📄 Orijinal fatura numarası: ${widget.invoice!.invoiceNumber}',
        );
        debugPrint('📦 Mevcut ürün sayısı: ${_invoiceItems.length}');

        // Debug: Her ürünün invoiceId'sini kontrol et
        for (int i = 0; i < _invoiceItems.length; i++) {
          debugPrint(
            '  Ürün $i: ${_invoiceItems[i].productName ?? _invoiceItems[i].product?.name ?? 'Ürün'}, InvoiceId: ${_invoiceItems[i].invoiceId}',
          );
        }

        invoice = widget.invoice!.copyWith(
          invoiceNumber: _invoiceNumberController.text.trim(),
          customer: customer,
          items: _invoiceItems,
          currency: _invoiceCurrency, // ✅ Güncellendi
          updatedAt: DateTime.now(),
        );

        debugPrint('📄 Güncellenmiş fatura ID: ${invoice.id}');
        debugPrint('📄 Güncellenmiş fatura numarası: ${invoice.invoiceNumber}');

        success = await hybridProvider.updateInvoice(invoice);
        if (!success) {
          throw Exception('Fatura güncellenemedi');
        }
        debugPrint('✅ Fatura başarıyla güncellendi');
      } else {
        // Yeni fatura oluştur
        invoice = Invoice(
          invoiceNumber: _invoiceNumberController.text.trim(),
          customer: customer,
          invoiceDate: DateTime.now(),
          dueDate: DateTime.now().add(const Duration(days: 30)), // 30 gün vade
          items: _invoiceItems,
          currency: _invoiceCurrency, // ✅ Eklendi
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
        success = await hybridProvider.addInvoice(invoice);
        if (!success) {
          throw Exception('Fatura kaydedilemedi');
        }
        debugPrint('✅ Fatura başarıyla oluşturuldu');
      }

      debugPrint('✅ Fatura başarıyla kaydedildi');
      debugPrint('📄 Fatura Numarası: ${invoice.invoiceNumber}');
      debugPrint('👤 Müşteri: ${customer.name}');
      debugPrint('📦 Ürün Sayısı: ${_invoiceItems.length}');
      debugPrint('💰 Toplam Tutar: ₺${_calculateTotal().toStringAsFixed(2)}');

      // ✅ Eklendi: Seçilen "Fatura Detayları" maddelerini kaydet
      try {
        int? invoiceId;
        // Düzenleme modunda ID parse edilebilir
        if (widget.invoice?.id != null) {
          invoiceId = int.tryParse(widget.invoice!.id!);
        }
        // Yeni oluşturulduysa ya da parse edilemediyse, fatura numarasıyla bul
        if (invoiceId == null) {
          final db = await HybridDatabaseService().database;
          final rows = await db.query(
            'invoices',
            columns: ['id'],
            where: 'invoice_number = ?',
            whereArgs: [_invoiceNumberController.text.trim()],
            limit: 1,
          );
          if (rows.isNotEmpty) {
            invoiceId = rows.first['id'] as int;
          }
        }
        if (invoiceId != null) {
          await _saveInvoiceTermsToDb(invoiceId);
        } else {
          debugPrint(
            '⚠ invoice_id bulunamadı; Fatura Detayları kaydedilemedi.',
          );
        }
      } catch (e) {
        debugPrint('⚠ Fatura Detayları kaydı hatası: $e');
      }

      if (mounted) {
        Navigator.of(context).pop(true);

        // Yeni fatura oluşturulduysa PDF önizleme ekranına yönlendir
        if (widget.invoice == null) {
          // Kısa bir gecikme ile PDF önizleme ekranını aç
          Future.delayed(const Duration(milliseconds: 500), () {
            if (mounted) {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => PdfPreviewScreen(invoice: invoice),
                ),
              );
            }
          });
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.invoice != null
                  ? 'Fatura başarıyla güncellendi!'
                  : 'Fatura başarıyla oluşturuldu! PDF önizleme açılıyor...',
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      debugPrint('❌ Fatura kaydetme hatası: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Hata: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    debugPrint('🔄 InvoiceFormScreen build çağrıldı');

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.invoice != null ? 'Faturayı Düzenle' : 'Yeni Fatura',
        ),
        actions: [
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            IconButton(icon: const Icon(Icons.save), onPressed: _saveInvoice),
        ],
      ),
      body: SafeArea(
        child: Consumer<HybridProvider>(
          builder: (context, hybridProvider, child) {
            return Form(
              key: _formKey,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Fatura Para Birimi Seçimi
                      DropdownButtonFormField<String>(
                        value: _invoiceCurrency,
                        decoration: const InputDecoration(
                          labelText: 'Fatura Para Birimi',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.monetization_on),
                        ),
                        items: ['TRY', 'USD', 'EUR', 'GBP'].map((currency) {
                          return DropdownMenuItem(
                            value: currency,
                            child: Text('$currency (${_getCurrencySymbol(currency)})'),
                          );
                        }).toList(),
                        onChanged: (value) {
                          if (value != null) {
                            setState(() {
                              _invoiceCurrency = value;
                            });
                          }
                        },
                      ),
                      const SizedBox(height: 16),

                      // Fatura Numarası
                      TextFormField(
                        controller: _invoiceNumberController,
                        decoration: const InputDecoration(
                          labelText: 'Fatura Numarası *',
                          border: OutlineInputBorder(),
                        ),
                        inputFormatters: [InvoiceNumberFormatter()],
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Fatura numarası gerekli';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      // Satıcı Şirket Seçimi
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Satıcı Şirket',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Consumer<HybridProvider>(
                                builder: (context, provider, _) {
                                  final companies = provider.companies;
                                  return DropdownButtonFormField<String>(
                                    value: _selectedCompanyId,
                                    decoration: const InputDecoration(
                                      labelText: 'Şirket Seçin',
                                      border: OutlineInputBorder(),
                                      prefixIcon: Icon(Icons.business),
                                    ),
                                    items: [
                                      const DropdownMenuItem<String>(
                                        value: null,
                                        child: Text('Varsayılan Profil'),
                                      ),
                                      ...companies.map(
                                        (c) => DropdownMenuItem(
                                          value: c.firebaseId,
                                          child: Text(c.name),
                                        ),
                                      ),
                                    ],
                                    onChanged: (val) {
                                      setState(() {
                                        _selectedCompanyId = val;
                                      });
                                      final selected = companies.firstWhere(
                                        (c) => c.firebaseId == val,
                                        orElse: () =>
                                            provider.selectedCompany ??
                                            (companies.isNotEmpty
                                                ? companies.first
                                                : null)!,
                                      );
                                      provider.selectCompany(
                                        val == null ? null : selected,
                                      );
                                    },
                                  );
                                },
                              ),
                              const SizedBox(height: 16),

                              // Seçili şirket detay bilgileri
                              Consumer<HybridProvider>(
                                builder: (context, provider, _) {
                                  return Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: Colors.blue[50],
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: Colors.blue[200]!,
                                      ),
                                    ),
                                    child: _buildCompanyDetails(provider),
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Kayıtlı Müşteri Seçimi
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Kayıtlı Müşteri Seçimi',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 8),
                              if (hybridProvider.isLoading)
                                const Center(
                                  child: Padding(
                                    padding: EdgeInsets.all(16.0),
                                    child: CircularProgressIndicator(),
                                  ),
                                )
                              else
                                DropdownButtonFormField<String>(
                                  value: _selectedCustomerId,
                                  decoration: const InputDecoration(
                                    labelText: 'Müşteri Seçin',
                                    border: OutlineInputBorder(),
                                    prefixIcon: Icon(Icons.person_search),
                                  ),
                                  items: () {
                                    final set = <String>{};
                                    final items = <DropdownMenuItem<String>>[];
                                    // Yeni müşteri seçeneği
                                    items.add(
                                      const DropdownMenuItem<String>(
                                        value: null,
                                        child: Text('Yeni Müşteri'),
                                      ),
                                    );
                                    // Tekilleştirilmiş müşteri listesi (firebaseId/id/name bazlı)
                                    for (final c in hybridProvider.customers) {
                                      final key =
                                          (c.firebaseId ?? c.id ?? c.name)
                                              .toString()
                                              .toLowerCase();
                                      if (set.add(key)) {
                                        items.add(
                                          DropdownMenuItem<String>(
                                            value: c.id?.toString(),
                                            child: Text(c.name),
                                          ),
                                        );
                                      }
                                    }
                                    return items;
                                  }(),
                                  onChanged: _onCustomerSelected,
                                ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Alıcı Bilgileri Başlığı
                      const Card(
                        child: Padding(
                          padding: EdgeInsets.all(16.0),
                          child: Text(
                            'Alıcı Bilgileri',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Alıcı Adı/Unvanı
                      TextFormField(
                        controller: _customerNameController,
                        decoration: const InputDecoration(
                          labelText: 'Alıcı Adı/Unvanı *',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.business),
                        ),
                        textCapitalization: TextCapitalization.words,
                        inputFormatters: [CapitalizeWordsFormatter()],
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Alıcı adı gerekli';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      // Adres
                      TextFormField(
                        controller: _customerAddressController,
                        decoration: const InputDecoration(
                          labelText: 'Adres *',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.location_on),
                        ),
                        maxLines: 3,
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Adres gerekli';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      // Telefon ve E-posta satırı
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _customerPhoneController,
                              decoration: const InputDecoration(
                                labelText: 'Telefon *',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.phone),
                              ),
                              keyboardType: TextInputType.phone,
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'Telefon gerekli';
                                }
                                return null;
                              },
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextFormField(
                              controller: _customerEmailController,
                              decoration: const InputDecoration(
                                labelText: 'E-posta *',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.email),
                              ),
                              keyboardType: TextInputType.emailAddress,
                              inputFormatters: [LowerCaseFormatter()],
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'E-posta gerekli';
                                }
                                if (!RegExp(
                                  r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$',
                                ).hasMatch(value)) {
                                  return 'Geçerli e-posta adresi girin';
                                }
                                return null;
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Vergi Numarası
                      TextFormField(
                        controller: _customerTaxNumberController,
                        decoration: const InputDecoration(
                          labelText: 'Vergi Numarası (VKN/TCKN)',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.receipt_long),
                        ),
                        keyboardType: TextInputType.number,
                      ),
                      const SizedBox(height: 16),

                      // ✅ Eklendi: Fatura Detayları (maddeler)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Fatura Detayları',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 12),

                              // Çoklu seçim chip’leri
                              if (_terms.isEmpty)
                                const Text(
                                  'Seçenek bulunamadı.',
                                  style: TextStyle(color: Colors.grey),
                                )
                              else
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: _terms.map((t) {
                                    final id = t['id'] as int;
                                    final selected = _selectedTermIds.contains(
                                      id,
                                    );
                                    return FilterChip(
                                      label: Text(t['title'] as String),
                                      selected: selected,
                                      onSelected: (on) {
                                        setState(() {
                                          if (on) {
                                            _selectedTermIds.add(id);
                                          } else {
                                            _selectedTermIds.remove(id);
                                          }
                                        });
                                      },
                                    );
                                  }).toList(),
                                ),

                              const SizedBox(height: 12),

                              // Sayısal değer isteyen seçili maddeler için inputlar
                              Column(
                                children: _terms
                                    .where(
                                      (t) =>
                                          (t['requires_number'] ?? 0) == 1 &&
                                          _selectedTermIds.contains(
                                            t['id'] as int,
                                          ),
                                    )
                                    .map((t) {
                                      final id = t['id'] as int;
                                      final label =
                                          (t['number_label'] as String?) ??
                                          'Değer';
                                      final unit = (t['unit'] as String?) ?? '';
                                      final initial =
                                          _termValues[id]?.toString() ?? '';
                                      return Padding(
                                        padding: const EdgeInsets.only(
                                          bottom: 8.0,
                                        ),
                                        child: Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                '$label ${unit.isNotEmpty ? '($unit)' : ''}',
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            SizedBox(
                                              width: 140,
                                              child: TextFormField(
                                                initialValue: initial,
                                                decoration:
                                                    const InputDecoration(
                                                      isDense: true,
                                                      border:
                                                          OutlineInputBorder(),
                                                    ),
                                                keyboardType:
                                                    TextInputType.number,
                                                inputFormatters: [
                                                  FilteringTextInputFormatter.allow(
                                                    RegExp(r'[0-9.]'),
                                                  ),
                                                ],
                                                onChanged: (v) =>
                                                    _termValues[id] =
                                                        double.tryParse(v),
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    })
                                    .toList(),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 32),

                      // Ürün Seçimi Bölümü
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Ürün Seçimi',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 16),

                              // Ürün Seçimi
                              if (hybridProvider.isLoading)
                                const Center(
                                  child: Padding(
                                    padding: EdgeInsets.all(16.0),
                                    child: CircularProgressIndicator(),
                                  ),
                                )
                              else
                                DropdownButtonFormField<Product>(
                                  value: _selectedProduct,
                                  decoration: const InputDecoration(
                                    labelText: 'Ürün Seçin *',
                                    border: OutlineInputBorder(),
                                    prefixIcon: Icon(Icons.inventory),
                                  ),
                                  items: () {
                                    final selectedCompanyId =
                                        _selectedCompanyId ??
                                        hybridProvider
                                            .selectedCompany
                                            ?.firebaseId;
                                    final list = selectedCompanyId == null
                                        ? hybridProvider.products
                                        : hybridProvider.products
                                              .where(
                                                (p) =>
                                                    p.companyId ==
                                                    selectedCompanyId,
                                              )
                                              .toList();
                                    return list.map((product) {
                                      return DropdownMenuItem<Product>(
                                        value: product,
                                        child: Text(
                                          '${product.name} (${_getCurrencySymbol(product.currency)}${product.price.toStringAsFixed(2)})',
                                        ),
                                      );
                                    }).toList();
                                  }(),
                                  onChanged: _onProductSelected,
                                ),
                              const SizedBox(height: 16),

                              // Ürün Detayları
                              if (_selectedProduct != null) ...[
                                // ✅ Eklendi: Para Birimi Değiştirme Butonu
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 16.0),
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: InkWell(
                                      onTap: _showCurrencyConversionDialog,
                                      borderRadius: BorderRadius.circular(8),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 8,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.blue.withOpacity(0.1),
                                          borderRadius: BorderRadius.circular(8),
                                          border: Border.all(
                                            color: Colors.blue.withOpacity(0.3),
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              Icons.currency_exchange,
                                              size: 16,
                                              color: Colors.blue[700],
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              'Para Birimi: ${_itemCurrency ?? _selectedProduct!.currency} (${_getCurrencySymbol(_itemCurrency ?? _selectedProduct!.currency)}) - Değiştir',
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
                                                color: Colors.blue[700],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                Row(
                                  children: [
                                    Expanded(
                                      child: TextFormField(
                                        controller: _quantityController,
                                        decoration: const InputDecoration(
                                          labelText: 'Miktar *',
                                          border: OutlineInputBorder(),
                                          prefixIcon: Icon(
                                            Icons.format_list_numbered,
                                          ),
                                        ),
                                        keyboardType: TextInputType.number,
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: TextFormField(
                                        controller: _unitPriceController,
                                        decoration: InputDecoration(
                                          labelText: 'Birim Fiyat *',
                                          border: OutlineInputBorder(),
                                          prefixIcon: Icon(
                                            (_itemCurrency ?? _selectedProduct?.currency) == 'USD'
                                                ? Icons.attach_money
                                                : (_itemCurrency ?? _selectedProduct?.currency) ==
                                                      'EUR'
                                                ? Icons.euro
                                                : (_itemCurrency ?? _selectedProduct?.currency) ==
                                                      'GBP'
                                                ? Icons.currency_pound
                                                : Icons.currency_lira,
                                            color: Colors.grey[600],
                                          ),
                                        ),
                                        keyboardType: TextInputType.number,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),

                                Row(
                                  children: [
                                    Expanded(
                                      child: TextFormField(
                                        controller: _discountRateController,
                                        decoration: const InputDecoration(
                                          labelText: 'İskonto Oranı (%)',
                                          border: OutlineInputBorder(),
                                          prefixIcon: Icon(Icons.discount),
                                          suffixText: '%',
                                        ),
                                        keyboardType: TextInputType.number,
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: TextFormField(
                                        controller: _taxRateController,
                                        decoration: const InputDecoration(
                                          labelText: 'KDV Oranı (%) *',
                                          border: OutlineInputBorder(),
                                          prefixIcon: Icon(Icons.receipt),
                                          suffixText: '%',
                                        ),
                                        keyboardType: TextInputType.number,
                                        inputFormatters: [
                                          FilteringTextInputFormatter
                                              .digitsOnly,
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),

                                TextFormField(
                                  controller: _itemNotesController,
                                  decoration: const InputDecoration(
                                    labelText: 'Ürün Notu',
                                    border: OutlineInputBorder(),
                                    prefixIcon: Icon(Icons.note),
                                  ),
                                  maxLines: 2,
                                ),
                                const SizedBox(height: 16),

                                ElevatedButton.icon(
                                  onPressed: _addProductToInvoice,
                                  icon: const Icon(Icons.add),
                                  label: const Text('Ürünü Faturaya Ekle'),
                                  style: ElevatedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Eklenen Ürünler Listesi
                      if (_invoiceItems.isNotEmpty) ...[
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text(
                                      'Eklenen Ürünler',
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    Text(
                                      '${_invoiceItems.length} ürün',
                                      style: const TextStyle(
                                        color: Colors.grey,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),

                                ..._invoiceItems.asMap().entries.map((entry) {
                                  final index = entry.key;
                                  final item = entry.value;
                                  return Container(
                                    margin: const EdgeInsets.only(bottom: 12),
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      border: Border.all(
                                        color: Colors.grey[300]!,
                                      ),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          flex: 3,
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                item.productName ??
                                                    item.product?.name ??
                                                    'Ürün',
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                              if (item.notes != null) ...[
                                                const SizedBox(height: 4),
                                                Text(
                                                  'Not: ${item.notes!}',
                                                  style: const TextStyle(
                                                    fontSize: 12,
                                                    color: Colors.grey,
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                        Expanded(
                                          child: Text(
                                            '${item.quantity} ${item.product?.unit ?? 'adet'}',
                                            textAlign: TextAlign.center,
                                          ),
                                        ),
                                        Expanded(
                                          child: Text(
                                            '${_getCurrencySymbol(item.currency ?? item.product?.currency ?? 'TRY')}${item.unitPrice.toStringAsFixed(2)}',
                                            textAlign: TextAlign.center,
                                          ),
                                        ),
                                        Expanded(
                                          child: Text(
                                            '${_getCurrencySymbol(item.currency ?? item.product?.currency ?? 'TRY')}${item.totalAmount.toStringAsFixed(2)}',
                                            textAlign: TextAlign.right,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                        IconButton(
                                          icon: const Icon(
                                            Icons.delete,
                                            color: Colors.red,
                                          ),
                                          onPressed: () =>
                                              _removeProductFromInvoice(index),
                                        ),
                                      ],
                                    ),
                                  );
                                }),

                                const Divider(),

                                // Toplam Bilgileri
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text('Ara Toplam:'),
                                    Text(
                                      '$_invoiceCurrencySymbol${_calculateSubtotal().toStringAsFixed(2)}',
                                    ),
                                  ],
                                ),
                                if (_calculateTotalDiscount() > 0) ...[
                                  const SizedBox(height: 8),
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      const Text('Toplam İskonto:'),
                                      Text(
                                        '-$_invoiceCurrencySymbol${_calculateTotalDiscount().toStringAsFixed(2)}',
                                        style: const TextStyle(
                                          color: Colors.green,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                                const SizedBox(height: 8),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text('KDV Toplamı:'),
                                    Text(
                                      '$_invoiceCurrencySymbol${_calculateTotalTax().toStringAsFixed(2)}',
                                    ),
                                  ],
                                ),
                                const Divider(),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text(
                                      'TOPLAM:',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 18,
                                      ),
                                    ),
                                    Text(
                                      '$_invoiceCurrencySymbol${_calculateTotal().toStringAsFixed(2)}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 18,
                                        color: Colors.blue,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],

                      // Kaydet Butonu
                      ElevatedButton(
                        onPressed: _isLoading ? null : _saveInvoice,
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        child: _isLoading
                            ? const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        Colors.white,
                                      ),
                                    ),
                                  ),
                                  SizedBox(width: 8),
                                  Text('Kaydediliyor...'),
                                ],
                              )
                            : const Text(
                                'Faturayı Kaydet',
                                style: TextStyle(fontSize: 16),
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildCompanyDetails(HybridProvider provider) {
    // Seçili şirketi belirle
    final selectedCompany = _selectedCompanyId != null
        ? provider.companies.firstWhere(
            (c) => c.firebaseId == _selectedCompanyId,
            orElse: () => provider.selectedCompany!,
          )
        : null;

    final user = provider.appUser;

    if (selectedCompany != null) {
      // Şirket profili seçilmişse şirket bilgilerini göster
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CompanyLogoAvatar(
                logoPathOrUrl: selectedCompany.logo,
                size: 32,
                circular: false,
                backgroundColor: Colors.blue[100],
                fallbackIcon: Icons.business,
                fallbackIconColor: Colors.blue[700],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      selectedCompany.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: Colors.blue,
                      ),
                    ),
                    const Text(
                      'Seçili şirket profili - Bu bilgiler faturada görünecek',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(color: Colors.blue),
          const SizedBox(height: 8),

          // Şirket detay bilgileri
          _buildDetailRow('Adres', selectedCompany.address ?? 'Belirtilmemiş'),
          _buildDetailRow('Telefon', selectedCompany.phone ?? 'Belirtilmemiş'),
          _buildDetailRow('E-posta', selectedCompany.email ?? 'Belirtilmemiş'),
          _buildDetailRow(
            'Vergi No',
            selectedCompany.taxNumber ?? 'Belirtilmemiş',
          ),
        ],
      );
    } else {
      // Varsayılan profil (kullanıcı bilgileri)
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Icon(Icons.person, size: 16, color: Colors.grey[600]),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user?.fullName ?? user?.email ?? 'Kullanıcı',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: Colors.grey,
                      ),
                    ),
                    const Text(
                      'Varsayılan profil - Kullanıcı bilgileri kullanılacak',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(color: Colors.grey),
          const SizedBox(height: 8),

          // Kullanıcı detay bilgileri
          _buildDetailRow('Adres', user?.address ?? 'Belirtilmemiş'),
          _buildDetailRow('Telefon', user?.phone ?? 'Belirtilmemiş'),
          _buildDetailRow('E-posta', user?.email ?? 'Belirtilmemiş'),
        ],
      );
    }
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              '$label:',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: Colors.grey,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 13, color: Colors.black87),
            ),
          ),
        ],
      ),
    );
  }
}
