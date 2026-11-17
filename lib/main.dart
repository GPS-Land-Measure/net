import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'utils/app_theme.dart';
import 'utils/offline_helper.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize offline network listener
  OfflineHelper.init();

  // Load saved theme color across the whole application
  await AppTheme.loadSavedTheme();

  // Ensure default offline surveyor profile exists so app ALWAYS opens offline
  try {
    final prefs = await SharedPreferences.getInstance();
    final savedLogin = prefs.getBool('is_logged_in') ?? false;
    final userEmail = prefs.getString('user_email');
    if (!savedLogin || userEmail == null || userEmail.isEmpty) {
      await prefs.setBool('is_logged_in', true);
      await prefs.setString('user_name', 'អ្នកវាស់ដី (Offline Surveyor)');
      await prefs.setString('user_email', 'surveyor@offline.local');
      await prefs.setString('user_role', 'អ្នកវាស់ដី (Surveyor Pro)');
      await prefs.setString('user_provider', 'Offline Mode');
    }
  } catch (_) {}

  runApp(const GpsMeasureApp(isLoggedIn: true));
}

class GpsMeasureApp extends StatelessWidget {
  final bool isLoggedIn;

  const GpsMeasureApp({super.key, this.isLoggedIn = false});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Color>(
      valueListenable: AppTheme.primaryColor,
      builder: (context, primary, _) {
        return MaterialApp(
          title: 'GPS Land Measure',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            fontFamily: 'Kantumruy Pro',
            fontFamilyFallback: const [
              'Kantumruy Pro',
              'Khmer UI',
              'Battambang',
              'Khmer Sangam MN',
              'Noto Sans Khmer',
              'Khmer OS Siemreap',
              'Khmer OS',
              'sans-serif',
            ],
            colorScheme: ColorScheme.fromSeed(
              seedColor: primary,
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
      },
    );
  }
}
