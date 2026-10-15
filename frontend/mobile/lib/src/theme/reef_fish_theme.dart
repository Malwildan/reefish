import 'package:flutter/material.dart';

abstract final class ReefishColors {
  static const canvas = Color(0xFFF6F5EF);
  static const textPrimary = Color(0xFF102F3A);
  static const textSecondary = Color(0xFF48676A);
  static const field = Color(0xFFDDEBF2);
  static const border = Color(0xFFD6DEDA);
  static const reef = Color(0xFF188E8B);
  static const primaryAction = Color(0xFF1E6387);
  static const brand = Color(0xFF2B789C);
  static const info = Color(0xFF205B78);
  static const signupAccent = Color(0xFF9A4739);
}

abstract final class ReefishTheme {
  static ThemeData get light => ThemeData(
        useMaterial3: true,
        fontFamily: 'DM Sans',
        textTheme: const TextTheme(
          bodyMedium: TextStyle(
            fontVariations: [FontVariation('opsz', 14)],
          ),
        ),
        scaffoldBackgroundColor: ReefishColors.canvas,
        colorScheme: ColorScheme.fromSeed(
          seedColor: ReefishColors.primaryAction,
          surface: ReefishColors.canvas,
          primary: ReefishColors.primaryAction,
          onPrimary: Colors.white,
          onSurface: ReefishColors.textPrimary,
        ),
        textSelectionTheme: const TextSelectionThemeData(
          cursorColor: ReefishColors.reef,
          selectionColor: Color(0x55188E8B),
          selectionHandleColor: ReefishColors.reef,
        ),
      );
}
