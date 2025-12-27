import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

class CurrencyService {
  static const String _baseUrl = 'http://hasanadiguzel.com.tr/api/kurgetir';

  // Cache için son güncelleme zamanı ve veriler
  static DateTime? _lastUpdate;
  static Map<String, double>? _cachedRates;
  static const Duration _cacheTimeout = Duration(
    minutes: 15,
  ); // 15 dakika cache

  /// TCMB'den güncel döviz kurlarını çeker
  static Future<Map<String, double>> getExchangeRates() async {
    debugPrint('🔄 Doviz kurlari getiriliyor...');

    // Cache kontrolü - 15 dakikadan yeniyse cache'den döndür
    if (_cachedRates != null &&
        _lastUpdate != null &&
        DateTime.now().difference(_lastUpdate!) < _cacheTimeout) {
      debugPrint('✅ Cache\'den doviz kurlari donduruluyor: $_cachedRates');
      return _cachedRates!;
    }

    try {
      debugPrint('🌐 API\'ye istek gonderiliyor: $_baseUrl');
      final response = await http
          .get(
            Uri.parse(_baseUrl),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 10));

      debugPrint('📡 API yaniti alindi: ${response.statusCode}');
      debugPrint('📄 API yanit icerigi: ${response.body.substring(0, 200)}...');

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);
        debugPrint('📊 API verisi parse edildi');

