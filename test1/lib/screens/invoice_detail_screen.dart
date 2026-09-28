import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../models/models.dart';
import '../services/storage_service.dart';
import '../services/pdf_service.dart';
import '../theme/app_theme.dart';
import 'invoice_form_screen.dart';

class InvoiceDetailScreen extends StatelessWidget {
  final Invoice invoice;
  const InvoiceDetailScreen({super.key, required this.invoice});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: StorageService(),
      builder: (context, _) {
        final storage = StorageService();
        final inv = storage.invoices.firstWhere(
          (i) => i.id == invoice.id,
          orElse: () => invoice,
        );

        final currency = storage.settings.currency.isEmpty ? 'Rs' : storage.settings.currency;
        final dateStr = DateFormat('dd/MM/yyyy').format(
          DateTime.fromMillisecondsSinceEpoch(inv.createdAt),
        );

        return Scaffold(
          appBar: AppBar(
            title: Text(inv.number),
            actions: [
              IconButton(
                icon: const Icon(Icons.share, color: AppTheme.primary),
                tooltip: 'Share PDF File',
                onPressed: () => _openShareSheet(context, inv),
              ),

              IconButton(
                icon: Icon(
                  inv.isFullyPaid ? Icons.lock_outline_rounded : Icons.edit_outlined,
                  color: inv.isFullyPaid ? AppTheme.ink3 : AppTheme.ink,
                ),
                tooltip: inv.isFullyPaid ? 'Invoice is fully paid and locked' : 'Edit',
                onPressed: () {
                  if (inv.isFullyPaid) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('This invoice is fully paid and locked from editing.'),
                        backgroundColor: AppTheme.amber,
                      ),
                    );
                    return;
                  }
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => InvoiceFormScreen(invoice: inv)),
                  );
                },
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, color: AppTheme.rose),
                tooltip: 'Delete',
                onPressed: () async {
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Delete Invoice?'),
                      content: Text('Are you sure you want to delete ${inv.number}?'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Cancel'),
                        ),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.rose),
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('Delete'),
                        ),
                      ],
                    ),
                  );
                  if (confirm == true) {
                    await storage.deleteInvoice(inv.id);
                    Navigator.pop(context);
                  }
                },
              ),
            ],
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                // Top Meta row
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Invoice ${inv.number}  ·  $dateStr',
                      style: const TextStyle(color: AppTheme.textMuted, fontSize: 13),
                    ),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      ),
                      icon: const Icon(Icons.share, size: 16),
                      label: const Text('Share / Send', style: TextStyle(fontSize: 13)),
                      onPressed: () => _openShareSheet(context, inv),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // ── Payment Status & Action Card ──
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: inv.isFullyPaid
                        ? AppTheme.greenSoft
                        : (inv.isPartiallyPaid ? AppTheme.amberSoft : AppTheme.redSoft),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: inv.isFullyPaid
                          ? AppTheme.green.withOpacity(0.3)
                          : (inv.isPartiallyPaid ? AppTheme.amber.withOpacity(0.3) : AppTheme.red.withOpacity(0.3)),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        inv.isFullyPaid
                            ? Icons.check_circle_rounded
                            : (inv.isPartiallyPaid ? Icons.timelapse_rounded : Icons.pending_actions_rounded),
                        color: inv.isFullyPaid
                            ? AppTheme.green
                            : (inv.isPartiallyPaid ? AppTheme.amber : AppTheme.red),
                        size: 24,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  inv.isFullyPaid
                                      ? 'PAID IN FULL'
                                      : (inv.isPartiallyPaid ? 'PARTIALLY PAID' : 'UNPAID'),
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 13,
                                    color: inv.isFullyPaid
                                        ? AppTheme.green
                                        : (inv.isPartiallyPaid ? AppTheme.amber : AppTheme.red),
                                  ),
                                ),
                                if (inv.isFullyPaid) ...[
                                  const SizedBox(width: 6),
                                  const Icon(Icons.lock_rounded, size: 14, color: AppTheme.green),
                                  const SizedBox(width: 2),
                                  const Text('Locked', style: TextStyle(fontSize: 11, color: AppTheme.green, fontWeight: FontWeight.w600)),
                                ],
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              inv.isFullyPaid
                                  ? 'Recognized Revenue: $currency ${inv.paidAmount.toStringAsFixed(0)}'
                                  : 'Paid: $currency ${inv.paidAmount.toStringAsFixed(0)}  ·  Due: $currency ${inv.remainingAmount.toStringAsFixed(0)}',
                              style: TextStyle(
                                fontSize: 12,
                                color: inv.isFullyPaid
                                    ? AppTheme.green
                                    : (inv.isPartiallyPaid ? AppTheme.amber : AppTheme.red),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: inv.isFullyPaid ? Colors.white : AppTheme.brand,
                          foregroundColor: inv.isFullyPaid ? AppTheme.green : Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: () => _openPaymentDialog(context, inv),
                        child: Text(
                          inv.isFullyPaid ? 'Update' : (inv.isPartiallyPaid ? 'Add Pay' : 'Mark Paid'),
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Luxury Paper Container (White paper preview matching Web App & PDF exactly)
                Builder(
                  builder: (context) {
                    Uint8List? logoBytes;
                    if (storage.settings.logo.trim().isNotEmpty) {
                      try {
                        final logoStr = storage.settings.logo.trim();
                        final commaIdx = logoStr.indexOf(',');
                        final base64Part = commaIdx != -1 ? logoStr.substring(commaIdx + 1) : logoStr;
                        logoBytes = base64Decode(base64Part.trim());
                      } catch (_) {}
                    }

                    final List<String> clLines = [];
                    if (inv.clientName.trim().isNotEmpty) clLines.add(inv.clientName.trim());
                    if (inv.clientPhone.trim().isNotEmpty) clLines.add(inv.clientPhone.trim());
                    if (inv.clientAddress.trim().isNotEmpty) {
                      for (final l in inv.clientAddress.split('\n')) {
                        final t = l.trim();
                        if (t.isNotEmpty) clLines.add(t);
                      }
                    }
                    if (inv.clientEmail.trim().isNotEmpty) clLines.add(inv.clientEmail.trim());

                    final rowCount = storage.settings.invoiceRows < 7 ? 7 : storage.settings.invoiceRows;
                    final activeItems = inv.items.where((it) => it.name.trim().isNotEmpty).toList();
                    final emptyRowCount = (rowCount - activeItems.length).clamp(0, 30);

                    return Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 26),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.18),
                            blurRadius: 16,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Top Header: Logo / Brand (Left) & Serif "Invoice" (Right)
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (logoBytes != null)
                                SizedBox(
                                  width: 60,
                                  height: 46,
                                  child: Image.memory(logoBytes, fit: BoxFit.contain, alignment: Alignment.topLeft),
                                )
                              else
                                Container(
                                  height: 46,
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    storage.settings.businessName.isNotEmpty ? storage.settings.businessName : 'Business',
                                    style: GoogleFonts.playfairDisplay(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: const Color(0xFF141414),
                                    ),
                                  ),
                                ),
                              Text(
                                'Invoice',
                                style: GoogleFonts.playfairDisplay(
                                  fontSize: 34,
                                  color: const Color(0xFF141414),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),

                          // Billed To (Left) & Invoice No / Date (Right)
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Billed to:',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF141414),
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  ...clLines.asMap().entries.map((entry) {
                                    final i = entry.key;
                                    final l = entry.value;
                                    return Padding(
                                      padding: const EdgeInsets.only(bottom: 2),
                                      child: Text(
                                        l,
                                        style: TextStyle(
                                          fontSize: i == 0 ? 11 : 10,
                                          fontWeight: i == 0 ? FontWeight.bold : FontWeight.normal,
                                          color: i == 0 ? const Color(0xFF181818) : const Color(0xFF3C3C3C),
                                        ),
                                      ),
                                    );
                                  }),
                                ],
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    'Invoice No. ${inv.number.isNotEmpty ? inv.number : '12345'}',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: Color(0xFF141414),
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    dateStr,
                                    style: const TextStyle(
                                      fontSize: 10,
                                      color: Color(0xFF5A5A5A),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 18),

                          // Table Header (Thick underline, transparent bg)
                          Container(
                            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                            decoration: const BoxDecoration(
                              border: Border(bottom: BorderSide(color: Color(0xFF181818), width: 1.8)),
                            ),
                            child: const Row(
                              children: [
                                Expanded(flex: 5, child: Text('Item', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF101010)))),
                                SizedBox(width: 55, child: Text('Quantity', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF101010)))),
                                SizedBox(width: 75, child: Text('Unit Price', textAlign: TextAlign.right, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF101010)))),
                                SizedBox(width: 75, child: Text('Total', textAlign: TextAlign.right, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF101010)))),
                              ],
                            ),
                          ),

                          // Table Active Items
                          ...activeItems.map((it) {
                            final qtyStr = it.qty.toStringAsFixed(it.qty.truncateToDouble() == it.qty ? 0 : 2);
                            return Container(
                              padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 4),
                              decoration: const BoxDecoration(
                                border: Border(bottom: BorderSide(color: Color(0xFFC8C8C8), width: 0.6)),
                              ),
                              child: Row(
                                children: [
                                  Expanded(flex: 5, child: Text(it.name, style: const TextStyle(fontSize: 11, color: Color(0xFF1E1E1E)))),
                                  SizedBox(width: 55, child: Text(qtyStr, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, color: Color(0xFF1E1E1E)))),
                                  SizedBox(width: 75, child: Text('$currency ${it.price.toStringAsFixed(0)}', textAlign: TextAlign.right, style: const TextStyle(fontSize: 11, color: Color(0xFF1E1E1E)))),
                                  SizedBox(width: 75, child: Text('$currency ${it.total.toStringAsFixed(0)}', textAlign: TextAlign.right, style: const TextStyle(fontSize: 11, color: Color(0xFF1E1E1E)))),
                                ],
                              ),
                            );
                          }),

                          // Placeholder rows with '------'
                          ...List.generate(emptyRowCount, (index) => Container(
                            padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 4),
                            decoration: const BoxDecoration(
                              border: Border(bottom: BorderSide(color: Color(0xFFC8C8C8), width: 0.6)),
                            ),
                            child: const Row(
                              children: [
                                Expanded(flex: 5, child: Text('------', style: TextStyle(fontSize: 11, color: Color(0xFFA0A0A0)))),
                                SizedBox(width: 55, child: Text('------', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: Color(0xFFA0A0A0)))),
                                SizedBox(width: 75, child: Text('------', textAlign: TextAlign.right, style: TextStyle(fontSize: 11, color: Color(0xFFA0A0A0)))),
                                SizedBox(width: 75, child: Text('------', textAlign: TextAlign.right, style: TextStyle(fontSize: 11, color: Color(0xFFA0A0A0)))),
                              ],
                            ),
                          )),

                          const SizedBox(height: 16),

                          // Subtotal & Total Badge
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              SizedBox(
                                width: 215,
                                child: Column(
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          const Text('Subtotal', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF181818))),
                                          Text('$currency ${inv.subtotal.toStringAsFixed(0)}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF181818))),
                                        ],
                                      ),
                                    ),
                                    if (inv.calculatedDiscount > 0) ...[
                                      const SizedBox(height: 3),
                                      Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            const Text('Discount', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF181818))),
                                            Text('- $currency ${inv.calculatedDiscount.toStringAsFixed(0)}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF181818))),
                                          ],
                                        ),
                                      ),
                                    ],
                                    const SizedBox(height: 6),
                                    Container(
                                      height: 28,
                                      padding: const EdgeInsets.symmetric(horizontal: 10),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF181818),
                                        borderRadius: BorderRadius.circular(2),
                                      ),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          const Text('Total', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white)),
                                          Text('$currency ${inv.grandTotal.toStringAsFixed(0)}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white)),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 32),

                          // Bottom Area: "Thank You!" script
                          Text(
                            'Thank You!',
                            style: GoogleFonts.playfairDisplay(
                              fontSize: 26,
                              fontStyle: FontStyle.italic,
                              color: const Color(0xFF181818),
                            ),
                          ),
                          const SizedBox(height: 14),

                          // Payment Information (Left) + Business signature (Right)
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Payment Information',
                                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF181818)),
                                    ),
                                    const SizedBox(height: 3),
                                    if (inv.notes.trim().isNotEmpty)
                                      Text(inv.notes.trim(), style: const TextStyle(fontSize: 9, color: Color(0xFF464646)))
                                    else ...[
                                      Text(storage.settings.businessName.isNotEmpty ? storage.settings.businessName : 'Business', style: const TextStyle(fontSize: 9, color: Color(0xFF464646))),
                                      if (storage.settings.phone.trim().isNotEmpty)
                                        Text('Contact: ${storage.settings.phone.trim()}', style: const TextStyle(fontSize: 9, color: Color(0xFF464646))),
                                      if (storage.settings.email.trim().isNotEmpty)
                                        Text('Email: ${storage.settings.email.trim()}', style: const TextStyle(fontSize: 9, color: Color(0xFF464646))),
                                    ],
                                  ],
                                ),
                              ),
                              const SizedBox(width: 16),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    storage.settings.signName.trim().isNotEmpty
                                        ? storage.settings.signName.trim()
                                        : (storage.settings.businessName.trim().isNotEmpty
                                            ? storage.settings.businessName.trim()
                                            : 'Juliana Silva'),
                                    style: GoogleFonts.playfairDisplay(
                                      fontSize: 15,
                                      color: const Color(0xFF141414),
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  const Text(
                                    'Proprietor',
                                    style: TextStyle(fontSize: 9, color: Color(0xFF505050)),
                                    textAlign: TextAlign.right,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
                const SizedBox(height: 40),
              ],
            ),
          ),
        );
      },
    );
  }

  void _openShareSheet(BuildContext context, Invoice inv) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Share / Send — ${inv.number}',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),

              // 1. Share PDF File (Sends ONLY PDF to WhatsApp / any contact)
              Material(
                color: Colors.transparent,
                child: ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: const Color(0xFF25D366), borderRadius: BorderRadius.circular(10)),
                    child: const Icon(Icons.send, color: Colors.white, size: 20),
                  ),
                  title: const Text('Send PDF via WhatsApp / Apps', style: TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: const Text('Pick contact · Only PDF file will be attached', style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: AppTheme.textMuted),
                  onTap: () {
                    Navigator.pop(ctx);
                    PdfService.sharePdfOnly(inv);
                  },
                ),
              ),
              const Divider(color: AppTheme.border),

              // 2. Download / Print PDF
              Material(
                color: Colors.transparent,
                child: ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: const Color(0xFFE11D48), borderRadius: BorderRadius.circular(10)),
                    child: const Icon(Icons.picture_as_pdf, color: Colors.white, size: 20),
                  ),
                  title: const Text('Download / Print PDF', style: TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text('Save ${inv.number}.pdf to device', style: const TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: AppTheme.textMuted),
                  onTap: () {
                    Navigator.pop(ctx);
                    PdfService.printPdf(inv);
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _openPaymentDialog(BuildContext context, Invoice inv) {
    final storage = StorageService();
    final currency = storage.settings.currency.isEmpty ? 'Rs' : storage.settings.currency;
    final total = inv.grandTotal;
    final currentPaid = inv.paidAmount;
    final remaining = inv.remainingAmount;
    final half = (total / 2.0);

    final customCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: AppTheme.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              const Icon(Icons.payment_rounded, color: AppTheme.brand, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Record Payment — ${inv.number}',
                  style: GoogleFonts.sora(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Summary card
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.bg,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppTheme.line),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Grand Total:', style: TextStyle(fontSize: 13, color: AppTheme.ink3)),
                          Text('$currency ${total.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Current Paid:', style: TextStyle(fontSize: 13, color: AppTheme.ink3)),
                          Text('$currency ${currentPaid.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.green)),
                        ],
                      ),
                      const Divider(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Balance Due:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.ink)),
                          Text('$currency ${remaining.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: AppTheme.red)),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                const Text('Choose Payment Option:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.ink2)),
                const SizedBox(height: 10),

                // Option 1: Full Payment
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    side: const BorderSide(color: AppTheme.green),
                    backgroundColor: AppTheme.greenSoft,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: const Icon(Icons.check_circle_outline_rounded, color: AppTheme.green, size: 18),
                  label: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Full payment', style: TextStyle(color: AppTheme.green, fontWeight: FontWeight.bold)),
                      Text('$currency ${remaining.toStringAsFixed(0)}', style: const TextStyle(color: AppTheme.green, fontWeight: FontWeight.w800)),
                    ],
                  ),
                  onPressed: () async {
                    await storage.setInvoiceStatus(inv.id, 'paid');
                    if (ctx.mounted) Navigator.pop(ctx);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Invoice ${inv.number} marked FULLY PAID and locked.'),
                          backgroundColor: AppTheme.green,
                        ),
                      );
                    }
                  },
                ),
                const SizedBox(height: 8),

                // Option 2: Half Payment
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    side: const BorderSide(color: AppTheme.amber),
                    backgroundColor: AppTheme.amberSoft,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: const Icon(Icons.pie_chart_outline_rounded, color: AppTheme.amber, size: 18),
                  label: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Half payment', style: TextStyle(color: AppTheme.amber, fontWeight: FontWeight.bold)),
                      Text('$currency ${half.toStringAsFixed(0)}', style: const TextStyle(color: AppTheme.amber, fontWeight: FontWeight.w800)),
                    ],
                  ),
                  onPressed: () async {
                    await storage.applyPayment(inv.id, half);
                    if (ctx.mounted) Navigator.pop(ctx);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Invoice ${inv.number} marked PARTIALLY PAID ($currency ${half.toStringAsFixed(0)}).'),
                          backgroundColor: AppTheme.amber,
                        ),
                      );
                    }
                  },
                ),
                const SizedBox(height: 14),

                // Option 3: Partial payment — an amount below the invoice value
                const Text('Partial payment (below the invoice value):', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.ink2)),
                const SizedBox(height: 6),
                TextField(
                  controller: customCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    prefixText: '$currency ',
                    hintText: 'e.g. 5000',
                    helperText: 'Must stay below $currency ${total.toStringAsFixed(0)} — it is added to what was already received',
                    helperMaxLines: 2,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            if (currentPaid > 0)
              TextButton(
                onPressed: () async {
                  await storage.setInvoiceStatus(inv.id, 'unpaid');
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Invoice ${inv.number} marked unpaid — the full amount is due again.')),
                    );
                  }
                },
                child: const Text('Mark unpaid', style: TextStyle(color: AppTheme.rose, fontSize: 12)),
              ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.brand,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () async {
                final amt = double.tryParse(customCtrl.text.trim());
                if (amt == null || amt <= 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Enter the payment amount'), backgroundColor: AppTheme.rose),
                  );
                  return;
                }
                if (amt >= total) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('That is not a partial amount — use Full payment'), backgroundColor: AppTheme.rose),
                  );
                  return;
                }
                await storage.applyPayment(inv.id, amt);
                if (ctx.mounted) Navigator.pop(ctx);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Payment of $currency ${amt.toStringAsFixed(0)} recorded for ${inv.number}.'),
                      backgroundColor: AppTheme.amber,
                    ),
                  );
                }
              },
              child: const Text('Record partial'),
            ),
          ],
        );
      },
    );
  }
}
