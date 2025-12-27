# STAJ DEFTERİ - PROFORMA FATURA MOBİL UYGULAMASI
## 20 Günlük Staj Süreci - İlk 4 Gün

**Stajyer:** [Adınız]  
**Danışman:** Erkan Hoca  
**Kurum:** [Kurum Adı]  
**Tarih:** [Başlangıç Tarihi]  
**Proje:** Flutter ile Proforma Fatura Yönetim Sistemi

---

## 1. GÜN - FLUTTER VE MOBİL UYGULAMA GELİŞTİRME TEMELLERİ
**Tarih:** [1. Gün Tarihi]

Bugün stajımın ilk günüydü ve Erkan hocamla tanıştım. Hocam bana Flutter framework'ünü öğretmeye başladı. Daha önce mobil uygulama geliştirme konusunda deneyimim yoktu, bu yüzden temel kavramlardan başladık.

### Bugün Öğrendiklerim

**Flutter Framework Tanımı:**
Flutter, Google tarafından geliştirilen cross-platform mobil uygulama geliştirme framework'üdür. Dart programlama dili kullanır ve tek kodla hem Android hem iOS uygulamaları geliştirmeyi sağlar.

**Flutter'ın Temel Kavramları:**
- **Widget:** Flutter'da her şey widget'tır - UI bileşenleri
- **State:** Uygulamanın durumu, verilerin değişken hali
- **Hot Reload:** Kod değişikliklerinin anında uygulamada görünmesi
- **Cross-platform:** Tek kodla birden fazla platform için uygulama

**Dart Programlama Dili:**
Flutter'ın kullandığı programlama dili olan Dart'ın temel özelliklerini öğrendim:
- **Type Safety:** Güçlü tip sistemi
- **Null Safety:** Null değerlerin güvenli yönetimi
- **Async/Await:** Asenkron programlama desteği
- **Object-Oriented:** Nesne yönelimli programlama

### Proje Konusu Belirleme

Hocam bana proforma fatura yönetimi için bir mobil uygulama geliştirmemizi önerdi. Bu konuyu seçmemizin nedenleri:

**Proforma Fatura Nedir?**
- Mal veya hizmet teslim edilmeden önce düzenlenen belge
- Kesin satış belgesi değil, ön bilgi belgesi
- Uluslararası ticarette önemli rol oynar
- Gümrük işlemlerinde kullanılabilir

**Uygulama Gereksinimleri:**
1. **Kullanıcı Yönetimi** - Giriş/kayıt sistemi
2. **Müşteri Yönetimi** - Müşteri bilgileri CRUD işlemleri
3. **Ürün Kataloğu** - Ürün kategorileri ve yönetimi
4. **Fatura Oluşturma** - Proforma fatura düzenleme
5. **PDF Oluşturma** - Fatura PDF'leri oluşturma

### Teknoloji Stack'i

Hocam bana kullanacağımız teknolojileri açıkladı:

```dart
// pubspec.yaml dosyasından
dependencies:
  flutter:
    sdk: flutter
  provider: ^6.1.1  # State management
  postgres: ^3.0.1  # PostgreSQL database
  http: ^1.1.0      # HTTP istekleri için
```

**Provider Pattern:** Flutter'da state management için kullanılan desen
**PostgreSQL:** Güçlü ilişkisel veritabanı sistemi
**HTTP:** REST API'ler ile iletişim için

### Bugünkü Çalışmalar

- Flutter framework'ünü tanıdım
- Dart programlama dilinin temellerini öğrendim
- Proje konusunu belirledim
- Teknoloji stack'ini öğrendim
- Mobil uygulama geliştirme sürecini anladım

### Yarın Ne Yapacağım

Yarın Flutter geliştirme ortamını kuracağım ve ilk projemi oluşturacağım. Android Studio ve VS Code kurulumunu yapacağım.

---

## 2. GÜN - FLUTTER GELİŞTİRME ORTAMININ KURULUMU VE İLK PROJE
**Tarih:** [2. Gün Tarihi]

Bugün Flutter geliştirme ortamını kurmaya başladım. Hocam bana adım adım kurulum sürecini gösterdi. İlk defa mobil uygulama geliştirme ortamı kurduğum için her şey yeniydi.

### Sabah - Flutter SDK Kurulumu

Hocam bana Flutter SDK'sını nasıl kuracağımı gösterdi. Resmi web sitesinden Flutter 3.8.1+ sürümünü indirdim.

