import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/pdf_service.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';
import '../widgets/menu_button.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

enum ReportPeriod { day, weekly, monthly, yearly, custom }

class _ReportsScreenState extends State<ReportsScreen> {
  ReportPeriod _period = ReportPeriod.monthly;
  DateTime _dayDate = DateTime.now();
  DateTime _customStartDate = DateTime.now().subtract(const Duration(days: 30));
  DateTime _customEndDate = DateTime.now();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: StorageService(),
      builder: (context, _) {
        final storage = StorageService();
        final currency = storage.settings.currency.isEmpty ? 'Rs' : storage.settings.currency;

        final now = DateTime.now();
        DateTime rangeStart;
        DateTime rangeEnd;

        switch (_period) {
          case ReportPeriod.day:
            rangeStart = DateTime(_dayDate.year, _dayDate.month, _dayDate.day);
            rangeEnd = DateTime(_dayDate.year, _dayDate.month, _dayDate.day, 23, 59, 59);
            break;
          case ReportPeriod.weekly:
            rangeStart = DateTime(now.year, now.month, now.day).subtract(const Duration(days: 7));
            rangeEnd = DateTime(now.year, now.month, now.day, 23, 59, 59);
            break;
          case ReportPeriod.monthly:
            rangeStart = DateTime(now.year, now.month, 1);
            rangeEnd = DateTime(now.year, now.month + 1, 0, 23, 59, 59);
            break;
          case ReportPeriod.yearly:
            rangeStart = DateTime(now.year, 1, 1);
            rangeEnd = DateTime(now.year, 12, 31, 23, 59, 59);
            break;
          case ReportPeriod.custom:
            rangeStart = DateTime(_customStartDate.year, _customStartDate.month, _customStartDate.day);
            rangeEnd = DateTime(_customEndDate.year, _customEndDate.month, _customEndDate.day, 23, 59, 59);
            break;
        }

        final startMs = rangeStart.millisecondsSinceEpoch;
        final endMs = rangeEnd.millisecondsSinceEpoch;

        // Invoices in period are bucketed by the date they were raised.
        final periodInvoices = storage.invoices.where((i) {
          final t = i.createdAt;
          return t >= startMs && t <= endMs;
        }).toList();

        // Revenue = money actually received against this period's invoices, full or partial.
        final paidInvoices = periodInvoices.where((i) => i.isFullyPaid).toList();
        final openInvoices = periodInvoices.where((i) => !i.isFullyPaid).toList();
        final recognizedRevenue = periodInvoices.fold<double>(0.0, (sum, i) => sum + i.paidAmount);
        final pendingBalance = periodInvoices.fold<double>(0.0, (sum, i) => sum + i.remainingAmount);
        final totalInvoiced = periodInvoices.fold<double>(0.0, (sum, i) => sum + i.grandTotal);

        // Expenses in period
        final periodExpenses = storage.expenses.where((e) {
          return e.date >= startMs && e.date <= endMs;
        }).toList();

        final totalExpenses = periodExpenses.fold(0.0, (sum, e) => sum + e.amount);

        // Net Profit / Loss calculation
        final netProfitLoss = recognizedRevenue - totalExpenses;
        final isProfit = netProfitLoss >= 0;
        final profitMargin = recognizedRevenue > 0
            ? ((netProfitLoss / recognizedRevenue) * 100).clamp(-999.0, 100.0)
            : 0.0;

        // Group expenses by category
        final Map<String, double> categoryMap = {};
        for (final exp in periodExpenses) {
          categoryMap[exp.category] = (categoryMap[exp.category] ?? 0.0) + exp.amount;
        }
        final sortedCats = categoryMap.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

        final dateFmt = DateFormat('dd MMM yyyy');
        final periodLabel = _period == ReportPeriod.day
            ? '${dateFmt.format(rangeStart)} (single day)'
            : '${dateFmt.format(rangeStart)} – ${dateFmt.format(rangeEnd)}';

        // Top clients by cash actually received (period invoices, any payment)
        final Map<String, List<double>> clientMap = {};
        for (final inv in periodInvoices) {
          final name = inv.clientName.trim().isEmpty ? 'Walk-in Client' : inv.clientName.trim();
          final e = clientMap.putIfAbsent(name, () => [0, 0]);
          e[0] = e[0] + inv.paidAmount;
          e[1] = e[1] + 1;
        }
        final topClients = (clientMap.entries.where((e) => e.value[0] > 0).toList()
          ..sort((a, b) => b.value[0].compareTo(a.value[0])))
            .take(5)
            .map((e) => NamedValue(e.key, e.value[0], e.value[1].toInt()))
            .toList();

        final summary = ReportSummary(
          periodLabel: periodLabel,
          revenue: recognizedRevenue,
          invoiced: totalInvoiced,
          invCount: periodInvoices.length,
          outstanding: pendingBalance,
          expenses: totalExpenses,
          profit: netProfitLoss,
          paidCount: paidInvoices.length,
          openCount: openInvoices.length,
          expCount: periodExpenses.length,
          topClients: topClients,
          expenseCats: sortedCats.map((e) => NamedValue(e.key, e.value)).toList(),
        );

        return Scaffold(
          backgroundColor: AppTheme.bg,
          appBar: AppBar(
            leading: const MenuButton(),
            backgroundColor: AppTheme.surface,
            elevation: 0,
            title: Text(
              'Profit & Loss Statement',
              style: GoogleFonts.sora(fontSize: 18, fontWeight: FontWeight.w800, color: AppTheme.ink),
            ),
            actions: [
              IconButton(
                tooltip: 'Export PDF',
                icon: const Icon(Icons.picture_as_pdf_rounded, color: AppTheme.brand),
                onPressed: () => _export(summary),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // ── Period Selector Buttons ──
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.line),
                ),
                child: Row(
                  children: [
                    _periodTab('Day', ReportPeriod.day),
                    _periodTab('Weekly', ReportPeriod.weekly),
                    _periodTab('Monthly', ReportPeriod.monthly),
                    _periodTab('Yearly', ReportPeriod.yearly),
                    _periodTab('Custom', ReportPeriod.custom),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // Date Range Indicator / Custom Picker
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.date_range_rounded, size: 16, color: AppTheme.ink3),
                      const SizedBox(width: 6),
                      Text(
                        periodLabel,
                        style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.ink2),
                      ),
                    ],
                  ),
                  if (_period == ReportPeriod.custom)
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        visualDensity: VisualDensity.compact,
                      ),
                      icon: const Icon(Icons.edit_calendar_rounded, size: 14, color: AppTheme.brand),
                      label: const Text('Change Dates', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.brand)),
                      onPressed: () => _pickCustomRange(context),
                    ),
                  if (_period == ReportPeriod.day)
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        visualDensity: VisualDensity.compact,
                      ),
                      icon: const Icon(Icons.edit_calendar_rounded, size: 14, color: AppTheme.brand),
                      label: const Text('Change Day', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.brand)),
                      onPressed: () => _pickDay(context),
                    ),
                ],
              ),
              const SizedBox(height: 16),

              // ── Profit / Loss Hero Statement Card ──
              Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: isProfit
                        ? [const Color(0xFF064E3B), const Color(0xFF047857)]
                        : [const Color(0xFF881337), const Color(0xFFBE123C)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: (isProfit ? AppTheme.green : AppTheme.red).withOpacity(0.35),
                      blurRadius: 14,
                      offset: const Offset(0, 6),
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
                          isProfit ? 'NET PROFIT' : 'NET LOSS',
                          style: GoogleFonts.sora(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.2,
                            color: Colors.white.withOpacity(0.85),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            isProfit ? '+${profitMargin.toStringAsFixed(1)}% Margin' : '${profitMargin.toStringAsFixed(1)}% Margin',
                            style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '$currency ${netProfitLoss.abs().toStringAsFixed(0)}',
                      style: GoogleFonts.sora(
                        fontSize: 32,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isProfit
                        ? 'Business generated net surplus after all expenses.'
                        : 'Expenses exceeded the revenue of this period.',
                      style: TextStyle(color: Colors.white.withOpacity(0.85), fontSize: 12),
                    ),
                    const SizedBox(height: 18),
                    Container(height: 1, color: Colors.white.withOpacity(0.2)),
                    const SizedBox(height: 14),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Revenue',
                              style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.75)),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '$currency ${recognizedRevenue.toStringAsFixed(0)}',
                              style: GoogleFonts.sora(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
                            ),
                          ],
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              'Total Expenses',
                              style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.75)),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '- $currency ${totalExpenses.toStringAsFixed(0)}',
                              style: GoogleFonts.sora(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // ── Summary Cards Grid ──
              Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppTheme.surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppTheme.line),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Total Invoiced', style: TextStyle(fontSize: 11, color: AppTheme.ink3)),
                          const SizedBox(height: 4),
                          Text(
                            '$currency ${totalInvoiced.toStringAsFixed(0)}',
                            style: GoogleFonts.sora(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.ink),
                          ),
                          Text('${periodInvoices.length} invoice(s)', style: const TextStyle(fontSize: 10, color: AppTheme.ink4)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppTheme.surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppTheme.line),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Outstanding (unpaid / partial)', style: TextStyle(fontSize: 11, color: AppTheme.ink3)),
                          const SizedBox(height: 4),
                          Text(
                            '$currency ${pendingBalance.toStringAsFixed(0)}',
                            style: GoogleFonts.sora(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.red),
                          ),
                          const Text('Pending cash collection', style: TextStyle(fontSize: 10, color: AppTheme.ink4)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // ── 1. Revenue Sources (Paid Invoices) ──
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Invoices in period (${periodInvoices.length})',
                    style: GoogleFonts.sora(fontSize: 15, fontWeight: FontWeight.w700, color: AppTheme.ink),
                  ),
                  Text(
                    'Revenue = amounts received',
                    style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: AppTheme.green),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              if (periodInvoices.isEmpty)
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppTheme.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.line),
                  ),
                  child: Center(
                    child: Text('No invoices recorded in this period', style: TextStyle(color: AppTheme.ink3, fontSize: 13)),
                  ),
                )
              else
                ...periodInvoices.map((inv) => Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppTheme.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.line),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: inv.isFullyPaid ? AppTheme.greenSoft : AppTheme.amberSoft,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          inv.isFullyPaid ? Icons.check_circle_rounded : Icons.timelapse_rounded,
                          color: inv.isFullyPaid ? AppTheme.green : AppTheme.amber,
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${inv.number} · ${inv.clientName.isEmpty ? 'Walk-in Client' : inv.clientName}',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                            Text(
                              DateFormat('dd MMM yyyy').format(DateTime.fromMillisecondsSinceEpoch(inv.createdAt)),
                              style: const TextStyle(fontSize: 11, color: AppTheme.ink3),
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            inv.paidAmount > 0
                                ? '+ $currency ${inv.paidAmount.toStringAsFixed(0)}'
                                : '$currency ${inv.grandTotal.toStringAsFixed(0)}',
                            style: GoogleFonts.sora(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: inv.paidAmount > 0 ? AppTheme.green : AppTheme.ink2,
                            ),
                          ),
                          Text(
                            inv.remainingAmount > 0
                                ? 'Due: $currency ${inv.remainingAmount.toStringAsFixed(0)}'
                                : 'Invoiced: $currency ${inv.grandTotal.toStringAsFixed(0)}',
                            style: TextStyle(
                              fontSize: 10,
                              color: inv.remainingAmount > 0 ? AppTheme.red : AppTheme.ink3,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                )),

              const SizedBox(height: 24),

              // ── 2. Expense Statement & Breakdown ──
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Expense Breakdown (${periodExpenses.length})',
                    style: GoogleFonts.sora(fontSize: 15, fontWeight: FontWeight.w700, color: AppTheme.ink),
                  ),
                  Text(
                    '$currency ${totalExpenses.toStringAsFixed(0)}',
                    style: GoogleFonts.sora(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.rose),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              if (periodExpenses.isEmpty)
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppTheme.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.line),
                  ),
                  child: Center(
                    child: Text('No expenses recorded in this period', style: TextStyle(color: AppTheme.ink3, fontSize: 13)),
                  ),
                )
              else ...[
                // Category progress list
                ...sortedCats.map((e) {
                  final percent = totalExpenses > 0 ? (e.value / totalExpenses) : 0.0;
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.line),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(e.key, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                            Text(
                              '$currency ${e.value.toStringAsFixed(0)}  ·  ${(percent * 100).toStringAsFixed(1)}%',
                              style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.ink2, fontSize: 12),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        LinearProgressIndicator(
                          value: percent,
                          backgroundColor: AppTheme.line,
                          valueColor: const AlwaysStoppedAnimation(AppTheme.rose),
                          borderRadius: BorderRadius.circular(4),
                          minHeight: 6,
                        ),
                      ],
                    ),
                  );
                }),

                const SizedBox(height: 14),
                // Detailed Itemized Expenses
                Text(
                  'Itemized Expenses',
                  style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.ink2),
                ),
                const SizedBox(height: 8),
                ...periodExpenses.map((exp) => Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppTheme.surface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppTheme.line),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: const BoxDecoration(
                          color: AppTheme.amberSoft,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.account_balance_wallet_outlined, size: 14, color: AppTheme.amber),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(exp.title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                            Text(
                              '${exp.category} · ${DateFormat('dd MMM yyyy').format(DateTime.fromMillisecondsSinceEpoch(exp.date))}',
                              style: const TextStyle(fontSize: 11, color: AppTheme.ink3),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        '- $currency ${exp.amount.toStringAsFixed(0)}',
                        style: GoogleFonts.sora(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.rose),
                      ),
                    ],
                  ),
                )),
              ],
              const SizedBox(height: 40),
            ],
          ),
        );
      },
    );
  }

  Widget _periodTab(String label, ReportPeriod period) {
    final active = _period == period;
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => setState(() => _period = period),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? AppTheme.brand : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              maxLines: 1,
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: active ? FontWeight.bold : FontWeight.w600,
                color: active ? Colors.white : AppTheme.ink2,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _export(ReportSummary summary) async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(duration: Duration(seconds: 1), content: Text('Preparing report PDF…')),
    );
    try {
      await PdfService.openReportPdf(summary);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open the report PDF: $e')),
      );
    }
  }

  Future<void> _pickDay(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dayDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked != null) setState(() => _dayDate = picked);
  }

  Future<void> _pickCustomRange(BuildContext context) async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
      initialDateRange: DateTimeRange(start: _customStartDate, end: _customEndDate),
    );
    if (picked != null) {
      setState(() {
        _customStartDate = picked.start;
        _customEndDate = picked.end;
      });
    }
  }
}
