
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // Light, modern, clean theme used across the app
  static final ThemeData lightTheme = ThemeData(
    brightness: Brightness.light,
    primaryColor: const Color(0xFF0B63FF),
    scaffoldBackgroundColor: Colors.white,
    // Use Poppins across the app with slightly reduced default sizes
    textTheme: _poppinsTextTheme(ThemeData.light().textTheme),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.white,
      elevation: 0,
      titleTextStyle: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.black87),
      iconTheme: const IconThemeData(color: Colors.black54),
    ),
    colorScheme: const ColorScheme.light(
      primary: Color(0xFF0B63FF),
      secondary: Color(0xFF00C2FF),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        backgroundColor: const Color(0xFF0B63FF),
        foregroundColor: Colors.white,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.grey[100],
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
    ),
  );

  static TextTheme _poppinsTextTheme(TextTheme base) {
    final t = GoogleFonts.poppinsTextTheme(base);
    return t.copyWith(
      // map older names to Material 3 equivalents
      titleLarge: t.titleLarge?.copyWith(fontSize: 18.0, fontWeight: FontWeight.w600),
      titleMedium: t.titleMedium?.copyWith(fontSize: 15.0),
      bodyLarge: t.bodyLarge?.copyWith(fontSize: 14.0),
      bodyMedium: t.bodyMedium?.copyWith(fontSize: 13.0),
      bodySmall: t.bodySmall?.copyWith(fontSize: 12.0),
      labelLarge: t.labelLarge?.copyWith(fontSize: 14.0, fontWeight: FontWeight.w600),
    );
  }
}