**Kurulum Sürecinde Öğrendiklerim:**
1. **Flutter SDK** - Ana framework, PATH ayarları gerekli
2. **Android Studio** - IDE olarak kullanacağımız editör
3. **Android SDK** - Android uygulamaları için gerekli
4. **Git** - Versiyon kontrolü için
5. **VS Code** - Alternatif editör, Flutter eklentileri ile

**PATH Ayarları:** Sistem değişkenlerinde Flutter'ın yolunu belirtmek gerekiyor ki terminal'den erişilebilsin.

### Öğleden Sonra - İlk Proje Oluşturma

Hocam bana ilk Flutter projemi nasıl oluşturacağımı gösterdi:

```bash
# Flutter projesi oluşturma
flutter create proforma_fatura_app
cd proforma_fatura_app
```

Bu komutları çalıştırdığımda proje klasörü oluştu. Hocam bana proje yapısını açıkladı:

```
lib/
├── config/           # Konfigürasyon dosyaları
├── constants/        # Sabitler ve temalar
├── models/          # Veri modelleri
├── providers/       # State management
├── screens/         # UI ekranları
├── services/        # İş mantığı servisleri
├── utils/           # Yardımcı fonksiyonlar
└── widgets/         # Özel widget'lar
```

**Proje Yapısı:** Flutter projelerinde kod organizasyonu için kullanılan klasör yapısıdır.

### Bağımlılıkları Ekleme

Hocam bana `pubspec.yaml` dosyasını nasıl düzenleyeceğimi gösterdi:

```yaml
# pubspec.yaml - Temel bağımlılıklar
dependencies:
  # UI ve State Management
  provider: ^6.1.1
  cupertino_icons: ^1.0.8
  
  # Veritabanı
  postgres: ^3.0.1
  path: ^1.8.3
  
  # HTTP istekleri
  http: ^1.1.0
  dio: ^5.3.2
  
  # PDF ve Dosya İşlemleri
  pdf: ^3.10.7
  path_provider: ^2.1.1
  printing: ^5.13.4
```

**pubspec.yaml:** Flutter projelerinde bağımlılıkları ve proje ayarlarını tanımlayan dosyadır.

`flutter pub get` komutunu çalıştırdım ve paketler indirildi. Bu komut paketleri `pubspec.lock` dosyasına kaydeder.

### İlk Uygulama Testi

Hocam bana Android emulator'ü nasıl başlatacağımı gösterdi. `flutter run` komutunu çalıştırdığımda ilk uygulamam çalıştı!

**Hot Reload:** Kod değişikliklerini anında görmek için kullanılan özellik. `r` tuşuna basarak test ettim.

### Bugünkü Zorluklar

- Android SDK kurulumu karmaşıktı
- Emulator başlatma süreci zaman aldı
- Flutter CLI komutlarını öğrenmek gerekti
- Proje yapısını anlamak zaman aldı

### Bugünkü Çalışmalar

- Flutter SDK kurulumunu tamamladım
- İlk Flutter projesini oluşturdum
- Gerekli bağımlılıkları ekledim
- Temel Flutter komutlarını öğrendim
- Hot reload özelliğini test ettim

### Yarın Ne Yapacağım

Yarın Dart programlama dilinin detaylarını öğreneceğim. Sınıflar, fonksiyonlar ve veri tipleri konularında çalışacağım.

---

## 3. GÜN - DART PROGRAMLAMA DİLİ VE VERİ TİPLERİ
**Tarih:** [3. Gün Tarihi]

Bugün Dart programlama dilinin detaylarını öğrenmeye başladım. Hocam bana Dart'ın Flutter'ın temelini oluşturduğunu söyledi. İlk defa bu dili kullanacağım için temel kavramlardan başladık.

### Sabah - Dart Temel Kavramları

Hocam bana Dart'ın temel özelliklerini açıkladı:

**Dart Programlama Dili:**
- Google tarafından geliştirilen modern programlama dili
- Flutter'ın kullandığı ana dil
- Type-safe ve null-safe özellikler
- Object-oriented programlama desteği

**Temel Veri Tipleri:**
```dart
// Temel veri tipleri
int age = 25;                    // Tamsayı
double price = 19.99;            // Ondalıklı sayı
String name = "Ahmet";           // Metin
bool isActive = true;            // Boolean
List<String> items = ["a", "b"]; // Liste
Map<String, int> scores = {      // Map (Dictionary)
  "math": 85,
  "science": 90
};
```

**Type Safety:** Değişkenlerin tipinin belirli olması ve tip hatalarının derleme zamanında yakalanması.

### Öğleden Sonra - Sınıflar ve Nesneler

Hocam bana Dart'ta sınıf yapısını öğretti:

