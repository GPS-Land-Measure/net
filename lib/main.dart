import 'package:flutter/material.dart';
import 'screens/login_screen.dart';
import 'utils/app_theme.dart';

void main() {
  runApp(const GpsMeasureApp());
}

class GpsMeasureApp extends StatelessWidget {
  const GpsMeasureApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GPS Land Measure',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.sunsetPink,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: AppColors.bgDark,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          foregroundColor: Colors.white,
        ),
        textTheme: const TextTheme(
          bodyMedium: TextStyle(color: Colors.white),
        ),
      ),
      home: const LoginScreen(),
    );
  }
}
