import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'utils/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  bool isLoggedIn = false;
  try {
    final prefs = await SharedPreferences.getInstance();
    final savedLogin = prefs.getBool('is_logged_in') ?? false;
    final userEmail = prefs.getString('user_email');
    if (savedLogin && userEmail != null && userEmail.isNotEmpty) {
      isLoggedIn = true;
    }
  } catch (_) {}

  runApp(GpsMeasureApp(isLoggedIn: isLoggedIn));
}

class GpsMeasureApp extends StatelessWidget {
  final bool isLoggedIn;

  const GpsMeasureApp({super.key, this.isLoggedIn = false});

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
      home: isLoggedIn ? const HomeScreen() : const LoginScreen(),
    );
  }
}