```dart
// lib/models/user.dart
class User {
  final String? id;           // Nullable string
  final String username;      // Required string
  final String email;
  final String passwordHash;
  final String fullName;
  final String? companyName;  // Optional field
  final String? phone;
  final String? address;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  // Constructor
  User({
    this.id,
    required this.username,    // Required parameter
    required this.email,
    required this.passwordHash,
    required this.fullName,
    this.companyName,          // Optional parameter
    this.phone,
    this.address,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
  });
}
```

**Constructor:** Sınıf örneği oluştururken kullanılan özel metod.

**Required:** Constructor parametrelerinin zorunlu olduğunu belirten anahtar kelime.

**Final:** Değişkenin değerinin bir kez atandıktan sonra değiştirilemeyeceğini belirten anahtar kelime.

### Getter ve Setter Metodları

Hocam bana getter metodlarını öğretti:

```dart
// lib/models/invoice.dart
class Invoice {
  final List<InvoiceItem> items;
  final double? discountRate;

  // Getter metodları
  double get subtotal {
    return items.fold(0.0, (sum, item) => sum + item.subtotal);
  }

  double get totalAmount => amountAfterDiscount + totalTaxAmount;
}
```

**Getter:** Bir özelliğin değerini hesaplayarak döndüren metod türü.

**Fold Fonksiyonu:** Bir listedeki elemanları belirli bir işlemle birleştiren fonksiyon.

### Null Safety

Hocam bana Dart'ın null safety özelliğini açıkladı:

```dart
// Null safety örnekleri
String? nullableString;        // Null olabilir
String nonNullableString;      // Null olamaz

// Null kontrolü
if (nullableString != null) {
  print(nullableString.length);
}

// Null-aware operatörler
String result = nullableString ?? "Default Value";
String length = nullableString?.length.toString() ?? "0";
```

**Null Safety:** Null değerlerin güvenli şekilde yönetilmesini sağlayan özellik.

**Null-aware Operators:** Null değerlerle güvenli çalışmayı sağlayan operatörler.

### Asenkron Programlama

Hocam bana async/await kavramlarını öğretti:

```dart
// Asenkron fonksiyon örneği
Future<String> fetchData() async {
  await Future.delayed(Duration(seconds: 2));
  return "Data loaded";
}

// Kullanım
void loadData() async {
  try {
    String data = await fetchData();
    print(data);
  } catch (e) {
    print("Error: $e");
  }
}
```

**Async/Await:** Asenkron işlemleri yönetmek için kullanılan anahtar kelimeler.

**Future:** Gelecekte tamamlanacak bir işlemi temsil eden sınıf.

### Bugünkü Zorluklar

- Dart sınıf yapısını anlamak zaman aldı
- `required` ve `final` kelimelerini karıştırdım
- Null safety kavramını kavramak zordu
- Asenkron programlama karmaşıktı
- Getter/setter metodlarını anlamak gerekti

### Bugünkü Çalışmalar

- Dart temel veri tiplerini öğrendim
- Sınıf yapısını anladım
- Constructor ve parametreleri öğrendim
- Getter metodlarını yazdım
- Null safety kavramını öğrendim
- Asenkron programlama temellerini öğrendim

### Yarın Ne Yapacağım

Yarın veritabanı tasarımı konusuna geçeceğim. PostgreSQL veritabanı kurulumunu öğreneceğim ve veri modellerini tasarlayacağım.

---

## 4. GÜN - VERİTABANI TASARIMI VE SQL TEMELLERİ
**Tarih:** [4. Gün Tarihi]

Bugün veritabanı tasarımı konusuna geçtim. Hocam bana "Veritabanı olmadan gerçek uygulama olmaz" dedi. PostgreSQL veritabanı kurulumunu ve SQL temellerini öğrenmeye başladım.

### Sabah - PostgreSQL Kurulumu

Hocam bana PostgreSQL'i nasıl kuracağımı gösterdi. Resmi web sitesinden PostgreSQL 15 sürümünü indirdim.

**PostgreSQL Nedir?**
- Açık kaynak kodlu ilişkisel veritabanı yönetim sistemi
- ACID uyumlu, güçlü veri bütünlüğü
- Gelişmiş veri tipleri (JSON, array)
- Büyük veri setleri için uygun

**Kurulum Sürecinde Öğrendiklerim:**
1. **PostgreSQL 15 indirme** - Resmi web sitesinden
2. **Kurulum yapılandırması** - Port 5432, postgres kullanıcısı
3. **pgAdmin kurulumu** - Veritabanı yönetim arayüzü
4. **Veritabanı oluşturma** - "proforma_fatura" adıyla
5. **Bağlantı testi** - pgAdmin ile bağlantı doğrulama

