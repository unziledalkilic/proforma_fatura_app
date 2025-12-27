import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../constants/app_constants.dart';
import '../providers/hybrid_provider.dart';
import '../models/user.dart';
import '../utils/text_formatter.dart';
import 'company_management_screen.dart';
import '../widgets/company_logo_avatar.dart';

// AddCompanyScreen import'u company_management_screen.dart içinde

class ProfileScreen extends StatefulWidget {
  final VoidCallback? onBackToHome;

  const ProfileScreen({super.key, this.onBackToHome});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  // Eski form kontrolleri kaldırıldı; kullanıcı düzenlemesi diyalogda yapılıyor

  @override
  void initState() {
    super.initState();
    debugPrint('ProfileScreen initState - auto-updating profiles');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<HybridProvider>().loadCompanyProfiles();
    });
  }

  @override
  void dispose() {
    debugPrint('🔄 ProfileScreen disposing...');
    super.dispose();
  }

  // Eski dialog metodları kaldırıldı - artık ayrı ekranlar kullanıyoruz

  Future<void> _showUserProfileDialog(BuildContext context, User user) async {
    final nameCtrl = TextEditingController(text: user.fullName ?? '');
    // Firma adı kaldırıldığı için companyCtrl kullanılmıyor
    final phoneCtrl = TextEditingController(text: user.phone ?? '');
    final addressCtrl = TextEditingController(text: user.address ?? '');

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.person, color: AppConstants.primaryColor),
              const SizedBox(width: 8),
              const Text('Kullanıcı Profili'),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // E-posta (salt okunur)
                TextFormField(
                  initialValue: user.email,
                  enabled: false,
                  decoration: const InputDecoration(
                    labelText: 'E-posta',
                    prefixIcon: Icon(Icons.email_outlined),
                    filled: true,
                    fillColor: AppConstants.surfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),

                // Ad Soyad
                TextFormField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Ad Soyad',
                    hintText: 'Adınız ve soyadınız',
                    prefixIcon: Icon(Icons.person_outlined),
                  ),
                  textCapitalization: TextCapitalization.words,
                  inputFormatters: [CapitalizeWordsFormatter()],
                ),
                const SizedBox(height: 16),

                // Firma Adı kaldırıldı

                // Telefon
                TextFormField(
                  controller: phoneCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Telefon',
                    hintText: '0555 123 45 67',
                    prefixIcon: Icon(Icons.phone_outlined),
                  ),
                  inputFormatters: [PhoneNumberFormatter()],
                ),
                const SizedBox(height: 16),

                // Adres
                TextFormField(
                  controller: addressCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Adres',
                    hintText: 'Adresiniz',
                    prefixIcon: Icon(Icons.location_on_outlined),
                    alignLabelWithHint: true,
                  ),
                  textCapitalization: TextCapitalization.words,
                  inputFormatters: [CapitalizeWordsFormatter()],
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('İptal'),
            ),
            ElevatedButton(
              onPressed: () async {
                final provider = context.read<HybridProvider>();
                final updatedUser = user.copyWith(
                  fullName: nameCtrl.text.trim().isEmpty
                      ? null
                      : nameCtrl.text.trim(),
                  companyName: null,
                  phone: phoneCtrl.text.trim().isEmpty
                      ? null
                      : phoneCtrl.text.trim(),
                  address: addressCtrl.text.trim().isEmpty
                      ? null
                      : addressCtrl.text.trim(),

                  updatedAt: DateTime.now(),
                );

                final success = await provider.updateProfile(updatedUser);
                if (!context.mounted) return;

                if (success) {
                  Navigator.of(ctx).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Profil başarıyla güncellendi'),
                      backgroundColor: AppConstants.successColor,
                    ),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Profil güncellenirken hata oluştu'),
                      backgroundColor: AppConstants.errorColor,
                    ),
                  );
                }
              },
              child: const Text('Kaydet'),
            ),
          ],
        ),
      ),
    );
  }

  // Eski form tabanlı profil güncellemesi kaldırıldı (yerine diyalog kullanılıyor)

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Çıkış Yap'),
        content: const Text('Çıkış yapmak istediğinizden emin misiniz?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppConstants.errorColor,
            ),
            child: const Text('Çıkış Yap'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      try {
        // Loading göster
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Çıkış yapılıyor...'),
            duration: Duration(seconds: 2),
          ),
        );

        // Provider'dan logout çağır
        await context.read<HybridProvider>().logout();
        
        // Başarılı çıkış sonrası login ekranına yönlendir
        if (mounted) {
          Navigator.of(context).pushNamedAndRemoveUntil(
            '/login',
            (route) => false,
          );
        }
      } catch (e) {
        // Hata durumunda bile login ekranına yönlendir
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Çıkış hatası: $e'),
              backgroundColor: AppConstants.errorColor,
            ),
          );
          
          // Hata olsa bile login ekranına yönlendir
          await Future.delayed(const Duration(seconds: 2));
          if (mounted) {
            Navigator.of(context).pushNamedAndRemoveUntil(
              '/login',
              (route) => false,
            );
          }
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profil'),
        backgroundColor: AppConstants.primaryColor,
        foregroundColor: AppConstants.textOnPrimary,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            // Ana sayfaya (Dashboard) dön
            widget.onBackToHome?.call();
          },
        ),
      ),
      body: Consumer<HybridProvider>(
        builder: (context, hybridProvider, child) {
          try {
            final firebaseUser = hybridProvider.currentUser;
            final appUser = hybridProvider.appUser;

            if (firebaseUser == null || appUser == null) {
              return const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text(
                      'Kullanıcı bilgileri yükleniyor...',
                      style: TextStyle(color: AppConstants.textSecondary),
                    ),
                  ],
                ),
              );
            }

            // appUser ve firebaseUser burada tanımlandı ve kullanılabilir

            return SingleChildScrollView(
              padding: const EdgeInsets.all(AppConstants.paddingLarge),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Ana başlık - Şirket yönetimi odaklı (Daha ince)
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          AppConstants.primaryColor,
                          AppConstants.primaryLight,
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(
                        AppConstants.borderRadius,
                      ),
                    ),
                    child: Row( // Column yerine Row kullanıldı
                      children: [
                        Icon(
                          Icons.business_center,
                          size: 32, // Küçültüldü
                          color: AppConstants.textOnPrimary,
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Şirket Yönetimi',
                                style: AppConstants.headingStyle.copyWith(
                                  color: AppConstants.textOnPrimary,
                                  fontSize: 20, // Küçültüldü
                                ),
                              ),
                              Text(
                                'Şirketlerinizi yönetin ve faturalarınızda kullanın',
                                style: AppConstants.captionStyle.copyWith(
                                  color: AppConstants.textOnPrimary.withOpacity(0.9),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Şirket Profilleri Listesi
                  Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(
                        AppConstants.borderRadius,
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.business,
                                color: AppConstants.primaryColor,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Kayıtlı Şirketler',
                                style: AppConstants.subheadingStyle.copyWith(
                                  color: AppConstants.primaryColor,
                                  fontSize: 16,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          // Şirket yönetimi bölümü - Güvenli Consumer
                          Consumer<HybridProvider>(
                            builder: (context, provider, child) {
                              try {
                                final companies = provider.companies;
                                final selectedCompany =
                                    provider.selectedCompany;

                                // Safe logging
                                if (companies.isEmpty) {
                                  debugPrint(
                                    '🔍 No companies found - showing empty state',
                                  );
                                } else {
                                  debugPrint(
                                    '🔍 Companies: ${companies.length}, Selected: ${selectedCompany?.name}',
                                  );
                                }

                                      return Container(
                                        padding: const EdgeInsets.all(16.0),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            // Üstteki "Aktif Şirket Profili" başlığı ve butonu kaldırıldı

                                            // Safe empty state - no complex widgets
                                            if (companies.isEmpty)
                                              Container(
                                                padding: const EdgeInsets.all(20),
                                                child: Column(
                                                  children: [
                                                    const Icon(
                                                      Icons.business_outlined,
                                                      size: 40,
                                                      color: Colors.grey,
                                                    ),
                                                    const SizedBox(height: 8),
                                                    const Text(
                                                      'Henüz şirket kaydınız yok',
                                                      style: TextStyle(
                                                        color: Colors.grey,
                                                      ),
                                                    ),
                                                    const SizedBox(height: 12),
                                                    ElevatedButton(
                                                      onPressed: () {
                                                        try {
                                                          Navigator.push(
                                                            context,
                                                            MaterialPageRoute(
                                                              builder: (context) =>
                                                                  const AddCompanyScreen(),
                                                            ),
                                                          );
                                                        } catch (e) {
                                                          debugPrint(
                                                            'Navigation error: $e',
                                                          );
                                                        }
                                                      },
                                                      child: const Text(
                                                        'Şirket Ekle',
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              )
                                            else
                                              Column(
                                                children: [
                                                  // Basit container box (Generic Aktif) kaldırıldı

                                                  // Seçili şirket detay kartı
                                                  if (selectedCompany != null)
                                                    Card(
                                                      color: AppConstants.primaryLight
                                                          .withOpacity(0.1),
                                                      shape: RoundedRectangleBorder(
                                                        borderRadius:
                                                            BorderRadius.circular(12),
                                                        side: BorderSide(
                                                          color: AppConstants
                                                              .primaryColor,
                                                          width: 1,
                                                        ),
                                                      ),
                                                      child: ListTile(
                                                        leading: CompanyLogoAvatar(
                                                          logoPathOrUrl:
                                                              selectedCompany.logo,
                                                          size: 32,
                                                          circular: true,
                                                          backgroundColor:
                                                              AppConstants
                                                                  .primaryLight,
                                                          fallbackIcon:
                                                              Icons.business,
                                                          fallbackIconColor:
                                                              AppConstants
                                                                  .primaryColor,
                                                        ),
                                                        title: Text(
                                                          selectedCompany.name,
                                                          style: AppConstants
                                                              .bodyStyle
                                                              .copyWith(
                                                                fontWeight:
                                                                    FontWeight.w600,
                                                                color: AppConstants
                                                                    .primaryColor,
                                                              ),
                                                        ),
                                                        subtitle: Text(
                                                          'Seçili şirket - Faturalarda kullanılacak',
                                                          style: AppConstants
                                                              .captionStyle
                                                              .copyWith(
                                                                color: AppConstants
                                                                    .primaryColor,
                                                              ),
                                                        ),
                                                        trailing: Container(
                                                          padding:
                                                              const EdgeInsets.symmetric(
                                                                horizontal: 8,
                                                                vertical: 4,
                                                              ),
                                                          decoration: BoxDecoration(
                                                            color: AppConstants
                                                                .primaryColor,
                                                            borderRadius:
                                                                BorderRadius.circular(
                                                                  12,
                                                                ),
                                                          ),
                                                          child: Text(
                                                            'Aktif',
                                                            style: AppConstants
                                                                .captionStyle
                                                                .copyWith(
                                                                  color: AppConstants
                                                                      .textOnPrimary,
                                                                  fontWeight:
                                                                      FontWeight.w600,
                                                                ),
                                                          ),
                                                        ),
                                                      ),
                                                    ),

                                            const SizedBox(height: 12),

                                            // Özet bilgi
                                            Row(
                                              children: [
                                                Expanded(
                                                  child: Card(
                                                    child: Padding(
                                                      padding:
                                                          const EdgeInsets.all(
                                                            16,
                                                          ),
                                                      child: Column(
                                                        children: [
                                                          Text(
                                                            '${companies.length}',
                                                            style: AppConstants
                                                                .headingStyle
                                                                .copyWith(
                                                                  color: AppConstants
                                                                      .primaryColor,
                                                                  fontSize: 24,
                                                                ),
                                                          ),
                                                          Text(
                                                            'Kayıtlı Şirket',
                                                            style: AppConstants
                                                                .captionStyle,
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(width: 12),
                                                Expanded(
                                                  child: ElevatedButton.icon(
                                                    onPressed: () {
                                                      Navigator.push(
                                                        context,
                                                        MaterialPageRoute(
                                                          builder: (context) =>
                                                              const CompanyManagementScreen(),
                                                        ),
                                                      );
                                                    },
                                                    icon: const Icon(
                                                      Icons.settings,
                                                    ),
                                                    label: const Text('Yönet'),
                                                    style: ElevatedButton.styleFrom(
                                                      backgroundColor:
                                                          AppConstants
                                                              .primaryColor,
                                                      foregroundColor:
                                                          AppConstants
                                                              .textOnPrimary,
                                                      padding:
                                                          const EdgeInsets.symmetric(
                                                            vertical: 12,
                                                          ),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                    ],
                                  ),
                                );
                              } catch (e) {
                                debugPrint('❌ Company Consumer error: $e');
                                return Container(
                                  padding: const EdgeInsets.all(16.0),
                                  child: const Center(
                                    child: Text(
                                      'Şirket bilgileri yüklenirken hata oluştu',
                                      style: TextStyle(color: Colors.red),
                                    ),
                                  ),
                                );
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Kullanıcı Profili - Tıklanabilir Kart
                  Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(
                        AppConstants.borderRadius,
                      ),
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(
                        AppConstants.borderRadius,
                      ),
                      onTap: () => _showUserProfileDialog(context, appUser),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 24,
                              backgroundColor: AppConstants.getAvatarColor(
                                appUser.fullName ?? appUser.email,
                              ),
                              child: Text(
                                TextFormatter.initialTr(
                                  appUser.fullName ?? appUser.email,
                                ),
                                style: const TextStyle(
                                  color: AppConstants.textOnPrimary,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.person,
                                        color: AppConstants.primaryColor,
                                        size: 16,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        'Kullanıcı Profili',
                                        style: AppConstants.captionStyle
                                            .copyWith(
                                              color: AppConstants.primaryColor,
                                              fontWeight: FontWeight.w600,
                                            ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    appUser.fullName?.isNotEmpty == true
                                        ? appUser.fullName!
                                        : 'Ad Soyad Girilmemiş',
                                    style: AppConstants.bodyStyle.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    appUser.email,
                                    style: AppConstants.captionStyle.copyWith(
                                      color: AppConstants.textSecondary,
                                    ),
                                  ),
                                  if (appUser.phone?.isNotEmpty == true) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      appUser.phone!,
                                      style: AppConstants.captionStyle.copyWith(
                                        color: AppConstants.textSecondary,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            Icon(
                              Icons.edit,
                              color: AppConstants.textSecondary,
                              size: 20,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Manuel butonlar kaldırıldı (Otomatik yapılıyor)
                  const SizedBox(height: 12),

                  // Çıkış butonu
                  OutlinedButton(
                    onPressed: _logout,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppConstants.errorColor,
                      side: const BorderSide(color: AppConstants.errorColor),
                      padding: const EdgeInsets.symmetric(
                        vertical: AppConstants.paddingMedium,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                          AppConstants.borderRadius,
                        ),
                      ),
                    ),
                    child: const Text(
                      'Çıkış Yap',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            );
          } catch (e) {
            debugPrint('❌ Main ProfileScreen Consumer error: $e');
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error, color: Colors.red, size: 48),
                  SizedBox(height: 16),
                  Text(
                    'Profil ekranı yüklenirken hata oluştu',
                    style: TextStyle(color: Colors.red),
                  ),
                ],
              ),
            );
          }
        },
      ),
    );
  }
}
