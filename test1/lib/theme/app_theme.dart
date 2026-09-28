import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Exact same color palette as the web app's style.css CSS variables.
class AppTheme {
  // ── Web app CSS variables ─────────────────────────────────────────
  static const Color bg          = Color(0xFFF5F7FB); // --bg: #f5f7fb
  static const Color surface     = Color(0xFFFFFFFF); // --surface: #ffffff
  static const Color surface2    = Color(0xFFF8FAFD); // --surface-2: #f8fafd
  static const Color ink         = Color(0xFF0F172A); // --ink: #0f172a
  static const Color ink2        = Color(0xFF334155); // --ink-2: #334155
  static const Color ink3        = Color(0xFF64748B); // --ink-3: #64748b
  static const Color ink4        = Color(0xFF94A3B8); // --ink-4: #94a3b8
  static const Color line        = Color(0xFFE6EAF3); // --line: #e6eaf3
  static const Color line2       = Color(0xFFEEF1F8); // --line-2: #eef1f8
  static const Color brand       = Color(0xFF2563EB); // --brand: #2563eb
  static const Color brandDark   = Color(0xFF1D4ED8); // --brand-ink: #1d4ed8
  static const Color brandSoft   = Color(0xFFEFF6FF); // --brand-soft: #eff6ff
  static const Color green       = Color(0xFF059669); // --green: #059669
  static const Color greenSoft   = Color(0xFFECFDF5); // --green-soft: #ecfdf5
  static const Color red         = Color(0xFFE11D48); // --red: #e11d48
  static const Color redSoft     = Color(0xFFFFF1F2); // --red-soft: #fff1f2
  static const Color amber       = Color(0xFFD97706); // --amber: #d97706
  static const Color amberSoft   = Color(0xFFFFFBEB); // --amber-soft: #fffbeb
  static const Color blue        = Color(0xFF0284C7); // --blue: #0284c7
  static const Color blueSoft    = Color(0xFFF0F9FF); // --blue-soft: #f0f9ff

  // ── Backward-compatible aliases ──────────────────────────────────
  static const Color primary     = brand;
  static const Color primaryDark = brandDark;
  static const Color textMain    = ink;
  static const Color textMuted   = ink3;
  static const Color bgDark      = bg;
  static const Color bgCard      = surface;
  static const Color bgCardHover = surface2;
  static const Color border      = line;
  static const Color emerald     = green;
  static const Color rose        = red;
  static const Color paperBg     = surface;
  static const Color paperText   = ink;

  // ── Theme ─────────────────────────────────────────────────────────
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: bg,
      primaryColor: brand,
      colorScheme: const ColorScheme.light(
        primary: brand,
        secondary: brandDark,
        surface: surface,
        error: red,
        onPrimary: Colors.white,
        onSurface: ink,
        secondaryContainer: brandSoft,
        onSecondaryContainer: brand,
      ),
      textTheme: GoogleFonts.interTextTheme(
        ThemeData.light().textTheme.apply(bodyColor: ink, displayColor: ink),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shadowColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: line, width: 1),
        ),
        margin: EdgeInsets.zero,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: GoogleFonts.sora(
          color: ink,
          fontSize: 18,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.3,
        ),
        iconTheme: const IconThemeData(color: ink2),
        actionsIconTheme: const IconThemeData(color: ink2),
        shape: const Border(bottom: BorderSide(color: line, width: 1)),
      ),
      dividerColor: line,
      dividerTheme: const DividerThemeData(color: line, thickness: 1, space: 1),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: brand, width: 1.5),
        ),
        hintStyle: const TextStyle(color: ink4, fontSize: 14),
        labelStyle: const TextStyle(color: ink3, fontSize: 14),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: brand,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: ink,
          side: const BorderSide(color: line),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        elevation: 0,
        indicatorColor: brandSoft,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: brand);
          }
          return const IconThemeData(color: ink3);
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: brand);
          }
          return GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w500, color: ink3);
        }),
      ),
    );
  }
}
