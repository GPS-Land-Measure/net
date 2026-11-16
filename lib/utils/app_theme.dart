import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppTheme {
  // ValueNotifier so any widget, screen, or bottom navigation bar can reactively re-render
  static final ValueNotifier<Color> primaryColor = ValueNotifier<Color>(const Color(0xFF1338BE));
  static final ValueNotifier<Color> primaryDarkColor = ValueNotifier<Color>(const Color(0xFF0D2888));
  static final ValueNotifier<String> colorThemeName = ValueNotifier<String>('ខៀវរាជ (Cobalt Blue)');

  static Color get currentPrimary => primaryColor.value;
  static Color get currentPrimaryDark => primaryDarkColor.value;
  static String get currentThemeName => colorThemeName.value;

  static Color getColor(String name) {
    if (name.contains('បៃតង')) return const Color(0xFF059669); // Emerald Green
    if (name.contains('ទឹកក្រូច') || name.contains('មាស')) return const Color(0xFFD97706); // Golden Amber
    if (name.contains('ផ្កាឈូក')) return const Color(0xFFEC4899); // Rose Pink
    if (name.contains('ក្រហម')) return const Color(0xFFDC2626); // Ruby Red
    if (name.contains('ស្វាយ')) return const Color(0xFF7C3AED); // Royal Purple
    if (name.contains('ផ្ទៃមេឃ') || name.contains('Cyan')) return const Color(0xFF0284C7); // Cyan Sky
    if (name.contains('លឿង')) return const Color(0xFFEAB308); // Electric Yellow
    return const Color(0xFF1338BE); // Cobalt Blue
  }

  static Color getDarkColor(String name) {
    if (name.contains('បៃតង')) return const Color(0xFF047857);
    if (name.contains('ទឹកក្រូច') || name.contains('មាស')) return const Color(0xFFB45309);
    if (name.contains('ផ្កាឈូក')) return const Color(0xFFBE185D);
    if (name.contains('ក្រហម')) return const Color(0xFFB91C1C);
    if (name.contains('ស្វាយ')) return const Color(0xFF6D28D9);
    if (name.contains('ផ្ទៃមេឃ') || name.contains('Cyan')) return const Color(0xFF0369A1);
    if (name.contains('លឿង')) return const Color(0xFFCA8A04);
    return const Color(0xFF0D2888);
  }

  static Future<void> setTheme(String name) async {
    colorThemeName.value = name;
    primaryColor.value = getColor(name);
    primaryDarkColor.value = getDarkColor(name);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('pref_color', name);
    } catch (_) {}
  }

  static Future<void> loadSavedTheme() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString('pref_color') ?? 'ខៀវរាជ (Cobalt Blue)';
      colorThemeName.value = saved;
      primaryColor.value = getColor(saved);
      primaryDarkColor.value = getDarkColor(saved);
    } catch (_) {}
  }
}

class AppColors {
  // Deep Night & Dark Purple Backgrounds
  static const Color bgDark = Color(0xFF0C0D19);
  static const Color bgCard = Color(0xFF16182E);
  static const Color bgCardSubtle = Color(0xFF1E213D);
  static const Color bgSurface = Color(0xFF141528);

  // Sunset & Neon Gradients (From reference pictures)
  static const Color sunsetPink = Color(0xFFFF2A6D);
  static const Color sunsetCoral = Color(0xFFFF5E62);
  static const Color sunsetOrange = Color(0xFFFF9966);
  static const Color sunsetYellow = Color(0xFFFFD166);
  static const Color neonPurple = Color(0xFF9D4EDD);

  // Status & Accents
  static const Color cyanAccent = Color(0xFF05D9E8);
  static const Color greenAccent = Color(0xFF00F5D4);
  static const Color redAccent = Color(0xFFFF3366);

  // Gradients
  static const LinearGradient sunsetGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFFE9237B),
      Color(0xFFFF486A),
      Color(0xFFFF8E53),
    ],
  );

  static const LinearGradient purpleGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFF7B2CBF),
      Color(0xFF9D4EDD),
      Color(0xFFE9237B),
    ],
  );

  static const LinearGradient cardDarkGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFF1D1F38),
      Color(0xFF131427),
    ],
  );

  static const LinearGradient bottomBarGradient = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [
      Color(0xFF141527),
      Color(0xFF1B1D36),
      Color(0xFF141527),
    ],
  );
}

