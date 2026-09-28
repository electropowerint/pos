import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';
import 'invoice_detail_screen.dart';

class InvoiceFormScreen extends StatefulWidget {
  final Invoice? invoice;
  const InvoiceFormScreen({super.key, this.invoice});

  @override
  State<InvoiceFormScreen> createState() => _InvoiceFormScreenState();
}

class _InvoiceFormScreenState extends State<InvoiceFormScreen> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _numberCtrl;
  late TextEditingController _nameCtrl;
  late TextEditingController _phoneCtrl;
  late TextEditingController _emailCtrl;
  late TextEditingController _addressCtrl;
  late TextEditingController _dueDateCtrl;
  late TextEditingController _discountCtrl;
  late TextEditingController _notesCtrl;

  String _discountType = 'amount';
  List<Map<String, dynamic>> _itemControllers = [];

  @override
  void initState() {
    super.initState();
    final inv = widget.invoice;
    final storage = StorageService();

    // User can edit invoice number directly!
    _numberCtrl = TextEditingController(text: inv?.number ?? storage.nextInvoiceNumber());
    _nameCtrl = TextEditingController(text: inv?.clientName ?? '');
    _phoneCtrl = TextEditingController(text: inv?.clientPhone ?? '');
    _emailCtrl = TextEditingController(text: inv?.clientEmail ?? '');
    _addressCtrl = TextEditingController(text: inv?.clientAddress ?? '');
    _dueDateCtrl = TextEditingController(text: inv?.dueDate ?? '');
    _discountCtrl = TextEditingController(text: inv?.discount != null && inv!.discount > 0 ? inv.discount.toString() : '0');
    _notesCtrl = TextEditingController(text: inv?.notes ?? '');
    _discountType = inv?.discountType ?? 'amount';

    if (inv != null && inv.items.isNotEmpty) {
      for (final item in inv.items) {
        _addItemRow(name: item.name, qty: item.qty.toString(), price: item.price.toString());
      }
    } else {
      _addItemRow();
      _addItemRow();
    }
  }

  void _addItemRow({String name = '', String qty = '1', String price = '0'}) {
    setState(() {
      _itemControllers.add({
        'name': TextEditingController(text: name),
        'qty': TextEditingController(text: qty),
        'price': TextEditingController(text: price),
      });
    });
  }

  void _removeItemRow(int index) {
    if (_itemControllers.length <= 1) return;
    setState(() {
      _itemControllers.removeAt(index);
    });
  }

  double _calculateSubtotal() {
    double sum = 0.0;
    for (final row in _itemControllers) {
      final q = double.tryParse((row['qty'] as TextEditingController).text) ?? 0.0;
      final p = double.tryParse((row['price'] as TextEditingController).text) ?? 0.0;
      sum += (q * p);
    }
    return sum;
  }

  double _calculateDiscount(double subtotal) {
    final dVal = double.tryParse(_discountCtrl.text) ?? 0.0;
    if (_discountType == 'percent') {
      return (subtotal * dVal) / 100.0;
    }
    return dVal;
  }

  Invoice _buildCurrentInvoice() {
    final items = _itemControllers.map((row) {
      final name = (row['name'] as TextEditingController).text.trim();
      final qty = double.tryParse((row['qty'] as TextEditingController).text) ?? 0.0;
      final price = double.tryParse((row['price'] as TextEditingController).text) ?? 0.0;
      return InvoiceItem(name: name, qty: qty, price: price);
    }).where((it) => it.name.isNotEmpty && it.qty > 0).toList();

    return Invoice(
      id: widget.invoice?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
      number: _numberCtrl.text.trim().isEmpty ? StorageService().nextInvoiceNumber() : _numberCtrl.text.trim(),
      clientName: _nameCtrl.text.trim(),
      clientPhone: _phoneCtrl.text.trim(),
      clientEmail: _emailCtrl.text.trim(),
      clientAddress: _addressCtrl.text.trim(),
      dueDate: _dueDateCtrl.text.trim(),
      discount: double.tryParse(_discountCtrl.text) ?? 0.0,
      discountType: _discountType,
      notes: _notesCtrl.text.trim(),
      items: items,
      createdAt: widget.invoice?.createdAt ?? DateTime.now().millisecondsSinceEpoch,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
      status: widget.invoice?.status ?? 'unpaid',
      paidAmount: widget.invoice?.paidAmount ?? 0.0,
      paidAt: widget.invoice?.paidAt,
    );
  }

  void _saveInvoice() async {
    if (widget.invoice?.isFullyPaid == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cannot edit: This invoice is fully paid and locked.'),
          backgroundColor: AppTheme.rose,
        ),
      );
      return;
    }
    if (!_formKey.currentState!.validate()) return;
    final inv = _buildCurrentInvoice();
    if (inv.items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please add at least one item')),
      );
      return;
    }

    final storage = StorageService();
    if (widget.invoice != null) {
      await storage.updateInvoice(inv);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Invoice ${inv.number} updated')),
      );
    } else {
      await storage.addInvoice(inv);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Invoice ${inv.number} saved')),
      );
    }

    Navigator.pop(context);
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => InvoiceDetailScreen(invoice: inv)),
    );
  }

  @override
  void dispose() {
    _numberCtrl.dispose();
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _addressCtrl.dispose();
    _dueDateCtrl.dispose();
    _discountCtrl.dispose();
    _notesCtrl.dispose();
    for (final row in _itemControllers) {
      (row['name'] as TextEditingController).dispose();
      (row['qty'] as TextEditingController).dispose();
      (row['price'] as TextEditingController).dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final storage = StorageService();
    final currency = storage.settings.currency.isEmpty ? 'Rs' : storage.settings.currency;
    final subtotal = _calculateSubtotal();
    final discount = _calculateDiscount(subtotal);
    final grandTotal = (subtotal - discount) > 0 ? (subtotal - discount) : 0.0;

    final isLocked = widget.invoice?.isFullyPaid == true;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.invoice == null
            ? 'New Invoice'
            : (isLocked ? 'Invoice Locked (${widget.invoice!.number})' : 'Edit Invoice')),
        actions: [
          if (!isLocked)
            IconButton(
              icon: const Icon(Icons.check, color: AppTheme.emerald),
              tooltip: 'Save',
              onPressed: _saveInvoice,
            )
          else
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: Icon(Icons.lock_rounded, color: AppTheme.green),
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (isLocked) ...[
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppTheme.greenSoft,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.green.withOpacity(0.3)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.lock_rounded, color: AppTheme.green, size: 22),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'This invoice is FULLY PAID and locked. Completed invoices cannot be edited.',
                        style: TextStyle(color: AppTheme.green, fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            // Section 1: Client & Invoice Info
            _sectionHeader('1', 'Client & Invoice Details'),
            const SizedBox(height: 12),

            // Invoice Number input (User-editable)
            TextFormField(
              controller: _numberCtrl,
              decoration: const InputDecoration(
                labelText: 'Invoice Number *',
                hintText: 'e.g. INV-0001',
                prefixIcon: Icon(Icons.tag, size: 20, color: AppTheme.primary),
              ),
              style: const TextStyle(fontWeight: FontWeight.bold),
              validator: (v) => v == null || v.trim().isEmpty ? 'Invoice number is required' : null,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),

            // Saved Client Autocomplete/Picker
            if (storage.clients.isNotEmpty) ...[
              DropdownButtonFormField<String>(
                decoration: const InputDecoration(
                  labelText: 'Pick Saved Client',
                  prefixIcon: Icon(Icons.person_search, size: 20, color: AppTheme.textMuted),
                ),
                items: [
                  const DropdownMenuItem(value: '', child: Text('— Select Saved Client —')),
                  ...storage.clients.map((c) => DropdownMenuItem(value: c.name, child: Text(c.name))),
                ],
                onChanged: (val) {
                  if (val != null && val.isNotEmpty) {
                    final c = storage.clients.firstWhere((x) => x.name == val);
                    setState(() {
                      _nameCtrl.text = c.name;
                      _phoneCtrl.text = c.phone;
                      _emailCtrl.text = c.email;
                      _addressCtrl.text = c.address;
                    });
                  }
                },
              ),
              const SizedBox(height: 12),
            ],

            TextFormField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Client Name *',
                hintText: 'e.g. Ahmed Traders',
                prefixIcon: Icon(Icons.person_outline, size: 20, color: AppTheme.textMuted),
              ),
              validator: (v) => v == null || v.trim().isEmpty ? 'Client name is required' : null,
            ),
            const SizedBox(height: 12),

            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _phoneCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Phone',
                      hintText: '+92 300 1234567',
                      prefixIcon: Icon(Icons.phone_outlined, size: 18, color: AppTheme.textMuted),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _dueDateCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Due Date',
                      hintText: 'YYYY-MM-DD',
                      prefixIcon: Icon(Icons.calendar_today_outlined, size: 18, color: AppTheme.textMuted),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            TextFormField(
              controller: _emailCtrl,
              decoration: const InputDecoration(
                labelText: 'Email',
                hintText: 'client@example.com',
                prefixIcon: Icon(Icons.email_outlined, size: 18, color: AppTheme.textMuted),
              ),
            ),
            const SizedBox(height: 12),

            TextFormField(
              controller: _addressCtrl,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Client Address',
                hintText: 'Area, Town, City',
                prefixIcon: Icon(Icons.location_on_outlined, size: 18, color: AppTheme.textMuted),
              ),
            ),
            const SizedBox(height: 28),

            // Section 2: Items
            _sectionHeader('2', 'Items & Products'),
            const SizedBox(height: 12),

            // Item rows
            ..._itemControllers.asMap().entries.map((entry) {
              final idx = entry.key;
              final row = entry.value;
              final nameC = row['name'] as TextEditingController;
              final qtyC = row['qty'] as TextEditingController;
              final priceC = row['price'] as TextEditingController;

              final q = double.tryParse(qtyC.text) ?? 0.0;
              final p = double.tryParse(priceC.text) ?? 0.0;
              final lineTotal = q * p;

              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: nameC,
                              decoration: InputDecoration(
                                hintText: 'Item / Product name #${idx + 1}',
                                isDense: true,
                              ),
                              onChanged: (_) => setState(() {}),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline, size: 20, color: AppTheme.rose),
                            onPressed: () => _removeItemRow(idx),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: qtyC,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'Qty',
                                isDense: true,
                              ),
                              onChanged: (_) => setState(() {}),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 2,
                            child: TextFormField(
                              controller: priceC,
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                labelText: 'Price ($currency)',
                                isDense: true,
                              ),
                              onChanged: (_) => setState(() {}),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              const Text('Line Total', style: TextStyle(fontSize: 10, color: AppTheme.textMuted)),
                              Text(
                                '$currency ${lineTotal.toStringAsFixed(0)}',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            }),

            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppTheme.primary),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              icon: const Icon(Icons.add, color: AppTheme.primary, size: 18),
              label: const Text('Add Row', style: TextStyle(color: AppTheme.primary)),
              onPressed: () => _addItemRow(),
            ),
            const SizedBox(height: 24),

            // Section 3: Discount & Totals
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _discountCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Discount',
                              isDense: true,
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                        const SizedBox(width: 12),
                        SizedBox(
                          width: 120,
                          child: DropdownButtonFormField<String>(
                            value: _discountType,
                            decoration: const InputDecoration(
                              labelText: 'Type',
                              isDense: true,
                            ),
                            items: const [
                              DropdownMenuItem(value: 'amount', child: Text('Amount')),
                              DropdownMenuItem(value: 'percent', child: Text('%')),
                            ],
                            onChanged: (val) {
                              if (val != null) setState(() => _discountType = val);
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Divider(color: AppTheme.border),
                    const SizedBox(height: 8),

                    // Totals Breakdown
                    _summaryRow('Subtotal', '$currency ${subtotal.toStringAsFixed(0)}'),
                    if (discount > 0)
                      _summaryRow('Discount', '- $currency ${discount.toStringAsFixed(0)}', color: AppTheme.rose),
                    const SizedBox(height: 6),
                    _summaryRow(
                      'Grand Total',
                      '$currency ${grandTotal.toStringAsFixed(0)}',
                      isBold: true,
                      fontSize: 18,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Save Button
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              onPressed: _saveInvoice,
              child: Text(
                widget.invoice == null ? 'Save Invoice' : 'Update Invoice',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(String step, String title) {
    return Row(
      children: [
        Container(
          width: 24,
          height: 24,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppTheme.primary,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            step,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.white),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
        ),
      ],
    );
  }

  Widget _summaryRow(String label, String value, {bool isBold = false, double fontSize = 14, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: AppTheme.textMuted, fontSize: fontSize)),
          Text(
            value,
            style: TextStyle(
              fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
              fontSize: fontSize,
              color: color ?? AppTheme.textMain,
            ),
          ),
        ],
      ),
    );
  }
}
