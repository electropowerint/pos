import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'services/storage_service.dart';
import 'theme/app_theme.dart';
import 'widgets/menu_button.dart';
import 'screens/dashboard_screen.dart';
import 'screens/invoices_screen.dart';
import 'screens/expenses_screen.dart';
import 'screens/reports_screen.dart';
import 'screens/reminders_screen.dart';
import 'screens/notes_screen.dart';
import 'screens/settings_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase (same project as web app — eppos-41139)
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    debugPrint('Firebase init notice: $e');
  }

  final storage = StorageService();
  await storage.init();

  runApp(const NovaPOSApp());
}

class NovaPOSApp extends StatelessWidget {
  const NovaPOSApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ElectroPowerInt Mobile',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: const MainNavigationShell(),
    );
  }
}

class MainNavigationShell extends StatefulWidget {
  const MainNavigationShell({super.key});

  @override
  State<MainNavigationShell> createState() => _MainNavigationShellState();
}

class _MainNavigationShellState extends State<MainNavigationShell> {
  // Screens: 0=Dashboard, 1=Invoices, 2=Expenses, 3=Reports, 4=Reminders, 5=Notes, 6=Settings
  int _currentIndex = 0;

  late final List<Widget> _screens;

  @override
  void initState() {
    super.initState();
    _screens = [
      DashboardScreen(
        onNavigateToInvoices: () => setState(() => _currentIndex = 1),
        onNavigateToExpenses: () => setState(() => _currentIndex = 2),
      ),
      const InvoicesScreen(),
      const ExpensesScreen(),
      const ReportsScreen(),
      const RemindersScreen(),
      const NotesScreen(),
      const SettingsScreen(),
    ];
  }

  void _go(int index) => setState(() => _currentIndex = index);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: StorageService(),
      builder: (context, _) {
        final outstanding = StorageService().invoices.where((i) => i.isOverdueOneWeek).length;
        return Scaffold(
      key: MenuButton.shellKey,
      // ── Drawer (sidebar) ──────────────────────────────────────────────
      drawer: Drawer(
        width: 270,
        backgroundColor: AppTheme.bgCard,
        child: Material(
          color: AppTheme.bgCard,
          child: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
              // Drawer header
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                color: AppTheme.primary,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.point_of_sale_rounded, color: Colors.white, size: 26),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'ElectroPowerInt',
                      style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    const Text(
                      'Business Manager',
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),

              // ── Drawer items (all 7 screens) ──────────────────────────
              _DrawerItem(
                icon: Icons.dashboard_outlined,
                selectedIcon: Icons.dashboard,
                label: 'Dashboard',
                selected: _currentIndex == 0,
                onTap: () { Navigator.pop(context); _go(0); },
              ),
              _DrawerItem(
                icon: Icons.receipt_long_outlined,
                selectedIcon: Icons.receipt_long,
                label: 'Invoices',
                selected: _currentIndex == 1,
                onTap: () { Navigator.pop(context); _go(1); },
              ),
              _DrawerItem(
                icon: Icons.payments_outlined,
                selectedIcon: Icons.payments,
                label: 'Expenses',
                selected: _currentIndex == 2,
                onTap: () { Navigator.pop(context); _go(2); },
              ),
              _DrawerItem(
                icon: Icons.bar_chart_outlined,
                selectedIcon: Icons.bar_chart,
                label: 'Reports',
                selected: _currentIndex == 3,
                onTap: () { Navigator.pop(context); _go(3); },
              ),
              _DrawerItem(
                icon: Icons.alarm_outlined,
                selectedIcon: Icons.alarm,
                label: 'Reminders',
                selected: _currentIndex == 4,
                badge: outstanding,
                onTap: () { Navigator.pop(context); _go(4); },
              ),
              _DrawerItem(
                icon: Icons.edit_note_outlined,
                selectedIcon: Icons.edit_note,
                label: 'Notes',
                selected: _currentIndex == 5,
                onTap: () { Navigator.pop(context); _go(5); },
              ),

              const Spacer(),
              const Divider(height: 1),
              _DrawerItem(
                icon: Icons.settings_outlined,
                selectedIcon: Icons.settings,
                label: 'Settings',
                selected: _currentIndex == 6,
                onTap: () { Navigator.pop(context); _go(6); },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
        ),
      ),

      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),

      // ── Bottom bar: Invoices | Expenses | Settings ────────────────────
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: AppTheme.bgCard,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 12,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: SafeArea(
          child: SizedBox(
            height: 62,
            child: Row(
              children: [
                // Invoices (left)
                _BottomBarItem(
                  icon: Icons.receipt_long_outlined,
                  selectedIcon: Icons.receipt_long,
                  label: 'Invoices',
                  selected: _currentIndex == 1,
                  onTap: () => _go(1),
                ),

                // Expenses (middle)
                _BottomBarItem(
                  icon: Icons.payments_outlined,
                  selectedIcon: Icons.payments,
                  label: 'Expenses',
                  selected: _currentIndex == 2,
                  onTap: () => _go(2),
                ),

                // Settings (right)
                _BottomBarItem(
                  icon: Icons.settings_outlined,
                  selectedIcon: Icons.settings,
                  label: 'Settings',
                  selected: _currentIndex == 6,
                  onTap: () => _go(6),
                ),
              ],
            ),
          ),
        ),
      ),
      );
      },
    );
  }
}

// ── Reusable bottom bar item ───────────────────────────────────────────────
class _BottomBarItem extends StatelessWidget {
  const _BottomBarItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppTheme.primary : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5);
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(selected ? selectedIcon : icon, size: 26, color: color),
            const SizedBox(height: 3),
            Text(label, style: TextStyle(fontSize: 10, color: color, fontWeight: selected ? FontWeight.w600 : FontWeight.normal)),
          ],
        ),
      ),
    );
  }
}

// ── Reusable drawer item ───────────────────────────────────────────────────
class _DrawerItem extends StatelessWidget {
  const _DrawerItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    this.badge = 0,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool selected;
  final int badge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bg = selected ? AppTheme.primary.withValues(alpha: 0.09) : Colors.transparent;
    final iconColor = selected ? AppTheme.primary : AppTheme.textMuted;
    final textColor = selected ? AppTheme.primary : AppTheme.textMain;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Ink(
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                badge > 0
                    ? Badge(
                        label: Text('$badge'),
                        backgroundColor: AppTheme.red,
                        textColor: Colors.white,
                        child: Icon(selected ? selectedIcon : icon, color: iconColor, size: 22),
                      )
                    : Icon(selected ? selectedIcon : icon, color: iconColor, size: 22),
                const SizedBox(width: 14),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                    color: textColor,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