**pgAdmin:** PostgreSQL veritabanlarını yönetmek için kullanılan web tabanlı arayüzdür.

### Öğleden Sonra - SQL Temelleri

Hocam bana SQL (Structured Query Language) temellerini öğretti:

**Temel SQL Komutları:**
```sql
-- Veritabanı oluşturma
CREATE DATABASE proforma_fatura;

-- Tablo oluşturma
CREATE TABLE users (
  id SERIAL PRIMARY KEY,
  username VARCHAR(50) NOT NULL,
  email VARCHAR(100) UNIQUE NOT NULL,
  password_hash VARCHAR(255) NOT NULL,
  full_name VARCHAR(100) NOT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Veri ekleme
INSERT INTO users (username, email, password_hash, full_name) 
VALUES ('ahmet', 'ahmet@email.com', 'hash123', 'Ahmet Yılmaz');

-- Veri sorgulama
SELECT * FROM users WHERE email = 'ahmet@email.com';

-- Veri güncelleme
UPDATE users SET full_name = 'Ahmet Yılmaz' WHERE id = 1;

-- Veri silme
DELETE FROM users WHERE id = 1;
```

**SERIAL:** PostgreSQL'de otomatik artan tamsayı veri tipidir.

**PRIMARY KEY:** Tabloda her satırı benzersiz şekilde tanımlayan anahtar.

**UNIQUE:** Aynı değerden sadece bir tane olabileceğini belirten kısıtlamadır.

### Foreign Key İlişkileri

Hocam bana tablolar arası ilişkileri öğretti:

```sql
-- Müşteriler tablosu
CREATE TABLE customers (
  id SERIAL PRIMARY KEY,
  user_id INTEGER NOT NULL,
  name VARCHAR(100) NOT NULL,
  email VARCHAR(100),
  phone VARCHAR(20),
  tax_number VARCHAR(20),
  address TEXT,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (user_id) REFERENCES users (id)
);

-- Faturalar tablosu
CREATE TABLE invoices (
  id SERIAL PRIMARY KEY,
  user_id INTEGER NOT NULL,
  customer_id INTEGER NOT NULL,
  invoice_number VARCHAR(50) NOT NULL,
  invoice_date DATE NOT NULL,
  due_date DATE NOT NULL,
  total_amount DECIMAL(10,2) NOT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (user_id) REFERENCES users (id),
  FOREIGN KEY (customer_id) REFERENCES customers (id)
);
```

**Foreign Key:** Bir tablodaki sütunun başka bir tablodaki sütuna referans verdiğini belirten kısıtlamadır.

**Referential Integrity:** Veritabanında referans bütünlüğünü sağlayan kısıtlamadır.

### Veri Tipleri

Hocam bana PostgreSQL veri tiplerini açıkladı:

```sql
-- Temel veri tipleri
INTEGER          -- Tamsayı
SERIAL           -- Otomatik artan tamsayı
VARCHAR(n)       -- Değişken uzunlukta metin
TEXT             -- Uzun metin
BOOLEAN          -- True/False
DECIMAL(p,s)     -- Ondalıklı sayı (precision, scale)
DATE             -- Tarih
TIMESTAMP        -- Tarih ve saat
JSON             -- JSON veri
ARRAY            -- Dizi
```

**DECIMAL:** Para tutarları için kullanılan hassas ondalıklı sayı tipi.

**JSON:** Modern uygulamalarda esnek veri saklama için kullanılan tip.

### Dart ile Veritabanı Bağlantısı

Hocam bana Dart'ta PostgreSQL bağlantısını nasıl yapacağımı gösterdi:

```dart
// lib/config/database_config.dart
class DatabaseConfig {
  static const String host = 'localhost';
  static const int port = 5432;
  static const String databaseName = 'proforma_fatura';
  static const String username = 'postgres';
  static const String password = 'your_password';
  
  static String get connectionString => 
      'postgresql://$username:$password@$host:$port/$databaseName';
}
```

**Connection String:** Veritabanına bağlanmak için kullanılan bağlantı adresidir.

### Bugünkü Zorluklar

- PostgreSQL kurulumu karmaşıktı
- SQL syntax'ını öğrenmek zaman aldı
- Foreign key ilişkilerini kavramak zordu
- Veri tiplerini seçmek zordu
- Bağlantı string'ini yapılandırmak zordu

### Bugünkü Çalışmalar

