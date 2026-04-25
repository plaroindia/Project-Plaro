import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Provider
// ─────────────────────────────────────────────────────────────────────────────

final themeNotifierProvider = StateNotifierProvider<ThemeNotifier, ThemeMode>(
  (ref) => ThemeNotifier(),
);

// ─────────────────────────────────────────────────────────────────────────────
// Notifier — with SharedPreferences persistence
// ─────────────────────────────────────────────────────────────────────────────

class ThemeNotifier extends StateNotifier<ThemeMode> {
  static const _key = 'theme_mode';

  ThemeNotifier() : super(ThemeMode.dark) {
    _loadSaved();
  }

  Future<void> _loadSaved() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_key);
    if (saved == 'light') {
      state = ThemeMode.light;
    } else {
      state = ThemeMode.dark; // default
    }
  }

  Future<void> toggleTheme(bool isDark) async {
    state = isDark ? ThemeMode.dark : ThemeMode.light;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, isDark ? 'dark' : 'light');
  }

  Future<void> setTheme(ThemeMode mode) async {
    state = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, mode == ThemeMode.dark ? 'dark' : 'light');
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// App themes (unchanged)
// ─────────────────────────────────────────────────────────────────────────────

class AppThemes {
  static ThemeData darkTheme = ThemeData(
    brightness: Brightness.dark,
    useMaterial3: true,
    scaffoldBackgroundColor: const Color(0xFF0F0F0F),
    colorScheme: const ColorScheme.dark(
      primary: Colors.blue,
      secondary: Color(0xFF00E5FF),
      surface: Color(0xFF1A1A1A),
      onSurface: Colors.white,
      onPrimary: Colors.white,
      error: Color(0xFFFF5252),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Color(0xFF0F0F0F),
      foregroundColor: Colors.white,
      elevation: 0,
      centerTitle: false,
      iconTheme: IconThemeData(color: Colors.white),
      titleTextStyle: TextStyle(
        color: Colors.white,
        fontSize: 22.0,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
        fontFamily: 'Inter',
      ),
    ),
    drawerTheme: const DrawerThemeData(
      backgroundColor: Color(0xFF1A1A1A),
      elevation: 0,
    ),
    iconTheme: const IconThemeData(color: Colors.white, size: 24),
    dividerColor: Colors.white10,
    cardTheme: CardThemeData(
      color: const Color(0xFF1A1A1A),
      elevation: 8,
      shadowColor: Colors.black54,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
    ),
    textTheme: const TextTheme(
      displayLarge: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: -1),
      titleLarge:   TextStyle(color: Colors.white, fontWeight: FontWeight.w600, letterSpacing: -0.5),
      bodyLarge:    TextStyle(color: Color(0xE6FFFFFF), fontSize: 16),
      bodyMedium:   TextStyle(color: Color(0xB3FFFFFF), fontSize: 14),
      labelLarge:   TextStyle(fontWeight: FontWeight.w600, letterSpacing: 0.5),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        elevation: 0,
        backgroundColor: const Color(0xFF2196F3),
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: const Color(0xFF2196F3),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFF1A1A1A),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0x1AFFFFFF)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.blue, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: const Color(0xFF1A1A1A),
      contentTextStyle: const TextStyle(color: Colors.white),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      behavior: SnackBarBehavior.floating,
    ),
  );

  static ThemeData lightTheme = ThemeData(
    brightness: Brightness.light,
    useMaterial3: true,
    scaffoldBackgroundColor: const Color(0xFFF8F9FA),
    colorScheme: const ColorScheme.light(
      primary: Colors.blue,
      secondary: Color(0xFF00B8D4),
      surface: Colors.white,
      onSurface: Color(0xFF2D2D2D),
      onPrimary: Colors.white,
      error: Color(0xFFD32F2F),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Color(0xFFF8F9FA),
      foregroundColor: Color(0xFF1A1A1A),
      elevation: 0,
      centerTitle: false,
      iconTheme: IconThemeData(color: Color(0xFF1A1A1A)),
      titleTextStyle: TextStyle(
        color: Color(0xFF1A1A1A),
        fontSize: 22.0,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
        fontFamily: 'Inter',
      ),
    ),
    drawerTheme: const DrawerThemeData(backgroundColor: Colors.white, elevation: 0),
    iconTheme: const IconThemeData(color: Color(0xFF1A1A1A), size: 24),
    dividerColor: const Color(0x0D000000),
    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 4,
      shadowColor: const Color(0x0D000000),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
    ),
    textTheme: const TextTheme(
      displayLarge: TextStyle(color: Color(0xFF1A1A1A), fontWeight: FontWeight.bold, letterSpacing: -1),
      titleLarge:   TextStyle(color: Color(0xFF1A1A1A), fontWeight: FontWeight.w600, letterSpacing: -0.5),
      bodyLarge:    TextStyle(color: Color(0xCC000000), fontSize: 16),
      bodyMedium:   TextStyle(color: Color(0x99000000), fontSize: 14),
      labelLarge:   TextStyle(fontWeight: FontWeight.w600, letterSpacing: 0.5),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        elevation: 0,
        backgroundColor: const Color(0xFF2196F3),
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: const Color(0xFF2196F3),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0x0D000000)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.blue, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: const Color(0xFF2D2D2D),
      contentTextStyle: const TextStyle(color: Colors.white),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      behavior: SnackBarBehavior.floating,
    ),
  );
}