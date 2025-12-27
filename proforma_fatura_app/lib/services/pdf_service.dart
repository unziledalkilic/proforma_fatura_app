import 'dart:io';
import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';
import '../models/invoice.dart';
import '../models/invoice_item.dart';
import '../models/user.dart';
import '../models/company_info.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;

class PdfService {
  static final PdfService _instance = PdfService._internal();
  factory PdfService() => _instance;
  PdfService._internal();

  /// Fatura PDF'ini oluştur ve dosya yolunu döndür
  Future<String> generateInvoicePdf(
    Invoice invoice, {
    User? companyInfo, // backward compatibility
    CompanyInfo? sellerCompany, // preferred multi-company info
  }) async {
    final pdf = pw.Document();

    // Türkçe karakterleri destekleyen font ayarları
    final ttf = await rootBundle.load("assets/fonts/Roboto-Regular.ttf");
    final ttfBold = await rootBundle.load("assets/fonts/Roboto-Bold.ttf");

    final font = pw.Font.ttf(ttf);
    final fontBold = pw.Font.ttf(ttfBold);

    // Hazırsa satıcı logo görselini yükle
    pw.MemoryImage? sellerLogoImage;
    final logoUrl = sellerCompany?.logo ?? '';
    if (logoUrl.isNotEmpty) {
      try {
        Uint8List bytes;
        if (logoUrl.startsWith('http')) {
          final resp = await http.get(Uri.parse(logoUrl));
          if (resp.statusCode == 200) {
            bytes = resp.bodyBytes;
            sellerLogoImage = pw.MemoryImage(bytes);
          }
        } else {
          final file = File(logoUrl);
          if (await file.exists()) {
            bytes = await file.readAsBytes();
            sellerLogoImage = pw.MemoryImage(bytes);
          }
        }
      } catch (_) {}
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(30),
        theme: pw.ThemeData.withFont(base: font, bold: fontBold),
        build: (context) => [
          _buildHeader(
            invoice,
            companyInfo,
            sellerCompany,
            sellerLogoImage,
            font,
            fontBold,
          ),
          pw.SizedBox(height: 30),
          _buildBillingSection(
            invoice,
            companyInfo,
            sellerCompany,
            font,
            fontBold,
          ),
          pw.SizedBox(height: 30),
          _buildItemsTable(invoice, font, fontBold),
          pw.SizedBox(height: 20),
          _buildTotals(invoice, font, fontBold),
          pw.SizedBox(height: 30),
          _buildFooter(invoice, font, fontBold),
        ],
      ),
    );

    // Dosyayı kaydet
    final output = await getTemporaryDirectory();
    final file = File('${output.path}/fatura_${invoice.invoiceNumber}.pdf');
    await file.writeAsBytes(await pdf.save());

