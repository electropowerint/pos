import 'package:flutter/material.dart';

/// Opens the shell's sidebar drawer from a nested screen Scaffold.
/// The shell Scaffold registers [shellKey] so nested AppBars can reach its drawer.
class MenuButton extends StatelessWidget {
  const MenuButton({super.key});

  static final GlobalKey<ScaffoldState> shellKey = GlobalKey<ScaffoldState>();

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Menu',
      icon: const Icon(Icons.menu_rounded, size: 26),
      onPressed: () => shellKey.currentState?.openDrawer(),
    );
  }
}
