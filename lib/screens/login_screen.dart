import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:google_sign_in_web/web_only.dart' as web_gis;
import 'package:shared_preferences/shared_preferences.dart';
import 'home_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _regFormKey = GlobalKey<FormState>();
  final _emailController = TextEditingController(text: 'admin@gpsmeasure.com');
  final _passwordController = TextEditingController(text: '1234');

  // ── Registration State ──
  final _regNameController = TextEditingController();
  final _regEmailController = TextEditingController();
  final _regPasswordController = TextEditingController();
  final _regConfirmPasswordController = TextEditingController();
  bool _isRegister = false;
  bool _regAgreeTerms = true;
  String _regAccountType = 'អ្នកវាស់ដី (Surveyor Pro)';
  bool _obscureRegPassword = true;
  bool _obscureRegConfirmPassword = true;

  bool _obscurePassword = true;
  bool _rememberMe = true;
  bool _isLoading = false;
  final bool _isGoogleLoading = false;
  String? _errorMessage;

  // Google Cloud Project: third-light-513301-c2 (Project Number: 1059658557356)
  String googleWebClientId =
      '1059658557356-5iugf64fg9l2djkth48ef71e82qtb8g7.apps.googleusercontent.com';
  static bool _isGoogleInitialized = false;
  StreamSubscription<GoogleSignInAuthenticationEvent>? _authEventsSub;

  // ── NEUMORPHIC SOFT UI PALETTE (Matches user's reference image) ──
  static const Color _neuBg = Color(0xFFE8ECF2); // Soft ceramic matte background
  static const Color _neuLightShadow = Color(0xFFFFFFFF); // Top-left highlight
  static const Color _neuDarkShadow = Color(0xFFBCC7D6); // Bottom-right shadow
  static const Color _neuCobalt = Color(0xFF1338BE); // Deep Royal Cobalt Blue
  static const Color _neuCobaltDark = Color(0xFF0D2888);
  static const Color _neuYellow = Color(0xFFF7B731); // Warm Honey Yellow
  static const Color _neuTextDark = Color(0xFF1E2638); // Deep charcoal
  static const Color _neuTextMuted = Color(0xFF6B7A90); // Muted secondary text
  static const Color _neuInputBg = Color(0xFFDFE4EC); // Recessed input background

  static List<BoxShadow> neuExtrudedShadows({double distance = 6, double blur = 14}) => [
        const BoxShadow(
          color: _neuLightShadow,
          offset: Offset(-5, -5),
          blurRadius: 12,
        ),
        BoxShadow(
          color: _neuDarkShadow.withOpacity(0.85),
          offset: const Offset(5, 5),
          blurRadius: 12,
        ),
      ];

  static List<BoxShadow> neuRecessedShadows() => [
        BoxShadow(
          color: _neuDarkShadow.withOpacity(0.55),
          offset: const Offset(2, 2),
          blurRadius: 5,
        ),
        const BoxShadow(
          color: _neuLightShadow,
          offset: Offset(-2, -2),
          blurRadius: 5,
        ),
      ];

  String _lastGmailAccount = '';
  String _lastGmailName = '';

  // Animations
  late AnimationController _fadeCtrl;
  late AnimationController _floatCtrl;

  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;
  late Animation<double> _floatAnim;

  @override
  void initState() {
    super.initState();
    _checkSavedGoogleAccount();
    _initGoogleSignInWeb();

    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.08),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOutCubic));

    _floatCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    )..repeat(reverse: true);
    _floatAnim = Tween<double>(begin: -6, end: 6).animate(
      CurvedAnimation(parent: _floatCtrl, curve: Curves.easeInOut),
    );

    _fadeCtrl.forward();
  }

  @override
  void dispose() {
    _authEventsSub?.cancel();
    _fadeCtrl.dispose();
    _floatCtrl.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _regNameController.dispose();
    _regEmailController.dispose();
    _regPasswordController.dispose();
    _regConfirmPasswordController.dispose();
    super.dispose();
  }

  void _navigateToHome() {
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (_, _, _) => const HomeScreen(),
        transitionsBuilder: (_, anim, _, child) =>
            FadeTransition(opacity: anim, child: child),
        transitionDuration: const Duration(milliseconds: 550),
      ),
    );
  }

  Future<void> _handleEmailLogin() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    await Future.delayed(const Duration(milliseconds: 900));

    final email = _emailController.text.trim();
    final password = _passwordController.text;

    try {
      final prefs = await SharedPreferences.getInstance();
      final savedEmail = prefs.getString('user_email');
      final savedPassword = prefs.getString('user_password');

      if (((email == 'admin@gpsmeasure.com' || email == 'admin') && password == '1234') ||
          (savedEmail != null && email.toLowerCase() == savedEmail.toLowerCase() && password == savedPassword)) {
        await prefs.setBool('is_logged_in', true);
        if (!mounted) return;
        _navigateToHome();
        return;
      }
    } catch (_) {}

    if (!mounted) return;
    setState(() {
      _isLoading = false;
      _errorMessage = 'អ៊ីមែល ឬលេខសម្ងាត់មិនត្រឹមត្រូវទេ!';
    });
  }

  Future<void> _handleRegister() async {
    if (!_regFormKey.currentState!.validate()) return;
    if (!_regAgreeTerms) {
      setState(() {
        _errorMessage = 'សូមចុចយល់ព្រមតាមលក្ខខណ្ឌប្រើប្រាស់!';
      });
      return;
    }
    if (_regPasswordController.text != _regConfirmPasswordController.text) {
      setState(() {
        _errorMessage = 'លេខសម្ងាត់ទាំងពីរមិនដូចគ្នាទេ!';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    await Future.delayed(const Duration(milliseconds: 1000));

    final name = _regNameController.text.trim();
    final email = _regEmailController.text.trim();
    final password = _regPasswordController.text;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('is_logged_in', true);
      await prefs.setString('user_name', name.isNotEmpty ? name : 'Surveyor Pro');
      await prefs.setString('user_email', email);
      await prefs.setString('user_password', password);
      await prefs.setString('user_role', _regAccountType);
      await prefs.setString('user_provider', 'App Registration');
    } catch (_) {}

    if (!mounted) return;
    _navigateToHome();
  }

  Future<void> _checkSavedGoogleAccount() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedEmail = prefs.getString('user_email');
      if (savedEmail != null && savedEmail.isNotEmpty) {
        if (!mounted) return;
        setState(() {
          _lastGmailAccount = savedEmail;
          _lastGmailName = prefs.getString('user_name') ?? 'Google Surveyor';
        });
      }
    } catch (_) {}
  }

  Future<void> _initGoogleSignInWeb() async {
    if (!_isGoogleInitialized) {
      try {
        await GoogleSignIn.instance.initialize(
          clientId: kIsWeb ? googleWebClientId : null,
        );
        _isGoogleInitialized = true;
      } catch (_) {
        _isGoogleInitialized = true;
      }
    }

    _authEventsSub = GoogleSignIn.instance.authenticationEvents.listen((event) async {
      if (event is GoogleSignInAuthenticationEventSignIn) {
        final account = event.user;
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool('is_logged_in', true);
          await prefs.setString('user_email', account.email);
          await prefs.setString('user_name', account.displayName ?? account.email.split('@').first);
          await prefs.setString('user_provider', 'Google');
          if (account.photoUrl != null) {
            await prefs.setString('user_photo', account.photoUrl!);
          }
        } catch (_) {}

        if (!mounted) return;
        ScaffoldMessenger.of(context).clearSnackBars();
        _navigateToHome();
      }
    });
  }

  void _handleGoogleLogin() {
    _showGoogleSignInModal();
  }

  void _showGoogleSignInModal() {
    final nameCtrl = TextEditingController(text: _lastGmailName);
    final gmailCtrl = TextEditingController(text: _lastGmailAccount);
    bool isCustomMode = _lastGmailAccount.isEmpty;
    bool isAuthenticating = false;
    String? modalError;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (modalCtx, setModalState) {
          Future<void> performSignIn(String email, String name) async {
            String cleanEmail = email.trim();
            if (cleanEmail.isEmpty) {
              setModalState(() => modalError = 'សូមបញ្ចូលអាសយដ្ឋាន Gmail!');
              return;
            }
            if (!cleanEmail.contains('@')) {
              cleanEmail = '$cleanEmail@gmail.com';
            }
            if (!cleanEmail.toLowerCase().endsWith('@gmail.com') && !cleanEmail.contains('.')) {
              setModalState(() => modalError = 'ទម្រង់អ៊ីមែលត្រូវតែជា @gmail.com!');
              return;
            }

            setModalState(() {
              isAuthenticating = true;
              modalError = null;
            });

            // Simulate authentic Google OAuth network handshake
            await Future.delayed(const Duration(milliseconds: 900));

            // Save session to SharedPreferences
            try {
              final prefs = await SharedPreferences.getInstance();
              await prefs.setBool('is_logged_in', true);
              await prefs.setString('user_email', cleanEmail);
              await prefs.setString(
                'user_name',
                name.trim().isNotEmpty ? name.trim() : cleanEmail.split('@').first,
              );
              await prefs.setString('user_provider', 'Google');
            } catch (_) {}

            if (!ctx.mounted) return;
            Navigator.pop(ctx);

            if (!mounted) return;
            ScaffoldMessenger.of(context).clearSnackBars();
            _navigateToHome();
          }

          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(modalCtx).viewInsets.bottom),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 480),
              padding: const EdgeInsets.fromLTRB(22, 14, 22, 26),
              decoration: BoxDecoration(
                color: _neuBg,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
                boxShadow: [
                  BoxShadow(
                    color: _neuDarkShadow.withOpacity(0.6),
                    blurRadius: 28,
                    offset: const Offset(0, -8),
                  ),
                  const BoxShadow(
                    color: _neuLightShadow,
                    blurRadius: 10,
                    offset: Offset(0, -2),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Neumorphic pull handle
                  Container(
                    width: 46,
                    height: 5,
                    decoration: BoxDecoration(
                      color: const Color(0xFFCAD3DF),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(height: 18),

                  // Header with Google Logo
                  Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: _neuBg,
                          shape: BoxShape.circle,
                          boxShadow: neuExtrudedShadows(distance: 4, blur: 8),
                        ),
                        child: CustomPaint(painter: _GoogleLogoPainter()),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            Text(
                              'ចូលគណនី Google / Gmail',
                              style: TextStyle(
                                color: _neuTextDark,
                                fontWeight: FontWeight.w900,
                                fontSize: 16.5,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'ជ្រើសរើស ឬ បញ្ចូល Gmail របស់អ្នកដើម្បីវាស់ដី',
                              style: TextStyle(
                                color: _neuTextMuted,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      GestureDetector(
                        onTap: () => Navigator.pop(ctx),
                        child: Container(
                          padding: const EdgeInsets.all(7),
                          decoration: BoxDecoration(
                            color: _neuBg,
                            shape: BoxShape.circle,
                            boxShadow: neuExtrudedShadows(distance: 3, blur: 6),
                          ),
                          child: const Icon(Icons.close_rounded, color: _neuTextMuted, size: 18),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Official Google GIS Button on Web
                  if (kIsWeb) ...[
                    Container(
                      height: 48,
                      margin: const EdgeInsets.only(bottom: 12),
                      alignment: Alignment.center,
                      child: web_gis.renderButton(
                        configuration: web_gis.GSIButtonConfiguration(
                          type: web_gis.GSIButtonType.standard,
                          theme: web_gis.GSIButtonTheme.filledBlue,
                          size: web_gis.GSIButtonSize.large,
                          text: web_gis.GSIButtonText.signinWith,
                          shape: web_gis.GSIButtonShape.pill,
                          minimumWidth: 300,
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        Expanded(child: Container(height: 1, color: _neuTextMuted.withOpacity(0.2))),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          child: Text(
                            'ឬ ចូលរហ័សដោយផ្ទាល់ (Instant 1-Tap)',
                            style: TextStyle(
                              color: _neuTextMuted,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        Expanded(child: Container(height: 1, color: _neuTextMuted.withOpacity(0.2))),
                      ],
                    ),
                    const SizedBox(height: 14),
                  ],

                  if (modalError != null) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF486A).withOpacity(0.12),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFFF486A).withOpacity(0.5)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline_rounded, color: Color(0xFFFF486A), size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              modalError!,
                              style: const TextStyle(color: Color(0xFFFF486A), fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],

                  // Fast 1-Tap Account Item (Neumorphic Extruded Tile)
                  if (!isCustomMode) ...[
                    Container(
                      decoration: BoxDecoration(
                        color: _neuBg,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: neuExtrudedShadows(distance: 4, blur: 10),
                      ),
                      child: InkWell(
                        onTap: isAuthenticating
                            ? null
                            : () => performSignIn(_lastGmailAccount, _lastGmailName),
                        borderRadius: BorderRadius.circular(20),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Row(
                            children: [
                              Container(
                                width: 42,
                                height: 42,
                                decoration: BoxDecoration(
                                  color: _neuCobalt,
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: _neuCobalt.withOpacity(0.4),
                                      blurRadius: 8,
                                      offset: const Offset(0, 3),
                                    ),
                                  ],
                                ),
                                child: Center(
                                  child: Text(
                                    _lastGmailName.isNotEmpty ? _lastGmailName[0].toUpperCase() : 'G',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 18,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _lastGmailName,
                                      style: const TextStyle(
                                        color: _neuTextDark,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 14.5,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      _lastGmailAccount,
                                      style: const TextStyle(
                                        color: _neuTextMuted,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [_neuCobalt, _neuCobaltDark],
                                  ),
                                  borderRadius: BorderRadius.circular(16),
                                  boxShadow: [
                                    BoxShadow(
                                      color: _neuCobalt.withOpacity(0.35),
                                      blurRadius: 8,
                                      offset: const Offset(0, 3),
                                    ),
                                  ],
                                ),
                                child: const Text(
                                  'ចូលភ្លាមៗ',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Switch to custom Gmail entry
                    GestureDetector(
                      onTap: () {
                        setModalState(() {
                          isCustomMode = true;
                          gmailCtrl.clear();
                          nameCtrl.clear();
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: const [
                            Icon(Icons.add_circle_outline_rounded, color: _neuCobalt, size: 18),
                            SizedBox(width: 8),
                            Text(
                              'ប្រើប្រាស់គណនី Gmail ផ្ទាល់ខ្លួនផ្សេងទៀត',
                              style: TextStyle(
                                color: _neuCobalt,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ] else ...[
                    // Custom Gmail Form (Recessed Inset Inputs)
                    // 1. User Full Name
                    Container(
                      decoration: BoxDecoration(
                        color: _neuInputBg,
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: neuRecessedShadows(),
                      ),
                      child: TextField(
                        controller: nameCtrl,
                        style: const TextStyle(color: _neuTextDark, fontSize: 14, fontWeight: FontWeight.w700),
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.person_outline_rounded, color: _neuCobalt, size: 20),
                          hintText: 'ឈ្មោះរបស់អ្នក (ឧ. សុខា ដីធ្លី)',
                          hintStyle: TextStyle(color: _neuTextMuted, fontSize: 13),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // 2. Gmail Address
                    Container(
                      decoration: BoxDecoration(
                        color: _neuInputBg,
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: neuRecessedShadows(),
                      ),
                      child: TextField(
                        controller: gmailCtrl,
                        keyboardType: TextInputType.emailAddress,
                        style: const TextStyle(color: _neuTextDark, fontSize: 14, fontWeight: FontWeight.w700),
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.mail_outline_rounded, color: _neuCobalt, size: 20),
                          hintText: 'អាសយដ្ឋាន Gmail (ឧ. yourname@gmail.com)',
                          hintStyle: const TextStyle(color: _neuTextMuted, fontSize: 13),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                          suffixIcon: GestureDetector(
                            onTap: () {
                              if (!gmailCtrl.text.contains('@')) {
                                gmailCtrl.text = '${gmailCtrl.text.trim()}@gmail.com';
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              margin: const EdgeInsets.only(right: 8, top: 8, bottom: 8),
                              decoration: BoxDecoration(
                                color: _neuCobalt.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Center(
                                widthFactor: 1,
                                child: Text(
                                  '+ @gmail.com',
                                  style: TextStyle(color: _neuCobalt, fontSize: 11, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Back to default list
                    GestureDetector(
                      onTap: () {
                        setModalState(() {
                          isCustomMode = false;
                        });
                      },
                      child: const Text(
                        '← ត្រឡប់ទៅជ្រើសរើសគណនីមុនវិញ',
                        style: TextStyle(color: _neuTextMuted, fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),

                  // Submit / Sign In Button (Cobalt Blue Neumorphic Pill)
                  GestureDetector(
                    onTap: isAuthenticating
                        ? null
                        : () => performSignIn(gmailCtrl.text, nameCtrl.text),
                    child: Container(
                      width: double.infinity,
                      height: 52,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFF1A46DC), Color(0xFF0F319F)],
                        ),
                        borderRadius: BorderRadius.circular(22),
                        boxShadow: [
                          BoxShadow(
                            color: _neuCobalt.withOpacity(0.45),
                            blurRadius: 18,
                            offset: const Offset(0, 7),
                          ),
                          const BoxShadow(
                            color: _neuLightShadow,
                            blurRadius: 8,
                            offset: Offset(-2, -2),
                          ),
                        ],
                      ),
                      child: Center(
                        child: isAuthenticating
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2.2,
                                ),
                              )
                            : Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: const [
                                  Icon(Icons.login_rounded, color: _neuYellow, size: 20),
                                  SizedBox(width: 8),
                                  Text(
                                    'ចូលប្រើប្រាស់ជាមួយ Gmail នេះ',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 15,
                                      letterSpacing: 0.3,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _neuBg,
      body: Stack(
        children: [
          // ── Soft Neumorphic Ambient Highlights ─────────────────
          Positioned(
            top: -60,
            right: -60,
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    _neuLightShadow.withOpacity(0.8),
                    _neuBg.withOpacity(0.1),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: -60,
            left: -60,
            child: Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    _neuDarkShadow.withOpacity(0.35),
                    _neuBg.withOpacity(0.1),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          // ── Main Scroll View ──────────────────────────────────
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                child: FadeTransition(
                  opacity: _fadeAnim,
                  child: SlideTransition(
                    position: _slideAnim,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // ── Neumorphic Dial & Squircle Feature Icons ──
                        AnimatedBuilder(
                          animation: _floatAnim,
                          builder: (_, child) => Transform.translate(
                            offset: Offset(0, _floatAnim.value),
                            child: child,
                          ),
                          child: _buildRich3DBadge(),
                        ),
                        const SizedBox(height: 22),

                        // ── Title & Soft Pill Subtitle ─────────
                        _buildTitleSection(),
                        const SizedBox(height: 26),

                        // ── Neumorphic Soft UI Form Card ───────
                        _buildNeuFormCard(),
                        const SizedBox(height: 22),

                        // ── Or Divider ─────────────────────────
                        _buildOrDivider(),
                        const SizedBox(height: 20),

                        // ── Neumorphic Google Sign In Button ───
                        _buildGoogleSignInButton(),
                        const SizedBox(height: 24),

                        // ── App Footer ─────────────────────────
                        const Text(
                          'GPS Measure • High Precision Satellite v2.0',
                          style: TextStyle(
                            color: _neuTextMuted,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // 1. NEUMORPHIC GPS COMPASS DIAL
  // ─────────────────────────────────────────────────────────────
  Widget _buildRich3DBadge() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Neumorphic Compass / Satellite Dial
        Container(
          width: 116,
          height: 116,
          decoration: BoxDecoration(
            color: _neuBg,
            shape: BoxShape.circle,
            boxShadow: neuExtrudedShadows(distance: 8, blur: 20),
          ),
          child: Center(
            child: Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: _neuBg,
                shape: BoxShape.circle,
                border: Border.all(
                  color: _neuCobalt.withOpacity(0.85),
                  width: 2.2,
                ),
                boxShadow: neuRecessedShadows(),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Compass Tick Ring Indicator
                  Container(
                    width: 78,
                    height: 78,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _neuCobalt.withOpacity(0.2),
                        width: 1.2,
                      ),
                    ),
                  ),

                  // Honey Yellow Satellite / Sun Orb
                  Positioned(
                    top: 15,
                    right: 17,
                    child: Container(
                      width: 13,
                      height: 13,
                      decoration: BoxDecoration(
                        color: _neuYellow,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: _neuYellow.withOpacity(0.8),
                            blurRadius: 8,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Center Cobalt Blue Terrain & GPS Satellite Icon
                  const Icon(
                    Icons.explore_rounded,
                    color: _neuCobalt,
                    size: 46,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────
  // 2. TITLE SECTION (Neumorphic Dark Typography & Soft Pill)
  // ─────────────────────────────────────────────────────────────
  Widget _buildTitleSection() {
    return Column(
      children: [
        const Text(
          'GPS Land Measure',
          style: TextStyle(
            color: _neuTextDark,
            fontSize: 27,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: _neuBg,
            borderRadius: BorderRadius.circular(22),
            boxShadow: neuExtrudedShadows(distance: 4, blur: 10),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: _neuYellow,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: _neuYellow.withOpacity(0.9),
                      blurRadius: 6,
                      spreadRadius: 1,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 9),
              const Text(
                'កម្មវិធីវាស់ដី និងគណនាប្លង់ GPS ជំនាន់ថ្មី',
                style: TextStyle(
                  color: _neuCobalt,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────
  // 3. MAIN NEUMORPHIC FORM CARD (Sign In & Register Switcher)
  // ─────────────────────────────────────────────────────────────
  Widget _buildNeuFormCard() {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: _neuBg,
        borderRadius: BorderRadius.circular(28),
        boxShadow: neuExtrudedShadows(distance: 8, blur: 22),
        border: Border.all(color: Colors.white, width: 1.4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Neumorphic Segmented Switcher Pill ──
          Container(
            height: 48,
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: _neuInputBg,
              borderRadius: BorderRadius.circular(24),
              boxShadow: neuRecessedShadows(),
            ),
            child: Row(
              children: [
                // Sign In Tab
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        _isRegister = false;
                        _errorMessage = null;
                      });
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeInOut,
                      decoration: BoxDecoration(
                        color: !_isRegister ? _neuBg : Colors.transparent,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: !_isRegister ? neuExtrudedShadows(distance: 3, blur: 8) : null,
                        border: !_isRegister ? Border.all(color: Colors.white, width: 1.2) : null,
                      ),
                      child: Center(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.login_rounded,
                              size: 16,
                              color: !_isRegister ? _neuCobalt : _neuTextMuted,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'ចូលគណនី',
                              style: TextStyle(
                                color: !_isRegister ? _neuCobalt : _neuTextMuted,
                                fontSize: 13,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                // Register Tab
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        _isRegister = true;
                        _errorMessage = null;
                      });
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeInOut,
                      decoration: BoxDecoration(
                        color: _isRegister ? _neuBg : Colors.transparent,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: _isRegister ? neuExtrudedShadows(distance: 3, blur: 8) : null,
                        border: _isRegister ? Border.all(color: Colors.white, width: 1.2) : null,
                      ),
                      child: Center(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.person_add_alt_1_rounded,
                              size: 16,
                              color: _isRegister ? _neuCobalt : _neuTextMuted,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'ចុះឈ្មោះ (Register)',
                              style: TextStyle(
                                color: _isRegister ? _neuCobalt : _neuTextMuted,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // ── Conditional Form Body: Sign In vs Register ──
          if (!_isRegister) ...[
            // ── SIGN IN FORM ──
            Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 4,
                        height: 20,
                        decoration: BoxDecoration(
                          color: _neuCobalt,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'ចូលគណនី (Sign In)',
                        style: TextStyle(
                          color: _neuTextDark,
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Email / Username
                  _buildInputLabel('អ៊ីមែល ឬ ឈ្មោះគណនី'),
                  const SizedBox(height: 8),
                  _buildTextField(
                    controller: _emailController,
                    hint: 'admin@gpsmeasure.com',
                    icon: Icons.mail_outline_rounded,
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'សូមបញ្ចូលអ៊ីមែល' : null,
                  ),
                  const SizedBox(height: 16),

                  // Password
                  _buildInputLabel('លេខសម្ងាត់ (Password)'),
                  const SizedBox(height: 8),
                  _buildTextField(
                    controller: _passwordController,
                    hint: '••••••••',
                    icon: Icons.lock_outline_rounded,
                    isPassword: true,
                    obscure: _obscurePassword,
                    onTogglePassword: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                    validator: (v) =>
                        (v == null || v.isEmpty) ? 'សូមបញ្ចូលលេខសម្ងាត់' : null,
                  ),

                  const SizedBox(height: 14),

                  // Remember Me & Forgot Password Row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      GestureDetector(
                        onTap: () => setState(() => _rememberMe = !_rememberMe),
                        child: Row(
                          children: [
                            Container(
                              width: 22,
                              height: 22,
                              decoration: BoxDecoration(
                                color: _rememberMe ? _neuCobalt : _neuInputBg,
                                borderRadius: BorderRadius.circular(6),
                                boxShadow: neuRecessedShadows(),
                              ),
                              child: _rememberMe
                                  ? const Icon(
                                      Icons.check_rounded,
                                      color: Colors.white,
                                      size: 16,
                                    )
                                  : null,
                            ),
                            const SizedBox(width: 9),
                            const Text(
                              'ចងចាំខ្ញុំ',
                              style: TextStyle(
                                color: _neuTextDark,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      GestureDetector(
                        onTap: () {},
                        child: const Text(
                          'ភ្លេចលេខសម្ងាត់?',
                          style: TextStyle(
                            color: _neuCobalt,
                            fontSize: 12.5,
                            fontWeight: FontWeight.bold,
                            decoration: TextDecoration.underline,
                            decorationColor: _neuCobalt,
                          ),
                        ),
                      ),
                    ],
                  ),

                  // Error Message Box
                  if (_errorMessage != null) ...[
                    const SizedBox(height: 16),
                    _buildErrorBox(_errorMessage!),
                  ],

                  const SizedBox(height: 22),

                  // Submit Login Button
                  GestureDetector(
                    onTap: _isLoading ? null : _handleEmailLogin,
                    child: Container(
                      width: double.infinity,
                      height: 52,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [_neuCobalt, _neuCobaltDark],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(22),
                        boxShadow: [
                          BoxShadow(
                            color: _neuCobalt.withOpacity(0.45),
                            blurRadius: 16,
                            offset: const Offset(0, 6),
                          ),
                          const BoxShadow(
                            color: _neuLightShadow,
                            blurRadius: 6,
                            offset: Offset(-2, -2),
                          ),
                        ],
                      ),
                      child: Center(
                        child: _isLoading
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2.5,
                                ),
                              )
                            : const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.login_rounded, color: _neuYellow, size: 20),
                                  SizedBox(width: 8),
                                  Text(
                                    'ចូលប្រើប្រាស់',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Toggle to Register Prompt
                  Center(
                    child: GestureDetector(
                      onTap: () {
                        setState(() {
                          _isRegister = true;
                          _errorMessage = null;
                        });
                      },
                      child: RichText(
                        text: const TextSpan(
                          text: 'មិនទាន់មានគណនីមែនទេ? ',
                          style: TextStyle(color: _neuTextMuted, fontSize: 13, fontWeight: FontWeight.w600),
                          children: [
                            TextSpan(
                              text: 'ចុះឈ្មោះ (Register)',
                              style: TextStyle(
                                color: _neuCobalt,
                                fontSize: 13,
                                fontWeight: FontWeight.w900,
                                decoration: TextDecoration.underline,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
            // ── REGISTER FORM ──
            Form(
              key: _regFormKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 4,
                        height: 20,
                        decoration: BoxDecoration(
                          color: _neuYellow,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'ចុះឈ្មោះគណនីថ្មី (Create Account)',
                        style: TextStyle(
                          color: _neuTextDark,
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Full Name / Surveyor Name
                  _buildInputLabel('ឈ្មោះពេញ ឬ ឈ្មោះអ្នកវាស់ដី'),
                  const SizedBox(height: 8),
                  _buildTextField(
                    controller: _regNameController,
                    hint: 'ឧ. វ៉ាន់ សុផាត (Sophat)',
                    icon: Icons.badge_outlined,
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'សូមបញ្ចូលឈ្មោះរបស់អ្នក' : null,
                  ),
                  const SizedBox(height: 14),

                  // Email or Phone
                  _buildInputLabel('អ៊ីមែល ឬ លេខទូរស័ព្ទ'),
                  const SizedBox(height: 8),
                  _buildTextField(
                    controller: _regEmailController,
                    hint: '012 345 678 ឬ user@email.com',
                    icon: Icons.contact_mail_outlined,
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'សូមបញ្ចូលអ៊ីមែល ឬ លេខទូរស័ព្ទ' : null,
                  ),
                  const SizedBox(height: 14),

                  // Account Role Selector
                  _buildInputLabel('ប្រភេទគណនី (Account Role)'),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _buildRoleChip(
                          'អ្នកវាស់ដី',
                          'Surveyor Pro',
                          Icons.straighten_rounded,
                          _regAccountType == 'អ្នកវាស់ដី (Surveyor Pro)',
                          () => setState(() => _regAccountType = 'អ្នកវាស់ដី (Surveyor Pro)'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _buildRoleChip(
                          'ម្ចាស់ដី / ក្រុមហ៊ុន',
                          'Owner / Agency',
                          Icons.domain_rounded,
                          _regAccountType == 'ម្ចាស់ដី / ក្រុមហ៊ុន (Owner)',
                          () => setState(() => _regAccountType = 'ម្ចាស់ដី / ក្រុមហ៊ុន (Owner)'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // Password
                  _buildInputLabel('លេខសម្ងាត់ថ្មី (Password)'),
                  const SizedBox(height: 8),
                  _buildTextField(
                    controller: _regPasswordController,
                    hint: 'យ៉ាងហោច ៤ តួអក្សរឡើងទៅ',
                    icon: Icons.lock_outline_rounded,
                    isPassword: true,
                    obscure: _obscureRegPassword,
                    onTogglePassword: () =>
                        setState(() => _obscureRegPassword = !_obscureRegPassword),
                    validator: (v) =>
                        (v == null || v.length < 4) ? 'លេខសម្ងាត់ត្រូវមានយ៉ាងតិច ៤ ខ្ទង់' : null,
                  ),
                  const SizedBox(height: 14),

                  // Confirm Password
                  _buildInputLabel('បញ្ជាក់លេខសម្ងាត់ (Confirm Password)'),
                  const SizedBox(height: 8),
                  _buildTextField(
                    controller: _regConfirmPasswordController,
                    hint: 'វាយលេខសម្ងាត់ម្តងទៀត',
                    icon: Icons.lock_reset_rounded,
                    isPassword: true,
                    obscure: _obscureRegConfirmPassword,
                    onTogglePassword: () =>
                        setState(() => _obscureRegConfirmPassword = !_obscureRegConfirmPassword),
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'សូមបញ្ជាក់លេខសម្ងាត់';
                      if (v != _regPasswordController.text) return 'លេខសម្ងាត់មិនត្រូវគ្នាទេ';
                      return null;
                    },
                  ),
                  const SizedBox(height: 14),

                  // Agree to Terms Checkbox
                  GestureDetector(
                    onTap: () => setState(() => _regAgreeTerms = !_regAgreeTerms),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Container(
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            color: _regAgreeTerms ? _neuCobalt : _neuInputBg,
                            borderRadius: BorderRadius.circular(6),
                            boxShadow: neuRecessedShadows(),
                          ),
                          child: _regAgreeTerms
                              ? const Icon(
                                  Icons.check_rounded,
                                  color: Colors.white,
                                  size: 16,
                                )
                              : null,
                        ),
                        const SizedBox(width: 9),
                        const Expanded(
                          child: Text(
                            'ខ្ញុំយល់ព្រមតាមលក្ខខណ្ឌប្រើប្រាស់ និងគោលការណ៍ឯកជនភាព',
                            style: TextStyle(
                              color: _neuTextDark,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Error Box if any
                  if (_errorMessage != null) ...[
                    const SizedBox(height: 14),
                    _buildErrorBox(_errorMessage!),
                  ],

                  const SizedBox(height: 22),

                  // Submit Register Button
                  GestureDetector(
                    onTap: _isLoading ? null : _handleRegister,
                    child: Container(
                      width: double.infinity,
                      height: 52,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [_neuCobalt, _neuCobaltDark],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(22),
                        boxShadow: [
                          BoxShadow(
                            color: _neuCobalt.withOpacity(0.45),
                            blurRadius: 16,
                            offset: const Offset(0, 6),
                          ),
                          const BoxShadow(
                            color: _neuLightShadow,
                            blurRadius: 6,
                            offset: Offset(-2, -2),
                          ),
                        ],
                      ),
                      child: Center(
                        child: _isLoading
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2.5,
                                ),
                              )
                            : const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.person_add_rounded, color: _neuYellow, size: 20),
                                  SizedBox(width: 8),
                                  Text(
                                    'ចុះឈ្មោះគណនីថ្មី (Register)',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 15.5,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 0.4,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Toggle to Sign In Prompt
                  Center(
                    child: GestureDetector(
                      onTap: () {
                        setState(() {
                          _isRegister = false;
                          _errorMessage = null;
                        });
                      },
                      child: RichText(
                        text: const TextSpan(
                          text: 'មានគណនីរួចហើយ? ',
                          style: TextStyle(color: _neuTextMuted, fontSize: 13, fontWeight: FontWeight.w600),
                          children: [
                            TextSpan(
                              text: 'ចូលគណនីវិញ (Sign In)',
                              style: TextStyle(
                                color: _neuCobalt,
                                fontSize: 13,
                                fontWeight: FontWeight.w900,
                                decoration: TextDecoration.underline,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRoleChip(String title, String subtitle, IconData icon, bool isSelected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? _neuCobalt : _neuBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? _neuCobalt : Colors.white,
            width: 1.3,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: _neuCobalt.withOpacity(0.35),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ]
              : neuExtrudedShadows(distance: 2.5, blur: 6),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 18,
              color: isSelected ? _neuYellow : _neuCobalt,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isSelected ? Colors.white : _neuTextDark,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isSelected ? Colors.white.withOpacity(0.8) : _neuTextMuted,
                      fontSize: 9.5,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorBox(String msg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFF486A).withOpacity(0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFF486A).withOpacity(0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: Color(0xFFFF486A), size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              msg,
              style: const TextStyle(
                color: Color(0xFFFF486A),
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputLabel(String label) {
    return Text(
      label,
      style: const TextStyle(
        color: _neuTextDark,
        fontSize: 13,
        fontWeight: FontWeight.bold,
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    bool isPassword = false,
    bool obscure = false,
    VoidCallback? onTogglePassword,
    String? Function(String?)? validator,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: _neuInputBg,
        borderRadius: BorderRadius.circular(18),
        boxShadow: neuRecessedShadows(),
      ),
      child: TextFormField(
        controller: controller,
        obscureText: obscure,
        style: const TextStyle(
          color: _neuTextDark,
          fontSize: 14.5,
          fontWeight: FontWeight.w700,
        ),
        cursorColor: _neuCobalt,
        validator: validator,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(
            color: _neuTextMuted,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
          prefixIcon: Icon(icon, color: _neuCobalt, size: 20),
          suffixIcon: isPassword
              ? GestureDetector(
                  onTap: onTogglePassword,
                  child: Icon(
                    obscure
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    color: _neuCobalt.withOpacity(0.7),
                    size: 20,
                  ),
                )
              : null,
          filled: false,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: const BorderSide(color: _neuCobalt, width: 1.6),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: const BorderSide(color: Color(0xFFFF2A6D), width: 1.4),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: const BorderSide(color: Color(0xFFFF2A6D), width: 1.6),
          ),
          errorStyle: const TextStyle(
            color: Color(0xFFFF486A),
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // 4. OR DIVIDER
  // ─────────────────────────────────────────────────────────────
  Widget _buildOrDivider() {
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 1.5,
            decoration: BoxDecoration(
              color: const Color(0xFFD4DAE4),
              boxShadow: const [
                BoxShadow(color: _neuLightShadow, offset: Offset(0, 1)),
              ],
            ),
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 14),
          child: Text(
            'ឬ ភ្ជាប់តាមរយៈ',
            style: TextStyle(
              color: _neuTextMuted,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        Expanded(
          child: Container(
            height: 1.5,
            decoration: BoxDecoration(
              color: const Color(0xFFD4DAE4),
              boxShadow: const [
                BoxShadow(color: _neuLightShadow, offset: Offset(0, 1)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────
  // 5. GOOGLE SIGN-IN BUTTON (Neumorphic Ceramic Pill)
  // ─────────────────────────────────────────────────────────────
  Widget _buildGoogleSignInButton() {
    return GestureDetector(
      onTap: _isGoogleLoading ? null : _handleGoogleLogin,
      child: Container(
        width: double.infinity,
        height: 54,
        decoration: BoxDecoration(
          color: _neuBg,
          borderRadius: BorderRadius.circular(22),
          boxShadow: neuExtrudedShadows(distance: 5, blur: 14),
          border: Border.all(color: Colors.white, width: 1.2),
        ),
        child: Center(
          child: _isGoogleLoading
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    color: _neuCobalt,
                    strokeWidth: 2.2,
                  ),
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Official 4-Color Google "G" Badge
                    Container(
                      width: 32,
                      height: 32,
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: _neuDarkShadow.withOpacity(0.5),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: CustomPaint(
                        painter: _GoogleLogoPainter(),
                      ),
                    ),
                    const SizedBox(width: 14),
                    const Text(
                      'ចូលជាមួយ Google / Gmail',
                      style: TextStyle(
                        color: _neuTextDark,
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// OFFICIAL GOOGLE 4-COLOR LOGO VECTOR PAINTER
// ─────────────────────────────────────────────────────────────
class _GoogleLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final strokeWidth = size.width * 0.22;
    final rect = Rect.fromCircle(center: center, radius: radius - strokeWidth / 2);

    final bluePaint = Paint()
      ..color = const Color(0xFF4285F4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.butt;

    final greenPaint = Paint()
      ..color = const Color(0xFF34A853)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.butt;

    final yellowPaint = Paint()
      ..color = const Color(0xFFFBBC05)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.butt;

    final redPaint = Paint()
      ..color = const Color(0xFFEA4335)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.butt;

    // Google 4 color arcs
    canvas.drawArc(rect, -0.4, 1.25, false, bluePaint);
    canvas.drawArc(rect, 0.85, 1.45, false, greenPaint);
    canvas.drawArc(rect, 2.3, 1.35, false, yellowPaint);
    canvas.drawArc(rect, 3.65, 1.6, false, redPaint);

    // Blue horizontal bar
    final barPaint = Paint()
      ..color = const Color(0xFF4285F4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.butt;

    canvas.drawLine(
      Offset(center.dx - radius * 0.05, center.dy),
      Offset(center.dx + radius * 0.88, center.dy),
      barPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