    return file.path;
  }

  /// Başlık bölümü - Modern ve temiz tasarım
  pw.Widget _buildHeader(
    Invoice invoice,
    User? companyInfo,
    CompanyInfo? sellerCompany,
    pw.MemoryImage? sellerLogoImage,
    pw.Font font,
    pw.Font fontBold,
  ) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        // Sol taraf - Logo ve başlık
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            if (sellerLogoImage != null)
              pw.Container(
                width: 64,
                height: 64,
                decoration: pw.BoxDecoration(
                  color: PdfColors.grey100,
                  borderRadius: const pw.BorderRadius.all(
                    pw.Radius.circular(6),
                  ),
                ),
                padding: const pw.EdgeInsets.all(4),
                child: pw.Image(sellerLogoImage, fit: pw.BoxFit.contain),
              )
            else
              pw.Container(
                padding: const pw.EdgeInsets.all(8),
                decoration: pw.BoxDecoration(
                  color: PdfColors.grey100,
                  borderRadius: const pw.BorderRadius.all(
                    pw.Radius.circular(4),
                  ),
                ),
              ),
            pw.SizedBox(height: 15),
            // Ana başlık
            pw.Text(
              'TEKLİF FORMU',
              style: pw.TextStyle(
                fontSize: 28,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.black,
                letterSpacing: 1.2,
                font: fontBold,
              ),
            ),
          ],
        ),
        // Sağ taraf - Fatura detayları
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            _buildInvoiceDetailRow(
              'Fatura No.',
              invoice.invoiceNumber,
              font,
              fontBold,
            ),
            pw.SizedBox(height: 8),
            _buildInvoiceDetailRow(
              'Fatura Tarihi',
              DateFormat('dd.MM.yyyy').format(invoice.invoiceDate),
              font,
              fontBold,
            ),
            pw.SizedBox(height: 8),
            _buildInvoiceDetailRow(
              'Geçerlilik Tarihi',
              DateFormat('dd.MM.yyyy').format(invoice.dueDate),
              font,
              fontBold,
            ),
          ],
        ),
      ],
    );
  }

  /// Fatura detay satırı
  pw.Widget _buildInvoiceDetailRow(
    String label,
    String value,
    pw.Font font,
    pw.Font fontBold,
  ) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey300, width: 0.5),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
      ),
      child: pw.Row(
        mainAxisSize: pw.MainAxisSize.min,
        children: [
          pw.Text(
            '$label: ',
            style: pw.TextStyle(
              fontSize: 11,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.black,
              font: fontBold,
            ),
          ),
          pw.Text(
            value,
            style: pw.TextStyle(
              fontSize: 11,
              color: PdfColors.black,
              font: font,
            ),
          ),
        ],
      ),
    );
  }

  /// Fatura ve müşteri bilgileri bölümü
  pw.Widget _buildBillingSection(
    Invoice invoice,
    User? companyInfo,
    CompanyInfo? sellerCompany,
    pw.Font font,
    pw.Font fontBold,
  ) {
    final sellerName =
        sellerCompany?.name ??
        (companyInfo?.companyName ?? companyInfo?.fullName ?? '');
    final sellerAddress =
        sellerCompany?.address ?? (companyInfo?.address ?? '');
    final sellerPhone = sellerCompany?.phone ?? (companyInfo?.phone ?? '');
    final sellerEmail = sellerCompany?.email ?? (companyInfo?.email ?? '');
    final sellerTaxNo = sellerCompany?.taxNumber ?? '';
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        // Sol taraf - Satıcı bilgileri
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'SATICI BİLGİLERİ',
                style: pw.TextStyle(
                  fontSize: 14,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.black,
                  font: fontBold,
                ),
              ),
              pw.SizedBox(height: 12),
              _buildInfoField('Satıcı', sellerName, font, fontBold),
              _buildInfoField('Adres', sellerAddress, font, fontBold),
              _buildInfoField('Telefon', sellerPhone, font, fontBold),
              _buildInfoField('E-posta', sellerEmail, font, fontBold),
              if (sellerTaxNo.isNotEmpty)
                _buildInfoField('Vergi No', sellerTaxNo, font, fontBold),
            ],
          ),
        ),
        pw.SizedBox(width: 40),
        // Sağ taraf - Müşteri bilgileri
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'MÜŞTERİ BİLGİLERİ',
                style: pw.TextStyle(
                  fontSize: 14,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.black,
                  font: fontBold,
                ),
              ),
              pw.SizedBox(height: 12),
              _buildInfoField(
                'Ad Soyad',
                invoice.customer.name,
                font,
                fontBold,
              ),
              _buildInfoField(
                'E-posta',
                invoice.customer.email ?? '',
                font,
                fontBold,
              ),
              _buildInfoField(
                'Telefon',
                invoice.customer.phone ?? '',
                font,
                fontBold,
              ),
              _buildInfoField(
                'Adres',
                invoice.customer.address ?? '',
                font,
                fontBold,
              ),
              if (invoice.customer.taxNumber != null &&
                  invoice.customer.taxNumber!.isNotEmpty)
                _buildInfoField(
                  'Vergi No',
                  invoice.customer.taxNumber!,
                  font,
                  fontBold,
                ),
            ],
          ),
        ),
      ],
    );
  }

  /// Bilgi alanı
  pw.Widget _buildInfoField(
    String label,
    String value,
    pw.Font font,
    pw.Font fontBold,
  ) {
    if (value.isEmpty) return pw.SizedBox.shrink();

    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 6),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            label,
            style: pw.TextStyle(
              fontSize: 10,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.grey700,
              font: fontBold,
            ),
          ),
          pw.Text(
            value,
            style: pw.TextStyle(
              fontSize: 11,
              color: PdfColors.black,
              font: font,
            ),
          ),
        ],
      ),
    );
  }

  /// Ürün tablosu - Modern tasarım
  pw.Widget _buildItemsTable(Invoice invoice, pw.Font font, pw.Font fontBold) {
    return pw.Container(
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey400, width: 1),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
      ),
      child: pw.Table(
        border: pw.TableBorder(
          horizontalInside: pw.BorderSide(color: PdfColors.grey300, width: 0.5),
          bottom: pw.BorderSide(color: PdfColors.grey400, width: 1),
        ),
        columnWidths: const {
          0: pw.FlexColumnWidth(3), // Ürün adı
          1: pw.FlexColumnWidth(1), // Miktar
          2: pw.FlexColumnWidth(1.2), // Birim fiyat
          3: pw.FlexColumnWidth(1), // İskonto
          4: pw.FlexColumnWidth(1), // KDV
          5: pw.FlexColumnWidth(1.2), // Toplam
        },
        children: [
          // Başlık satırı
          pw.TableRow(
            decoration: pw.BoxDecoration(
              color: PdfColors.grey100,
              borderRadius: const pw.BorderRadius.only(
                topLeft: pw.Radius.circular(6),
                topRight: pw.Radius.circular(6),
              ),
            ),
            children: [
              _buildTableHeader('Ürün/Hizmet', fontBold),
              _buildTableHeader('Miktar', fontBold),
              _buildTableHeader('Birim Fiyat', fontBold),
              _buildTableHeader('İskonto', fontBold),
              _buildTableHeader('KDV', fontBold),
              _buildTableHeader('Toplam', fontBold),
            ],
          ),
          // Ürün satırları
          ...invoice.items.map((item) => _buildTableRow(item, font, fontBold)),
        ],
      ),
    );
  }

  /// Tablo başlık hücresi
  pw.Widget _buildTableHeader(String text, pw.Font fontBold) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: 11,
          fontWeight: pw.FontWeight.bold,
          color: PdfColors.black,
          font: fontBold,
        ),
        textAlign: pw.TextAlign.center,
      ),
    );
  }

  /// Tablo satırı
  pw.TableRow _buildTableRow(InvoiceItem item, pw.Font font, pw.Font fontBold) {
    return pw.TableRow(
      children: [
        pw.Padding(
          padding: const pw.EdgeInsets.all(12),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                item.productName ?? item.product?.name ?? 'Ürün',
                style: pw.TextStyle(
                  fontSize: 11,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.black,
                  font: fontBold,
                ),
              ),
              if ((item.productName ?? item.product?.description) != null &&
                  (item.productName ?? item.product?.description)!.isNotEmpty)
                pw.Text(
                  item.productName ?? item.product?.description ?? '',
                  style: pw.TextStyle(
                    fontSize: 9,
                    color: PdfColors.grey600,
                    font: font,
                  ),
                ),
            ],
          ),
        ),
        pw.Padding(
          padding: const pw.EdgeInsets.all(12),
          child: pw.Text(
            '${item.quantity.toStringAsFixed(0)} ${item.product?.unit ?? 'adet'}',
            style: pw.TextStyle(
              fontSize: 11,
              color: PdfColors.black,
              font: font,
            ),
            textAlign: pw.TextAlign.center,
          ),
        ),
        pw.Padding(
          padding: const pw.EdgeInsets.all(12),
          child: pw.Text(
            '${_getCurrencySymbol(item.currency ?? item.product?.currency ?? 'TRY')}${item.unitPrice.toStringAsFixed(2)}',
            style: pw.TextStyle(
              fontSize: 11,
              color: PdfColors.black,
              font: font,
            ),
            textAlign: pw.TextAlign.right,
          ),
        ),
        pw.Padding(
          padding: const pw.EdgeInsets.all(12),
          child: pw.Text(
            item.discountRate != null
                ? '%${item.discountRate!.toStringAsFixed(0)}'
                : '-',
            style: pw.TextStyle(
              fontSize: 11,
              color: PdfColors.black,
              font: font,
            ),
            textAlign: pw.TextAlign.center,
          ),
        ),
        pw.Padding(
          padding: const pw.EdgeInsets.all(12),
          child: pw.Text(
            item.taxRate != null ? '%${item.taxRate!.toStringAsFixed(0)}' : '-',
            style: pw.TextStyle(
              fontSize: 11,
              color: PdfColors.black,
              font: font,
            ),
            textAlign: pw.TextAlign.center,
          ),
        ),
        pw.Padding(
          padding: const pw.EdgeInsets.all(12),
          child: pw.Text(
            '${_getCurrencySymbol(item.currency ?? item.product?.currency ?? 'TRY')}${item.totalAmount.toStringAsFixed(2)}',
            style: pw.TextStyle(
              fontSize: 11,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.black,
              font: fontBold,
            ),
            textAlign: pw.TextAlign.right,
          ),
        ),
      ],
    );
  }

  /// Toplamlar bölümü
  pw.Widget _buildTotals(Invoice invoice, pw.Font font, pw.Font fontBold) {
    final subtotal = invoice.items.fold(
      0.0,
      (sum, item) => sum + item.subtotal,
    );
    final totalDiscount = invoice.items.fold(
      0.0,
      (sum, item) => sum + item.discountAmount,
    );
    final totalTax = invoice.items.fold(
      0.0,
      (sum, item) => sum + item.taxAmount,
    );
    final grandTotal = invoice.items.fold(
      0.0,
      (sum, item) => sum + item.totalAmount,
    );

    final currencySymbol = _getCurrencySymbol(invoice.currency);

    return pw.Container(
      padding: const pw.EdgeInsets.all(20),
      decoration: pw.BoxDecoration(
        color: PdfColors.grey50,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
        border: pw.Border.all(color: PdfColors.grey300, width: 1),
      ),
      child: pw.Column(
        children: [
          _buildTotalRow('Ara Toplam', subtotal, currencySymbol, font, fontBold),
          _buildTotalRow(
            'Toplam İskonto',
            totalDiscount,
            currencySymbol,
            font,
            fontBold,
          ),
          _buildTotalRow('Toplam KDV', totalTax, currencySymbol, font, fontBold),
          pw.Divider(color: PdfColors.grey400, thickness: 1),
          _buildTotalRow(
            'GENEL TOPLAM',
            grandTotal,
            currencySymbol,
            font,
            fontBold,
            isGrandTotal: true,
          ),
        ],
      ),
    );
  }

  /// Toplam satırı
  pw.Widget _buildTotalRow(
    String label,
    double value,
    String currencySymbol,
    pw.Font font,
    pw.Font fontBold, {
    bool isGrandTotal = false,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 4),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            label,
            style: pw.TextStyle(
              fontSize: isGrandTotal ? 14 : 11,
              fontWeight: isGrandTotal
                  ? pw.FontWeight.bold
                  : pw.FontWeight.bold,
              color: PdfColors.black,
              font: isGrandTotal ? fontBold : fontBold,
            ),
          ),
          pw.Text(
            '$currencySymbol${value.toStringAsFixed(2)}',
            style: pw.TextStyle(
              fontSize: isGrandTotal ? 14 : 11,
              fontWeight: isGrandTotal
                  ? pw.FontWeight.bold
                  : pw.FontWeight.bold,
              color: PdfColors.black,
              font: isGrandTotal ? fontBold : fontBold,
            ),
          ),
        ],
      ),
    );
  }

  /// Alt bilgi
  pw.Widget _buildFooter(Invoice invoice, pw.Font font, pw.Font fontBold) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(20),
      decoration: pw.BoxDecoration(
        color: PdfColors.grey100,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
        border: pw.Border.all(color: PdfColors.grey300, width: 1),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'ÖDEME BİLGİLERİ',
            style: pw.TextStyle(
              fontSize: 13,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.black,
              font: fontBold,
            ),
          ),
          pw.SizedBox(height: 12),
          if (invoice.terms != null && invoice.terms!.isNotEmpty)
            pw.Text(
              'Ödeme Koşulları: ${invoice.terms}',
              style: pw.TextStyle(
                fontSize: 12,
                color: PdfColors.black,
                font: font,
              ),
            ),
          pw.SizedBox(height: 8),
          pw.Text(
            'Bu bir proforma faturadır ve vergi beyannamesi yerine geçmez.',
            style: pw.TextStyle(
              fontSize: 13,
              fontStyle: pw.FontStyle.italic,
              color: PdfColors.grey700,
              font: font,
            ),
          ),
          pw.SizedBox(height: 8),

          // 'Oluşturulma Tarihi: ${DateFormat('dd.MM.yyyy HH:mm').format(invoice.createdAt)}',
        ],
      ),
    );
  }

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
}
