import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';
import '../widgets/menu_button.dart';
import 'invoice_detail_screen.dart';

class RemindersScreen extends StatelessWidget {
  const RemindersScreen({super.key});

  void _showAddReminder(BuildContext context) {
    final titleCtrl = TextEditingController();
    final dateCtrl = TextEditingController();
    final timeCtrl = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Add Reminder', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              TextField(
                controller: titleCtrl,
                decoration: const InputDecoration(labelText: 'Title *', hintText: 'Call client about invoice...'),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: dateCtrl,
                      decoration: const InputDecoration(labelText: 'Date', hintText: 'YYYY-MM-DD'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: timeCtrl,
                      decoration: const InputDecoration(labelText: 'Time', hintText: '10:00 AM'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  minimumSize: const Size.fromHeight(48),
                ),
                onPressed: () async {
                  final title = titleCtrl.text.trim();
                  if (title.isEmpty) return;
                  final rem = Reminder(
                    id: DateTime.now().millisecondsSinceEpoch.toString(),
                    title: title,
                    date: dateCtrl.text.trim(),
                    time: timeCtrl.text.trim(),
                  );
                  await StorageService().addReminder(rem);
                  Navigator.pop(ctx);
                },
                child: const Text('Save Reminder', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: StorageService(),
      builder: (context, _) {
        final storage = StorageService();
        final currency = storage.settings.currency.isEmpty ? 'Rs' : storage.settings.currency;

        // Auto reminder: invoices still not fully paid a week after being raised.
        final outstanding = storage.invoices.where((i) => i.isOverdueOneWeek).toList()
          ..sort((a, b) => b.remainingAmount.compareTo(a.remainingAmount));
        final dueTotal = outstanding.fold<double>(0.0, (s, i) => s + i.remainingAmount);

        return Scaffold(
          appBar: AppBar(
            leading: const MenuButton(),
            title: const Text('Reminders'),
            actions: [
              IconButton(
                icon: const Icon(Icons.add),
                tooltip: 'Add',
                onPressed: () => _showAddReminder(context),
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            backgroundColor: AppTheme.primary,
            icon: const Icon(Icons.add, color: Colors.white),
            label: const Text('New Reminder', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            onPressed: () => _showAddReminder(context),
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: outstanding.isEmpty ? AppTheme.greenSoft : AppTheme.redSoft,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: (outstanding.isEmpty ? AppTheme.green : AppTheme.red).withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      outstanding.isEmpty ? Icons.verified_outlined : Icons.warning_amber_rounded,
                      color: outstanding.isEmpty ? AppTheme.green : AppTheme.red,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            outstanding.isEmpty
                                ? 'Invoices outstanding'
                                : 'Invoices outstanding (${outstanding.length})',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              color: outstanding.isEmpty ? AppTheme.green : AppTheme.red,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            outstanding.isEmpty
                                ? 'No invoice is unpaid or partially paid for more than 7 days.'
                                : 'Not fully paid even after 7 days · $currency ${dueTotal.toStringAsFixed(0)} still due',
                            style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),

              ...outstanding.map((inv) {
                final days = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(inv.createdAt)).inDays;
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: Icon(
                      inv.isPartiallyPaid ? Icons.timelapse_rounded : Icons.error_outline_rounded,
                      color: inv.isPartiallyPaid ? AppTheme.amber : AppTheme.red,
                    ),
                    title: Text(
                      '${inv.number} · ${inv.clientName.isEmpty ? 'Walk-in Client' : inv.clientName}',
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                    ),
                    subtitle: Text(
                      '$days days · invoice $currency ${inv.grandTotal.toStringAsFixed(0)}'
                      '${inv.paidAmount > 0 ? ' · paid $currency ${inv.paidAmount.toStringAsFixed(0)}' : ''}'
                      ' · due $currency ${inv.remainingAmount.toStringAsFixed(0)}',
                      style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
                    ),
                    trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: AppTheme.textMuted),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => InvoiceDetailScreen(invoice: inv)),
                    ),
                  ),
                );
              }),

              const SizedBox(height: 18),
              const Padding(
                padding: EdgeInsets.only(left: 4, bottom: 8),
                child: Text('Your reminders', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
              ),

              if (storage.reminders.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Column(
                    children: [
                      Icon(Icons.alarm, size: 48, color: AppTheme.textMuted.withValues(alpha: 0.4)),
                      const SizedBox(height: 10),
                      const Text('No reminders set', style: TextStyle(color: AppTheme.textMuted)),
                    ],
                  ),
                )
              else
                ...storage.reminders.map((rem) => Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: CheckboxListTile(
                    value: rem.done,
                    activeColor: AppTheme.emerald,
                    title: Text(
                      rem.title,
                      style: TextStyle(
                        decoration: rem.done ? TextDecoration.lineThrough : null,
                        color: rem.done ? AppTheme.textMuted : AppTheme.textMain,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: (rem.date.isNotEmpty || rem.time.isNotEmpty)
                        ? Text('${rem.date} ${rem.time}', style: const TextStyle(fontSize: 12, color: AppTheme.textMuted))
                        : null,
                    secondary: IconButton(
                      icon: const Icon(Icons.delete_outline, size: 18, color: AppTheme.textMuted),
                      onPressed: () => storage.deleteReminder(rem.id),
                    ),
                    onChanged: (_) => storage.toggleReminder(rem.id),
                  ),
                )),
            ],
          ),
        );
      },
    );
  }
}
