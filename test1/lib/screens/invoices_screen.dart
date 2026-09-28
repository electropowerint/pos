import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/storage_service.dart';
import '../services/pdf_service.dart';
import '../theme/app_theme.dart';
import '../widgets/menu_button.dart';
import 'invoice_form_screen.dart';
import 'invoice_detail_screen.dart';
import '../models/models.dart';

class InvoicesScreen extends StatefulWidget {
  const InvoicesScreen({super.key});

  @override
  State<InvoicesScreen> createState() => _InvoicesScreenState();
}

class _InvoicesScreenState extends State<InvoicesScreen> {
  String _query = '';
  String _status = 'all';
  String _sort = 'new';

  int _statusRank(Invoice i) => i.isFullyPaid ? 0 : (i.isPartiallyPaid ? 1 : 2);

  int _cmp(Invoice a, Invoice b) {
    switch (_sort) {
      case 'old':
        return a.createdAt.compareTo(b.createdAt);
      case 'high':
        return b.grandTotal.compareTo(a.grandTotal);
      case 'low':
        return a.grandTotal.compareTo(b.grandTotal);
      case 'paidfirst':
        final d = _statusRank(a) - _statusRank(b);
        return d != 0 ? d : b.createdAt.compareTo(a.createdAt);
      case 'unpaidfirst':
        final d = _statusRank(b) - _statusRank(a);
        return d != 0 ? d : b.createdAt.compareTo(a.createdAt);
      default:
        return b.createdAt.compareTo(a.createdAt);
    }
  }

