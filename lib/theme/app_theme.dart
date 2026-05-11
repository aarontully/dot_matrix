import 'package:flutter/material.dart';

class AppTheme {
  static const Color primaryBlue = Color(0xFF0084FF); // Messenger classic blue
  static const Color messageGray = Color(
    0xFFE4E6EB,
  ); // Chat bubble gray for received
  static const Color scaffoldBackground = Colors.white;
  static const Color settingsBackground = Color(
    0xFFF1F5FB,
  ); // Light blueish white for settings

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryBlue,
        primary: primaryBlue,
        surface: scaffoldBackground,
      ),
      scaffoldBackgroundColor: scaffoldBackground,
      appBarTheme: const AppBarTheme(
        backgroundColor: scaffoldBackground,
        foregroundColor: Colors.black,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        iconTheme: IconThemeData(color: Colors.black87),
        titleTextStyle: TextStyle(
          color: Colors.black,
          fontSize: 24,
          fontWeight: FontWeight.bold,
          letterSpacing: -0.5,
        ),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: scaffoldBackground,
        selectedItemColor: primaryBlue,
        unselectedItemColor: Colors.black54,
        type: BottomNavigationBarType.fixed,
        elevation: 8,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFFF0F2F5),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(30),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(30),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(30),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      ),
      iconTheme: const IconThemeData(color: primaryBlue),
      dividerTheme: DividerThemeData(
        color: Colors.grey.withValues(alpha: 0.2),
        thickness: 1,
        space: 1,
      ),
    );
  }
}
