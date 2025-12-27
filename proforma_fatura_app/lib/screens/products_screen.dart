import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../constants/app_constants.dart';
import '../utils/text_formatter.dart';
import '../widgets/company_logo_avatar.dart';

import '../models/product.dart';
import '../providers/hybrid_provider.dart';
import 'product_form_screen.dart';

class ProductsScreen extends StatefulWidget {
  final VoidCallback? onBackToHome;

  const ProductsScreen({super.key, this.onBackToHome});

  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends State<ProductsScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<dynamic> _filteredProducts = [];
  String? _selectedCategoryFilter;
  final bool _showAllProducts = false; // Geçici olarak tüm ürünleri göster

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadInitialData();
    });
  }

  Future<void> _loadInitialData() async {
    if (!mounted) return;
    try {
      final hybridProvider = context.read<HybridProvider>();
      await hybridProvider.loadProducts();
      if (mounted) {
        await hybridProvider.loadCategories();
        await hybridProvider.loadCompanyProfiles();
        // Şirket bazlı filtrelemeyi başlat
        _filterProducts(_searchController.text);
      }
    } catch (e) {
      debugPrint('❌ Error loading initial data: $e');
      // Error handling for initState
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _filterProducts(String query) {
    if (!mounted) return;

    try {
      // BuildContext'i güvenli şekilde kullan
      final hybridProvider = context.read<HybridProvider>();

      final allProducts = hybridProvider.products;
      List<Product> filtered = List.from(allProducts); // Yeni liste oluştur

      // Aktif şirkete göre filtrele - ŞİRKET SEÇİLMEMİŞSE TÜM ÜRÜNLERİ GÖSTER
      final selectedCompany = hybridProvider.selectedCompany;
      if (selectedCompany != null && !_showAllProducts) {
        // Sadece query değiştiğinde debug yap
        if (query.isNotEmpty || _selectedCategoryFilter != null) {
          debugPrint('🔍 Filtering products for: ${selectedCompany.name}');
        }

        filtered = filtered
            .where(
              (product) =>
                  product.companyId == selectedCompany.firebaseId ||
                  (product.companyId == null || product.companyId!.isEmpty),
            )
            .toList();
      }
      // _showAllProducts true ise tüm ürünleri göster (filtreleme yapma)

      // Kategori filtresi
      if (_selectedCategoryFilter != null && filtered.isNotEmpty) {
        filtered = filtered
            .where((product) => product.category == _selectedCategoryFilter)
            .toList();
      }

      // Arama filtresi
      if (query.isNotEmpty && filtered.isNotEmpty) {
        filtered = filtered.where((product) {
          return product.name.toLowerCase().contains(query.toLowerCase()) ||
              (product.description?.toLowerCase().contains(
                    query.toLowerCase(),
                  ) ??
                  false) ||
              (product.barcode?.contains(query) ?? false);
        }).toList();
      }

      if (mounted) {
        setState(() {
          _filteredProducts = filtered;
        });
      }
    } catch (e) {
      debugPrint('❌ Error filtering products: $e');
      // Error handling for _filterProducts
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(AppConstants.productsTitle),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            // Ana sayfaya (Dashboard) dön
            widget.onBackToHome?.call();
          },
        ),
      ),
      body: Column(
        children: [
          // Arama çubuğu
          Padding(
            padding: const EdgeInsets.all(AppConstants.paddingMedium),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Ürün ara...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          if (mounted) {
                            _filterProducts('');
                          }
                        },
                      )
                    : null,
              ),
              onChanged: (value) {
                if (mounted) {
                  _filterProducts(value);
                }
              },
            ),
          ),

          // Kategori filtresi
          Consumer<HybridProvider>(
            builder: (context, hybridProvider, child) {
              final cats = hybridProvider.categories;
              final categories = ['Tümü', ...cats];
              return Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppConstants.paddingMedium,
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const Text(
                          'Kategori: ',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: DropdownButtonFormField<String?>(
                            value: _selectedCategoryFilter,
                            decoration: const InputDecoration(
                              labelText: 'Kategori',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            items: categories
                                .map(
                                  (c) => DropdownMenuItem<String?>(
                                    value: c == 'Tümü' ? null : c,
                                    child: Text(c),
                                  ),
                                )
                                .toList(),
                            onChanged: (val) {
                              setState(() => _selectedCategoryFilter = val);
                              _filterProducts(_searchController.text);
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // Estetik Şirket Seçimi Card'ı
                    Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: hybridProvider.selectedCompany != null
                              ? AppConstants.primaryColor.withOpacity(0.05)
                              : Colors.grey[50],
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: hybridProvider.selectedCompany != null
                                ? AppConstants.primaryColor.withOpacity(0.3)
                                : Colors.grey[300]!,
                            width: 1.5,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                CompanyLogoAvatar(
                                  logoPathOrUrl:
                                      hybridProvider.selectedCompany?.logo,
                                  size: 32,
                                  circular: true,
                                  backgroundColor:
                                      (hybridProvider.selectedCompany != null)
                                      ? AppConstants.primaryColor.withOpacity(
                                          0.2,
                                        )
                                      : Colors.grey[400],
                                  fallbackIcon: Icons.business,
                                  fallbackIconColor:
                                      (hybridProvider.selectedCompany != null)
                                      ? AppConstants.primaryColor
                                      : Colors.white,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Aktif Şirket',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey[600],
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        hybridProvider.selectedCompany?.name ??
                                            'Şirket Seçilmemiş',
                                        style: TextStyle(
                                          fontSize: 16,
                                          color:
                                              hybridProvider.selectedCompany !=
                                                  null
                                              ? AppConstants.primaryColor
                                              : Colors.grey[700],
                                          fontWeight: FontWeight.w600,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                                // Status indicator
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color:
                                        hybridProvider.selectedCompany != null
                                        ? Colors.green[100]
                                        : Colors.orange[100],
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        hybridProvider.selectedCompany != null
                                            ? Icons.check_circle
                                            : Icons.warning,
                                        size: 14,
                                        color:
                                            hybridProvider.selectedCompany !=
                                                null
                                            ? Colors.green[700]
                                            : Colors.orange[700],
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        hybridProvider.selectedCompany != null
                                            ? 'Aktif'
                                            : 'Seçin',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color:
                                              hybridProvider.selectedCompany !=
                                                  null
                                              ? Colors.green[700]
                                              : Colors.orange[700],
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            if (hybridProvider.selectedCompany == null) ...[
                              const SizedBox(height: 12),
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.orange[50],
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: Colors.orange[200]!,
                                    width: 1,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.info_outline,
                                      size: 16,
                                      color: Colors.orange[700],
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        'Ürünleri görmek için profil sayfasından şirket seçin',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.orange[700],
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ] else ...[
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Icon(
                                    Icons.inventory_2,
                                    size: 14,
                                    color: AppConstants.primaryColor,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Bu şirkete ait ürünler gösteriliyor',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: AppConstants.primaryColor,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),

          // Filtreleme temizleme butonu
          if (_selectedCategoryFilter != null ||
              _searchController.text.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppConstants.paddingMedium,
                vertical: AppConstants.paddingSmall,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        setState(() {
                          _selectedCategoryFilter = null;
                          _searchController.clear();
                        });
                        if (mounted) {
                          _filterProducts('');
                        }
                      },
                      icon: const Icon(Icons.clear, size: 16),
                      label: const Text('Filtreleri Temizle'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.grey[200],
                        foregroundColor: Colors.grey[700],
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // Ürün listesi
          Expanded(
            child: Consumer<HybridProvider>(
              builder: (context, hybridProvider, child) {
                try {
                  if (hybridProvider.isLoading) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (hybridProvider.error != null) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.error_outline,
                            size: 64,
                            color: AppConstants.errorColor,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            hybridProvider.error!,
                            style: AppConstants.bodyStyle,
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: () {
                              hybridProvider.loadProducts();
                            },
                            child: const Text('Tekrar Dene'),
                          ),
                        ],
                      ),
                    );
                  }

                  // Şirket seçilip seçilmediğini kontrol et
                  final selectedCompany = hybridProvider.selectedCompany;
                  final hasCompanies = hybridProvider.companies.isNotEmpty;

                  // Şirket ID'si eksik legacy ürünleri gizleme yerine varsayılan olarak göster

                  // Şirket hiç yoksa uyarı göster (ilk giriş deneyimi)
                  if (!hasCompanies) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.business_outlined,
                            size: 64,
                            color: Colors.grey,
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'Ürünleri görüntülemek için önce şirket ekleyiniz',
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 12),
                          ElevatedButton.icon(
                            onPressed: () {
                              Navigator.pushNamed(context, '/profile');
                            },
                            icon: const Icon(Icons.add_business),
                            label: const Text('Şirket Ekle'),
                          ),
                        ],
                      ),
                    );
                  }
                  // Şirketler var ama seçili yoksa (teorik olarak provider seçer), yine de güvenli ol
                  if (selectedCompany == null) {
                    debugPrint('ℹ️ No company selected - showing all products');
                  }

                  // Filtreleme durumuna göre ürünleri belirle
                  final products =
                      (_searchController.text.isNotEmpty ||
                          _selectedCategoryFilter != null)
                      ? _filteredProducts
                      : (selectedCompany == null
                            ? hybridProvider.products
                            : hybridProvider.products
                                  .where(
                                    (p) =>
                                        p.companyId ==
                                        selectedCompany.firebaseId,
                                  )
                                  .toList());

                  if (products.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.inventory_2_outlined,
                            size: 64,
                            color: Colors.grey,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _searchController.text.isEmpty &&
                                    _selectedCategoryFilter == null
                                ? 'Henüz ürün bulunmuyor'
                                : 'Arama sonucu bulunamadı',
                            style: AppConstants.bodyStyle,
                          ),
                          if (_searchController.text.isEmpty &&
                              _selectedCategoryFilter == null) ...[
                            const SizedBox(height: 16),
                            ElevatedButton(
                              onPressed: () async {
                                final navigatorContext = context;
                                final result =
                                    await Navigator.of(navigatorContext).push(
                                      MaterialPageRoute(
                                        builder: (context) =>
                                            const ProductFormScreen(),
                                      ),
                                    );
                                if (result == true &&
                                    mounted &&
                                    navigatorContext.mounted) {
                                  final hybridProvider = navigatorContext
                                      .read<HybridProvider>();
                                  await hybridProvider.loadProducts();
                                  _filterProducts(_searchController.text);
                                }
                              },
                              child: const Text('İlk Ürünü Ekle'),
                            ),
                          ],
                        ],
                      ),
                    );
                  }

                  return RefreshIndicator(
                    onRefresh: () async {
                      await hybridProvider.loadProducts();
                      if (!mounted) return;
                      _filterProducts(_searchController.text);
                    },
                    child: ListView.builder(
                      padding: const EdgeInsets.all(AppConstants.paddingMedium),
                      itemCount: products.length,
                      itemBuilder: (context, index) {
                        final product = products[index];
                        return Card(
                          margin: const EdgeInsets.only(
                            bottom: AppConstants.paddingSmall,
                          ),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: AppConstants.getCategoryColor(
                                product.category ?? 'Diğer',
                              ),
                              child: Text(
                                TextFormatter.initialTr(product.name),
                                style: const TextStyle(
                                  color: AppConstants.textOnPrimary,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            title: Text(
                              product.name,
                              style: AppConstants.bodyStyle.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (product.description?.isNotEmpty == true)
                                  Text(
                                    product.description!,
                                    style: AppConstants.captionStyle,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Text(
                                      '${product.price.toStringAsFixed(2)} ${product.currency}',
                                      style: AppConstants.bodyStyle.copyWith(
                                        fontWeight: FontWeight.w500,
                                        color: AppConstants.primaryColor,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      '/ ${product.unit}',
                                      style: AppConstants.captionStyle,
                                    ),
                                  ],
                                ),
                                if (product.category != null) ...[
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      Container(
                                        width: 8,
                                        height: 8,
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        product.category!,
                                        style: AppConstants.captionStyle
                                            .copyWith(fontSize: 12),
                                      ),
                                    ],
                                  ),
                                ],
                                const SizedBox(height: 4),
                                Builder(
                                  builder: (context) {
                                    final companies = hybridProvider.companies;
                                    String txt = 'Şirket: -';

                                    if (product.companyId != null &&
                                        companies.isNotEmpty) {
                                      try {
                                        final comp = companies.firstWhere(
                                          (c) =>
                                              c.firebaseId == product.companyId,
                                        );
                                        txt = 'Şirket: ${comp.name}';
                                      } catch (e) {
                                        // Şirket bulunamadı, varsayılan metni kullan
                                        txt = 'Şirket: Bulunamadı';
                                      }
                                    }
                                    return Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: AppConstants.secondaryColor
                                            .withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        txt,
                                        style: AppConstants.captionStyle
                                            .copyWith(fontSize: 12),
                                      ),
                                    );
                                  },
                                ),
                              ],
                            ),
                            trailing: PopupMenuButton<String>(
                              onSelected: (value) async {
                                if (!mounted) return;

                                switch (value) {
                                  case 'edit':
                                    final navigatorContext = context;

                                    // Kategorilerin yüklendiğinden emin ol
                                    final hybridProvider = navigatorContext
                                        .read<HybridProvider>();
                                    if (hybridProvider.categories.isEmpty) {
                                      debugPrint(
                                        '🔄 Düzenleme için kategoriler yükleniyor...',
                                      );
                                      await hybridProvider.loadCategories();
                                      debugPrint(
                                        '✅ ${hybridProvider.categories.length} kategori yüklendi',
                                      );
                                    }

                                    // ignore: use_build_context_synchronously
                                    final result =
                                        // ignore: use_build_context_synchronously
                                        await Navigator.of(
                                          navigatorContext,
                                        ).push(
                                          MaterialPageRoute(
                                            builder: (context) =>
                                                ProductFormScreen(
                                                  product: product,
                                                ),
                                          ),
                                        );
                                    if (result == true &&
                                        mounted &&
                                        navigatorContext.mounted) {
                                      await hybridProvider.loadProducts();
                                      // Kategori filtresini sıfırla ki ürün hemen listede görünsün
                                      setState(() {
                                        _selectedCategoryFilter = null;
                                      });
                                      if (!mounted) return;
                                      _filterProducts(_searchController.text);
                                    }
                                    break;
                                  case 'delete':
                                    _showDeleteDialog(product);
                                    break;
                                }
                              },
                              itemBuilder: (context) => [
                                const PopupMenuItem(
                                  value: 'edit',
                                  child: Row(
                                    children: [
                                      Icon(Icons.edit, size: 16),
                                      SizedBox(width: 8),
                                      Text('Düzenle'),
                                    ],
                                  ),
                                ),
                                const PopupMenuItem(
                                  value: 'delete',
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.delete,
                                        size: 16,
                                        color: AppConstants.errorColor,
                                      ),
                                      SizedBox(width: 8),
                                      Text(
                                        'Sil',
                                        style: TextStyle(
                                          color: AppConstants.errorColor,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  );
                } catch (e) {
                  debugPrint('❌ ProductsScreen builder error: $e');
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.error_outline,
                          size: 48,
                          color: Colors.red,
                        ),
                        const SizedBox(height: 12),
                        const Text('Ürünler yüklenirken bir hata oluştu'),
                      ],
                    ),
                  );
                }
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final navigatorContext = context;

          // Kategorilerin yüklendiğinden emin ol
          final hybridProvider = navigatorContext.read<HybridProvider>();
          if (hybridProvider.categories.isEmpty) {
            debugPrint('🔄 Kategoriler yükleniyor...');
            await hybridProvider.loadCategories();
            debugPrint(
              '✅ ${hybridProvider.categories.length} kategori yüklendi',
            );
          }

          // ignore: use_build_context_synchronously
          final result = await Navigator.of(navigatorContext).push(
            MaterialPageRoute(builder: (context) => const ProductFormScreen()),
          );
          // Eğer ürün eklendi/güncellendi ise listeyi yeniden yükle
          if (result == true && mounted && navigatorContext.mounted) {
            await hybridProvider.loadProducts();
            setState(() {
              _selectedCategoryFilter = null;
            });
            if (!mounted) return;
            _filterProducts(_searchController.text);
          }
        },
        backgroundColor: AppConstants.primaryColor,
        child: const Icon(Icons.add, color: AppConstants.textOnPrimary),
      ),
    );
  }

  void _showDeleteDialog(Product product) {
    final dialogContext = context;
    showDialog(
      context: dialogContext,
      builder: (context) => AlertDialog(
        title: const Text('Ürünü Sil'),
        content: Text(
          '${product.name} ürününü silmek istediğinizden emin misiniz?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('İptal'),
          ),
          TextButton(
            onPressed: () async {
              // HybridProvider'ı dialog kapatılmadan önce al
              final hybridProvider = dialogContext.read<HybridProvider>();
              Navigator.of(context).pop();
              if (mounted && product.id != null) {
                await hybridProvider.deleteProduct(int.parse(product.id!));
                // Silme sonrası listeyi yenile
                if (!mounted) return;
                _filterProducts(_searchController.text);
              }
            },
            style: TextButton.styleFrom(
              foregroundColor: AppConstants.errorColor,
            ),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
  }
}
