import 'package:flutter/material.dart';
import '../models/card.dart';

class AppTheme {
  static const Color darkBackground = Color(0xFF0A0A0F);
  static const Color darkSurface = Color(0xFF151520);
  static const Color neonRed = Color(0xFFFF1744);
  static const Color neonBlue = Color(0xFF00E5FF);
  static const Color neonGreen = Color(0xFF00FF88);
  static const Color neonYellow = Color(0xFFFFEA00);
  static const Color neonPurple = Color(0xFFE91E63);
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFFB0B0C0);

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: darkBackground,
      colorScheme: const ColorScheme.dark(
        primary: neonBlue,
        secondary: neonPurple,
        surface: darkSurface,
        background: darkBackground,
        error: neonRed,
        onPrimary: darkBackground,
        onSecondary: textPrimary,
        onSurface: textPrimary,
        onBackground: textPrimary,
        onError: textPrimary,
      ),
      textTheme: const TextTheme(
        displayLarge: TextStyle(
          fontFamily: 'SourGummy',
          fontSize: 32,
          fontWeight: FontWeight.w500,
          color: textPrimary,
        ),
        displayMedium: TextStyle(
          fontFamily: 'SourGummy',
          fontSize: 28,
          fontWeight: FontWeight.w500,
          color: textPrimary,
        ),
        displaySmall: TextStyle(
          fontFamily: 'SourGummy',
          fontSize: 24,
          fontWeight: FontWeight.w500,
          color: textPrimary,
        ),
        headlineMedium: TextStyle(
          fontFamily: 'SourGummy',
          fontSize: 22,
          fontWeight: FontWeight.w500,
          color: textPrimary,
        ),
        headlineSmall: TextStyle(
          fontFamily: 'SourGummy',
          fontSize: 20,
          fontWeight: FontWeight.w500,
          color: textPrimary,
        ),
        titleLarge: TextStyle(
          fontFamily: 'SourGummy',
          fontSize: 18,
          fontWeight: FontWeight.w500,
          color: textPrimary,
        ),
        bodyLarge: TextStyle(
          fontFamily: 'SourGummy',
          fontSize: 16,
          color: textPrimary,
        ),
        bodyMedium: TextStyle(
          fontFamily: 'SourGummy',
          fontSize: 14,
          color: textSecondary,
        ),
        bodySmall: TextStyle(
          fontFamily: 'SourGummy',
          fontSize: 12,
          color: textSecondary,
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: darkSurface,
        foregroundColor: textPrimary,
        elevation: 0,
        centerTitle: true,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: neonBlue,
          foregroundColor: darkBackground,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontFamily: 'SourGummy',
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: neonBlue,
          textStyle: const TextStyle(
            fontFamily: 'SourGummy',
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: darkSurface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: neonBlue, width: 2),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: neonBlue, width: 2),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: neonBlue, width: 2),
        ),
        labelStyle: const TextStyle(
          fontFamily: 'SourGummy',
          color: textSecondary,
        ),
        hintStyle: const TextStyle(
          fontFamily: 'SourGummy',
          color: textSecondary,
        ),
      ),
      cardTheme: CardTheme(
        color: darkSurface,
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    );
  }

  static Color getCardColor(CardColor color) {
    switch (color) {
      case CardColor.red:
        return neonRed;
      case CardColor.blue:
        return neonBlue;
      case CardColor.green:
        return neonGreen;
      case CardColor.yellow:
        return neonYellow;
      case CardColor.wild:
        return neonPurple;
    }
  }
}
