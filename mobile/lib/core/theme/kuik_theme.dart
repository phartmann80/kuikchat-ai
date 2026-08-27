import 'package:flutter/material.dart';

/// KuikChat brand palette, matching the existing web app tokens in
/// `src/index.css` (blue hsl(217 91% 60%), green hsl(142 71% 45%)).
class KuikColors {
  const KuikColors._();

  static const Color brandBlue = Color(0xFF3B82F6);
  static const Color brandGreen = Color(0xFF22C55E);

  static const Color background = Color(0xFF000000);
  static const Color surface = Color(0xFF0B1220);
  static const Color surfaceHigh = Color(0xFF111A2E);
  static const Color border = Color(0xFF1E293B);
  static const Color mutedForeground = Color(0xFF94A3B8);
  static const Color foreground = Color(0xFFF1F5F9);
  static const Color destructive = Color(0xFFEF4444);
}

/// Material 3 dark theme for the whole app. There is intentionally no light
/// theme in this milestone: the product direction is full dark.
class KuikTheme {
  const KuikTheme._();

  static ThemeData dark() {
    const scheme = ColorScheme(
      brightness: Brightness.dark,
      primary: KuikColors.brandBlue,
      onPrimary: Colors.white,
      secondary: KuikColors.brandGreen,
      onSecondary: Colors.white,
      error: KuikColors.destructive,
      onError: Colors.white,
      surface: KuikColors.surface,
      onSurface: KuikColors.foreground,
      surfaceContainerHighest: KuikColors.surfaceHigh,
      onSurfaceVariant: KuikColors.mutedForeground,
      outline: KuikColors.border,
      outlineVariant: KuikColors.border,
    );

    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: KuikColors.background,
    );

    return base.copyWith(
      appBarTheme: const AppBarTheme(
        backgroundColor: KuikColors.background,
        foregroundColor: KuikColors.foreground,
        elevation: 0,
        centerTitle: false,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: KuikColors.surface,
        indicatorColor: KuikColors.brandBlue.withValues(alpha: 0.18),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: KuikColors.surface,
        indicatorColor: KuikColors.brandBlue.withValues(alpha: 0.18),
      ),
      cardTheme: CardThemeData(
        color: KuikColors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: KuikColors.border),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: KuikColors.surfaceHigh,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: KuikColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: KuikColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: KuikColors.brandBlue),
        ),
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: KuikColors.surfaceHigh,
        contentTextStyle: TextStyle(color: KuikColors.foreground),
        behavior: SnackBarBehavior.floating,
      ),
      dividerTheme: const DividerThemeData(color: KuikColors.border),
    );
  }
}