- PostgreSQL kurulumunu tamamladım
- SQL temel komutlarını öğrendim
- Veri tiplerini öğrendim
- Foreign key ilişkilerini kavradım
- Veritabanı tasarımı prensiplerini öğrendim
- Dart ile veritabanı bağlantısı konusunu öğrendim

### Yarın Ne Yapacağım

Yarın Provider pattern'i öğreneceğim. Flutter'da state management nasıl yapılır, veri nasıl yönetilir konularında çalışacağım.

---

## GENEL DEĞERLENDİRME - İLK 4 GÜN

### Bu 4 Günde Öğrenilen Kavramlar

**1. Gün - Flutter ve Mobil Uygulama Temelleri:**
- Flutter framework tanımı ve özellikleri
- Dart programlama dili temelleri
- Cross-platform geliştirme kavramları
- Proje konusu belirleme

**2. Gün - Flutter Geliştirme Ortamı:**
- Flutter SDK kurulumu
- Android Studio ve VS Code entegrasyonu
- Proje yapısı organizasyonu
- Dependency management ve pubspec.yaml

**3. Gün - Dart Programlama Dili:**
- Dart temel veri tipleri
- Sınıflar ve nesneler
- Constructor ve parametreler
- Null safety ve asenkron programlama

**4. Gün - Veritabanı Tasarımı:**
- PostgreSQL kurulumu ve yapılandırması
- SQL temel komutları
- Foreign key ilişkileri
- Veri tipleri ve veritabanı tasarımı

### Öğrenilen Teknik Terimler

**Flutter Terimleri:**
- **Cross-platform:** Tek kodla birden fazla platform için uygulama geliştirme
- **Hot reload:** Kod değişikliklerinin anında uygulamada görünmesi
- **Widget:** Flutter'da UI bileşenleri
- **Provider Pattern:** State management deseni

**Veritabanı Terimleri:**
- **ACID:** Veri tutarlılığı garantisi (Atomicity, Consistency, Isolation, Durability)
- **SERIAL:** PostgreSQL'de otomatik artan tamsayı veri tipi
- **Foreign Key:** Tablolar arası referans ilişkisi
- **Referential Integrity:** Referans bütünlüğü

**Programlama Terimleri:**
- **Async/Await:** Asenkron programlama
- **Try-Catch:** Hata yakalama mekanizması
- **Constructor:** Sınıf örneği oluşturma metodu
- **Getter/Setter:** Özellik erişim metodları

### Karşılaşılan Zorluklar

1. **Dart sınıf yapısı** - `required` ve `final` kavramlarını anlamak
2. **PostgreSQL syntax** - SQL komutlarını öğrenmek
3. **PostgreSQL konfigürasyonu** - Bağlantı string'i yapılandırma
4. **Asenkron programlama** - `async/await` kavramını kavramak
5. **SQL sorguları** - Veritabanı işlemleri için SQL yazma

### Başarılan Çalışmalar

- Flutter geliştirme ortamı kurulumu
- İlk Flutter projesi oluşturma
- Veri modelleri tasarlama
- PostgreSQL veritabanı kurulumu
- Authentication sistemi geliştirme

### Hocamdan Öğrenilen Prensipler

Erkan hocam bana şu prensipleri öğretti:
- **"Her şeyi düşün, eksik bırakma"** - Proje planlamada
- **"Veritabanı güvenliği önemli"** - Şifre hash'leme ve güvenli bağlantı
- **"Güvenlik önemli"** - API key'leri korumada
- **"Hata yakala, kullanıcıyı bilgilendir"** - Error handling'de

### Sonraki Adımlar

5. günden itibaren:
- **UI/UX tasarımı** - Login, register, ana sayfa ekranları
- **Provider pattern** - State management implementasyonu
- **CRUD operasyonları** - Müşteri, ürün yönetimi
- **PDF oluşturma** - Fatura PDF servisleri

### Genel Değerlendirme

Bu 4 günlük süreçte temel mobil uygulama geliştirme kavramlarını öğrendim. Flutter framework'ünü, Dart programlama dilini ve PostgreSQL veritabanını tanıdım. Cross-platform geliştirme, veri modelleme ve veritabanı tasarımı konularında temel bilgiler edindim. Hocamın rehberliği sayesinde sistematik bir şekilde ilerledim.

---

**Not:** Bu defter, staj sürecinde öğrenilen kavramları, uygulanan teknikleri ve karşılaşılan zorlukları içermektedir. Her günün sonunda yapılan değerlendirmeler, sürekli öğrenme ve gelişim sürecini yansıtmaktadır.
