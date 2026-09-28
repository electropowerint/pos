import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';
import '../widgets/menu_button.dart';
import 'invoice_form_screen.dart';
import 'invoice_detail_screen.dart';

class DashboardScreen extends StatelessWidget {
  final VoidCallback onNavigateToInvoices;
  final VoidCallback onNavigateToExpenses;

  const DashboardScreen({
    super.key,
    required this.onNavigateToInvoices,
    required this.onNavigateToExpenses,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: StorageService(),
      builder: (context, _) {
        final storage = StorageService();
        final currency = storage.settings.currency.isEmpty ? 'Rs' : storage.settings.currency;

        final now = DateTime.now();
        final nowMs = now.millisecondsSinceEpoch;
        final startOfToday = DateTime(now.year, now.month, now.day).millisecondsSinceEpoch;
        final startOfMonth = DateTime(now.year, now.month, 1).millisecondsSinceEpoch;

        // Revenue recognized on Cash Basis (only when paid)
        final todayRevenue = storage.invoices
            .where((i) => i.createdAt >= startOfToday)
            .fold(0.0, (sum, i) => sum + i.paidAmount);

        final collectedRevenue = storage.invoices.fold(0.0, (sum, i) => sum + i.paidAmount);
        final pendingBalance = storage.invoices.fold(0.0, (sum, i) => sum + i.remainingAmount);

        final monthExpenses = storage.expenses
            .where((e) => e.date >= startOfMonth)
            .fold(0.0, (sum, e) => sum + e.amount);

        final overdueInvoices = storage.invoices.where((i) => i.isOverdueOneWeek).toList();
        final recentInvoices = storage.invoices.take(5).toList();

        return Scaffold(
          backgroundColor: AppTheme.bg,
          appBar: AppBar(
            leading: const MenuButton(),
            backgroundColor: AppTheme.surface,
            elevation: 0,
            title: Row(
              children: [
                // Web app exact logo mark
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppTheme.brand, AppTheme.brandDark],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.brand.withOpacity(0.35),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: const Icon(Icons.grid_view_rounded, color: Colors.white, size: 18),
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      storage.settings.businessName.isEmpty ? 'ElectroPowerInt' : storage.settings.businessName,
                      style: GoogleFonts.sora(fontSize: 16, fontWeight: FontWeight.w800, color: AppTheme.ink),
                    ),
                    Text(
                      'Snapshot of sales & expenses',
                      style: GoogleFonts.inter(fontSize: 11, color: AppTheme.ink3),
                    ),
                  ],
                ),
              ],
            ),
            actions: [
              // Cloud Sync Status Pill
              Container(
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: storage.syncStatus.contains('Synced') ? AppTheme.greenSoft : AppTheme.brandSoft,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: storage.syncStatus.contains('Synced')
                        ? AppTheme.green.withOpacity(0.3)
                        : AppTheme.brand.withOpacity(0.3),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: storage.syncStatus.contains('Synced') ? AppTheme.green : AppTheme.brand,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      storage.syncStatus,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: storage.syncStatus.contains('Synced') ? AppTheme.green : AppTheme.brand,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: storage.isSyncing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.brand),
                      )
                    : const Icon(Icons.sync, size: 20, color: AppTheme.ink2),
                tooltip: 'Sync Data with Cloud',
                onPressed: () async {
                  await storage.pullFromCloud();
                  await storage.pushToCloud();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Firebase Cloud Sync: ${storage.syncStatus}')),
                    );
                  }
                },
              ),
            ],
          ),
          body: RefreshIndicator(
            onRefresh: () async {
              await storage.pullFromCloud();
            },
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Quick Action Buttons (Exact web app blue styling)
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.brand,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          elevation: 2,
                          shadowColor: AppTheme.brand.withOpacity(0.4),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: Text(
                          'New Invoice',
                          style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 14),
                        ),
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const InvoiceFormScreen()),
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          backgroundColor: AppTheme.surface,
                          foregroundColor: AppTheme.ink,
                          side: const BorderSide(color: AppTheme.line),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        icon: const Icon(Icons.payments_outlined, size: 18, color: AppTheme.brand),
                        label: Text(
                          'Add Expense',
                          style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 14),
                        ),
                        onPressed: onNavigateToExpenses,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // ── Overdue Unpaid Invoices Alert (1+ Week) ──
                if (overdueInvoices.isNotEmpty) ...[
                  Container(
                    margin: const EdgeInsets.only(bottom: 20),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppTheme.redSoft,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppTheme.red.withOpacity(0.35)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: AppTheme.red.withOpacity(0.12),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.warning_amber_rounded, color: AppTheme.red, size: 22),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Invoices outstanding (${overdueInvoices.length})',
                                    style: GoogleFonts.sora(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.red),
                                  ),
                                  Text(
                                    'Not fully paid even after 7 days — follow up on every one of these',
                                    style: GoogleFonts.inter(fontSize: 11, color: AppTheme.ink2),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        ...overdueInvoices.map((inv) => Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppTheme.line),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${inv.number} · ${inv.clientName.isEmpty ? 'Walk-in Client' : inv.clientName}',
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                    ),
                                    Text(
                                      'Due: $currency ${inv.remainingAmount.toStringAsFixed(0)} · Created: ${DateFormat('dd MMM yyyy').format(DateTime.fromMillisecondsSinceEpoch(inv.createdAt))}',
                                      style: const TextStyle(fontSize: 11, color: AppTheme.ink3),
                                    ),
                                  ],
                                ),
                              ),
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppTheme.brand,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  minimumSize: Size.zero,
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                ),
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(builder: (_) => InvoiceDetailScreen(invoice: inv)),
                                  );
                                },
                                child: const Text('View / Pay', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                              ),
                            ],
                          ),
                        )),
                      ],
                    ),
                  ),
                ],

                // Stat Cards Grid (Exact web app tone circles & Sora numbers)
                Row(
                  children: [
                    Expanded(
                      child: _statCard(
                        "Today's Revenue",
                        '$currency ${todayRevenue.toStringAsFixed(0)}',
                        Icons.payments_rounded,
                        AppTheme.brand,
                        AppTheme.brandSoft,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _statCard(
                        'Collected Revenue',
                        '$currency ${collectedRevenue.toStringAsFixed(0)}',
                        Icons.check_circle_rounded,
                        AppTheme.green,
                        AppTheme.greenSoft,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _statCard(
                        'Pending (Unpaid)',
                        '$currency ${pendingBalance.toStringAsFixed(0)}',
                        Icons.timelapse_rounded,
                        AppTheme.red,
                        AppTheme.redSoft,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _statCard(
                        'Month Expenses',
                        '$currency ${monthExpenses.toStringAsFixed(0)}',
                        Icons.account_balance_wallet_rounded,
                        AppTheme.amber,
                        AppTheme.amberSoft,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 26),

                // Recent Invoices Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Recent Invoices',
                      style: GoogleFonts.sora(fontSize: 16, fontWeight: FontWeight.w700, color: AppTheme.ink),
                    ),
                    TextButton(
                      onPressed: onNavigateToInvoices,
                      child: Text(
                        'View All →',
                        style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.brand),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                if (recentInvoices.isEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
                    decoration: BoxDecoration(
                      color: AppTheme.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppTheme.line),
                    ),
                    alignment: Alignment.center,
                    child: Column(
                      children: [
                        Container(
                          width: 54,
                          height: 54,
                          decoration: const BoxDecoration(
                            color: AppTheme.brandSoft,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.receipt_long_outlined, size: 28, color: AppTheme.brand),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'No invoices yet',
                          style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600, color: AppTheme.ink),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Invoices synced from web or created here will appear here.',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(fontSize: 12, color: AppTheme.ink3),
                        ),
                        const SizedBox(height: 14),
                        ElevatedButton.icon(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => const InvoiceFormScreen()),
                            );
                          },
                          icon: const Icon(Icons.add, size: 16),
                          label: const Text('Create First Invoice'),
                        ),
                      ],
                    ),
                  )
                else
                  ...recentInvoices.map((inv) {
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
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => InvoiceDetailScreen(invoice: inv)),
                            );
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            child: Row(
                              children: [
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: AppTheme.brandSoft,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Icon(Icons.description_outlined, color: AppTheme.brand, size: 20),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Text(
                                            inv.number,
                                            style: GoogleFonts.sora(fontWeight: FontWeight.w700, fontSize: 14, color: AppTheme.ink),
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              inv.clientName.isEmpty ? 'Walk-in Client' : inv.clientName,
                                              style: GoogleFonts.inter(fontSize: 13, color: AppTheme.ink2),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        dateStr,
                                        style: GoogleFonts.inter(fontSize: 12, color: AppTheme.ink3),
                                      ),
                                    ],
                                  ),
                                ),
                                Text(
                                  '$currency ${inv.grandTotal.toStringAsFixed(0)}',
                                  style: GoogleFonts.sora(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 15,
                                    color: AppTheme.ink,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _statCard(String label, String value, IconData icon, Color iconColor, Color bgColor) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.line),
        boxShadow: [
          BoxShadow(
            color: AppTheme.ink.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.ink3),
              ),
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 18, color: iconColor),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: GoogleFonts.sora(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: AppTheme.ink,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
