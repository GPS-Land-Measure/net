import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// ═══════════════════════════════════════════════════════════════════════════
/// AR CAMERA MEASURE & DIGITAL LEVEL SCREEN (ម៉ាស៊ីនវាស់ប្រវែងតាម Camera AR)
/// Modeled after Apple / Android Measure App (Picture 2 Reference)
/// ═══════════════════════════════════════════════════════════════════════════
class CameraMeasureScreen extends StatefulWidget {
  const CameraMeasureScreen({super.key});

  @override
  State<CameraMeasureScreen> createState() => _CameraMeasureScreenState();
}

enum CameraToolMode { measure, level }

class ArMeasurePoint {
  final Offset position;
  final DateTime timestamp;

  ArMeasurePoint(this.position) : timestamp = DateTime.now();
}

class _CameraMeasureScreenState extends State<CameraMeasureScreen>
    with SingleTickerProviderStateMixin {
  CameraToolMode _currentMode = CameraToolMode.measure;

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

  void _capturePhoto() async {
    _triggerHaptic();
    setState(() => _showFlash = true);
    await Future.delayed(const Duration(milliseconds: 150));
    if (mounted) setState(() => _showFlash = false);

    if (_points.length >= 2) {
      final totalDist = _computeTotalDistance();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle_rounded, color: Color(0xFF10B981)),
              const SizedBox(width: 8),
              Text('📸 បានរក្សាទុករូបថតវាស់វែង: ${_formatDistance(totalDist)}'),
            ],
          ),
          backgroundColor: const Color(0xFF0F172A),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('📸 បានថតរូបប្លង់វាស់វែង'),
          backgroundColor: Color(0xFF0F172A),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  double _computeDistanceMeters(Offset p1, Offset p2) {
    final dx = p1.dx - p2.dx;
    final dy = p1.dy - p2.dy;
    final pixelDist = math.sqrt(dx * dx + dy * dy);
    final cm = pixelDist * _scaleFactorCmPerPixel;
    return cm / 100.0; // returns meters
  }

  double _computeTotalDistance() {
    if (_points.length < 2) return 0.0;
    double sum = 0.0;
    for (int i = 0; i < _points.length - 1; i++) {
      sum += _computeDistanceMeters(_points[i], _points[i + 1]);
    }
    return sum;
  }

  String _formatDistance(double meters) {
    final cm = meters * 100.0;
    if (cm < 100.0) {
      return '${cm.toStringAsFixed(0)} cm';
    } else {
      return '${meters.toStringAsFixed(2)} m';
    }
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
          if (_currentMode == CameraToolMode.measure)
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
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
                // List Records Button
                _buildCircleIconButton(
                  icon: Icons.list_rounded,
                  onTap: _showSavedRecordsModal,
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

                // Trash Clear Button
                _buildCircleIconButton(
                  icon: Icons.delete_outline_rounded,
                  onTap: _clearAll,
                ),
              ],
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
                if (_currentMode == CameraToolMode.measure && _points.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.7),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: Colors.white30, width: 1),
                    ),
                    child: Text(
                      'សរុប: ${_formatDistance(_computeTotalDistance())} (${_points.length} ចំណុច)',
                      style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w900),
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
                        onTap: _currentMode == CameraToolMode.measure ? _addPoint : null,
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

                      // Shutter Capture Button
                      GestureDetector(
                        onTap: _capturePhoto,
                        child: Container(
                          width: 58,
                          height: 58,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.black.withOpacity(0.2), width: 3),
                            boxShadow: [
                              BoxShadow(color: Colors.white.withOpacity(0.3), blurRadius: 10),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 22),

                // ── 4. BOTTOM MODE SWITCHER PILL (Measure | Level) ──
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E242E).withOpacity(0.85),
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(color: Colors.white12, width: 1),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildModePillItem(
                        icon: Icons.straighten_rounded,
                        label: 'Measure',
                        isSelected: _currentMode == CameraToolMode.measure,
                        onTap: () {
                          _triggerHaptic();
                          setState(() => _currentMode = CameraToolMode.measure);
                        },
                      ),
                      const SizedBox(width: 4),
                      _buildModePillItem(
                        icon: Icons.panorama_horizontal_rounded,
                        label: 'Level',
                        isSelected: _currentMode == CameraToolMode.level,
                        onTap: () {
                          _triggerHaptic();
                          setState(() => _currentMode = CameraToolMode.level);
                        },
                      ),
                    ],
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
    return Container(
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

          // Calibration / Hint text at top
          Positioned(
            top: MediaQuery.of(context).padding.top + 54,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.6),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: const BoxDecoration(
                        color: Color(0xFF10B981),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      'តម្រង់កែវឆ្លុះ (+) រួចចុចប៊ូតុង + ដើម្បីវាស់',
                      style: TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // DIGITAL SPIRIT BUBBLE LEVEL (កម្រិតទឹកស្ទង់តុល្យភាព)
  // ─────────────────────────────────────────────────────────────
  Widget _buildDigitalLevelView(Size size) {
    final isCentered = _pitchDeg.abs() < 1.0 && _rollDeg.abs() < 1.0;
    return GestureDetector(
      onPanUpdate: (d) {
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

  _ArRulerPainter({
    required this.points,
    required this.currentReticle,
    required this.scaleFactor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Paint Anchor Fixed Points
    final anchorPointPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    final anchorRingPaint = Paint()
      ..color = Colors.white.withOpacity(0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;

    for (final pt in points) {
      canvas.drawCircle(pt, 12, anchorRingPaint);
      canvas.drawCircle(pt, 5, anchorPointPaint);
    }

    // 2. Connect fixed points with solid/dotted lines
    if (points.length >= 2) {
      for (int i = 0; i < points.length - 1; i++) {
        _drawMeasuredSegment(canvas, points[i], points[i + 1], isLive: false);
      }
    }

    // 3. Live measurement line from last anchor point to current reticle
    if (points.isNotEmpty) {
      _drawMeasuredSegment(canvas, points.last, currentReticle, isLive: true);
    }

    // 4. Draw Center Reticle: Open circle with center dot (Picture 2 match!)
    _drawArReticle(canvas, currentReticle);
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
    if (cm < 100) {
      label = '${cm.toStringAsFixed(0)} cm';
    } else {
      label = '${(cm / 100).toStringAsFixed(2)} m';
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