        if (data['TCMB_AnlikKurBilgileri'] != null &&
            data['TCMB_AnlikKurBilgileri'] is List) {
          final List<dynamic> currencies = data['TCMB_AnlikKurBilgileri'];
          debugPrint('💰 ${currencies.length} para birimi bulundu');
          final Map<String, double> rates = {};

          // Her bir para birimini işle
          for (var currency in currencies) {
            if (currency is Map<String, dynamic>) {
              final String? currencyCode = currency['CurrencyName']?.toString();
              final String? forexSelling = currency['ForexSelling']?.toString();

              if (currencyCode != null &&
                  forexSelling != null &&
                  forexSelling.isNotEmpty) {
                // Virgülü noktaya çevir (Türk sayı formatı için)
                final String normalizedRate = forexSelling.replaceAll(',', '.');
                final double? rate = double.tryParse(normalizedRate);

                if (rate != null && rate > 0) {
                  // Para birimi kodunu normalize et
                  final String normalizedCode = _normalizeCurrencyCode(
                    currencyCode,
                  );
                  if (normalizedCode.isNotEmpty) {
                    rates[normalizedCode] = rate;
                    debugPrint(
                      '💱 $currencyCode -> $normalizedCode: $forexSelling -> ${rate.toStringAsFixed(4)}',
                    );
                  }
                }
              }
            }
          }

          // Cache'i güncelle
          _cachedRates = rates;
          _lastUpdate = DateTime.now();
          debugPrint('✅ Cache guncellendi: ${rates.length} para birimi');

          return rates;
        } else {
          throw Exception('API yanıt formatı beklenmedik');
        }
      } else {
        throw Exception('API yanıtı başarısız: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('❌ Doviz kurlari getirme hatasi: $e');
      // Hata durumunda cache varsa onu döndür
      if (_cachedRates != null) {
        debugPrint('✅ Hata durumunda cache kullaniliyor: $_cachedRates');
        return _cachedRates!;
      }
      // Cache de yoksa varsayılan değerler döndür
      debugPrint('⚠️ Varsayilan degerler kullaniliyor');
      return _getDefaultRates();
    }
  }

  /// Belirli bir para biriminin kurunu çeker
  static Future<double?> getCurrencyRate(String currencyCode) async {
    try {
      final rates = await getExchangeRates();
      return rates[currencyCode.toUpperCase()];
    } catch (e) {
      return null;
    }
  }

  /// Para birimi formatlaması
  static String formatCurrency(double amount, String currencyCode) {
    if (amount == 0) return '₺0,00';

    switch (currencyCode.toUpperCase()) {
      case 'USD':
        return '₺${amount.toStringAsFixed(4)}';
      case 'EUR':
        return '₺${amount.toStringAsFixed(4)}';
      case 'GBP':
        return '₺${amount.toStringAsFixed(4)}';
      case 'JPY':
        return '₺${amount.toStringAsFixed(2)}'; // JPY genelde daha büyük sayılar
      default:
        return '₺${amount.toStringAsFixed(4)}';
    }
  }

  /// Döviz çevrim hesaplaması (TRY'den diğer para birimine)
  static Future<double?> convertFromTRY(
    double tryAmount,
    String toCurrency,
  ) async {
    try {
      final rate = await getCurrencyRate(toCurrency);
      if (rate != null && rate > 0) {
        return tryAmount / rate;
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Döviz çevrim hesaplaması (diğer para biriminden TRY'ye)
  static Future<double?> convertToTRY(
    double amount,
    String fromCurrency,
  ) async {
    try {
      final rate = await getCurrencyRate(fromCurrency);
      if (rate != null && rate > 0) {
        return amount * rate;
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Genel döviz çevirici (Herhangi birinden herhangi birine)
  static Future<double?> convertCurrency(
    double amount,
    String fromCurrency,
    String toCurrency,
  ) async {
    // Aynı para birimi ise direkt döndür
    if (fromCurrency == toCurrency) return amount;

    // TRY'ye çevir veya TRY'den çevir
    if (fromCurrency == 'TRY') {
      return await convertFromTRY(amount, toCurrency);
    } else if (toCurrency == 'TRY') {
      return await convertToTRY(amount, fromCurrency);
    } else {
      // Çapraz kur: Önce TRY'ye çevir, sonra hedefe çevir
      final tryAmount = await convertToTRY(amount, fromCurrency);
      if (tryAmount != null) {
        return await convertFromTRY(tryAmount, toCurrency);
      }
    }
    return null;
  }

  /// Cache'i temizle
  static void clearCache() {
    _cachedRates = null;
    _lastUpdate = null;
  }

  /// Cache durumunu kontrol et
  static bool get isCacheValid {
    return _cachedRates != null &&
        _lastUpdate != null &&
        DateTime.now().difference(_lastUpdate!) < _cacheTimeout;
  }

  /// Son güncelleme zamanını döndür
  static DateTime? get lastUpdateTime => _lastUpdate;

  /// Varsayılan kurlar (API erişilemediğinde)
  static Map<String, double> _getDefaultRates() {
    final defaultRates = {
      'USD': 34.50,
      'EUR': 37.20,
      'GBP': 43.80,
      'JPY': 0.23,
    };
    debugPrint('📊 Varsayilan kurlar donduruluyor: $defaultRates');
    return defaultRates;
  }

  /// Mevcut tüm para birimlerini listele
  static Future<List<String>> getAvailableCurrencies() async {
    try {
      final rates = await getExchangeRates();
      return rates.keys.toList()..sort();
    } catch (e) {
      return ['USD', 'EUR', 'GBP', 'JPY'];
    }
  }

  /// Para birimi bilgilerini detaylı şekilde çek
  static Future<Map<String, dynamic>?> getCurrencyDetails(
    String currencyCode,
  ) async {
    try {
      final response = await http.get(Uri.parse(_baseUrl));

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);
        final List<dynamic> currencies = data['TCMB_AnlikKurBilgileri'] ?? [];

        for (var currency in currencies) {
          if (currency is Map<String, dynamic> &&
              currency['CurrencyName']?.toString().toUpperCase() ==
                  currencyCode.toUpperCase()) {
            return {
              'name': currency['Isim']?.toString() ?? '',
              'code': currency['CurrencyName']?.toString() ?? '',
              'forexBuying': _parseRate(currency['ForexBuying']?.toString()),
              'forexSelling': _parseRate(currency['ForexSelling']?.toString()),
              'banknoteBuying': _parseRate(
                currency['BanknoteBuying']?.toString(),
              ),
              'banknoteSelling': _parseRate(
                currency['BanknoteSelling']?.toString(),
              ),
              'crossRateUSD': _parseRate(currency['CrossRateUSD']?.toString()),
            };
          }
        }
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// String rate'i double'a çevir
  static double? _parseRate(String? rateString) {
    if (rateString == null || rateString.isEmpty) return null;
    final normalizedRate = rateString.replaceAll(',', '.');
    return double.tryParse(normalizedRate);
  }

  /// Para birimi kodunu normalize et
  static String _normalizeCurrencyCode(String currencyCode) {
    final code = currencyCode.toUpperCase();

    // API'den gelen kodları standart kodlara çevir
    switch (code) {
      case 'US DOLLAR':
        return 'USD';
      case 'EURO':
        return 'EUR';
      case 'POUND STERLING':
        return 'GBP';
      case 'JAPENESE YEN':
        return 'JPY';
      default:
        // Eğer tanınmayan bir kod ise boş string döndür
        return '';
    }
  }
}
