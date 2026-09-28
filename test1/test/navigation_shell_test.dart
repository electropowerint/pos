import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novapos_mobile/main.dart';

void main() {
  testWidgets('menu button sits top-left and expenses takes its bottom slot', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: MainNavigationShell()));
    await tester.pumpAndSettle();

    // The hamburger lives in the top-left (leading) of the app bar, not the bottom bar.
    expect(find.byIcon(Icons.menu_rounded), findsOneWidget);
    final menu = tester.getRect(find.byIcon(Icons.menu_rounded));
    final screen = tester.getRect(find.byType(MaterialApp).first);
    expect(menu.left, lessThan(60));
    expect(menu.top, lessThan(screen.top + 100));

    // Bottom bar: Invoices | Expenses | Settings
    expect(find.text('Invoices'), findsWidgets);
    expect(find.text('Expenses'), findsWidgets);
    expect(find.text('Settings'), findsWidgets);
    expect(find.text('Menu'), findsNothing);

    // Tapping it opens the sidebar drawer with all seven destinations.
    await tester.tap(find.byIcon(Icons.menu_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Dashboard'), findsOneWidget);
    expect(find.text('Reports'), findsOneWidget);
    expect(find.text('Reminders'), findsOneWidget);
    expect(find.text('Notes'), findsOneWidget);

    await tester.tap(find.text('Expenses').hitTestable().first);
    await tester.pumpAndSettle();
    expect(find.text('Add Expense'), findsWidgets);
  });
}
