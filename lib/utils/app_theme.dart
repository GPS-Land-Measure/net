import 'package:flutter/material.dart';

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

