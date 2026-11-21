import 'package:material_ui/material_ui.dart';

class AppTheme {
  static bool isDark = true;

  // Dynamic surfaces & backgrounds
  static Color get scaffoldBg =>
      isDark ? const Color(0xFF141414) : const Color(0xFFF3F4F6);
  static Color get windowBg => scaffoldBg;
  static Color get surface =>
      isDark ? const Color(0xFF1E1E1E) : const Color(0xFFFFFFFF);
  static Color get surfaceHigh =>
      isDark ? const Color(0xFF252526) : const Color(0xFFF9FAFB);
  static Color get inputFill => surfaceHigh;
  static Color get surfaceElevated =>
      isDark ? const Color(0xFF2D2D2D) : const Color(0xFFFFFFFF);
  static Color get surfaceContainerLowest => scaffoldBg;
  static Color get surfaceContainerLow =>
      isDark ? const Color(0xFF1A1A1A) : const Color(0xFFF9FAFB);
  static Color get surfaceContainer =>
      isDark ? const Color(0xFF222222) : const Color(0xFFFFFFFF);
  static Color get surfaceContainerHigh =>
      isDark ? const Color(0xFF282828) : const Color(0xFFF3F4F6);
  static Color get surfaceContainerHighest =>
      isDark ? const Color(0xFF323232) : const Color(0xFFE5E7EB);
  static Color get border =>
      isDark ? const Color(0xFF2C2C2C) : const Color(0xFFE5E7EB);
  static Color get borderSubtle =>
      isDark ? const Color(0xFF3E3E42) : const Color(0xFFD1D5DB);

  // Dynamic text hierarchy
  static Color get textPrimary =>
      isDark ? const Color(0xFFE0E0E0) : const Color(0xFF111827);
  static Color get textSecondary =>
      isDark ? const Color(0xFF9E9E9E) : const Color(0xFF4B5563);
  static Color get textMuted =>
      isDark ? const Color(0xFF6E6E6E) : const Color(0xFF6B7280);

  // Dynamic accents & semantic status colors
  static Color get accent =>
      isDark ? const Color(0xFF007ACC) : const Color(0xFF0284C7);
  static Color get primaryAccent => accent;
  static Color get success =>
      isDark ? const Color(0xFF10B981) : const Color(0xFF059669);
  static Color get error =>
      isDark ? const Color(0xFFEF4444) : const Color(0xFFDC2626);
  static Color get warning =>
      isDark ? const Color(0xFFF59E0B) : const Color(0xFFD97706);
  static Color get info =>
      isDark ? const Color(0xFF3B82F6) : const Color(0xFF2563EB);
  static Color get cyan =>
      isDark ? const Color(0xFF06B6D4) : const Color(0xFF0891B2);

  // Semantic node colors
  static Color get hostLocal =>
      isDark ? const Color(0xFF6366F1) : const Color(0xFF4F46E5);
  static Color get router =>
      isDark ? const Color(0xFF38BDF8) : const Color(0xFF0284C7);
  static Color get target => success;
  static Color get unresponsive =>
      isDark ? const Color(0xFF64748B) : const Color(0xFF6B7280);
  static Color get activeHighlight =>
      isDark ? const Color(0xFFEC4899) : const Color(0xFFDB2777);

  // Canvas & card utility colors
  static Color get canvasGridDot =>
      isDark ? const Color(0xFF2C2C2C) : const Color(0xFFD1D5DB);
  static Color get cardShadow => isDark
      ? Colors.black.withValues(alpha: 0.35)
      : Colors.black.withValues(alpha: 0.08);
  static Color get switchCardBg =>
      isDark ? const Color(0xFF161A22) : const Color(0xFFF0F9FF);

  static ThemeData get currentTheme => isDark ? darkTheme() : lightTheme();

  static ThemeData darkTheme() => _buildTheme(dark: true);

  static ThemeData lightTheme() => _buildTheme(dark: false);

  static ThemeData _buildTheme({required bool dark}) {
    final bg = dark ? const Color(0xFF141414) : const Color(0xFFF3F4F6);
    final surf = dark ? const Color(0xFF1E1E1E) : const Color(0xFFFFFFFF);
    final surfLow = dark ? const Color(0xFF1A1A1A) : const Color(0xFFF9FAFB);
    final surfCont = dark ? const Color(0xFF222222) : const Color(0xFFFFFFFF);
    final surfHigh = dark ? const Color(0xFF282828) : const Color(0xFFF3F4F6);
    final surfHighest =
        dark ? const Color(0xFF323232) : const Color(0xFFE5E7EB);
    final fill = dark ? const Color(0xFF252526) : const Color(0xFFF9FAFB);
    final divBorder = dark ? const Color(0xFF2C2C2C) : const Color(0xFFE5E7EB);
    final inputBorder =
        dark ? const Color(0xFF3E3E42) : const Color(0xFFD1D5DB);
    final primary = dark ? const Color(0xFF007ACC) : const Color(0xFF0284C7);
    final textPrim = dark ? const Color(0xFFE0E0E0) : const Color(0xFF111827);
    final textSec = dark ? const Color(0xFF9E9E9E) : const Color(0xFF4B5563);

    return ThemeData(
      useMaterial3: true,
      brightness: dark ? Brightness.dark : Brightness.light,
      scaffoldBackgroundColor: bg,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primary,
        brightness: dark ? Brightness.dark : Brightness.light,
        surface: surf,
        surfaceContainerLowest: bg,
        surfaceContainerLow: surfLow,
        surfaceContainer: surfCont,
        surfaceContainerHigh: surfHigh,
        surfaceContainerHighest: surfHighest,
      ),
      textTheme: (dark ? ThemeData.dark() : ThemeData.light()).textTheme.apply(
            bodyColor: textPrim,
            displayColor: textPrim,
          ),
      iconTheme: IconThemeData(color: textSec),
      cardTheme: CardThemeData(
        color: surf,
        elevation: 0,
        margin: EdgeInsets.zero,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surf,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: divBorder),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: divBorder,
        thickness: 1,
        space: 1,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: surf,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: divBorder),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        isDense: true,
        filled: true,
        fillColor: fill,
        hintStyle: TextStyle(color: textSec),
        labelStyle: TextStyle(color: textSec),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(color: inputBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(color: inputBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(color: primary, width: 1.5),
        ),
      ),
      visualDensity: VisualDensity.compact,
    );
  }
}
