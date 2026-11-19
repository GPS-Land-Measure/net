import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/camera_feed.dart';
import '../utils/compass_helper.dart';
import '../utils/geo_calculator.dart';

/// ═══════════════════════════════════════════════════════════════════════════
/// AR CAMERA MEASURE & DIGITAL LEVEL SCREEN (ម៉ាស៊ីនវាស់ប្រវែងតាម Camera AR)
/// Modeled after Apple / Android Measure App (Picture 2 Reference)
/// ═══════════════════════════════════════════════════════════════════════════
class CameraMeasureScreen extends StatefulWidget {
  const CameraMeasureScreen({super.key});

  @override
  State<CameraMeasureScreen> createState() => _CameraMeasureScreenState();
}

enum CameraToolMode { measure, area, height, level }

class ArMeasurePoint {
  final Offset position;
  final DateTime timestamp;

  ArMeasurePoint(this.position) : timestamp = DateTime.now();
}

class _CameraMeasureScreenState extends State<CameraMeasureScreen>
    with TickerProviderStateMixin {
  CameraToolMode _currentMode = CameraToolMode.measure;
  bool _isLiveCameraActive = false;
  final _cameraController = CameraFeedController();
  String? _capturedPhotoUrl;

  // New Pro Features: Zoom, Flashlight, Holding Height Calibration & Units
  double _cameraZoom = 1.0;
  bool _isFlashOn = false;
  double _holdingHeightM = 1.5;
  String _selectedUnit = 'm'; // 'm', 'cm', 'ft'

  // AR Points on Screen Canvas
  final List<Offset> _points = [];
  Offset _currentReticle = Offset.zero;

  // Unit mode: cm vs m
  bool _useMetricMeters = false; // false = cm, true = m
  double _scaleFactorCmPerPixel =
      0.28; // Calibration: ~0.28 cm per screen pixel at ~0.8m distance

  // Undo / History
  final List<List<Offset>> _undoHistory = [];
  final List<Map<String, dynamic>> _savedRecords = [];

  // Bubble Level Simulation
  double _pitchDeg = 0.0;
  double _rollDeg = 0.0;
  bool _isLevelLocked = false;

  // Flash Capture Animation
  bool _showFlash = false;

  // ── GPS Live Distance Tracking (Apple Measure-style) ──────────────────────
  // GPS anchor points (real-world LatLng corresponding to each _points entry)
  final List<LatLng> _gpsAnchorPoints = [];
  LatLng? _currentGpsPosition;
  double _liveGpsDistanceM =
      0.0; // Live distance from last anchor to current GPS
  bool _isGpsTracking = false; // True while measuring live
  StreamSubscription<Position>? _gpsTrackingStream;
  bool _gpsReady = false; // GPS has first fix
  double _gpsAccuracy = 0.0; // Current GPS accuracy in meters

  // Reticle & Cyber-HUD Animations
  late AnimationController _pulseController;
  late Animation<double> _pulseAnim;

  late AnimationController _radarScanController;
  late Animation<double> _radarScanAnim;

  late AnimationController _scanLineController;
  late Animation<double> _scanLineAnim;

  @override
  void initState() {
    super.initState();
    CompassHelper.init();
    _loadSavedRecords();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

    // Pulse animation for reticle while tracking
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.7, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Continuous 360-degree radar scanner sweep
    _radarScanController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4000),
    )..repeat();
    _radarScanAnim = Tween<double>(begin: 0.0, end: 2 * math.pi).animate(
      CurvedAnimation(parent: _radarScanController, curve: Curves.linear),
    );

    // Continuous vertical LiDAR laser scanline sweep
    _scanLineController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    )..repeat();
    _scanLineAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _scanLineController, curve: Curves.easeInOut),
    );

    // Warm up GPS so first fix is fast
    _initGps();
  }

  Future<void> _initGps() async {
    try {
      bool svc = await Geolocator.isLocationServiceEnabled();
      if (!svc) return;
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) return;

      // Get last known fast fix
      final last = await Geolocator.getLastKnownPosition();
      if (last != null && mounted) {
        setState(() {
          _currentGpsPosition = LatLng(last.latitude, last.longitude);
          _gpsAccuracy = last.accuracy;
          _gpsReady = true;
        });
      }

      // Start continuous background GPS stream for fast response
      _gpsTrackingStream = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          distanceFilter: 0,
        ),
      ).listen((pos) {
        if (!mounted) return;
        final loc = LatLng(pos.latitude, pos.longitude);
        setState(() {
          _currentGpsPosition = loc;
          _gpsAccuracy = pos.accuracy;
          _gpsReady = true;
        });
        // If tracking: update live distance from last anchor
        if (_isGpsTracking && _gpsAnchorPoints.isNotEmpty) {
          final dist = _totalGpsDistance() +
              haversineDistance(_gpsAnchorPoints.last, loc);
          setState(() => _liveGpsDistanceM = dist);
        }
      }, onError: (_) {});
    } catch (_) {}
  }

  /// Total committed GPS distance (sum of locked segments)
  double _totalGpsDistance() {
    if (_gpsAnchorPoints.length < 2) return 0.0;
    double sum = 0;
    for (int i = 0; i < _gpsAnchorPoints.length - 1; i++) {
      sum += haversineDistance(_gpsAnchorPoints[i], _gpsAnchorPoints[i + 1]);
    }
    return sum;
  }

  void _stopGpsTracking() {
    _gpsTrackingStream?.cancel();
    _gpsTrackingStream = null;
    setState(() => _isGpsTracking = false);
  }

  Future<void> _loadSavedRecords() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList('camera_measure_records') ?? [];
      setState(() {
        _savedRecords.clear();
        for (final item in list) {
          final parts = item.split('|');
          if (parts.length >= 2) {
            _savedRecords.add({
              'value': parts[0],
              'date': parts[1],
            });
          }
        }
      });
    } catch (_) {}
  }

  Future<void> _saveRecord(String value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime.now();
      final dateStr =
          '${now.day}/${now.month}/${now.year} ${now.hour}:${now.minute.toString().padLeft(2, '0')}';
      _savedRecords.insert(0, {'value': value, 'date': dateStr});
      final list =
          _savedRecords.map((r) => '${r['value']}|${r['date']}').toList();
      await prefs.setStringList('camera_measure_records', list);
    } catch (_) {}
  }

  void _triggerHaptic() {
    HapticFeedback.lightImpact();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _radarScanController.dispose();
    _scanLineController.dispose();
    _stopGpsTracking();
    super.dispose();
  }

  /// GPS-powered tap: First tap = set anchor; subsequent taps = lock segment
  void _addPoint() {
    _triggerHaptic();
    final gpsPos = _currentGpsPosition;

    setState(() {
      _undoHistory.add(List.from(_points));
      _points.add(_currentReticle);
    });

    if ((_currentMode == CameraToolMode.measure ||
            _currentMode == CameraToolMode.area) &&
        gpsPos != null) {
      // GPS-based tracking
      _gpsAnchorPoints.add(gpsPos);
      setState(() => _isGpsTracking = true);

      if (_gpsAnchorPoints.length >= 2) {
        final segDist = haversineDistance(
            _gpsAnchorPoints[_gpsAnchorPoints.length - 2],
            _gpsAnchorPoints.last);
        final totalDist = _totalGpsDistance();
        final txt = _formatGpsDistance(totalDist);
        _saveRecord('GPS ចម្ងាយ: $txt');
        setState(() {
          _liveGpsDistanceM = totalDist;
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Row(children: [
            const Icon(Icons.gps_fixed_rounded,
                color: Color(0xFF10B981), size: 16),
            const SizedBox(width: 8),
            Text(
                '📍 ចំណុច ${_gpsAnchorPoints.length}: +${_formatGpsDistance(segDist)} (សរុប: $txt)'),
          ]),
          backgroundColor: const Color(0xFF0F172A),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ));
      } else {
        setState(() {
          _liveGpsDistanceM = 0;
        });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Row(children: [
            Icon(Icons.radio_button_checked, color: Colors.white, size: 16),
            SizedBox(width: 8),
            Text('📍 ចំណុចចាប់ផ្តើម! ដើរបន្ត → ចម្ងាយ GPS ចេញ​តៗ'),
          ]),
          backgroundColor: Color(0xFF10B981),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2),
        ));
      }
    } else {
      // Pixel-based fallback (no GPS or height mode)
      if (_points.length >= 2) {
        final d =
            _computeDistanceMeters(_points[_points.length - 2], _points.last);
        _saveRecord('ប្រវែង: ${_formatDistance(d)}');
      }
    }
  }

  String _formatGpsDistance(double meters) {
    if (meters < 1.0) return '${(meters * 100).toStringAsFixed(0)} cm';
    if (meters < 1000) return '${meters.toStringAsFixed(2)} ម';
    return '${(meters / 1000).toStringAsFixed(3)} គម';
  }

  void _undo() {
    if (_undoHistory.isNotEmpty) {
      _triggerHaptic();
      setState(() {
        _points.clear();
        _points.addAll(_undoHistory.removeLast());
        // Also pop last GPS anchor
        if (_gpsAnchorPoints.isNotEmpty) _gpsAnchorPoints.removeLast();
        if (_gpsAnchorPoints.length < 2) {
          _liveGpsDistanceM = 0;
        }
        if (_gpsAnchorPoints.isEmpty) _isGpsTracking = false;
      });
    } else if (_points.isNotEmpty) {
      _triggerHaptic();
      setState(() {
        _points.removeLast();
        if (_gpsAnchorPoints.isNotEmpty) _gpsAnchorPoints.removeLast();
        if (_gpsAnchorPoints.length < 2) {
          _liveGpsDistanceM = 0;
        }
        if (_gpsAnchorPoints.isEmpty) _isGpsTracking = false;
      });
    }
  }

  void _clearAll() {
    if (_points.isEmpty) return;
    _triggerHaptic();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E2638),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('លុបការវាស់ទាំងអស់?',
            style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold)),
        content: const Text(
            'តើអ្នកពិតជាចង់សម្អាតចំណុចវាស់ទាំងអស់លើអេក្រង់មែនទេ?',
            style: TextStyle(color: Colors.white70, fontSize: 13)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child:
                const Text('បោះបង់', style: TextStyle(color: Colors.white60)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFEF4444)),
            onPressed: () {
              Navigator.pop(ctx);
              setState(() {
                _undoHistory.clear();
                _points.clear();
                _gpsAnchorPoints.clear();
                _liveGpsDistanceM = 0;
                _isGpsTracking = false;
              });
            },
            child: const Text('លុបទាំងអស់',
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _openNativeCamera() {
    _triggerHaptic();
    _cameraController.openNativeCamera((dataUrl) {
      if (mounted) {
        setState(() {
          _capturedPhotoUrl = dataUrl;
          _points.clear();
          _undoHistory.clear();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                '📸 បានថតរូបដីរួចរាល់! សូមចុចលើជ្រុងដីនីមួយៗលើរូបភាពដើម្បីវាស់'),
            backgroundColor: Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    });
  }

  void _clearCapturedPhoto() {
    _triggerHaptic();
    setState(() {
      _capturedPhotoUrl = null;
      _points.clear();
      _undoHistory.clear();
    });
  }

  void _capturePhoto() async {
    _triggerHaptic();
    setState(() => _showFlash = true);
    await Future.delayed(const Duration(milliseconds: 150));
    if (mounted) setState(() => _showFlash = false);

    if (_capturedPhotoUrl == null) {
      // 1. If currently in live camera view, freeze/capture current frame
      final frame = _cameraController.captureFrame();
      if (frame != null) {
        setState(() {
          _capturedPhotoUrl = frame;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                '📸 បានថតរូបដីរួចរាល់! សូមចុចលើជ្រុងដីនីមួយៗលើរូបភាពដើម្បីវាស់'),
            backgroundColor: Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        // 2. Open native camera directly
        _openNativeCamera();
      }
    } else {
      // Photo is already captured and measured, save the record!
      if (_points.length >= 2) {
        final totalDist = _computeTotalDistance();
        await _saveRecord(
            'ប្លង់ថតវាស់: ${_formatDistance(totalDist)} (${_points.length} ចំណុច)');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.check_circle_rounded,
                      color: Color(0xFF10B981)),
                  const SizedBox(width: 8),
                  Text(
                      '💾 បានរក្សាទុកការថតវាស់ដី: ${_formatDistance(totalDist)}'),
                ],
              ),
              backgroundColor: const Color(0xFF0F172A),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('សូមចុចលើជ្រុងដីយ៉ាងហោចណាស់ ២ ចំណុចដើម្បីវាស់ប្រវែង'),
            backgroundColor: Color(0xFF0F172A),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  double _computeDistanceMeters(Offset p1, Offset p2) {
    final dx = p1.dx - p2.dx;
    final dy = p1.dy - p2.dy;
    final pixelDist = math.sqrt(dx * dx + dy * dy);
    final effectiveScale = _scaleFactorCmPerPixel * (_holdingHeightM / 1.5);
    final cm = pixelDist * effectiveScale;
    return cm / 100.0; // returns meters
  }

  double _computeVerticalHeightMeters(Offset p1, Offset p2) {
    final dy = (p1.dy - p2.dy).abs();
    final effectiveScale = _scaleFactorCmPerPixel * (_holdingHeightM / 1.5);
    return (dy * effectiveScale) / 100.0;
  }

  double _computePolygonAreaM2() {
    if (_points.length < 3) return 0.0;
    double shoelace = 0.0;
    for (int i = 0; i < _points.length; i++) {
      final j = (i + 1) % _points.length;
      shoelace +=
          (_points[i].dx * _points[j].dy - _points[j].dx * _points[i].dy);
    }
    final pixelArea = shoelace.abs() / 2.0;
    final effectiveScale = _scaleFactorCmPerPixel * (_holdingHeightM / 1.5);
    final mPerPixel = effectiveScale / 100.0;
    return pixelArea * mPerPixel * mPerPixel;
  }

  double _computeTotalDistance() {
    if (_points.length < 2) return 0.0;
    double sum = 0.0;
    for (int i = 0; i < _points.length - 1; i++) {
      sum += _computeDistanceMeters(_points[i], _points[i + 1]);
    }
    if (_currentMode == CameraToolMode.area && _points.length >= 3) {
      sum += _computeDistanceMeters(_points.last, _points.first);
    }
    return sum;
  }

  String _formatDistance(double meters) {
    if (_selectedUnit == 'cm') {
      final cm = meters * 100.0;
      return '${cm.toStringAsFixed(0)} cm';
    } else if (_selectedUnit == 'ft') {
      final ft = meters * 3.28084;
      return '${ft.toStringAsFixed(1)} ft';
    } else {
      if (meters < 1.0 && !_useMetricMeters) {
        return '${(meters * 100).toStringAsFixed(0)} cm';
      }
      return '${meters.toStringAsFixed(2)} m';
    }
  }

  void _showCalibrationModal() {
    _triggerHaptic();
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF131A26),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setMState) => Container(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                      color: Colors.white30,
                      borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 14),
              const Row(
                children: [
                  Icon(Icons.tune_rounded, color: Color(0xFF10B981), size: 22),
                  SizedBox(width: 8),
                  Text('ក្រិតខ្នាតកាមេរ៉ាវាស់ដី (Camera Calibration)',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w900)),
                ],
              ),
              const SizedBox(height: 16),
              const Text('កម្ពស់កាន់ទូរស័ព្ទវាស់ (Phone Holding Height):',
                  style: TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Row(
                children: [1.2, 1.4, 1.5, 1.6, 1.7].map((h) {
                  final isSel = (_holdingHeightM - h).abs() < 0.05;
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: GestureDetector(
                        onTap: () {
                          setState(() => _holdingHeightM = h);
                          setMState(() {});
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: isSel
                                ? const Color(0xFF10B981)
                                : Colors.white12,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Center(
                            child: Text(
                              '${h}m',
                              style: TextStyle(
                                  color: isSel ? Colors.white : Colors.white70,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 18),
              const Text('ខ្នាតបង្ហាញ (Display Unit):',
                  style: TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Row(
                children: [
                  {'id': 'm', 'name': 'ម៉ែត្រ (m)'},
                  {'id': 'cm', 'name': 'សង់ទីម៉ែត្រ (cm)'},
                  {'id': 'ft', 'name': 'ហ្វីត (ft)'},
                ].map((u) {
                  final isSel = _selectedUnit == u['id'];
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: GestureDetector(
                        onTap: () {
                          setState(() => _selectedUnit = u['id'] as String);
                          setMState(() {});
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: isSel
                                ? const Color(0xFF1338BE)
                                : Colors.white12,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Center(
                            child: Text(
                              u['name'] as String,
                              style: TextStyle(
                                  color: isSel ? Colors.white : Colors.white70,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('យល់ព្រម',
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    if (_currentReticle == Offset.zero) {
      _currentReticle = Offset(size.width / 2, size.height / 2);
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // ── 1. CAMERA FEED / HIGH-TECH SIMULATION BACKDROP ──
          Positioned.fill(
            child: _buildCameraFeedBackdrop(size),
          ),

          // ── 2. AR VIEW-FINDER HUD BRACKETS & TELEMETRY ──
          _buildViewfinderHud(size),

          // ── 3. AR MEASUREMENT VECTOR CANVAS ──
          if (_currentMode != CameraToolMode.level &&
              (_isLiveCameraActive || _capturedPhotoUrl != null))
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: (details) {
                  setState(() {
                    _currentReticle = details.localPosition;
                  });
                  _addPoint();
                },
                onPanUpdate: (details) {
                  setState(() {
                    _currentReticle = details.localPosition;
                  });
                },
                child: CustomPaint(
                  painter: _ArRulerPainter(
                    points: _points,
                    currentReticle: _currentReticle,
                    scaleFactor: _scaleFactorCmPerPixel,
                    mode: _currentMode,
                    unit: _selectedUnit,
                  ),
                ),
              ),
            ),

          // ── 4. MISSION CONTROL AR ACTIVATION CARD (Hero Idle Overlay) ──
          if (!_isLiveCameraActive &&
              _capturedPhotoUrl == null &&
              _currentMode != CameraToolMode.level)
            _buildActivationHeroCard(size),

          // ── 5. BUBBLE LEVEL HUD (When in Level mode) ──
          if (_currentMode == CameraToolMode.level)
            Positioned.fill(
              child: _buildDigitalLevelView(size),
            ),

          // ── 6. TOP ACTION BAR (Frosted Glass Control Deck) ──
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 16,
            right: 16,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // List Records Button (with badge count)
                    _buildCircleIconButton(
                      icon: Icons.list_rounded,
                      badgeCount: _savedRecords.length,
                      onTap: _showSavedRecordsModal,
                    ),
                    const SizedBox(width: 8),
                    // Quick Snap / Native Camera
                    _buildCircleIconButton(
                      icon: Icons.camera_alt_rounded,
                      onTap: _openNativeCamera,
                    ),
                  ],
                ),

                // Back / Close Frosted Pill
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: BackdropFilter(
                      filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 7),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A).withOpacity(0.7),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.white24, width: 1),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.arrow_back_ios_new_rounded,
                                color: Colors.white, size: 12),
                            SizedBox(width: 5),
                            Text(
                              'ត្រឡប់ក្រោយ',
                              style: TextStyle(
                                fontFamily: 'Kantumruy Pro',
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Flashlight Toggle
                    _buildCircleIconButton(
                      icon: _isFlashOn
                          ? Icons.flashlight_on_rounded
                          : Icons.flashlight_off_rounded,
                      color:
                          _isFlashOn ? const Color(0xFFFBBF24) : Colors.white,
                      onTap: () {
                        _triggerHaptic();
                        setState(() => _isFlashOn = !_isFlashOn);
                      },
                    ),
                    const SizedBox(width: 6),
                    // Calibration Settings
                    _buildCircleIconButton(
                      icon: Icons.tune_rounded,
                      onTap: _showCalibrationModal,
                    ),
                    const SizedBox(width: 6),
                    if (_capturedPhotoUrl != null) ...[
                      GestureDetector(
                        onTap: _clearCapturedPhoto,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 7),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF2563EB), Color(0xFF1D4ED8)],
                            ),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                                color: const Color(0xFF60A5FA), width: 1),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.refresh_rounded,
                                  color: Colors.white, size: 14),
                              SizedBox(width: 4),
                              Text('ថតថ្មី',
                                  style: TextStyle(
                                      fontFamily: 'Kantumruy Pro',
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                    ],
                    // Trash Clear Button
                    _buildCircleIconButton(
                      icon: Icons.delete_outline_rounded,
                      onTap: _clearAll,
                    ),
                  ],
                ),
              ],
            ),
          ),

          // ── 7. CALIBRATION / LIVE STATUS PILL ──
          Positioned(
            top: MediaQuery.of(context).padding.top + 58,
            left: 20,
            right: 20,
            child: Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 6.5),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0B1320).withOpacity(0.75),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: Colors.white12, width: 1),
                      boxShadow: [
                        BoxShadow(
                            color: Colors.black.withOpacity(0.4),
                            blurRadius: 10),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AnimatedBuilder(
                          animation: _pulseAnim,
                          builder: (_, __) {
                            final statusColor = _capturedPhotoUrl != null
                                ? const Color(0xFF38BDF8)
                                : (_isLiveCameraActive
                                    ? const Color(0xFF10B981)
                                    : Colors.amber);
                            return Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: statusColor,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: statusColor
                                        .withOpacity(0.7 * _pulseAnim.value),
                                    blurRadius: 8,
                                    spreadRadius: 1.5,
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            _capturedPhotoUrl != null
                                ? '📸 បានថតរូបដីរួចរាល់: ចុចលើរូបដើម្បីវាស់ប្រវែង & ផ្ទៃក្រឡា'
                                : (_isGpsTracking
                                    ? '🚶‍♂️ កំពុងវាស់ចម្ងាយ GPS: សូមដើរទៅមុខ រួចចុច + នៅចំណុចបន្ទាប់'
                                    : (_isLiveCameraActive
                                        ? 'កាមេរ៉ា AR កំពុងដំណើរការ: ចុចលើអេក្រង់ ឬចុច + ដើម្បីវាស់'
                                        : '🎯 តម្រង់កែវឆ្លុះ (+) រួចចុចប៊ូតុង + ដើម្បីវាស់')),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontFamily: 'Kantumruy Pro',
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
            ),
          ),

          // ── 8. COMPASS AZIMUTH HUD BADGE ──
          Positioned(
            top: MediaQuery.of(context).padding.top + 98,
            left: 16,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A).withOpacity(0.7),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.white24, width: 0.8),
                  ),
                  child: ValueListenableBuilder<double>(
                    valueListenable: CompassHelper.headingNotifier,
                    builder: (context, heading, _) {
                      final h = heading.isNaN ? 0.0 : heading;
                      final dirShort = getCompassDirectionShort(h);
                      final dirKhmer = getCompassDirectionKhmer(h);
                      return Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.explore_rounded,
                              color: Color(0xFFFBBF24), size: 14),
                          const SizedBox(width: 5),
                          Text(
                            '${h.toInt()}° $dirShort ($dirKhmer)',
                            style: const TextStyle(
                              fontFamily: 'Kantumruy Pro',
                              color: Colors.white,
                              fontSize: 10.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ),

          // ── 9. FLOATING ZOOM SELECTOR (0.5x, 1x, 2x, 3x) ──
          Positioned(
            right: 14,
            bottom: 230,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A).withOpacity(0.75),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(
                        color: const Color(0xFF10B981).withOpacity(0.3),
                        width: 1),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black.withOpacity(0.5), blurRadius: 10),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [0.5, 1.0, 2.0, 3.0].map((z) {
                      final isSel = (_cameraZoom - z).abs() < 0.05;
                      return GestureDetector(
                        onTap: () {
                          _triggerHaptic();
                          setState(() => _cameraZoom = z);
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          margin: const EdgeInsets.symmetric(vertical: 2.5),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 5),
                          decoration: BoxDecoration(
                            gradient: isSel
                                ? const LinearGradient(
                                    colors: [
                                      Color(0xFF10B981),
                                      Color(0xFF059669)
                                    ],
                                  )
                                : null,
                            color: isSel ? null : Colors.transparent,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: isSel
                                ? [
                                    BoxShadow(
                                      color: const Color(0xFF10B981)
                                          .withOpacity(0.5),
                                      blurRadius: 8,
                                    ),
                                  ]
                                : null,
                          ),
                          child: Text(
                            '${z}x',
                            style: TextStyle(
                              color: isSel ? Colors.white : Colors.white70,
                              fontSize: 11,
                              fontWeight:
                                  isSel ? FontWeight.w900 : FontWeight.bold,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
            ),
          ),

          // ── 10. CAMERA FLASH EFFECT OVERLAY ──
          if (_showFlash)
            Positioned.fill(
              child: Container(color: Colors.white),
            ),

          // ── 11. BOTTOM CONTROL CLUSTER (Trigger, Undo, Shutter, Mode Dock) ──
          Positioned(
            left: 0,
            right: 0,
            bottom: MediaQuery.of(context).padding.bottom + 12,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── GPS Live Distance HUD ──────────────────────────────
                if (_isGpsTracking && _points.isNotEmpty)
                  AnimatedBuilder(
                    animation: _pulseAnim,
                    builder: (ctx, _) {
                      final liveFromAnchor = (_isGpsTracking &&
                              _gpsAnchorPoints.isNotEmpty &&
                              _currentGpsPosition != null)
                          ? _totalGpsDistance() +
                              haversineDistance(
                                  _gpsAnchorPoints.last, _currentGpsPosition!)
                          : _liveGpsDistanceM;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0B1623).withOpacity(0.92),
                          borderRadius: BorderRadius.circular(28),
                          border: Border.all(
                              color: const Color(0xFF10B981)
                                  .withOpacity(_pulseAnim.value),
                              width: 1.8),
                          boxShadow: [
                            BoxShadow(
                                color: const Color(0xFF10B981)
                                    .withOpacity(0.3 * _pulseAnim.value),
                                blurRadius: 14),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Pulsing GPS dot
                            Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: const Color(0xFF10B981)
                                    .withOpacity(_pulseAnim.value),
                                boxShadow: [
                                  BoxShadow(
                                      color: const Color(0xFF10B981)
                                          .withOpacity(0.5),
                                      blurRadius: 6)
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'GPS ចម្ងាយ: ${_formatGpsDistance(liveFromAnchor)}',
                                  style: const TextStyle(
                                      fontFamily: 'Kantumruy Pro',
                                      color: Colors.white,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w900),
                                ),
                                Text(
                                  '📍 ${_gpsAnchorPoints.length} ចំណុច • ភាពច្បាស់ ±${_gpsAccuracy.toStringAsFixed(0)} ម',
                                  style: const TextStyle(
                                      fontFamily: 'Kantumruy Pro',
                                      color: Colors.white60,
                                      fontSize: 10.5),
                                ),
                              ],
                            ),
                            const SizedBox(width: 10),
                            const Icon(Icons.gps_fixed_rounded,
                                color: Color(0xFF10B981), size: 16),
                          ],
                        ),
                      );
                    },
                  ),

                // ── Pixel-based / Area / Height Info Bar ──
                if (_currentMode != CameraToolMode.level &&
                    _points.isNotEmpty &&
                    !_isGpsTracking)
                  GestureDetector(
                    onTap: () {
                      setState(() => _useMetricMeters = !_useMetricMeters);
                      _triggerHaptic();
                    },
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 14),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F172A).withOpacity(0.88),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                            color: const Color(0xFF10B981).withOpacity(0.7),
                            width: 1.2),
                        boxShadow: [
                          BoxShadow(
                              color: const Color(0xFF10B981).withOpacity(0.2),
                              blurRadius: 12),
                        ],
                      ),
                      child: Text(
                        _currentMode == CameraToolMode.area &&
                                _points.length >= 3
                            ? '📐 ផ្ទៃដី: ${_computePolygonAreaM2().toStringAsFixed(1)} m² (${(_computePolygonAreaM2() / 100).toStringAsFixed(2)} អា) • ជុំវិញ: ${_formatDistance(_computeTotalDistance())}'
                            : (_currentMode == CameraToolMode.height &&
                                    _points.length >= 2
                                ? '🌲 កម្ពស់: ${_formatDistance(_computeVerticalHeightMeters(_points[0], _points[1]))}'
                                : 'សរុប: ${_formatDistance(_computeTotalDistance())} (${_points.length} ចំណុច)'),
                        style: const TextStyle(
                            fontFamily: 'Kantumruy Pro',
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w900),
                      ),
                    ),
                  ),

                // ── GPS No-Signal warning when + tapped but no GPS ──
                if (!_gpsReady && _points.isNotEmpty && !_isGpsTracking)
                  Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.85),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.gps_off_rounded,
                            color: Colors.white, size: 14),
                        SizedBox(width: 6),
                        Text('GPS មិនទាន់ត្រឹមត្រូវ — ប្រើស្ទង់ Screen',
                            style: TextStyle(
                                fontFamily: 'Kantumruy Pro',
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),

                // ── 3 Action Buttons (Undo, Master Cyber +, Shutter) ──
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 28),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Undo Button
                      _buildLargeActionButton(
                        icon: Icons.undo_rounded,
                        size: 56,
                        bgColor: const Color(0xFF0F172A).withOpacity(0.75),
                        iconColor:
                            _points.isNotEmpty ? Colors.white : Colors.white38,
                        onTap: _points.isNotEmpty ? _undo : null,
                      ),

                      // Master Cyber AR Trigger Button (+)
                      _buildMasterArTrigger(),

                      // Pro Shutter Capture Button
                      _buildShutterButton(),
                    ],
                  ),
                ),

                const SizedBox(height: 18),

                // ── 4. BOTTOM MODE SWITCHER DOCK (4 Modes) ──
                _buildModeSwitcherDock(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // CAMERA FEED SIMULATION / VIEWFINDER (Cybernetic Radar & LiDAR)
  // ─────────────────────────────────────────────────────────────
  Widget _buildCameraFeedBackdrop(Size size) {
    return RealCameraFeed(
      controller: _cameraController,
      capturedPhotoUrl: _capturedPhotoUrl,
      zoom: _cameraZoom,
      isFlashOn: _isFlashOn,
      onCameraStatusChanged: (active) {
        if (mounted) setState(() => _isLiveCameraActive = active);
      },
      fallback: AnimatedBuilder(
        animation: Listenable.merge(
            [_radarScanController, _scanLineController, _pulseController]),
        builder: (context, _) {
          return Container(
            color: const Color(0xFF030712),
            child: Stack(
              fit: StackFit.expand,
              children: [
                // 1. Deep Cybernetic Vignette Gradient
                Container(
                  decoration: const BoxDecoration(
                    gradient: RadialGradient(
                      center: Alignment(0, -0.1),
                      radius: 1.2,
                      colors: [
                        Color(0xFF0F172A),
                        Color(0xFF090E17),
                        Color(0xFF020408),
                      ],
                    ),
                  ),
                ),

                // 2. Realistic 3D Perspective Ground Plane Grid & LiDAR Radar
                CustomPaint(
                  painter: _CameraGroundPlanePainter(
                    radarAngle: _radarScanAnim.value,
                    scanProgress: _scanLineAnim.value,
                    pulse: _pulseAnim.value,
                  ),
                ),

                // 3. AR Surface Detection Mesh Dots & Constellations
                CustomPaint(
                  painter: _ArTrackingFeaturePointsPainter(
                    pulse: _pulseAnim.value,
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
  // DIGITAL SPIRIT BUBBLE LEVEL (កម្រិតទឹកស្ទង់តុល្យភាព)
  // ─────────────────────────────────────────────────────────────
  Widget _buildDigitalLevelView(Size size) {
    final isCentered = _pitchDeg.abs() < 1.0 && _rollDeg.abs() < 1.0;
    return GestureDetector(
      onTap: () {
        setState(() => _isLevelLocked = !_isLevelLocked);
        _triggerHaptic();
      },
      onPanUpdate: (d) {
        if (_isLevelLocked) return;
        setState(() {
          _rollDeg = (_rollDeg + d.delta.dx * 0.15).clamp(-45.0, 45.0);
          _pitchDeg = (_pitchDeg - d.delta.dy * 0.15).clamp(-45.0, 45.0);
        });
      },
      child: Container(
        color: isCentered ? const Color(0xFF047857) : Colors.black,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Bubble Discs
              SizedBox(
                width: 240,
                height: 240,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Outer Target Circle
                    Container(
                      width: 200,
                      height: 200,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white30, width: 2),
                      ),
                    ),
                    // Inner Center Target
                    Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: isCentered ? Colors.white : Colors.white24,
                            width: 1.5),
                      ),
                    ),
                    // Floating Bubble Disc
                    Transform.translate(
                      offset: Offset(_rollDeg * 2.8, -_pitchDeg * 2.8),
                      child: Container(
                        width: 90,
                        height: 90,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isCentered
                              ? Colors.white
                              : const Color(0xFF10B981).withOpacity(0.85),
                          boxShadow: [
                            BoxShadow(
                                color: const Color(0xFF10B981).withOpacity(0.5),
                                blurRadius: 18),
                          ],
                        ),
                        child: Center(
                          child: Text(
                            '${_pitchDeg.abs().toInt()}°',
                            style: TextStyle(
                              color: isCentered
                                  ? const Color(0xFF047857)
                                  : Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              Text(
                isCentered
                    ? 'ស្មើស្អាត ០° (Perfect Level)'
                    : '${_pitchDeg.toStringAsFixed(1)}°',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 6),
              Text(
                isCentered
                    ? 'ផ្ទៃរាបស្មើល្អ ១០០%'
                    : 'រំកិលទូរស័ព្ទដើម្បីរកកម្រិតស្មើ',
                style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // SAVED RECORDS SHEET MODAL
  // ─────────────────────────────────────────────────────────────
  void _showSavedRecordsModal() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF131A26),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                    color: Colors.white30,
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.history_rounded,
                        color: Color(0xFF10B981), size: 20),
                    SizedBox(width: 8),
                    Text(
                      'ប្រវត្តិវាស់វែងតាម Camera AR',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w900),
                    ),
                  ],
                ),
                if (_savedRecords.isNotEmpty)
                  GestureDetector(
                    onTap: () async {
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.remove('camera_measure_records');
                      setState(() => _savedRecords.clear());
                      Navigator.pop(ctx);
                    },
                    child: const Text('សម្អាត',
                        style: TextStyle(
                            color: Color(0xFFEF4444),
                            fontSize: 12,
                            fontWeight: FontWeight.bold)),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            if (_savedRecords.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 28),
                child: Center(
                  child: Text('មិនទាន់មានប្រវត្តិវាស់វែងទេ',
                      style: TextStyle(color: Colors.white54, fontSize: 13)),
                ),
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 280),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _savedRecords.length,
                  separatorBuilder: (_, __) =>
                      const Divider(color: Colors.white10, height: 1),
                  itemBuilder: (ctx, i) {
                    final item = _savedRecords[i];
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(item['value'] ?? '',
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14)),
                              Text(item['date'] ?? '',
                                  style: const TextStyle(
                                      color: Colors.white38, fontSize: 11)),
                            ],
                          ),
                          const Icon(Icons.straighten_rounded,
                              color: Color(0xFF10B981), size: 18),
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

  // ─────────────────────────────────────────────────────────────
  // 1. HIGH-TECH AR VIEWFINDER HUD (Corner Brackets & Pitch Ticks)
  // ─────────────────────────────────────────────────────────────
  Widget _buildViewfinderHud(Size size) {
    if (_currentMode == CameraToolMode.level) return const SizedBox.shrink();
    return IgnorePointer(
      child: Stack(
        children: [
          // Corner 1: Top-Left
          Positioned(
            top: MediaQuery.of(context).padding.top + 60,
            left: 20,
            child: _buildHudCorner(
              isTop: true,
              isLeft: true,
              label: 'AR-SURVEY // OPTIC-01',
            ),
          ),
          // Corner 2: Top-Right
          Positioned(
            top: MediaQuery.of(context).padding.top + 60,
            right: 20,
            child: _buildHudCorner(
              isTop: true,
              isLeft: false,
              label: 'LiDAR // 60FPS',
            ),
          ),
          // Corner 3: Bottom-Left
          Positioned(
            bottom: MediaQuery.of(context).padding.bottom + 120,
            left: 20,
            child: _buildHudCorner(
              isTop: false,
              isLeft: true,
              label: 'CAL // ${_holdingHeightM.toStringAsFixed(1)}m',
            ),
          ),
          // Corner 4: Bottom-Right
          Positioned(
            bottom: MediaQuery.of(context).padding.bottom + 120,
            right: 20,
            child: _buildHudCorner(
              isTop: false,
              isLeft: false,
              label: 'SYS // ${_useMetricMeters ? "METRIC" : "METRIC/CM"}',
            ),
          ),
          // Left Artificial Horizon Level Ladder
          Positioned(
            left: 10,
            top: size.height * 0.42,
            child: _buildPitchLadder(isLeft: true),
          ),
          // Right Artificial Horizon Level Ladder
          Positioned(
            right: 10,
            top: size.height * 0.42,
            child: _buildPitchLadder(isLeft: false),
          ),
        ],
      ),
    );
  }

  Widget _buildHudCorner(
      {required bool isTop, required bool isLeft, required String label}) {
    return Column(
      crossAxisAlignment:
          isLeft ? CrossAxisAlignment.start : CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!isTop) ...[
          Text(
            label,
            style: TextStyle(
              color: const Color(0xFF10B981).withOpacity(0.7),
              fontSize: 9,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w700,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(height: 3),
        ],
        CustomPaint(
          size: const Size(24, 24),
          painter: _HudCornerPainter(
            isTop: isTop,
            isLeft: isLeft,
            color: const Color(0xFF10B981).withOpacity(0.65),
          ),
        ),
        if (isTop) ...[
          const SizedBox(height: 3),
          Text(
            label,
            style: TextStyle(
              color: const Color(0xFF10B981).withOpacity(0.7),
              fontSize: 9,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w700,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildPitchLadder({required bool isLeft}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment:
          isLeft ? CrossAxisAlignment.start : CrossAxisAlignment.end,
      children: [
        Container(width: 6, height: 1, color: Colors.white24),
        const SizedBox(height: 10),
        Container(width: 12, height: 1, color: Colors.white38),
        const SizedBox(height: 10),
        Container(
          width: 18,
          height: 1.5,
          color: const Color(0xFF10B981).withOpacity(0.7),
        ),
        const SizedBox(height: 10),
        Container(width: 12, height: 1, color: Colors.white38),
        const SizedBox(height: 10),
        Container(width: 6, height: 1, color: Colors.white24),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────
  // 2. MISSION CONTROL AR ACTIVATION CARD (Hero Idle Overlay)
  // ─────────────────────────────────────────────────────────────
  Widget _buildActivationHeroCard(Size size) {
    return Positioned.fill(
      child: Container(
        color: Colors.black.withOpacity(0.45),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(28),
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(22, 22, 22, 22),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        const Color(0xFF0F172A).withOpacity(0.88),
                        const Color(0xFF020617).withOpacity(0.95),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(
                      color: const Color(0xFF10B981).withOpacity(0.35),
                      width: 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF10B981).withOpacity(0.18),
                        blurRadius: 36,
                        spreadRadius: 2,
                      ),
                      BoxShadow(
                        color: Colors.black.withOpacity(0.6),
                        blurRadius: 24,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Top Cyber Badge
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4.5),
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981).withOpacity(0.12),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: const Color(0xFF10B981).withOpacity(0.4),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            AnimatedBuilder(
                              animation: _pulseAnim,
                              builder: (_, __) => Container(
                                width: 7,
                                height: 7,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: const Color(0xFF10B981),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFF10B981)
                                          .withOpacity(_pulseAnim.value),
                                      blurRadius: 8,
                                      spreadRadius: 2,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 7),
                            const Text(
                              'AR LIDAR SURVEY SYSTEM • PRO',
                              style: TextStyle(
                                color: Color(0xFF34D399),
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.8,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),

                      // Holographic Camera Lens Core
                      GestureDetector(
                        onTap: () {
                          _triggerHaptic();
                          _cameraController.startCamera();
                        },
                        child: AnimatedBuilder(
                          animation: Listenable.merge(
                              [_radarScanController, _pulseController]),
                          builder: (context, _) {
                            return SizedBox(
                              width: 96,
                              height: 96,
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  // Rotating dashed cyber ring
                                  Transform.rotate(
                                    angle: _radarScanAnim.value,
                                    child: CustomPaint(
                                      size: const Size(96, 96),
                                      painter: _CyberDashedRingPainter(
                                        color: const Color(0xFF10B981)
                                            .withOpacity(0.55),
                                      ),
                                    ),
                                  ),
                                  // Pulsing outer glow ring
                                  Container(
                                    width: 82 * _pulseAnim.value,
                                    height: 82 * _pulseAnim.value,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: const Color(0xFF06B6D4)
                                            .withOpacity(
                                                0.5 * _pulseAnim.value),
                                        width: 1.5,
                                      ),
                                    ),
                                  ),
                                  // Center 3D Lens Core
                                  Container(
                                    width: 70,
                                    height: 70,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      gradient: const RadialGradient(
                                        center: Alignment(-0.2, -0.3),
                                        radius: 0.9,
                                        colors: [
                                          Color(0xFF34D399),
                                          Color(0xFF059669),
                                          Color(0xFF064E3B),
                                        ],
                                      ),
                                      border: Border.all(
                                          color: Colors.white.withOpacity(0.8),
                                          width: 2),
                                      boxShadow: [
                                        BoxShadow(
                                          color: const Color(0xFF10B981)
                                              .withOpacity(0.6),
                                          blurRadius: 20,
                                          spreadRadius: 2,
                                        ),
                                      ],
                                    ),
                                    child: const Center(
                                      child: Icon(Icons.videocam_rounded,
                                          color: Colors.white, size: 34),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Title & Subtitle
                      const Text(
                        'បើកប្រព័ន្ធ AR & Camera វាស់ដី',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'Kantumruy Pro',
                          color: Colors.white,
                          fontSize: 17.5,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'ឆ្លុះមើលទិដ្ឋភាពដីជាក់ស្តែង និងវាស់ប្រវែង ផ្ទៃក្រឡា ដោយបច្ចេកវិទ្យា AR & GPS សុក្រឹត',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'Kantumruy Pro',
                          color: Color(0xFF94A3B8),
                          fontSize: 12.5,
                          height: 1.45,
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Primary Button (Live Camera AR)
                      GestureDetector(
                        onTap: () {
                          _triggerHaptic();
                          _cameraController.startCamera();
                        },
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF10B981), Color(0xFF059669)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: const Color(0xFF6EE7B7).withOpacity(0.6),
                              width: 1.2,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color:
                                    const Color(0xFF10B981).withOpacity(0.45),
                                blurRadius: 18,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 38,
                                height: 38,
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.2),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.videocam_rounded,
                                    color: Colors.white, size: 20),
                              ),
                              const SizedBox(width: 12),
                              const Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      'បើក Live Camera (AR)',
                                      style: TextStyle(
                                        fontFamily: 'Kantumruy Pro',
                                        color: Colors.white,
                                        fontSize: 14.5,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    Text(
                                      'ស្កេនវាស់ដីផ្ទាល់លើអេក្រង់',
                                      style: TextStyle(
                                        fontFamily: 'Kantumruy Pro',
                                        color: Color(0xFFD1FAE5),
                                        fontSize: 11,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(Icons.arrow_forward_ios_rounded,
                                  color: Colors.white70, size: 14),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),

                      // Secondary Button (Phone Camera App)
                      GestureDetector(
                        onTap: _openNativeCamera,
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 11),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.06),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.white24, width: 1),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.08),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.camera_alt_rounded,
                                    color: Color(0xFF38BDF8), size: 18),
                              ),
                              const SizedBox(width: 12),
                              const Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      'ថតរូបដីតាមកាមេរ៉ាទូរស័ព្ទ',
                                      style: TextStyle(
                                        fontFamily: 'Kantumruy Pro',
                                        color: Colors.white,
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    Text(
                                      'Camera App • ថតរួចវាស់លើរូបភាព',
                                      style: TextStyle(
                                        fontFamily: 'Kantumruy Pro',
                                        color: Colors.white54,
                                        fontSize: 10.5,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(Icons.chevron_right_rounded,
                                  color: Colors.white38, size: 18),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Sensor Quick Telemetry Footer
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 7),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.35),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white10, width: 0.8),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            Text('🎯 0.28cm/px',
                                style: TextStyle(
                                    color: Color(0xFF34D399),
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.bold)),
                            Text('•', style: TextStyle(color: Colors.white24)),
                            Text('🛰️ GPS ស្វ័យប្រវត្តិ',
                                style: TextStyle(
                                    color: Colors.white70, fontSize: 10.5)),
                            Text('•', style: TextStyle(color: Colors.white24)),
                            Text('📐 Shoelace m²',
                                style: TextStyle(
                                    color: Colors.white70, fontSize: 10.5)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // 3. MASTER CYBER AR TRIGGER (+)
  // ─────────────────────────────────────────────────────────────
  Widget _buildMasterArTrigger() {
    return GestureDetector(
      onTap: _currentMode != CameraToolMode.level ? _addPoint : null,
      child: AnimatedBuilder(
        animation: _pulseAnim,
        builder: (context, _) {
          return SizedBox(
            width: 86,
            height: 86,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Outer Pulsing Neon Halo
                Container(
                  width: 84 * _pulseAnim.value,
                  height: 84 * _pulseAnim.value,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: const Color(0xFF10B981)
                          .withOpacity(0.45 * _pulseAnim.value),
                      width: 1.5,
                    ),
                  ),
                ),
                // Outer Titanium Stepped Bezel
                Container(
                  width: 76,
                  height: 76,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Color(0xFF2D3748),
                        Color(0xFF1A202C),
                        Color(0xFF0F172A)
                      ],
                    ),
                    border: Border.all(color: Colors.white24, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF10B981).withOpacity(0.35),
                        blurRadius: 18,
                        spreadRadius: 1,
                      ),
                      BoxShadow(
                        color: Colors.black.withOpacity(0.6),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                ),
                // Inner Cyber Dial
                CustomPaint(
                  size: const Size(66, 66),
                  painter: _CyberTriggerTicksPainter(
                    color: const Color(0xFF10B981).withOpacity(0.7),
                  ),
                ),
                // Center Core Button
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const RadialGradient(
                      colors: [Color(0xFF10B981), Color(0xFF047857)],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF10B981).withOpacity(0.6),
                        blurRadius: 10,
                      ),
                    ],
                  ),
                  child: const Center(
                    child:
                        Icon(Icons.add_rounded, color: Colors.white, size: 36),
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
  // 4. PRO SHUTTER / SNAPSHOT BUTTON
  // ─────────────────────────────────────────────────────────────
  Widget _buildShutterButton() {
    return GestureDetector(
      onTap: _capturePhoto,
      child: Container(
        width: 60,
        height: 60,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(
            colors: [Color(0xFF475569), Color(0xFF1E293B)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(color: Colors.white38, width: 2.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.5),
              blurRadius: 12,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Center(
          child: Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _capturedPhotoUrl != null
                  ? const Color(0xFF10B981)
                  : Colors.white,
              boxShadow: [
                BoxShadow(
                  color: (_capturedPhotoUrl != null
                          ? const Color(0xFF10B981)
                          : Colors.white)
                      .withOpacity(0.5),
                  blurRadius: 8,
                ),
              ],
            ),
            child: _capturedPhotoUrl != null
                ? const Icon(Icons.check_rounded, color: Colors.white, size: 26)
                : null,
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // 5. BOTTOM MODE SWITCHER DOCK (Frosted Cyber Dock)
  // ─────────────────────────────────────────────────────────────
  Widget _buildModeSwitcherDock() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A).withOpacity(0.85),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.white12, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.4),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(26),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildModePillItem(
                  icon: Icons.straighten_rounded,
                  label: 'វាស់ប្រវែង',
                  isSelected: _currentMode == CameraToolMode.measure,
                  onTap: () {
                    _triggerHaptic();
                    setState(() => _currentMode = CameraToolMode.measure);
                  },
                ),
                const SizedBox(width: 4),
                _buildModePillItem(
                  icon: Icons.crop_square_rounded,
                  label: 'វាស់ផ្ទៃដី',
                  isSelected: _currentMode == CameraToolMode.area,
                  onTap: () {
                    _triggerHaptic();
                    setState(() => _currentMode = CameraToolMode.area);
                  },
                ),
                const SizedBox(width: 4),
                _buildModePillItem(
                  icon: Icons.height_rounded,
                  label: 'វាស់កម្ពស់',
                  isSelected: _currentMode == CameraToolMode.height,
                  onTap: () {
                    _triggerHaptic();
                    setState(() => _currentMode = CameraToolMode.height);
                  },
                ),
                const SizedBox(width: 4),
                _buildModePillItem(
                  icon: Icons.panorama_horizontal_rounded,
                  label: 'កម្រិតទឹក',
                  isSelected: _currentMode == CameraToolMode.level,
                  onTap: () {
                    _triggerHaptic();
                    setState(() => _currentMode = CameraToolMode.level);
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // UI WIDGET HELPERS
  // ─────────────────────────────────────────────────────────────
  Widget _buildCircleIconButton({
    required IconData icon,
    required VoidCallback onTap,
    Color? color,
    int? badgeCount,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A).withOpacity(0.7),
              shape: BoxShape.circle,
              border: Border.all(
                color: color != null ? color.withOpacity(0.6) : Colors.white24,
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.4),
                  blurRadius: 8,
                ),
              ],
            ),
            child: Icon(icon, color: color ?? Colors.white, size: 21),
          ),
          if (badgeCount != null && badgeCount > 0)
            Positioned(
              top: -2,
              right: -2,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.black, width: 1.5),
                ),
                child: Text(
                  '$badgeCount',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildLargeActionButton({
    required IconData icon,
    required double size,
    required Color bgColor,
    required Color iconColor,
    required VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: bgColor,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white24, width: 1.2),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 10),
          ],
        ),
        child: Icon(icon, color: iconColor, size: 26),
      ),
    );
  }

  Widget _buildModePillItem({
    required IconData icon,
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          gradient: isSelected
              ? const LinearGradient(
                  colors: [Color(0xFF10B981), Color(0xFF059669)],
                )
              : null,
          color: isSelected ? null : Colors.transparent,
          borderRadius: BorderRadius.circular(22),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: const Color(0xFF10B981).withOpacity(0.4),
                    blurRadius: 10,
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: isSelected ? Colors.white : Colors.white60,
              size: 16,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Kantumruy Pro',
                color: isSelected ? Colors.white : Colors.white70,
                fontSize: 12.5,
                fontWeight: isSelected ? FontWeight.w900 : FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// AR RULER CANVAS PAINTER (High-Precision LiDAR Crosshair & Laser Beam)
// ─────────────────────────────────────────────────────────────
class _ArRulerPainter extends CustomPainter {
  final List<Offset> points;
  final Offset currentReticle;
  final double scaleFactor;
  final CameraToolMode mode;
  final String unit;

  _ArRulerPainter({
    required this.points,
    required this.currentReticle,
    required this.scaleFactor,
    this.mode = CameraToolMode.measure,
    this.unit = 'm',
  });

  @override
  void paint(Canvas canvas, Size size) {
    // A. Height Measurement Mode (Vertical Pole / Tree Height)
    if (mode == CameraToolMode.height) {
      if (points.length >= 2) {
        final p1 = points[0];
        final p2 = points[1];
        final hLinePaint = Paint()
          ..color = const Color(0xFF10B981)
          ..strokeWidth = 3.0;

        canvas.drawLine(p1, Offset(p1.dx, p2.dy), hLinePaint);
        canvas.drawLine(
          Offset(p1.dx, p2.dy),
          p2,
          Paint()
            ..color = Colors.white54
            ..strokeWidth = 1.5,
        );

        final dy = (p1.dy - p2.dy).abs();
        final hMeters = (dy * scaleFactor) / 100.0;
        final mid = Offset(p1.dx, (p1.dy + p2.dy) / 2);
        _drawMeasurementPill(
            canvas, mid, '🌲 កម្ពស់: ${hMeters.toStringAsFixed(2)} m');
      } else if (points.length == 1) {
        canvas.drawLine(
          points[0],
          Offset(points[0].dx, currentReticle.dy),
          Paint()
            ..color = const Color(0xFF10B981).withOpacity(0.8)
            ..strokeWidth = 2.0,
        );
      }
    } else {
      // B. Polygon Area & Line Distance Modes
      if ((mode == CameraToolMode.area && points.length >= 3) ||
          points.length >= 3) {
        final path = Path()..moveTo(points[0].dx, points[0].dy);
        for (int i = 1; i < points.length; i++) {
          path.lineTo(points[i].dx, points[i].dy);
        }
        path.close();

        final fillPaint = Paint()
          ..color = const Color(0xFF10B981).withOpacity(0.18)
          ..style = PaintingStyle.fill;
        canvas.drawPath(path, fillPaint);

        // Connect last point to first point with measured segment
        _drawMeasuredSegment(canvas, points.last, points.first, isLive: false);

        // Shoelace Area Calculation
        double shoelace = 0.0;
        double cx = 0.0;
        double cy = 0.0;
        for (int i = 0; i < points.length; i++) {
          final j = (i + 1) % points.length;
          shoelace +=
              (points[i].dx * points[j].dy - points[j].dx * points[i].dy);
          cx += points[i].dx;
          cy += points[i].dy;
        }
        final pixelArea = shoelace.abs() / 2.0;
        final m2 = pixelArea * (scaleFactor / 100.0) * (scaleFactor / 100.0);
        final center = Offset(cx / points.length, cy / points.length);

        String areaText = '${m2.toStringAsFixed(1)} m²';
        if (m2 >= 100) {
          areaText = '$areaText (${(m2 / 100).toStringAsFixed(2)} អា)';
        }
        _drawAreaPill(canvas, center, areaText);
      }

      // Connect consecutive points with measured segments
      if (points.length >= 2) {
        for (int i = 0; i < points.length - 1; i++) {
          _drawMeasuredSegment(canvas, points[i], points[i + 1], isLive: false);
        }
      }

      // Live measurement line from last anchor point to current reticle
      if (points.isNotEmpty &&
          (mode != CameraToolMode.height || points.length < 2)) {
        _drawMeasuredSegment(canvas, points.last, currentReticle, isLive: true);
      }
    }

    // Paint Anchor Fixed Points with Numbered Badges (①, ②, ③)
    final anchorPointPaint = Paint()
      ..color = const Color(0xFF10B981)
      ..style = PaintingStyle.fill;

    final anchorRingPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;

    for (int i = 0; i < points.length; i++) {
      final pt = points[i];
      // Glow halo
      canvas.drawCircle(
        pt,
        16,
        Paint()
          ..color = const Color(0xFF10B981).withOpacity(0.3)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
      canvas.drawCircle(pt, 12, anchorPointPaint);
      canvas.drawCircle(pt, 12, anchorRingPaint);

      final tp = TextPainter(
        text: TextSpan(
          text: '${i + 1}',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.w900,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(pt.dx - tp.width / 2, pt.dy - tp.height / 2));
    }

    // Draw Dynamic LiDAR Reticle
    _drawArReticle(canvas, currentReticle);
  }

  void _drawAreaPill(Canvas canvas, Offset pos, String text) {
    const textStyle = TextStyle(
      fontFamily: 'Kantumruy Pro',
      color: Colors.white,
      fontSize: 12.5,
      fontWeight: FontWeight.w900,
    );
    final textSpan = TextSpan(
      children: [
        const TextSpan(
            text: '📐 ផ្ទៃដី: ',
            style: TextStyle(
                color: Color(0xFFFBBF24), fontWeight: FontWeight.bold)),
        TextSpan(text: text),
      ],
      style: textStyle,
    );
    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();

    final pillWidth = textPainter.width + 20;
    final pillHeight = textPainter.height + 10;
    final pillRect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: pos, width: pillWidth, height: pillHeight),
      const Radius.circular(14),
    );

    final bgPaint = Paint()..color = const Color(0xFF0F172A).withOpacity(0.92);
    final borderPaint = Paint()
      ..color = const Color(0xFF10B981)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;

    canvas.drawRRect(pillRect, bgPaint);
    canvas.drawRRect(pillRect, borderPaint);

    textPainter.paint(
      canvas,
      Offset(pos.dx - textPainter.width / 2, pos.dy - textPainter.height / 2),
    );
  }

  void _drawArReticle(Canvas canvas, Offset center) {
    // 1. Center laser dot with neon halo
    final laserGlow = Paint()
      ..color = const Color(0xFF10B981).withOpacity(0.55)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    canvas.drawCircle(center, 7, laserGlow);

    final laserDot = Paint()
      ..color = const Color(0xFF34D399)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, 3.5, laserDot);

    // 2. High-precision corner brackets around reticle
    final bracketPaint = Paint()
      ..color = Colors.white.withOpacity(0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    const r = 24.0;
    const len = 7.0;

    // Top-Left
    canvas.drawLine(Offset(center.dx - r, center.dy - r + len),
        Offset(center.dx - r, center.dy - r), bracketPaint);
    canvas.drawLine(Offset(center.dx - r, center.dy - r),
        Offset(center.dx - r + len, center.dy - r), bracketPaint);

    // Top-Right
    canvas.drawLine(Offset(center.dx + r - len, center.dy - r),
        Offset(center.dx + r, center.dy - r), bracketPaint);
    canvas.drawLine(Offset(center.dx + r, center.dy - r),
        Offset(center.dx + r, center.dy - r + len), bracketPaint);

    // Bottom-Left
    canvas.drawLine(Offset(center.dx - r, center.dy + r - len),
        Offset(center.dx - r, center.dy + r), bracketPaint);
    canvas.drawLine(Offset(center.dx - r, center.dy + r),
        Offset(center.dx - r + len, center.dy + r), bracketPaint);

    // Bottom-Right
    canvas.drawLine(Offset(center.dx + r - len, center.dy + r),
        Offset(center.dx + r, center.dy + r), bracketPaint);
    canvas.drawLine(Offset(center.dx + r, center.dy + r),
        Offset(center.dx + r, center.dy + r - len), bracketPaint);

    // 3. Center crosshair ticks
    final tickPaint = Paint()
      ..color = const Color(0xFF10B981).withOpacity(0.8)
      ..strokeWidth = 1.2;
    canvas.drawLine(Offset(center.dx - 12, center.dy),
        Offset(center.dx - 5, center.dy), tickPaint);
    canvas.drawLine(Offset(center.dx + 5, center.dy),
        Offset(center.dx + 12, center.dy), tickPaint);
    canvas.drawLine(Offset(center.dx, center.dy - 12),
        Offset(center.dx, center.dy - 5), tickPaint);
    canvas.drawLine(Offset(center.dx, center.dy + 5),
        Offset(center.dx, center.dy + 12), tickPaint);
  }

  void _drawMeasuredSegment(Canvas canvas, Offset p1, Offset p2,
      {required bool isLive}) {
    // Neon Laser Glow underlayer
    final glowPaint = Paint()
      ..color = const Color(0xFF10B981).withOpacity(isLive ? 0.35 : 0.25)
      ..strokeWidth = 5.0
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);

    final linePaint = Paint()
      ..color = Colors.white.withOpacity(isLive ? 0.95 : 1.0)
      ..strokeWidth = 2.0;

    final dx = p2.dx - p1.dx;
    final dy = p2.dy - p1.dy;
    final totalLen = math.sqrt(dx * dx + dy * dy);
    if (totalLen < 1) return;

    // Draw dotted line
    const dashWidth = 5.0;
    const dashSpace = 4.0;
    double currentDist = 0.0;
    while (currentDist < totalLen) {
      final x1 = p1.dx + (dx * currentDist / totalLen);
      final y1 = p1.dy + (dy * currentDist / totalLen);
      final nextDist = math.min(currentDist + dashWidth, totalLen);
      final x2 = p1.dx + (dx * nextDist / totalLen);
      final y2 = p1.dy + (dy * nextDist / totalLen);
      canvas.drawLine(Offset(x1, y1), Offset(x2, y2), glowPaint);
      canvas.drawLine(Offset(x1, y1), Offset(x2, y2), linePaint);
      currentDist += dashWidth + dashSpace;
    }

    // Measurement Pill Label at Midpoint
    final mid = Offset((p1.dx + p2.dx) / 2, (p1.dy + p2.dy) / 2);
    final cm = totalLen * scaleFactor;
    String label;
    if (unit == 'cm') {
      label = '${cm.toStringAsFixed(0)} cm';
    } else if (unit == 'ft') {
      label = '${(cm / 100.0 * 3.28084).toStringAsFixed(1)} ft';
    } else {
      if (cm < 100) {
        label = '${cm.toStringAsFixed(0)} cm';
      } else {
        label = '${(cm / 100).toStringAsFixed(2)} m';
      }
    }

    _drawMeasurementPill(canvas, mid, label);
  }

  void _drawMeasurementPill(Canvas canvas, Offset pos, String text) {
    const textStyle = TextStyle(
      fontFamily: 'Kantumruy Pro',
      color: Colors.white,
      fontSize: 12.5,
      fontWeight: FontWeight.w900,
    );
    final textSpan = TextSpan(text: text, style: textStyle);
    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();

    final pillWidth = textPainter.width + 20;
    final pillHeight = textPainter.height + 10;
    final pillRect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: pos, width: pillWidth, height: pillHeight),
      const Radius.circular(14),
    );

    // Dark Frosted Glass with Neon Emerald Border
    final shadowPaint = Paint()
      ..color = Colors.black.withOpacity(0.55)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    canvas.drawRRect(pillRect.shift(const Offset(0, 3)), shadowPaint);

    final bgPaint = Paint()..color = const Color(0xFF0F172A).withOpacity(0.92);
    canvas.drawRRect(pillRect, bgPaint);

    final borderPaint = Paint()
      ..color = const Color(0xFF10B981)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    canvas.drawRRect(pillRect, borderPaint);

    // Paint Text
    textPainter.paint(
      canvas,
      Offset(pos.dx - textPainter.width / 2, pos.dy - textPainter.height / 2),
    );
  }

  @override
  bool shouldRepaint(covariant _ArRulerPainter oldDelegate) => true;
}

// ─────────────────────────────────────────────────────────────
// CAMERA SURFACE GROUND PLANE PAINTER (Cyber Grid & Rotating Radar)
// ─────────────────────────────────────────────────────────────
class _CameraGroundPlanePainter extends CustomPainter {
  final double radarAngle;
  final double scanProgress;
  final double pulse;

  _CameraGroundPlanePainter({
    this.radarAngle = 0.0,
    this.scanProgress = 0.0,
    this.pulse = 1.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final horizonY = size.height * 0.45;
    final center = Offset(size.width / 2, size.height * 0.52);

    // 1. Horizon Line
    final horizonPaint = Paint()
      ..color = const Color(0xFF10B981).withOpacity(0.2)
      ..strokeWidth = 1.0;
    canvas.drawLine(
        Offset(0, horizonY), Offset(size.width, horizonY), horizonPaint);

    // 2. 3D Perspective Ground Grid
    final gridPaint = Paint()
      ..color = const Color(0xFF06B6D4).withOpacity(0.08)
      ..strokeWidth = 1.0;

    for (double y = horizonY + 12;
        y < size.height;
        y += (y - horizonY + 18) * 0.32) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final vanishingPoint = Offset(size.width / 2, horizonY);
    for (double x = -size.width * 0.5;
        x <= size.width * 1.5;
        x += size.width * 0.18) {
      canvas.drawLine(vanishingPoint, Offset(x, size.height), gridPaint);
    }

    // 3. Concentric LiDAR Range Rings (centered on screen)
    final ringPaint = Paint()
      ..color = const Color(0xFF10B981).withOpacity(0.14)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    final rings = [70.0, 140.0, 220.0, 310.0];
    final labels = ['5M', '15M', '30M', '60M'];

    for (int i = 0; i < rings.length; i++) {
      final r = rings[i];
      canvas.drawCircle(center, r, ringPaint);

      // Range text along top axis
      final tp = TextPainter(
        text: TextSpan(
          text: labels[i],
          style: TextStyle(
            color: const Color(0xFF10B981).withOpacity(0.4),
            fontSize: 9,
            fontWeight: FontWeight.w700,
            fontFamily: 'monospace',
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(center.dx + 4, center.dy - r - 5));
    }

    // 4. Crosshairs & Angle Ticks
    final axisPaint = Paint()
      ..color = Colors.white.withOpacity(0.08)
      ..strokeWidth = 1.0;
    canvas.drawLine(Offset(center.dx - 320, center.dy),
        Offset(center.dx + 320, center.dy), axisPaint);
    canvas.drawLine(Offset(center.dx, center.dy - 320),
        Offset(center.dx, center.dy + 320), axisPaint);

    // 5. Rotating Radar Scanner Sweep
    final sweepPaint = Paint()
      ..shader = ui.Gradient.sweep(
        center,
        [
          const Color(0xFF10B981).withOpacity(0.0),
          const Color(0xFF10B981).withOpacity(0.0),
          const Color(0xFF10B981).withOpacity(0.02),
          const Color(0xFF10B981).withOpacity(0.18),
        ],
        [0.0, 0.7, 0.85, 1.0],
        TileMode.clamp,
        radarAngle - 0.5,
        radarAngle,
      );
    canvas.drawCircle(center, 260, sweepPaint);

    // Radar Leading Line
    final leadEnd = Offset(
      center.dx + 260 * math.cos(radarAngle),
      center.dy + 260 * math.sin(radarAngle),
    );
    final leadPaint = Paint()
      ..color = const Color(0xFF34D399).withOpacity(0.45)
      ..strokeWidth = 1.5;
    canvas.drawLine(center, leadEnd, leadPaint);

    // 6. Moving Horizontal LiDAR Scanline
    final scanY = size.height * scanProgress;
    final scanGlowPaint = Paint()
      ..shader = ui.Gradient.linear(
        Offset(0, scanY - 14),
        Offset(0, scanY + 14),
        [
          const Color(0xFF06B6D4).withOpacity(0.0),
          const Color(0xFF06B6D4).withOpacity(0.25),
          const Color(0xFF06B6D4).withOpacity(0.0),
        ],
      );
    canvas.drawRect(
        Rect.fromLTWH(0, scanY - 14, size.width, 28), scanGlowPaint);

    final scanCorePaint = Paint()
      ..color = const Color(0xFF38BDF8).withOpacity(0.4)
      ..strokeWidth = 1.2;
    canvas.drawLine(Offset(0, scanY), Offset(size.width, scanY), scanCorePaint);
  }

  @override
  bool shouldRepaint(covariant _CameraGroundPlanePainter oldDelegate) => true;
}

// ─────────────────────────────────────────────────────────────
// AR FEATURE POINTS PAINTER (Surrounding Scanning Dots & Mesh)
// ─────────────────────────────────────────────────────────────
class _ArTrackingFeaturePointsPainter extends CustomPainter {
  final double pulse;

  _ArTrackingFeaturePointsPainter({this.pulse = 1.0});

  @override
  void paint(Canvas canvas, Size size) {
    final dotPaint = Paint()
      ..color = const Color(0xFF34D399).withOpacity(0.28)
      ..style = PaintingStyle.fill;

    final haloPaint = Paint()
      ..color = const Color(0xFF10B981).withOpacity(0.12 * pulse)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    final linePaint = Paint()
      ..color = const Color(0xFF06B6D4).withOpacity(0.08)
      ..strokeWidth = 0.8;

    final rnd = math.Random(1337);
    final pts = <Offset>[];
    for (int i = 0; i < 48; i++) {
      final x = rnd.nextDouble() * size.width;
      final y = size.height * 0.25 + rnd.nextDouble() * size.height * 0.65;
      pts.add(Offset(x, y));
    }

    // Faint triangulation connections between nearby points
    for (int i = 0; i < pts.length; i++) {
      for (int j = i + 1; j < pts.length; j++) {
        final d = (pts[i] - pts[j]).distance;
        if (d < 70) {
          canvas.drawLine(pts[i], pts[j], linePaint);
        }
      }
    }

    // Draw dots and halos
    for (int i = 0; i < pts.length; i++) {
      final p = pts[i];
      canvas.drawCircle(p, 1.8, dotPaint);
      if (i % 6 == 0) {
        canvas.drawCircle(p, 6.0 * pulse, haloPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ArTrackingFeaturePointsPainter oldDelegate) =>
      true;
}

// ─────────────────────────────────────────────────────────────
// HUD CORNER & CYBER PAINTERS
// ─────────────────────────────────────────────────────────────
class _HudCornerPainter extends CustomPainter {
  final bool isTop;
  final bool isLeft;
  final Color color;

  _HudCornerPainter({
    required this.isTop,
    required this.isLeft,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    final path = Path();
    if (isTop && isLeft) {
      path.moveTo(0, size.height);
      path.lineTo(0, 0);
      path.lineTo(size.width, 0);
    } else if (isTop && !isLeft) {
      path.moveTo(size.width, size.height);
      path.lineTo(size.width, 0);
      path.lineTo(0, 0);
    } else if (!isTop && isLeft) {
      path.moveTo(0, 0);
      path.lineTo(0, size.height);
      path.lineTo(size.width, size.height);
    } else {
      path.moveTo(size.width, 0);
      path.lineTo(size.width, size.height);
      path.lineTo(0, size.height);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _CyberDashedRingPainter extends CustomPainter {
  final Color color;

  _CyberDashedRingPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 2;

    const totalDashes = 24;
    const sweep = (2 * math.pi) / totalDashes;
    for (int i = 0; i < totalDashes; i++) {
      if (i % 2 == 0) {
        final startAngle = i * sweep;
        canvas.drawArc(
          Rect.fromCircle(center: center, radius: radius),
          startAngle,
          sweep * 0.7,
          false,
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _CyberTriggerTicksPainter extends CustomPainter {
  final Color color;

  _CyberTriggerTicksPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5;

    final center = Offset(size.width / 2, size.height / 2);
    final r1 = size.width / 2 - 3;
    final r2 = size.width / 2 - 8;

    for (int i = 0; i < 12; i++) {
      final angle = (i * math.pi) / 6;
      final isMajor = i % 3 == 0;
      final innerR = isMajor ? r2 - 2 : r2;
      final p1 = Offset(
          center.dx + r1 * math.cos(angle), center.dy + r1 * math.sin(angle));
      final p2 = Offset(center.dx + innerR * math.cos(angle),
          center.dy + innerR * math.sin(angle));
      canvas.drawLine(p1, p2, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
