import 'package:flutter/material.dart';

class AppTheme {
  // Custom Color Palette
  static const Color backgroundColor = Color(0xFF0F172A); // slate-900
  static const Color surfaceColor = Color(0xFF1E293B); // slate-800
  static const Color primaryColor = Color(0xFF10B981); // emerald-500
  static const Color secondaryColor = Color(0xFF14B8A6); // teal-500
  static const Color errorColor = Color(0xFFF43F5E); // rose-500
  static const Color warningColor = Color(0xFFF59E0B); // amber-500
  static const Color textPrimaryColor = Color(0xFFF8FAFC); // slate-50
  static const Color textSecondaryColor = Color(0xFF94A1B2); // slate-400

  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      primaryColor: primaryColor,
      scaffoldBackgroundColor: backgroundColor,
      cardColor: surfaceColor,
      colorScheme: const ColorScheme.dark(
        primary: primaryColor,
        secondary: secondaryColor,
        surface: surfaceColor,
        error: errorColor,
      ),
      dialogBackgroundColor: surfaceColor,
      appBarTheme: const AppBarTheme(
        backgroundColor: backgroundColor,
        elevation: 0,
        iconTheme: IconThemeData(color: textPrimaryColor),
        titleTextStyle: TextStyle(
          color: textPrimaryColor,
          fontFamily: 'Outfit',
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
      ),
      textTheme: const TextTheme(
        titleLarge: TextStyle(fontFamily: 'Outfit', fontWeight: FontWeight.bold, color: textPrimaryColor),
        titleMedium: TextStyle(fontFamily: 'Outfit', fontWeight: FontWeight.w600, color: textPrimaryColor),
        bodyLarge: TextStyle(fontFamily: 'Inter', color: textPrimaryColor),
        bodyMedium: TextStyle(fontFamily: 'Inter', color: textSecondaryColor),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceColor,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.05)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: primaryColor, width: 1.5),
        ),
        labelStyle: const TextStyle(color: textSecondaryColor, fontSize: 14),
        hintStyle: const TextStyle(color: textSecondaryColor, fontSize: 14),
      ),
      useMaterial3: true,
    );
  }
}
