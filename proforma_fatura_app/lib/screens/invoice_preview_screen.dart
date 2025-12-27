import 'package:flutter/material.dart';
import '../constants/app_constants.dart';
import '../utils/text_formatter.dart';
import '../models/invoice.dart';
import '../models/company_info.dart';
// yoksa ekle
import '../widgets/invoice_terms_list.dart';

class InvoicePreviewScreen extends StatelessWidget {
  final Invoice invoice;
  final CompanyInfo companyInfo;

  const InvoicePreviewScreen({
    super.key,
    required this.invoice,
    required this.companyInfo,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Fatura Önizleme'),
        actions: [
          IconButton(
            icon: const Icon(Icons.print),
            onPressed: () {
              // TODO: PDF oluşturma işlemi
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('PDF oluşturma özelliği yakında eklenecek'),
                  backgroundColor: Colors.orange,
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: () {
              // TODO: Paylaşım işlemi
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Paylaşım özelliği yakında eklenecek'),
                  backgroundColor: Colors.orange,
                ),
              );
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Firma Bilgileri
            _buildCompanySection(),
            const SizedBox(height: 20),

            // Müşteri Bilgileri
            _buildCustomerSection(),
            const SizedBox(height: 20),

            // Fatura Detayları
            _buildInvoiceDetails(),
            const SizedBox(height: 20),

            // Ürün Listesi
            _buildProductsSection(),
            const SizedBox(height: 20),

            // Toplam Bilgileri
            _buildTotalsSection(),
            const SizedBox(height: 20),

            // Notlar ve Şartlar
            if (invoice.notes != null || invoice.terms != null)
              _buildNotesSection(),
          ],
        ),
      ),
    );
  }

  Widget _buildCompanySection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              companyInfo.name,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            if (companyInfo.address != null) ...[
              const SizedBox(height: 8),
              Text(companyInfo.address!),
            ],
            if (companyInfo.phone != null) ...[
              const SizedBox(height: 4),
              Text('Tel: ${companyInfo.phone}'),
            ],
            if (companyInfo.email != null) ...[
              const SizedBox(height: 4),
              Text('E-posta: ${companyInfo.email}'),
            ],
            if (companyInfo.taxNumber != null) ...[
              const SizedBox(height: 4),
              Text('Vergi No: ${companyInfo.taxNumber}'),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCustomerSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Müşteri Bilgileri',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(invoice.customer.name, style: const TextStyle(fontSize: 16)),
            if (invoice.customer.address != null) ...[
              const SizedBox(height: 4),
              Text(invoice.customer.address!),
            ],
            if (invoice.customer.phone != null) ...[
              const SizedBox(height: 4),
              Text('Tel: ${invoice.customer.phone}'),
            ],
            if (invoice.customer.email != null) ...[
              const SizedBox(height: 4),
              Text('E-posta: ${invoice.customer.email}'),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInvoiceDetails() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Fatura No: ${invoice.invoiceNumber}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  'Tarih: ${invoice.invoiceDate.day}/${invoice.invoiceDate.month}/${invoice.invoiceDate.year}',
                ),
                const SizedBox(height: 4),
                Text(
                  'Vade: ${invoice.dueDate.day}/${invoice.dueDate.month}/${invoice.dueDate.year}',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProductsSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Ürünler',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            ...invoice.items.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: Text(
                        item.productName ?? item.product?.name ?? 'Ürün',
                      ),
                    ),
                    Expanded(
                      flex: 1,
                      child: Text(
                        '${TextFormatter.formatQuantity(item.quantity)} ${item.product?.unit ?? 'adet'}',
                      ),
                    ),
                    Expanded(
                      flex: 1,
                      child: Text('₺${item.unitPrice.toStringAsFixed(2)}'),
                    ),
                    Expanded(
                      flex: 1,
                      child: Text('₺${item.totalAmount.toStringAsFixed(2)}'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTotalsSection() {
    final subtotal = invoice.items.fold(
      0.0,
      (sum, item) => sum + item.subtotal,
    );
    final discountAmount = subtotal * (invoice.discountRate ?? 0.0) / 100;
    final totalTax = invoice.items.fold(
      0.0,
      (sum, item) => sum + item.taxAmount,
    );
    final total = subtotal - discountAmount + totalTax;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Ara Toplam:'),
                Text('₺${subtotal.toStringAsFixed(2)}'),
              ],
            ),
            if (invoice.discountRate != null && invoice.discountRate! > 0) ...[
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'İskonto (%${TextFormatter.formatPercent(invoice.discountRate)}):',
                  ),
                  Text('-₺${discountAmount.toStringAsFixed(2)}'),
                ],
              ),
            ],
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('KDV Toplamı:'),
                Text('₺${totalTax.toStringAsFixed(2)}'),
              ],
            ),
            const Divider(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'TOPLAM:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                ),
                Text(
                  '₺${total.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    color: AppConstants.primaryColor,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNotesSection() {
    final hasNotes = (invoice.notes ?? '').trim().isNotEmpty;
    final hasPlainTerms = (invoice.terms ?? '').trim().isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (hasNotes || hasPlainTerms)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (hasNotes) ...[
                    const Text(
                      'Notlar',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18, // başlık bir tık büyük
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      invoice.notes!.trim(),
                      style: const TextStyle(
                        fontSize: 16,
                      ), // metin bir tık büyük
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (hasPlainTerms) ...[
                    const Text(
                      'Ödeme Şartları',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 20, // başlık bir tık büyük
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      invoice.terms!.trim(),
                      style: const TextStyle(
                        fontSize: 16,
                      ), // metin bir tık büyük
                    ),
                  ],
                ],
              ),
            ),
          ),

        // Seçili ödeme ve şartlar (DB'den gelenler)
        InvoiceTermsList(
          invoiceId: int.tryParse(invoice.id ?? ''),
          title: 'Seçili Ödeme ve Şartlar',
          padding: const EdgeInsets.all(16),
        ),
      ],
    );
  }
}