  Widget _summaryCard(String label, String value, Color color, Color soft, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.line),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: soft, borderRadius: BorderRadius.circular(9)),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: AppTheme.ink3)),
                const SizedBox(height: 2),
                Text(value,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.sora(fontSize: 15, fontWeight: FontWeight.w800, color: color)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: StorageService(),
      builder: (context, _) {
        final storage = StorageService();
        final currency = storage.settings.currency.isEmpty ? 'Rs' : storage.settings.currency;

        final filtered = storage.invoices.where((i) {
          if (_query.isNotEmpty) {
            final q = _query.toLowerCase();
            if (!(i.number.toLowerCase().contains(q) ||
                i.clientName.toLowerCase().contains(q) ||
                i.clientPhone.toLowerCase().contains(q))) return false;
          }
          if (_status == 'paid') return i.isFullyPaid;
          if (_status == 'partial') return i.isPartiallyPaid;
          if (_status == 'unpaid') return !i.isFullyPaid && !i.isPartiallyPaid;
          return true;
        }).toList()..sort(_cmp);

        // proportional: every invoice splits into what came in and what is still due
        final paidValue = filtered.fold<double>(0.0, (s, i) => s + i.paidAmount);
        final dueValue = filtered.fold<double>(0.0, (s, i) => s + i.remainingAmount);

        return Scaffold(
          backgroundColor: AppTheme.bg,
          appBar: AppBar(
            leading: const MenuButton(),
            backgroundColor: AppTheme.surface,
            elevation: 0,
            title: Text(
              'Invoices',
              style: GoogleFonts.sora(fontSize: 18, fontWeight: FontWeight.w800, color: AppTheme.ink),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh_rounded, color: AppTheme.ink2),
                tooltip: 'Pull from Firebase',
                onPressed: () async {
                  await storage.pullFromCloud();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Firebase sync: ${storage.syncStatus}')),
                    );
                  }
                },
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            heroTag: 'invoices_fab',
            backgroundColor: AppTheme.brand,
            foregroundColor: Colors.white,
            elevation: 3,
            icon: const Icon(Icons.add_rounded),
            label: Text('New Invoice', style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const InvoiceFormScreen()),
              );
            },
          ),
          body: Column(
            children: [
              // Search input
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: TextField(
                  decoration: InputDecoration(
                    hintText: 'Search by invoice # or client name...',
                    prefixIcon: const Icon(Icons.search_rounded, size: 20, color: AppTheme.ink3),
                    suffixIcon: _query.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded, size: 18),
                            onPressed: () => setState(() => _query = ''),
                          )
                        : null,
                    isDense: true,
                  ),
                  onChanged: (val) => setState(() => _query = val.trim()),
                ),
              ),

              // Paid / Unpaid totals across the invoices on screen
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: _summaryCard('Paid', '$currency ${paidValue.toStringAsFixed(0)}',
                          AppTheme.green, AppTheme.greenSoft, Icons.check_circle_outline_rounded),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _summaryCard('Unpaid', '$currency ${dueValue.toStringAsFixed(0)}',
                          AppTheme.red, AppTheme.redSoft, Icons.schedule_rounded),
                    ),
                  ],
                ),
              ),

              // Status filter + sort
              SizedBox(
                height: 42,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    for (final opt in const [
                      ['all', 'All statuses'],
                      ['paid', 'Paid'],
                      ['partial', 'Partial'],
                      ['unpaid', 'Unpaid'],
                    ])
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: FilterChip(
                          label: Text(opt[1]),
                          selected: _status == opt[0],
                          showCheckmark: false,
                          selectedColor: AppTheme.brandSoft,
                          checkmarkColor: AppTheme.brand,
                          onSelected: (_) => setState(() => _status = opt[0]),
                        ),
                      ),
                    const SizedBox(width: 4),
                    SizedBox(
                      width: 170,
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          isExpanded: true,
                          value: _sort,
                          hint: const Text('Sort'),
                          style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.ink2),
                          items: const [
                            DropdownMenuItem(value: 'new', child: Text('Newest first')),
                            DropdownMenuItem(value: 'old', child: Text('Oldest first')),
                            DropdownMenuItem(value: 'high', child: Text('Amount: high to low')),
                            DropdownMenuItem(value: 'low', child: Text('Amount: low to high')),
                            DropdownMenuItem(value: 'paidfirst', child: Text('Paid first')),
                            DropdownMenuItem(value: 'unpaidfirst', child: Text('Unpaid first')),
                          ],
                          onChanged: (v) => setState(() => _sort = v ?? 'new'),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Counter
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${filtered.length} invoice${filtered.length == 1 ? '' : 's'}',
                      style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.ink3),
                    ),
                  ],
                ),
              ),

              // List
              Expanded(
                child: filtered.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 60,
                              height: 60,
                              decoration: const BoxDecoration(
                                color: AppTheme.brandSoft,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.receipt_long_outlined, size: 30, color: AppTheme.brand),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              _query.isEmpty ? 'No invoices created yet' : 'No matches found',
                              style: GoogleFonts.inter(color: AppTheme.ink2, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 6, 16, 80),
                        itemCount: filtered.length,
                        itemBuilder: (context, index) {
                          final inv = filtered[index];
                          final dateStr = DateFormat('dd MMM yyyy').format(
                            DateTime.fromMillisecondsSinceEpoch(inv.createdAt),
                          );

                          return Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            decoration: BoxDecoration(
                              color: AppTheme.surface,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: AppTheme.line),
                              boxShadow: [
                                BoxShadow(
                                  color: AppTheme.ink.withOpacity(0.03),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(16),
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(builder: (_) => InvoiceDetailScreen(invoice: inv)),
                                );
                              },
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Row(
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                              decoration: BoxDecoration(
                                                color: AppTheme.brandSoft,
                                                borderRadius: BorderRadius.circular(8),
                                              ),
                                              child: Text(
                                                inv.number,
                                                style: GoogleFonts.sora(
                                                  fontWeight: FontWeight.w700,
                                                  fontSize: 14,
                                                  color: AppTheme.brand,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            if (inv.isFullyPaid)
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: AppTheme.greenSoft,
                                                  borderRadius: BorderRadius.circular(6),
                                                  border: Border.all(color: AppTheme.green.withOpacity(0.3)),
                                                ),
                                                child: const Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    Icon(Icons.lock_rounded, size: 10, color: AppTheme.green),
                                                    SizedBox(width: 3),
                                                    Text('PAID', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.green)),
                                                  ],
                                                ),
                                              )
                                            else if (inv.isPartiallyPaid)
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: AppTheme.amberSoft,
                                                  borderRadius: BorderRadius.circular(6),
                                                  border: Border.all(color: AppTheme.amber.withOpacity(0.3)),
                                                ),
                                                child: Text('PARTIAL ($currency ${inv.paidAmount.toStringAsFixed(0)})',
                                                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.amber)),
                                              )
                                            else if (inv.isOverdueOneWeek)
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: AppTheme.redSoft,
                                                  borderRadius: BorderRadius.circular(6),
                                                  border: Border.all(color: AppTheme.red.withOpacity(0.3)),
                                                ),
                                                child: const Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    Icon(Icons.warning_amber_rounded, size: 11, color: AppTheme.red),
                                                    SizedBox(width: 2),
                                                    Text('OVERDUE (1w+)', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.red)),
                                                  ],
                                                ),
                                              )
                                            else
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: AppTheme.redSoft,
                                                  borderRadius: BorderRadius.circular(6),
                                                ),
                                                child: const Text('UNPAID', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.red)),
                                              ),
                                          ],
                                        ),
                                        Text(
                                          '$currency ${inv.grandTotal.toStringAsFixed(0)}',
                                          style: GoogleFonts.sora(
                                            fontWeight: FontWeight.w800,
                                            fontSize: 16,
                                            color: AppTheme.ink,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Expanded(
                                          child: Text(
                                            inv.clientName.isEmpty ? 'Walk-in Client' : inv.clientName,
                                            style: GoogleFonts.inter(
                                              color: AppTheme.ink,
                                              fontSize: 14,
                                              fontWeight: FontWeight.w600,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        Text(
                                          dateStr,
                                          style: GoogleFonts.inter(color: AppTheme.ink3, fontSize: 12),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                    const Divider(color: AppTheme.line, height: 1),
                                    const SizedBox(height: 6),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          inv.isFullyPaid
                                              ? 'Revenue: $currency ${inv.paidAmount.toStringAsFixed(0)}'
                                              : 'Paid: $currency ${inv.paidAmount.toStringAsFixed(0)} · Due: $currency ${inv.remainingAmount.toStringAsFixed(0)}',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                            color: inv.isFullyPaid ? AppTheme.green : AppTheme.ink3,
                                          ),
                                        ),
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            // Share PDF Only (No text)
                                            IconButton(
                                              icon: const Icon(Icons.share_rounded, size: 18, color: AppTheme.brand),
                                              tooltip: 'Share PDF File Only',
                                              onPressed: () => PdfService.sharePdfOnly(inv),
                                            ),
                                            // Print / View PDF
                                            IconButton(
                                              icon: const Icon(Icons.print_outlined, size: 18, color: AppTheme.ink2),
                                              tooltip: 'Print / Download PDF',
                                              onPressed: () => PdfService.printPdf(inv),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}
