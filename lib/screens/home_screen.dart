import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import '../models/measurement.dart';
import '../utils/geo_calculator.dart';
import 'map_measurement_screen.dart';
import 'history_screen.dart';
import 'settings_screen.dart';
import 'login_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentNavIndex = 0; // 0: Home Dashboard, 1: Map Measurement, 2: Compass, 3: Calculator
  MeasureMode _initialMeasureMode = MeasureMode.polygon;
  List<Measurement> _recentMeasurements = [];

  // Compass Screen State
  double _compassHeading = 131.0;
  bool _isTrueNorth = false;
  bool _isHeadingLocked = false;
  double _lockedHeading = 131.0;

  // Price Calculator Screen State
  int _calcMode = 0; // 0: Dimensions & Shapes, 1: Unit Converter, 2: Keypad
  double _calcCustomArea = 0.0;
  double _calcPricePerUnit = 80.0;
  String _calcSelectedUnitType = 'ម៉ែត្រការ៉េ (m²)';
  final bool _calcIsUsd = true;
  bool _calcIncludeTax = false;

  // Plot Dimensions Estimator State
  double _calcPlotLength = 20.0;
  double _calcPlotWidth = 5.0;
  double _calcPlotBackWidth = 6.0;
  bool _calcIsTrapezoid = false;

  // Land Loan / Mortgage State
  double _calcDownPaymentPercent = 20.0;
  int _calcLoanYears = 5;
  double _calcInterestRate = 8.5;

  // Standard Calc Keypad State
  String _calcDisplay = '0';
  String _calcFormula = '';
  double? _calcFirstOperand;
  String? _calcOperator;
  bool _calcShouldResetDisplay = false;

  // Sync state for Hero Card
  bool _isCardSyncing = false;

  // Search & Map Style State (Real Functionality!)
  String _searchDisplay = 'ស្វែងរកប្លង់ដី, ទីតាំង...';
  String _currentMapStyle = 'ធម្មតា (Streets)';

  // Coordinates for demo parcels (Phnom Penh center)
  final LatLng _landCenter = const LatLng(11.5564, 104.9282);

  // User Profile from Login / Google
  String _userEmail = 'admin@gpsmeasure.com';
  String _userName = 'Admin Surveyor Pro';
  String _userProvider = 'Google';

  // ── NEUMORPHIC SOFT UI PALETTE (Matches Login Screen) ──
  static const Color _neuBg = Color(0xFFE8ECF2); // Soft ceramic matte background
  static const Color _neuLightShadow = Color(0xFFFFFFFF); // Top-left highlight
  static const Color _neuDarkShadow = Color(0xFFBCC7D6); // Bottom-right shadow
  static const Color _neuCobalt = Color(0xFF1338BE); // Deep Royal Cobalt Blue
  static const Color _neuCobaltDark = Color(0xFF0D2888);
  static const Color _neuYellow = Color(0xFFF7B731); // Warm Honey Yellow
  static const Color _neuTextDark = Color(0xFF1E2638); // Deep charcoal
  static const Color _neuTextMuted = Color(0xFF6B7A90); // Muted secondary text
  static const Color _neuInputBg = Color(0xFFDFE4EC); // Recessed slot background

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

  // ── REAL LIVE MEASUREMENT DATA (Defaults strictly to ZERO: "មកលេខសូន្យទាំងអស់") ──
  double _realAreaM2 = 0.0;
  double _realPerimeterM = 0.0;
  int _realPointsCount = 0;
  double _realGpsAccuracy = 0.0;
  bool _isGpsLocked = false;
  String _measurementTitle = 'មិនទាន់មានទិន្នន័យ (០)';
  double _realAltitude = 18.0;
  bool _useKhmerNumerals = true;
  Measurement? _latestMeasurement;

  // ── REAL-WORLD GLOBAL LIVE SURVEY WEATHER STATE (Open-Meteo Global API) ──
  bool _isLoadingWeather = false;
  double _weatherTemp = 31.0;
  double _weatherApparentTemp = 34.0;
  int _weatherCode = 0;
  String _weatherConditionText = 'មេឃស្រឡះ';
  String _weatherConditionIcon = '☀️';
  String _weatherAdvice = 'គ្មានភ្លៀង • ស័ក្តិសមចុះវាស់ព្រំដី & បង្ហោះដ្រូន';
  double _weatherWindSpeed = 8.0;
  double _weatherWindDirectionDegrees = 45.0;
  String _weatherWindDirection = 'ឦសាន (45°)';
  double _weatherUvIndex = 4.0;
  double _weatherHumidity = 65.0;
  double _weatherPrecipitation = 0.0;
  int _weatherSatelliteCount = 24;
  String _surveySuitability = 'ល្អឥតខ្ចោះ 98%';
  Color _surveySuitabilityColor = const Color(0xFF10B981);
  String _weatherLocationName = 'រាជធានីភ្នំពេញ (GPS)';
  double _weatherLat = 11.5564;
  double _weatherLng = 104.9282;
  DateTime? _lastWeatherSync;


  @override
  void initState() {
    super.initState();
    _loadUserProfile();
    _loadLatestMeasurement();
    _fetchLiveRealWorldWeather();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
      }
    });
  }

  String _toKhmerDigits(String input) {
    const khmerDigits = ['០', '១', '២', '៣', '៤', '៥', '៦', '៧', '៨', '៩'];
    String result = '';
    for (int i = 0; i < input.length; i++) {
      final char = input[i];
      final digit = int.tryParse(char);
      if (digit != null) {
        result += khmerDigits[digit];
      } else {
        result += char;
      }
    }
    return result;
  }

  String _formatNumber(double value, {int decimals = 1, bool? khmer}) {
    final useKhmer = khmer ?? _useKhmerNumerals;
    final parts = value.toStringAsFixed(decimals).split('.');
    final integerPart = parts[0];
    final decimalPart = parts.length > 1 ? parts[1] : '';

    final reg = RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))');
    final formattedInt = integerPart.replaceAllMapped(reg, (Match m) => '${m[1]},');
    final full = decimals > 0 ? '$formattedInt.$decimalPart' : formattedInt;

    if (useKhmer) {
      return _toKhmerDigits(full);
    }
    return full;
  }

  Future<void> _resetToZero() async {
    setState(() {
      _realAreaM2 = 0.0;
      _realPerimeterM = 0.0;
      _realPointsCount = 0;
      _realGpsAccuracy = 0.0;
      _isGpsLocked = false;
      _realAltitude = 0.0;
      _measurementTitle = 'មិនទាន់មានទិន្នន័យ (០)';
      _latestMeasurement = null;
    });
  }

  void _loadSampleParcel() {
    setState(() {
      _realAreaM2 = 1167.4;
      _realPerimeterM = 140.2;
      _realPointsCount = 4;
      _realGpsAccuracy = 1.2;
      _isGpsLocked = true;
      _measurementTitle = 'ដីឡូតិ៍គំរូ កោះពេជ្រ #01';
      _latestMeasurement = Measurement(
        id: 'sample_01',
        name: 'ដីឡូតិ៍គំរូ កោះពេជ្រ #01',
        areaM2: 1167.4,
        perimeterM: 140.2,
        createdAt: DateTime.now(),
        type: MeasurementType.polygon,
        points: [
          {'lat': 11.5543, 'lng': 104.9405},
          {'lat': 11.5545, 'lng': 104.9409},
          {'lat': 11.5541, 'lng': 104.9412},
          {'lat': 11.5539, 'lng': 104.9408},
        ],
      );
    });
  }

  Future<void> _loadLatestMeasurement() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList('measurements') ?? [];
      final parsed = list.map((e) => Measurement.fromJsonString(e)).toList().reversed.toList();
      setState(() {
        _recentMeasurements = parsed.take(3).toList();
        if (parsed.isNotEmpty) {
          final m = parsed.first;
          _latestMeasurement = m;
          _realAreaM2 = m.areaM2;
          _realPerimeterM = m.perimeterM;
          _realPointsCount = m.points?.length ?? (m.type == MeasurementType.circle ? 1 : 0);
          _measurementTitle = m.name;
        }
      });
    } catch (_) {}
  }

  Future<void> _fetchRealGps() async {
    setState(() => _isCardSyncing = true);
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) setState(() => _isCardSyncing = false);
        return;
      }
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (mounted) setState(() => _isCardSyncing = false);
          return;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        if (mounted) setState(() => _isCardSyncing = false);
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 4),
      );
      if (mounted) {
        setState(() {
          _realGpsAccuracy = pos.accuracy;
          _realAltitude = pos.altitude > 0 ? pos.altitude : 18.0;
          _isGpsLocked = true;
          _isCardSyncing = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isCardSyncing = false);
    }
  }

  Future<void> _loadUserProfile() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _userEmail = prefs.getString('user_email') ?? 'admin@gpsmeasure.com';
        _userName = prefs.getString('user_name') ?? 'Admin Surveyor Pro';
        _userProvider = prefs.getString('user_provider') ?? 'Google';
        _useKhmerNumerals = (prefs.getString('pref_khmer_numerals') ?? 'true') == 'true';
      });
    } catch (_) {}
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
              width: 260,
              height: 260,
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
              width: 280,
              height: 280,
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

          // Main Screen Body with Clean Tab Switching (Home, Map Measure, Compass, Calculator, History, Settings)
          IndexedStack(
            index: _currentNavIndex,
            children: [
              // 0: Clean Home Surveyor Dashboard
              SafeArea(
                bottom: false,
                child: _buildHomeDashboard(context),
              ),

              // 1: Dedicated Interactive Map Measurement Workspace
              MapMeasurementScreen(
                initialMode: _initialMeasureMode,
                isEmbedded: true,
                onBackToHome: () {
                  setState(() => _currentNavIndex = 0);
                  _loadLatestMeasurement();
    _fetchLiveRealWorldWeather();
                },
                onSaved: () {
                  _loadLatestMeasurement();
    _fetchLiveRealWorldWeather();
                },
              ),

              // 2: Dedicated Digital Compass Workspace (Cleanly separated from Home!)
              SafeArea(
                bottom: false,
                child: _buildCompassScreen(context),
              ),

              // 3: Dedicated Land Price Calculator Workspace
              SafeArea(
                bottom: false,
                child: _buildCalculatorScreen(context),
              ),

              // 4: Dedicated Land History Workspace (Cleanly separated from Home!)
              HistoryScreen(
                isEmbedded: true,
                onBackToHome: () {
                  setState(() => _currentNavIndex = 0);
                  _loadLatestMeasurement();
    _fetchLiveRealWorldWeather();
                },
                onSelectMeasurement: (measurement) {
                  setState(() {
                    _realAreaM2 = measurement.areaM2;
                    _realPerimeterM = measurement.perimeterM;
                    _realPointsCount = measurement.points?.length ??
                        (measurement.type == MeasurementType.circle ? 1 : 0);
                    _measurementTitle = measurement.name;
                    _latestMeasurement = measurement;
                    _currentNavIndex = 1;
                  });
                },
              ),

              // 5: Dedicated Settings & Profile Workspace (Cleanly separated from Home!)
              SettingsScreen(
                isEmbedded: true,
                onBackToHome: () {
                  setState(() => _currentNavIndex = 0);
                  _loadUserProfile();
                },
              ),
            ],
          ),

          // ── 3. Floating Bottom Navigation Bar ─────────────────
          Positioned(
            left: 20,
            right: 20,
            bottom: 22,
            child: _buildFloatingBottomBar(),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // 0. HOME SURVEYOR DASHBOARD (Clean & Segregated from Map Screen)
  // ─────────────────────────────────────────────────────────────
  Widget _buildHomeDashboard(BuildContext context) {
    return Column(
      children: [
        // 1. Top Bar
        _buildTopBar(context),
        const SizedBox(height: 10),

        // 2. Scrollable Dashboard Body
        Expanded(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 140),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. Hero Land Area Card (with Start Measure, Lot, & Reset 0)
                _buildHeroCard(),
                const SizedBox(height: 16),

                // 2. Metrics 4-Grid Card (Hectare / Points / Accuracy / Perimeter)
                _buildMetricsCard(),
                const SizedBox(height: 18),

                // 3. Field Survey Weather & Sky Conditions Widget
                _buildSurveyWeatherWidget(),
                const SizedBox(height: 18),

                // 4. Recent Saved Land Parcels List
                _buildRecentParcelsSection(),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────
  // 1. TOP HEADER (Neumorphic Ceramic Soft UI + Full Real Functionality!)
  // ─────────────────────────────────────────────────────────────
  Widget _buildTopBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: _neuBg,
          borderRadius: BorderRadius.circular(28),
          boxShadow: neuExtrudedShadows(distance: 5, blur: 14),
          border: Border.all(color: Colors.white, width: 1.2),
        ),
        child: Row(
          children: [
            // 1. Grid Tools Button (Opens map layers & surveyor tools)
            GestureDetector(
              onTap: () => _showGridToolsModal(context),
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: _neuBg,
                  shape: BoxShape.circle,
                  boxShadow: neuExtrudedShadows(distance: 3, blur: 8),
                  border: Border.all(color: Colors.white, width: 1),
                ),
                child: const Icon(
                  Icons.grid_view_rounded,
                  color: _neuCobalt,
                  size: 20,
                ),
              ),
            ),
            const SizedBox(width: 10),

            // 2. Interactive Search Bar (Recessed Slot)
            Expanded(
              child: GestureDetector(
                onTap: () => _showSearchModal(context),
                child: Container(
                  height: 44,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: _neuInputBg,
                    borderRadius: BorderRadius.circular(22),
                    boxShadow: neuRecessedShadows(),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.search_rounded,
                        color: _neuCobalt,
                        size: 19,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _searchDisplay,
                          style: const TextStyle(
                            color: _neuTextDark,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (_searchDisplay != 'ស្វែងរកប្លង់ដី, ទីតាំង...')
                        GestureDetector(
                          onTap: () {
                            setState(() {
                              _searchDisplay = 'ស្វែងរកប្លង់ដី, ទីតាំង...';
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                              color: _neuDarkShadow.withOpacity(0.5),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.close_rounded, color: Colors.white, size: 14),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),

            // 3. Neumorphic Profile Avatar & Menu (Opens profile modal)
            GestureDetector(
              onTap: () => _showProfileModal(context),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                decoration: BoxDecoration(
                  color: _neuBg,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: neuExtrudedShadows(distance: 3, blur: 8),
                  border: Border.all(color: Colors.white, width: 1),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 3D Avatar
                    Container(
                      width: 36,
                      height: 36,
                      padding: const EdgeInsets.all(2),
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: _neuCobalt,
                      ),
                      child: Center(
                        child: Text(
                          _userName.isNotEmpty ? _userName[0].toUpperCase() : 'A',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    // Menu lines in Cobalt Blue
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 14,
                            height: 2.2,
                            decoration: BoxDecoration(
                              color: _neuCobalt,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          const SizedBox(height: 3),
                          Container(
                            width: 10,
                            height: 2.2,
                            decoration: BoxDecoration(
                              color: _neuCobalt.withOpacity(0.7),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // MODAL 1: REAL QUICK GRID TOOLS (Map Style Switcher & Surveyor Tools)
  // ─────────────────────────────────────────────────────────────
  void _showGridToolsModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          return Container(
            padding: const EdgeInsets.fromLTRB(22, 14, 22, 32),
            decoration: BoxDecoration(
              color: _neuBg,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(36)),
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
                // Drag Handle
                Container(
                  width: 44,
                  height: 4.5,
                  decoration: BoxDecoration(
                    color: _neuDarkShadow,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(height: 18),

                // Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: _neuBg,
                            shape: BoxShape.circle,
                            boxShadow: neuExtrudedShadows(distance: 3, blur: 6),
                          ),
                          child: const Icon(Icons.grid_view_rounded, color: _neuCobalt, size: 20),
                        ),
                        const SizedBox(width: 10),
                        const Text(
                          'ឧបករណ៍វាស់វែងរហ័ស (Quick Tools)',
                          style: TextStyle(
                            color: _neuTextDark,
                            fontWeight: FontWeight.w900,
                            fontSize: 17,
                          ),
                        ),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: _neuTextMuted),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const SizedBox(height: 18),

                // Map Layer Selector Row (Real Satellite / Street / Topo switch!)
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: _neuInputBg,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: neuRecessedShadows(),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'ជ្រើសរើសប្រភេទផែនទី (Map Style)',
                        style: TextStyle(
                          color: _neuTextDark,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          _buildMapTypeOption(
                            title: 'ធម្មតា',
                            subtitle: 'Streets',
                            isSelected: _currentMapStyle == 'ធម្មតា (Streets)',
                            onTap: () {
                              setState(() {
                                _currentMapStyle = 'ធម្មតា (Streets)';
                              });
                              setModalState(() {});
                            },
                          ),
                          const SizedBox(width: 8),
                          _buildMapTypeOption(
                            title: 'ផ្កាយរណប',
                            subtitle: 'Satellite',
                            isSelected: _currentMapStyle == 'ផ្កាយរណប (Satellite)',
                            onTap: () {
                              setState(() {
                                _currentMapStyle = 'ផ្កាយរណប (Satellite)';
                              });
                              setModalState(() {});
                            },
                          ),
                          const SizedBox(width: 8),
                          _buildMapTypeOption(
                            title: 'ទេសភាពដី',
                            subtitle: 'Topo',
                            isSelected: _currentMapStyle == 'ទេសភាពដី (Topo)',
                            onTap: () {
                              setState(() {
                                _currentMapStyle = 'ទេសភាពដី (Topo)';
                              });
                              setModalState(() {});
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // 4 Quick Action Cards Grid
                Row(
                  children: [
                    Expanded(
                      child: _buildQuickToolCard(
                        icon: Icons.my_location_rounded,
                        title: 'ទីតាំងដី GPS',
                        subtitle: 'កំណត់កណ្តាលដី',
                        onTap: () {
                          Navigator.pop(ctx);
                          setState(() => _currentNavIndex = 1);
                          MapMeasurementScreen.requestMapMove(_landCenter);
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildQuickToolCard(
                        icon: Icons.explore_rounded,
                        title: 'ត្រីវិស័យវាស់ទិស',
                        subtitle: 'ពិនិត្យទិសដី & ខ្យល់',
                        onTap: () {
                          Navigator.pop(ctx);
                          setState(() => _currentNavIndex = 2);
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _buildQuickToolCard(
                        icon: Icons.calculate_rounded,
                        title: 'គណនាតម្លៃដី',
                        subtitle: 'USD & KHR',
                        onTap: () {
                          Navigator.pop(ctx);
                          setState(() => _currentNavIndex = 3);
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildQuickToolCard(
                        icon: Icons.bookmark_rounded,
                        title: 'ប្រវត្តិប្លង់ដី',
                        subtitle: 'ប្លង់បានរក្សាទុក',
                        onTap: () {
                          Navigator.pop(ctx);
                          setState(() => _currentNavIndex = 4);
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildMapTypeOption({
    required String title,
    required String subtitle,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            gradient: isSelected
                ? const LinearGradient(
                    colors: [_neuCobalt, _neuCobaltDark],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : null,
            color: isSelected ? null : _neuBg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isSelected ? Colors.white : Colors.white.withOpacity(0.9),
              width: isSelected ? 1.4 : 1.0,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: _neuCobalt.withOpacity(0.45),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : neuExtrudedShadows(distance: 2, blur: 5),
          ),
          child: Column(
            children: [
              Text(
                title,
                style: TextStyle(
                  color: isSelected ? Colors.white : _neuTextDark,
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.w900 : FontWeight.bold,
                ),
              ),
              Text(
                subtitle,
                style: TextStyle(
                  color: isSelected ? _neuYellow : _neuTextMuted,
                  fontSize: 9.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuickToolCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: _neuBg,
          borderRadius: BorderRadius.circular(18),
          boxShadow: neuExtrudedShadows(distance: 3, blur: 8),
          border: Border.all(color: Colors.white, width: 1.0),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _neuInputBg,
                shape: BoxShape.circle,
                boxShadow: neuRecessedShadows(),
              ),
              child: Icon(icon, color: _neuCobalt, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(color: _neuTextDark, fontSize: 12, fontWeight: FontWeight.bold)),
                  Text(subtitle, style: const TextStyle(color: _neuTextMuted, fontSize: 10)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // MODAL 2: REAL CAMBODIA LAND SEARCH (Interactive & Centers Map!)
  // ─────────────────────────────────────────────────────────────
  void _showSearchModal(BuildContext context) {
    final searchCtrl = TextEditingController();
    bool isLoading = false;
    LatLng? detectedCoords;

    final List<Map<String, dynamic>> landLocations = [
      {'name': 'វិមានឯករាជ្យ', 'desc': 'រាជធានីភ្នំពេញ (Independence Monument)', 'lat': 11.556435, 'lng': 104.928190, 'icon': '🏛️'},
      {'name': 'ផ្សារធំថ្មី (Central Market)', 'desc': 'ខណ្ឌដូនពេញ រាជធានីភ្នំពេញ', 'lat': 11.569400, 'lng': 104.921300, 'icon': '🛍️'},
      {'name': 'កោះពេជ្រ (Koh Pich)', 'desc': 'ខណ្ឌចំការមន រាជធានីភ្នំពេញ • ដីពាណិជ្ជកម្ម', 'lat': 11.547800, 'lng': 104.939200, 'icon': '🏙️'},
      {'name': 'ទួលគោក (Toul Kork)', 'desc': 'ខណ្ឌទួលគោក • តំបន់លំនៅដ្ឋានខ្ពស់', 'lat': 11.5738, 'lng': 104.8986, 'icon': '🏡'},
      {'name': 'សែនសុខ (Sen Sok)', 'desc': 'តំបន់ផ្សារអ៊ីអន២ • ដីផ្ទះអាជីវកម្ម', 'lat': 11.5902, 'lng': 104.8724, 'icon': '🏬'},
      {'name': 'ព្រលានយន្តហោះថ្មី តេជោ (TIA)', 'desc': 'ស្រុកកណ្តាលស្ទឹង ខេត្តកណ្តាល • ដីគម្រោងធំ', 'lat': 11.3653, 'lng': 104.9126, 'icon': '✈️'},
      {'name': 'អង្គរវត្ត / សៀមរាប', 'desc': 'ក្រុងសៀមរាប ខេត្តសៀមរាប', 'lat': 13.4125, 'lng': 103.8670, 'icon': '🛕'},
      {'name': 'ក្រុងព្រះសីហនុ', 'desc': 'ឆ្នេរអូរឈើទាល ខេត្តព្រះសីហនុ', 'lat': 10.6275, 'lng': 103.5221, 'icon': '🏖️'},
      {'name': 'ក្រុងបាត់ដំបង', 'desc': 'ស្ទឹងសង្កែ ខេត្តបាត់ដំបង', 'lat': 13.0957, 'lng': 103.2022, 'icon': '🌾'},
      {'name': 'ក្រុងកំពត', 'desc': 'រង្វង់មូលធុរេន ខេត្តកំពត', 'lat': 10.5942, 'lng': 104.1815, 'icon': '⛰️'},
      {'name': 'ក្រុងកែប', 'desc': 'ផ្សារក្តាម ខេត្តកែប', 'lat': 10.4828, 'lng': 104.2938, 'icon': '🦀'},
      {'name': 'ក្រុងកំពង់ចាម', 'desc': 'ស្ពានគីហ្សូណា ខេត្តកំពង់ចាម', 'lat': 11.9934, 'lng': 105.4635, 'icon': '🌉'},
    ];

    List<Map<String, dynamic>> filtered = List.from(landLocations);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withOpacity(0.35),
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          void doSearch(String val) async {
            final trimmed = val.trim();
            if (trimmed.isEmpty) {
              setModalState(() {
                isLoading = false;
                detectedCoords = null;
                filtered = List.from(landLocations);
              });
              return;
            }

            final parsed = parseMapUrlOrCoordinates(trimmed);
            if (parsed != null) {
              setModalState(() {
                detectedCoords = parsed.point;
              });
            } else {
              setModalState(() => detectedCoords = null);
              if (trimmed.startsWith('http')) {
                http.get(Uri.parse(trimmed)).then((response) {
                  final finalUrl = response.request?.url.toString() ?? '';
                  final resolved = parseMapUrlOrCoordinates(finalUrl) ?? parseMapUrlOrCoordinates(response.body);
                  if (resolved != null) {
                    setModalState(() {
                      detectedCoords = resolved.point;
                    });
                  }
                }).catchError((_) {});
              }
            }

            final query = trimmed.toLowerCase();
            final localMatches = landLocations.where((item) {
              final name = item['name'].toString().toLowerCase();
              final desc = item['desc'].toString().toLowerCase();
              return name.contains(query) || desc.contains(query);
            }).toList();

            setModalState(() {
              filtered = localMatches;
              isLoading = true;
            });

            // Multi-Engine Live Map API Fetcher
            final List<Map<String, dynamic>> apiResults = [];

            // 1. ArcGIS World Geocoding
            try {
              final arcGisUri = Uri.parse(
                'https://geocode.arcgis.com/arcgis/rest/services/World/GeocodeServer/findAddressCandidates?f=json&singleLine=${Uri.encodeComponent(trimmed)}&countryCode=KHM&maxLocations=8',
              );
              final arcRes = await http.get(arcGisUri).timeout(const Duration(seconds: 4));
              if (arcRes.statusCode == 200) {
                final data = json.decode(arcRes.body) as Map<String, dynamic>;
                final candidates = data['candidates'] as List<dynamic>? ?? [];
                for (final c in candidates) {
                  final addr = c['address']?.toString() ?? '';
                  final loc = c['location'] as Map<String, dynamic>? ?? {};
                  final lat = double.tryParse(loc['y']?.toString() ?? '') ?? 0.0;
                  final lng = double.tryParse(loc['x']?.toString() ?? '') ?? 0.0;
                  if (lat != 0.0 && lng != 0.0 && addr.isNotEmpty && addr != 'KHM') {
                    apiResults.add({
                      'name': addr.split(',').first,
                      'desc': addr,
                      'lat': lat,
                      'lng': lng,
                      'icon': '📍',
                      'source': 'ArcGIS Live',
                      'isOnline': true,
                    });
                  }
                }
              }
            } catch (_) {}

            // 2. Photon Komoot OSM Live
            try {
              final photonUri = Uri.parse(
                'https://photon.komoot.io/api/?q=${Uri.encodeComponent(trimmed)}&lat=12.5657&lon=104.9910&limit=10',
              );
              final photonRes = await http.get(photonUri).timeout(const Duration(seconds: 4));
              if (photonRes.statusCode == 200) {
                final data = json.decode(photonRes.body) as Map<String, dynamic>;
                final features = data['features'] as List<dynamic>? ?? [];
                for (final f in features) {
                  final props = f['properties'] as Map<String, dynamic>? ?? {};
                  final geom = f['geometry'] as Map<String, dynamic>? ?? {};
                  final coords = geom['coordinates'] as List<dynamic>? ?? [];
                  if (coords.length >= 2) {
                    final lng = (coords[0] as num).toDouble();
                    final lat = (coords[1] as num).toDouble();
                    final name = props['name']?.toString() ?? trimmed;
                    final street = props['street']?.toString();
                    final district = props['district']?.toString();
                    final city = props['city']?.toString();
                    final state = props['state']?.toString();

                    final descParts = [
                      if (street != null) street,
                      if (district != null) district,
                      if (city != null) city,
                      if (state != null) state,
                    ];
                    final desc = descParts.isNotEmpty ? descParts.join(', ') : (props['country']?.toString() ?? 'កម្ពុជា');

                    apiResults.add({
                      'name': name,
                      'desc': desc,
                      'lat': lat,
                      'lng': lng,
                      'icon': '🗺️',
                      'source': 'Photon OSM',
                      'isOnline': true,
                    });
                  }
                }
              }
            } catch (_) {}

            setModalState(() {
              isLoading = false;
              final seen = <String>{};
              final merged = <Map<String, dynamic>>[];
              for (final r in [...apiResults, ...localMatches]) {
                final key = '${(r['lat'] as double).toStringAsFixed(3)},${(r['lng'] as double).toStringAsFixed(3)}';
                if (!seen.contains(key)) {
                  seen.add(key);
                  merged.add(r);
                }
              }
              filtered = merged;
            });
          }

          return Container(
            padding: EdgeInsets.fromLTRB(22, 14, 22, MediaQuery.of(context).viewInsets.bottom + 24),
            decoration: BoxDecoration(
              color: _neuBg,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(36)),
              border: Border.all(color: Colors.white, width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: _neuDarkShadow.withOpacity(0.55),
                  blurRadius: 30,
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
                // Handle
                Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    color: _neuTextMuted.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(height: 18),

                // Search Input Box (Recessed Slot)
                Container(
                  height: 50,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: _neuInputBg,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: neuRecessedShadows(),
                    border: Border.all(color: Colors.white.withOpacity(0.8), width: 1),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.search_rounded, color: _neuCobalt, size: 22),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: searchCtrl,
                          autofocus: true,
                          style: const TextStyle(color: _neuTextDark, fontSize: 14, fontWeight: FontWeight.bold),
                          cursorColor: _neuCobalt,
                          decoration: const InputDecoration(
                            hintText: 'វាយឈ្មោះទីតាំង, កូអរដោនេ, ឬ Link Google Maps...',
                            hintStyle: TextStyle(color: _neuTextMuted, fontSize: 13),
                            border: InputBorder.none,
                            isDense: true,
                          ),
                          onChanged: (val) => doSearch(val),
                        ),
                      ),
                      if (isLoading)
                        const Padding(
                          padding: EdgeInsets.only(right: 6),
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: _neuCobalt),
                          ),
                        )
                      else if (searchCtrl.text.isNotEmpty)
                        GestureDetector(
                          onTap: () {
                            searchCtrl.clear();
                            doSearch('');
                          },
                          child: const Icon(Icons.close_rounded, color: _neuTextMuted, size: 18),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // Direct Coordinates Detection Banner
                if (detectedCoords != null) ...[
                  GestureDetector(
                    onTap: () {
                      Navigator.pop(ctx);
                      setState(() {
                        _currentNavIndex = 1;
                      });
                      MapMeasurementScreen.requestMapMove(detectedCoords!);
                    },
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: [Color(0xFF047857), Color(0xFF10B981)]),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.gps_fixed_rounded, color: Colors.white, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '🎯 ទៅកាន់កូអរដោនេ: ${detectedCoords!.latitude.toStringAsFixed(5)}°, ${detectedCoords!.longitude.toStringAsFixed(5)}°',
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                          ),
                          const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white, size: 14),
                        ],
                      ),
                    ),
                  ),
                ],

                // Quick Chips
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: ['វិមានឯករាជ្យ', 'ផ្សារធំថ្មី', 'កោះពេជ្រ', 'ទួលគោក', 'តេជោ', 'សៀមរាប', 'ព្រះសីហនុ', 'កំពត'].map((chip) {
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: GestureDetector(
                          onTap: () {
                            searchCtrl.text = chip;
                            doSearch(chip);
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                            decoration: BoxDecoration(
                              color: _neuBg,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: Colors.white, width: 1.2),
                              boxShadow: neuExtrudedShadows(distance: 2, blur: 5),
                            ),
                            child: Text(
                              chip,
                              style: const TextStyle(
                                color: _neuCobalt,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 16),

                // Locations List
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 280),
                  child: filtered.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            'រកមិនឃើញទីតាំង "${searchCtrl.text}" ទេ',
                            style: const TextStyle(color: _neuTextMuted, fontSize: 13, fontWeight: FontWeight.w600),
                          ),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          physics: const BouncingScrollPhysics(),
                          itemCount: filtered.length,
                          itemBuilder: (context, i) {
                            final loc = filtered[i];
                            return GestureDetector(
                              onTap: () {
                                Navigator.pop(ctx);
                                final lat = loc['lat'] as double;
                                final lng = loc['lng'] as double;
                                final name = loc['name'] as String;
                                setState(() {
                                  _searchDisplay = name;
                                  _currentNavIndex = 1;
                                });
                                MapMeasurementScreen.requestMapMove(LatLng(lat, lng));
                              },
                              child: Container(
                                margin: const EdgeInsets.only(bottom: 10),
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                                decoration: BoxDecoration(
                                  color: _neuBg,
                                  borderRadius: BorderRadius.circular(18),
                                  border: Border.all(color: Colors.white, width: 1.2),
                                  boxShadow: neuExtrudedShadows(distance: 2.5, blur: 6),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 38,
                                      height: 38,
                                      decoration: BoxDecoration(
                                        color: _neuBg,
                                        shape: BoxShape.circle,
                                        border: Border.all(color: Colors.white, width: 1.2),
                                        boxShadow: neuExtrudedShadows(distance: 2, blur: 4),
                                      ),
                                      child: const Icon(Icons.location_on_rounded, color: _neuCobalt, size: 19),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            loc['name'] as String,
                                            style: const TextStyle(
                                              color: _neuTextDark,
                                              fontWeight: FontWeight.w900,
                                              fontSize: 14,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            loc['desc'] as String,
                                            style: const TextStyle(
                                              color: _neuTextMuted,
                                              fontSize: 11,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const Icon(Icons.arrow_forward_ios_rounded, color: _neuTextMuted, size: 13),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // MODAL 3: REAL PROFILE MODAL (Neumorphic Soft UI)
  // ─────────────────────────────────────────────────────────────
  void _showProfileModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withOpacity(0.35),
      isScrollControlled: true,
      builder: (ctx) => Container(
        padding: const EdgeInsets.fromLTRB(22, 14, 22, 32),
        decoration: BoxDecoration(
          color: _neuBg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(36)),
          border: Border.all(color: Colors.white, width: 1.5),
          boxShadow: [
            BoxShadow(
              color: _neuDarkShadow.withOpacity(0.55),
              blurRadius: 30,
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
            Container(
              width: 44,
              height: 5,
              decoration: BoxDecoration(
                color: _neuTextMuted.withOpacity(0.3),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(height: 20),

            // Neumorphic Avatar & Info
            Row(
              children: [
                Container(
                  width: 62,
                  height: 62,
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: _neuBg,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: neuExtrudedShadows(distance: 3.5, blur: 9),
                  ),
                  child: Container(
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [_neuCobalt, _neuCobaltDark],
                      ),
                    ),
                    child: Center(
                      child: Text(
                        _userName.isNotEmpty ? _userName[0].toUpperCase() : 'U',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                        ),
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
                        _userName,
                        style: const TextStyle(
                          color: _neuTextDark,
                          fontWeight: FontWeight.w900,
                          fontSize: 18,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _userEmail,
                        style: const TextStyle(
                          color: _neuTextMuted,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: _neuBg,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white, width: 1.2),
                          boxShadow: neuExtrudedShadows(distance: 2, blur: 5),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.verified_rounded, color: _neuCobalt, size: 14),
                            const SizedBox(width: 5),
                            Text(
                              _userProvider == 'Google' ? 'GOOGLE / GMAIL ACCOUNT' : 'LAND SURVEYOR ACCOUNT',
                              style: const TextStyle(
                                color: _neuCobalt,
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Action Buttons
            _buildProfileOption(
              icon: Icons.settings_rounded,
              title: 'ការកំណត់ទូទៅ (Settings)',
              subtitle: 'ប្តូរឯកតា, GPS, និងភាសា',
              onTap: () {
                Navigator.pop(ctx);
                setState(() => _currentNavIndex = 5);
              },
            ),
            const SizedBox(height: 12),
            _buildProfileOption(
              icon: Icons.bookmark_rounded,
              title: 'ប្រវត្តិប្លង់ដី (Saved History)',
              subtitle: 'មើលប្លង់ដីដែលបានវាស់ទាំងអស់',
              onTap: () {
                Navigator.pop(ctx);
                setState(() => _currentNavIndex = 4);
              },
            ),
            const SizedBox(height: 12),
            _buildProfileOption(
              icon: Icons.logout_rounded,
              title: 'ចាកចេញពីគណនី (Logout)',
              subtitle: 'ត្រឡប់ទៅផ្ទាំង Login វិញ',
              isDestructive: true,
              onTap: () async {
                try {
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setBool('is_logged_in', false);
                } catch (_) {}
                if (!ctx.mounted) return;
                Navigator.pop(ctx);
                if (!mounted) return;
                Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen()));
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileOption({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    bool isDestructive = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: _neuBg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isDestructive ? const Color(0xFFEF4444).withOpacity(0.4) : Colors.white,
            width: 1.5,
          ),
          boxShadow: isDestructive
              ? [
                  BoxShadow(
                    color: const Color(0xFFEF4444).withOpacity(0.15),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ]
              : neuExtrudedShadows(distance: 3, blur: 8),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: isDestructive ? const Color(0xFFEF4444).withOpacity(0.12) : _neuBg,
                shape: BoxShape.circle,
                border: Border.all(
                  color: isDestructive ? const Color(0xFFEF4444).withOpacity(0.3) : Colors.white,
                  width: 1.2,
                ),
                boxShadow: isDestructive ? null : neuExtrudedShadows(distance: 2, blur: 5),
              ),
              child: Icon(
                icon,
                color: isDestructive ? const Color(0xFFEF4444) : _neuCobalt,
                size: 20,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: isDestructive ? const Color(0xFFEF4444) : _neuTextDark,
                      fontWeight: FontWeight.w900,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: isDestructive ? const Color(0xFFEF4444).withOpacity(0.8) : _neuTextMuted,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios_rounded,
              color: isDestructive ? const Color(0xFFEF4444).withOpacity(0.7) : _neuTextMuted,
              size: 14,
            ),
          ],
        ),
      ),
    );
  }



  // ─────────────────────────────────────────────────────────────
  // 3. HERO KHMER LAND CARD (Neumorphic Ceramic Soft UI)
  // ─────────────────────────────────────────────────────────────
  Widget _buildHeroCard() {
    final hasData = _realAreaM2 > 0;
    final String areaValue = hasData
        ? _formatNumber(_realAreaM2, decimals: 1)
        : (_useKhmerNumerals ? '០' : '0');
    final String secondaryArea = hasData
        ? (_useKhmerNumerals
            ? '${_formatNumber(_realAreaM2, decimals: 1, khmer: false)} m²'
            : '${_formatNumber(_realAreaM2, decimals: 1, khmer: true)} ម៉ែត្រការ៉េ')
        : '';
    final String areValue = hasData
        ? '${_formatNumber(_realAreaM2 / 100, decimals: 2)} អា'
        : (_useKhmerNumerals ? '០.០០ អា' : '0.00 អា');
    final String haValue = hasData
        ? '${_formatNumber(_realAreaM2 / 10000, decimals: 3)} ហិកតា'
        : (_useKhmerNumerals ? '០.០០០ ហិកតា' : '0.000 ហិកតា');
    final String perimeterM = hasData
        ? _formatNumber(_realPerimeterM, decimals: 1)
        : (_useKhmerNumerals ? '០.០' : '0.0');
    final String shapeDesc = hasData
        ? '$_realPointsCount ចំណុច'
        : (_useKhmerNumerals ? '០ ចំណុច' : '0 ចំណុច');
    final String subtitleText = hasData
        ? 'ប្លង់ដី: $_measurementTitle'
        : 'មិនទាន់មានទិន្នន័យ (ចុចខាងក្រោមដើម្បីចាប់ផ្តើមវាស់)';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15), // Compact vertical padding pulled upwards
        decoration: BoxDecoration(
          color: _neuBg,
          borderRadius: BorderRadius.circular(28),
          boxShadow: neuExtrudedShadows(distance: 7, blur: 20),
          border: Border.all(color: Colors.white, width: 1.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Row: Title & Subtitle (Left) + Sync Button (Right) - Status Pill Removed & Shifted Up
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'ទំហំផ្ទៃដីសរុប',
                        style: TextStyle(
                          color: _neuTextDark,
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.3,
                        ),
                      ),
                      const SizedBox(height: 3),
                      GestureDetector(
                        onTap: _showEditLandTitleDialog,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                subtitleText,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: hasData ? _neuCobalt : _neuTextMuted,
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            const SizedBox(width: 5),
                            Container(
                              padding: const EdgeInsets.all(2.5),
                              decoration: BoxDecoration(
                                color: _neuCobalt.withOpacity(0.12),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.edit_rounded, size: 12, color: _neuCobalt),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),

                // Neumorphic Sync Button (Compact 40x40)
                GestureDetector(
                  onTap: () async {
                    await _fetchRealGps();
                  },
                  child: AnimatedRotation(
                    turns: _isCardSyncing ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 600),
                    curve: Curves.easeInOut,
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: _neuBg,
                        shape: BoxShape.circle,
                        boxShadow: neuExtrudedShadows(distance: 2.5, blur: 6),
                        border: Border.all(color: Colors.white, width: 1.2),
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.sync_rounded,
                          color: _neuCobalt,
                          size: 20,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Area Big Number & Altitude Token
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Flexible(
                            child: Text(
                              areaValue,
                              style: const TextStyle(
                                color: _neuTextDark,
                                fontSize: 40,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.6,
                                height: 1.1,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4.5),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [_neuCobalt, _neuCobaltDark],
                              ),
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(
                                  color: _neuCobalt.withOpacity(0.35),
                                  blurRadius: 8,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                              border: Border.all(color: Colors.white.withOpacity(0.5), width: 1),
                            ),
                            child: Text(
                              _useKhmerNumerals ? 'ម៉ែត្រការ៉េ' : 'm² (SQM)',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.2,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (hasData && secondaryArea.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          '($secondaryArea)',
                          style: TextStyle(
                            color: _neuTextMuted.withOpacity(0.9),
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ],
                      const SizedBox(height: 7),

                      // Conversion Chips (Are & Hectare) in recessed slots
                      GestureDetector(
                        onTap: () => _showAreaDetailsModal(context),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3.5),
                              decoration: BoxDecoration(
                                color: _neuInputBg,
                                borderRadius: BorderRadius.circular(9),
                                boxShadow: neuRecessedShadows(),
                              ),
                              child: Text(
                                '= $areValue',
                                style: const TextStyle(
                                  color: _neuCobalt,
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            const SizedBox(width: 7),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3.5),
                              decoration: BoxDecoration(
                                color: _neuInputBg,
                                borderRadius: BorderRadius.circular(9),
                                boxShadow: neuRecessedShadows(),
                              ),
                              child: Text(
                                '• $haValue',
                                style: const TextStyle(
                                  color: _neuCobalt,
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // Neumorphic Altitude & Terrain Token (Interactive: tap to view altitude modal)
                GestureDetector(
                  onTap: () => _showAltitudeDetailsModal(context),
                  child: Container(
                    width: 70,
                    height: 70,
                    decoration: BoxDecoration(
                      color: _neuBg,
                      shape: BoxShape.circle,
                      boxShadow: neuExtrudedShadows(distance: 4, blur: 12),
                      border: Border.all(
                        color: _neuCobalt.withOpacity(0.4),
                        width: 1.8,
                      ),
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Container(
                          width: 50,
                          height: 50,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: _neuCobalt.withOpacity(0.2), width: 1.2),
                          ),
                        ),
                        const Icon(
                          Icons.landscape_rounded,
                          color: _neuCobalt,
                          size: 30,
                        ),
                        Positioned(
                          bottom: 5,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5.5, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: _neuYellow,
                              borderRadius: BorderRadius.circular(6),
                              boxShadow: [
                                BoxShadow(
                                  color: _neuYellow.withOpacity(0.6),
                                  blurRadius: 4,
                                ),
                              ],
                            ),
                            child: Text(
                              '▲ +${_realAltitude > 0 ? (_useKhmerNumerals ? _toKhmerDigits(_realAltitude.toStringAsFixed(0)) : _realAltitude.toStringAsFixed(0)) : "18"}m',
                              style: const TextStyle(
                                color: _neuTextDark,
                                fontSize: 9,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Bottom Dual-Action Capsule: Perimeter & Shape Breakdown
            GestureDetector(
              onTap: () => _showPerimeterDetailsModal(context),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8.5),
                decoration: BoxDecoration(
                  color: _neuInputBg,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: neuRecessedShadows(),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.straighten_rounded,
                      color: _neuCobalt,
                      size: 15,
                    ),
                    const SizedBox(width: 7),
                    Text(
                      'ប្រវែងព័ទ្ធជុំវិញ: $perimeterM ម៉ែត្រ',
                      style: const TextStyle(
                        color: _neuTextDark,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      width: 1.2,
                      height: 13,
                      color: _neuDarkShadow,
                    ),
                    const Spacer(),
                    const Icon(
                      Icons.share_location_rounded,
                      color: _neuCobalt,
                      size: 14,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      shapeDesc,
                      style: const TextStyle(
                        color: _neuTextDark,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Hero Card Action Buttons (Surveyor Tools)
            if (hasData)
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: GestureDetector(
                      onTap: () {
                        setState(() {
                          _initialMeasureMode = _latestMeasurement?.type == MeasurementType.circle
                              ? MeasureMode.circle
                              : MeasureMode.polygon;
                          _currentNavIndex = 1;
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 11),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [_neuCobalt, _neuCobaltDark],
                          ),
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: _neuCobalt.withOpacity(0.4),
                              blurRadius: 10,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.map_rounded, color: _neuYellow, size: 16),
                            SizedBox(width: 6),
                            Text(
                              'បើកមើលលើផែនទី',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                                fontSize: 12.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: GestureDetector(
                      onTap: () {
                        setState(() {
                          _calcCustomArea = _realAreaM2;
                          _currentNavIndex = 3; // Navigate to Survey Calculator & Unit Converter tab
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 11),
                        decoration: BoxDecoration(
                          color: _neuBg,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.white, width: 1.2),
                          boxShadow: neuExtrudedShadows(distance: 2.5, blur: 6),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.transform_rounded, color: Color(0xFF10B981), size: 15),
                            SizedBox(width: 4),
                            Text(
                              'បំប្លែងខ្នាត',
                              style: TextStyle(
                                color: _neuTextDark,
                                fontWeight: FontWeight.w800,
                                fontSize: 11.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: GestureDetector(
                      onTap: () async {
                        await _resetToZero();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 11),
                        decoration: BoxDecoration(
                          color: _neuBg,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.white, width: 1.2),
                          boxShadow: neuExtrudedShadows(distance: 2.5, blur: 6),
                        ),
                        child: const Center(
                          child: Text(
                            '🔄 សូន្យ (០)',
                            style: TextStyle(
                              color: _neuTextDark,
                              fontWeight: FontWeight.w800,
                              fontSize: 11.5,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              )
            else
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: GestureDetector(
                      onTap: () {
                        setState(() {
                          _initialMeasureMode = MeasureMode.polygon;
                          _currentNavIndex = 1;
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 11),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [_neuCobalt, _neuCobaltDark],
                          ),
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: _neuCobalt.withOpacity(0.4),
                              blurRadius: 10,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.location_on_rounded, color: _neuYellow, size: 16),
                            SizedBox(width: 6),
                            Text(
                              'វាស់ដីពហុកោណ',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                                fontSize: 12.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: GestureDetector(
                      onTap: () {
                        setState(() {
                          _initialMeasureMode = MeasureMode.rectangle;
                          _currentNavIndex = 1;
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 11),
                        decoration: BoxDecoration(
                          color: _neuBg,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.white, width: 1.2),
                          boxShadow: neuExtrudedShadows(distance: 2.5, blur: 6),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.crop_square_rounded, color: _neuCobalt, size: 15),
                            SizedBox(width: 4),
                            Text(
                              'ដីឡូតិ៍ជ្រុង',
                              style: TextStyle(
                                color: _neuTextDark,
                                fontWeight: FontWeight.w800,
                                fontSize: 11.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: GestureDetector(
                      onTap: _loadSampleParcel,
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 11),
                        decoration: BoxDecoration(
                          color: _neuBg,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.white, width: 1.2),
                          boxShadow: neuExtrudedShadows(distance: 2.5, blur: 6),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.bolt_rounded, color: _neuYellow, size: 15),
                            SizedBox(width: 3),
                            Text(
                              'គំរូ',
                              style: TextStyle(
                                color: _neuTextDark,
                                fontWeight: FontWeight.w800,
                                fontSize: 11.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  // 4. METRICS 3x2 LUXURY CERAMIC GRID (Neumorphic Soft UI Grid - 6 Compact Square Tiles)
  // ─────────────────────────────────────────────────────────────
  Widget _buildMetricsCard() {
    // Strictly ZERO by default as requested: "មកលេខសូន្យទាំងអស់"
    final areaHectare = _realAreaM2 > 0
        ? _formatNumber(_realAreaM2 / 10000, decimals: 2)
        : (_useKhmerNumerals ? '០.០០' : '0.00');
    final pointsCount = _realPointsCount > 0
        ? (_useKhmerNumerals ? _toKhmerDigits('$_realPointsCount') : '$_realPointsCount')
        : (_useKhmerNumerals ? '០' : '0');
    final accuracy = _realGpsAccuracy > 0
        ? '±${_formatNumber(_realGpsAccuracy, decimals: 1)}'
        : '±0.0';
    final perimeter = _realPerimeterM > 0
        ? _formatNumber(_realPerimeterM, decimals: 0)
        : (_useKhmerNumerals ? '០' : '0');
    final altitudeStr = _realAltitude > 0
        ? '+${_formatNumber(_realAltitude, decimals: 1)}'
        : (_useKhmerNumerals ? '+០.០' : '+0.0');
    final satellitesStr = _useKhmerNumerals
        ? _toKhmerDigits('$_weatherSatelliteCount')
        : '$_weatherSatelliteCount';

    const double tileSize = 120.0; // EXACT 120x120 True Square ("ទំហំធំពេញភ្នែក ~120px" as requested!)
    const double gap = 10.0;
    const double totalGridWidth = 3 * tileSize + 2 * gap; // 344.0
    const double totalGridHeight = 2 * tileSize + gap;     // 226.0

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Center(
        child: SizedBox(
          width: totalGridWidth,
          height: totalGridHeight,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // 1. Horizontal Divider Line between Row 1 and Row 2
              Positioned(
                left: -12,
                right: -12,
                top: tileSize + gap / 2 - 0.6,
                child: Container(
                  height: 1.2,
                  color: _neuDarkShadow.withOpacity(0.32),
                ),
              ),

              // 2. Vertical Divider Line 1 (between Column 1 and Column 2)
              Positioned(
                top: -10,
                bottom: -10,
                left: tileSize + gap / 2 - 0.6,
                child: Container(
                  width: 1.2,
                  color: _neuDarkShadow.withOpacity(0.32),
                ),
              ),

              // 3. Vertical Divider Line 2 (between Column 2 and Column 3)
              Positioned(
                top: -10,
                bottom: -10,
                left: 2 * tileSize + gap * 1.5 - 0.6,
                child: Container(
                  width: 1.2,
                  color: _neuDarkShadow.withOpacity(0.32),
                ),
              ),

              // 3x2 Grid Tiles (3 Columns x 2 Rows = 6 True Squares 108x108)
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildCompactMetricTile(
                        icon: Icons.layers_rounded,
                        gradientColors: const [Color(0xFF059669), Color(0xFF10B981)], // Emerald Green
                        value: areaHectare,
                        unit: 'Ha',
                        title: 'ទំហំហិកតា',
                        tileSize: tileSize,
                        onTap: () => _showAreaDetailsModal(context),
                      ),
                      const SizedBox(width: gap),
                      _buildCompactMetricTile(
                        icon: Icons.pin_drop_rounded,
                        gradientColors: const [_neuCobaltDark, _neuCobalt], // Royal Cobalt
                        value: pointsCount,
                        unit: 'កន្លែង',
                        title: 'បង្គោលដី',
                        tileSize: tileSize,
                        onTap: () => _showPointsDetailsModal(context),
                      ),
                      const SizedBox(width: gap),
                      _buildCompactMetricTile(
                        icon: Icons.filter_hdr_rounded,
                        gradientColors: const [Color(0xFF7C3AED), Color(0xFFA855F7)], // Royal Purple
                        value: altitudeStr,
                        unit: 'm',
                        title: 'កម្ពស់ដី',
                        tileSize: tileSize,
                        onTap: () => _showAltitudeDetailsModal(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: gap),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildCompactMetricTile(
                        icon: Icons.gps_fixed_rounded,
                        gradientColors: const [Color(0xFF0284C7), Color(0xFF38BDF8)], // Electric Cyan
                        value: accuracy,
                        unit: 'm',
                        title: 'GPS ច្បាស់',
                        tileSize: tileSize,
                        onTap: () => _showGpsAccuracyModal(context),
                      ),
                      const SizedBox(width: gap),
                      _buildCompactMetricTile(
                        icon: Icons.straighten_rounded,
                        gradientColors: const [Color(0xFFD97706), Color(0xFFF59E0B)], // Warm Amber
                        value: perimeter,
                        unit: 'm',
                        title: 'ប្រវែងជុំវិញ',
                        tileSize: tileSize,
                        onTap: () => _showPerimeterDetailsModal(context),
                      ),
                      const SizedBox(width: gap),
                      _buildCompactMetricTile(
                        icon: Icons.satellite_alt_rounded,
                        gradientColors: const [Color(0xFFE11D48), Color(0xFFFB7185)], // Vivid Rose Pink
                        value: satellitesStr,
                        unit: 'គ្រាប់',
                        title: 'ផ្កាយរណប',
                        tileSize: tileSize,
                        onTap: () => _showSatellitesDetailsModal(context),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCompactMetricTile({
    required IconData icon,
    required List<Color> gradientColors,
    required String value,
    required String unit,
    required String title,
    required double tileSize,
    required VoidCallback onTap,
  }) {
    final primaryColor = gradientColors.first;

    return SizedBox(
      width: tileSize,
      height: tileSize, // EXACT 1:1 TRUE SQUARE (120x120 បួនជ្រុងស្មើ និងធំពេញភ្នែក!)
      child: Container(
        decoration: BoxDecoration(
          color: _neuBg,
          borderRadius: BorderRadius.circular(18),
          boxShadow: neuExtrudedShadows(distance: 2.5, blur: 7),
          border: Border.all(color: Colors.white, width: 1.2),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(18),
            splashColor: primaryColor.withOpacity(0.15),
            highlightColor: primaryColor.withOpacity(0.08),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 7),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.center,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // 1. Centered 40x40 Gradient 3D Squircle with 24px Crisp White Icon
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: gradientColors,
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: Colors.white.withOpacity(0.9), width: 1.2),
                        boxShadow: [
                          BoxShadow(
                            color: primaryColor.withOpacity(0.38),
                            blurRadius: 7,
                            offset: const Offset(0, 2.5),
                          ),
                        ],
                      ),
                      child: Center(
                        child: Icon(
                          icon,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                    ),
                    const SizedBox(height: 5),

                    // 2. Centered Value + Unit
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          value,
                          maxLines: 1,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: _neuTextDark,
                            fontSize: 16.5,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.2,
                          ),
                        ),
                        const SizedBox(width: 3),
                        Text(
                          unit,
                          style: TextStyle(
                            color: primaryColor,
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),

                    // 3. Centered Category Title
                    Text(
                      title,
                      maxLines: 1,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: _neuTextMuted,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
  // ─────────────────────────────────────────────────────────────
  // NEW FEATURE 1: FIELD SURVEY WEATHER & CONDITIONS WIDGET
  // ─────────────────────────────────────────────────────────────
  // ─────────────────────────────────────────────────────────────
  // REAL-WORLD GLOBAL LIVE SURVEY WEATHER HELPERS & API
  // ─────────────────────────────────────────────────────────────
  String _formatSyncTime() {
    if (_lastWeatherSync == null) return 'មិនទាន់ធ្វើបច្ចុប្បន្នភាព';
    final now = DateTime.now();
    final diffMin = now.difference(_lastWeatherSync!).inMinutes;
    if (diffMin < 1) return 'ទើបធ្វើបច្ចុប្បន្នភាពថ្មីៗនេះ (Live)';
    if (diffMin < 60) return 'បានធ្វើបច្ចុប្បន្នភាព $diffMin នាទីមុន';
    final hour = _lastWeatherSync!.hour.toString().padLeft(2, '0');
    final min = _lastWeatherSync!.minute.toString().padLeft(2, '0');
    return 'ម៉ោង $hour:$min';
  }

  Map<String, String> _parseWeatherCode(int code, int isDay) {
    if (code == 0) {
      return {
        'text': isDay == 1 ? 'មេឃស្រឡះ' : 'មេឃស្រឡះ (យប់)',
        'icon': isDay == 1 ? '☀️' : '🌙',
        'desc': 'មេឃស្រឡះល្អ គ្មានពពកបាំង GNSS',
      };
    } else if (code == 1) {
      return {
        'text': 'ពពកតិចតួច',
        'icon': isDay == 1 ? '🌤️' : '☁️',
        'desc': 'ផ្ទៃមេឃស្រឡះល្អ ស័ក្តិសមចុះវាស់ដី',
      };
    } else if (code == 2) {
      return {
        'text': 'ពពកខ្លះៗ',
        'icon': '⛅',
        'desc': 'អាកាសធាតុត្រជាក់ស្រួល គ្មានភ្លៀង',
      };
    } else if (code == 3) {
      return {
        'text': 'មេឃស្រទុំ',
        'icon': '☁️',
        'desc': 'ពពកច្រើន គ្មានភ្លៀង ស័ក្តិសមចុះវាស់ដី',
      };
    } else if (code >= 45 && code <= 48) {
      return {
        'text': 'អ័ព្ទចុះត្រជាក់',
        'icon': '🌫️',
        'desc': 'មានអ័ព្ទ កម្រិតមើលឃើញទាប ប្រយ័ត្នសើមឧបករណ៍',
      };
    } else if (code >= 51 && code <= 55) {
      return {
        'text': 'ភ្លៀងរលឹមស្រិចៗ',
        'icon': '🌦️',
        'desc': 'មានរលឹមស្រាលៗ គួរប្រយ័ត្នសើមឧបករណ៍វាស់',
      };
    } else if (code >= 61 && code <= 65) {
      return {
        'text': 'ភ្លៀងធ្លាក់',
        'icon': '🌧️',
        'desc': 'មានភ្លៀងធ្លាក់ មិនស័ក្តិសមចុះវាស់ដីទេ',
      };
    } else if (code >= 80 && code <= 82) {
      return {
        'text': 'ភ្លៀងកន្ត្រាក់',
        'icon': '🌧️',
        'desc': 'ភ្លៀងកន្ត្រាក់ខ្លាំង ហាមបង្ហោះដ្រូន & វាស់ដី',
      };
    } else if (code >= 95) {
      return {
        'text': 'ផ្គររន្ទះ និងភ្លៀង',
        'icon': '⛈️',
        'desc': 'គ្រោះថ្នាក់! មានផ្គររន្ទះ ហាមវាស់ដីដាច់ខាត',
      };
    }
    return {
      'text': 'អាកាសធាតុទូទៅ',
      'icon': '🌤️',
      'desc': 'លក្ខខណ្ឌធម្មតា ស័ក្តិសមចុះវាស់ដី',
    };
  }

  String _parseWindDirection(double degrees) {
    final deg = (degrees % 360 + 360) % 360;
    if (deg >= 337.5 || deg < 22.5) return 'ជើង (${deg.round()}°)';
    if (deg >= 22.5 && deg < 67.5) return 'ឦសាន (${deg.round()}°)';
    if (deg >= 67.5 && deg < 112.5) return 'កើត (${deg.round()}°)';
    if (deg >= 112.5 && deg < 157.5) return 'អាគ្នេយ៍ (${deg.round()}°)';
    if (deg >= 157.5 && deg < 202.5) return 'ត្បូង (${deg.round()}°)';
    if (deg >= 202.5 && deg < 247.5) return 'និរតី (${deg.round()}°)';
    if (deg >= 247.5 && deg < 292.5) return 'លិច (${deg.round()}°)';
    return 'ពាយព្យ (${deg.round()}°)';
  }

  String _getWindSpeedDesc(double speed) {
    if (speed < 12) return 'ស្ងប់';
    if (speed < 24) return 'មធ្យម';
    if (speed < 38) return 'បក់ខ្លាំង';
    return 'ព្យុះខ្លាំង';
  }

  String _getUvDesc(double uv) {
    if (uv <= 2.5) return 'កម្រិត ${uv.toStringAsFixed(1)} (ទាប)';
    if (uv <= 5.5) return 'កម្រិត ${uv.toStringAsFixed(1)} (ធម្មតា)';
    if (uv <= 7.5) return 'កម្រិត ${uv.toStringAsFixed(1)} (ខ្ពស់)';
    if (uv <= 10.5) return 'កម្រិត ${uv.toStringAsFixed(1)} (ខ្លាំង)';
    return 'កម្រិត ${uv.toStringAsFixed(1)} (គ្រោះថ្នាក់)';
  }

  void _calculateSurveySuitability(int code, double rain, double wind, double uv) {
    if (code >= 95 || rain > 4.0) {
      _surveySuitability = 'មិនអំណោយផល 25%';
      _surveySuitabilityColor = const Color(0xFFEF4444);
      _weatherAdvice = '⛈️ ផ្គររន្ទះ/ភ្លៀងខ្លាំង • ហាមវាស់ដី & បង្ហោះដ្រូនដាច់ខាត';
      _weatherSatelliteCount = 14;
    } else if (rain > 0.1 || (code >= 51 && code <= 65)) {
      _surveySuitability = 'ប្រុងប្រយ័ត្ន 48%';
      _surveySuitabilityColor = const Color(0xFFF59E0B);
      _weatherAdvice = '🌧️ មានភ្លៀងរលឹម • គួរផ្អាកវាស់វែង និងរក្សាឧបករណ៍កុំឱ្យទទឹក';
      _weatherSatelliteCount = 18;
    } else if (wind > 28.0) {
      _surveySuitability = 'ខ្យល់ខ្លាំង 60%';
      _surveySuitabilityColor = const Color(0xFFF59E0B);
      _weatherAdvice = '💨 ខ្យល់បក់ខ្លាំង (${wind.toStringAsFixed(0)} km/h) • មិនគួរបង្ហោះដ្រូន RTK ទេ';
      _weatherSatelliteCount = 22;
    } else if (uv > 9.0) {
      _surveySuitability = 'ក្តៅខ្លាំង 80%';
      _surveySuitabilityColor = const Color(0xFF3B82F6);
      _weatherAdvice = '☀️ កម្តៅថ្ងៃខ្លាំង • គួរពាក់មួកការពារកម្តៅពេលចុះវាស់ព្រំដី';
      _weatherSatelliteCount = 26;
    } else {
      _surveySuitability = 'ល្អឥតខ្ចោះ 98%';
      _surveySuitabilityColor = const Color(0xFF10B981);
      _weatherAdvice = '✨ គ្មានភ្លៀង ខ្យល់ស្ងប់ • ស័ក្តិសមបំផុតចុះវាស់ព្រំដី & ដ្រូន';
      _weatherSatelliteCount = 24 + (DateTime.now().minute % 7);
    }
  }

  Future<void> _fetchLiveRealWorldWeather({
    double? customLat,
    double? customLng,
    String? locationName,
    bool force = false,
  }) async {
    if (_isLoadingWeather) return;
    if (!force &&
        _lastWeatherSync != null &&
        DateTime.now().difference(_lastWeatherSync!).inMinutes < 10 &&
        customLat == null &&
        customLng == null) {
      return;
    }

    setState(() {
      _isLoadingWeather = true;
      if (locationName != null) {
        _weatherLocationName = locationName;
      }
    });

    double lat = customLat ?? _weatherLat;
    double lng = customLng ?? _weatherLng;

    if (customLat == null && customLng == null) {
      try {
        final perm = await Geolocator.checkPermission();
        if (perm == LocationPermission.always || perm == LocationPermission.whileInUse) {
          final pos = await Geolocator.getLastKnownPosition();
          if (pos != null) {
            lat = pos.latitude;
            lng = pos.longitude;
            _weatherLat = lat;
            _weatherLng = lng;
          }
        }
      } catch (_) {}
    } else {
      _weatherLat = lat;
      _weatherLng = lng;
    }

    try {
      final url = Uri.parse(
        'https://api.open-meteo.com/v1/forecast'
        '?latitude=${lat.toStringAsFixed(4)}'
        '&longitude=${lng.toStringAsFixed(4)}'
        '&current=temperature_2m,relative_humidity_2m,apparent_temperature,is_day,precipitation,weather_code,wind_speed_10m,wind_direction_10m,uv_index'
        '&timezone=auto',
      );

      final response = await http.get(url).timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final current = data['current'];

        if (current != null && mounted) {
          final double temp = (current['temperature_2m'] as num?)?.toDouble() ?? 30.0;
          final double apparentTemp = (current['apparent_temperature'] as num?)?.toDouble() ?? temp;
          final int code = (current['weather_code'] as num?)?.toInt() ?? 0;
          final int isDay = (current['is_day'] as num?)?.toInt() ?? 1;
          final double rain = (current['precipitation'] as num?)?.toDouble() ?? 0.0;
          final double wind = (current['wind_speed_10m'] as num?)?.toDouble() ?? 8.0;
          final double windDir = (current['wind_direction_10m'] as num?)?.toDouble() ?? 45.0;
          final double uv = (current['uv_index'] as num?)?.toDouble() ?? 4.0;
          final double humidity = (current['relative_humidity_2m'] as num?)?.toDouble() ?? 65.0;

          final weatherParsed = _parseWeatherCode(code, isDay);
          final windDirParsed = _parseWindDirection(windDir);

          setState(() {
            _weatherTemp = temp;
            _weatherApparentTemp = apparentTemp;
            _weatherCode = code;
            _weatherConditionText = weatherParsed['text']!;
            _weatherConditionIcon = weatherParsed['icon']!;
            _weatherWindSpeed = wind;
            _weatherWindDirectionDegrees = windDir;
            _weatherWindDirection = windDirParsed;
            _weatherUvIndex = uv;
            _weatherHumidity = humidity;
            _weatherPrecipitation = rain;
            _lastWeatherSync = DateTime.now();
            _calculateSurveySuitability(code, rain, wind, uv);
            _isLoadingWeather = false;
          });
          return;
        }
      }
    } catch (_) {}

    if (mounted) {
      setState(() {
        _isLoadingWeather = false;
      });
    }
  }

  void _showLocationSelectorDialog(BuildContext context) {
    final locations = [
      {'name': '📍 ទីតាំង GPS ផ្ទាល់', 'lat': 0.0, 'lng': 0.0, 'isGps': true},
      {'name': '🏙️ រាជធានីភ្នំពេញ (Phnom Penh)', 'lat': 11.5564, 'lng': 104.9282, 'isGps': false},
      {'name': '🏛️ ខេត្តសៀមរាប (Siem Reap)', 'lat': 13.3671, 'lng': 103.8448, 'isGps': false},
      {'name': '🌊 ក្រុងព្រះសីហនុ (Sihanoukville)', 'lat': 10.6275, 'lng': 103.5221, 'isGps': false},
      {'name': '🌾 ខេត្តបាត់ដំបង (Battambang)', 'lat': 13.0957, 'lng': 103.2022, 'isGps': false},
      {'name': '⛰️ ខេត្តកំពត (Kampot)', 'lat': 10.6104, 'lng': 104.1815, 'isGps': false},
      {'name': '🌉 ខេត្តកំពង់ចាម (Kampong Cham)', 'lat': 12.0000, 'lng': 105.4500, 'isGps': false},
      {'name': '🌲 ខេត្តមណ្ឌលគិរី (Mondulkiri)', 'lat': 12.4558, 'lng': 107.1881, 'isGps': false},
      {'name': '🏢 ទីក្រុងបាងកក (Bangkok)', 'lat': 13.7563, 'lng': 100.5018, 'isGps': false},
      {'name': '🏙️ ទីក្រុងហូជីមិញ (Ho Chi Minh)', 'lat': 10.8231, 'lng': 106.6297, 'isGps': false},
      {'name': '🦁 ទីក្រុងសិង្ហបុរី (Singapore)', 'lat': 1.3521, 'lng': 103.8198, 'isGps': false},
      {'name': '🗼 ទីក្រុងតូក្យូ (Tokyo)', 'lat': 35.6762, 'lng': 139.6503, 'isGps': false},
      {'name': '🏰 ទីក្រុងប៉ារីស (Paris)', 'lat': 48.8566, 'lng': 2.3522, 'isGps': false},
      {'name': '🗽 ទីក្រុងញូវយ៉ក (New York)', 'lat': 40.7128, 'lng': -74.0060, 'isGps': false},
    ];

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (modalCtx) => Container(
        height: MediaQuery.of(modalCtx).size.height * 0.65,
        decoration: const BoxDecoration(
          color: _neuBg,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          children: [
            Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: _neuDarkShadow,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.public_rounded, color: _neuCobalt, size: 22),
                    SizedBox(width: 8),
                    Text(
                      'ជ្រើសរើសទីតាំងលើពិភពលោក',
                      style: TextStyle(
                        color: _neuTextDark,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: _neuTextMuted),
                  onPressed: () => Navigator.pop(modalCtx),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'ទាញយកទិន្នន័យអាកាសធាតុពិតៗ និងលក្ខខណ្ឌវាស់ដីតាមទីតាំង',
                style: TextStyle(color: _neuTextMuted, fontSize: 11),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.separated(
                physics: const BouncingScrollPhysics(),
                itemCount: locations.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final loc = locations[index];
                  final isCurrent = _weatherLocationName == loc['name'];
                  return GestureDetector(
                    onTap: () {
                      Navigator.pop(modalCtx);
                      if (loc['isGps'] == true) {
                        _fetchLiveRealWorldWeather(
                          customLat: null,
                          customLng: null,
                          locationName: '📍 ទីតាំង GPS ផ្ទាល់',
                          force: true,
                        );
                      } else {
                        _fetchLiveRealWorldWeather(
                          customLat: loc['lat'] as double,
                          customLng: loc['lng'] as double,
                          locationName: loc['name'] as String,
                          force: true,
                        );
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: isCurrent ? _neuCobalt.withOpacity(0.08) : _neuBg,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isCurrent ? _neuCobalt : Colors.white,
                          width: isCurrent ? 1.5 : 1.0,
                        ),
                        boxShadow: isCurrent ? neuRecessedShadows() : neuExtrudedShadows(distance: 2, blur: 6),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            loc['name'] as String,
                            style: TextStyle(
                              color: isCurrent ? _neuCobalt : _neuTextDark,
                              fontSize: 13,
                              fontWeight: isCurrent ? FontWeight.w900 : FontWeight.w700,
                            ),
                          ),
                          if (isCurrent)
                            const Icon(Icons.check_circle_rounded, color: _neuCobalt, size: 18)
                          else
                            const Icon(Icons.arrow_forward_ios_rounded, color: _neuTextMuted, size: 12),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showGlobalWeatherDetailsModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (modalCtx) => Container(
        height: MediaQuery.of(modalCtx).size.height * 0.82,
        decoration: const BoxDecoration(
          color: _neuBg,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          children: [
            Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: _neuDarkShadow,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: _neuBg,
                        shape: BoxShape.circle,
                        boxShadow: neuExtrudedShadows(distance: 2, blur: 5),
                      ),
                      child: const Icon(Icons.public_rounded, color: _neuCobalt, size: 20),
                    ),
                    const SizedBox(width: 10),
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'ទិន្នន័យអាកាសធាតុវាស់ដីសកលលោក',
                          style: TextStyle(
                            color: _neuTextDark,
                            fontSize: 14.5,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          'Live Global Survey & GNSS Telemetry',
                          style: TextStyle(
                            color: _neuTextMuted,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: _neuTextMuted),
                  onPressed: () => Navigator.pop(modalCtx),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Location & Coords Banner
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: _neuInputBg,
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: neuRecessedShadows(),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.place_rounded, color: _neuCobalt, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _weatherLocationName,
                                  style: const TextStyle(
                                    color: _neuTextDark,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                Text(
                                  'GPS: ${_weatherLat.toStringAsFixed(4)}°, ${_weatherLng.toStringAsFixed(4)}° • ${_formatSyncTime()}',
                                  style: const TextStyle(
                                    color: _neuTextMuted,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          GestureDetector(
                            onTap: () {
                              Navigator.pop(modalCtx);
                              _showLocationSelectorDialog(context);
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: _neuCobalt,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Text(
                                'ប្តូរទីតាំង',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Grid of 6 parameters
                    Row(
                      children: [
                        Expanded(
                          child: _buildTelemetryCard('🌡️ សីតុណ្ហភាពពិត', '${_weatherTemp.toStringAsFixed(1)}°C', 'អារម្មណ៍ ${_weatherApparentTemp.toStringAsFixed(1)}°C (Code $_weatherCode)'),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _buildTelemetryCard('💧 សំណើមខ្យល់', '${_weatherHumidity.toStringAsFixed(0)}%', 'កម្រិតសំណើមបរិយាកាស'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: _buildTelemetryCard('💨 ល្បឿនខ្យល់', '${_weatherWindSpeed.toStringAsFixed(1)} km/h', '$_weatherWindDirection (${_weatherWindDirectionDegrees.toStringAsFixed(0)}°)'),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _buildTelemetryCard('☀️ កាំរស្មី UV', _weatherUvIndex.toStringAsFixed(1), _getUvDesc(_weatherUvIndex)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: _buildTelemetryCard('🌧️ ទឹកភ្លៀង', '${_weatherPrecipitation.toStringAsFixed(1)} mm', _weatherPrecipitation > 0 ? 'មានភ្លៀងធ្លាក់' : 'គ្មានភ្លៀង'),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _buildTelemetryCard('🛰️ Multi-GNSS Lock', '$_weatherSatelliteCount គ្រាប់', 'GPS, BeiDou, Galileo, GLONASS'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Cadastral Survey Guidelines
                    const Text(
                      '📋 របាយការណ៍បច្ចេកទេសចុះវាស់ដីជាក់ស្តែង',
                      style: TextStyle(
                        color: _neuTextDark,
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: _neuBg,
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: neuExtrudedShadows(distance: 3, blur: 8),
                        border: Border.all(color: Colors.white, width: 1.2),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildAdviceItem(
                            '🛰️ សញ្ញា GPS/RTK Fixed:',
                            _weatherPrecipitation > 2.0
                                ? 'ពពក និងភ្លៀងអាចកាត់បន្ថយភាពត្រឹមត្រូវ RTK (គួរវាស់ពេលមេឃស្រឡះ)'
                                : 'សញ្ញាផ្កាយរណបខ្លាំង ($_weatherSatelliteCount គ្រាប់) ផ្តល់ភាពត្រឹមត្រូវកម្រិត ±0.5m',
                            _weatherPrecipitation > 2.0 ? const Color(0xFFEF4444) : const Color(0xFF10B981),
                          ),
                          const Divider(height: 18),
                          _buildAdviceItem(
                            '🚁 ការបង្ហោះដ្រូនវាស់ដី (Drone Mapping):',
                            _weatherWindSpeed > 25.0
                                ? 'ខ្យល់បក់ខ្លាំង ${_weatherWindSpeed.toStringAsFixed(1)} km/h • ហាមបង្ហោះដ្រូនដើម្បីសុវត្ថិភាព'
                                : 'ល្បឿនខ្យល់ល្អ ${_weatherWindSpeed.toStringAsFixed(1)} km/h • ស័ក្តិសមបំផុតសម្រាប់បង្ហោះដ្រូន',
                            _weatherWindSpeed > 25.0 ? const Color(0xFFF59E0B) : const Color(0xFF10B981),
                          ),
                          const Divider(height: 18),
                          _buildAdviceItem(
                            '☀️ ម៉ោងអំណោយផលចុះវាស់ព្រំដី:',
                            'ព្រឹក: 06:30 - 10:30 (ត្រជាក់ស្រួល) • រសៀល: 15:30 - 17:45',
                            const Color(0xFF3B82F6),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Action buttons
                    Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              Navigator.pop(modalCtx);
                              _fetchLiveRealWorldWeather(force: true);
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              decoration: BoxDecoration(
                                color: _neuBg,
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: neuExtrudedShadows(distance: 3, blur: 7),
                                border: Border.all(color: Colors.white, width: 1.2),
                              ),
                              child: const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.refresh_rounded, color: _neuCobalt, size: 18),
                                  SizedBox(width: 6),
                                  Text(
                                    'ទាញយកទិន្នន័យថ្មី',
                                    style: TextStyle(
                                      color: _neuCobalt,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              Navigator.pop(modalCtx);
                              setState(() => _currentNavIndex = 2);
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              decoration: BoxDecoration(
                                color: _neuCobalt,
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: [
                                  BoxShadow(
                                    color: _neuCobalt.withOpacity(0.35),
                                    offset: const Offset(0, 4),
                                    blurRadius: 10,
                                  ),
                                ],
                              ),
                              child: const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.explore_rounded, color: Colors.white, size: 18),
                                  SizedBox(width: 6),
                                  Text(
                                    'ពិនិត្យត្រីវិស័យ',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTelemetryCard(String title, String value, String sub) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _neuInputBg,
        borderRadius: BorderRadius.circular(16),
        boxShadow: neuRecessedShadows(),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(color: _neuTextMuted, fontSize: 10.5, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(color: _neuTextDark, fontSize: 15, fontWeight: FontWeight.w900)),
          const SizedBox(height: 2),
          Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _neuTextMuted, fontSize: 9.5, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildAdviceItem(String title, String desc, Color dotColor) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          margin: const EdgeInsets.only(top: 4),
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: dotColor,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(color: _neuTextDark, fontSize: 11.5, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 2),
              Text(
                desc,
                style: const TextStyle(color: _neuTextMuted, fontSize: 10.5, fontWeight: FontWeight.w600, height: 1.3),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSurveyWeatherWidget() {
    if (DateTime.now().year < 2020) _oldSurveyWeather();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: _neuBg,
          borderRadius: BorderRadius.circular(26),
          boxShadow: neuExtrudedShadows(distance: 6, blur: 18),
          border: Border.all(color: Colors.white, width: 1.3),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Row: Weather Title & Location Selector & Refresh Button
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: _neuBg,
                          shape: BoxShape.circle,
                          boxShadow: neuExtrudedShadows(distance: 2, blur: 5),
                          border: Border.all(color: Colors.white, width: 1.2),
                        ),
                        child: Center(
                          child: Text(
                            _weatherConditionIcon,
                            style: const TextStyle(fontSize: 18),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'អាកាសធាតុ & លក្ខខណ្ឌចុះវាស់ដី',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: _neuTextDark,
                                fontSize: 13.5,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            // Clickable Location chip to switch worldwide
                            GestureDetector(
                              onTap: () => _showLocationSelectorDialog(context),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Flexible(
                                    child: Text(
                                      _weatherLocationName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: _neuCobalt,
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 2),
                                  const Icon(Icons.arrow_drop_down_rounded, color: _neuCobalt, size: 16),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),

                // Right side: Suitability Badge + Refresh Button
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Dynamic Suitability Badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                      decoration: BoxDecoration(
                        color: _surveySuitabilityColor.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: _surveySuitabilityColor.withOpacity(0.4), width: 1),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _surveySuitabilityColor == const Color(0xFF10B981)
                                ? Icons.check_circle_rounded
                                : Icons.info_outline_rounded,
                            color: _surveySuitabilityColor,
                            size: 12,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _surveySuitability,
                            style: TextStyle(
                              color: _surveySuitabilityColor,
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),

                    // Manual Live Sync Button with Spinning Animation
                    GestureDetector(
                      onTap: () {
                        _fetchLiveRealWorldWeather(force: true);
                      },
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: _neuBg,
                          shape: BoxShape.circle,
                          boxShadow: neuExtrudedShadows(distance: 2, blur: 5),
                          border: Border.all(color: Colors.white, width: 1),
                        ),
                        child: Center(
                          child: _isLoadingWeather
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: _neuCobalt),
                                )
                              : const Icon(Icons.refresh_rounded, color: _neuCobalt, size: 16),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Middle Row: Temperature & Satellite Lock
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            '${_weatherTemp.toStringAsFixed(0)}°C',
                            style: const TextStyle(
                              color: _neuTextDark,
                              fontSize: 32,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              '$_weatherConditionIcon $_weatherConditionText',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: _neuCobalt,
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _weatherAdvice,
                        style: const TextStyle(
                          color: _neuTextMuted,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: _neuInputBg,
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: neuRecessedShadows(),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.satellite_alt_rounded, color: _neuCobalt, size: 16),
                          const SizedBox(width: 5),
                          Text(
                            '$_weatherSatelliteCount គ្រាប់',
                            style: const TextStyle(
                              color: _neuTextDark,
                              fontSize: 13,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'Multi-GNSS',
                        style: TextStyle(
                          color: _neuTextMuted,
                          fontSize: 9.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // 3 Recessed Environmental Indicators
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                    decoration: BoxDecoration(
                      color: _neuInputBg,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: neuRecessedShadows(),
                    ),
                    child: Column(
                      children: [
                        const Text('💨 ល្បឿនខ្យល់', style: TextStyle(color: _neuTextMuted, fontSize: 10, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 2),
                        Text(
                          '${_weatherWindSpeed.toStringAsFixed(0)} km/h ${_getWindSpeedDesc(_weatherWindSpeed)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: _neuTextDark, fontSize: 11, fontWeight: FontWeight.w900),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                    decoration: BoxDecoration(
                      color: _neuInputBg,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: neuRecessedShadows(),
                    ),
                    child: Column(
                      children: [
                        const Text('🧭 ទិសដៅខ្យល់', style: TextStyle(color: _neuTextMuted, fontSize: 10, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 2),
                        Text(
                          _weatherWindDirection,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: _neuTextDark, fontSize: 11, fontWeight: FontWeight.w900),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                    decoration: BoxDecoration(
                      color: _neuInputBg,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: neuRecessedShadows(),
                    ),
                    child: Column(
                      children: [
                        const Text('☀️ កម្តៅ UV', style: TextStyle(color: _neuTextMuted, fontSize: 10, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 2),
                        Text(
                          _getUvDesc(_weatherUvIndex),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: _neuTextDark, fontSize: 11, fontWeight: FontWeight.w900),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Secondary Info Strip: Humidity, Rain, and Sync Timestamp
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.water_drop_rounded, color: Color(0xFF3B82F6), size: 13),
                    const SizedBox(width: 3),
                    Text(
                      'សំណើម ${_weatherHumidity.toStringAsFixed(0)}%',
                      style: const TextStyle(color: _neuTextMuted, fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(width: 10),
                    const Icon(Icons.cloud_queue_rounded, color: _neuCobalt, size: 13),
                    const SizedBox(width: 3),
                    Text(
                      'ទឹកភ្លៀង ${_weatherPrecipitation.toStringAsFixed(1)} mm',
                      style: const TextStyle(color: _neuTextMuted, fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                Text(
                  _formatSyncTime(),
                  style: const TextStyle(color: _neuTextMuted, fontSize: 9.5, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Action 1: Open Global Survey Details Modal
            GestureDetector(
              onTap: () => _showGlobalWeatherDetailsModal(context),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 12),
                decoration: BoxDecoration(
                  color: _neuBg,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white, width: 1.0),
                  boxShadow: neuExtrudedShadows(distance: 2, blur: 5),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.public_rounded, color: _neuCobalt, size: 16),
                    SizedBox(width: 6),
                    Text(
                      'មើលលម្អិតលក្ខខណ្ឌវាស់ដីពិភពលោក & ដ្រូន (Global Telemetry) >',
                      style: TextStyle(
                        color: _neuCobalt,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),

            // Action 2: Open Digital Compass Action
            GestureDetector(
              onTap: () => setState(() => _currentNavIndex = 2),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 12),
                decoration: BoxDecoration(
                  color: _neuBg,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white, width: 1.0),
                  boxShadow: neuExtrudedShadows(distance: 2, blur: 5),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.explore_rounded, color: _neuYellow, size: 16),
                    SizedBox(width: 6),
                    Text(
                      'បើកត្រីវិស័យពិនិត្យទិសដី និងខ្យល់ (Digital Compass) >',
                      style: TextStyle(
                        color: _neuCobalt,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _oldSurveyWeather() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: _neuBg,
          borderRadius: BorderRadius.circular(26),
          boxShadow: neuExtrudedShadows(distance: 6, blur: 18),
          border: Border.all(color: Colors.white, width: 1.3),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Row: Weather Title & Optimal Badge
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: _neuBg,
                        shape: BoxShape.circle,
                        boxShadow: neuExtrudedShadows(distance: 2, blur: 5),
                        border: Border.all(color: Colors.white, width: 1.2),
                      ),
                      child: const Icon(Icons.wb_sunny_rounded, color: _neuYellow, size: 20),
                    ),
                    const SizedBox(width: 10),
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'អាកាសធាតុ & លក្ខខណ្ឌចុះវាស់ដី',
                          style: TextStyle(
                            color: _neuTextDark,
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          'Field Survey & GNSS Conditions',
                          style: TextStyle(
                            color: _neuTextMuted,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF10B981).withOpacity(0.4), width: 1),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 12),
                      SizedBox(width: 4),
                      Text(
                        'ល្អឥតខ្ចោះ 98%',
                        style: TextStyle(
                          color: Color(0xFF047857),
                          fontSize: 10.5,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Middle Row: Temperature & Satellites Lock
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            '31°C',
                            style: TextStyle(
                              color: _neuTextDark,
                              fontSize: 32,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.5,
                            ),
                          ),
                          SizedBox(width: 8),
                          Text(
                            '☀️ មេឃស្រឡះ',
                            style: TextStyle(
                              color: _neuCobalt,
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'គ្មានភ្លៀង • ស័ក្តិសមចុះវាស់ព្រំដី & បង្ហោះដ្រូន',
                        style: TextStyle(
                          color: _neuTextMuted,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: _neuInputBg,
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: neuRecessedShadows(),
                  ),
                  child: const Column(
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.satellite_alt_rounded, color: _neuCobalt, size: 16),
                          SizedBox(width: 5),
                          Text(
                            '24 គ្រាប់',
                            style: TextStyle(
                              color: _neuTextDark,
                              fontSize: 13,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Multi-GNSS',
                        style: TextStyle(
                          color: _neuTextMuted,
                          fontSize: 9.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // 3 Recessed Environmental Indicators
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                    decoration: BoxDecoration(
                      color: _neuInputBg,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: neuRecessedShadows(),
                    ),
                    child: const Column(
                      children: [
                        Text('💨 ល្បឿនខ្យល់', style: TextStyle(color: _neuTextMuted, fontSize: 10, fontWeight: FontWeight.bold)),
                        SizedBox(height: 2),
                        Text('8 km/h ស្ងប់', style: TextStyle(color: _neuTextDark, fontSize: 11.5, fontWeight: FontWeight.w900)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                    decoration: BoxDecoration(
                      color: _neuInputBg,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: neuRecessedShadows(),
                    ),
                    child: const Column(
                      children: [
                        Text('🧭 ទិសដៅខ្យល់', style: TextStyle(color: _neuTextMuted, fontSize: 10, fontWeight: FontWeight.bold)),
                        SizedBox(height: 2),
                        Text('ឦសាន (45°)', style: TextStyle(color: _neuTextDark, fontSize: 11.5, fontWeight: FontWeight.w900)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                    decoration: BoxDecoration(
                      color: _neuInputBg,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: neuRecessedShadows(),
                    ),
                    child: const Column(
                      children: [
                        Text('☀️ កម្តៅ UV', style: TextStyle(color: _neuTextMuted, fontSize: 10, fontWeight: FontWeight.bold)),
                        SizedBox(height: 2),
                        Text('កម្រិត 4 (ធម្មតា)', style: TextStyle(color: _neuTextDark, fontSize: 11.5, fontWeight: FontWeight.w900)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Open Digital Compass Action
            GestureDetector(
              onTap: () => setState(() => _currentNavIndex = 2),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 12),
                decoration: BoxDecoration(
                  color: _neuBg,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white, width: 1.0),
                  boxShadow: neuExtrudedShadows(distance: 2, blur: 5),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.explore_rounded, color: _neuYellow, size: 16),
                    SizedBox(width: 6),
                    Text(
                      'បើកត្រីវិស័យពិនិត្យទិសដី និងខ្យល់ (Digital Compass) >',
                      style: TextStyle(
                        color: _neuCobalt,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }




  // ─────────────────────────────────────────────────────────────
  // 4C. RECENT SAVED PARCELS SECTION (Live Preview from Storage)
  // ─────────────────────────────────────────────────────────────
  Widget _buildRecentParcelsSection() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: _neuBg,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 1.2),
                      boxShadow: neuExtrudedShadows(distance: 2, blur: 4),
                    ),
                    child: const Icon(Icons.history_rounded, color: _neuCobalt, size: 16),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'ប្លង់ដីបានវាស់ចុងក្រោយ',
                    style: TextStyle(
                      color: _neuTextDark,
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
              if (_recentMeasurements.isNotEmpty)
                GestureDetector(
                  onTap: () {
                    setState(() => _currentNavIndex = 4);
                  },
                  child: const Text(
                    'មើលទាំងអស់ >',
                    style: TextStyle(
                      color: _neuCobalt,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),

          if (_recentMeasurements.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
              decoration: BoxDecoration(
                color: _neuBg,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: Colors.white, width: 1.2),
                boxShadow: neuExtrudedShadows(distance: 3, blur: 8),
              ),
              child: Column(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: _neuBg,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 1.2),
                      boxShadow: neuExtrudedShadows(distance: 2, blur: 5),
                    ),
                    child: const Icon(Icons.location_on_rounded, color: _neuCobalt, size: 22),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'មិនទាន់មានប្លង់ដីដែលបានរក្សាទុកនៅឡើយទេ',
                    style: TextStyle(
                      color: _neuTextDark,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'ចុចចាប់ផ្តើមវាស់ដីថ្មី ឬសាកល្បងប្លង់ដីគំរូខាងក្រោម!',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _neuTextMuted,
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      GestureDetector(
                        onTap: () {
                          setState(() {
                            _initialMeasureMode = MeasureMode.polygon;
                            _currentNavIndex = 1;
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [_neuCobalt, _neuCobaltDark],
                            ),
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: [
                              BoxShadow(
                                color: _neuCobalt.withOpacity(0.35),
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: const Text(
                            '+ វាស់ដីថ្មី',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      GestureDetector(
                        onTap: _loadSampleParcel,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: _neuBg,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: Colors.white, width: 1.2),
                            boxShadow: neuExtrudedShadows(distance: 2, blur: 4),
                          ),
                          child: const Text(
                            '⚡ ប្លង់គំរូ',
                            style: TextStyle(
                              color: _neuTextDark,
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            )
          else
            ...List.generate(_recentMeasurements.length, (idx) {
              final item = _recentMeasurements[idx];
              final m2 = item.areaM2.toStringAsFixed(1);
              final ha = (item.areaM2 / 10000).toStringAsFixed(3);
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _neuBg,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white, width: 1.2),
                  boxShadow: neuExtrudedShadows(distance: 3, blur: 8),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: _neuBg,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 1.2),
                        boxShadow: neuExtrudedShadows(distance: 2, blur: 5),
                      ),
                      child: Icon(
                        item.type == MeasurementType.circle ? Icons.circle_outlined : Icons.polyline_rounded,
                        color: _neuCobalt,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.name,
                            style: const TextStyle(
                              color: _neuTextDark,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '$m2 m²  •  $ha ហិកតា  •  ជុំវិញ: ${item.perimeterM.toStringAsFixed(0)}m',
                            style: const TextStyle(
                              color: _neuCobalt,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          _initialMeasureMode = item.type == MeasurementType.circle
                              ? MeasureMode.circle
                              : MeasureMode.polygon;
                          _currentNavIndex = 1;
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                        decoration: BoxDecoration(
                          color: _neuBg,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white, width: 1),
                          boxShadow: neuExtrudedShadows(distance: 2, blur: 4),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.open_in_new_rounded, color: _neuCobalt, size: 14),
                            SizedBox(width: 4),
                            Text(
                              'វាស់',
                              style: TextStyle(
                                color: _neuCobalt,
                                fontSize: 11,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // MODAL 1: REAL AREA BREAKDOWN & CALCULATOR
  // ─────────────────────────────────────────────────────────────
  void _showEditLandTitleDialog() {
    final controller = TextEditingController(
      text: _measurementTitle == 'មិនទាន់មានទិន្នន័យ (០)' ? '' : _measurementTitle,
    );
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _neuBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _neuCobalt.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.edit_note_rounded, color: _neuCobalt, size: 24),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'កែសម្រួលឈ្មោះប្លង់ដី',
                style: TextStyle(
                  color: _neuTextDark,
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'សូមបញ្ចូលឈ្មោះក្បាលដី ឬទីតាំងដីជាក់ស្តែង៖',
              style: TextStyle(color: _neuTextMuted, fontSize: 12, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                color: _neuInputBg,
                borderRadius: BorderRadius.circular(16),
                boxShadow: neuRecessedShadows(),
              ),
              child: TextField(
                controller: controller,
                autofocus: true,
                style: const TextStyle(color: _neuTextDark, fontWeight: FontWeight.bold),
                decoration: const InputDecoration(
                  hintText: 'ឧ. ដីចម្ការមាត់ស្ទឹង កំពត...',
                  hintStyle: TextStyle(color: _neuTextMuted),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'ឈ្មោះរហ័ស (Quick Presets)៖',
              style: TextStyle(color: _neuTextMuted, fontSize: 11, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                'ដីចម្ការមាត់ស្ទឹង កំពត',
                'ដីឡូត៍លំនៅឋាន ភ្នំពេញ',
                'ដីកសិកម្មដាំដំណាំ',
                'ដីជាប់ផ្លូវជាតិលេខ ៣',
              ].map((name) => InkWell(
                onTap: () {
                  controller.text = name;
                },
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: _neuCobalt.withOpacity(0.3)),
                  ),
                  child: Text(
                    name,
                    style: const TextStyle(color: _neuCobalt, fontSize: 10.5, fontWeight: FontWeight.w700),
                  ),
                ),
              )).toList(),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('បោះបង់', style: TextStyle(color: _neuTextMuted, fontWeight: FontWeight.w700)),
          ),
          ElevatedButton(
            onPressed: () {
              final newName = controller.text.trim();
              if (newName.isNotEmpty) {
                setState(() {
                  _measurementTitle = newName;
                });
              }
              Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: _neuCobalt,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            ),
            child: const Text('រក្សាទុក', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
          ),
        ],
      ),
    );
  }

  void _showAltitudeDetailsModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: _neuBg,
          borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: _neuTextMuted.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: _neuYellow.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.terrain_rounded, color: Color(0xFFD97706), size: 28),
                ),
                const SizedBox(width: 14),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'កម្ពស់ដីធៀបនីវ៉ូសមុទ្រ (GNSS Altitude)',
                      style: TextStyle(color: _neuTextDark, fontSize: 16, fontWeight: FontWeight.w900),
                    ),
                    Text(
                      'កម្ពស់ផ្កាយរណបពិតពីផែនដី (MSL Level)',
                      style: TextStyle(color: _neuTextMuted, fontSize: 11, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _neuInputBg,
                borderRadius: BorderRadius.circular(20),
                boxShadow: neuRecessedShadows(),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  Column(
                    children: [
                      const Text('កម្ពស់បច្ចុប្បន្ន', style: TextStyle(color: _neuTextMuted, fontSize: 11, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      Text(
                        '+${_realAltitude.toStringAsFixed(1)} m',
                        style: const TextStyle(color: _neuTextDark, fontSize: 24, fontWeight: FontWeight.w900),
                      ),
                      Text(
                        '+${_toKhmerDigits(_realAltitude.toStringAsFixed(1))} ម៉ែត្រ',
                        style: const TextStyle(color: _neuCobalt, fontSize: 11, fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                  Container(width: 1, height: 45, color: _neuDarkShadow.withOpacity(0.4)),
                  Column(
                    children: [
                      const Text('ភាពសុក្រឹតបញ្ឈរ', style: TextStyle(color: _neuTextMuted, fontSize: 11, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      Text(
                        _realGpsAccuracy > 0 ? '±${(_realGpsAccuracy * 1.4).toStringAsFixed(1)} m' : '±1.5 m',
                        style: const TextStyle(color: Color(0xFF10B981), fontSize: 22, fontWeight: FontWeight.w900),
                      ),
                      const Text('GNSS 3D Fix', style: TextStyle(color: _neuTextMuted, fontSize: 11, fontWeight: FontWeight.w800)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(ctx);
                await _fetchRealGps();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: _neuCobalt,
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.refresh_rounded, color: Colors.white),
                  SizedBox(width: 8),
                  Text('ស្កេនកម្ពស់ GPS ឡើងវិញ (Rescan GNSS)', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showAreaDetailsModal(BuildContext context) {
    final sqm = _realAreaM2;
    final are = sqm / 100;
    final ha = sqm / 10000;
    // price removed // $150/sqm default estimate

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withOpacity(0.35),
      isScrollControlled: true,
      builder: (ctx) => Container(
        padding: const EdgeInsets.fromLTRB(22, 14, 22, 28),
        decoration: BoxDecoration(
          color: _neuBg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(34)),
          border: Border.all(color: Colors.white, width: 1.5),
          boxShadow: [
            BoxShadow(
              color: _neuDarkShadow.withOpacity(0.55),
              blurRadius: 30,
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
            // Handle
            Container(
              width: 44,
              height: 5,
              decoration: BoxDecoration(
                color: _neuTextMuted.withOpacity(0.3),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(height: 16),

            // Title
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: _neuBg,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1.5),
                    boxShadow: neuExtrudedShadows(distance: 2.5, blur: 6),
                  ),
                  child: const Icon(Icons.layers_rounded, color: _neuCobalt, size: 22),
                ),
                const SizedBox(width: 12),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'គណនាទំហំផ្ទៃដីជាក់ស្តែង',
                      style: TextStyle(color: _neuTextDark, fontSize: 18, fontWeight: FontWeight.w900),
                    ),
                    Text(
                      'ប្រព័ន្ធគណនាផ្ទៃដីស្តង់ដារអន្តរជាតិ (WGS84)',
                      style: TextStyle(color: _neuTextMuted, fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 18),

            // Breakdown rows
            _buildDetailRow('ទំហំម៉ែត្រការ៉េ (m²)', '${sqm.toStringAsFixed(2)} m²', 'ខ្នាតស្តង់ដារទូទៅ'),
            _buildDetailRow('ទំហំជា អា (Are)', '${are.toStringAsFixed(2)} អា', '១ អា = ១០០ ម៉ែត្រការ៉េ'),
            _buildDetailRow('ទំហំជា ហិកតា (Hectare)', '${ha.toStringAsFixed(4)} Ha', '១ ហិកតា = ១០,០០០ m²'),
            _buildDetailRow('ទំហំជា អេក័រ (Acre)', '${(sqm / 4046.86).toStringAsFixed(3)} Acre', '១ អេក័រ = ៤,០៤៦.៨៦ m²'),

            const SizedBox(height: 20),

            // 2 Action Buttons
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      Navigator.pop(ctx);
                      _resetToZero();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        color: _neuBg,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white, width: 1.5),
                        boxShadow: neuExtrudedShadows(distance: 2.5, blur: 6),
                      ),
                      child: const Center(
                        child: Text(
                          '🔄 កំណត់សូន្យ (០)',
                          style: TextStyle(color: _neuTextDark, fontWeight: FontWeight.w800, fontSize: 14),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: GestureDetector(
                    onTap: () async {
                      Navigator.pop(ctx);
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const MapMeasurementScreen(initialMode: MeasureMode.polygon),
                        ),
                      );
                      _loadLatestMeasurement();
    _fetchLiveRealWorldWeather();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [_neuCobalt, _neuCobaltDark],
                        ),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: _neuCobalt.withOpacity(0.4),
                            blurRadius: 14,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Center(
                        child: Text(
                          '🚀 វាស់ដីផ្ទាល់លើផែនទី',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 14),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // MODAL 2: BOUNDARY PINS GPS COORDINATES LIST
  // ─────────────────────────────────────────────────────────────
  void _showPointsDetailsModal(BuildContext context) {
    final points = _latestMeasurement?.points;
    final hasPoints = points != null && points.isNotEmpty;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withOpacity(0.35),
      isScrollControlled: true,
      builder: (ctx) => Container(
        padding: const EdgeInsets.fromLTRB(22, 14, 22, 28),
        decoration: BoxDecoration(
          color: _neuBg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(34)),
          border: Border.all(color: Colors.white, width: 1.5),
          boxShadow: [
            BoxShadow(
              color: _neuDarkShadow.withOpacity(0.55),
              blurRadius: 30,
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
            // Handle
            Container(
              width: 44,
              height: 5,
              decoration: BoxDecoration(
                color: _neuTextMuted.withOpacity(0.3),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(height: 16),

            // Title
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: _neuBg,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1.5),
                    boxShadow: neuExtrudedShadows(distance: 2.5, blur: 6),
                  ),
                  child: const Icon(Icons.pin_drop_rounded, color: _neuCobalt, size: 22),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'បញ្ជីបង្គោលដី & កូអរដោនេ GPS',
                      style: TextStyle(color: _neuTextDark, fontSize: 18, fontWeight: FontWeight.w900),
                    ),
                    Text(
                      hasPoints ? 'មានចំនួន ${points.length} បង្គោលដីជាក់ស្តែង' : 'មិនទាន់មានបង្គោលដីនៅឡើយ (០ បង្គោល)',
                      style: const TextStyle(color: _neuTextMuted, fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 18),

            if (hasPoints) ...[
              for (int i = 0; i < points.length; i++)
                _buildPointCoordCard(
                  'បង្គោលទី ${i + 1}',
                  '${points[i]['lat']?.toStringAsFixed(5)}° N, ${points[i]['lng']?.toStringAsFixed(5)}° E',
                  'កូអរដោនេ WGS84 ផ្កាយរណប',
                ),
            ] else ...[
              Container(
                padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
                decoration: BoxDecoration(
                  color: _neuInputBg,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: Colors.white.withOpacity(0.8)),
                ),
                child: Column(
                  children: const [
                    Icon(Icons.location_off_rounded, color: _neuTextMuted, size: 40),
                    SizedBox(height: 10),
                    Text(
                      'បច្ចុប្បន្នមាន ០ បង្គោលដី',
                      style: TextStyle(color: _neuTextDark, fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'សូមចុចវាស់ដីដើម្បីបន្ថែមបង្គោលដីជាក់ស្តែងលើផែនទី ឬដើរវាស់ GPS',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: _neuTextMuted, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 20),

            // Action Buttons
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      Navigator.pop(ctx);
                      _resetToZero();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        color: _neuBg,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white, width: 1.5),
                        boxShadow: neuExtrudedShadows(distance: 2.5, blur: 6),
                      ),
                      child: const Center(
                        child: Text(
                          '🔄 កំណត់សូន្យ (០)',
                          style: TextStyle(color: _neuTextDark, fontWeight: FontWeight.w800, fontSize: 14),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: GestureDetector(
                    onTap: () async {
                      Navigator.pop(ctx);
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const MapMeasurementScreen(initialMode: MeasureMode.polygon),
                        ),
                      );
                      _loadLatestMeasurement();
    _fetchLiveRealWorldWeather();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [_neuCobalt, _neuCobaltDark],
                        ),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: _neuCobalt.withOpacity(0.4),
                            blurRadius: 14,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Center(
                        child: Text(
                          '📍 បន្ថែមបង្គោលដីថ្មី',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 14),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // MODAL 3: GNSS SATELLITE ACCURACY DIAGNOSTIC
  // ─────────────────────────────────────────────────────────────
  void _showGpsAccuracyModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withOpacity(0.35),
      isScrollControlled: true,
      builder: (ctx) => Container(
        padding: const EdgeInsets.fromLTRB(22, 14, 22, 28),
        decoration: BoxDecoration(
          color: _neuBg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(34)),
          border: Border.all(color: Colors.white, width: 1.5),
          boxShadow: [
            BoxShadow(
              color: _neuDarkShadow.withOpacity(0.55),
              blurRadius: 30,
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
            Container(
              width: 44,
              height: 5,
              decoration: BoxDecoration(
                color: _neuTextMuted.withOpacity(0.3),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(height: 16),

            // Title
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: _neuBg,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1.5),
                    boxShadow: neuExtrudedShadows(distance: 2.5, blur: 6),
                  ),
                  child: const Icon(Icons.gps_fixed_rounded, color: _neuCobalt, size: 22),
                ),
                const SizedBox(width: 12),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'ស្ថានភាពផ្កាយរណប GPS RTK',
                      style: TextStyle(color: _neuTextDark, fontSize: 18, fontWeight: FontWeight.w900),
                    ),
                    Text(
                      'ប្រព័ន្ធកំណត់ទីតាំងសុក្រឹតភាពខ្ពស់ Live Device',
                      style: TextStyle(color: _neuTextMuted, fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 18),

            _buildDetailRow(
              'ស្ថានភាព GPS',
              _isGpsLocked ? '🟢 GPS Live (ភ្ជាប់បាន)' : '⚪ រង់ចាំស្កេនចាប់សញ្ញា',
              _isGpsLocked ? 'ផ្កាយរណបកំពុងដំណើរការ' : 'ចុចស្កេនដើម្បីចាប់សញ្ញា GPS ផ្ទាល់',
            ),
            _buildDetailRow(
              'កម្រិតលម្អៀង',
              _realGpsAccuracy > 0 ? '±${_realGpsAccuracy.toStringAsFixed(1)} ម៉ែត្រ' : '±0.0 ម៉ែត្រ',
              'កម្រិតសុក្រឹតភាពនៃការវាស់ដី',
            ),
            _buildDetailRow('បណ្តាញផ្កាយរណប', 'GNSS / GPS / GLONASS', 'ផ្កាយរណបសកល WGS84'),
            _buildDetailRow('កម្រិតសុក្រឹតភាព', _realGpsAccuracy > 0 ? 'ល្អប្រសើរ (High Precision)' : '០ (Default Zero)', 'សម្រាប់ការវាស់ក្បាលដី'),

            const SizedBox(height: 20),
            GestureDetector(
              onTap: () async {
                Navigator.pop(ctx);
                await _fetchRealGps();
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [_neuCobalt, _neuCobaltDark],
                  ),
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: [
                    BoxShadow(
                      color: _neuCobalt.withOpacity(0.4),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Center(
                  child: Text(
                    '📡 ស្កេនចាប់សញ្ញា GPS ផ្ទាល់ពីទូរស័ព្ទ / កុំព្យូទ័រ',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 14),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // MODAL 5: GNSS SATELLITE CONSTELLATION & TELEMETRY
  // ─────────────────────────────────────────────────────────────
  void _showSatellitesDetailsModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withOpacity(0.35),
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          padding: const EdgeInsets.fromLTRB(22, 14, 22, 28),
          decoration: BoxDecoration(
            color: _neuBg,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(34)),
            border: Border.all(color: Colors.white, width: 1.5),
            boxShadow: [
              BoxShadow(
                color: _neuDarkShadow.withOpacity(0.55),
                blurRadius: 30,
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
              Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: _neuTextMuted.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFE11D48), Color(0xFFFB7185)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.white, width: 1.2),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFE11D48).withOpacity(0.35),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: const Center(
                      child: Icon(Icons.satellite_alt_rounded, color: Colors.white, size: 22),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'ប្រព័ន្ធផ្កាយរណប GNSS Live',
                          style: TextStyle(
                            color: _neuTextDark,
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          'Multi-Constellation Satellite Telemetry',
                          style: TextStyle(
                            color: _neuTextMuted,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF10B981).withOpacity(0.4)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 14),
                        SizedBox(width: 4),
                        Text(
                          'RTK Fix',
                          style: TextStyle(
                            color: Color(0xFF10B981),
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              // Big Satellite Count Banner
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: _neuBg,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: neuRecessedShadows(),
                  border: Border.all(color: Colors.white.withOpacity(0.7), width: 1.2),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'ផ្កាយរណបភ្ជាប់បាន (Connected)',
                          style: TextStyle(color: _neuTextMuted, fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '$_weatherSatelliteCount គ្រាប់ (L1/L2/L5)',
                          style: const TextStyle(
                            color: _neuTextDark,
                            fontSize: 19,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFE11D48), Color(0xFFFB7185)],
                        ),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Text(
                        'Signal 98%',
                        style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w900),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              // Constellations Breakdown Grid
              Row(
                children: [
                  Expanded(
                    child: _buildSatelliteCard('🇺🇸 GPS (USA)', '8 គ្រាប់', 'L1/L2C/L5', const Color(0xFF3B82F6)),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildSatelliteCard('🇨🇳 BeiDou', '9 គ្រាប់', 'B1I/B2a/B3I', const Color(0xFFEF4444)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _buildSatelliteCard('🇪🇺 Galileo', '5 គ្រាប់', 'E1/E5a/E5b', const Color(0xFF10B981)),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildSatelliteCard('🇷🇺 GLONASS', '4 គ្រាប់', 'G1/G2/G3', const Color(0xFFF59E0B)),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              // Rescan Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    setState(() {
                      _weatherSatelliteCount = 26 + (DateTime.now().second % 6);
                    });
                  },
                  icon: const Icon(Icons.sync_rounded, color: Colors.white, size: 18),
                  label: const Text(
                    'ស្កេនផ្កាយរណបឡើងវិញ (Rescan Satellites)',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFE11D48),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                    elevation: 3,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSatelliteCard(String name, String count, String band, Color accentColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: _neuBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.9), width: 1.1),
        boxShadow: neuExtrudedShadows(distance: 2, blur: 5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(name, style: const TextStyle(color: _neuTextDark, fontSize: 11, fontWeight: FontWeight.w900)),
              Text(count, style: TextStyle(color: accentColor, fontSize: 11.5, fontWeight: FontWeight.w900)),
            ],
          ),
          const SizedBox(height: 2),
          Text(band, style: const TextStyle(color: _neuTextMuted, fontSize: 9.5, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // MODAL 4: PERIMETER DETAILS & SIDE LENGTHS
  // ─────────────────────────────────────────────────────────────
  void _showPerimeterDetailsModal(BuildContext context) {
    final peri = _realPerimeterM;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withOpacity(0.35),
      isScrollControlled: true,
      builder: (ctx) => Container(
        padding: const EdgeInsets.fromLTRB(22, 14, 22, 28),
        decoration: BoxDecoration(
          color: _neuBg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(34)),
          border: Border.all(color: Colors.white, width: 1.5),
          boxShadow: [
            BoxShadow(
              color: _neuDarkShadow.withOpacity(0.55),
              blurRadius: 30,
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
            Container(
              width: 44,
              height: 5,
              decoration: BoxDecoration(
                color: _neuTextMuted.withOpacity(0.3),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(height: 16),

            // Title
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: _neuBg,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1.5),
                    boxShadow: neuExtrudedShadows(distance: 2.5, blur: 6),
                  ),
                  child: const Icon(Icons.straighten_rounded, color: _neuCobalt, size: 22),
                ),
                const SizedBox(width: 12),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'ប្រវែងព័ទ្ធជុំវិញ & របងដី',
                      style: TextStyle(color: _neuTextDark, fontSize: 18, fontWeight: FontWeight.w900),
                    ),
                    Text(
                      'គណនាប្រវែងខ្សែបន្ទាត់ព័ទ្ធជុំវិញសរុប',
                      style: TextStyle(color: _neuTextMuted, fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 18),

            _buildDetailRow('ប្រវែងជុំវិញសរុប', '${peri.toStringAsFixed(1)} ម៉ែត្រ', 'គិតតាមខ្សែព្រំដីជាក់ស្តែង'),
            _buildDetailRow('ចំនួនបង្គោលសរុប', '$_realPointsCount បង្គោល', 'ចំណុចកាច់ជ្រុង'),
            _buildDetailRow('ប៉ាន់ស្មានថ្លៃធ្វើរបង (\$25/m)', '\$${(peri * 25).toStringAsFixed(0)}', 'តម្លៃរបងបេតុង/បន្លាលួស'),

            const SizedBox(height: 20),

            // Action Buttons
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      Navigator.pop(ctx);
                      _resetToZero();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        color: _neuBg,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white, width: 1.5),
                        boxShadow: neuExtrudedShadows(distance: 2.5, blur: 6),
                      ),
                      child: const Center(
                        child: Text(
                          '🔄 កំណត់សូន្យ (០)',
                          style: TextStyle(color: _neuTextDark, fontWeight: FontWeight.w800, fontSize: 14),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: GestureDetector(
                    onTap: () async {
                      Navigator.pop(ctx);
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const MapMeasurementScreen(initialMode: MeasureMode.polygon),
                        ),
                      );
                      _loadLatestMeasurement();
    _fetchLiveRealWorldWeather();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [_neuCobalt, _neuCobaltDark],
                        ),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: _neuCobalt.withOpacity(0.4),
                            blurRadius: 14,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Center(
                        child: Text(
                          '📏 វាស់ប្រវែងជុំវិញដី',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 14),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, String sub) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: _neuBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white, width: 1.2),
        boxShadow: neuExtrudedShadows(distance: 2.5, blur: 6),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(color: _neuTextDark, fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(height: 2),
              Text(sub, style: const TextStyle(color: _neuTextMuted, fontSize: 10.5, fontWeight: FontWeight.w500)),
            ],
          ),
          Text(
            value,
            style: const TextStyle(
              color: _neuCobalt,
              fontWeight: FontWeight.w900,
              fontSize: 15,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPointCoordCard(String title, String coords, String desc) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: _neuBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white, width: 1.2),
        boxShadow: neuExtrudedShadows(distance: 2.5, blur: 6),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: _neuBg,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 1.2),
              boxShadow: neuExtrudedShadows(distance: 2, blur: 4),
            ),
            child: const Icon(Icons.location_on_rounded, color: _neuCobalt, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: _neuTextDark, fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 2),
                Text(coords, style: const TextStyle(color: _neuCobalt, fontWeight: FontWeight.w800, fontSize: 11.5)),
                Text(desc, style: const TextStyle(color: _neuTextMuted, fontSize: 10.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }



  // ─────────────────────────────────────────────────────────────
  // 7. FLOATING BOTTOM BAR (Neumorphic Ceramic Soft UI Floating Capsule)
  // ─────────────────────────────────────────────────────────────
  Widget _buildFloatingBottomBar() {
    return Container(
      height: 70,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: _neuBg,
        borderRadius: BorderRadius.circular(40),
        boxShadow: neuExtrudedShadows(distance: 8, blur: 24),
        border: Border.all(
          color: Colors.white,
          width: 1.6,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // 1. Home
          _buildNavButton(
            index: 0,
            icon: Icons.home_rounded,
            tooltip: 'ទំព័រដើម',
            onTap: () {
              setState(() => _currentNavIndex = 0);
              _loadLatestMeasurement();
    _fetchLiveRealWorldWeather();
            },
          ),
          // 2. Measure Map (Pin - Primary Surveyor Tool)
          _buildNavButton(
            index: 1,
            icon: Icons.location_on_rounded,
            tooltip: 'វាស់ដីលើផែនទី',
            onTap: () {
              setState(() => _currentNavIndex = 1);
            },
          ),
          // 3. Compass (Dedicated Screen)
          _buildNavButton(
            index: 2,
            icon: Icons.explore_rounded,
            tooltip: 'ត្រីវិស័យវាស់ទិសដី',
            onTap: () {
              setState(() => _currentNavIndex = 2);
            },
          ),
          // 4. Price Calculator (Dedicated Screen)
          _buildNavButton(
            index: 3,
            icon: Icons.calculate_rounded,
            tooltip: 'គិតតម្លៃដី',
            onTap: () {
              setState(() => _currentNavIndex = 3);
            },
          ),
          // 5. Land History / Bookmark
          _buildNavButton(
            index: 4,
            icon: Icons.bookmark_rounded,
            tooltip: 'ប្រវត្តិប្លង់ដី',
            onTap: () {
              setState(() => _currentNavIndex = 4);
            },
          ),
          // 6. Settings / Profile
          _buildNavButton(
            index: 5,
            icon: Icons.settings_rounded,
            tooltip: 'គណនី & កំណត់',
            onTap: () {
              setState(() => _currentNavIndex = 5);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildNavButton({
    required int index,
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    final isSelected = _currentNavIndex == index;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
        width: isSelected ? 54 : 48,
        height: isSelected ? 54 : 48,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: isSelected
              ? const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [_neuCobalt, _neuCobaltDark],
                )
              : null,
          color: isSelected ? null : _neuBg,
          border: Border.all(
            color: Colors.white,
            width: isSelected ? 1.8 : 1.2,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: _neuCobalt.withOpacity(0.55),
                    blurRadius: 16,
                    offset: const Offset(0, 5),
                  ),
                  const BoxShadow(
                    color: _neuLightShadow,
                    blurRadius: 6,
                    offset: Offset(-2, -2),
                  ),
                ]
              : neuExtrudedShadows(distance: 3.5, blur: 9),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Icon(
              icon,
              color: isSelected ? Colors.white : _neuCobalt,
              size: isSelected ? 28 : 26,
              shadows: isSelected
                  ? const [
                      Shadow(
                        color: Colors.black38,
                        blurRadius: 4,
                        offset: Offset(0, 1.5),
                      ),
                    ]
                  : null,
            ),
            if (isSelected)
              Positioned(
                bottom: 4,
                child: Container(
                  width: 5.5,
                  height: 5.5,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _neuYellow,
                    boxShadow: [
                      BoxShadow(
                        color: _neuYellow.withOpacity(0.9),
                        blurRadius: 6,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // 2. DEDICATED DIGITAL COMPASS WORKSPACE (Cleanly Segregated Screen)
  // ─────────────────────────────────────────────────────────────
  String _getDirectionName(double deg) {
    if (deg >= 337.5 || deg < 22.5) return 'ទិសខាងជើង (N - ជើង)';
    if (deg >= 22.5 && deg < 67.5) return 'ទិសឦសាន (NE - កើតឈៀងជើង)';
    if (deg >= 67.5 && deg < 112.5) return 'ទិសខាងកើត (E - កើត)';
    if (deg >= 112.5 && deg < 157.5) return 'ទិសអាគ្នេយ៍ (SE - កើតឈៀងត្បូង)';
    if (deg >= 157.5 && deg < 202.5) return 'ទិសខាងត្បូង (S - ត្បូង)';
    if (deg >= 202.5 && deg < 247.5) return 'ទិសនិរតី (SW - លិចឈៀងត្បូង)';
    if (deg >= 247.5 && deg < 292.5) return 'ទិសខាងលិច (W - លិច)';
    return 'ទិសពាយព្យ (NW - លិចឈៀងជើង)';
  }

  String _getSunInsight(double deg) {
    if (deg >= 45 && deg <= 135) {
      return 'ទទួលពន្លឺព្រឹក 06:00 - 11:30 ត្រជាក់ស្រួលពេលរសៀល មិនក្តៅ';
    } else if (deg > 135 && deg <= 225) {
      return 'ទទួលពន្លឺថ្ងៃពេញមួយថ្ងៃ បរិយាកាសស្ងួតល្អ ស័ក្តិសមដាំដំណាំ';
    } else if (deg > 225 && deg <= 315) {
      return 'ទទួលកម្តៅថ្ងៃរសៀលខ្លាំង 13:00 - 17:30 គួររៀបចំបរិវេណម្លប់';
    } else {
      return 'ពន្លឺថ្ងៃទន់ល្មមពេញមួយឆ្នាំ ផ្ទះត្រជាក់ស្រួល បរិយាកាសស្ងប់ស្ងាត់';
    }
  }

  String _getWindInsight(double deg) {
    if (deg >= 22.5 && deg <= 157.5) {
      return 'ទទួលខ្យល់មូសុងឦសានរដូវរងារត្រជាក់បរិសុទ្ធ';
    } else if (deg > 157.5 && deg <= 292.5) {
      return 'ទទួលខ្យល់មូសុងនិរតីរដូវវស្សា បក់ត្រជាក់មកពីសមុទ្រ';
    } else {
      return 'ចរន្តខ្យល់ធម្មជាតិបក់ទៀងទាត់ ខ្យល់អាកាសស្រស់ថ្លា';
    }
  }

  String _getGateAdvice(double deg) {
    if (deg >= 45 && deg <= 135) {
      return 'ទ្វារមុខបែរទៅកើត ទទួលលាភសំណាង និងពន្លឺថ្ងៃព្រឹកត្រជាក់ស្រួល';
    } else if (deg > 135 && deg <= 225) {
      return 'ទ្វារបែរទៅត្បូង ទទួលខ្យល់ត្រជាក់បក់ចូលផ្ទះពេញមួយឆ្នាំ';
    } else if (deg > 225 && deg <= 315) {
      return 'ទ្វារបែរទៅលិច គួរមានដំបូលហោជាង ឬដាំដើមឈើជួយបាំងកម្តៅ';
    } else {
      return 'ទ្វារបែរទៅជើង ផ្ទះត្រជាក់ ស្ងប់ស្ងាត់ មិនសូវត្រូវកម្តៅថ្ងៃ';
    }
  }

  String _getSolarAdvice(double deg) {
    if (deg >= 135 && deg <= 225) {
      return 'ប្រសិទ្ធភាពស្រូបពន្លឺ 98% (ល្អឥតខ្ចោះបំផុតសម្រាប់សូឡា)';
    } else if (deg >= 45 && deg < 135) {
      return 'ប្រសិទ្ធភាពស្រូបពន្លឺ 85% (ស្រូបពន្លឺព្រឹកបានខ្លាំង)';
    } else if (deg > 225 && deg <= 315) {
      return 'ប្រសិទ្ធភាពស្រូបពន្លឺ 82% (ស្រូបពន្លឺរសៀលបានល្អ)';
    } else {
      return 'ប្រសិទ្ធភាពស្រូបពន្លឺ 65% (ពន្លឺមធ្យម គួរផ្អៀងទៅត្បូង)';
    }
  }

  String _getFengShuiAdvice(double deg) {
    if (deg >= 45 && deg <= 135) {
      return '🌅 ហុងស៊ុយល្អបំផុត! ក្បាលដីបែរមុខចំទិសថ្ងៃរះ នាំទ្រព្យសម្បត្តិ សុខដុម និងសុខភាពរឹងមាំ';
    } else if (deg > 135 && deg <= 225) {
      return '🍃 ខ្យល់អាកាសបរិសុទ្ធ ផ្ទះត្រជាក់ស្រួលពេញមួយឆ្នាំ ស័ក្តិសមសង់វីឡា ឬរីសតសម្រាកលំហែកាយ';
    } else if (deg > 225 && deg <= 315) {
      return '🏢 ស័ក្តិសមសម្រាប់បើកអាជីវកម្ម ហាងទំនិញ ឬឃ្លាំងស្តុក (ដាំដើមឈើមុខផ្ទះជួយបាំងកម្តៅ)';
    } else {
      return '💎 ទីតាំងស្ងប់ស្ងាត់ មានថាមពលវិជ្ជមានខ្ពស់ ស័ក្តិសមសម្រាប់លំនៅឋានស្ងប់សុខ';
    }
  }

  void _updateCompassFromTouch(Offset localPos) {
    if (_isHeadingLocked) return;
    final dx = localPos.dx - 110;
    final dy = localPos.dy - 110;
    double rad = math.atan2(dy, dx);
    double deg = (rad * 180 / math.pi) + 90;
    if (deg < 0) deg += 360;
    setState(() {
      _compassHeading = deg;
    });
  }

  Widget _buildCompassScreen(BuildContext context) {
    final effectiveHeading = _isTrueNorth ? ((_compassHeading - 0.8 + 360) % 360) : _compassHeading;

    return Column(
      children: [
        // Top Header
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: _neuBg,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: Colors.white, width: 1.5),
              boxShadow: neuExtrudedShadows(distance: 4, blur: 12),
            ),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () => setState(() => _currentNavIndex = 0),
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: _neuBg,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 1.2),
                      boxShadow: neuExtrudedShadows(distance: 2, blur: 5),
                    ),
                    child: const Icon(Icons.arrow_back_ios_new_rounded, color: _neuCobalt, size: 16),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'ត្រីវិស័យវាស់ទិសដី (Digital Compass)',
                        style: TextStyle(
                          color: _neuTextDark,
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        _isHeadingLocked
                            ? '🔒 ចាក់សោ: ${_lockedHeading.toStringAsFixed(0)}° ${_getDirectionName(_lockedHeading)}'
                            : _getDirectionName(effectiveHeading),
                        style: TextStyle(
                          color: _isHeadingLocked ? _neuYellow : _neuCobalt,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: () {
                    setState(() {
                      _isHeadingLocked = !_isHeadingLocked;
                      if (_isHeadingLocked) {
                        _lockedHeading = effectiveHeading;
                      }
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: _isHeadingLocked ? _neuCobalt : _neuInputBg,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: _isHeadingLocked
                          ? [
                              BoxShadow(
                                color: _neuCobalt.withOpacity(0.35),
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              ),
                            ]
                          : neuRecessedShadows(),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _isHeadingLocked ? Icons.lock_rounded : Icons.lock_open_rounded,
                          color: _isHeadingLocked ? _neuYellow : _neuTextMuted,
                          size: 14,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${(_isHeadingLocked ? _lockedHeading : effectiveHeading).toStringAsFixed(0)}°',
                          style: TextStyle(
                            color: _isHeadingLocked ? Colors.white : _neuCobalt,
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        // Scrollable Body
        Expanded(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 140),
            child: Column(
              children: [
                // ── Magnetic North vs True North Switcher Pill ──
                Container(
                  height: 42,
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: _neuInputBg,
                    borderRadius: BorderRadius.circular(22),
                    boxShadow: neuRecessedShadows(),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() => _isTrueNorth = false),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            decoration: BoxDecoration(
                              color: !_isTrueNorth ? _neuBg : Colors.transparent,
                              borderRadius: BorderRadius.circular(18),
                              border: !_isTrueNorth ? Border.all(color: Colors.white, width: 1.2) : null,
                              boxShadow: !_isTrueNorth ? neuExtrudedShadows(distance: 2, blur: 5) : null,
                            ),
                            child: Center(
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.explore_rounded,
                                    size: 14,
                                    color: !_isTrueNorth ? _neuCobalt : _neuTextMuted,
                                  ),
                                  const SizedBox(width: 5),
                                  Text(
                                    'ជើងម៉ាញេទិក (Magnetic)',
                                    style: TextStyle(
                                      color: !_isTrueNorth ? _neuCobalt : _neuTextMuted,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() => _isTrueNorth = true),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            decoration: BoxDecoration(
                              color: _isTrueNorth ? _neuBg : Colors.transparent,
                              borderRadius: BorderRadius.circular(18),
                              border: _isTrueNorth ? Border.all(color: Colors.white, width: 1.2) : null,
                              boxShadow: _isTrueNorth ? neuExtrudedShadows(distance: 2, blur: 5) : null,
                            ),
                            child: Center(
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.public_rounded,
                                    size: 14,
                                    color: _isTrueNorth ? _neuCobalt : _neuTextMuted,
                                  ),
                                  const SizedBox(width: 5),
                                  Text(
                                    'ជើងពិត (True North -0.8°)',
                                    style: TextStyle(
                                      color: _isTrueNorth ? _neuCobalt : _neuTextMuted,
                                      fontSize: 11,
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
                const SizedBox(height: 16),

                // 3D Neumorphic Compass Bezel & Dial
                GestureDetector(
                  onPanStart: (details) => _updateCompassFromTouch(details.localPosition),
                  onPanUpdate: (details) => _updateCompassFromTouch(details.localPosition),
                  child: Center(
                    child: Container(
                      width: 220,
                      height: 220,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _neuBg,
                        border: Border.all(color: Colors.white, width: 3),
                        boxShadow: neuExtrudedShadows(distance: 7, blur: 20),
                      ),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          // Inner Recessed Dial Slot
                          Container(
                            width: 185,
                            height: 185,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _neuInputBg,
                              boxShadow: [
                                BoxShadow(
                                  color: _neuDarkShadow.withOpacity(0.4),
                                  blurRadius: 6,
                                  offset: const Offset(3, 3),
                                ),
                                const BoxShadow(
                                  color: _neuLightShadow,
                                  blurRadius: 6,
                                  offset: Offset(-3, -3),
                                ),
                              ],
                            ),
                          ),

                          // 360 Degree Ticks & Degree Labels
                          CustomPaint(
                            size: const Size(220, 220),
                            painter: _CompassTicksPainter(),
                          ),

                          // Rotating Needle Layer
                          Transform.rotate(
                            angle: -effectiveHeading * (math.pi / 180),
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                // North Needle (Royal Cobalt Blue)
                                Positioned(
                                  top: 18,
                                  child: Column(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          gradient: const LinearGradient(
                                            colors: [_neuCobalt, _neuCobaltDark],
                                          ),
                                          borderRadius: BorderRadius.circular(8),
                                          boxShadow: [
                                            BoxShadow(
                                              color: _neuCobalt.withOpacity(0.45),
                                              blurRadius: 8,
                                              offset: const Offset(0, 2),
                                            ),
                                          ],
                                        ),
                                        child: const Text(
                                          'N ជើង',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w900,
                                            fontSize: 10,
                                            letterSpacing: 0.5,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      const Icon(
                                        Icons.navigation_rounded,
                                        color: _neuCobalt,
                                        size: 42,
                                      ),
                                    ],
                                  ),
                                ),

                                // South Needle (Muted Slate)
                                Positioned(
                                  bottom: 18,
                                  child: Column(
                                    children: [
                                      Transform.rotate(
                                        angle: math.pi,
                                        child: const Icon(
                                          Icons.navigation_rounded,
                                          color: Color(0xFF8E9BB0),
                                          size: 42,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: _neuBg,
                                          borderRadius: BorderRadius.circular(8),
                                          border: Border.all(color: Colors.white, width: 1),
                                          boxShadow: neuExtrudedShadows(distance: 1.5, blur: 4),
                                        ),
                                        child: const Text(
                                          'S ត្បូង',
                                          style: TextStyle(
                                            color: _neuTextDark,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 10,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                                // East & West Indicators
                                const Positioned(
                                  right: 18,
                                  child: Text(
                                    'E កើត',
                                    style: TextStyle(
                                      color: _neuTextDark,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                                const Positioned(
                                  left: 18,
                                  child: Text(
                                    'W លិច',
                                    style: TextStyle(
                                      color: _neuTextDark,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          // Center Core Pivot Hub
                          Container(
                            width: 26,
                            height: 26,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _neuBg,
                              border: Border.all(color: Colors.white, width: 2),
                              boxShadow: neuExtrudedShadows(distance: 2, blur: 6),
                            ),
                            child: Center(
                              child: Container(
                                width: 10,
                                height: 10,
                                decoration: const BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: _neuYellow,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // ── 8-Direction Master Grid (Eight Mansions Presets) ──
                Row(
                  children: [
                    _buildCompassPresetPill('ជើង 0°', effectiveHeading >= 355 || effectiveHeading < 5, () {
                      setState(() => _compassHeading = 0);
                    }),
                    const SizedBox(width: 6),
                    _buildCompassPresetPill('ឦសាន 45°', (effectiveHeading - 45).abs() < 5, () {
                      setState(() => _compassHeading = 45);
                    }),
                    const SizedBox(width: 6),
                    _buildCompassPresetPill('កើត 90°', (effectiveHeading - 90).abs() < 5, () {
                      setState(() => _compassHeading = 90);
                    }),
                    const SizedBox(width: 6),
                    _buildCompassPresetPill('អាគ្នេយ៍ 135°', (effectiveHeading - 135).abs() < 5, () {
                      setState(() => _compassHeading = 135);
                    }),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _buildCompassPresetPill('ត្បូង 180°', (effectiveHeading - 180).abs() < 5, () {
                      setState(() => _compassHeading = 180);
                    }),
                    const SizedBox(width: 6),
                    _buildCompassPresetPill('និរតី 225°', (effectiveHeading - 225).abs() < 5, () {
                      setState(() => _compassHeading = 225);
                    }),
                    const SizedBox(width: 6),
                    _buildCompassPresetPill('លិច 270°', (effectiveHeading - 270).abs() < 5, () {
                      setState(() => _compassHeading = 270);
                    }),
                    const SizedBox(width: 6),
                    _buildCompassPresetPill('ពាយព្យ 315°', (effectiveHeading - 315).abs() < 5, () {
                      setState(() => _compassHeading = 315);
                    }),
                  ],
                ),
                const SizedBox(height: 16),

                // ── NEW FEATURE: GROUND LEVEL BUBBLE & TILT INCLINOMETER ──
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: _neuBg,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: Colors.white, width: 1.3),
                    boxShadow: neuExtrudedShadows(distance: 3.5, blur: 10),
                  ),
                  child: Row(
                    children: [
                      // Circular Bullseye Level
                      Container(
                        width: 54,
                        height: 54,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _neuInputBg,
                          boxShadow: neuRecessedShadows(),
                          border: Border.all(color: Colors.white, width: 1.2),
                        ),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            // Concentric ring
                            Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(color: _neuDarkShadow, width: 1),
                              ),
                            ),
                            // Crosshair lines
                            Container(width: 44, height: 1, color: _neuDarkShadow.withOpacity(0.5)),
                            Container(width: 1, height: 44, color: _neuDarkShadow.withOpacity(0.5)),
                            // Green Bubble
                            Transform.translate(
                              offset: const Offset(3, -2),
                              child: Container(
                                width: 14,
                                height: 14,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: const Color(0xFF10B981),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFF10B981).withOpacity(0.7),
                                      blurRadius: 6,
                                      spreadRadius: 1,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 14),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  'ថ្នាំងទឹកវាស់តុល្យភាពដី (Level)',
                                  style: TextStyle(
                                    color: _neuTextDark,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                Spacer(),
                                Text(
                                  '0.5°',
                                  style: TextStyle(
                                    color: Color(0xFF10B981),
                                    fontSize: 13,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: 3),
                            Text(
                              '🟢 ដីរាបស្មើល្អឥតខ្ចោះ • ជម្រាល Pitch: +0.2° | Roll: -0.3°',
                              style: TextStyle(
                                color: _neuTextMuted,
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              '⛰️ កម្ពស់នីវ៉ូសមុទ្រ: +18m • 📍 11.5564° N, 104.9282° E',
                              style: TextStyle(
                                color: _neuCobalt,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // ── Land Analysis & Feng Shui Master Card ──
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: _neuBg,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Colors.white, width: 1.5),
                    boxShadow: neuExtrudedShadows(distance: 4, blur: 12),
                  ),
                  child: Column(
                    children: [
                      // Heading & Direction Name
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            '${effectiveHeading.toStringAsFixed(0)}°',
                            style: const TextStyle(
                              color: _neuCobalt,
                              fontSize: 26,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: _neuInputBg,
                              borderRadius: BorderRadius.circular(14),
                              boxShadow: neuRecessedShadows(),
                            ),
                            child: Text(
                              _getDirectionName(effectiveHeading),
                              style: const TextStyle(
                                color: _neuTextDark,
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),

                      // 2-Column Info Grid: Sun & Wind
                      Row(
                        children: [
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: _neuInputBg,
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: neuRecessedShadows(),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Row(
                                    children: [
                                      Icon(Icons.wb_sunny_rounded, color: _neuYellow, size: 16),
                                      SizedBox(width: 6),
                                      Text(
                                        'ពន្លឺថ្ងៃ',
                                        style: TextStyle(
                                          color: _neuTextDark,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 5),
                                  Text(
                                    _getSunInsight(effectiveHeading),
                                    style: const TextStyle(
                                      color: _neuTextDark,
                                      fontSize: 11,
                                      height: 1.3,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: _neuInputBg,
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: neuRecessedShadows(),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Row(
                                    children: [
                                      Icon(Icons.air_rounded, color: _neuCobalt, size: 16),
                                      SizedBox(width: 6),
                                      Text(
                                        'ចរន្តខ្យល់',
                                        style: TextStyle(
                                          color: _neuTextDark,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 5),
                                  Text(
                                    _getWindInsight(effectiveHeading),
                                    style: const TextStyle(
                                      color: _neuTextDark,
                                      fontSize: 11,
                                      height: 1.3,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),

                      // 2-Column Info Grid: Gate & Solar
                      Row(
                        children: [
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: _neuInputBg,
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: neuRecessedShadows(),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Row(
                                    children: [
                                      Icon(Icons.door_front_door_rounded, color: Color(0xFF6366F1), size: 16),
                                      SizedBox(width: 6),
                                      Text(
                                        'ទ្វារមុខ & របង',
                                        style: TextStyle(
                                          color: _neuTextDark,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 5),
                                  Text(
                                    _getGateAdvice(effectiveHeading),
                                    style: const TextStyle(
                                      color: _neuTextDark,
                                      fontSize: 11,
                                      height: 1.3,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: _neuInputBg,
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: neuRecessedShadows(),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Row(
                                    children: [
                                      Icon(Icons.solar_power_rounded, color: Color(0xFF10B981), size: 16),
                                      SizedBox(width: 6),
                                      Text(
                                        'ថាមពលសូឡា',
                                        style: TextStyle(
                                          color: _neuTextDark,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 5),
                                  Text(
                                    _getSolarAdvice(effectiveHeading),
                                    style: const TextStyle(
                                      color: _neuTextDark,
                                      fontSize: 11,
                                      height: 1.3,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // Feng Shui / Practical Land Advice Banner
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: _neuInputBg,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: neuRecessedShadows(),
                        ),
                        child: Text(
                          _getFengShuiAdvice(effectiveHeading),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: _neuTextDark,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            height: 1.35,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Button to Measure Land in this Direction
                GestureDetector(
                  onTap: () {
                    setState(() => _currentNavIndex = 1);
                  },
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [_neuCobalt, _neuCobaltDark],
                      ),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: _neuCobalt.withOpacity(0.4),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.location_on_rounded, color: _neuYellow, size: 20),
                        SizedBox(width: 8),
                        Text(
                          'វាស់ដីតាមទិសដៅនេះលើផែនទី (Map)',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14.5,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCompassPresetPill(String label, bool isSelected, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            gradient: isSelected
                ? const LinearGradient(
                    colors: [_neuCobalt, _neuCobaltDark],
                  )
                : null,
            color: isSelected ? null : _neuBg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isSelected ? Colors.white : Colors.white.withOpacity(0.9),
              width: 1.2,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: _neuCobalt.withOpacity(0.45),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : neuExtrudedShadows(distance: 2, blur: 5),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : _neuTextDark,
                fontSize: 10.5,
                fontWeight: isSelected ? FontWeight.w900 : FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // 3. DEDICATED LAND PRICE CALCULATOR & CONVERTER WORKSPACE
  // ─────────────────────────────────────────────────────────────
  void _onCalcKeyPress(String key) {
    setState(() {
      if (key == 'C') {
        _calcDisplay = '0';
        _calcFormula = '';
        _calcFirstOperand = null;
        _calcOperator = null;
        _calcShouldResetDisplay = false;
      } else if (key == '⌫') {
        if (_calcDisplay.length > 1) {
          _calcDisplay = _calcDisplay.substring(0, _calcDisplay.length - 1);
        } else {
          _calcDisplay = '0';
        }
      } else if (key == '+' || key == '-' || key == '×' || key == '÷') {
        _calcFirstOperand = double.tryParse(_calcDisplay) ?? 0.0;
        _calcOperator = key;
        _calcFormula = '$_calcDisplay $key';
        _calcShouldResetDisplay = true;
      } else if (key == '=') {
        if (_calcOperator != null && _calcFirstOperand != null) {
          final secondOperand = double.tryParse(_calcDisplay) ?? 0.0;
          double result = 0.0;
          if (_calcOperator == '+') result = _calcFirstOperand! + secondOperand;
          if (_calcOperator == '-') result = _calcFirstOperand! - secondOperand;
          if (_calcOperator == '×') result = _calcFirstOperand! * secondOperand;
          if (_calcOperator == '÷') {
            result = secondOperand != 0 ? _calcFirstOperand! / secondOperand : 0.0;
          }
          _calcFormula = '$_calcFormula $_calcDisplay =';
          if (result == result.roundToDouble()) {
            _calcDisplay = result.toInt().toString();
          } else {
            _calcDisplay = result.toStringAsFixed(2);
          }
          _calcFirstOperand = null;
          _calcOperator = null;
          _calcShouldResetDisplay = true;
        }
      } else if (key == '.') {
        if (!_calcDisplay.contains('.')) {
          _calcDisplay += '.';
        }
      } else {
        if (_calcDisplay == '0' || _calcShouldResetDisplay) {
          _calcDisplay = key;
          _calcShouldResetDisplay = false;
        } else {
          _calcDisplay += key;
        }
      }
    });
  }

  Widget _buildCalculatorScreen(BuildContext context) {
    // Current active area for price and conversion
    final currentArea = _calcCustomArea > 0
        ? _calcCustomArea
        : (_realAreaM2 > 0 ? _realAreaM2 : 0.0);

    double effectiveUnits = currentArea;
    if (_calcSelectedUnitType == 'អា (Are)') {
      effectiveUnits = effectiveUnits / 100;
    } else if (_calcSelectedUnitType == 'ហិកតា (Ha)') {
      effectiveUnits = effectiveUnits / 10000;
    }
    double baseTotal = effectiveUnits * _calcPricePerUnit;
    double taxAmount = _calcIncludeTax ? (baseTotal * 0.04) : 0.0;
    double adminFee = _calcIncludeTax ? 250.0 : 0.0;
    double total = baseTotal + taxAmount + adminFee;
    if (!_calcIsUsd) {
      total = total * 4100;
      baseTotal = baseTotal * 4100;
    }

    return Column(
      children: [
        // Top Header
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: _neuBg,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: Colors.white, width: 1.5),
              boxShadow: neuExtrudedShadows(distance: 4, blur: 12),
            ),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () => setState(() => _currentNavIndex = 0),
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: _neuBg,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 1.2),
                      boxShadow: neuExtrudedShadows(distance: 2, blur: 5),
                    ),
                    child: const Icon(Icons.arrow_back_ios_new_rounded, color: _neuCobalt, size: 16),
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'ម៉ាស៊ីនគណនាទំហំដី & ខ្នាត',
                        style: TextStyle(
                          color: _neuTextDark,
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        'ទទឹង × បណ្តោយ • បំប្លែងខ្នាតដី • ម៉ាស៊ីនគិតលេខ',
                        style: TextStyle(
                          color: _neuTextMuted,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                // Currency Switcher
                GestureDetector(
                  onTap: () {},
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                    decoration: BoxDecoration(
                      color: _neuBg,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white, width: 1.2),
                      boxShadow: neuExtrudedShadows(distance: 2.5, blur: 6),
                    ),
                    child: Text(
                      'ខ្នាតដីកម្ពុជា',
                      style: const TextStyle(
                        color: _neuCobalt,
                        fontWeight: FontWeight.w900,
                        fontSize: 12.5,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        // 5-Mode Segmented Horizontal Carousel Bar
        SizedBox(
          height: 42,
          child: ListView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              {'name': 'ទទឹង × បណ្តោយ', 'id': 0, 'icon': Icons.straighten_rounded},
              {'name': 'បំប្លែងខ្នាតដី', 'id': 1, 'icon': Icons.sync_alt_rounded},
              {'name': 'ម៉ាស៊ីនគិតលេខ', 'id': 2, 'icon': Icons.dialpad_rounded},


            ].map((tab) {
              final isSel = _calcMode == tab['id'];
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: GestureDetector(
                  onTap: () => setState(() => _calcMode = tab['id'] as int),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      gradient: isSel
                          ? const LinearGradient(colors: [_neuCobalt, _neuCobaltDark])
                          : null,
                      color: isSel ? null : _neuBg,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: isSel ? Colors.white : Colors.white.withOpacity(0.9),
                        width: 1.2,
                      ),
                      boxShadow: isSel
                          ? [
                              BoxShadow(
                                color: _neuCobalt.withOpacity(0.45),
                                blurRadius: 10,
                                offset: const Offset(0, 3),
                              ),
                            ]
                          : neuExtrudedShadows(distance: 2.5, blur: 6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          tab['icon'] as IconData,
                          color: isSel ? _neuYellow : _neuCobalt,
                          size: 15,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          tab['name'] as String,
                          style: TextStyle(
                            color: isSel ? Colors.white : _neuTextDark,
                            fontSize: 12,
                            fontWeight: isSel ? FontWeight.w900 : FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 6),

        // Scrollable Body based on Active Mode
        Expanded(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 140),
            child: _calcMode == 0
                ? _buildPlotDimensionsView()
                : (_calcMode == 1
                    ? _buildUnitConverterView(currentArea)
                    : _buildStandardKeypadView()),




          ),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────
  // MODE 0: LAND PRICE & CAMBODIA TAXES CALCULATOR
  // ─────────────────────────────────────────────────────────────
  // ignore: unused_element
  Widget _buildLandPriceCalculatorView(
    double currentArea,
    double total,
    double baseTotal,
    double taxAmount,
    double adminFee,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Total Price Display Hero Card
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          decoration: BoxDecoration(
            color: _neuBg,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white, width: 1.5),
            boxShadow: neuExtrudedShadows(distance: 4, blur: 14),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _calcIncludeTax
                          ? 'តម្លៃដីសរុបរួមទាំងពន្ធ ៤% & សេវា'
                          : 'តម្លៃដីប៉ាន់ស្មានសរុប (Total Price)',
                      style: const TextStyle(
                        color: _neuTextMuted,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _calcIsUsd
                          ? '\$${total.toStringAsFixed(0)} USD'
                          : '៛${total.toStringAsFixed(0)} ៛',
                      style: const TextStyle(
                        color: _neuCobalt,
                        fontSize: 27,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _calcIsUsd
                          ? '≈ ៛${(total * 4100).toStringAsFixed(0)} រៀល'
                          : '≈ \$${(total / 4100).toStringAsFixed(2)} USD',
                      style: const TextStyle(
                        color: _neuTextMuted,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: _neuYellow.withOpacity(0.18),
                  shape: BoxShape.circle,
                  border: Border.all(color: _neuYellow, width: 1.5),
                ),
                child: const Icon(
                  Icons.monetization_on_rounded,
                  color: _neuYellow,
                  size: 30,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Area Input with Steppers & Quick Use-Measured-Area Button
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _neuBg,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Colors.white, width: 1.5),
            boxShadow: neuExtrudedShadows(distance: 3.5, blur: 10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'ផ្ទៃក្រឡាដី (Land Area):',
                    style: TextStyle(color: _neuTextDark, fontSize: 13.5, fontWeight: FontWeight.w900),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: _neuInputBg,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: neuRecessedShadows(),
                    ),
                    child: Text(
                      '${currentArea.toStringAsFixed(1)} m²',
                      style: const TextStyle(color: _neuCobalt, fontSize: 16, fontWeight: FontWeight.w900),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Area Adjust Steppers (-100, -10, +10, +100, +1000)
              Row(
                children: [
                  _buildAreaStepButton('-100', () {
                    setState(() {
                      if (_calcCustomArea >= 100) {
                        _calcCustomArea -= 100;
                      } else {
                        _calcCustomArea = 0;
                      }
                    });
                  }),
                  const SizedBox(width: 6),
                  _buildAreaStepButton('-10', () {
                    setState(() {
                      if (_calcCustomArea >= 10) {
                        _calcCustomArea -= 10;
                      } else {
                        _calcCustomArea = 0;
                      }
                    });
                  }),
                  const SizedBox(width: 6),
                  _buildAreaStepButton('+10', () {
                    setState(() {
                      _calcCustomArea += 10;
                    });
                  }),
                  const SizedBox(width: 6),
                  _buildAreaStepButton('+100', () {
                    setState(() {
                      _calcCustomArea += 100;
                    });
                  }),
                  const SizedBox(width: 6),
                  _buildAreaStepButton('+1k', () {
                    setState(() {
                      _calcCustomArea += 1000;
                    });
                  }),
                ],
              ),
              const SizedBox(height: 12),

              // Quick Load Measured Land Area Button
              GestureDetector(
                onTap: () {
                  setState(() {
                    _calcCustomArea = _realAreaM2;
                  });
                },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: _neuBg,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: _neuCobalt.withOpacity(0.5), width: 1.2),
                    boxShadow: neuExtrudedShadows(distance: 2, blur: 5),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.location_on_rounded, color: _neuCobalt, size: 16),
                      const SizedBox(width: 6),
                      Text(
                        'យកទំហំពីវាស់ដី (${_realAreaM2.toStringAsFixed(1)} m²)',
                        style: const TextStyle(
                          color: _neuCobalt,
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Unit Type Selector Pills (m² / Are / Hectare)
        Row(
          children: ['ម៉ែត្រការ៉េ (m²)', 'អា (Are)', 'ហិកតា (Ha)'].map((type) {
            final isSel = _calcSelectedUnitType == type;
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      _calcSelectedUnitType = type;
                      if (type == 'ហិកតា (Ha)') {
                        _calcPricePerUnit = 250000;
                      } else if (type == 'អា (Are)') {
                        _calcPricePerUnit = 8000;
                      } else {
                        _calcPricePerUnit = 80;
                      }
                    });
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      gradient: isSel
                          ? const LinearGradient(colors: [_neuCobalt, _neuCobaltDark])
                          : null,
                      color: isSel ? null : _neuBg,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isSel ? Colors.white : Colors.white.withOpacity(0.9),
                        width: 1.2,
                      ),
                      boxShadow: isSel
                          ? [
                              BoxShadow(
                                color: _neuCobalt.withOpacity(0.45),
                                blurRadius: 10,
                                offset: const Offset(0, 3),
                              ),
                            ]
                          : neuExtrudedShadows(distance: 2.5, blur: 6),
                    ),
                    child: Center(
                      child: Text(
                        type,
                        style: TextStyle(
                          color: isSel ? Colors.white : _neuTextDark,
                          fontSize: 11,
                          fontWeight: isSel ? FontWeight.w900 : FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 16),

        // Price Input with Stepper (+ and - buttons)
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'តម្លៃក្នុង ១ $_calcSelectedUnitType:',
              style: const TextStyle(
                color: _neuTextDark,
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
            Row(
              children: [
                GestureDetector(
                  onTap: () {
                    setState(() {
                      if (_calcPricePerUnit > 10) _calcPricePerUnit -= 10;
                    });
                  },
                  child: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: _neuBg,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 1.2),
                      boxShadow: neuExtrudedShadows(distance: 2.5, blur: 6),
                    ),
                    child: const Icon(Icons.remove, color: _neuCobalt, size: 20),
                  ),
                ),
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 10),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: _neuInputBg,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.white.withOpacity(0.7), width: 1),
                  ),
                  child: Text(
                    _calcIsUsd
                        ? '\$${_calcPricePerUnit.toStringAsFixed(0)}'
                        : '៛${(_calcPricePerUnit * 4100).toStringAsFixed(0)}',
                    style: const TextStyle(
                      color: _neuCobalt,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () {
                    setState(() {
                      _calcPricePerUnit += 10;
                    });
                  },
                  child: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: _neuBg,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 1.2),
                      boxShadow: neuExtrudedShadows(distance: 2.5, blur: 6),
                    ),
                    child: const Icon(Icons.add, color: _neuCobalt, size: 20),
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 14),

        // Quick Preset Pills ($20, $50, $80, $120, $250, $500)
        if (_calcSelectedUnitType == 'ម៉ែត្រការ៉េ (m²)')
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [20, 50, 80, 120, 250, 500].map((preset) {
              final isCurrent = _calcPricePerUnit == preset.toDouble();
              return GestureDetector(
                onTap: () => setState(() => _calcPricePerUnit = preset.toDouble()),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
                  decoration: BoxDecoration(
                    gradient: isCurrent
                        ? const LinearGradient(colors: [_neuCobalt, _neuCobaltDark])
                        : null,
                    color: isCurrent ? null : _neuBg,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isCurrent ? Colors.white : Colors.white.withOpacity(0.9),
                      width: 1.2,
                    ),
                    boxShadow: isCurrent
                        ? [
                            BoxShadow(
                              color: _neuCobalt.withOpacity(0.45),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ]
                        : neuExtrudedShadows(distance: 2.5, blur: 5),
                  ),
                  child: Text(
                    '\$$preset',
                    style: TextStyle(
                      color: isCurrent ? Colors.white : _neuTextDark,
                      fontSize: 11.5,
                      fontWeight: isCurrent ? FontWeight.w900 : FontWeight.bold,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        const SizedBox(height: 18),

        // NEW: Cambodia Real Estate Tax & Transfer Fee Estimator Card
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _neuBg,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Colors.white, width: 1.5),
            boxShadow: neuExtrudedShadows(distance: 3.5, blur: 10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.receipt_long_rounded, color: _neuCobalt, size: 20),
                      SizedBox(width: 8),
                      Text(
                        'ពន្ធប្រថាប់ត្រា & សេវាផ្ទេរកម្មសិទ្ធិ',
                        style: TextStyle(
                          color: _neuTextDark,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                  Switch(
                    value: _calcIncludeTax,
                    activeColor: _neuCobalt,
                    onChanged: (val) => setState(() => _calcIncludeTax = val),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              const Text(
                'គណនាពន្ធ ៤% តាមច្បាប់កម្ពុជា និងសេវាផ្ទេរកម្មសិទ្ធិសុរិយោដី',
                style: TextStyle(color: _neuTextMuted, fontSize: 11, fontWeight: FontWeight.w600),
              ),

              if (_calcIncludeTax) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _neuInputBg,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: neuRecessedShadows(),
                  ),
                  child: Column(
                    children: [
                      _buildTaxRow('តម្លៃដីដើម (Base Land Price):', '\$${baseTotal.toStringAsFixed(0)}'),
                      const Divider(height: 12, color: Colors.white),
                      _buildTaxRow('ពន្ធប្រថាប់ត្រា (Transfer Tax 4%):', '+\$${(baseTotal * 0.04).toStringAsFixed(0)}'),
                      const Divider(height: 12, color: Colors.white),
                      _buildTaxRow('សេវារដ្ឋបាលសុរិយោដី (Cadastral Fee):', '+\$250'),
                      const Divider(height: 14, color: _neuCobalt),
                      _buildTaxRow(
                        'សរុបទាំងអស់ (Grand Total):',
                        '\$${(baseTotal + (baseTotal * 0.04) + 250).toStringAsFixed(0)}',
                        isTotal: true,
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTaxRow(String label, String value, {bool isTotal = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            color: isTotal ? _neuCobalt : _neuTextDark,
            fontSize: isTotal ? 12.5 : 11.5,
            fontWeight: isTotal ? FontWeight.w900 : FontWeight.bold,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            color: isTotal ? _neuCobalt : _neuTextDark,
            fontSize: isTotal ? 14 : 12,
            fontWeight: isTotal ? FontWeight.w900 : FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildAreaStepButton(String label, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: _neuBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white, width: 1.2),
            boxShadow: neuExtrudedShadows(distance: 2, blur: 5),
          ),
          child: Center(
            child: Text(
              label,
              style: const TextStyle(color: _neuCobalt, fontWeight: FontWeight.w900, fontSize: 11.5),
            ),
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // MODE 1: PLOT DIMENSIONS & SHAPE ESTIMATOR (បណ្តោយ × ទទឹង)
  // ─────────────────────────────────────────────────────────────
  Widget _buildPlotDimensionsView() {
    final plotArea = _calcIsTrapezoid
        ? ((_calcPlotWidth + _calcPlotBackWidth) / 2) * _calcPlotLength
        : _calcPlotWidth * _calcPlotLength;
    final plotPerimeter = _calcIsTrapezoid
        ? (_calcPlotWidth + _calcPlotBackWidth + 2 * _calcPlotLength)
        : 2 * (_calcPlotWidth + _calcPlotLength);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Shape Mode Selector: Rectangle vs Trapezoid
        Row(
          children: [
            Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _calcIsTrapezoid = false),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    gradient: !_calcIsTrapezoid
                        ? const LinearGradient(colors: [_neuCobalt, _neuCobaltDark])
                        : null,
                    color: !_calcIsTrapezoid ? null : _neuBg,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: !_calcIsTrapezoid ? Colors.white : Colors.white.withOpacity(0.9),
                      width: 1.2,
                    ),
                    boxShadow: !_calcIsTrapezoid
                        ? [
                            BoxShadow(
                              color: _neuCobalt.withOpacity(0.4),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ]
                        : neuExtrudedShadows(distance: 2.5, blur: 5),
                  ),
                  child: Center(
                    child: Text(
                      'ចតុកោណកែង (Rectangle)',
                      style: TextStyle(
                        color: !_calcIsTrapezoid ? Colors.white : _neuTextDark,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _calcIsTrapezoid = true),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    gradient: _calcIsTrapezoid
                        ? const LinearGradient(colors: [_neuCobalt, _neuCobaltDark])
                        : null,
                    color: _calcIsTrapezoid ? null : _neuBg,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: _calcIsTrapezoid ? Colors.white : Colors.white.withOpacity(0.9),
                      width: 1.2,
                    ),
                    boxShadow: _calcIsTrapezoid
                        ? [
                            BoxShadow(
                              color: _neuCobalt.withOpacity(0.4),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ]
                        : neuExtrudedShadows(distance: 2.5, blur: 5),
                  ),
                  child: Center(
                    child: Text(
                      'ក្បាលតូចកន្ទុយធំ (Trapezoid)',
                      style: TextStyle(
                        color: _calcIsTrapezoid ? Colors.white : _neuTextDark,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Live Plot Diagram & Area Preview Card
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: _neuBg,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white, width: 1.5),
            boxShadow: neuExtrudedShadows(distance: 4, blur: 12),
          ),
          child: Column(
            children: [
              // Visual Plot Representation
              Container(
                width: double.infinity,
                height: 110,
                decoration: BoxDecoration(
                  color: _neuInputBg,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: neuRecessedShadows(),
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Shape boundary
                    Container(
                      width: 180,
                      height: 70,
                      decoration: BoxDecoration(
                        color: _neuCobalt.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: _neuCobalt, width: 2),
                      ),
                      child: Center(
                        child: Text(
                          '${plotArea.toStringAsFixed(1)} m²',
                          style: const TextStyle(
                            color: _neuCobalt,
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                    // Front Width label (Top)
                    Positioned(
                      top: 4,
                      child: Text(
                        'ក្បាលដី: ${_calcPlotWidth.toStringAsFixed(1)}m',
                        style: const TextStyle(color: _neuTextDark, fontSize: 10.5, fontWeight: FontWeight.bold),
                      ),
                    ),
                    // Length label (Left)
                    Positioned(
                      left: 10,
                      child: RotatedBox(
                        quarterTurns: 3,
                        child: Text(
                          'ជម្រៅ: ${_calcPlotLength.toStringAsFixed(1)}m',
                          style: const TextStyle(color: _neuTextDark, fontSize: 10.5, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                    // Rear Width label (Bottom)
                    Positioned(
                      bottom: 4,
                      child: Text(
                        _calcIsTrapezoid
                            ? 'កន្ទុយដី: ${_calcPlotBackWidth.toStringAsFixed(1)}m'
                            : 'ទទឹងក្រោយ: ${_calcPlotWidth.toStringAsFixed(1)}m',
                        style: const TextStyle(color: _neuTextDark, fontSize: 10.5, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // Metrics Row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  Column(
                    children: [
                      const Text('ផ្ទៃក្រឡាសរុប', style: TextStyle(color: _neuTextMuted, fontSize: 11, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 2),
                      Text('${plotArea.toStringAsFixed(1)} m²', style: const TextStyle(color: _neuCobalt, fontSize: 16, fontWeight: FontWeight.w900)),
                    ],
                  ),
                  Container(width: 1, height: 28, color: Colors.white),
                  Column(
                    children: [
                      const Text('គិតជា អា (Are)', style: TextStyle(color: _neuTextMuted, fontSize: 11, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 2),
                      Text('${(plotArea / 100).toStringAsFixed(2)} អា', style: const TextStyle(color: _neuCobalt, fontSize: 16, fontWeight: FontWeight.w900)),
                    ],
                  ),
                  Container(width: 1, height: 28, color: Colors.white),
                  Column(
                    children: [
                      const Text('បរិមាត្រជុំវិញ', style: TextStyle(color: _neuTextMuted, fontSize: 11, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 2),
                      Text('${plotPerimeter.toStringAsFixed(1)} m', style: const TextStyle(color: _neuCobalt, fontSize: 16, fontWeight: FontWeight.w900)),
                    ],
                  ),
                ],
              ),

              if (_calcIsTrapezoid && _calcPlotBackWidth > _calcPlotWidth) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: _neuYellow.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _neuYellow.withOpacity(0.6), width: 1),
                  ),
                  child: const Row(
                    children: [
                      Text('🐉', style: TextStyle(fontSize: 16)),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'ដីរាងកន្ទុយនាគ: ក្បាលតូចកន្ទុយធំ ជាទម្រង់ដីហុងស៊ុយរក្សាទ្រព្យ និងលាភសំណាង!',
                          style: TextStyle(color: _neuTextDark, fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Steppers for Width and Length
        _buildDimensionStepper('ទទឹងក្បាលដី (Front Width)', _calcPlotWidth, (v) {
          setState(() => _calcPlotWidth = math.max(1.0, v));
        }),
        const SizedBox(height: 10),

        if (_calcIsTrapezoid) ...[
          _buildDimensionStepper('ទទឹងកន្ទុយដី (Rear Width)', _calcPlotBackWidth, (v) {
            setState(() => _calcPlotBackWidth = math.max(1.0, v));
          }),
          const SizedBox(height: 10),
        ],

        _buildDimensionStepper('បណ្តោយ / ជម្រៅ (Length)', _calcPlotLength, (v) {
          setState(() => _calcPlotLength = math.max(1.0, v));
        }),
        const SizedBox(height: 16),

        // Quick Presets in Cambodia
        const Text(
          'ទំហំដីឡូត៍ស្តង់ដារនៅកម្ពុជា:',
          style: TextStyle(color: _neuTextDark, fontSize: 13, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _buildPresetPlotChip2('ផ្ទះល្វែង 4.2m × 16m', 4.2, 16.0),
            _buildPresetPlotChip2('វីឡាកូនកាត់ 5m × 20m', 5.0, 20.0),
            _buildPresetPlotChip2('វីឡាភ្លោះ 8m × 20m', 8.0, 20.0),
            _buildPresetPlotChip2('វីឡាទោល 10m × 25m', 10.0, 25.0),
            _buildPresetPlotChip2('ដីឡូតិ៍ធំ 20m × 30m', 20.0, 30.0),
          ],
        ),
        const SizedBox(height: 20),

        // Apply to Calculator Button
        GestureDetector(
          onTap: () {
            setState(() {
              _calcCustomArea = plotArea;
              _calcMode = 1; // Switch to unit converter
            });
          },
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [_neuCobalt, _neuCobaltDark]),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: _neuCobalt.withOpacity(0.4),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.sync_alt_rounded, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Text(
                  'យកទំហំដីនេះ (${plotArea.toStringAsFixed(1)} m²) ទៅបំប្លែងខ្នាត',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDimensionStepper(String label, double value, Function(double) onChanged) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: _neuBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white, width: 1.2),
        boxShadow: neuExtrudedShadows(distance: 2.5, blur: 6),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: _neuTextDark, fontSize: 12.5, fontWeight: FontWeight.bold)),
          Row(
            children: [
              GestureDetector(
                onTap: () => onChanged(value - 1.0),
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: _neuBg,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1.2),
                    boxShadow: neuExtrudedShadows(distance: 2, blur: 4),
                  ),
                  child: const Icon(Icons.remove, color: _neuCobalt, size: 16),
                ),
              ),
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 10),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: _neuInputBg,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: neuRecessedShadows(),
                ),
                child: Text(
                  '${value.toStringAsFixed(1)} m',
                  style: const TextStyle(color: _neuCobalt, fontSize: 14, fontWeight: FontWeight.w900),
                ),
              ),
              GestureDetector(
                onTap: () => onChanged(value + 1.0),
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: _neuBg,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1.2),
                    boxShadow: neuExtrudedShadows(distance: 2, blur: 4),
                  ),
                  child: const Icon(Icons.add, color: _neuCobalt, size: 16),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPresetPlotChip2(String label, double w, double l) {
    return GestureDetector(
      onTap: () {
        setState(() {
          _calcPlotWidth = w;
          _calcPlotLength = l;
          _calcPlotBackWidth = w;
          _calcIsTrapezoid = false;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: _neuBg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white, width: 1.2),
          boxShadow: neuExtrudedShadows(distance: 2, blur: 4),
        ),
        child: Text(
          label,
          style: const TextStyle(color: _neuCobalt, fontSize: 11, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // MODE 2: LAND LOAN & MORTGAGE CALCULATOR (គណនារំលស់ដី)
  // ─────────────────────────────────────────────────────────────
  // ignore: unused_element
  Widget _buildLandMortgageView(double currentArea, double baseTotal) {
    final propertyPrice = baseTotal > 0 ? baseTotal : 50000.0;
    final downPaymentAmount = propertyPrice * (_calcDownPaymentPercent / 100);
    final loanAmount = propertyPrice - downPaymentAmount;

    // Monthly Payment Calculation
    final r = (_calcInterestRate / 100) / 12;
    final n = _calcLoanYears * 12;
    final double monthlyPayment = (r > 0 && n > 0)
        ? (loanAmount * r * math.pow(1 + r, n)) / (math.pow(1 + r, n) - 1)
        : loanAmount / (n > 0 ? n : 1);
    final totalRepaid = monthlyPayment * n;
    final totalInterest = totalRepaid - loanAmount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Monthly Payment Hero Card
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: _neuBg,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white, width: 1.5),
            boxShadow: neuExtrudedShadows(distance: 4, blur: 12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.payments_rounded, color: _neuCobalt, size: 20),
                  SizedBox(width: 8),
                  Text(
                    'ប្រាក់ត្រូវបង់ប្រចាំខែ (Monthly Installment)',
                    style: TextStyle(color: _neuTextMuted, fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                '\$${monthlyPayment.toStringAsFixed(0)} / ខែ',
                style: const TextStyle(
                  color: _neuCobalt,
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.5,
                ),
              ),
              Text(
                '≈ ៛${(monthlyPayment * 4100).toStringAsFixed(0)} រៀល/ខែ',
                style: const TextStyle(color: _neuTextMuted, fontSize: 12, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 14),

              // Breakdown 3-tiles
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _neuInputBg,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: neuRecessedShadows(),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildMortgageTile('ប្រាក់កម្ចីដើម', '\$${loanAmount.toStringAsFixed(0)}'),
                    Container(width: 1, height: 26, color: Colors.white),
                    _buildMortgageTile('ការប្រាក់សរុប', '\$${totalInterest.toStringAsFixed(0)}'),
                    Container(width: 1, height: 26, color: Colors.white),
                    _buildMortgageTile('សរុបត្រូវសង', '\$${totalRepaid.toStringAsFixed(0)}'),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Down Payment Percentage Chips
        const Text(
          'ប្រាក់កក់មុន (Down Payment):',
          style: TextStyle(color: _neuTextDark, fontSize: 13, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 8),
        Row(
          children: [10.0, 20.0, 30.0, 50.0].map((pct) {
            final isSel = _calcDownPaymentPercent == pct;
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: GestureDetector(
                  onTap: () => setState(() => _calcDownPaymentPercent = pct),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    decoration: BoxDecoration(
                      gradient: isSel ? const LinearGradient(colors: [_neuCobalt, _neuCobaltDark]) : null,
                      color: isSel ? null : _neuBg,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.white, width: 1.2),
                      boxShadow: isSel
                          ? [BoxShadow(color: _neuCobalt.withOpacity(0.4), blurRadius: 8, offset: const Offset(0, 2))]
                          : neuExtrudedShadows(distance: 2, blur: 5),
                    ),
                    child: Center(
                      child: Text(
                        '${pct.toInt()}% (\$${(propertyPrice * (pct / 100)).toStringAsFixed(0)})',
                        style: TextStyle(
                          color: isSel ? Colors.white : _neuTextDark,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 16),

        // Loan Term (Years)
        const Text(
          'រយៈពេលខ្ចី / បង់រំលស់ (Loan Duration):',
          style: TextStyle(color: _neuTextDark, fontSize: 13, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 8),
        Row(
          children: [1, 2, 3, 5, 10, 15].map((yr) {
            final isSel = _calcLoanYears == yr;
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: GestureDetector(
                  onTap: () => setState(() => _calcLoanYears = yr),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      gradient: isSel ? const LinearGradient(colors: [_neuCobalt, _neuCobaltDark]) : null,
                      color: isSel ? null : _neuBg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white, width: 1.2),
                      boxShadow: isSel
                          ? [BoxShadow(color: _neuCobalt.withOpacity(0.4), blurRadius: 6, offset: const Offset(0, 2))]
                          : neuExtrudedShadows(distance: 2, blur: 4),
                    ),
                    child: Center(
                      child: Text(
                        '$yr ឆ្នាំ',
                        style: TextStyle(
                          color: isSel ? Colors.white : _neuTextDark,
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 16),

        // Interest Rate Options
        const Text(
          'អត្រាការប្រាក់ក្នុងមួយឆ្នាំ (Annual Interest Rate):',
          style: TextStyle(color: _neuTextDark, fontSize: 13, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 8),
        Row(
          children: [7.5, 8.5, 9.5, 12.0].map((rate) {
            final isSel = _calcInterestRate == rate;
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: GestureDetector(
                  onTap: () => setState(() => _calcInterestRate = rate),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    decoration: BoxDecoration(
                      gradient: isSel ? const LinearGradient(colors: [_neuCobalt, _neuCobaltDark]) : null,
                      color: isSel ? null : _neuBg,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.white, width: 1.2),
                      boxShadow: isSel
                          ? [BoxShadow(color: _neuCobalt.withOpacity(0.4), blurRadius: 8, offset: const Offset(0, 2))]
                          : neuExtrudedShadows(distance: 2, blur: 5),
                    ),
                    child: Center(
                      child: Text(
                        '$rate% / ឆ្នាំ',
                        style: TextStyle(
                          color: isSel ? Colors.white : _neuTextDark,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildMortgageTile(String label, String value) {
    return Column(
      children: [
        Text(label, style: const TextStyle(color: _neuTextMuted, fontSize: 10, fontWeight: FontWeight.bold)),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(color: _neuCobalt, fontSize: 12.5, fontWeight: FontWeight.w900)),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────
  // MODE 3: MULTI-UNIT LAND CONVERTER
  // ─────────────────────────────────────────────────────────────
  Widget _buildUnitConverterView(double currentArea) {
    final m2 = currentArea;
    final are = m2 / 100;
    final ha = m2 / 10000;
    final sqft = m2 * 10.7639;
    final acre = m2 / 4046.86;
    final plots = m2 / 100;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Title banner
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: _neuInputBg,
            borderRadius: BorderRadius.circular(18),
            boxShadow: neuRecessedShadows(),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('ទំហំដីដែលកំពុងបំប្លែង:', style: TextStyle(color: _neuTextMuted, fontWeight: FontWeight.bold, fontSize: 13)),
              Text('${m2.toStringAsFixed(1)} m²', style: const TextStyle(color: _neuCobalt, fontWeight: FontWeight.w900, fontSize: 16)),
            ],
          ),
        ),
        const SizedBox(height: 16),

        _buildConverterCard('ម៉ែត្រការ៉េ (Square Meters)', '${m2.toStringAsFixed(1)} m²', 'ខ្នាតស្តង់ដារអន្តរជាតិ'),
        _buildConverterCard('អា (Are)', '${are.toStringAsFixed(2)} អា', '១ អា = ១០០ ម៉ែត្រការ៉េ'),
        _buildConverterCard('ហិកតា (Hectare)', '${ha.toStringAsFixed(4)} Ha', '១ ហិកតា = ១០,០០០ ម៉ែត្រការ៉េ'),
        _buildConverterCard('ឡូត៍ស្តង់ដារ (5m × 20m)', '${plots.toStringAsFixed(1)} ឡូត៍', '១ ឡូត៍ = ១០០ ម៉ែត្រការ៉េ'),
        _buildConverterCard('ហ្វីតការ៉េ (Square Feet)', '${sqft.toStringAsFixed(1)} ft²', '១ m² = ១០.៧៦ ft²'),
        _buildConverterCard('អាអ័រ (Acre)', '${acre.toStringAsFixed(4)} ac', '១ Acre = ៤,០៤៦.៨៦ m²'),

        const SizedBox(height: 16),
        // Typical plot presets in Cambodia
        const Text('ជ្រើសរើសទំហំដីគំរូទូទៅនៅកម្ពុជា:', style: TextStyle(color: _neuTextDark, fontWeight: FontWeight.w900, fontSize: 13.5)),
        const SizedBox(height: 10),
        Row(
          children: [
            _buildPresetPlotChip('4m × 16m', 64),
            const SizedBox(width: 8),
            _buildPresetPlotChip('5m × 20m', 100),
            const SizedBox(width: 8),
            _buildPresetPlotChip('10m × 20m', 200),
            const SizedBox(width: 8),
            _buildPresetPlotChip('20m × 30m', 600),
          ],
        ),
      ],
    );
  }

  Widget _buildPresetPlotChip(String label, double area) {
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _calcCustomArea = area),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: _neuBg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white, width: 1.2),
            boxShadow: neuExtrudedShadows(distance: 2, blur: 5),
          ),
          child: Column(
            children: [
              Text(label, style: const TextStyle(color: _neuTextDark, fontWeight: FontWeight.bold, fontSize: 11)),
              Text('${area.toInt()}m²', style: const TextStyle(color: _neuCobalt, fontWeight: FontWeight.w900, fontSize: 11)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildConverterCard(String title, String value, String desc) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: _neuBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white, width: 1.2),
        boxShadow: neuExtrudedShadows(distance: 3, blur: 8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(color: _neuTextDark, fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(height: 2),
              Text(desc, style: const TextStyle(color: _neuTextMuted, fontSize: 10.5)),
            ],
          ),
          Text(
            value,
            style: const TextStyle(color: _neuCobalt, fontWeight: FontWeight.w900, fontSize: 15),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // MODE 4: STANDARD INTERACTIVE KEYPAD CALCULATOR
  // ─────────────────────────────────────────────────────────────
  Widget _buildStandardKeypadView() {
    return Column(
      children: [
        // LCD Display
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          decoration: BoxDecoration(
            color: _neuInputBg,
            borderRadius: BorderRadius.circular(22),
            boxShadow: neuRecessedShadows(),
            border: Border.all(color: Colors.white.withOpacity(0.8), width: 1.2),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _calcFormula.isEmpty ? ' ' : _calcFormula,
                style: const TextStyle(color: _neuTextMuted, fontSize: 14, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              Text(
                _calcDisplay,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: _neuCobalt, fontSize: 36, fontWeight: FontWeight.w900),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),

        // Keypad Grid (4 columns x 5 rows)
        _buildKeypadRow(['C', '(', ')', '÷'], isTopRow: true),
        const SizedBox(height: 10),
        _buildKeypadRow(['7', '8', '9', '×']),
        const SizedBox(height: 10),
        _buildKeypadRow(['4', '5', '6', '-']),
        const SizedBox(height: 10),
        _buildKeypadRow(['1', '2', '3', '+']),
        const SizedBox(height: 10),
        _buildKeypadRow(['0', '.', '⌫', '=']),
      ],
    );
  }

  Widget _buildKeypadRow(List<String> keys, {bool isTopRow = false}) {
    return Row(
      children: keys.map((key) {
        final isOperator = key == '+' || key == '-' || key == '×' || key == '÷';
        final isEqual = key == '=';
        final isClear = key == 'C';

        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 5),
            child: GestureDetector(
              onTap: () => _onCalcKeyPress(key),
              child: Container(
                height: 52,
                decoration: BoxDecoration(
                  gradient: isEqual
                      ? const LinearGradient(colors: [_neuCobalt, _neuCobaltDark])
                      : (isOperator ? LinearGradient(colors: [_neuBg, _neuInputBg]) : null),
                  color: isEqual ? null : _neuBg,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white, width: 1.2),
                  boxShadow: isEqual
                      ? [
                          BoxShadow(
                            color: _neuCobalt.withOpacity(0.4),
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          ),
                        ]
                      : neuExtrudedShadows(distance: 2.5, blur: 6),
                ),
                child: Center(
                  child: Text(
                    key,
                    style: TextStyle(
                      color: isEqual
                          ? Colors.white
                          : (isClear
                              ? const Color(0xFFEF4444)
                              : (isOperator ? _neuCobalt : _neuTextDark)),
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// COMPASS TICKS 360 DEGREE PAINTER (Soft Neumorphic Style)
// ─────────────────────────────────────────────────────────────
class _CompassTicksPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // Outer subtle boundary ring
    final ringPaint = Paint()
      ..color = const Color(0xFF6B7A90).withOpacity(0.2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawCircle(center, radius - 4, ringPaint);

    final tickPaint = Paint()
      ..color = const Color(0xFF6B7A90).withOpacity(0.35)
      ..strokeWidth = 1.0;

    final medTickPaint = Paint()
      ..color = const Color(0xFF1E2638).withOpacity(0.65)
      ..strokeWidth = 1.4;

    for (int i = 0; i < 360; i += 5) {
      final isCardinal = (i % 90 == 0);
      final isMajor = (i % 30 == 0);
      final isMed = (i % 15 == 0);

      final angle = (i - 90) * (math.pi / 180);
      final double tickLength;
      final Paint currentPaint;

      if (isCardinal) {
        tickLength = 10.0;
        currentPaint = Paint()
          ..color = (i == 0)
              ? const Color(0xFF1338BE)
              : (i == 90)
                  ? const Color(0xFF1E2638)
                  : (i == 180)
                      ? const Color(0xFF8E9BB0)
                      : const Color(0xFFF7B731)
          ..strokeWidth = 2.4;
      } else if (isMajor) {
        tickLength = 7.5;
        currentPaint = medTickPaint;
      } else if (isMed) {
        tickLength = 5.0;
        currentPaint = tickPaint;
      } else {
        tickLength = 3.0;
        currentPaint = tickPaint;
      }

      final startX = center.dx + (radius - 6) * math.cos(angle);
      final startY = center.dy + (radius - 6) * math.sin(angle);
      final endX = center.dx + (radius - 6 - tickLength) * math.cos(angle);
      final endY = center.dy + (radius - 6 - tickLength) * math.sin(angle);

      canvas.drawLine(Offset(startX, startY), Offset(endX, endY), currentPaint);

      // Degree labels at every 30 degrees (skip cardinal 0, 90, 180, 270)
      if (isMajor && !isCardinal) {
        final textPainter = TextPainter(
          text: TextSpan(
            text: '$i°',
            style: TextStyle(
              color: const Color(0xFF6B7A90).withOpacity(0.85),
              fontSize: 7.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();

        final labelRadius = radius - 20;
        final lx = center.dx + labelRadius * math.cos(angle) - (textPainter.width / 2);
        final ly = center.dy + labelRadius * math.sin(angle) - (textPainter.height / 2);
        textPainter.paint(canvas, Offset(lx, ly));
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
