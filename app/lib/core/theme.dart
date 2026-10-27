import 'package:flutter/material.dart';

// Палитра из ТЗ (на основе логотипа).
const kPrimary = Color(0xFF1D3557); // глубокий синий
const kPink = Color(0xFFE63946); // насыщенный розовый
const kWarm = Color(0xFFF4A261); // тёплый жёлтый — плашки
const kBg = Color(0xFFFCFAFA); // слоновая кость — фон приложения
const kOk = Color(0xFF2A9D5B);
const kMuted = Color(0xFF6B7A90);
const kLine = Color(0xFFE7E9EE);

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: kPrimary,
    primary: kPrimary,
    secondary: kPink,
    tertiary: kWarm,
    surface: Colors.white,
    error: kPink,
  );
  final rounded = RoundedRectangleBorder(borderRadius: BorderRadius.circular(14));
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: kBg,
    appBarTheme: const AppBarTheme(
      backgroundColor: kBg,
      foregroundColor: kPrimary,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      titleTextStyle: TextStyle(color: kPrimary, fontSize: 20, fontWeight: FontWeight.w700),
    ),
    textTheme: const TextTheme(
      headlineSmall: TextStyle(color: kPrimary, fontWeight: FontWeight.w800),
      titleLarge: TextStyle(color: kPrimary, fontWeight: FontWeight.w700),
      titleMedium: TextStyle(color: kPrimary, fontWeight: FontWeight.w600),
      bodyMedium: TextStyle(color: kPrimary),
      bodyLarge: TextStyle(color: kPrimary),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        shape: rounded,
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        shape: rounded,
        side: const BorderSide(color: kLine),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: kLine)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: kLine)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: kPrimary, width: 1.5)),
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: const BorderSide(color: kLine)),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.white,
      indicatorColor: kWarm.withValues(alpha: 0.35),
      labelTextStyle: WidgetStateProperty.all(const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: kPrimary)),
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    dividerTheme: const DividerThemeData(color: kLine, space: 1),
  );
}
