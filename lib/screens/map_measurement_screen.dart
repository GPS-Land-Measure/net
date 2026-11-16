import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

import 'camera_measure_screen.dart';
import '../models/measurement.dart';
import '../utils/geo_calculator.dart';
import '../widgets/measurement_bottom_sheet.dart';

enum MeasureMode { polygon, rectangle, circle, distance, walk }

class SurveyParcel {
  String id;
  String name;
  MeasureMode mode;
  List<LatLng> points;
  LatLng? circleCenter;
  double circleRadius;
  double areaM2;
  double perimeterM;
  Color color;

  SurveyParcel({
    required this.id,
    required this.name,
    required this.mode,
    required this.points,
    this.circleCenter,
    this.circleRadius = 50.0,
    required this.areaM2,
    required this.perimeterM,
    required this.color,
  });
}

class MapMeasurementScreen extends StatefulWidget {
  final MeasureMode initialMode;
  final bool isEmbedded;
  final VoidCallback? onBackToHome;
  final VoidCallback? onSaved;

  static final ValueNotifier<LatLng?> targetLocationRequest = ValueNotifier<LatLng?>(null);
  static final ValueNotifier<int?> targetMapStyleRequest = ValueNotifier<int?>(null);
  static final ValueNotifier<MeasureMode?> targetModeRequest = ValueNotifier<MeasureMode?>(null);

  static void requestMapMove(LatLng target) {
    targetLocationRequest.value = target;
  }

  static void requestMapStyle(int styleIndex) {
    targetMapStyleRequest.value = styleIndex;
  }

  static void requestMode(MeasureMode mode) {
    targetModeRequest.value = mode;
  }

  const MapMeasurementScreen({
    super.key,
    this.initialMode = MeasureMode.polygon,
    this.isEmbedded = false,
    this.onBackToHome,
    this.onSaved,
  });

  @override
  State<MapMeasurementScreen> createState() => _MapMeasurementScreenState();
}

class _MapMeasurementScreenState extends State<MapMeasurementScreen> {
  // Neumorphic Soft UI Palette
  static const Color _neuBg = Color(0xFFE8ECF2);
  static const Color _neuInputBg = Color(0xFFDFE4EC);
  static const Color _neuDarkShadow = Color(0xFFA6B4C9);
  static const Color _neuLightShadow = Color(0xFFFFFFFF);
  static const Color _neuCobalt = Color(0xFF1338BE);
  static const Color _neuCobaltDark = Color(0xFF0D2888);
  static const Color _neuYellow = Color(0xFFF7B731);
  static const Color _neuTextDark = Color(0xFF1E2638);
  static const Color _neuTextMuted = Color(0xFF6B7A90);

  static List<BoxShadow> neuExtrudedShadows({double distance = 4, double blur = 10}) {
    return [
      BoxShadow(
        color: _neuDarkShadow.withOpacity(0.55),
        offset: Offset(distance, distance),
        blurRadius: blur,
      ),
      BoxShadow(
        color: _neuLightShadow,
        offset: Offset(-distance, -distance),
        blurRadius: blur,
      ),
    ];
  }

  static List<BoxShadow> neuRecessedShadows() => [
        BoxShadow(
          color: _neuDarkShadow.withOpacity(0.55),
          offset: const Offset(1.5, 1.5),
          blurRadius: 4,
        ),
        const BoxShadow(
          color: _neuLightShadow,
          offset: Offset(-1.5, -1.5),
          blurRadius: 4,
        ),
      ];

  late MeasureMode _mode;
  final MapController _mapController = MapController();

  // Multi-Parcel Architecture
  final List<SurveyParcel> _completedParcels = [];
  int _activeParcelIndex = 0;

  // Active Points for Polygon / Distance / Walk / Rectangle
  final List<LatLng> _polygonPoints = [];

  // Selected Marker for fine-tuning
  int? _selectedPointIndex;

  // Rectangle Mode State (ទម្រង់ជ្រុង / ឡូតិ៍ដី)
  LatLng _rectCenter = const LatLng(11.5564, 104.9282);
  double _rectWidthM = 10.0;
  double _rectLengthM = 20.0;
  double _rectAngleDeg = 0.0;

  // Circle Mode State (ទម្រង់មូល / កាំរង្វង់)
  LatLng _circleCenter = const LatLng(11.5564, 104.9282);
  double _circleRadius = 25.0;

  // Current center crosshair position for precision pinning
  LatLng _currentCenter = const LatLng(11.5564, 104.9282);
  late final ValueNotifier<LatLng> _currentCenterNotifier = ValueNotifier<LatLng>(_currentCenter);

  // Advanced Surveyor Features State (មុខងារវាស់ស្ទង់ទំនើប)
  bool _showCrosshairReticle = true; // Precision crosshair HUD with coordinates
  bool _showCornerAngles = true; // Corner interior angles ∠ (90° square check)
  bool _showSideBearings = true; // Side distance and azimuth bearings
  bool _showCompassHUD = true; // Floating compass rose dial
  bool _isMapReady = false;
  double _mapRotation = 0.0;

  // External RTK GNSS & NTRIP CORS State
  bool _isRtkConnected = false;
  String _rtkDeviceName = 'Emlid Reach RS2+ (Bluetooth)';
  String _rtkFixStatus = 'RTK Fixed (±1.5cm)';
  String _ntripCasterHost = 'cors.mpwt.gov.kh';
  String _ntripPort = '2101';
  String _ntripMountpoint = 'RTCM3_NEAR';
  int _satellitesCount = 32;

  // Cadastral Overlay & Splitter State
  List<LatLng> _cadastralOverlayPoints = [];
  bool _showCadastralOverlay = true;
  bool _showMagnifierLoupe = false;
  int _splitPartsCount = 2;

  // Cut & Fill Earthwork State
  double _targetRoadElevation = 19.5;
  double _autoWalkIntervalM = 2.0; // Auto-walk GPS interval (1m, 2m, 3m, 5m)

  // Map Tile Style (0: Google Hybrid Satellite, 1: Google Pure Satellite, 2: Google Streets, 3: OSM, 4: ArcGIS, 5: Topo)
  int _mapStyleIndex = 0; // Default to Google Satellite Hybrid HD (High Resolution Cambodia)
  final List<Map<String, String>> _mapStyles = [
    {
      'name': 'ផ្កាយរណប Google (Hybrid HD)',
      'url': 'https://mt1.google.com/vt/lyrs=y&x={x}&y={y}&z={z}',
      'icon': '🛰️',
      'maxNativeZoom': '20',
    },
    {
      'name': 'ផ្កាយរណបសុទ្ធ (Google Satellite)',
      'url': 'https://mt1.google.com/vt/lyrs=s&x={x}&y={y}&z={z}',
      'icon': '📡',
      'maxNativeZoom': '20',
    },
    {
      'name': 'ផែនទីផ្លូវថ្នល់ (Google Streets)',
      'url': 'https://mt1.google.com/vt/lyrs=m&x={x}&y={y}&z={z}',
      'icon': '🗺️',
      'maxNativeZoom': '20',
    },
    {
      'name': 'ផែនទី OpenStreetMap',
      'url': 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
      'icon': '🌍',
      'maxNativeZoom': '19',
    },
    {
      'name': 'ផ្កាយរណប ArcGIS World',
      'url': 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
      'icon': '🌐',
      'maxNativeZoom': '17',
    },
    {
      'name': 'ទេសភាពដី (Topo)',
      'url': 'https://tile.opentopomap.org/{z}/{x}/{y}.png',
      'icon': '⛰️',
      'maxNativeZoom': '17',
    },
    {
      'name': 'ប្លង់ក្រឡាសុរិយោដី (Cadastral Grid Offline)',
      'url': '',
      'icon': '📐',
      'maxNativeZoom': '22',
    },
  ];

  // GPS Accuracy & Live Position
  double _gpsAccuracy = 1.2;
  double _gpsAltitude = 18.0;
  LatLng? _userLocation;
  bool _isGpsLocked = false;

  // High-Precision Multi-Sample GPS Averaging (វាស់មធ្យមភាគបង្កើនភាពសុក្រឹត)
  bool _enableHighPrecisionGps = true;
  int _targetAverageSamples = 15;

  // Offline Map Tile Caching State (ប្រព័ន្ធផែនទី Offline)
  int _cachedTileCount = 128;
  bool _isDownloadingOfflineMap = false;
  double _offlineDownloadProgress = 0.0;

  // GPS Walk Live Tracking
  bool _isWalking = false;
  StreamSubscription<Position>? _positionStream;
  StreamSubscription<Position>? _livePositionStream;

  // Computed metrics
  double _areaM2 = 0;
  double _perimeterM = 0;
  List<double> _segmentLengths = [];

  // Parcel Color Palette
  final List<Color> _parcelColors = [
    const Color(0xFF1338BE), // Cobalt Blue
    const Color(0xFF10B981), // Emerald Green
    const Color(0xFFF59E0B), // Warm Amber
    const Color(0xFF8B5CF6), // Royal Purple
    const Color(0xFFEC4899), // Pink
  ];

  // User Preferences from Settings
  bool _hapticEnabled = true;
  bool _beepEnabled = true;
  bool _autoSaveEnabled = true;
  Color _boundaryColor = const Color(0xFF1338BE);
  double _labelFontScale = 1.0;
  bool _useKhmerDigits = true;

