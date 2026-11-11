import 'package:material_ui/material_ui.dart';

class AppTheme {
  static const Color windowBg = Color(0xFF141414);
  static const Color surface = Color(0xFF1E1E1E);
  static const Color surfaceContainerLowest = Color(0xFF141414);
  static const Color surfaceContainerLow = Color(0xFF1A1A1A);
  static const Color surfaceContainer = Color(0xFF222222);
  static const Color surfaceContainerHigh = Color(0xFF282828);
  static const Color surfaceContainerHighest = Color(0xFF323232);
  static const Color inputFill = Color(0xFF252526);
  static const Color border = Color(0xFF2C2C2C);
  static const Color primaryAccent = Color(0xFF007ACC);

  // Spec-defined semantic node colors
  static const Color hostLocal = Color(0xFF6366F1); // Electric Indigo
  static const Color router = Color(0xFF38BDF8); // Cyan Wave
  static const Color target = Color(0xFF10B981); // Emerald Green
  static const Color unresponsive = Color(0xFF64748B); // Dim Slate Gray
  static const Color activeHighlight = Color(0xFFEC4899); // Glowing Magenta

  static ThemeData darkTheme() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: windowBg,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryAccent,
        brightness: Brightness.dark,
        surface: surface,
        surfaceContainerLowest: surfaceContainerLowest,
        surfaceContainerLow: surfaceContainerLow,
        surfaceContainer: surfaceContainer,
        surfaceContainerHigh: surfaceContainerHigh,
        surfaceContainerHighest: surfaceContainerHighest,
      ),
      cardTheme: const CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
      ),
      dividerTheme: const DividerThemeData(
        color: border,
        thickness: 1,
        space: 1,
      ),
      inputDecorationTheme: InputDecorationTheme(
        isDense: true,
        filled: true,
        fillColor: inputFill,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: Color(0xFF3E3E42)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: Color(0xFF3E3E42)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: primaryAccent, width: 1.5),
        ),
      ),
      visualDensity: VisualDensity.compact,
    );
  }
}
