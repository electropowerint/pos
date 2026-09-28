import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';
import '../widgets/menu_button.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _nameCtrl;
  late TextEditingController _phoneCtrl;
  late TextEditingController _emailCtrl;
  late TextEditingController _addressCtrl;
  late TextEditingController _currencyCtrl;
  late TextEditingController _prefixCtrl;
  late TextEditingController _rowsCtrl;
  late TextEditingController _signCtrl;

  @override
  void initState() {
    super.initState();
    final s = StorageService().settings;
    _nameCtrl = TextEditingController(text: s.businessName);
    _phoneCtrl = TextEditingController(text: s.phone);
    _emailCtrl = TextEditingController(text: s.email);
    _addressCtrl = TextEditingController(text: s.address);
    _currencyCtrl = TextEditingController(text: s.currency);
    _prefixCtrl = TextEditingController(text: s.prefix);
    _rowsCtrl = TextEditingController(text: s.invoiceRows.toString());
    _signCtrl = TextEditingController(text: s.signName);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _addressCtrl.dispose();
    _currencyCtrl.dispose();
    _prefixCtrl.dispose();
    _rowsCtrl.dispose();
    _signCtrl.dispose();
    super.dispose();
  }

  void _saveSettings() async {
    if (!_formKey.currentState!.validate()) return;
    final rows = int.tryParse(_rowsCtrl.text.trim()) ?? 7;
    final newSettings = AppSettings(
      businessName: _nameCtrl.text.trim(),
      phone: _phoneCtrl.text.trim(),
      email: _emailCtrl.text.trim(),
      address: _addressCtrl.text.trim(),
      currency: _currencyCtrl.text.trim().isEmpty ? 'Rs' : _currencyCtrl.text.trim(),
      prefix: _prefixCtrl.text.trim().isEmpty ? 'INV' : _prefixCtrl.text.trim(),
      invoiceRows: rows < 7 ? 7 : rows,
      signName: _signCtrl.text.trim(),
    );

    await StorageService().saveSettings(newSettings);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Settings saved successfully')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: StorageService(),
      builder: (context, _) {
        final storage = StorageService();

        return Scaffold(
          appBar: AppBar(
            leading: const MenuButton(),
            title: const Text('Settings'),
            actions: [
              IconButton(
                icon: const Icon(Icons.check, color: AppTheme.emerald),
                tooltip: 'Save Settings',
                onPressed: _saveSettings,
              ),
            ],
          ),
          body: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Cloud Sync Status Card
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.bgCard,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: storage.syncStatus.contains('Synced')
                              ? AppTheme.emerald.withOpacity(0.15)
                              : AppTheme.amber.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          storage.syncStatus.contains('Synced') ? Icons.cloud_done : Icons.cloud_queue,
                          color: storage.syncStatus.contains('Synced') ? AppTheme.emerald : AppTheme.amber,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Database & Cloud Sync', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                            const SizedBox(height: 2),
                            Text(
                              'Status: ${storage.syncStatus}  (Firebase: ${storage.firestoreProjectId})',
                              style: const TextStyle(color: AppTheme.textMuted, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primary,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        ),
                        onPressed: () async {
                          await storage.pullFromCloud();
                          await storage.pushToCloud();
                        },
                        child: storage.isSyncing
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Text('Sync', style: TextStyle(fontSize: 12)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Business Profile Section
                const Text('Business Profile', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 12),

                TextFormField(
                  controller: _nameCtrl,
                  decoration: const InputDecoration(labelText: 'Business Name *', hintText: 'My Business'),
                  validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
                ),
                const SizedBox(height: 12),

                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _phoneCtrl,
                        decoration: const InputDecoration(labelText: 'Phone', hintText: '+92 300 1234567'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _emailCtrl,
                        decoration: const InputDecoration(labelText: 'Email', hintText: 'info@biz.com'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                TextFormField(
                  controller: _addressCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Business Address', hintText: 'Shop / Office address'),
                ),
                const SizedBox(height: 24),

                // Invoice Config Section
                const Text('Invoice Configuration', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 12),

                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _currencyCtrl,
                        decoration: const InputDecoration(labelText: 'Currency Symbol', hintText: 'Rs'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _prefixCtrl,
                        decoration: const InputDecoration(labelText: 'Invoice Prefix', hintText: 'INV'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _rowsCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Printed Rows Count (min 7)',
                          hintText: '7',
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _signCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Authorized Signature Title',
                          hintText: 'e.g. Manager',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 28),

                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  onPressed: _saveSettings,
                  child: const Text('Save All Settings', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        );
      },
    );
  }
}
