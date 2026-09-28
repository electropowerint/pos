import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/models.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';
import '../widgets/menu_button.dart';

class ExpensesScreen extends StatefulWidget {
  const ExpensesScreen({super.key});

  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends State<ExpensesScreen> {
  final List<String> categories = ['Rent', 'Salaries', 'Utilities', 'Stock', 'Marketing', 'Transport', 'Other'];

  void _showAddExpenseDialog() {
    final titleCtrl = TextEditingController();
    final amountCtrl = TextEditingController();
    String selectedCategory = categories.first;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
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
                  const Text('Add Expense', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  TextField(
                    controller: titleCtrl,
                    decoration: const InputDecoration(labelText: 'Expense Title *', hintText: 'e.g. Shop rent'),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: selectedCategory,
                    decoration: const InputDecoration(labelText: 'Category'),
                    items: categories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                    onChanged: (val) {
                      if (val != null) setModalState(() => selectedCategory = val);
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: amountCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Amount *', hintText: '0'),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      minimumSize: const Size.fromHeight(48),
                    ),
                    onPressed: () async {
                      final title = titleCtrl.text.trim();
                      final amt = double.tryParse(amountCtrl.text) ?? 0.0;
                      if (title.isEmpty || amt <= 0) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Please enter valid title and amount')),
                        );
                        return;
                      }

                      final exp = Expense(
                        id: DateTime.now().millisecondsSinceEpoch.toString(),
                        title: title,
                        category: selectedCategory,
                        amount: amt,
                        date: DateTime.now().millisecondsSinceEpoch,
                      );

                      await StorageService().addExpense(exp);
                      Navigator.pop(ctx);
                    },
                    child: const Text('Save Expense', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            );
          },
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
        final total = storage.expenses.fold(0.0, (sum, e) => sum + e.amount);

        return Scaffold(
          appBar: AppBar(
            leading: const MenuButton(),
            title: const Text('Expenses'),
            actions: [
              IconButton(
                icon: const Icon(Icons.add),
                tooltip: 'Add Expense',
                onPressed: _showAddExpenseDialog,
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            backgroundColor: AppTheme.rose,
            icon: const Icon(Icons.add, color: Colors.white),
            label: const Text('Add Expense', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            onPressed: _showAddExpenseDialog,
          ),
          body: Column(
            children: [
              // Summary card
              Container(
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.bgCard,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppTheme.border),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Total Expenses', style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
                        const SizedBox(height: 4),
                        Text(
                          '$currency ${total.toStringAsFixed(0)}',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 22, color: AppTheme.rose),
                        ),
                      ],
                    ),
                    Text(
                      '${storage.expenses.length} records',
                      style: const TextStyle(color: AppTheme.textMuted, fontSize: 13),
                    ),
                  ],
                ),
              ),

              // Expense list
              Expanded(
                child: storage.expenses.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.payments_outlined, size: 56, color: AppTheme.textMuted.withOpacity(0.4)),
                            const SizedBox(height: 12),
                            const Text('No expenses recorded yet', style: TextStyle(color: AppTheme.textMuted)),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
                        itemCount: storage.expenses.length,
                        itemBuilder: (context, index) {
                          final exp = storage.expenses[index];
                          final dateStr = DateFormat('dd MMM yyyy').format(
                            DateTime.fromMillisecondsSinceEpoch(exp.date),
                          );

                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              title: Text(exp.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                              subtitle: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: AppTheme.primary.withOpacity(0.15),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      exp.category,
                                      style: const TextStyle(fontSize: 10, color: AppTheme.primary, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(dateStr, style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                                ],
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    '$currency ${exp.amount.toStringAsFixed(0)}',
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppTheme.rose),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline, size: 18, color: AppTheme.textMuted),
                                    onPressed: () => storage.deleteExpense(exp.id),
                                  ),
                                ],
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
