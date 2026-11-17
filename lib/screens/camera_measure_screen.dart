import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
    with SingleTickerProviderStateMixin {
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
  double _scaleFactorCmPerPixel = 0.28; // Calibration: ~0.28 cm per screen pixel at ~0.8m distance

  // Undo / History
  final List<List<Offset>> _undoHistory = [];
  final List<Map<String, dynamic>> _savedRecords = [];

  // Bubble Level Simulation
  double _pitchDeg = 0.0;
  double _rollDeg = 0.0;
  bool _isLevelLocked = false;

  // Flash Capture Animation
  bool _showFlash = false;

  @override
  void initState() {
    super.initState();
    CompassHelper.init();
    _loadSavedRecords();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);
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
      final dateStr = '${now.day}/${now.month}/${now.year} ${now.hour}:${now.minute.toString().padLeft(2, '0')}';
      _savedRecords.insert(0, {'value': value, 'date': dateStr});
      final list = _savedRecords.map((r) => '${r['value']}|${r['date']}').toList();
      await prefs.setStringList('camera_measure_records', list);
    } catch (_) {}
  }

  void _triggerHaptic() {
    HapticFeedback.lightImpact();
  }

  void _addPoint() {
    _triggerHaptic();
    setState(() {
      _undoHistory.add(List.from(_points));
      _points.add(_currentReticle);
    });

    if (_points.length >= 2) {
      final d = _computeDistanceMeters(_points[_points.length - 2], _points.last);
      final txt = _formatDistance(d);
      _saveRecord('ប្រវែង: $txt');
    }
  }

  void _undo() {
    if (_undoHistory.isNotEmpty) {
      _triggerHaptic();
      setState(() {
        _points.clear();
        _points.addAll(_undoHistory.removeLast());
      });
    } else if (_points.isNotEmpty) {
      _triggerHaptic();
      setState(() {
        _points.removeLast();
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
        title: const Text('លុបការវាស់ទាំងអស់?', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
        content: const Text('តើអ្នកពិតជាចង់សម្អាតចំណុចវាស់ទាំងអស់លើអេក្រង់មែនទេ?', style: TextStyle(color: Colors.white70, fontSize: 13)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('បោះបង់', style: TextStyle(color: Colors.white60)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
            onPressed: () {
              Navigator.pop(ctx);
              setState(() {
                _undoHistory.clear();
                _points.clear();
              });
            },
            child: const Text('លុបទាំងអស់', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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
            content: Text('📸 បានថតរូបដីរួចរាល់! សូមចុចលើជ្រុងដីនីមួយៗលើរូបភាពដើម្បីវាស់'),
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
            content: Text('📸 បានថតរូបដីរួចរាល់! សូមចុចលើជ្រុងដីនីមួយៗលើរូបភាពដើម្បីវាស់'),
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
        await _saveRecord('ប្លង់ថតវាស់: ${_formatDistance(totalDist)} (${_points.length} ចំណុច)');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.check_circle_rounded, color: Color(0xFF10B981)),
                  const SizedBox(width: 8),
                  Text('💾 បានរក្សាទុកការថតវាស់ដី: ${_formatDistance(totalDist)}'),
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
      shoelace += (_points[i].dx * _points[j].dy - _points[j].dx * _points[i].dy);
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
                  decoration: BoxDecoration(color: Colors.white30, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 14),
              const Row(
                children: [
                  Icon(Icons.tune_rounded, color: Color(0xFF10B981), size: 22),
                  SizedBox(width: 8),
                  Text('ក្រិតខ្នាតកាមេរ៉ាវាស់ដី (Camera Calibration)', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900)),
                ],
              ),
              const SizedBox(height: 16),
              const Text('កម្ពស់កាន់ទូរស័ព្ទវាស់ (Phone Holding Height):', style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold)),
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
                            color: isSel ? const Color(0xFF10B981) : Colors.white12,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Center(
                            child: Text(
                              '${h}m',
                              style: TextStyle(color: isSel ? Colors.white : Colors.white70, fontWeight: FontWeight.bold, fontSize: 12),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 18),
              const Text('ខ្នាតបង្ហាញ (Display Unit):', style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold)),
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
                            color: isSel ? const Color(0xFF1338BE) : Colors.white12,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Center(
                            child: Text(
                              u['name'] as String,
                              style: TextStyle(color: isSel ? Colors.white : Colors.white70, fontWeight: FontWeight.bold, fontSize: 11),
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
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('យល់ព្រម', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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
          // ── 1. CAMERA FEED / SIMULATION BACKDROP ──
          Positioned.fill(
            child: _buildCameraFeedBackdrop(size),
          ),

          // ── 2. AR MEASUREMENT VECTOR CANVAS ──
          if (_currentMode != CameraToolMode.level && (_isLiveCameraActive || _capturedPhotoUrl != null))
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

          // ── 2.1 OPEN CAMERA / TAKE PHOTO CTA OVERLAY (When Camera Not Yet Active) ──
          if (!_isLiveCameraActive && _capturedPhotoUrl == null && _currentMode != CameraToolMode.level)
            Positioned.fill(
              child: Container(
                color: Colors.black.withOpacity(0.55),
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      GestureDetector(
                        onTap: () {
                          _triggerHaptic();
                          _cameraController.startCamera();
                        },
                        child: Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF10B981), Color(0xFF059669)],
                            ),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(color: const Color(0xFF10B981).withOpacity(0.5), blurRadius: 24),
                            ],
                          ),
                          child: const Icon(Icons.videocam_rounded, color: Colors.white, size: 44),
                        ),
                      ),
                      const SizedBox(height: 18),
                      const Text(
                        'ចុចដើម្បីបើក Camera ឬថតរូបដី',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'កម្មវិធីត្រូវការកាមេរ៉ាដើម្បីឆ្លុះមើលទេសភាពដី និងវាស់ប្រវែងជាក់ស្តែង',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white70, fontSize: 12.5),
                      ),
                      const SizedBox(height: 22),
                      ElevatedButton.icon(
                        onPressed: () {
                          _triggerHaptic();
                          _cameraController.startCamera();
                        },
                        icon: const Icon(Icons.videocam_rounded, size: 20),
                        label: const Text('បើក Live Camera', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF10B981),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 13),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: _openNativeCamera,
                        icon: const Icon(Icons.camera_alt_rounded, size: 18),
                        label: const Text('ថតរូបដីតាមកាមេរ៉ាទូរស័ព្ទ (Camera App)'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Colors.white38),
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // ── 2.1 BUBBLE LEVEL HUD (When in Level mode) ──
          if (_currentMode == CameraToolMode.level)
            Positioned.fill(
              child: _buildDigitalLevelView(size),
            ),

          // ── 3. TOP ACTION BAR (Menu List & Trash Clear) ──
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
                    // List Records Button
                    _buildCircleIconButton(
                      icon: Icons.list_rounded,
                      onTap: _showSavedRecordsModal,
                    ),
                    const SizedBox(width: 8),
                    // Native Camera / Snap Button
                    _buildCircleIconButton(
                      icon: Icons.camera_alt_rounded,
                      onTap: _openNativeCamera,
                    ),
                  ],
                ),

                // Back / Close
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.55),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white24, width: 1),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 13),
                        SizedBox(width: 4),
                        Text('ត្រឡប់ក្រោយ', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ),

                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Flashlight Toggle
                    _buildCircleIconButton(
                      icon: _isFlashOn ? Icons.flashlight_on_rounded : Icons.flashlight_off_rounded,
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
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1338BE),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.white30, width: 1),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.refresh_rounded, color: Colors.white, size: 14),
                              SizedBox(width: 4),
                              Text('ថតថ្មី', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
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

          // ── 3.1 CALIBRATION / LIVE STATUS PILL ──
          Positioned(
            top: MediaQuery.of(context).padding.top + 54,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.65),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white12, width: 1),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: _capturedPhotoUrl != null
                            ? const Color(0xFF3B82F6)
                            : (_isLiveCameraActive ? const Color(0xFF10B981) : Colors.amber),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: (_capturedPhotoUrl != null
                                    ? const Color(0xFF3B82F6)
                                    : (_isLiveCameraActive ? const Color(0xFF10B981) : Colors.amber))
                                .withOpacity(0.6),
                            blurRadius: 6,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _capturedPhotoUrl != null
                          ? '📸 បានថតរូបដីរួចរាល់: ចុចលើរូបដើម្បីវាស់ប្រវែង & ផ្ទៃក្រឡា'
                          : (_isLiveCameraActive
                              ? 'កាមេរ៉ាជាក់ស្តែង: ចុចលើអេក្រង់ ឬចុច + ដើម្បីវាស់'
                              : 'តម្រង់កែវឆ្លុះ (+) រួចចុចប៊ូតុង + ដើម្បីវាស់'),
                      style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── 3.2 COMPASS AZIMUTH HUD BADGE ──
          Positioned(
            top: MediaQuery.of(context).padding.top + 92,
            left: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4.5),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.6),
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
                      const Icon(Icons.explore_rounded, color: Color(0xFFFBBF24), size: 14),
                      const SizedBox(width: 5),
                      Text(
                        '${h.toInt()}° $dirShort ($dirKhmer)',
                        style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.bold),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),

          // ── 3.3 FLOATING ZOOM SELECTOR (0.5x, 1x, 2x, 3x) ──
          Positioned(
            right: 14,
            bottom: 230,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.65),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: Colors.white24, width: 1),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 8),
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
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 2.5),
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
                      decoration: BoxDecoration(
                        color: isSel ? const Color(0xFF10B981) : Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${z}x',
                        style: TextStyle(
                          color: isSel ? Colors.white : Colors.white70,
                          fontSize: 11,
                          fontWeight: isSel ? FontWeight.w900 : FontWeight.bold,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),

          // ── 4. CAMERA FLASH EFFECT OVERLAY ──
          if (_showFlash)
            Positioned.fill(
              child: Container(color: Colors.white),
            ),

          // ── 5. BOTTOM CONTROL CLUSTER ──
          Positioned(
            left: 0,
            right: 0,
            bottom: MediaQuery.of(context).padding.bottom + 12,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── Calibration / Distance Info Bar ──
                if (_currentMode != CameraToolMode.level && _points.isNotEmpty)
                  GestureDetector(
                    onTap: () {
                      setState(() => _useMetricMeters = !_useMetricMeters);
                      _triggerHaptic();
                    },
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.75),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: const Color(0xFF10B981).withOpacity(0.6), width: 1.2),
                      ),
                      child: Text(
                        _currentMode == CameraToolMode.area && _points.length >= 3
                            ? '📐 ផ្ទៃដី: ${_computePolygonAreaM2().toStringAsFixed(1)} m² (${(_computePolygonAreaM2() / 100).toStringAsFixed(2)} អា) • ជុំវិញ: ${_formatDistance(_computeTotalDistance())}'
                            : (_currentMode == CameraToolMode.height && _points.length >= 2
                                ? '🌲 កម្ពស់: ${_formatDistance(_computeVerticalHeightMeters(_points[0], _points[1]))}'
                                : 'សរុប: ${_formatDistance(_computeTotalDistance())} (${_points.length} ចំណុច)'),
                        style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w900),
                      ),
                    ),
                  ),

                // ── 3 Action Buttons (Undo, Big +, Shutter) ──
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Undo Button
                      _buildLargeActionButton(
                        icon: Icons.undo_rounded,
                        size: 56,
                        bgColor: Colors.black.withOpacity(0.55),
                        iconColor: _points.isNotEmpty ? Colors.white : Colors.white38,
                        onTap: _points.isNotEmpty ? _undo : null,
                      ),

                      // Center Big Plus (+) Button
                      GestureDetector(
                        onTap: _currentMode != CameraToolMode.level ? _addPoint : null,
                        child: Container(
                          width: 76,
                          height: 76,
                          decoration: BoxDecoration(
                            color: const Color(0xFF22262E).withOpacity(0.9),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white24, width: 2),
                            boxShadow: [
                              BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 16, offset: const Offset(0, 4)),
                            ],
                          ),
                          child: const Icon(Icons.add_rounded, color: Colors.white, size: 40),
                        ),
                      ),

                      // Shutter Capture / Save Button
                      GestureDetector(
                        onTap: _capturePhoto,
                        child: Container(
                          width: 58,
                          height: 58,
                          decoration: BoxDecoration(
                            color: _capturedPhotoUrl != null ? const Color(0xFF10B981) : Colors.white,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.black.withOpacity(0.2), width: 3),
                            boxShadow: [
                              BoxShadow(
                                color: (_capturedPhotoUrl != null ? const Color(0xFF10B981) : Colors.white).withOpacity(0.4),
                                blurRadius: 10,
                              ),
                            ],
                          ),
                          child: _capturedPhotoUrl != null
                              ? const Icon(Icons.check_rounded, color: Colors.white, size: 30)
                              : null,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 22),

                // ── 4. BOTTOM MODE SWITCHER PILL (4 Modes) ──
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E242E).withOpacity(0.85),
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(color: Colors.white12, width: 1),
                  ),
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
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // CAMERA FEED SIMULATION / VIEWFINDER
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
      fallback: Container(
        color: const Color(0xFF0D1117),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Background Gradient / Texture
            Container(
              decoration: const BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(0, -0.2),
                  radius: 1.2,
                  colors: [
                    Color(0xFF222B38),
                    Color(0xFF0F141C),
                    Color(0xFF05070A),
                  ],
                ),
              ),
            ),

            // Realistic Perspective Grid (Camera Surface Ground Plane)
            CustomPaint(
              painter: _CameraGroundPlanePainter(),
            ),

            // AR Surface Detection Mesh Dots
            CustomPaint(
              painter: _ArTrackingFeaturePointsPainter(),
            ),
          ],
        ),
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
                        border: Border.all(color: isCentered ? Colors.white : Colors.white24, width: 1.5),
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
                          color: isCentered ? Colors.white : const Color(0xFF10B981).withOpacity(0.85),
                          boxShadow: [
                            BoxShadow(color: const Color(0xFF10B981).withOpacity(0.5), blurRadius: 18),
                          ],
                        ),
                        child: Center(
                          child: Text(
                            '${_pitchDeg.abs().toInt()}°',
                            style: TextStyle(
                              color: isCentered ? const Color(0xFF047857) : Colors.white,
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
                isCentered ? 'ស្មើស្អាត ០° (Perfect Level)' : '${_pitchDeg.toStringAsFixed(1)}°',
                style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 6),
              Text(
                isCentered ? 'ផ្ទៃរាបស្មើល្អ ១០០%' : 'រំកិលទូរស័ព្ទដើម្បីរកកម្រិតស្មើ',
                style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold),
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
                decoration: BoxDecoration(color: Colors.white30, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.history_rounded, color: Color(0xFF10B981), size: 20),
                    SizedBox(width: 8),
                    Text(
                      'ប្រវត្តិវាស់វែងតាម Camera AR',
                      style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900),
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
                    child: const Text('សម្អាត', style: TextStyle(color: Color(0xFFEF4444), fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            if (_savedRecords.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 28),
                child: Center(
                  child: Text('មិនទាន់មានប្រវត្តិវាស់វែងទេ', style: TextStyle(color: Colors.white54, fontSize: 13)),
                ),
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 280),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _savedRecords.length,
                  separatorBuilder: (_, __) => const Divider(color: Colors.white10, height: 1),
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
                              Text(item['value'] ?? '', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                              Text(item['date'] ?? '', style: const TextStyle(color: Colors.white38, fontSize: 11)),
                            ],
                          ),
                          const Icon(Icons.straighten_rounded, color: Color(0xFF10B981), size: 18),
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
  // UI WIDGET HELPERS
  // ─────────────────────────────────────────────────────────────
  Widget _buildCircleIconButton({required IconData icon, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.5),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white24, width: 1.2),
        ),
        child: Icon(icon, color: Colors.white, size: 22),
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
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? Colors.black.withOpacity(0.7) : Colors.transparent,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: isSelected ? Colors.white : Colors.white54, size: 17),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.white54,
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
// AR RULER CANVAS PAINTER (Dotted Line, Dynamic Measurement Pill, Reticle)
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
        _drawMeasurementPill(canvas, mid, '🌲 កម្ពស់: ${hMeters.toStringAsFixed(2)} m');
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
      if ((mode == CameraToolMode.area && points.length >= 3) || points.length >= 3) {
        final path = Path()..moveTo(points[0].dx, points[0].dy);
        for (int i = 1; i < points.length; i++) {
          path.lineTo(points[i].dx, points[i].dy);
        }
        path.close();

        final fillPaint = Paint()
          ..color = const Color(0xFF10B981).withOpacity(0.2)
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
          shoelace += (points[i].dx * points[j].dy - points[j].dx * points[i].dy);
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
      if (points.isNotEmpty && (mode != CameraToolMode.height || points.length < 2)) {
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

    // Draw Center Reticle: Open circle with center dot
    _drawArReticle(canvas, currentReticle);
  }

  void _drawAreaPill(Canvas canvas, Offset pos, String text) {
    const textStyle = TextStyle(
      color: Colors.white,
      fontSize: 12.5,
      fontWeight: FontWeight.w900,
    );
    final textSpan = TextSpan(
      children: [
        const TextSpan(text: '📐 ផ្ទៃដី: ', style: TextStyle(color: Color(0xFFFBBF24), fontWeight: FontWeight.bold)),
        TextSpan(text: text),
      ],
      style: textStyle,
    );
    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();

    final pillWidth = textPainter.width + 18;
    final pillHeight = textPainter.height + 8;
    final pillRect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: pos, width: pillWidth, height: pillHeight),
      const Radius.circular(14),
    );

    final bgPaint = Paint()..color = const Color(0xFF0F172A).withOpacity(0.9);
    final borderPaint = Paint()
      ..color = const Color(0xFF10B981)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    canvas.drawRRect(pillRect, bgPaint);
    canvas.drawRRect(pillRect, borderPaint);

    textPainter.paint(
      canvas,
      Offset(pos.dx - textPainter.width / 2, pos.dy - textPainter.height / 2),
    );
  }

  void _drawArReticle(Canvas canvas, Offset center) {
    final ringPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.8;

    final dotPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    // Draw center dot
    canvas.drawCircle(center, 3.5, dotPaint);

    // Draw broken circle arcs (Picture 2 exact replica)
    const radius = 28.0;
    final rect = Rect.fromCircle(center: center, radius: radius);

    // Arc 1 (Left side)
    canvas.drawArc(rect, 0.8, 1.5, false, ringPaint);
    // Arc 2 (Right side)
    canvas.drawArc(rect, 3.9, 1.5, false, ringPaint);
  }

  void _drawMeasuredSegment(Canvas canvas, Offset p1, Offset p2, {required bool isLive}) {
    final linePaint = Paint()
      ..color = Colors.white.withOpacity(isLive ? 0.9 : 1.0)
      ..strokeWidth = 2.0;

    // Draw dotted line
    final dx = p2.dx - p1.dx;
    final dy = p2.dy - p1.dy;
    final totalLen = math.sqrt(dx * dx + dy * dy);
    if (totalLen < 1) return;

    const dashWidth = 4.0;
    const dashSpace = 4.0;
    double currentDist = 0.0;
    while (currentDist < totalLen) {
      final x1 = p1.dx + (dx * currentDist / totalLen);
      final y1 = p1.dy + (dy * currentDist / totalLen);
      final nextDist = math.min(currentDist + dashWidth, totalLen);
      final x2 = p1.dx + (dx * nextDist / totalLen);
      final y2 = p1.dy + (dy * nextDist / totalLen);
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
      color: Colors.black,
      fontSize: 12.5,
      fontWeight: FontWeight.w900,
    );
    final textSpan = TextSpan(text: text, style: textStyle);
    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();

    final pillWidth = textPainter.width + 18;
    final pillHeight = textPainter.height + 8;
    final pillRect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: pos, width: pillWidth, height: pillHeight),
      const Radius.circular(14),
    );

    // White Pill Background with Shadow
    final shadowPaint = Paint()
      ..color = Colors.black.withOpacity(0.35)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    canvas.drawRRect(pillRect.shift(const Offset(0, 2)), shadowPaint);

    final bgPaint = Paint()..color = Colors.white;
    canvas.drawRRect(pillRect, bgPaint);

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
// CAMERA SURFACE GROUND PLANE PAINTER (Realistic 3D Perspective Grid)
// ─────────────────────────────────────────────────────────────
class _CameraGroundPlanePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = Colors.white.withOpacity(0.04)
      ..strokeWidth = 1.0;

    // Horizon line
    final horizonY = size.height * 0.45;

    // Horizontal perspective lines
    for (double y = horizonY; y < size.height; y += (y - horizonY + 20) * 0.3) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // Vanishing perspective rays
    final vanishingPoint = Offset(size.width / 2, horizonY);
    for (double x = -size.width * 0.5; x <= size.width * 1.5; x += size.width * 0.2) {
      canvas.drawLine(vanishingPoint, Offset(x, size.height), gridPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ─────────────────────────────────────────────────────────────
// AR FEATURE POINTS PAINTER (Surrounding Scanning Dots)
// ─────────────────────────────────────────────────────────────
class _ArTrackingFeaturePointsPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final dotPaint = Paint()
      ..color = Colors.white.withOpacity(0.18)
      ..style = PaintingStyle.fill;

    // Fixed sparse tracking dots
    final rnd = math.Random(42);
    for (int i = 0; i < 40; i++) {
      final x = rnd.nextDouble() * size.width;
      final y = size.height * 0.4 + rnd.nextDouble() * size.height * 0.55;
      final r = 1.2 + rnd.nextDouble() * 1.5;
      canvas.drawCircle(Offset(x, y), r, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