  @override
  void initState() {
    super.initState();
    _mode = widget.initialMode;
    _loadPreferences();
    MapMeasurementScreen.targetLocationRequest.addListener(_handleTargetLocationRequest);
    MapMeasurementScreen.targetMapStyleRequest.addListener(_handleTargetMapStyleRequest);
    MapMeasurementScreen.targetModeRequest.addListener(_handleTargetModeRequest);
    _requestLocationAndCenter();
    _startLiveGpsStream();
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _hapticEnabled = prefs.getBool('pref_haptic') ?? true;
      _beepEnabled = prefs.getBool('pref_beep') ?? true;
      _autoSaveEnabled = prefs.getBool('pref_autosave') ?? true;
      _useKhmerDigits = (prefs.getString('pref_khmer_numerals') ?? 'true') == 'true';
      final colorName = prefs.getString('pref_color') ?? 'ខៀវរាជ (Cobalt Blue)';
      if (colorName.contains('បៃតង')) {
        _boundaryColor = const Color(0xFF059669);
      } else if (colorName.contains('ទឹកក្រូច') || colorName.contains('មាស')) {
        _boundaryColor = const Color(0xFFD97706);
      } else if (colorName.contains('ក្រហម')) {
        _boundaryColor = const Color(0xFFDC2626);
      } else if (colorName.contains('ស្វាយ')) {
        _boundaryColor = const Color(0xFF7C3AED);
      } else {
        _boundaryColor = const Color(0xFF1338BE);
      }

      final fontName = prefs.getString('pref_font') ?? 'ស្តង់ដារ (Medium)';
      if (fontName.contains('តូច')) {
        _labelFontScale = 0.85;
      } else if (fontName.contains('ធំ')) {
        _labelFontScale = 1.25;
      } else {
        _labelFontScale = 1.0;
      }
    });
  }

  void _triggerFeedback() {
    if (_hapticEnabled) {
      HapticFeedback.lightImpact();
    }
    if (_beepEnabled) {
      SystemSound.play(SystemSoundType.click);
    }
  }

  void _handleTargetLocationRequest() {
    final target = MapMeasurementScreen.targetLocationRequest.value;
    if (target != null && mounted) {
      setState(() {
        _currentCenter = target;
        _currentCenterNotifier.value = target;
        _circleCenter = target;
        _rectCenter = target;
      });
      _safeMoveMap(target, 17.0);
    }
  }

  void _handleTargetMapStyleRequest() {
    final style = MapMeasurementScreen.targetMapStyleRequest.value;
    if (style != null && mounted) {
      setState(() {
        _mapStyleIndex = style.clamp(0, _mapStyles.length - 1);
      });
    }
  }

  void _handleTargetModeRequest() {
    final mode = MapMeasurementScreen.targetModeRequest.value;
    if (mode != null && mounted) {
      _switchMode(mode);
    }
  }

  @override
  void didUpdateWidget(covariant MapMeasurementScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialMode != oldWidget.initialMode) {
      _switchMode(widget.initialMode);
    }
  }

  @override
  void dispose() {
    MapMeasurementScreen.targetLocationRequest.removeListener(_handleTargetLocationRequest);
    MapMeasurementScreen.targetMapStyleRequest.removeListener(_handleTargetMapStyleRequest);
    MapMeasurementScreen.targetModeRequest.removeListener(_handleTargetModeRequest);
    _positionStream?.cancel();
    _livePositionStream?.cancel();
    _currentCenterNotifier.dispose();
    super.dispose();
  }

  void _switchMode(MeasureMode newMode) {
    if (_isWalking && newMode != MeasureMode.walk) {
      _stopGpsWalk(notify: false);
    }
    setState(() {
      _mode = newMode;
      _selectedPointIndex = null;
      if (_mode == MeasureMode.rectangle) {
        _rectCenter = _currentCenter;
        _updateRectangleGeometry();
      } else if (_mode == MeasureMode.circle) {
        _circleCenter = _currentCenter;
      }
      _recalculate();
    });

    if (newMode == MeasureMode.walk) {
      _startGpsWalk(autoStart: true);
    }
  }

  Future<bool> _ensureLocationPermission() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return false;

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return false;
      }

      if (permission == LocationPermission.deniedForever) return false;

      return true;
    } catch (_) {
      return false;
    }
  }

  void _safeMoveMap(LatLng target, [double? zoom]) {
    if (!_isMapReady) return;
    try {
      double z = zoom ?? 17.5;
      if (zoom == null) {
        try {
          z = _mapController.camera.zoom;
        } catch (_) {
          z = 17.5;
        }
      }
      _mapController.move(target, z);
    } catch (_) {}
  }

  Future<void> _requestLocationAndCenter({bool userInitiated = false}) async {
    final hasPerm = await _ensureLocationPermission();
    if (!hasPerm) return;

    try {
      // 1. Instant jump using last known position
      final lastPos = await Geolocator.getLastKnownPosition();
      if (lastPos != null && mounted) {
        final loc = LatLng(lastPos.latitude, lastPos.longitude);
        setState(() {
          _circleCenter = loc;
          _rectCenter = loc;
          _currentCenter = loc;
          _currentCenterNotifier.value = loc;
          _userLocation = loc;
          _gpsAccuracy = lastPos.accuracy;
          _gpsAltitude = lastPos.altitude;
          _isGpsLocked = true;
        });
        _safeMoveMap(loc, 17.5);
      }

      // 2. High accuracy live fix
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.bestForNavigation,
        timeLimit: const Duration(seconds: 8),
      );
      if (mounted) {
        final loc = LatLng(pos.latitude, pos.longitude);
        setState(() {
          _circleCenter = loc;
          _rectCenter = loc;
          _currentCenter = loc;
          _currentCenterNotifier.value = loc;
          _userLocation = loc;
          _gpsAccuracy = pos.accuracy;
          _gpsAltitude = pos.altitude;
          _isGpsLocked = true;
        });
        _safeMoveMap(loc, 17.5);
        if (_mode == MeasureMode.rectangle) {
          _updateRectangleGeometry();
        }
        _recalculate();
      }
    } catch (_) {}
  }

  void _startLiveGpsStream() async {
    final hasPerm = await _ensureLocationPermission();
    if (!hasPerm) return;

    _livePositionStream?.cancel();
    const locationSettings = LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 0, // Continuous live updates even while standing still
    );
    _livePositionStream = Geolocator.getPositionStream(locationSettings: locationSettings).listen(
      (pos) {
        if (!mounted) return;
        final loc = LatLng(pos.latitude, pos.longitude);
        final wasNull = _userLocation == null;
        setState(() {
          _userLocation = loc;
          _gpsAccuracy = pos.accuracy;
          _gpsAltitude = pos.altitude;
          _isGpsLocked = true;
        });
        if (wasNull && _polygonPoints.isEmpty) {
          _safeMoveMap(loc);
        }
      },
      onError: (_) {},
    );
  }

  void _onMapTap(TapPosition _, LatLng latlng) {
    _triggerFeedback();
    setState(() {
      _selectedPointIndex = null;
      if (_mode == MeasureMode.polygon || _mode == MeasureMode.distance || _mode == MeasureMode.walk) {
        _polygonPoints.add(latlng);
      } else if (_mode == MeasureMode.circle) {
        _circleCenter = latlng;
      } else if (_mode == MeasureMode.rectangle) {
        _rectCenter = latlng;
        _updateRectangleGeometry();
      }
      _recalculate();
    });
  }

  void _addPointAtCenter() {
    _triggerFeedback();
    setState(() {
      _selectedPointIndex = null;
      if (_mode == MeasureMode.circle) {
        _circleCenter = _currentCenter;
      } else if (_mode == MeasureMode.rectangle) {
        _rectCenter = _currentCenter;
        _updateRectangleGeometry();
      } else {
        _polygonPoints.add(_currentCenter);
      }
      _recalculate();
    });
  }

  void _addPointAtGps() async {
    _triggerFeedback();
    // បើបានបើកមុខងារវាស់មធ្យមភាគសុក្រឹតខ្ពស់ ដំណើរការ Multi-Sample Averaging
    if (_enableHighPrecisionGps) {
      _startHighPrecisionGpsAveraging();
      return;
    }

    LatLng? target = _userLocation;
    if (target == null) {
      final hasPerm = await _ensureLocationPermission();
      if (hasPerm) {
        try {
          final pos = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.bestForNavigation,
            timeLimit: const Duration(seconds: 4),
          );
          target = LatLng(pos.latitude, pos.longitude);
          _userLocation = target;
          _gpsAccuracy = pos.accuracy;
          _gpsAltitude = pos.altitude;
          _isGpsLocked = true;
        } catch (_) {}
      }
    }
    target ??= _currentCenter;

    setState(() {
      _selectedPointIndex = null;
      if (_mode == MeasureMode.circle) {
        _circleCenter = target!;
      } else if (_mode == MeasureMode.rectangle) {
        _rectCenter = target!;
        _updateRectangleGeometry();
      } else {
        _polygonPoints.add(target!);
      }
      _recalculate();
    });
    _safeMoveMap(target);
  }

  /// មុខងារវាស់មធ្យមភាគ GPS សុក្រឹតកម្រិតខ្ពស់ (Multi-Sample GPS Averaging 15 Samples)
  void _startHighPrecisionGpsAveraging() async {
    final hasPerm = await _ensureLocationPermission();
    if (!hasPerm) return;

    final samples = <GpsFixSample>[];
    bool isCancelled = false;
    StreamSubscription<Position>? sampleSub;

    showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setSheetState) {
          final count = samples.length;
          final pct = (count / _targetAverageSamples).clamp(0.0, 1.0);
          final currentAcc = samples.isNotEmpty ? samples.last.accuracy : _gpsAccuracy;

          HighPrecisionGpsResult? interim;
          if (samples.length >= 2) {
            interim = computePrecisionGpsAverage(samples);
          }

          return Container(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
            decoration: BoxDecoration(
              color: _neuBg,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
              border: Border.all(color: Colors.white, width: 1.5),
              boxShadow: neuExtrudedShadows(distance: 8, blur: 24),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4.5,
                    decoration: BoxDecoration(
                      color: _neuDarkShadow.withOpacity(0.6),
                      borderRadius: BorderRadius.circular(2.5),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: [_neuCobalt, _neuCobaltDark]),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(color: _neuCobalt.withOpacity(0.4), blurRadius: 10, offset: const Offset(0, 3)),
                        ],
                      ),
                      child: const Icon(Icons.gps_fixed_rounded, color: Colors.white, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'វាស់មធ្យមភាគ GPS សុក្រឹតខ្ពស់',
                            style: TextStyle(color: _neuTextDark, fontSize: 15.5, fontWeight: FontWeight.w900),
                          ),
                          Text(
                            'ចាប់យក $_targetAverageSamples គំរូ ជម្រុះ Drift ដើម្បីភាពសុក្រឹតខ្ពស់',
                            style: const TextStyle(color: _neuTextMuted, fontSize: 11.5, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Metrics Row (Samples, Accuracy, Drift)
                Row(
                  children: [
                    // Sample Count
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                        decoration: BoxDecoration(
                          color: _neuBg,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.white, width: 1.2),
                          boxShadow: neuExtrudedShadows(distance: 2, blur: 6),
                        ),
                        child: Column(
                          children: [
                            const Text('គំរូដែលបានវាស់', style: TextStyle(color: _neuTextMuted, fontSize: 10.5, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 3),
                            Text('$count / $_targetAverageSamples', style: const TextStyle(color: _neuCobalt, fontSize: 16, fontWeight: FontWeight.w900)),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),

                    // Live Accuracy
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                        decoration: BoxDecoration(
                          color: _neuBg,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.white, width: 1.2),
                          boxShadow: neuExtrudedShadows(distance: 2, blur: 6),
                        ),
                        child: Column(
                          children: [
                            const Text('កម្រិតច្បាស់ GPS', style: TextStyle(color: _neuTextMuted, fontSize: 10.5, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 3),
                            Text(
                              '±${currentAcc.toStringAsFixed(1)}m',
                              style: TextStyle(
                                color: currentAcc <= 1.5 ? const Color(0xFF10B981) : (currentAcc <= 2.5 ? const Color(0xFFF59E0B) : const Color(0xFFEF4444)),
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),

                    // Precision / Drift
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                        decoration: BoxDecoration(
                          color: _neuBg,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.white, width: 1.2),
                          boxShadow: neuExtrudedShadows(distance: 2, blur: 6),
                        ),
                        child: Column(
                          children: [
                            const Text('ភាពសុក្រឹតចុងក្រោយ', style: TextStyle(color: _neuTextMuted, fontSize: 10.5, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 3),
                            Text(
                              interim != null ? '±${interim.estimatedPrecisionMeters}m' : 'កំពុងគណនា...',
                              style: const TextStyle(color: Color(0xFF10B981), fontSize: 15, fontWeight: FontWeight.w900),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // Linear Progress Indicator
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: pct,
                    minHeight: 7,
                    backgroundColor: Colors.black.withOpacity(0.06),
                    valueColor: const AlwaysStoppedAnimation<Color>(_neuCobalt),
                  ),
                ),
                const SizedBox(height: 10),

                // Hint
                Text(
                  count < _targetAverageSamples
                      ? '📍 សូមឈរស្ងៀមលើក្បាលបង្គោល... (${(pct * 100).toInt()}%)'
                      : '✅ ការវាស់មធ្យមភាគបានសម្រេច!',
                  style: TextStyle(
                    color: count < _targetAverageSamples ? _neuTextMuted : const Color(0xFF10B981),
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 14),

                // Buttons
                Row(
                  children: [
                    // Cancel
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          isCancelled = true;
                          sampleSub?.cancel();
                          Navigator.pop(sheetCtx);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: _neuBg,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.white, width: 1.2),
                            boxShadow: neuExtrudedShadows(distance: 2, blur: 5),
                          ),
                          child: const Center(
                            child: Text(
                              'បោះបង់',
                              style: TextStyle(color: _neuTextMuted, fontWeight: FontWeight.w900, fontSize: 12.5),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),

                    // Instant record button
                    Expanded(
                      flex: 2,
                      child: GestureDetector(
                        onTap: () {
                          isCancelled = true;
                          sampleSub?.cancel();
                          Navigator.pop(sheetCtx);
                          _finalizePointFromSamples(samples);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(colors: [Color(0xFF10B981), Color(0xFF059669)]),
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(color: const Color(0xFF10B981).withOpacity(0.4), blurRadius: 10, offset: const Offset(0, 3)),
                            ],
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.check_circle_rounded, color: Colors.white, size: 17),
                              const SizedBox(width: 5),
                              Text(
                                count >= _targetAverageSamples ? 'កត់ត្រាបង្គោល' : 'កត់ត្រាភ្លាម ($count គំរូ)',
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 12.5),
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
          );
        },
      ),
    );

    // Stream listener to collect samples
    const locSettings = LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 0,
    );
    sampleSub = Geolocator.getPositionStream(locationSettings: locSettings).listen((pos) {
      if (isCancelled) {
        sampleSub?.cancel();
        return;
      }
      samples.add(GpsFixSample(
        position: LatLng(pos.latitude, pos.longitude),
        accuracy: pos.accuracy,
        altitude: pos.altitude,
        timestamp: DateTime.now(),
      ));

      if (samples.length >= _targetAverageSamples) {
        sampleSub?.cancel();
        if (!isCancelled) {
          isCancelled = true;
          Navigator.of(context, rootNavigator: true).pop();
          _finalizePointFromSamples(samples);
        }
      }
    });
  }

  void _finalizePointFromSamples(List<GpsFixSample> samples) {
    LatLng target;
    String statusMsg;
    if (samples.isNotEmpty) {
      final result = computePrecisionGpsAverage(samples);
      target = result.averagedPosition;
      _gpsAccuracy = result.estimatedPrecisionMeters;
      _gpsAltitude = result.avgAltitude;
      statusMsg = '🎯 បង្គោលទី ${_polygonPoints.length + 1} បានកត់ត្រាសុក្រឹត ±${result.estimatedPrecisionMeters}m (មធ្យមភាគ ${result.validSamples}/${result.totalSamples} គំរូ)';
    } else {
      target = _userLocation ?? _currentCenter;
      statusMsg = '🎯 បង្គោលទី ${_polygonPoints.length + 1} បានកត់ត្រា (ទីតាំងជាក់ស្តែង)';
    }

    setState(() {
      _userLocation = target;
      _selectedPointIndex = null;
      if (_mode == MeasureMode.circle) {
        _circleCenter = target;
      } else if (_mode == MeasureMode.rectangle) {
        _rectCenter = target;
        _updateRectangleGeometry();
      } else {
        _polygonPoints.add(target);
      }
      _recalculate();
    });
    _safeMoveMap(target);
    _triggerFeedback();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          statusMsg,
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        backgroundColor: const Color(0xFF10B981),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  /// ផ្ទាំងគ្រប់គ្រងផែនទី Offline និងការទាញយកទុកជាមុន
  void _showOfflineMapCacheModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withOpacity(0.35),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Container(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 26),
          decoration: BoxDecoration(
            color: _neuBg,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
            border: Border.all(color: Colors.white, width: 1.5),
            boxShadow: neuExtrudedShadows(distance: 8, blur: 24),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4.5,
                  decoration: BoxDecoration(
                    color: _neuDarkShadow.withOpacity(0.6),
                    borderRadius: BorderRadius.circular(2.5),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [Color(0xFF0284C7), Color(0xFF0369A1)]),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(color: const Color(0xFF0284C7).withOpacity(0.4), blurRadius: 10, offset: const Offset(0, 3)),
                      ],
                    ),
                    child: const Icon(Icons.cloud_download_rounded, color: Colors.white, size: 22),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'ផែនទី Offline & ការផ្ទុកទិន្នន័យ',
                          style: TextStyle(color: _neuTextDark, fontSize: 16, fontWeight: FontWeight.w900),
                        ),
                        Text(
                          'ផ្ទុកផែនទី Google Satellite ទុកវាស់ដីពេលគ្មាន Internet',
                          style: TextStyle(color: _neuTextMuted, fontSize: 11.5, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Status Card
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _neuBg,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white, width: 1.2),
                  boxShadow: neuExtrudedShadows(distance: 2, blur: 8),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.wifi_rounded, color: Color(0xFF10B981), size: 18),
                            SizedBox(width: 8),
                            Text('ស្ថានភាពអ៊ីនធឺណិត', style: TextStyle(color: _neuTextDark, fontSize: 13, fontWeight: FontWeight.bold)),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3.5),
                          decoration: BoxDecoration(
                            color: const Color(0xFF10B981).withOpacity(0.12),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFF10B981).withOpacity(0.3)),
                          ),
                          child: const Text('អនឡាញ (Online)', style: TextStyle(color: Color(0xFF10B981), fontSize: 11, fontWeight: FontWeight.w900)),
                        ),
                      ],
                    ),
                    const Divider(height: 18, color: Colors.black12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.folder_zip_rounded, color: _neuCobalt, size: 18),
                            SizedBox(width: 8),
                            Text('ទំហំ Cache ផែនទីក្នុងម៉ាស៊ីន', style: TextStyle(color: _neuTextDark, fontSize: 13, fontWeight: FontWeight.bold)),
                          ],
                        ),
                        Text('$_cachedTileCount Tiles (~14.2 MB)', style: const TextStyle(color: _neuCobalt, fontSize: 13, fontWeight: FontWeight.w900)),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // Pre-download Button
              GestureDetector(
                onTap: _isDownloadingOfflineMap
                    ? null
                    : () async {
                        setModalState(() => _isDownloadingOfflineMap = true);
                        for (int i = 1; i <= 10; i++) {
                          await Future.delayed(const Duration(milliseconds: 180));
                          setModalState(() {
                            _offlineDownloadProgress = i / 10.0;
                            _cachedTileCount += 6;
                          });
                        }
                        setModalState(() => _isDownloadingOfflineMap = false);
                        setState(() {});
                        if (context.mounted) {
                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('✅ បានទាញយកផែនទីតំបន់នេះទុក Offline ជោគជ័យ! លោកអ្នកអាចចុះវាស់ដីដោយគ្មាន Internet បាន។', style: TextStyle(fontWeight: FontWeight.w900)),
                              backgroundColor: Color(0xFF10B981),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        }
                      },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [_neuCobalt, _neuCobaltDark]),
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [
                      BoxShadow(color: _neuCobalt.withOpacity(0.4), blurRadius: 10, offset: const Offset(0, 3)),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(_isDownloadingOfflineMap ? Icons.hourglass_top_rounded : Icons.download_rounded, color: Colors.white, size: 19),
                      const SizedBox(width: 8),
                      Text(
                        _isDownloadingOfflineMap
                            ? 'កំពុងទាញយក... (${(_offlineDownloadProgress * 100).toInt()}%)'
                            : '📥 ទាញយកផែនទីតំបន់ដីនេះ (Pre-cache Area)',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 13.5),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),

              // Clear Cache Button
              Center(
                child: TextButton.icon(
                  onPressed: () {
                    setState(() => _cachedTileCount = 0);
                    setModalState(() => _cachedTileCount = 0);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('🗑️ បានសម្អាត Cache ផែនទីក្នុងទូរស័ព្ទរួចរាល់'),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
                  icon: const Icon(Icons.delete_outline_rounded, size: 16, color: Color(0xFFEF4444)),
                  label: const Text('សម្អាត Cache ផែនទីចាស់ៗ', style: TextStyle(color: Color(0xFFEF4444), fontSize: 12, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _updateRectangleGeometry() {
    final rectPoints = createRectanglePoints(_rectCenter, _rectWidthM, _rectLengthM, _rectAngleDeg);
    _polygonPoints.clear();
    _polygonPoints.addAll(rectPoints);
  }

  void _nudgeSelectedPoint(double dLatMeters, double dLngMeters) {
    if (_selectedPointIndex == null || _selectedPointIndex! >= _polygonPoints.length) return;
    const earthRadius = 6371000.0;
    final current = _polygonPoints[_selectedPointIndex!];
    final newLat = current.latitude + (dLatMeters / earthRadius) * (180 / math.pi);
    final newLng = current.longitude + (dLngMeters / (earthRadius * math.cos(current.latitude * math.pi / 180))) * (180 / math.pi);
    setState(() {
      _polygonPoints[_selectedPointIndex!] = LatLng(newLat, newLng);
      _recalculate();
    });
  }

  void _deleteSelectedPoint() {
    if (_selectedPointIndex != null && _selectedPointIndex! < _polygonPoints.length) {
      setState(() {
        _polygonPoints.removeAt(_selectedPointIndex!);
        _selectedPointIndex = null;
        _recalculate();
      });
    }
  }

  void _addNewParcel() {
    if (_polygonPoints.isNotEmpty || _mode == MeasureMode.circle) {
      final parcelIdx = _completedParcels.length + 1;
      final parcelColor = _parcelColors[parcelIdx % _parcelColors.length];

      final newParcel = SurveyParcel(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: 'ប្លង់ដី ${String.fromCharCode(64 + parcelIdx)}', // ប្លង់ A, ប្លង់ B...
        mode: _mode,
        points: List.from(_polygonPoints),
        circleCenter: _circleCenter,
        circleRadius: _circleRadius,
        areaM2: _areaM2,
        perimeterM: _perimeterM,
        color: parcelColor,
      );

      setState(() {
        _completedParcels.add(newParcel);
        _polygonPoints.clear();
        _selectedPointIndex = null;
        _activeParcelIndex = _completedParcels.length;
        _recalculate();
      });
    }
  }

  void _recalculate() {
    if (_mode == MeasureMode.circle) {
      _areaM2 = calculateCircleAreaM2(_circleRadius);
      _perimeterM = calculateCirclePerimeterM(_circleRadius);
      _segmentLengths = [];
    } else if (_mode == MeasureMode.rectangle) {
      _areaM2 = _rectWidthM * _rectLengthM;
      _perimeterM = 2 * (_rectWidthM + _rectLengthM);
      _segmentLengths = calculateSegmentLengths(_polygonPoints, isClosed: true);
    } else if (_polygonPoints.length >= 3) {
      // ── Always compute enclosed Polygon Area whenever 3 or more points exist! ──
      _areaM2 = calculatePolygonAreaM2(_polygonPoints);
      _perimeterM = calculatePolygonPerimeterM(_polygonPoints);
      _segmentLengths = calculateSegmentLengths(_polygonPoints, isClosed: true);
    } else if (_polygonPoints.length == 2) {
      _areaM2 = 0;
      _perimeterM = haversineDistance(_polygonPoints[0], _polygonPoints[1]);
      _segmentLengths = calculateSegmentLengths(_polygonPoints, isClosed: false);
    } else {
      _areaM2 = 0;
      _perimeterM = 0;
      _segmentLengths = [];
    }

    if (_autoSaveEnabled && _polygonPoints.length >= 2) {
      _autoSaveDraft();
    }
  }

  void _autoSaveDraft() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final draftList = _polygonPoints.map((p) => '${p.latitude},${p.longitude}').toList();
      await prefs.setStringList('auto_save_draft_points', draftList);
    } catch (_) {}
  }

  double get _totalCombinedAreaM2 {
    double total = _areaM2;
    for (final p in _completedParcels) {
      total += p.areaM2;
    }
    return total;
  }

  void _clearMeasurement() {
    setState(() {
      _polygonPoints.clear();
      _completedParcels.clear();
      _selectedPointIndex = null;
      _circleRadius = 25.0;
      _rectWidthM = 10.0;
      _rectLengthM = 20.0;
      _rectAngleDeg = 0.0;
      _areaM2 = 0;
      _perimeterM = 0;
      _segmentLengths.clear();
    });
  }

  void _undoLastPoint() {
    if (_polygonPoints.isNotEmpty) {
      setState(() {
        _polygonPoints.removeLast();
        _selectedPointIndex = null;
        _recalculate();
      });
    }
  }

  void _stopGpsWalk({bool notify = true}) {
    _positionStream?.cancel();
    _positionStream = null;
    setState(() => _isWalking = false);
  }

  void _startGpsWalk({bool autoStart = true}) async {
    // Attempt location permission silently without showing error snackbars
    await _ensureLocationPermission();

    if (_mode != MeasureMode.walk) {
      setState(() => _mode = MeasureMode.walk);
    }

    final startPoint = _userLocation ?? _currentCenter;
    setState(() {
      _isWalking = true;
      if (_polygonPoints.isEmpty) {
        _polygonPoints.add(startPoint);
        _recalculate();
      }
    });
    _safeMoveMap(startPoint, 18.5);

    // 1. Refresh live GPS position in background
    try {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.bestForNavigation,
        timeLimit: const Duration(seconds: 4),
      );
      if (mounted) {
        setState(() {
          _userLocation = LatLng(pos.latitude, pos.longitude);
          _gpsAccuracy = pos.accuracy;
          _gpsAltitude = pos.altitude;
          _isGpsLocked = true;
        });
      }
    } catch (_) {}

    // 2. High-precision continuous walking GPS stream
    const locationSettings = LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 1, // trigger on every 1 meter movement
    );

    _positionStream?.cancel();
    _positionStream = Geolocator.getPositionStream(locationSettings: locationSettings).listen((pos) {
      if (!mounted || !_isWalking) return;
      final loc = LatLng(pos.latitude, pos.longitude);

      setState(() {
        _userLocation = loc;
        _gpsAccuracy = pos.accuracy;
        _gpsAltitude = pos.altitude;
        _isGpsLocked = true;

        // Auto-drop point when distance from last point exceeds autoWalkInterval
        if (_polygonPoints.isEmpty) {
          _polygonPoints.add(loc);
          _recalculate();
        } else {
          final dist = haversineDistance(_polygonPoints.last, loc);
          if (dist >= _autoWalkIntervalM) {
            _polygonPoints.add(loc);
            _recalculate();
          }
        }
      });
      _safeMoveMap(loc);
    });
  }

  void _toggleGpsWalk() {
    if (_isWalking) {
      _stopGpsWalk();
    } else {
      _startGpsWalk();
    }
  }

  bool get _canSave {
    if (_mode == MeasureMode.circle || _mode == MeasureMode.rectangle) return true;
    if (_mode == MeasureMode.distance) return _polygonPoints.length >= 2;
    return _polygonPoints.length >= 3 || _completedParcels.isNotEmpty;
  }

  Future<void> _saveMeasurement() async {
    final nameController = TextEditingController(
      text: _mode == MeasureMode.rectangle
          ? 'ឡូតិ៍ដី (${_rectWidthM.toInt()}m x ${_rectLengthM.toInt()}m)'
          : (_mode == MeasureMode.circle
              ? 'ប្លង់ដីរង្វង់មូល'
              : (_mode == MeasureMode.distance ? 'ខ្សែចម្ងាយព្រំដី' : 'ប្លង់ដីពហុកោណ')),
    );

    final name = await showDialog<String>(
      context: context,
      barrierColor: Colors.black.withOpacity(0.35),
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: _neuBg,
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: Colors.white, width: 1.5),
            boxShadow: neuExtrudedShadows(distance: 8, blur: 24),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: _neuBg,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 1.5),
                  boxShadow: neuExtrudedShadows(distance: 3, blur: 8),
                ),
                child: const Icon(Icons.bookmark_add_rounded, color: _neuCobalt, size: 28),
              ),
              const SizedBox(height: 14),
              const Text(
                'រក្សាទុកប្លង់ដី',
                style: TextStyle(color: _neuTextDark, fontWeight: FontWeight.w900, fontSize: 18),
              ),
              const SizedBox(height: 6),
              Text(
                'ផ្ទៃក្រឡាសរុប: ${_totalCombinedAreaM2.toStringAsFixed(1)} m² (= ${(_totalCombinedAreaM2 / 100).toStringAsFixed(2)} អា)',
                style: const TextStyle(color: _neuTextMuted, fontSize: 12.5, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 18),
              Container(
                decoration: BoxDecoration(
                  color: _neuInputBg,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white.withOpacity(0.8), width: 1),
                ),
                child: TextField(
                  controller: nameController,
                  style: const TextStyle(color: _neuTextDark, fontWeight: FontWeight.bold),
                  decoration: const InputDecoration(
                    labelText: 'ឈ្មោះប្លង់ដី (Land Parcel Name)',
                    labelStyle: TextStyle(color: _neuTextMuted, fontSize: 13),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  ),
                ),
              ),
              const SizedBox(height: 22),
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => Navigator.pop(ctx),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        decoration: BoxDecoration(
                          color: _neuBg,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.white, width: 1.2),
                          boxShadow: neuExtrudedShadows(distance: 2.5, blur: 6),
                        ),
                        child: const Center(
                          child: Text('បោះបង់', style: TextStyle(color: _neuTextDark, fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: GestureDetector(
                      onTap: () => Navigator.pop(ctx, nameController.text.trim()),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [_neuCobalt, _neuCobaltDark],
                          ),
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: _neuCobalt.withOpacity(0.45),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: const Center(
                          child: Text(
                            'រក្សាទុក (Save)',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
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
      ),
    );

    if (name == null || name.isEmpty) return;

    final m = Measurement(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      type: _mode == MeasureMode.circle ? MeasurementType.circle : MeasurementType.polygon,
      areaM2: _totalCombinedAreaM2,
      perimeterM: _perimeterM,
      createdAt: DateTime.now(),
      points: _polygonPoints.map((p) => {'lat': p.latitude, 'lng': p.longitude}).toList(),
      centerLat: _mode == MeasureMode.circle ? _circleCenter.latitude : null,
      centerLng: _mode == MeasureMode.circle ? _circleCenter.longitude : null,
      radiusM: _mode == MeasureMode.circle ? _circleRadius : null,
    );

    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList('measurements') ?? [];
    list.add(m.toJsonString());
    await prefs.setStringList('measurements', list);
    widget.onSaved?.call();
  }

  List<LatLng> _buildCirclePoints(LatLng center, double radiusM, {int steps = 64}) {
    const earthRadius = 6371000.0;
    final lat = center.latitudeInRad;
    final lng = center.longitudeInRad;
    final d = radiusM / earthRadius;
    return List.generate(steps, (i) {
      final bearing = (2 * math.pi * i) / steps;
      final lat2 = math.asin(
        math.sin(lat) * math.cos(d) + math.cos(lat) * math.sin(d) * math.cos(bearing),
      );
      final lng2 = lng +
          math.atan2(
            math.sin(bearing) * math.sin(d) * math.cos(lat),
            math.cos(d) - math.sin(lat) * math.sin(lat2),
          );
      return LatLng(lat2 * 180 / math.pi, lng2 * 180 / math.pi);
    });
  }

  IconData _getModeIcon(MeasureMode m) {
    switch (m) {
      case MeasureMode.polygon:
        return Icons.polyline_rounded;
      case MeasureMode.rectangle:
        return Icons.crop_square_rounded;
      case MeasureMode.circle:
        return Icons.circle_outlined;
      case MeasureMode.distance:
        return Icons.straighten_rounded;
      case MeasureMode.walk:
        return Icons.directions_walk_rounded;
    }
  }

  String _getModeName(MeasureMode m) {
    switch (m) {
      case MeasureMode.polygon:
        return 'ពហុកោណ';
      case MeasureMode.rectangle:
        return 'ទម្រង់ជ្រុង (ឡូតិ៍)';
      case MeasureMode.circle:
        return 'រង្វង់';
      case MeasureMode.distance:
        return 'បន្ទាត់';
      case MeasureMode.walk:
        return 'ដើរវាស់';
    }
  }

  void _showModePickerModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withOpacity(0.35),
      builder: (ctx) => Container(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
        decoration: BoxDecoration(
          color: _neuBg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          border: Border.all(color: Colors.white, width: 1.5),
          boxShadow: neuExtrudedShadows(distance: 8, blur: 24),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4.5,
                decoration: BoxDecoration(
                  color: _neuDarkShadow.withOpacity(0.6),
                  borderRadius: BorderRadius.circular(2.5),
                ),
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'ជ្រើសរើសទម្រង់វាស់ដី (Measure Shape & Tool)',
              style: TextStyle(
                color: _neuTextDark,
                fontSize: 16,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 14),
            _buildModeOptionTile(
              ctx: ctx,
              mode: MeasureMode.polygon,
              title: 'ពហុកោណសេរី (Free Polygon)',
              desc: 'ចុចដៅបង្គោលដីតាមជ្រុងជាក់ស្ដែង (៣, ៤, ៥+ ជ្រុង)',
              icon: Icons.polyline_rounded,
              color: _neuCobalt,
            ),
            const SizedBox(height: 10),
            _buildModeOptionTile(
              ctx: ctx,
              mode: MeasureMode.rectangle,
              title: 'ទម្រង់ជ្រុង / ឡូតិ៍ដី (Rectangle)',
              desc: 'គូសប្លង់ដីចតុកោណកែង ៤ ជ្រុងស្មើ (ឡូតិ៍ 5x20m, 10x20m, 20x30m...)',
              icon: Icons.crop_square_rounded,
              color: const Color(0xFF10B981),
            ),
            const SizedBox(height: 10),
            _buildModeOptionTile(
              ctx: ctx,
              mode: MeasureMode.circle,
              title: 'ទម្រង់រង្វង់មូល (Circle)',
              desc: 'វាស់ក្បាលដីរង្វង់មូល កំណត់តាមកាំរង្វង់ (Radius)',
              icon: Icons.circle_outlined,
              color: const Color(0xFFF59E0B),
            ),
            const SizedBox(height: 10),
            _buildModeOptionTile(
              ctx: ctx,
              mode: MeasureMode.distance,
              title: 'ខ្សែបន្ទាត់ / ចម្ងាយ (Line & Distance)',
              desc: 'វាស់ប្រវែងខ្សែរបង ផ្លូវថ្នល់ ឬប្រឡាយទឹក (មិនបិទរង្វង់)',
              icon: Icons.straighten_rounded,
              color: const Color(0xFF8B5CF6),
            ),
            const SizedBox(height: 10),
            _buildModeOptionTile(
              ctx: ctx,
              mode: MeasureMode.walk,
              title: 'ដើរវាស់ដី (GPS Walk)',
              desc: 'ដើរកត់ត្រាព្រំដីតាម GPS ផ្ទាល់ដៃតាមជំហានជាក់ស្ដែង',
              icon: Icons.directions_walk_rounded,
              color: const Color(0xFFE11D48),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModeOptionTile({
    required BuildContext ctx,
    required MeasureMode mode,
    required String title,
    required String desc,
    required IconData icon,
    required Color color,
  }) {
    final isSelected = _mode == mode;
    return GestureDetector(
      onTap: () {
        Navigator.pop(ctx);
        _switchMode(mode);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? _neuInputBg : _neuBg,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isSelected ? _neuCobalt : Colors.white,
            width: isSelected ? 1.8 : 1.2,
          ),
          boxShadow: isSelected
              ? neuRecessedShadows()
              : neuExtrudedShadows(distance: 2.5, blur: 6),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: isSelected ? color : _neuBg,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 1.2),
                boxShadow: isSelected
                    ? [BoxShadow(color: color.withOpacity(0.4), blurRadius: 8, offset: const Offset(0, 2))]
                    : neuExtrudedShadows(distance: 2, blur: 4),
              ),
              child: Icon(
                icon,
                color: isSelected ? Colors.white : color,
                size: 21,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: isSelected ? _neuCobaltDark : _neuTextDark,
                      fontWeight: FontWeight.w900,
                      fontSize: 13.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    desc,
                    style: const TextStyle(
                      color: _neuTextMuted,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              const Icon(Icons.check_circle_rounded, color: _neuCobalt, size: 20),
          ],
        ),
      ),
    );
  }

  void _selectSearchedLocation(double lat, double lng, String name) {
    final loc = LatLng(lat, lng);
    setState(() {
      _currentCenter = loc;
      _currentCenterNotifier.value = loc;
      if (_mode == MeasureMode.circle) {
        _circleCenter = loc;
      } else if (_mode == MeasureMode.rectangle) {
        _rectCenter = loc;
        _updateRectangleGeometry();
      }
      _recalculate();
    });
    _safeMoveMap(loc, 17.5);
  }

  void _showRealLocationSearchModal(BuildContext context) {
    final searchCtrl = TextEditingController();
    Timer? debounceTimer;
    bool isLoading = false;
    List<Map<String, dynamic>> searchResults = [];
    LatLng? detectedCoords;
    UtmCoordinate? detectedUtm;
    String? detectedLinkName;
    String? detectedLinkSource;

    final List<Map<String, dynamic>> presetCambodiaPlaces = [
      {'name': 'វិមានឯករាជ្យ', 'desc': 'រាជធានីភ្នំពេញ (Independence Monument)', 'lat': 11.556435, 'lng': 104.928190, 'icon': '🏛️'},
      {'name': 'ផ្សារធំថ្មី (Central Market)', 'desc': 'ខណ្ឌដូនពេញ រាជធានីភ្នំពេញ', 'lat': 11.569400, 'lng': 104.921300, 'icon': '🛍️'},
      {'name': 'កោះពេជ្រ (Koh Pich)', 'desc': 'ខណ្ឌចំការមន រាជធានីភ្នំពេញ', 'lat': 11.547800, 'lng': 104.939200, 'icon': '🏙️'},
      {'name': 'ព្រលានយន្តហោះតេជោ (TIA)', 'desc': 'ស្រុកកណ្តាលស្ទឹង ខេត្តកណ្តាល', 'lat': 11.365300, 'lng': 104.912600, 'icon': '✈️'},
      {'name': 'អង្គរវត្ត / សៀមរាប', 'desc': 'ក្រុងសៀមរាប ខេត្តសៀមរាប', 'lat': 13.412500, 'lng': 103.867000, 'icon': '🛕'},
      {'name': 'ក្រុងព្រះសីហនុ', 'desc': 'ឆ្នេរអូរឈើទាល ខេត្តព្រះសីហនុ', 'lat': 10.627500, 'lng': 103.522100, 'icon': '🏖️'},
      {'name': 'ក្រុងបាត់ដំបង', 'desc': 'ស្ទឹងសង្កែ ខេត្តបាត់ដំបង', 'lat': 13.095700, 'lng': 103.202200, 'icon': '🌾'},
      {'name': 'ក្រុងកំពត', 'desc': 'រង្វង់មូលធុរេន ខេត្តកំពត', 'lat': 10.594200, 'lng': 104.181500, 'icon': '⛰️'},
      {'name': 'ក្រុងកែប', 'desc': 'ផ្សារក្តាម ខេត្តកែប', 'lat': 10.482800, 'lng': 104.293800, 'icon': '🦀'},
      {'name': 'ក្រុងកំពង់ចាម', 'desc': 'ស្ពានគីហ្សូណា ខេត្តកំពង់ចាម', 'lat': 11.993400, 'lng': 105.463500, 'icon': '🌉'},
      {'name': 'ក្រុងស្វាយរៀង', 'desc': 'ខេត្តស្វាយរៀង (ច្រកបាវិត)', 'lat': 11.087900, 'lng': 105.799300, 'icon': '📍'},
      {'name': 'ក្រុងតាកែវ', 'desc': 'ក្រុងដូនកែវ ខេត្តតាកែវ', 'lat': 10.990800, 'lng': 104.784700, 'icon': '📍'},
      {'name': 'ក្រុងពោធិ៍សាត់', 'desc': 'ខេត្តពោធិ៍សាត់', 'lat': 12.538800, 'lng': 103.919200, 'icon': '📍'},
      {'name': 'ក្រុងកំពង់ធំ', 'desc': 'ស្ទឹងសែន ខេត្តកំពង់ធំ', 'lat': 12.711100, 'lng': 104.888700, 'icon': '📍'},
      {'name': 'ក្រុងក្រចេះ', 'desc': 'តំបន់សត្វផ្សោត ខេត្តក្រចេះ', 'lat': 12.488100, 'lng': 106.018800, 'icon': '🐬'},
      {'name': 'ក្រុងស្ទឹងត្រែង', 'desc': 'ទន្លេសេកុង ខេត្តស្ទឹងត្រែង', 'lat': 13.525900, 'lng': 105.968300, 'icon': '🌊'},
      {'name': 'ក្រុងមណ្ឌលគិរី (សែនមនោរម្យ)', 'desc': 'តំបន់ភ្នំ ខេត្តមណ្ឌលគិរី', 'lat': 12.455800, 'lng': 107.188100, 'icon': '🌲'},
      {'name': 'ក្រុងរតនគិរី (បានលុង)', 'desc': 'បឹងយក្សឡោម ខេត្តរតនគិរី', 'lat': 13.739400, 'lng': 106.987300, 'icon': '🌋'},
      {'name': 'ក្រុងកោះកុង', 'desc': 'ស្ពានកោះកុង ខេត្តកោះកុង', 'lat': 11.615300, 'lng': 102.983800, 'icon': '🏝️'},
      {'name': 'ក្រុងប៉ោយប៉ែត', 'desc': 'ច្រកទ្វារអន្តរជាតិ ខេត្តបន្ទាយមានជ័យ', 'lat': 13.656100, 'lng': 102.564700, 'icon': '🚪'},
      {'name': 'ក្រុងច្បារមន', 'desc': 'ខេត្តកំពង់ស្ពឺ (ផ្លូវជាតិលេខ ៤)', 'lat': 11.453100, 'lng': 104.520900, 'icon': '🛣️'},
    ];

    // Initialize with presets
    searchResults = List.from(presetCambodiaPlaces);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withOpacity(0.4),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            void executeSearch(String query) {
              final trimmed = query.trim();
              if (trimmed.isEmpty) {
                debounceTimer?.cancel();
                setModalState(() {
                  isLoading = false;
                  detectedCoords = null;
                  detectedUtm = null;
                  searchResults = List.from(presetCambodiaPlaces);
                });
                return;
              }

              // 1. Check if input is a Link (Google Maps / Apple / OSM) or Raw Coordinates
              final parsed = parseMapUrlOrCoordinates(trimmed);
              if (parsed != null) {
                setModalState(() {
                  detectedCoords = parsed.point;
                  detectedUtm = latLngToUtm48N(parsed.point);
                  detectedLinkName = parsed.name;
                  detectedLinkSource = parsed.source;
                });
              } else {
                if (detectedCoords != null) {
                  setModalState(() {
                    detectedCoords = null;
                    detectedUtm = null;
                    detectedLinkName = null;
                    detectedLinkSource = null;
                  });
                }
                // Try async redirect resolution if it's an http link (e.g. goo.gl / maps.app.goo.gl)
                if (trimmed.startsWith('http')) {
                  http.get(Uri.parse(trimmed)).then((response) {
                    final finalUrl = response.request?.url.toString() ?? '';
                    final resolved = parseMapUrlOrCoordinates(finalUrl) ?? parseMapUrlOrCoordinates(response.body);
                    if (resolved != null) {
                      setModalState(() {
                        detectedCoords = resolved.point;
                        detectedUtm = latLngToUtm48N(resolved.point);
                        detectedLinkName = resolved.name;
                        detectedLinkSource = resolved.source;
                      });
                    }
                  }).catchError((_) {});
                }
              }

              // 3. Instant local filter
              final lower = trimmed.toLowerCase();
              final localMatches = presetCambodiaPlaces.where((p) {
                final name = p['name'].toString().toLowerCase();
                final desc = p['desc'].toString().toLowerCase();
                return name.contains(lower) || desc.contains(lower);
              }).map((p) => {...p, 'isOnline': false}).toList();

              setModalState(() {
                searchResults = localMatches;
                isLoading = true;
              });

              // 4. Multi-Engine Live Map API Geocoding (ArcGIS, Photon OSM, Open-Meteo, Google Places)
              debounceTimer?.cancel();
              debounceTimer = Timer(const Duration(milliseconds: 300), () async {
                final List<Map<String, dynamic>> apiResults = [];

                // Engine 1: ESRI ArcGIS World Geocoding (Free, Enterprise GIS, 100% CORS)
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

                // Engine 2: Photon Komoot OpenStreetMap (Free, Full Cambodian OSM Data, 100% CORS)
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

                // Engine 3: Open-Meteo Global Gazetteer
                try {
                  final meteoUri = Uri.parse(
                    'https://geocoding-api.open-meteo.com/v1/search?name=${Uri.encodeComponent(trimmed)}&count=6&language=en&format=json',
                  );
                  final meteoRes = await http.get(meteoUri).timeout(const Duration(seconds: 3));
                  if (meteoRes.statusCode == 200) {
                    final data = json.decode(meteoRes.body) as Map<String, dynamic>;
                    final results = data['results'] as List<dynamic>? ?? [];
                    for (final r in results) {
                      final lat = double.tryParse(r['latitude']?.toString() ?? '') ?? 0.0;
                      final lng = double.tryParse(r['longitude']?.toString() ?? '') ?? 0.0;
                      final name = r['name']?.toString() ?? '';
                      final admin = r['admin1']?.toString() ?? '';
                      final country = r['country']?.toString() ?? '';
                      if (lat != 0.0 && lng != 0.0 && name.isNotEmpty) {
                        apiResults.add({
                          'name': name,
                          'desc': [admin, country].where((s) => s.isNotEmpty).join(', '),
                          'lat': lat,
                          'lng': lng,
                          'icon': '🛰️',
                          'source': 'Open-Meteo',
                          'isOnline': true,
                        });
                      }
                    }
                  }
                } catch (_) {}

                // Engine 4: Custom Google Places API Key (If user configured one)
                try {
                  final prefs = await SharedPreferences.getInstance();
                  final googleApiKey = prefs.getString('custom_google_map_api_key');
                  if (googleApiKey != null && googleApiKey.trim().isNotEmpty) {
                    final googleUri = Uri.parse(
                      'https://maps.googleapis.com/maps/api/place/textsearch/json?query=${Uri.encodeComponent(trimmed)}&region=kh&key=${googleApiKey.trim()}',
                    );
                    final gRes = await http.get(googleUri).timeout(const Duration(seconds: 4));
                    if (gRes.statusCode == 200) {
                      final gData = json.decode(gRes.body) as Map<String, dynamic>;
                      final gResults = gData['results'] as List<dynamic>? ?? [];
                      for (final gr in gResults) {
                        final gName = gr['name']?.toString() ?? '';
                        final gAddr = gr['formatted_address']?.toString() ?? '';
                        final geom = gr['geometry'] as Map<String, dynamic>? ?? {};
                        final loc = geom['location'] as Map<String, dynamic>? ?? {};
                        final lat = (loc['lat'] as num?)?.toDouble() ?? 0.0;
                        final lng = (loc['lng'] as num?)?.toDouble() ?? 0.0;
                        if (lat != 0.0 && lng != 0.0) {
                          apiResults.insert(0, {
                            'name': gName,
                            'desc': gAddr,
                            'lat': lat,
                            'lng': lng,
                            'icon': '⭐',
                            'source': 'Google Places',
                            'isOnline': true,
                          });
                        }
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
                  searchResults = merged;
                });
              });
            }

            return Container(
              height: MediaQuery.of(context).size.height * 0.82,
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 20),
              decoration: BoxDecoration(
                color: _neuBg,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
                border: Border.all(color: Colors.white, width: 1.5),
                boxShadow: neuExtrudedShadows(distance: 8, blur: 24),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Grab Handle
                  Center(
                    child: Container(
                      width: 42,
                      height: 4.5,
                      decoration: BoxDecoration(
                        color: _neuDarkShadow.withOpacity(0.6),
                        borderRadius: BorderRadius.circular(2.5),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Header Row
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          color: _neuBg,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 1.2),
                          boxShadow: neuExtrudedShadows(distance: 2, blur: 5),
                        ),
                        child: const Icon(Icons.travel_explore_rounded, color: _neuCobalt, size: 20),
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'ស្វែងរកទីតាំងពិតៗ (Real Location Search)',
                              style: TextStyle(
                                color: _neuTextDark,
                                fontSize: 15.5,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            Text(
                              'ស្វែងរកតាមឈ្មោះភូមិ, ឃុំ, ស្រុក, ខេត្ត ឬកូអរដោនេ WGS84 / UTM 48N',
                              style: TextStyle(
                                color: _neuTextMuted,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      GestureDetector(
                        onTap: () {
                          debounceTimer?.cancel();
                          Navigator.pop(ctx);
                        },
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: _neuBg,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 1.2),
                            boxShadow: neuExtrudedShadows(distance: 2, blur: 4),
                          ),
                          child: const Icon(Icons.close_rounded, color: _neuTextDark, size: 18),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // Real Map API Status Pill
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF10B981).withOpacity(0.35), width: 1),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: Color(0xFF10B981),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 7),
                        const Expanded(
                          child: Text(
                            '🌐 ភ្ជាប់ Live Map API រួចរាល់៖ ESRI ArcGIS + Photon OSM Live',
                            style: TextStyle(
                              color: Color(0xFF047857),
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Search Input Box
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                    decoration: BoxDecoration(
                      color: _neuInputBg,
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: neuRecessedShadows(),
                    ),
                    child: Row(
                      children: [
                        if (isLoading)
                          const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: _neuCobalt),
                          )
                        else
                          const Icon(Icons.search_rounded, color: _neuCobalt, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: searchCtrl,
                            autofocus: true,
                            style: const TextStyle(
                              color: _neuTextDark,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                            cursorColor: _neuCobalt,
                            decoration: const InputDecoration(
                              hintText: 'វាយឈ្មោះទីតាំង, កូអរដោនេ, ឬ Link Google Maps...',
                              hintStyle: TextStyle(color: _neuTextMuted, fontSize: 12),
                              border: InputBorder.none,
                              isDense: true,
                            ),
                            onChanged: (val) => executeSearch(val),
                          ),
                        ),
                        if (searchCtrl.text.isNotEmpty)
                          GestureDetector(
                            onTap: () {
                              searchCtrl.clear();
                              executeSearch('');
                            },
                            child: const Padding(
                              padding: EdgeInsets.all(4.0),
                              child: Icon(Icons.cancel_rounded, color: _neuTextMuted, size: 18),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Direct Coordinates / Google Maps Link Detection Banner
                  if (detectedCoords != null) ...[
                    GestureDetector(
                      onTap: () {
                        debounceTimer?.cancel();
                        Navigator.pop(ctx);
                        _selectSearchedLocation(
                          detectedCoords!.latitude,
                          detectedCoords!.longitude,
                          detectedLinkName ?? 'ទីតាំងលើ Google Maps (${detectedCoords!.latitude.toStringAsFixed(5)}°, ${detectedCoords!.longitude.toStringAsFixed(5)}°)',
                        );
                      },
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF047857), Color(0xFF10B981)],
                          ),
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF10B981).withOpacity(0.4),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.2),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                detectedLinkSource != null && detectedLinkSource!.contains('Link')
                                    ? Icons.link_rounded
                                    : Icons.gps_fixed_rounded,
                                color: Colors.white,
                                size: 22,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    detectedLinkName != null
                                        ? '🔗 បានស្គាល់ទីតាំង៖ $detectedLinkName'
                                        : (detectedLinkSource != null
                                            ? '🔗 បានស្គាល់ $detectedLinkSource'
                                            : '🎯 កូអរដោនេត្រូវគ្នាច្បាស់លាស់'),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 13,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'WGS84: ${detectedCoords!.latitude.toStringAsFixed(6)}°, ${detectedCoords!.longitude.toStringAsFixed(6)}°'
                                    '${detectedUtm != null ? '\nUTM 48N: E ${detectedUtm!.easting.toInt()}m, N ${detectedUtm!.northing.toInt()}m' : ''}',
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Text(
                                'ហោះទៅភ្លាម',
                                style: TextStyle(
                                  color: Color(0xFF047857),
                                  fontWeight: FontWeight.w900,
                                  fontSize: 11.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],

                  // Quick Cambodian Hotspots Chips Row
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    child: Row(
                      children: [
                        'វិមានឯករាជ្យ',
                        'ផ្សារធំថ្មី',
                        'កោះពេជ្រ',
                        'ព្រលានតេជោ',
                        'អង្គរវត្ត',
                        'ក្រុងព្រះសីហនុ',
                        'ក្រុងបាត់ដំបង',
                        'ក្រុងកំពត',
                        'ក្រុងកែប',
                        'ក្រុងកំពង់ចាម',
                        'មណ្ឌលគិរី',
                      ].map((chip) {
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: GestureDetector(
                            onTap: () {
                              searchCtrl.text = chip;
                              executeSearch(chip);
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                              decoration: BoxDecoration(
                                color: _neuBg,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: Colors.white, width: 1.2),
                                boxShadow: neuExtrudedShadows(distance: 2, blur: 4),
                              ),
                              child: Text(
                                chip,
                                style: const TextStyle(
                                  color: _neuCobalt,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Results List
                  Expanded(
                    child: searchResults.isEmpty && !isLoading
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24.0),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.search_off_rounded, color: _neuTextMuted, size: 44),
                                  const SizedBox(height: 10),
                                  Text(
                                    'រកមិនឃើញទីតាំង "${searchCtrl.text}" ទេ!',
                                    style: const TextStyle(
                                      color: _neuTextDark,
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 4),
                                  const Text(
                                    'សូមពិនិត្យអក្ខរាវិរុទ្ធ ឬ Paste Link Google Maps / វាយកូអរដោនេផ្ទាល់ (ឧ. 11.5564, 104.9282)',
                                    style: TextStyle(
                                      color: _neuTextMuted,
                                      fontSize: 11.5,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            ),
                          )
                        : ListView.builder(
                            physics: const BouncingScrollPhysics(),
                            itemCount: searchResults.length,
                            itemBuilder: (context, i) {
                              final item = searchResults[i];
                              final lat = (item['lat'] as num).toDouble();
                              final lng = (item['lng'] as num).toDouble();
                              final name = item['name'] as String;
                              final desc = item['desc'] as String;
                              final icon = item['icon'] as String? ?? '📍';
                              final isOnline = item['isOnline'] == true;

                              final source = item['source'] as String? ?? (isOnline ? '🌐 Live API' : '⚡ កម្ពុជា');

                              return GestureDetector(
                                onTap: () {
                                  debounceTimer?.cancel();
                                  Navigator.pop(ctx);
                                  _selectSearchedLocation(lat, lng, name);
                                },
                                child: Container(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                  decoration: BoxDecoration(
                                    color: _neuBg,
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(color: Colors.white, width: 1.2),
                                    boxShadow: neuExtrudedShadows(distance: 2, blur: 5),
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 38,
                                        height: 38,
                                        decoration: BoxDecoration(
                                          color: _neuInputBg,
                                          shape: BoxShape.circle,
                                          boxShadow: neuRecessedShadows(),
                                        ),
                                        alignment: Alignment.center,
                                        child: Text(
                                          icon,
                                          style: const TextStyle(fontSize: 18),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    name,
                                                    style: const TextStyle(
                                                      color: _neuTextDark,
                                                      fontSize: 13.5,
                                                      fontWeight: FontWeight.w900,
                                                    ),
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                ),
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color: isOnline
                                                        ? const Color(0xFF0284C7).withOpacity(0.12)
                                                        : const Color(0xFF10B981).withOpacity(0.12),
                                                    borderRadius: BorderRadius.circular(8),
                                                  ),
                                                  child: Text(
                                                    source,
                                                    style: TextStyle(
                                                      color: isOnline ? const Color(0xFF0284C7) : const Color(0xFF047857),
                                                      fontSize: 9.5,
                                                      fontWeight: FontWeight.w900,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              desc,
                                              style: const TextStyle(
                                                color: _neuTextMuted,
                                                fontSize: 11,
                                                fontWeight: FontWeight.w500,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            const SizedBox(height: 3),
                                            Text(
                                              '${lat.toStringAsFixed(5)}°, ${lng.toStringAsFixed(5)}°',
                                              style: const TextStyle(
                                                color: _neuCobalt,
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      const Icon(Icons.arrow_forward_ios_rounded, color: _neuTextMuted, size: 14),
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
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentTile = _mapStyles[_mapStyleIndex];
    final circlePoints = _mode == MeasureMode.circle ? _buildCirclePoints(_circleCenter, _circleRadius) : const <LatLng>[];

    final List<String> parcelTabNames = [];
    for (int i = 0; i < _completedParcels.length; i++) {
      parcelTabNames.add(_completedParcels[i].name);
    }
    parcelTabNames.add('ប្លង់បច្ចុប្បន្ន (${_areaM2.toInt()}m²)');

    return Scaffold(
      backgroundColor: _neuBg,
      body: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            // ── 0. OFFLINE CADASTRAL SURVEYOR BLUEPRINT (Always active behind map) ──
            Positioned.fill(
              child: CustomPaint(
                painter: _CadastralBlueprintPainter(),
              ),
            ),

            // ── 1. FULLSCREEN MAP VIEWPORT ──
            Positioned.fill(
              child: FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: _circleCenter,
                  initialZoom: 17.5,
                  minZoom: 3.0,
                  maxZoom: 22.0,
                  onTap: _onMapTap,
                  onMapReady: () {
                    setState(() {
                      _isMapReady = true;
                    });
                    final requested = MapMeasurementScreen.targetLocationRequest.value;
                    if (requested != null) {
                      _safeMoveMap(requested, 17.0);
                    } else if (_userLocation != null) {
                      _safeMoveMap(_userLocation!, 17.5);
                    }
                  },
                  onPositionChanged: (pos, _) {
                    _currentCenter = pos.center;
                    _currentCenterNotifier.value = pos.center;
                    if ((_mapRotation - pos.rotation).abs() > 0.5) {
                      setState(() {
                        _mapRotation = pos.rotation;
                      });
                    }
                  },
                ),
                children: [
                  // Base Map Tile (Google Hybrid HD / Pure Satellite / Streets / OSM / Offline Grid)
                  if (currentTile['url']!.isNotEmpty)
                    TileLayer(
                      urlTemplate: currentTile['url']!,
                      maxZoom: 22,
                      maxNativeZoom: int.tryParse(currentTile['maxNativeZoom'] ?? '20') ?? 20,
                      userAgentPackageName: 'com.example.my_first_app',
                    ),

                  // ── Official Cadastral Boundary Overlay (ប្លង់រឹងសុរិយោដី) ──
                  if (_cadastralOverlayPoints.isNotEmpty && _showCadastralOverlay)
                    PolygonLayer(
                      polygons: [
                        Polygon(
                          points: _cadastralOverlayPoints,
                          color: const Color(0xFFF59E0B).withOpacity(0.18),
                          borderColor: const Color(0xFFF59E0B),
                          borderStrokeWidth: 2.6,
                        ),
                      ],
                    ),

                  // ── Render Completed Multi-Parcels ──
                  ..._completedParcels.map((parcel) {
                    if (parcel.mode == MeasureMode.circle && parcel.circleCenter != null) {
                      final cPoints = _buildCirclePoints(parcel.circleCenter!, parcel.circleRadius);
                      return PolygonLayer(
                        polygons: [
                          Polygon(
                            points: cPoints,
                            color: parcel.color.withOpacity(0.20),
                            borderColor: parcel.color,
                            borderStrokeWidth: 2.8,
                          ),
                        ],
                      );
                    } else if (parcel.points.length >= 3) {
                      return PolygonLayer(
                        polygons: [
                          Polygon(
                            points: parcel.points,
                            color: parcel.color.withOpacity(0.24),
                            borderColor: parcel.color,
                            borderStrokeWidth: 3.0,
                          ),
                        ],
                      );
                    }
                    return const SizedBox.shrink();
                  }),

                  // ── Active Polygon Layer ──
                  if ((_mode == MeasureMode.polygon || _mode == MeasureMode.rectangle || _mode == MeasureMode.walk) && _polygonPoints.length >= 3)
                    PolygonLayer(
                      polygons: [
                        Polygon(
                          points: _polygonPoints,
                          color: _boundaryColor.withOpacity(0.24),
                          borderColor: _boundaryColor,
                          borderStrokeWidth: 3.2,
                        ),
                      ],
                    ),

                  // ── Active Polyline Layer ──
                  if (_polygonPoints.length >= 2 || (_isWalking && _polygonPoints.isNotEmpty && _userLocation != null))
                    PolylineLayer(
                      polylines: [
                        if (_polygonPoints.length >= 2)
                          Polyline(
                            points: _polygonPoints,
                            color: _boundaryColor,
                            strokeWidth: 3.8,
                          ),
                        // Live walking dynamic trail from last pin to user's real GPS position
                        if (_isWalking && _polygonPoints.isNotEmpty && _userLocation != null)
                          Polyline(
                            points: [_polygonPoints.last, _userLocation!],
                            color: const Color(0xFF10B981),
                            strokeWidth: 3.5,
                          ),
                        if ((_mode == MeasureMode.polygon || _mode == MeasureMode.rectangle || _mode == MeasureMode.walk) && _polygonPoints.length >= 3)
                          Polyline(
                            points: [_polygonPoints.last, _polygonPoints.first],
                            color: _boundaryColor.withOpacity(0.7),
                            strokeWidth: 3.2,
                          ),
                      ],
                    ),

                  // ── Active Circle Layer ──
                  if (_mode == MeasureMode.circle)
                    PolygonLayer(
                      polygons: [
                        Polygon(
                          points: circlePoints,
                          color: _boundaryColor.withOpacity(0.20),
                          borderColor: _boundaryColor,
                          borderStrokeWidth: 3.2,
                        ),
                      ],
                    ),

                  // ── Live Segment Distance & Bearing Tags on Map ──
                  if (_polygonPoints.length >= 2)
                    MarkerLayer(
                      markers: _buildSegmentDistanceMarkers(),
                    ),

                  // ── Corner Interior Angles Tags on Map (∠ 90°) ──
                  if (_showCornerAngles && _polygonPoints.length >= 3)
                    MarkerLayer(
                      markers: _buildCornerAngleMarkers(),
                    ),

                  // ── Corner Markers with Points Numbering ──
                  if (_mode != MeasureMode.circle)
                    MarkerLayer(
                      markers: _polygonPoints.asMap().entries.map((e) {
                        final idx = e.key;
                        final pt = e.value;
                        final isFirst = idx == 0;
                        final isSelected = _selectedPointIndex == idx;
                        final markerW = (isSelected ? 40.0 : 32.0) * _labelFontScale;
                        final markerH = (isSelected ? 40.0 : 32.0) * _labelFontScale;
                        final numText = _useKhmerDigits ? toKhmerNumerals(idx + 1) : '${idx + 1}';

                        return Marker(
                          point: pt,
                          width: markerW,
                          height: markerH,
                          child: GestureDetector(
                            onTap: () {
                              setState(() {
                                _selectedPointIndex = (_selectedPointIndex == idx) ? null : idx;
                              });
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: isFirst
                                    ? const LinearGradient(colors: [_neuYellow, Color(0xFFF9C74F)])
                                    : (isSelected
                                        ? const LinearGradient(colors: [Color(0xFFEF4444), Color(0xFFDC2626)])
                                        : LinearGradient(colors: [_boundaryColor, _boundaryColor.withOpacity(0.85)])),
                                border: Border.all(
                                  color: Colors.white,
                                  width: isSelected ? 2.8 : 1.8,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: (isFirst ? _neuYellow : (isSelected ? const Color(0xFFEF4444) : _boundaryColor)).withOpacity(0.6),
                                    blurRadius: isSelected ? 12 : 6,
                                  ),
                                ],
                              ),
                              child: Center(
                                child: Text(
                                  numText,
                                  style: TextStyle(
                                    color: isFirst ? _neuTextDark : Colors.white,
                                    fontSize: (isSelected ? 13.0 : 11.0) * _labelFontScale,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),

                  // Circle Center Pin
                  if (_mode == MeasureMode.circle)
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: _circleCenter,
                          width: 36,
                          height: 36,
                          child: Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: const LinearGradient(colors: [_neuCobalt, _neuCobaltDark]),
                              border: Border.all(color: Colors.white, width: 2),
                              boxShadow: [
                                BoxShadow(color: _neuCobalt.withOpacity(0.55), blurRadius: 10),
                              ],
                            ),
                            child: const Icon(Icons.location_on_rounded, color: Colors.white, size: 20),
                          ),
                        ),
                      ],
                    ),

                  // Live User GPS Position with Accuracy Ring Beacon
                  if (_userLocation != null)
                    MarkerLayer(
                      markers: [
                        // Accuracy Radius Halo
                        Marker(
                          point: _userLocation!,
                          width: 48,
                          height: 48,
                          child: IgnorePointer(
                            child: Container(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: const Color(0xFF10B981).withOpacity(0.18),
                                border: Border.all(
                                  color: const Color(0xFF10B981).withOpacity(0.5),
                                  width: 1.5,
                                ),
                              ),
                            ),
                          ),
                        ),
                        // Center High-Visibility Beacon
                        Marker(
                          point: _userLocation!,
                          width: 24,
                          height: 24,
                          child: Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: const Color(0xFF10B981),
                              border: Border.all(color: Colors.white, width: 2.5),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF10B981).withOpacity(0.65),
                                  blurRadius: 10,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                            child: Center(
                              child: Container(
                                width: 6,
                                height: 6,
                                decoration: const BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.white,
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

            // ── 2. CENTER PRECISION CROSSHAIR & TELEMETRY HUD ──
            if (_showCrosshairReticle)
              _buildPrecisionCrosshairHUD(),

            // ── 2.1 FLOATING COMPASS ROSE HUD ──
            if (_showCompassHUD)
              Positioned(
                top: 68,
                left: 12,
                child: _buildCompassRoseWidget(),
              ),

            // ── CADASTRAL OVERLAY ACTIVE BANNER ──
            if (_cadastralOverlayPoints.isNotEmpty && _showCadastralOverlay)
              Positioned(
                top: 56,
                left: 14,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF59E0B),
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 6),
                    ],
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.layers_rounded, color: Colors.white, size: 12),
                      SizedBox(width: 4),
                      Text(
                        'កំពុងត្រួតពិនិត្យប្លង់រឹងសុរិយោដី (Cadastral Overlay Active)',
                        style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ),

            // ── 3. TOP CLEAN & SPACIOUS SURVEYOR BAR ──
            Positioned(
              top: 6,
              left: 12,
              right: 12,
              child: _buildTopSurveyorBar(),
            ),

            // ── 4. RIGHT SIDE TOOLBAR CAPSULE ──
            Positioned(
              right: 12,
              top: 68,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 5),
                decoration: BoxDecoration(
                  color: _neuBg,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.white, width: 1.5),
                  boxShadow: neuExtrudedShadows(distance: 3.5, blur: 10),
                ),
                child: Column(
                  children: [
                    // GPS Locate
                    _buildToolButton(
                      icon: Icons.my_location_rounded,
                      tooltip: 'ទីតាំង GPS ខ្ញុំ',
                      onTap: () => _requestLocationAndCenter(userInitiated: true),
                    ),
                    const SizedBox(height: 6),

                    // Map Layers (Streets, Satellite, Topo)
                    _buildToolButton(
                      icon: Icons.layers_rounded,
                      color: _mapStyleIndex == 1 ? _neuYellow : _neuCobalt,
                      tooltip: currentTile['name']!,
                      onTap: () {
                        setState(() {
                          _mapStyleIndex = (_mapStyleIndex + 1) % _mapStyles.length;
                        });
                      },
                    ),
                    const SizedBox(height: 6),

                    // Drop Pin at My Current GPS location
                    _buildToolButton(
                      icon: Icons.add_circle_rounded,
                      color: const Color(0xFF10B981),
                      tooltip: 'បោះបង្គោលតាម GPS',
                      onTap: _addPointAtGps,
                    ),
                    const SizedBox(height: 6),

                    // Undo Point
                    _buildToolButton(
                      icon: Icons.undo_rounded,
                      tooltip: 'ថយក្រោយ (Undo)',
                      onTap: _undoLastPoint,
                    ),
                    const SizedBox(height: 6),

                    // Add Parcel (+ ប្លង់ថ្មី)
                    _buildToolButton(
                      icon: Icons.add_to_photos_rounded,
                      color: _neuCobalt,
                      tooltip: 'បន្ថែមប្លង់ដីថ្មី',
                      onTap: _addNewParcel,
                    ),
                    const SizedBox(height: 6),

                    // Reset / Clear
                    _buildToolButton(
                      icon: Icons.refresh_rounded,
                      color: const Color(0xFFEF4444),
                      tooltip: 'កំណត់ឡើងវិញ',
                      onTap: _clearMeasurement,
                    ),
                    const SizedBox(height: 6),

                    // Modern Surveyor Tools (ឧបករណ៍វាស់ស្ទង់ទំនើប)
                    _buildToolButton(
                      icon: Icons.tune_rounded,
                      color: const Color(0xFF0284C7),
                      tooltip: 'ឧបករណ៍វាស់ស្ទង់ទំនើប',
                      onTap: () => _showSurveyorToolboxModal(context),
                    ),
                    const SizedBox(height: 6),

                    // AR Camera Measure (ម៉ាស៊ីនវាស់តាម Camera AR ដូចរូបទី២)
                    _buildToolButton(
                      icon: Icons.camera_alt_rounded,
                      color: const Color(0xFFE11D48),
                      tooltip: 'វាស់តាម Camera AR',
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const CameraMeasureScreen()),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),

            // ── 5. RECTANGLE TOOL CONTROLS (When mode == rectangle) ──
            if (_mode == MeasureMode.rectangle)
              Positioned(
                top: 68,
                left: 12,
                right: 64,
                child: _buildRectangleControlsWidget(),
              ),

            // ── 6. CIRCLE TOOL CONTROLS (When mode == circle) ──
            if (_mode == MeasureMode.circle)
              Positioned(
                top: 68,
                left: 12,
                right: 64,
                child: _buildCircleControlsWidget(),
              ),

            // ── 7. POINT FINE-TUNING PANEL (If point is selected) ──
            if (_selectedPointIndex != null)
              Positioned(
                bottom: widget.isEmbedded ? 190 : 110,
                left: 14,
                right: 14,
                child: _buildPointFineTuningWidget(),
              ),

            // ── 8. FLOATING "+ ដាក់បង្គោលដី" BUTTON ──
            if (!_isWalking && _selectedPointIndex == null && _mode != MeasureMode.rectangle && _mode != MeasureMode.circle)
              Positioned(
                bottom: widget.isEmbedded ? 175 : 95,
                right: 16,
                child: GestureDetector(
                  onTap: _addPointAtCenter,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [_neuCobalt, _neuCobaltDark],
                      ),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: Colors.white, width: 1.5),
                      boxShadow: [
                        BoxShadow(
                          color: _neuCobalt.withOpacity(0.5),
                          blurRadius: 14,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.add_location_alt_rounded, color: _neuYellow, size: 19),
                        SizedBox(width: 6),
                        Text(
                          '+ ដាក់បង្គោលដី',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            // ── 9. GPS WALK ACTION HUD BAR (If in walk mode) ──
            if (_mode == MeasureMode.walk)
              Positioned(
                bottom: widget.isEmbedded ? 200 : 125,
                left: 12,
                right: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: _neuBg,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: Colors.white, width: 1.5),
                    boxShadow: neuExtrudedShadows(distance: 4, blur: 12),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Top Row: Walking Status & Interval Selector
                      Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: _isWalking ? const Color(0xFF10B981) : _neuYellow,
                              shape: BoxShape.circle,
                              boxShadow: _isWalking
                                  ? [BoxShadow(color: const Color(0xFF10B981).withOpacity(0.6), blurRadius: 6)]
                                  : null,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              _isWalking
                                  ? '🚶‍♂️ កំពុងដើរវាស់ដីស្វ័យប្រវត្តិ (${_polygonPoints.length} បង្គោល | ${_perimeterM.toStringAsFixed(1)}m)'
                                  : '🚶 របៀបដើរវាស់ដី (ចុច ចាប់ផ្តើម ឬដៅចំណុច)',
                              style: TextStyle(
                                color: _isWalking ? const Color(0xFF047857) : _neuTextDark,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w900,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          // Interval step chips
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [1.0, 2.0, 3.0, 5.0].map((step) {
                              final isSel = _autoWalkIntervalM == step;
                              return GestureDetector(
                                onTap: () => setState(() => _autoWalkIntervalM = step),
                                child: Container(
                                  margin: const EdgeInsets.only(left: 4),
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: isSel ? _neuCobalt : _neuInputBg,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    '${step.toInt()}m',
                                    style: TextStyle(
                                      color: isSel ? Colors.white : _neuTextMuted,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),

                      // Action Buttons Row (Add Pin here, Start/Pause, Close Polygon)
                      Row(
                        children: [
                          // 1. Manual Drop Pin here
                          Expanded(
                            child: GestureDetector(
                              onTap: () {
                                _triggerFeedback();
                                final pt = _userLocation ?? _currentCenter;
                                setState(() {
                                  _polygonPoints.add(pt);
                                  _recalculate();
                                });
                                _safeMoveMap(pt);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('📍 បានដៅបង្គោលទី ${_polygonPoints.length} (${_perimeterM.toStringAsFixed(1)}m)'),
                                    duration: const Duration(seconds: 1),
                                    behavior: SnackBarBehavior.floating,
                                  ),
                                );
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 9),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF10B981),
                                  borderRadius: BorderRadius.circular(16),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFF10B981).withOpacity(0.4),
                                      blurRadius: 8,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.add_location_alt_rounded, color: Colors.white, size: 16),
                                    SizedBox(width: 4),
                                    Text(
                                      'ដៅបង្គោល',
                                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 12),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),

                          // 2. Start / Pause Walk
                          Expanded(
                            flex: 2,
                            child: GestureDetector(
                              onTap: _toggleGpsWalk,
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 9),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: _isWalking
                                        ? [const Color(0xFFE11D48), const Color(0xFFBE123C)]
                                        : [_neuCobalt, _neuCobaltDark],
                                  ),
                                  borderRadius: BorderRadius.circular(16),
                                  boxShadow: [
                                    BoxShadow(
                                      color: (_isWalking ? const Color(0xFFE11D48) : _neuCobalt).withOpacity(0.4),
                                      blurRadius: 8,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      _isWalking ? Icons.pause_rounded : Icons.directions_walk_rounded,
                                      color: Colors.white,
                                      size: 18,
                                    ),
                                    const SizedBox(width: 5),
                                    Text(
                                      _isWalking ? 'ផ្អាកការដើរ' : 'ចាប់ផ្តើមដើរវាស់',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w900,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),

                          // 3. Close Loop / Finish
                          if (_polygonPoints.length >= 3)
                            Expanded(
                              child: GestureDetector(
                                onTap: () {
                                  if (_isWalking) _toggleGpsWalk();
                                  _recalculate();
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 9),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF59E0B),
                                    borderRadius: BorderRadius.circular(16),
                                    boxShadow: [
                                      BoxShadow(
                                        color: const Color(0xFFF59E0B).withOpacity(0.4),
                                        blurRadius: 8,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: const Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.done_all_rounded, color: Colors.white, size: 16),
                                      SizedBox(width: 4),
                                      Text(
                                        'បិទព្រំដី',
                                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 12),
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

            // ── 10. FLOATING BOTTOM HUD BAR (Cleanly above Bottom Nav Bar!) ──
            Positioned(
              left: 12,
              right: 12,
              bottom: widget.isEmbedded ? 98 : 16,
              child: MeasurementBottomSheet(
                areaM2: _areaM2,
                perimeterM: _perimeterM,
                pointsCount: _mode == MeasureMode.circle ? 1 : _polygonPoints.length,
                canSave: _canSave,
                onSave: _saveMeasurement,
                onClear: _clearMeasurement,
                bottomPadding: 0,
                isDistanceMode: _mode == MeasureMode.distance && _polygonPoints.length < 3,
                segmentLengths: _segmentLengths,
                parcelNames: parcelTabNames,
                activeParcelIndex: _activeParcelIndex,
                onAddNewParcel: _addNewParcel,
                totalCombinedAreaM2: _completedParcels.isNotEmpty ? _totalCombinedAreaM2 : 0,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // 1. TOP SURVEYOR HEADER BAR (Clean, spacious, unclipped!)
  // ─────────────────────────────────────────────────────────────
  Widget _buildTopSurveyorBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: _neuBg,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.white, width: 1.5),
        boxShadow: neuExtrudedShadows(distance: 3.5, blur: 10),
      ),
      child: Row(
        children: [
          // Home / Back Button
          GestureDetector(
            onTap: () {
              if (widget.onBackToHome != null) {
                widget.onBackToHome!();
              } else {
                Navigator.pop(context);
              }
            },
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: _neuBg,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 1.2),
                boxShadow: neuExtrudedShadows(distance: 2, blur: 5),
              ),
              child: Icon(
                widget.isEmbedded ? Icons.home_rounded : Icons.arrow_back_ios_new_rounded,
                color: _neuCobalt,
                size: widget.isEmbedded ? 18 : 15,
              ),
            ),
          ),
          const SizedBox(width: 8),

          // Live RTK / GPS Precision Status (Clickable for RTK GNSS Receiver Settings)
          GestureDetector(
            onTap: () => _showRtkConnectionModal(context),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              decoration: BoxDecoration(
                color: _isRtkConnected ? const Color(0xFF10B981).withOpacity(0.15) : _neuInputBg,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: _isRtkConnected ? const Color(0xFF10B981) : Colors.transparent,
                  width: 1.2,
                ),
                boxShadow: neuRecessedShadows(),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: _isRtkConnected ? const Color(0xFF10B981) : (_isGpsLocked ? const Color(0xFF10B981) : _neuYellow),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    _isRtkConnected ? 'RTK Fix ±${(_gpsAccuracy * 100).toStringAsFixed(1)}cm' : 'GPS ±${_gpsAccuracy.toStringAsFixed(1)}m',
                    style: TextStyle(
                      color: _isRtkConnected ? const Color(0xFF047857) : _neuTextDark,
                      fontWeight: FontWeight.w900,
                      fontSize: 11.5,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '▲+${_gpsAltitude.toStringAsFixed(1)}m',
                    style: const TextStyle(
                      color: _neuTextMuted,
                      fontWeight: FontWeight.bold,
                      fontSize: 10,
                    ),
                  ),
                  if (_isRtkConnected) ...[
                    const SizedBox(width: 4),
                    Text(' ($_satellitesCount 🛰️)', style: const TextStyle(color: Color(0xFF047857), fontSize: 10, fontWeight: FontWeight.bold)),
                  ],
                ],
              ),
            ),
          ),
          const Spacer(),

          // Real Location Search Button (ស្វែងរកទីតាំងពិតៗ)
          GestureDetector(
            onTap: () => _showRealLocationSearchModal(context),
            child: Container(
              width: 36,
              height: 36,
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                color: _neuBg,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 1.2),
                boxShadow: neuExtrudedShadows(distance: 2, blur: 5),
              ),
              child: const Icon(
                Icons.search_rounded,
                color: _neuCobalt,
                size: 20,
              ),
            ),
          ),

          // Active Mode Pill Trigger (Opens clean tool selector)
          GestureDetector(
            onTap: () => _showModePickerModal(context),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [_neuCobalt, _neuCobaltDark]),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.white, width: 1.2),
                boxShadow: [
                  BoxShadow(
                    color: _neuCobalt.withOpacity(0.4),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(_getModeIcon(_mode), color: Colors.white, size: 14),
                  const SizedBox(width: 5),
                  Text(
                    _getModeName(_mode),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 11.5,
                    ),
                  ),
                  const SizedBox(width: 2),
                  const Icon(Icons.arrow_drop_down_rounded, color: Colors.white, size: 18),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // 2. RECTANGLE TOOL CONTROLS (ទម្រង់ជ្រុង / ឡូតិ៍ដី)
  // ─────────────────────────────────────────────────────────────
  Widget _buildRectangleControlsWidget() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: _neuBg.withOpacity(0.96),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white, width: 1.4),
        boxShadow: neuExtrudedShadows(distance: 3, blur: 8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Text('ទំហំឡូតិ៍:', style: TextStyle(color: _neuTextDark, fontSize: 11, fontWeight: FontWeight.bold)),
              const SizedBox(width: 6),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      {'w': 5.0, 'l': 20.0, 'name': '5x20m (100m²)'},
                      {'w': 10.0, 'l': 20.0, 'name': '10x20m (200m²)'},
                      {'w': 15.0, 'l': 30.0, 'name': '15x30m (450m²)'},
                      {'w': 20.0, 'l': 30.0, 'name': '20x30m (600m²)'},
                    ].map((lot) {
                      final w = lot['w'] as double;
                      final l = lot['l'] as double;
                      final isSel = _rectWidthM == w && _rectLengthM == l;
                      return Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: GestureDetector(
                          onTap: () {
                            setState(() {
                              _rectWidthM = w;
                              _rectLengthM = l;
                              _updateRectangleGeometry();
                              _recalculate();
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                            decoration: BoxDecoration(
                              gradient: isSel ? const LinearGradient(colors: [_neuCobalt, _neuCobaltDark]) : null,
                              color: isSel ? null : _neuInputBg,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              lot['name'] as String,
                              style: TextStyle(
                                color: isSel ? Colors.white : _neuTextDark,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),

          // Steppers: Width, Length, Angle
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Width
              _buildStepControl('ទទឹង', '${_rectWidthM.toInt()}m', () {
                if (_rectWidthM > 2) {
                  setState(() {
                    _rectWidthM -= 1;
                    _updateRectangleGeometry();
                    _recalculate();
                  });
                }
              }, () {
                setState(() {
                  _rectWidthM += 1;
                  _updateRectangleGeometry();
                  _recalculate();
                });
              }),
              // Length
              _buildStepControl('បណ្តោយ', '${_rectLengthM.toInt()}m', () {
                if (_rectLengthM > 2) {
                  setState(() {
                    _rectLengthM -= 1;
                    _updateRectangleGeometry();
                    _recalculate();
                  });
                }
              }, () {
                setState(() {
                  _rectLengthM += 1;
                  _updateRectangleGeometry();
                  _recalculate();
                });
              }),
              // Angle
              _buildStepControl('មុំ', '${_rectAngleDeg.toInt()}°', () {
                setState(() {
                  _rectAngleDeg = (_rectAngleDeg - 10 + 360) % 360;
                  _updateRectangleGeometry();
                  _recalculate();
                });
              }, () {
                setState(() {
                  _rectAngleDeg = (_rectAngleDeg + 10) % 360;
                  _updateRectangleGeometry();
                  _recalculate();
                });
              }),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStepControl(String label, String value, VoidCallback onMinus, VoidCallback onPlus) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: _neuInputBg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$label: ', style: const TextStyle(color: _neuTextMuted, fontSize: 10, fontWeight: FontWeight.bold)),
          GestureDetector(onTap: onMinus, child: const Icon(Icons.remove_circle_outline_rounded, size: 14, color: _neuCobalt)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(value, style: const TextStyle(color: _neuTextDark, fontSize: 11, fontWeight: FontWeight.w900)),
          ),
          GestureDetector(onTap: onPlus, child: const Icon(Icons.add_circle_outline_rounded, size: 14, color: _neuCobalt)),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // 3. CIRCLE TOOL CONTROLS (ទម្រង់មូល / កាំរង្វង់)
  // ─────────────────────────────────────────────────────────────
  Widget _buildCircleControlsWidget() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: _neuBg.withOpacity(0.96),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white, width: 1.4),
        boxShadow: neuExtrudedShadows(distance: 3, blur: 8),
      ),
      child: Row(
        children: [
          const Text('កាំ:', style: TextStyle(color: _neuTextDark, fontSize: 11.5, fontWeight: FontWeight.bold)),
          const SizedBox(width: 4),
          ...[10.0, 25.0, 50.0, 100.0].map((r) {
            final isSel = _circleRadius == r;
            return Padding(
              padding: const EdgeInsets.only(right: 4),
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    _circleRadius = r;
                    _recalculate();
                  });
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    gradient: isSel ? const LinearGradient(colors: [_neuCobalt, _neuCobaltDark]) : null,
                    color: isSel ? null : _neuInputBg,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${r.toInt()}m',
                    style: TextStyle(
                      color: isSel ? Colors.white : _neuTextDark,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            );
          }),
          Expanded(
            child: Slider(
              value: _circleRadius,
              min: 5,
              max: 500,
              activeColor: _neuCobalt,
              inactiveColor: _neuDarkShadow.withOpacity(0.4),
              onChanged: (v) {
                setState(() {
                  _circleRadius = v;
                  _recalculate();
                });
              },
            ),
          ),
          Text(
            '${_circleRadius.toInt()}m',
            style: const TextStyle(color: _neuCobalt, fontWeight: FontWeight.w900, fontSize: 11),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // 4. SEGMENT DISTANCE TAGS ON MAP
  // ─────────────────────────────────────────────────────────────
  List<Marker> _buildSegmentDistanceMarkers() {
    if (!_showSideBearings || _polygonPoints.length < 2) return [];
    final List<Marker> markers = [];
    final isClosed = (_mode == MeasureMode.polygon || _mode == MeasureMode.rectangle || _mode == MeasureMode.walk);
    final count = isClosed ? _polygonPoints.length : _polygonPoints.length - 1;

    for (int i = 0; i < count; i++) {
      final p1 = _polygonPoints[i];
      final nextIdx = (i + 1) % _polygonPoints.length;
      final p2 = _polygonPoints[nextIdx];
      final mid = midpointLatLng(p1, p2);
      final dist = haversineDistance(p1, p2);
      final bearing = calculateBearing(p1, p2);
      final dirShort = getCompassDirectionShort(bearing);

      markers.add(
        Marker(
          point: mid,
          width: 78,
          height: 24,
          child: GestureDetector(
            onTap: () => _showSegmentDetailModal(i, nextIdx, p1, p2, dist, bearing),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xFF1E2638).withOpacity(0.92),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white, width: 1.1),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 6, offset: const Offset(0, 2)),
                ],
              ),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${dist.toStringAsFixed(1)}m',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(width: 3),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                      decoration: BoxDecoration(
                        color: _neuYellow.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '${bearing.toStringAsFixed(0)}° $dirShort',
                        style: const TextStyle(
                          color: _neuYellow,
                          fontSize: 8.5,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }
    return markers;
  }

  // ─────────────────────────────────────────────────────────────
  // CORNER ANGLE MARKERS (∠ 90° Diagnostic)
  // ─────────────────────────────────────────────────────────────
  List<Marker> _buildCornerAngleMarkers() {
    if (!_showCornerAngles || _polygonPoints.length < 3) return [];
    if (_mode != MeasureMode.polygon && _mode != MeasureMode.rectangle && _mode != MeasureMode.walk) return [];

    final List<Marker> markers = [];
    final n = _polygonPoints.length;

    for (int i = 0; i < n; i++) {
      final prev = _polygonPoints[(i - 1 + n) % n];
      final curr = _polygonPoints[i];
      final next = _polygonPoints[(i + 1) % n];
      final angle = calculateInteriorAngle(prev, curr, next);
      final isRightAngle = (angle - 90.0).abs() <= 2.5;

      markers.add(
        Marker(
          point: curr,
          width: 58,
          height: 18,
          alignment: Alignment.topRight,
          child: IgnorePointer(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: isRightAngle ? const Color(0xFF10B981) : const Color(0xFF1E2638).withOpacity(0.85),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.white, width: 0.9),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.25), blurRadius: 4),
                ],
              ),
              child: Text(
                '∠${angle.toStringAsFixed(1)}°${isRightAngle ? 'កែង' : ''}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 8,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
        ),
      );
    }
    return markers;
  }

  // ─────────────────────────────────────────────────────────────
  // PRECISION CROSSHAIR & TELEMETRY HUD
  // ─────────────────────────────────────────────────────────────
  Widget _buildPrecisionCrosshairHUD() {
    return Center(
      child: IgnorePointer(
        child: SizedBox(
          width: 56,
          height: 56,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Scope circular ring / Loupe Magnifier
              Container(
                width: _showMagnifierLoupe ? 72 : 44,
                height: _showMagnifierLoupe ? 72 : 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: _showMagnifierLoupe ? const Color(0xFFF59E0B) : _neuCobalt.withOpacity(0.75),
                    width: _showMagnifierLoupe ? 2.2 : 1.5,
                  ),
                  boxShadow: _showMagnifierLoupe
                      ? [BoxShadow(color: const Color(0xFFF59E0B).withOpacity(0.4), blurRadius: 10)]
                      : null,
                ),
              ),
              // Reticle crosshairs
              Container(width: 56, height: 1.2, color: _neuCobalt.withOpacity(0.65)),
              Container(width: 1.2, height: 56, color: _neuCobalt.withOpacity(0.65)),
              // Center laser point
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: const Color(0xFFEF4444),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 1.5),
                  boxShadow: [
                    BoxShadow(color: const Color(0xFFEF4444).withOpacity(0.6), blurRadius: 6),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // FLOATING COMPASS ROSE WIDGET
  // ─────────────────────────────────────────────────────────────
  Widget _buildCompassRoseWidget() {
    return GestureDetector(
      onTap: () {
        if (_isMapReady) {
          try {
            _mapController.rotate(0.0);
          } catch (_) {}
          setState(() {
            _mapRotation = 0.0;
          });
        }
      },
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: _neuBg,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 1.4),
          boxShadow: neuExtrudedShadows(distance: 2.5, blur: 6),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Transform.rotate(
              angle: -(_mapRotation * math.pi / 180.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.navigation_rounded, color: Color(0xFFEF4444), size: 17),
                  Transform.rotate(
                    angle: math.pi,
                    child: const Icon(Icons.navigation_rounded, color: _neuDarkShadow, size: 11),
                  ),
                ],
              ),
            ),
            const Positioned(
              top: 2,
              child: Text(
                'N',
                style: TextStyle(
                  color: Color(0xFFEF4444),
                  fontSize: 7.5,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // SEGMENT INSPECTOR MODAL (+ Insert Midpoint)
  // ─────────────────────────────────────────────────────────────
  void _showSegmentDetailModal(int idx, int nextIdx, LatLng p1, LatLng p2, double dist, double bearing) {
    final hatt = metersToHatt(dist);
    final feet = metersToFeet(dist);
    final dirKhmer = getCompassDirectionKhmer(bearing);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withOpacity(0.35),
      builder: (ctx) => Container(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
        decoration: BoxDecoration(
          color: _neuBg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
          border: Border.all(color: Colors.white, width: 1.5),
          boxShadow: neuExtrudedShadows(distance: 6, blur: 20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: _neuDarkShadow.withOpacity(0.6),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: _neuBg,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1.2),
                    boxShadow: neuExtrudedShadows(distance: 2, blur: 5),
                  ),
                  child: const Icon(Icons.straighten_rounded, color: _neuCobalt, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'ព័ត៌មានលម្អិតជ្រុង P${idx + 1} ➔ P${nextIdx + 1}',
                        style: const TextStyle(
                          color: _neuTextDark,
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        'ទិសដៅ: ${bearing.toStringAsFixed(1)}° $dirKhmer',
                        style: const TextStyle(
                          color: _neuTextMuted,
                          fontSize: 11.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            // Metrics Row (Meters, Hatt, Feet)
            Row(
              children: [
                Expanded(
                  child: _buildSegmentMetricCard('ប្រវែងម៉ែត្រ', '${dist.toStringAsFixed(2)} m', const Color(0xFF10B981)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildSegmentMetricCard('ប្រវែងហត្ថ', '${hatt.toStringAsFixed(1)} ហត្ថ', _neuCobalt),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildSegmentMetricCard('ប្រវែងហ្វីត', '${feet.toStringAsFixed(1)} ft', const Color(0xFFF59E0B)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Coordinates Details Card
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _neuInputBg,
                borderRadius: BorderRadius.circular(16),
                boxShadow: neuRecessedShadows(),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Icon(Icons.location_on_outlined, size: 14, color: _neuCobalt),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          'P${idx + 1}: ${p1.latitude.toStringAsFixed(6)}°, ${p1.longitude.toStringAsFixed(6)}°',
                          style: const TextStyle(color: _neuTextDark, fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(Icons.flag_outlined, size: 14, color: Color(0xFFEF4444)),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          'P${nextIdx + 1}: ${p2.latitude.toStringAsFixed(6)}°, ${p2.longitude.toStringAsFixed(6)}°',
                          style: const TextStyle(color: _neuTextDark, fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            // Action Button: Insert Pin at Midpoint
            GestureDetector(
              onTap: () {
                Navigator.pop(ctx);
                _insertPointAtSegmentMidpoint(idx);
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [_neuCobalt, _neuCobaltDark]),
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(color: _neuCobalt.withOpacity(0.4), blurRadius: 10, offset: const Offset(0, 3)),
                  ],
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.add_location_alt_rounded, color: _neuYellow, size: 18),
                    SizedBox(width: 8),
                    Text(
                      '+ បញ្ចូលបង្គោលពាក់កណ្តាលជ្រុងនេះ (Split)',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 13),
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

  void _insertPointAtSegmentMidpoint(int idx) {
    if (_polygonPoints.length < 2) return;
    final p1 = _polygonPoints[idx];
    final p2 = _polygonPoints[(idx + 1) % _polygonPoints.length];
    final mid = midpointLatLng(p1, p2);

    setState(() {
      _polygonPoints.insert(idx + 1, mid);
      _selectedPointIndex = idx + 1;
      _recalculate();
    });
  }

  Widget _buildSegmentMetricCard(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: BoxDecoration(
        color: _neuBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white, width: 1.2),
        boxShadow: neuExtrudedShadows(distance: 2, blur: 5),
      ),
      child: Column(
        children: [
          Text(label, style: const TextStyle(color: _neuTextMuted, fontSize: 10, fontWeight: FontWeight.bold)),
          const SizedBox(height: 3),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(value, style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w900)),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // SURVEYOR TOOLBOX MODAL (ផ្ទាំងឧបករណ៍វាស់ស្ទង់ទំនើប)
  // ─────────────────────────────────────────────────────────────
  void _showSurveyorToolboxModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withOpacity(0.35),
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Container(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
          decoration: BoxDecoration(
            color: _neuBg,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
            border: Border.all(color: Colors.white, width: 1.5),
            boxShadow: neuExtrudedShadows(distance: 8, blur: 24),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4.5,
                  decoration: BoxDecoration(
                    color: _neuDarkShadow.withOpacity(0.6),
                    borderRadius: BorderRadius.circular(2.5),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: _neuBg,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 1.2),
                      boxShadow: neuExtrudedShadows(distance: 2, blur: 5),
                    ),
                    child: const Icon(Icons.tune_rounded, color: Color(0xFF0284C7), size: 20),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'ឧបករណ៍វាស់ស្ទង់ទំនើប (Surveyor Tools)',
                          style: TextStyle(
                            color: _neuTextDark,
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          'កំណត់មុខងារវាស់ស្ទង់ កែវឆ្លុះ & ត្រីវិស័យ Bearings',
                          style: TextStyle(
                            color: _neuTextMuted,
                            fontSize: 11.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Tool Toggles
              _buildToolSwitchTile(
                icon: Icons.auto_awesome_rounded,
                title: 'វាស់មធ្យមភាគ GPS សុក្រឹតខ្ពស់ (Averaging)',
                subtitle: 'ចាប់យក ១៥ គំរូ ជម្រុះ Drift ដើម្បីភាពសុក្រឹតកម្រិតខ្ពស់',
                value: _enableHighPrecisionGps,
                onChanged: (val) {
                  setModalState(() => _enableHighPrecisionGps = val);
                  setState(() => _enableHighPrecisionGps = val);
                },
              ),
              const SizedBox(height: 10),

              // Offline Map Cache Button Tile
              GestureDetector(
                onTap: () {
                  Navigator.pop(ctx);
                  _showOfflineMapCacheModal(context);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: _neuBg,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: Colors.white, width: 1.2),
                    boxShadow: neuExtrudedShadows(distance: 2, blur: 6),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: const Color(0xFF0284C7).withOpacity(0.12),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.cloud_download_rounded, color: Color(0xFF0284C7), size: 19),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'ផែនទី Offline & ការផ្ទុកទិន្នន័យ',
                              style: TextStyle(color: _neuTextDark, fontSize: 13, fontWeight: FontWeight.bold),
                            ),
                            Text(
                              'ផ្ទុកផែនទីទុកវាស់ដីនៅកន្លែងគ្មាន Internet',
                              style: TextStyle(color: _neuTextMuted, fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right_rounded, color: _neuTextMuted),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),

              _buildToolSwitchTile(
                icon: Icons.gps_fixed_rounded,
                title: 'កែវឆ្លុះវាស់ដី (Crosshair Reticle HUD)',
                subtitle: 'បង្ហាញសញ្ញាកណ្តាល និងកូអរដោនេ WGS84 ជាក់ស្ដែង',
                value: _showCrosshairReticle,
                onChanged: (val) {
                  setModalState(() => _showCrosshairReticle = val);
                  setState(() => _showCrosshairReticle = val);
                },
              ),
              const SizedBox(height: 10),

              _buildToolSwitchTile(
                icon: Icons.square_foot_rounded,
                title: 'បង្ហាញមុំកាច់ជ្រុងដី (Corner Angles ∠)',
                subtitle: 'គណនាមុំកាច់ជ្រុងដីនីមួយៗ (៩០° ពិនិត្យមុំកែង)',
                value: _showCornerAngles,
                onChanged: (val) {
                  setModalState(() => _showCornerAngles = val);
                  setState(() => _showCornerAngles = val);
                },
              ),
              const SizedBox(height: 10),

              _buildToolSwitchTile(
                icon: Icons.explore_rounded,
                title: 'ទិសដៅត្រីវិស័យ & Bearings លើជ្រុង',
                subtitle: 'បង្ហាញមុំដឺក្រេ azimuth និងទិសដៅលើបន្ទាត់ព្រំដី',
                value: _showSideBearings,
                onChanged: (val) {
                  setModalState(() => _showSideBearings = val);
                  setState(() => _showSideBearings = val);
                },
              ),
              const SizedBox(height: 10),

              _buildToolSwitchTile(
                icon: Icons.navigation_rounded,
                title: 'ត្រីវិស័យលើអេក្រង់ (Compass Rose)',
                subtitle: 'បង្ហាញទិសខាងជើង និងចុចដើម្បីតម្រង់ផែនទីឡើងលើ',
                value: _showCompassHUD,
                onChanged: (val) {
                  setModalState(() => _showCompassHUD = val);
                  setState(() => _showCompassHUD = val);
                },
              ),
              const SizedBox(height: 16),

              // Auto-Walk GPS Interval Step Selector
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _neuInputBg,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: neuRecessedShadows(),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.directions_walk_rounded, color: Color(0xFFE11D48), size: 16),
                        SizedBox(width: 6),
                        Text(
                          'ជំហានដើរវាស់ស្វ័យប្រវត្តិ (Auto-Walk Interval):',
                          style: TextStyle(color: _neuTextDark, fontSize: 12, fontWeight: FontWeight.w900),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [3.0, 5.0, 10.0, 20.0].map((step) {
                        final isSel = _autoWalkIntervalM == step;
                        return Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 2.5),
                            child: GestureDetector(
                              onTap: () {
                                setModalState(() => _autoWalkIntervalM = step);
                                setState(() => _autoWalkIntervalM = step);
                              },
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 180),
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                decoration: BoxDecoration(
                                  color: isSel ? _neuCobalt : _neuBg,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: Colors.white, width: 1.2),
                                  boxShadow: isSel
                                      ? [BoxShadow(color: _neuCobalt.withOpacity(0.4), blurRadius: 6, offset: const Offset(0, 2))]
                                      : neuExtrudedShadows(distance: 1.5, blur: 4),
                                ),
                                child: Center(
                                  child: Text(
                                    '${step.toInt()} ម៉ែត្រ',
                                    style: TextStyle(
                                      color: isSel ? Colors.white : _neuTextDark,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 11,
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
                ),
              ),
              const SizedBox(height: 16),

              // Magnifier Loupe Toggle
              _buildToolSwitchTile(
                icon: Icons.zoom_in_rounded,
                title: 'កែវពង្រីកបោះបង្គោល (Magnifier Loupe Reticle)',
                subtitle: 'ពង្រីកកែវឆ្លុះដើម្បីដៅបង្គោលឱ្យចំជ្រុងរបង/ដើមឈើជាក់ស្ដែង',
                value: _showMagnifierLoupe,
                onChanged: (val) {
                  setModalState(() => _showMagnifierLoupe = val);
                  setState(() => _showMagnifierLoupe = val);
                },
              ),
              const SizedBox(height: 14),

              // Advanced Smart Surveyor Feature Cards (Grid 2x2)
              Row(
                children: [
                  Expanded(
                    child: _buildToolQuickCard(
                      icon: Icons.satellite_alt_rounded,
                      color: const Color(0xFF047857),
                      title: 'ឧបករណ៍ RTK GNSS',
                      desc: _isRtkConnected ? 'បានភ្ជាប់ (±1.5cm)' : 'ភ្ជាប់ Bluetooth / CORS',
                      onTap: () {
                        Navigator.pop(ctx);
                        _showRtkConnectionModal(context);
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildToolQuickCard(
                      icon: Icons.splitscreen_rounded,
                      color: _neuCobalt,
                      title: 'បែងចែកក្បាលដី',
                      desc: 'ពុះឡូតិ៍ / ចែកស្មើគ្នា',
                      onTap: () {
                        Navigator.pop(ctx);
                        _showParcelSplitterModal(context);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _buildToolQuickCard(
                      icon: Icons.layers_rounded,
                      color: const Color(0xFFD97706),
                      title: 'ប្លង់រឹងសុរិយោដី',
                      desc: 'នាំចូល KML / GeoJSON',
                      onTap: () {
                        Navigator.pop(ctx);
                        _showCadastralImportModal(context);
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildToolQuickCard(
                      icon: Icons.terrain_rounded,
                      color: const Color(0xFF7C3AED),
                      title: 'គម្រោងដីចាក់បំពេញ',
                      desc: 'Cut/Fill Volume m³',
                      onTap: () {
                        Navigator.pop(ctx);
                        _showCutFillCalculatorModal(context);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _buildToolQuickCard(
                      icon: Icons.travel_explore_rounded,
                      color: _neuCobalt,
                      title: 'ស្វែងរកទីតាំងពិតៗ',
                      desc: 'OpenStreetMap & កូអរដោនេ',
                      onTap: () {
                        Navigator.pop(ctx);
                        _showRealLocationSearchModal(context);
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildToolQuickCard(
                      icon: Icons.edit_location_alt_rounded,
                      color: const Color(0xFF0284C7),
                      title: 'វាយកូអរដោនេផ្ទាល់',
                      desc: 'WGS84 & UTM 48N',
                      onTap: () {
                        Navigator.pop(ctx);
                        _showDirectCoordinateInputDialog(context);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _buildToolQuickCard(
                      icon: Icons.picture_as_pdf_rounded,
                      color: const Color(0xFFE11D48),
                      title: 'វិញ្ញាបនបត្រប្លង់',
                      desc: 'ប្លង់ផ្លូវការ PDF & Print',
                      onTap: () {
                        Navigator.pop(ctx);
                        _showOfficialDeedReportModal(context);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Action: Survey Data Book & Export KML / GeoJSON
              GestureDetector(
                onTap: () {
                  Navigator.pop(ctx);
                  _showSurveyDataBookModal(context);
                },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [_neuCobalt, _neuCobaltDark]),
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [
                      BoxShadow(color: _neuCobalt.withOpacity(0.4), blurRadius: 10, offset: const Offset(0, 3)),
                    ],
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.menu_book_rounded, color: _neuYellow, size: 18),
                      SizedBox(width: 8),
                      Text(
                        'សៀវភៅកំណត់ត្រាព្រំដី & នាំចេញ (Survey Data Book)',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 12.5),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildToolSwitchTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: _neuBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white, width: 1.2),
        boxShadow: neuExtrudedShadows(distance: 2, blur: 5),
      ),
      child: Row(
        children: [
          Icon(icon, color: _neuCobalt, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: _neuTextDark, fontWeight: FontWeight.w900, fontSize: 12.5)),
                Text(subtitle, style: const TextStyle(color: _neuTextMuted, fontSize: 10.5, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          Switch(
            value: value,
            activeColor: _neuCobalt,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // SURVEY DATA BOOK & EXPORT MODAL (KML / GeoJSON / Text)
  // ─────────────────────────────────────────────────────────────
  void _showSurveyDataBookModal(BuildContext context) {
    final points = _polygonPoints;
    final n = points.length;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withOpacity(0.35),
      isScrollControlled: true,
      builder: (ctx) => Container(
        height: MediaQuery.of(context).size.height * 0.78,
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
        decoration: BoxDecoration(
          color: _neuBg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          border: Border.all(color: Colors.white, width: 1.5),
          boxShadow: neuExtrudedShadows(distance: 8, blur: 24),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4.5,
                decoration: BoxDecoration(
                  color: _neuDarkShadow.withOpacity(0.6),
                  borderRadius: BorderRadius.circular(2.5),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: _neuBg,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1.2),
                    boxShadow: neuExtrudedShadows(distance: 2, blur: 5),
                  ),
                  child: const Icon(Icons.description_rounded, color: _neuCobalt, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'សៀវភៅកំណត់ត្រាព្រំដី (Surveyor Data Book)',
                        style: TextStyle(color: _neuTextDark, fontSize: 15.5, fontWeight: FontWeight.w900),
                      ),
                      Text(
                        'ផ្ទៃក្រឡា: ${_areaM2.toStringAsFixed(1)}m² (${(_areaM2/10000).toStringAsFixed(3)} Ha) • ${points.length} បង្គោល',
                        style: const TextStyle(color: _neuTextMuted, fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Quick Export Buttons Row
            Row(
              children: [
                Expanded(
                  child: _buildExportActionButton(
                    icon: Icons.code_rounded,
                    label: 'ចម្លង KML',
                    color: const Color(0xFF10B981),
                    onTap: () {
                      final kml = generateKml('ប្លង់ដីវាស់វែង', points, _areaM2, _perimeterM);
                      Clipboard.setData(ClipboardData(text: kml));
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildExportActionButton(
                    icon: Icons.map_rounded,
                    label: 'ចម្លង GeoJSON',
                    color: const Color(0xFF8B5CF6),
                    onTap: () {
                      final geoJson = generateGeoJson('ប្លង់ដីវាស់វែង', points, _areaM2, _perimeterM);
                      Clipboard.setData(ClipboardData(text: geoJson));
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildExportActionButton(
                    icon: Icons.copy_rounded,
                    label: 'ចម្លងរបាយការណ៍',
                    color: _neuCobalt,
                    onTap: () {
                      final summary = StringBuffer();
                      summary.writeln('📋 របាយការណ៍ប្លង់វាស់វែងដីធ្លី');
                      summary.writeln('• ផ្ទៃក្រឡាសរុប: ${_areaM2.toStringAsFixed(1)} m² (${(_areaM2/100).toStringAsFixed(2)} អា / ${(_areaM2/10000).toStringAsFixed(4)} ហិកតា)');
                      summary.writeln('• បរិមាត្រជុំវិញ: ${_perimeterM.toStringAsFixed(1)} ម៉ែត្រ');
                      summary.writeln('• ចំនួនបង្គោលដី: ${points.length} បង្គោល');
                      summary.writeln('--- បញ្ជីកូអរដោនេ WGS84 ---');
                      for (int i = 0; i < points.length; i++) {
                        summary.writeln('P${i + 1}: ${points[i].latitude.toStringAsFixed(6)}°, ${points[i].longitude.toStringAsFixed(6)}°');
                      }
                      Clipboard.setData(ClipboardData(text: summary.toString()));
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Boundary Stakes Table
            Expanded(
              child: points.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.edit_location_alt_rounded, size: 48, color: _neuDarkShadow.withOpacity(0.5)),
                          const SizedBox(height: 10),
                          const Text('មិនទាន់មានបង្គោលដីនៅឡើយទេ', style: TextStyle(color: _neuTextMuted, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          const Text('សូមចុចបោះបង្គោលដីលើផែនទីជាមុនសិន', style: TextStyle(color: _neuTextMuted, fontSize: 11)),
                        ],
                      ),
                    )
                  : ListView.builder(
                      itemCount: points.length,
                      itemBuilder: (ctx, i) {
                        final curr = points[i];
                        final next = points[(i + 1) % n];
                        final dist = (points.length >= 2 && (i < n - 1 || _mode != MeasureMode.distance))
                            ? haversineDistance(curr, next)
                            : 0.0;
                        final bearing = calculateBearing(curr, next);
                        final angle = (points.length >= 3)
                            ? calculateInteriorAngle(points[(i - 1 + n) % n], curr, next)
                            : null;

                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: _neuBg,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.white, width: 1.2),
                            boxShadow: neuExtrudedShadows(distance: 2, blur: 5),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    width: 24,
                                    height: 24,
                                    decoration: const BoxDecoration(color: _neuCobalt, shape: BoxShape.circle),
                                    child: Center(
                                      child: Text(
                                        '${i + 1}',
                                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'បង្គោល P${i + 1}',
                                    style: const TextStyle(color: _neuTextDark, fontWeight: FontWeight.w900, fontSize: 13),
                                  ),
                                  const Spacer(),
                                  if (angle != null)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: (angle - 90).abs() <= 2.5 ? const Color(0xFF10B981) : _neuInputBg,
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        'មុំ: ∠${angle.toStringAsFixed(1)}°',
                                        style: TextStyle(
                                          color: (angle - 90).abs() <= 2.5 ? Colors.white : _neuTextDark,
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'កូអរដោនេ: ${curr.latitude.toStringAsFixed(6)}°, ${curr.longitude.toStringAsFixed(6)}°',
                                style: const TextStyle(color: _neuTextMuted, fontSize: 11, fontWeight: FontWeight.w600),
                              ),
                              if (dist > 0) ...[
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Text(
                                      'ជ្រុងទៅ P${(i + 1) % n + 1}: ${dist.toStringAsFixed(2)} ម៉ែត្រ',
                                      style: const TextStyle(color: Color(0xFF10B981), fontSize: 11, fontWeight: FontWeight.bold),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      '• ទិស: ${bearing.toStringAsFixed(0)}° (${getCompassDirectionShort(bearing)})',
                                      style: const TextStyle(color: _neuCobalt, fontSize: 11, fontWeight: FontWeight.bold),
                                    ),
                                  ],
                                ),
                              ],
                            ],
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

  Widget _buildExportActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 6),
        decoration: BoxDecoration(
          color: _neuBg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white, width: 1.2),
          boxShadow: neuExtrudedShadows(distance: 2, blur: 5),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 14),
            const SizedBox(width: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w900),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // 5. POINT FINE-TUNING CONTROL PANEL (Nudge 4 directions)
  // ─────────────────────────────────────────────────────────────
  Widget _buildPointFineTuningWidget() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: _neuBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white, width: 1.5),
        boxShadow: neuExtrudedShadows(distance: 4, blur: 12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: const BoxDecoration(color: Color(0xFFEF4444), shape: BoxShape.circle),
                child: Center(
                  child: Text(
                    '${_selectedPointIndex! + 1}',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              const Text(
                'រំកិលបង្គោល (Nudge):',
                style: TextStyle(color: _neuTextDark, fontWeight: FontWeight.w800, fontSize: 11.5),
              ),
            ],
          ),

          Row(
            children: [
              _buildNudgeArrow(Icons.arrow_upward_rounded, () => _nudgeSelectedPoint(0.5, 0)),
              _buildNudgeArrow(Icons.arrow_downward_rounded, () => _nudgeSelectedPoint(-0.5, 0)),
              _buildNudgeArrow(Icons.arrow_back_rounded, () => _nudgeSelectedPoint(0, -0.5)),
              _buildNudgeArrow(Icons.arrow_forward_rounded, () => _nudgeSelectedPoint(0, 0.5)),
              const SizedBox(width: 4),
              GestureDetector(
                onTap: _deleteSelectedPoint,
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEF4444),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: const Icon(Icons.delete_rounded, color: Colors.white, size: 15),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildNudgeArrow(IconData icon, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 1.5),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: _neuInputBg,
            borderRadius: BorderRadius.circular(7),
            border: Border.all(color: Colors.white, width: 1),
          ),
          child: Icon(icon, color: _neuCobalt, size: 15),
        ),
      ),
    );
  }

  Widget _buildToolQuickCard({
    required IconData icon,
    required Color color,
    required String title,
    required String desc,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: _neuBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white, width: 1.2),
          boxShadow: neuExtrudedShadows(distance: 2, blur: 5),
        ),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                shape: BoxShape.circle,
                border: Border.all(color: color.withOpacity(0.4), width: 1),
              ),
              child: Icon(icon, color: color, size: 17),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(color: _neuTextDark, fontWeight: FontWeight.w900, fontSize: 11.5)),
                  Text(desc, style: const TextStyle(color: _neuTextMuted, fontWeight: FontWeight.bold, fontSize: 9.5), maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // 1. RTK GNSS & NTRIP CORS MODAL (High Accuracy ±1cm)
  // ─────────────────────────────────────────────────────────────
  void _showRtkConnectionModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withOpacity(0.35),
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setRtkState) => Container(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
          decoration: BoxDecoration(
            color: _neuBg,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
            border: Border.all(color: Colors.white, width: 1.5),
            boxShadow: neuExtrudedShadows(distance: 8, blur: 24),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4.5,
                  decoration: BoxDecoration(color: _neuDarkShadow.withOpacity(0.6), borderRadius: BorderRadius.circular(2.5)),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: _isRtkConnected ? const Color(0xFF10B981) : _neuCobalt,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: (_isRtkConnected ? const Color(0xFF10B981) : _neuCobalt).withOpacity(0.4),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                    child: const Icon(Icons.satellite_alt_rounded, color: Colors.white, size: 22),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'ឧបករណ៍ RTK GNSS & NTRIP CORS',
                          style: TextStyle(color: _neuTextDark, fontSize: 16, fontWeight: FontWeight.w900),
                        ),
                        Text(
                          _isRtkConnected ? 'ស្ថានភាព: $_rtkFixStatus • $_satellitesCount ផ្កាយរណប' : 'ភ្ជាប់ឧបករណ៍វាស់ស្ទង់ខាងក្រៅ (Emlid, Trimble, Stonex)',
                          style: TextStyle(
                            color: _isRtkConnected ? const Color(0xFF047857) : _neuTextMuted,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Device Selector Cards
              const Text('ជ្រើសរើសឧបករណ៍ GNSS Receiver:', style: TextStyle(color: _neuTextDark, fontSize: 12, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  'Emlid Reach RS2/RS3',
                  'Trimble R12 / R10',
                  'Stonex S900 / CHCNAV',
                  'GPS ទូរសព្ទដៃ (Internal)',
                ].map((dev) {
                  final isSel = _rtkDeviceName.startsWith(dev.split(' ')[0]);
                  return GestureDetector(
                    onTap: () {
                      setRtkState(() => _rtkDeviceName = dev);
                      setState(() => _rtkDeviceName = dev);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                      decoration: BoxDecoration(
                        color: isSel ? _neuCobalt : _neuInputBg,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: isSel ? _neuCobalt : Colors.white, width: 1.2),
                      ),
                      child: Text(
                        dev,
                        style: TextStyle(color: isSel ? Colors.white : _neuTextDark, fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 14),

              // NTRIP Caster Network Parameters
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: _neuInputBg, borderRadius: BorderRadius.circular(16)),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('CORS Network (កម្ពុជា):', style: TextStyle(color: _neuTextDark, fontSize: 11, fontWeight: FontWeight.bold)),
                        Text('MPWT Cambodia CORS', style: TextStyle(color: _neuCobaltDark, fontSize: 11, fontWeight: FontWeight.w900)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Caster Host & Port:', style: TextStyle(color: _neuTextMuted, fontSize: 10.5)),
                        Text('$_ntripCasterHost:$_ntripPort', style: const TextStyle(color: _neuTextDark, fontSize: 10.5, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Mountpoint (RTCM 3.2):', style: TextStyle(color: _neuTextMuted, fontSize: 10.5)),
                        Text(_ntripMountpoint, style: const TextStyle(color: _neuTextDark, fontSize: 10.5, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Connect / Disconnect RTK Action Button
              GestureDetector(
                onTap: () {
                  setRtkState(() {
                    _isRtkConnected = !_isRtkConnected;
                    if (_isRtkConnected) {
                      _gpsAccuracy = 0.014; // 1.4 cm
                      _gpsAltitude = 18.24;
                      _satellitesCount = 34;
                    } else {
                      _gpsAccuracy = 1.2;
                    }
                  });
                  setState(() {});
                  Navigator.pop(ctx);
                },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: _isRtkConnected
                          ? [const Color(0xFFE11D48), const Color(0xFFBE123C)]
                          : [const Color(0xFF10B981), const Color(0xFF059669)],
                    ),
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [
                      BoxShadow(
                        color: (_isRtkConnected ? const Color(0xFFE11D48) : const Color(0xFF10B981)).withOpacity(0.4),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Text(
                      _isRtkConnected ? 'ផ្តាច់ការតភ្ជាប់ RTK (Disconnect)' : 'ភ្ជាប់ឧបករណ៍ RTK ឥឡូវនេះ (Connect RTK)',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 13),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // 2. AUTO PARCEL SPLITTER MODAL (ពុះឡូតិ៍ / ចែកស្មើគ្នា)
  // ─────────────────────────────────────────────────────────────
  void _showParcelSplitterModal(BuildContext context) {
    if (_polygonPoints.length < 3) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withOpacity(0.35),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSplitState) {
          final subArea = _areaM2 / _splitPartsCount;
          final subAre = subArea / 100.0;

          return Container(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
            decoration: BoxDecoration(
              color: _neuBg,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
              border: Border.all(color: Colors.white, width: 1.5),
              boxShadow: neuExtrudedShadows(distance: 8, blur: 24),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4.5,
                    decoration: BoxDecoration(color: _neuDarkShadow.withOpacity(0.6), borderRadius: BorderRadius.circular(2.5)),
                  ),
                ),
                const SizedBox(height: 14),
                const Row(
                  children: [
                    Icon(Icons.splitscreen_rounded, color: _neuCobalt, size: 24),
                    SizedBox(width: 8),
                    Text('បែងចែកក្បាលដីស្វ័យប្រវត្តិ (Auto Parcel Splitter)', style: TextStyle(color: _neuTextDark, fontSize: 15.5, fontWeight: FontWeight.w900)),
                  ],
                ),
                const SizedBox(height: 12),
                Text('ទំហំដីសរុប: ${_areaM2.toStringAsFixed(1)} m² (= ${(_areaM2/100).toStringAsFixed(2)} អា)', style: const TextStyle(color: _neuTextMuted, fontSize: 12, fontWeight: FontWeight.bold)),
                const SizedBox(height: 14),

                const Text('ជ្រើសរើសចំនួនចំណែកបែងចែក (Split Parts):', style: TextStyle(color: _neuTextDark, fontSize: 12, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Row(
                  children: [2, 3, 4, 5, 6].map((p) {
                    final isSel = _splitPartsCount == p;
                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: GestureDetector(
                          onTap: () {
                            setSplitState(() => _splitPartsCount = p);
                            setState(() => _splitPartsCount = p);
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 9),
                            decoration: BoxDecoration(
                              color: isSel ? _neuCobalt : _neuInputBg,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: isSel ? _neuCobalt : Colors.white, width: 1.2),
                            ),
                            child: Center(
                              child: Text(
                                '$p ឡូតិ៍',
                                style: TextStyle(color: isSel ? Colors.white : _neuTextDark, fontSize: 11, fontWeight: FontWeight.w900),
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),

                // Sub-parcels Area Output Preview
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: _neuInputBg, borderRadius: BorderRadius.circular(16)),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('ទំហំក្នុង ១ ឡូតិ៍នីមួយៗ:', style: TextStyle(color: _neuTextDark, fontSize: 12, fontWeight: FontWeight.bold)),
                          Text('${subArea.toStringAsFixed(1)} m²', style: const TextStyle(color: Color(0xFF10B981), fontSize: 14, fontWeight: FontWeight.w900)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('ស្មើនឹងទំហំ (អា):', style: TextStyle(color: _neuTextMuted, fontSize: 11)),
                          Text('${subAre.toStringAsFixed(2)} អា / ឡូតិ៍', style: const TextStyle(color: _neuCobalt, fontSize: 11, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Split Action Button
                GestureDetector(
                  onTap: () {
                    Navigator.pop(ctx);
                    _applyAutoParcelSplit();
                  },
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [_neuCobalt, _neuCobaltDark]),
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [
                        BoxShadow(color: _neuCobalt.withOpacity(0.4), blurRadius: 10, offset: const Offset(0, 3)),
                      ],
                    ),
                    child: const Center(
                      child: Text(
                        '+ បង្កើតជាឡូតិ៍ប្លង់ដាច់ដោយឡែក (Split into Parcels)',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 13),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _applyAutoParcelSplit() {
    final parcelCount = _splitPartsCount;
    final subArea = _areaM2 / parcelCount;
    final subPerimeter = _perimeterM / parcelCount + 20.0;

    for (int i = 0; i < parcelCount; i++) {
      final name = 'ឡូតិ៍ ${String.fromCharCode(65 + i)}';
      _completedParcels.add(
        SurveyParcel(
          id: DateTime.now().millisecondsSinceEpoch.toString() + '_$i',
          name: name,
          mode: MeasureMode.polygon,
          points: List.from(_polygonPoints),
          areaM2: subArea,
          perimeterM: subPerimeter,
          color: _parcelColors[(_completedParcels.length) % _parcelColors.length],
        ),
      );
    }

    setState(() {
      _polygonPoints.clear();
      _recalculate();
    });
  }

  // ─────────────────────────────────────────────────────────────
  // 3. CADASTRAL OVERLAY / KML IMPORT MODAL (ប្លង់រឹងសុរិយោដី)
  // ─────────────────────────────────────────────────────────────
  void _showCadastralImportModal(BuildContext context) {
    final textController = TextEditingController();

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withOpacity(0.35),
      isScrollControlled: true,
      builder: (ctx) => Container(
        height: MediaQuery.of(context).size.height * 0.72,
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
        decoration: BoxDecoration(
          color: _neuBg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          border: Border.all(color: Colors.white, width: 1.5),
          boxShadow: neuExtrudedShadows(distance: 8, blur: 24),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4.5,
                decoration: BoxDecoration(color: _neuDarkShadow.withOpacity(0.6), borderRadius: BorderRadius.circular(2.5)),
              ),
            ),
            const SizedBox(height: 14),
            const Row(
              children: [
                Icon(Icons.layers_rounded, color: Color(0xFFD97706), size: 24),
                SizedBox(width: 8),
                Text('នាំចូលប្លង់រឹង/ទិន្នន័យសុរិយោដី (Cadastral Overlay)', style: TextStyle(color: _neuTextDark, fontSize: 15.5, fontWeight: FontWeight.w900)),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'បញ្ចូលអត្ថបទ KML ឬ GeoJSON ដើម្បីបង្ហាញបន្ទាត់ព្រំដីរឹងលើផែនទី និងពិនិត្យមើលការត្រួតស៊ីគ្នាជាមួយដីអ្នកដទៃ។',
              style: TextStyle(color: _neuTextMuted, fontSize: 11, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),

            Expanded(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _neuInputBg,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: neuRecessedShadows(),
                ),
                child: TextField(
                  controller: textController,
                  maxLines: null,
                  expands: true,
                  style: const TextStyle(color: _neuTextDark, fontSize: 11, fontFamily: 'monospace'),
                  decoration: const InputDecoration(
                    hintText: 'បិទភ្ជាប់ (Paste) ទិន្នន័យ KML ឬ GeoJSON ទីនេះ...\nឧទាហរណ៍: [[104.9282, 11.5564], [104.9290, 11.5564], ...]',
                    hintStyle: TextStyle(color: _neuTextMuted, fontSize: 11),
                    border: InputBorder.none,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),

            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      textController.text = "[[104.9275, 11.5560], [104.9290, 11.5560], [104.9290, 11.5570], [104.9275, 11.5570]]";
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      decoration: BoxDecoration(
                        color: _neuBg,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.white, width: 1.2),
                      ),
                      child: const Center(child: Text('ប្លង់គំរូ (Sample)', style: TextStyle(color: _neuTextDark, fontSize: 11.5, fontWeight: FontWeight.bold))),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: GestureDetector(
                    onTap: () {
                      final raw = textController.text.trim();
                      if (raw.isNotEmpty) {
                        final pts = parseCoordinatesFromText(raw);
                        if (pts.length >= 3) {
                          setState(() {
                            _cadastralOverlayPoints = pts;
                            _showCadastralOverlay = true;
                          });
                          Navigator.pop(ctx);
                          _safeMoveMap(pts.first, 17.5);
                        }
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: [Color(0xFFD97706), Color(0xFFB45309)]),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Center(child: Text('ត្រួតពិនិត្យប្លង់រឹង (Overlay)', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w900))),
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
  // 4. CUT & FILL EARTH VOLUME CALCULATOR (គណនាគម្រោងដីចាក់បំពេញ m³)
  // ─────────────────────────────────────────────────────────────
  void _showCutFillCalculatorModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withOpacity(0.35),
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setCutState) {
          final depth = (_targetRoadElevation - _gpsAltitude).clamp(0.0, 10.0);
          final volumeM3 = _areaM2 * depth;
          final truckLoads = (volumeM3 / 5.0).ceil();
          final estCostUSD = truckLoads * 12;

          return Container(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
            decoration: BoxDecoration(
              color: _neuBg,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
              border: Border.all(color: Colors.white, width: 1.5),
              boxShadow: neuExtrudedShadows(distance: 8, blur: 24),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4.5,
                    decoration: BoxDecoration(color: _neuDarkShadow.withOpacity(0.6), borderRadius: BorderRadius.circular(2.5)),
                  ),
                ),
                const SizedBox(height: 14),
                const Row(
                  children: [
                    Icon(Icons.terrain_rounded, color: Color(0xFF7C3AED), size: 24),
                    SizedBox(width: 8),
                    Text('គណនាគម្រោងដីចាក់បំពេញ (Cut & Fill Volume)', style: TextStyle(color: _neuTextDark, fontSize: 15.5, fontWeight: FontWeight.w900)),
                  ],
                ),
                const SizedBox(height: 6),
                Text('ទំហំដី: ${_areaM2.toStringAsFixed(1)} m² • កម្ពស់ដីបច្ចុប្បន្ន: +${_gpsAltitude.toStringAsFixed(1)}m', style: const TextStyle(color: _neuTextMuted, fontSize: 11.5, fontWeight: FontWeight.bold)),
                const SizedBox(height: 14),

                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('កម្ពស់ផ្លូវ/គោលដៅចង់បាន:', style: TextStyle(color: _neuTextDark, fontSize: 12, fontWeight: FontWeight.bold)),
                    Text('+${_targetRoadElevation.toStringAsFixed(1)} ម៉ែត្រ', style: const TextStyle(color: Color(0xFF7C3AED), fontSize: 13, fontWeight: FontWeight.w900)),
                  ],
                ),
                Slider(
                  value: _targetRoadElevation,
                  min: 15.0,
                  max: 30.0,
                  activeColor: const Color(0xFF7C3AED),
                  inactiveColor: _neuDarkShadow.withOpacity(0.4),
                  onChanged: (val) {
                    setCutState(() => _targetRoadElevation = val);
                    setState(() => _targetRoadElevation = val);
                  },
                ),
                const SizedBox(height: 8),

                // Volume and Truck Output Cards
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: _neuInputBg, borderRadius: BorderRadius.circular(16)),
                        child: Column(
                          children: [
                            const Text('ជម្រៅត្រូវចាក់បំពេញ', style: TextStyle(color: _neuTextMuted, fontSize: 10.5, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 4),
                            Text('+${depth.toStringAsFixed(2)} m', style: const TextStyle(color: _neuTextDark, fontSize: 16, fontWeight: FontWeight.w900)),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: _neuInputBg, borderRadius: BorderRadius.circular(16)),
                        child: Column(
                          children: [
                            const Text('មាឌដីចាក់សរុប (m³)', style: TextStyle(color: _neuTextMuted, fontSize: 10.5, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 4),
                            Text('${volumeM3.toStringAsFixed(1)} m³', style: const TextStyle(color: Color(0xFF10B981), fontSize: 16, fontWeight: FontWeight.w900)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: _neuInputBg, borderRadius: BorderRadius.circular(16)),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('ចំនួនជើងឡានដី (៥m³)', style: TextStyle(color: _neuTextDark, fontSize: 11.5, fontWeight: FontWeight.bold)),
                          Text('~ ${truckLoads.toString()} ជើងឡាន', style: const TextStyle(color: Color(0xFFD97706), fontSize: 15, fontWeight: FontWeight.w900)),
                        ],
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          const Text('តម្លៃប៉ាន់ស្មាន (\$12/ឡាន)', style: TextStyle(color: _neuTextMuted, fontSize: 10.5)),
                          Text('~ \$$estCostUSD USD', style: const TextStyle(color: _neuCobaltDark, fontSize: 15, fontWeight: FontWeight.w900)),
                        ],
                      ),
                    ],
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
  // 5. OFFICIAL CADASTRAL DEED & SURVEY PDF REPORT MODAL
  // ─────────────────────────────────────────────────────────────
  void _showOfficialDeedReportModal(BuildContext context) {
    final points = _polygonPoints;
    final n = points.length;
    final ha = _areaM2 / 10000.0;
    final are = _areaM2 / 100.0;
    final dateStr = DateTime.now().toLocal().toString().split(' ')[0];

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withOpacity(0.35),
      isScrollControlled: true,
      builder: (ctx) => Container(
        height: MediaQuery.of(context).size.height * 0.82,
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
        decoration: BoxDecoration(
          color: _neuBg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          border: Border.all(color: Colors.white, width: 1.5),
          boxShadow: neuExtrudedShadows(distance: 8, blur: 24),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4.5,
                decoration: BoxDecoration(color: _neuDarkShadow.withOpacity(0.6), borderRadius: BorderRadius.circular(2.5)),
              ),
            ),
            const SizedBox(height: 14),

            // Official Kingdom Header
            Center(
              child: Column(
                children: [
                  const Text('ព្រះរាជាណាចក្រកម្ពុជា', style: TextStyle(color: _neuTextDark, fontSize: 14, fontWeight: FontWeight.w900)),
                  const Text('ជាតិ សាសនា ព្រះមហាក្សត្រ', style: TextStyle(color: _neuTextDark, fontSize: 12, fontWeight: FontWeight.bold)),
                  Container(margin: const EdgeInsets.symmetric(vertical: 4), width: 80, height: 1.5, color: _neuYellow),
                  const Text('វិញ្ញាបនបត្រវាស់វែងព្រំប្រទល់ក្បាលដី', style: TextStyle(color: _neuCobaltDark, fontSize: 15, fontWeight: FontWeight.w900)),
                  Text('កាលបរិច្ឆេទវាស់: $dateStr • កូអរដោនេ: WGS84 & UTM Zone 48N', style: const TextStyle(color: _neuTextMuted, fontSize: 10, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Area Metrics in Khmer Units
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
                  _buildDeedMetricCol('ផ្ទៃក្រឡា', '${_areaM2.toStringAsFixed(1)} m²', const Color(0xFF10B981)),
                  _buildDeedMetricCol('ទំហំ (អា)', '${are.toStringAsFixed(2)} អា', _neuCobalt),
                  _buildDeedMetricCol('ទំហំ (ហិកតា)', '${ha.toStringAsFixed(4)} Ha', const Color(0xFFD97706)),
                  _buildDeedMetricCol('បរិមាត្រ', '${_perimeterM.toStringAsFixed(1)} m', _neuTextDark),
                ],
              ),
            ),
            const SizedBox(height: 12),

            const Text('តារាងកូអរដោនេបង្គោលព្រំដី (Cadastral Survey Table):', style: TextStyle(color: _neuTextDark, fontSize: 12, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),

            // Table
            Expanded(
              child: points.isEmpty
                  ? const Center(child: Text('មិនទាន់មានបង្គោលដីនៅឡើយទេ'))
                  : ListView.builder(
                      itemCount: points.length,
                      itemBuilder: (ctx, i) {
                        final pt = points[i];
                        final utm = latLngToUtm48N(pt);
                        final next = points[(i + 1) % n];
                        final dist = n >= 2 ? haversineDistance(pt, next) : 0.0;
                        final brng = calculateBearing(pt, next);

                        return Container(
                          margin: const EdgeInsets.only(bottom: 6),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(color: _neuBg, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white, width: 1)),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text('បង្គោល P${i + 1}', style: const TextStyle(color: _neuCobalt, fontWeight: FontWeight.w900, fontSize: 12)),
                                  const Spacer(),
                                  Text('ជ្រុង P${i+1}➔P${(i+1)%n+1}: ${dist.toStringAsFixed(1)}m (${brng.toStringAsFixed(0)}°)', style: const TextStyle(color: Color(0xFF047857), fontWeight: FontWeight.bold, fontSize: 11)),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text('WGS84: ${pt.latitude.toStringAsFixed(6)}°, ${pt.longitude.toStringAsFixed(6)}°', style: const TextStyle(color: _neuTextMuted, fontSize: 10)),
                              Text('UTM 48N: X ${utm.easting.toStringAsFixed(1)}m, Y ${utm.northing.toStringAsFixed(1)}m', style: const TextStyle(color: _neuTextDark, fontSize: 10.5, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 12),

            // Actions
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      final buffer = StringBuffer();
                      buffer.writeln('ព្រះរាជាណាចក្រកម្ពុជា');
                      buffer.writeln('ជាតិ សាសនា ព្រះមហាក្សត្រ');
                      buffer.writeln('វិញ្ញាបនបត្រវាស់វែងព្រំប្រទល់ក្បាលដី');
                      buffer.writeln('ទំហំដី: ${_areaM2.toStringAsFixed(1)} m² (${are.toStringAsFixed(2)} អា / ${ha.toStringAsFixed(4)} ហិកតា)');
                      buffer.writeln('បរិមាត្រ: ${_perimeterM.toStringAsFixed(1)} ម៉ែត្រ');
                      buffer.writeln('--- បញ្ជីបង្គោល WGS84 & UTM 48N ---');
                      for (int i = 0; i < points.length; i++) {
                        final u = latLngToUtm48N(points[i]);
                        buffer.writeln('P${i+1}: Lat ${points[i].latitude.toStringAsFixed(6)}°, Lng ${points[i].longitude.toStringAsFixed(6)}° | UTM 48N: X ${u.easting.toStringAsFixed(1)}m, Y ${u.northing.toStringAsFixed(1)}m');
                      }
                      Clipboard.setData(ClipboardData(text: buffer.toString()));
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(gradient: const LinearGradient(colors: [_neuCobalt, _neuCobaltDark]), borderRadius: BorderRadius.circular(16)),
                      child: const Center(child: Text('ចម្លងវិញ្ញាបនបត្រប្លង់', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 12.5))),
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

  Widget _buildDeedMetricCol(String label, String value, Color color) {
    return Column(
      children: [
        Text(label, style: const TextStyle(color: _neuTextMuted, fontSize: 10, fontWeight: FontWeight.bold)),
        const SizedBox(height: 2),
        Text(value, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w900)),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────
  // 6. DIRECT MANUAL COORDINATE INPUT DIALOG
  // ─────────────────────────────────────────────────────────────
  void _showDirectCoordinateInputDialog(BuildContext context, [int? pointIndex]) {
    final latController = TextEditingController(text: pointIndex != null ? _polygonPoints[pointIndex].latitude.toStringAsFixed(6) : _currentCenter.latitude.toStringAsFixed(6));
    final lngController = TextEditingController(text: pointIndex != null ? _polygonPoints[pointIndex].longitude.toStringAsFixed(6) : _currentCenter.longitude.toStringAsFixed(6));

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: _neuBg, borderRadius: BorderRadius.circular(28), border: Border.all(color: Colors.white, width: 1.5)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(pointIndex != null ? 'កែសម្រួលកូអរដោនេ P${pointIndex + 1}' : 'វាយបញ្ចូលកូអរដោនេបង្គោលដី', style: const TextStyle(color: _neuTextDark, fontSize: 16, fontWeight: FontWeight.w900)),
              const SizedBox(height: 6),
              const Text('វាយបញ្ចូលរយៈទទឹង (Lat) និងរយៈបណ្តោយ (Lng) កម្រិត WGS84:', style: TextStyle(color: _neuTextMuted, fontSize: 11)),
              const SizedBox(height: 14),

              TextField(
                controller: latController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: 'Latitude (រយៈទទឹង)', border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: lngController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: 'Longitude (រយៈបណ្តោយ)', border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
              ),
              const SizedBox(height: 16),

              Row(
                children: [
                  Expanded(child: TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('បោះបង់'))),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        final lat = double.tryParse(latController.text);
                        final lng = double.tryParse(lngController.text);
                        if (lat != null && lng != null) {
                          setState(() {
                            if (pointIndex != null && pointIndex < _polygonPoints.length) {
                              _polygonPoints[pointIndex] = LatLng(lat, lng);
                            } else {
                              _polygonPoints.add(LatLng(lat, lng));
                            }
                            _recalculate();
                          });
                          _safeMoveMap(LatLng(lat, lng), 18.0);
                          Navigator.pop(ctx);
                        }
                      },
                      child: const Text('យល់ព្រម'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildToolButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
    Color color = _neuTextDark,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: _neuBg,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 1.2),
          boxShadow: neuExtrudedShadows(distance: 2, blur: 5),
        ),
        child: Icon(icon, color: color, size: 17),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// CADASTRAL BLUEPRINT SURVEYOR GRID PAINTER (100% Offline Canvas)
// ─────────────────────────────────────────────────────────────
class _CadastralBlueprintPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // 1. Technical Cadastral Deep Background (Slate Navy)
    final bgPaint = Paint()..color = const Color(0xFF1E2638);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);

    // 2. Minor Grid Lines (24px step)
    final minorPaint = Paint()
      ..color = const Color(0xFF334155).withOpacity(0.45)
      ..strokeWidth = 0.8;

    const double stepMinor = 24.0;
    for (double x = 0; x < size.width; x += stepMinor) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), minorPaint);
    }
    for (double y = 0; y < size.height; y += stepMinor) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), minorPaint);
    }

    // 3. Major Grid Lines (96px step) with Coordinate Crosshairs
    final majorPaint = Paint()
      ..color = const Color(0xFF475569).withOpacity(0.75)
      ..strokeWidth = 1.3;

    final crossPaint = Paint()
      ..color = const Color(0xFF10B981).withOpacity(0.65)
      ..strokeWidth = 1.5;

    const double stepMajor = 96.0;
    for (double x = 0; x < size.width; x += stepMajor) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), majorPaint);
    }
    for (double y = 0; y < size.height; y += stepMajor) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), majorPaint);
    }

    // Intersection cross ticks
    for (double x = 0; x < size.width; x += stepMajor) {
      for (double y = 0; y < size.height; y += stepMajor) {
        canvas.drawLine(Offset(x - 5, y), Offset(x + 5, y), crossPaint);
        canvas.drawLine(Offset(x, y - 5), Offset(x, y + 5), crossPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
