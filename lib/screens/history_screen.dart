import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/measurement.dart';
import 'map_measurement_screen.dart';

class HistoryScreen extends StatefulWidget {
  final bool isEmbedded;
  final VoidCallback? onBackToHome;
  final Function(Measurement)? onSelectMeasurement;

  const HistoryScreen({
    super.key,
    this.isEmbedded = false,
    this.onBackToHome,
    this.onSelectMeasurement,
  });

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  // Neumorphic Soft UI Palette
  static const Color _neuBg = Color(0xFFE8ECF2);
  static const Color _neuInputBg = Color(0xFFDFE4EC);
  static const Color _neuDarkShadow = Color(0xFFA6B4C9);
  static const Color _neuLightShadow = Color(0xFFFFFFFF);
  static const Color _neuCobalt = Color(0xFF1338BE);
  static const Color _neuCobaltDark = Color(0xFF0D2888);
  static const Color _neuTextDark = Color(0xFF1E2638);
  static const Color _neuTextMuted = Color(0xFF6B7A90);
  static const Color _neuGreen = Color(0xFF10B981);

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

  static List<BoxShadow> neuRecessedShadows() {
    return [
      BoxShadow(
        color: _neuDarkShadow.withOpacity(0.6),
        offset: const Offset(2.5, 2.5),
        blurRadius: 5,
      ),
      const BoxShadow(
        color: _neuLightShadow,
        offset: Offset(-2.5, -2.5),
        blurRadius: 5,
      ),
    ];
  }

  List<Measurement> _measurements = [];
  bool _loading = true;
  String _selectedFilter = 'ទាំងអស់'; // 'ទាំងអស់', 'ពហុកោណ', 'រាងចតុកោណ', 'រង្វង់'
  String _sortOrder = 'newest'; // 'newest', 'largest', 'smallest'
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.trim().toLowerCase();
      });
    });
    _loadMeasurements();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant HistoryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    _loadMeasurements();
  }

  Future<void> _loadMeasurements() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList('measurements') ?? [];
    setState(() {
      _measurements = list
          .map((s) => Measurement.fromJsonString(s))
          .toList();
      _sortList();
      _loading = false;
    });
  }

  void _sortList() {
    if (_sortOrder == 'newest') {
      _measurements.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    } else if (_sortOrder == 'largest') {
      _measurements.sort((a, b) => b.areaM2.compareTo(a.areaM2));
    } else if (_sortOrder == 'smallest') {
      _measurements.sort((a, b) => a.areaM2.compareTo(b.areaM2));
    }
  }

  Future<void> _saveMeasurementsToStorage() async {
    final prefs = await SharedPreferences.getInstance();
    final list = _measurements.map((m) => m.toJsonString()).toList();
    await prefs.setStringList('measurements', list);
  }

  Future<void> _deleteMeasurement(String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _neuBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Color(0xFFEF4444), size: 28),
            SizedBox(width: 10),
            Text(
              'លុបប្លង់ដី?',
              style: TextStyle(color: _neuTextDark, fontWeight: FontWeight.w900, fontSize: 18),
            ),
          ],
        ),
        content: const Text(
          'តើលោកអ្នកពិតជាចង់លុបទិន្នន័យប្លង់ដីនេះមែនទេ? សកម្មភាពនេះមិនអាចត្រឡប់វិញបានទេ។',
          style: TextStyle(color: _neuTextMuted, fontSize: 13.5, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('បោះបង់', style: TextStyle(color: _neuTextMuted, fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('លុបចេញ', style: TextStyle(fontWeight: FontWeight.w900)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList('measurements') ?? [];
    final updated = list
        .map((s) => Measurement.fromJsonString(s))
        .where((m) => m.id != id)
        .map((m) => m.toJsonString())
        .toList();
    await prefs.setStringList('measurements', updated);
    _loadMeasurements();
  }

  Future<void> _renameMeasurement(Measurement item) async {
    final nameCtrl = TextEditingController(text: item.name);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _neuBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text(
          '✏️ កែប្រែឈ្មោះប្លង់ដី',
          style: TextStyle(color: _neuTextDark, fontWeight: FontWeight.w900, fontSize: 18),
        ),
        content: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          decoration: BoxDecoration(
            color: _neuInputBg,
            borderRadius: BorderRadius.circular(16),
            boxShadow: neuRecessedShadows(),
          ),
          child: TextField(
            controller: nameCtrl,
            autofocus: true,
            style: const TextStyle(color: _neuTextDark, fontWeight: FontWeight.bold),
            decoration: const InputDecoration(
              border: InputBorder.none,
              hintText: 'បញ្ចូលឈ្មោះប្លង់ដីថ្មី...',
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('បោះបង់', style: TextStyle(color: _neuTextMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _neuCobalt,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            onPressed: () => Navigator.pop(ctx, nameCtrl.text.trim()),
            child: const Text('រក្សាទុក', style: TextStyle(fontWeight: FontWeight.w900)),
          ),
        ],
      ),
    );

    if (newName != null && newName.isNotEmpty && newName != item.name) {
      final updatedItem = Measurement(
        id: item.id,
        name: newName,
        type: item.type,
        areaM2: item.areaM2,
        perimeterM: item.perimeterM,
        createdAt: item.createdAt,
        points: item.points,
        centerLat: item.centerLat,
        centerLng: item.centerLng,
        radiusM: item.radiusM,
      );

      final idx = _measurements.indexWhere((m) => m.id == item.id);
      if (idx != -1) {
        setState(() {
          _measurements[idx] = updatedItem;
        });
        await _saveMeasurementsToStorage();
      }
    }
  }

  Future<void> _addSampleParcels() async {
    final now = DateTime.now();
    final sample1 = Measurement(
      id: '${now.millisecondsSinceEpoch}_1',
      name: 'ដីឡូតិ៍វីឡាទោល សែនសុខ ភ្នំពេញ #01',
      type: MeasurementType.polygon,
      areaM2: 1167.4,
      perimeterM: 139.4,
      createdAt: now.subtract(const Duration(hours: 2)),
      points: [
        {'lat': 11.54892, 'lng': 104.92873},
        {'lat': 11.54928, 'lng': 104.92876},
        {'lat': 11.54926, 'lng': 104.92915},
        {'lat': 11.54890, 'lng': 104.92912},
      ],
    );

    final sample2 = Measurement(
      id: '${now.millisecondsSinceEpoch}_2',
      name: 'ដីពាណិជ្ជកម្មក្បាលដី មហាវិថីព្រះសីហនុ',
      type: MeasurementType.polygon,
      areaM2: 3420.0,
      perimeterM: 245.8,
      createdAt: now.subtract(const Duration(days: 1)),
      points: [
        {'lat': 11.5590, 'lng': 104.9240},
        {'lat': 11.5620, 'lng': 104.9310},
        {'lat': 11.5570, 'lng': 104.9335},
        {'lat': 11.5540, 'lng': 104.9265},
      ],
    );

    final sample3 = Measurement(
      id: '${now.millisecondsSinceEpoch}_3',
      name: 'ដីចម្ការមាត់ស្ទឹង កំពត (២.៥ ហិកតា)',
      type: MeasurementType.polygon,
      areaM2: 25000.0,
      perimeterM: 640.0,
      createdAt: now.subtract(const Duration(days: 3)),
      points: [
        {'lat': 10.6120, 'lng': 104.1780},
        {'lat': 10.6150, 'lng': 104.1840},
        {'lat': 10.6110, 'lng': 104.1870},
        {'lat': 10.6080, 'lng': 104.1810},
      ],
    );

    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList('measurements') ?? [];
    list.add(sample1.toJsonString());
    list.add(sample2.toJsonString());
    list.add(sample3.toJsonString());
    await prefs.setStringList('measurements', list);
    _loadMeasurements();
  }

  void _showCoordinatesSheet(Measurement item) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        final pts = item.points ?? [];
        return Container(
          decoration: const BoxDecoration(
            color: _neuBg,
            borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
          ),
          padding: const EdgeInsets.fromLTRB(22, 14, 22, 30),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: _neuDarkShadow.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.name,
                          style: const TextStyle(
                            color: _neuTextDark,
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          '📍 បញ្ជីកូអរដោនេបង្គោលព្រំដី GPS WGS84',
                          style: TextStyle(
                            color: _neuTextMuted,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: _neuCobalt.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${pts.length} បង្គោល',
                      style: const TextStyle(
                        color: _neuCobalt,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              if (pts.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Center(
                    child: Text(
                      'គ្មានទិន្នន័យចំណុចកូអរដោនេលម្អិតទេ',
                      style: TextStyle(color: _neuTextMuted),
                    ),
                  ),
                )
              else
                Container(
                  constraints: const BoxConstraints(maxHeight: 280),
                  decoration: BoxDecoration(
                    color: _neuInputBg,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: neuRecessedShadows(),
                  ),
                  child: ListView.separated(
                    shrinkWrap: true,
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.all(12),
                    itemCount: pts.length,
                    separatorBuilder: (ctx, i) => const Divider(height: 14, color: Colors.white70),
                    itemBuilder: (c, i) {
                      final p = pts[i];
                      final lat = p['lat'] ?? 0.0;
                      final lng = p['lng'] ?? 0.0;
                      return Row(
                        children: [
                          Container(
                            width: 32,
                            height: 32,
                            decoration: const BoxDecoration(
                              color: _neuCobalt,
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: Text(
                                '${i + 1}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'បង្គោល P${i + 1}',
                                  style: const TextStyle(
                                    color: _neuTextDark,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                ),
                                Text(
                                  'Lat: ${lat.toStringAsFixed(6)}°,  Lng: ${lng.toStringAsFixed(6)}°',
                                  style: const TextStyle(
                                    color: _neuTextMuted,
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.copy_rounded, color: _neuCobalt, size: 18),
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: '$lat, $lng'));
                            },
                          ),
                        ],
                      );
                    },
                  ),
                ),

              const SizedBox(height: 20),

              // Copy All Button
              GestureDetector(
                onTap: () {
                  final textBuffer = StringBuffer();
                  textBuffer.writeln('=== កូអរដោនេប្លង់ដី: ${item.name} ===');
                  textBuffer.writeln('ផ្ទៃក្រឡា: ${item.areaM2.toStringAsFixed(1)} m²');
                  textBuffer.writeln('បរិមាត្រ: ${item.perimeterM.toStringAsFixed(1)} m');
                  for (int i = 0; i < pts.length; i++) {
                    final p = pts[i];
                    textBuffer.writeln('P${i + 1}: ${p['lat']}, ${p['lng']}');
                  }
                  Clipboard.setData(ClipboardData(text: textBuffer.toString()));
                  Navigator.pop(ctx);
                },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [_neuCobalt, _neuCobaltDark]),
                    borderRadius: BorderRadius.circular(18),
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
                      Icon(Icons.copy_all_rounded, color: Colors.white, size: 18),
                      SizedBox(width: 8),
                      Text(
                        'ចម្លងកូអរដោនេទាំងអស់ (Copy All)',
                        style: TextStyle(
                          color: Colors.white,
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
        );
      },
    );
  }

  void _showShareSummaryDialog(Measurement item) {
    final areaAre = (item.areaM2 / 100).toStringAsFixed(2);
    final areaHa = (item.areaM2 / 10000).toStringAsFixed(4);
    final estimatedUsd = (item.areaM2 * 120).toStringAsFixed(0);

    final summary = '''
📐 សេចក្តីសង្ខេបប្លង់ដី (Cadastral Land Summary)
━━━━━━━━━━━━━━━━━━━━
🏷️ ឈ្មោះប្លង់ដី: ${item.name}
📅 កាលបរិច្ឆេទវាស់: ${item.createdAt.day}/${item.createdAt.month}/${item.createdAt.year}
📐 ផ្ទៃក្រឡាសរុប: ${item.areaM2.toStringAsFixed(1)} ម៉ែត្រការ៉េ (m²)
🌾 គិតជាខ្នាតខ្មែរ: $areaAre អា  •  $areaHa ហិកតា
📏 បរិមាត្រព្រំដី: ${item.perimeterM.toStringAsFixed(1)} ម៉ែត្រ
📍 ចំនួនបង្គោលព្រំ: ${item.points?.length ?? 1} បង្គោល
💰 តម្លៃប៉ាន់ស្មាន (~120\$/m²): \$$estimatedUsd USD
━━━━━━━━━━━━━━━━━━━━
វាស់ដោយ: កម្មវិធី GPS Land Measure v2.0 Pro
''';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _neuBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Row(
          children: [
            Icon(Icons.share_rounded, color: _neuCobalt, size: 24),
            SizedBox(width: 10),
            Text(
              'ចែករំលែកសេចក្តីសង្ខេបប្លង់ដី',
              style: TextStyle(color: _neuTextDark, fontWeight: FontWeight.w900, fontSize: 16),
            ),
          ],
        ),
        content: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _neuInputBg,
            borderRadius: BorderRadius.circular(16),
            boxShadow: neuRecessedShadows(),
          ),
          child: SingleChildScrollView(
            child: Text(
              summary,
              style: const TextStyle(
                color: _neuTextDark,
                fontSize: 12,
                height: 1.5,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('បិទ', style: TextStyle(color: _neuTextMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _neuCobalt,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: summary));
              Navigator.pop(ctx);
            },
            child: const Text('ចម្លងទិន្នន័យ', style: TextStyle(fontWeight: FontWeight.w900)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filteredList = _measurements.where((m) {
      if (_selectedFilter == 'ពហុកោណ' && m.type != MeasurementType.polygon) return false;
      if (_selectedFilter == 'រង្វង់' && m.type != MeasurementType.circle) return false;
      if (_searchQuery.isNotEmpty && !m.name.toLowerCase().contains(_searchQuery)) {
        return false;
      }
      return true;
    }).toList();

    // Portfolio stats
    double totalAreaM2 = 0.0;
    for (final m in _measurements) {
      totalAreaM2 += m.areaM2;
    }
    final totalAreaHa = (totalAreaM2 / 10000).toStringAsFixed(2);
    final totalValueUsd = (totalAreaM2 * 120).toStringAsFixed(0);

    return Scaffold(
      backgroundColor: _neuBg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Custom Header
            _buildHeader(context),

            // Portfolio Overview Card
            if (_measurements.isNotEmpty)
              _buildPortfolioOverviewCard(totalAreaM2, totalAreaHa, totalValueUsd),

            // Search Bar
            _buildSearchBar(),

            // Filter Chips Row with Sort Option
            _buildFilterRow(),
            const SizedBox(height: 8),

            // Content List or Empty State
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(color: _neuCobalt),
                    )
                  : filteredList.isEmpty
                      ? _buildRichEmptyState(context)
                      : ListView.builder(
                          physics: const BouncingScrollPhysics(),
                          padding: EdgeInsets.only(
                            left: 20,
                            right: 20,
                            top: 4,
                            bottom: widget.isEmbedded ? 140 : 20,
                          ),
                          itemCount: filteredList.length,
                          itemBuilder: (ctx, index) {
                            return _buildSavedParcelCard(filteredList[index]);
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // 1. TOP CUSTOM HEADER
  // ─────────────────────────────────────────────────────────────
  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: _neuBg,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: Colors.white, width: 1.5),
          boxShadow: neuExtrudedShadows(distance: 3.5, blur: 10),
        ),
        child: Row(
          children: [
            GestureDetector(
              onTap: () {
                if (widget.onBackToHome != null) {
                  widget.onBackToHome!();
                } else {
                  Navigator.pop(context);
                }
              },
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: _neuBg,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 1.2),
                  boxShadow: neuExtrudedShadows(distance: 2, blur: 5),
                ),
                child: const Icon(
                  Icons.arrow_back_ios_new_rounded,
                  color: _neuCobalt,
                  size: 16,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'ប្រវត្តិប្លង់ដីរក្សាទុក',
                    style: TextStyle(
                      color: _neuTextDark,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    '${_measurements.length} ប្លង់ដីបានកត់ត្រាទុក',
                    style: const TextStyle(
                      color: _neuTextMuted,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),

            // Quick Add Sample Button
            GestureDetector(
              onTap: _addSampleParcels,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: _neuBg,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white, width: 1.2),
                  boxShadow: neuExtrudedShadows(distance: 2, blur: 5),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.add_location_alt_rounded, color: _neuCobalt, size: 15),
                    SizedBox(width: 4),
                    Text(
                      '+ គំរូដី',
                      style: TextStyle(
                        color: _neuCobalt,
                        fontSize: 11.5,
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
    );
  }

  // ─────────────────────────────────────────────────────────────
  // 2. PORTFOLIO OVERVIEW CARD
  // ─────────────────────────────────────────────────────────────
  Widget _buildPortfolioOverviewCard(double totalM2, String totalHa, String totalVal) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 6),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: _neuBg,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Colors.white, width: 1.5),
          boxShadow: neuExtrudedShadows(distance: 3, blur: 8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildStatItem('ប្លង់ដីសរុប', '${_measurements.length}', Icons.layers_rounded),
            Container(width: 1, height: 32, color: Colors.white.withOpacity(0.8)),
            _buildStatItem('ផ្ទៃដីសរុប', '$totalHa Ha', Icons.landscape_rounded),
            Container(width: 1, height: 32, color: Colors.white.withOpacity(0.8)),
            _buildStatItem('តម្លៃសរុប (~)', '\$$totalVal', Icons.monetization_on_rounded),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(String label, String value, IconData icon) {
    return Column(
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: _neuCobalt, size: 14),
            const SizedBox(width: 4),
            Text(
              label,
              style: const TextStyle(
                color: _neuTextMuted,
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 3),
        Text(
          value,
          style: const TextStyle(
            color: _neuCobalt,
            fontSize: 14.5,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────
  // 3. SEARCH BAR
  // ─────────────────────────────────────────────────────────────
  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 6),
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: _neuInputBg,
          borderRadius: BorderRadius.circular(20),
          boxShadow: neuRecessedShadows(),
          border: Border.all(color: Colors.white.withOpacity(0.6), width: 1),
        ),
        child: Row(
          children: [
            const Icon(Icons.search_rounded, color: _neuTextMuted, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _searchController,
                style: const TextStyle(
                  color: _neuTextDark,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
                decoration: const InputDecoration(
                  hintText: 'ស្វែងរកតាមឈ្មោះ ឬទីតាំងប្លង់ដី...',
                  hintStyle: TextStyle(color: _neuTextMuted, fontSize: 12),
                  border: InputBorder.none,
                  isDense: true,
                ),
              ),
            ),
            if (_searchQuery.isNotEmpty)
              GestureDetector(
                onTap: () {
                  _searchController.clear();
                },
                child: const Icon(Icons.close_rounded, color: _neuTextMuted, size: 18),
              ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // 4. FILTER CHIPS & SORT
  // ─────────────────────────────────────────────────────────────
  Widget _buildFilterRow() {
    final filters = ['ទាំងអស់', 'ពហុកោណ', 'រង្វង់'];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: filters.map((f) {
                final isSelected = _selectedFilter == f;
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: GestureDetector(
                    onTap: () => setState(() => _selectedFilter = f),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6.5),
                      decoration: BoxDecoration(
                        gradient: isSelected
                            ? const LinearGradient(colors: [_neuCobalt, _neuCobaltDark])
                            : null,
                        color: isSelected ? null : _neuBg,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isSelected ? Colors.white : Colors.white.withOpacity(0.9),
                          width: 1.2,
                        ),
                        boxShadow: isSelected
                            ? [
                                BoxShadow(
                                  color: _neuCobalt.withOpacity(0.4),
                                  blurRadius: 7,
                                  offset: const Offset(0, 2),
                                ),
                              ]
                            : neuExtrudedShadows(distance: 2, blur: 5),
                      ),
                      child: Text(
                        f,
                        style: TextStyle(
                          color: isSelected ? Colors.white : _neuTextDark,
                          fontSize: 11,
                          fontWeight: isSelected ? FontWeight.w900 : FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),

          // Sort Popup Menu
          PopupMenuButton<String>(
            icon: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: _neuBg,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white, width: 1.2),
                boxShadow: neuExtrudedShadows(distance: 2, blur: 5),
              ),
              child: const Row(
                children: [
                  Icon(Icons.sort_rounded, color: _neuCobalt, size: 15),
                  SizedBox(width: 4),
                  Text(
                    'តម្រៀប',
                    style: TextStyle(
                      color: _neuCobalt,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            color: _neuBg,
            onSelected: (val) {
              setState(() {
                _sortOrder = val;
                _sortList();
              });
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem(
                value: 'newest',
                child: Text('កាលបរិច្ឆេទថ្មីបំផុត', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              ),
              const PopupMenuItem(
                value: 'largest',
                child: Text('ទំហំដីធំជាងគេ', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              ),
              const PopupMenuItem(
                value: 'smallest',
                child: Text('ទំហំដីតូចជាងគេ', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // 5. SAVED LAND PARCEL CARD (Neumorphic Soft UI)
  // ─────────────────────────────────────────────────────────────
  Widget _buildSavedParcelCard(Measurement item) {
    final isPolygon = item.type == MeasurementType.polygon;
    final areaAre = (item.areaM2 / 100).toStringAsFixed(1);
    final areaHa = (item.areaM2 / 10000).toStringAsFixed(3);
    final pointsCount = item.points?.length ?? (item.type == MeasurementType.circle ? 1 : 0);
    final estPriceUsd = (item.areaM2 * 120).toStringAsFixed(0);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: _neuBg,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white, width: 1.5),
        boxShadow: neuExtrudedShadows(distance: 3.5, blur: 10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top Header of Card
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 3D Parcel Icon Badge
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: _neuBg,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white, width: 1.5),
                    boxShadow: neuExtrudedShadows(distance: 2.5, blur: 6),
                  ),
                  child: Center(
                    child: Icon(
                      isPolygon ? Icons.polyline_rounded : Icons.circle_outlined,
                      color: _neuCobalt,
                      size: 24,
                    ),
                  ),
                ),
                const SizedBox(width: 12),

                // Name & Metadata
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              item.name,
                              style: const TextStyle(
                                color: _neuTextDark,
                                fontSize: 14.5,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          GestureDetector(
                            onTap: () => _renameMeasurement(item),
                            child: const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 4),
                              child: Icon(Icons.edit_note_rounded, color: _neuTextMuted, size: 20),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          const Icon(Icons.verified_rounded, color: _neuGreen, size: 12),
                          const SizedBox(width: 4),
                          const Text(
                            'ប្លង់វាស់ត្រឹមត្រូវ',
                            style: TextStyle(
                              color: _neuGreen,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '•  ${item.createdAt.day}/${item.createdAt.month}/${item.createdAt.year}',
                            style: const TextStyle(
                              color: _neuTextMuted,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Delete Button
                GestureDetector(
                  onTap: () => _deleteMeasurement(item.id),
                  child: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: _neuBg,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 1.2),
                      boxShadow: neuExtrudedShadows(distance: 2, blur: 4),
                    ),
                    child: const Icon(
                      Icons.delete_outline_rounded,
                      color: Color(0xFFEF4444),
                      size: 17,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Area & Dimensions Inset Banner
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: _neuInputBg,
              border: Border.symmetric(
                horizontal: BorderSide(color: Colors.white.withOpacity(0.7), width: 1),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'ទំហំផ្ទៃក្រឡាដី:',
                      style: TextStyle(color: _neuTextMuted, fontSize: 10.5, fontWeight: FontWeight.bold),
                    ),
                    Row(
                      children: [
                        Text(
                          item.areaM2.toStringAsFixed(1),
                          style: const TextStyle(
                            color: _neuCobalt,
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Text(
                          'm²',
                          style: TextStyle(color: _neuCobalt, fontSize: 12, fontWeight: FontWeight.w900),
                        ),
                      ],
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '= $areaAre អា  •  $areaHa Ha',
                      style: const TextStyle(
                        color: _neuTextDark,
                        fontWeight: FontWeight.bold,
                        fontSize: 11.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'តម្លៃ ~$estPriceUsd USD',
                      style: const TextStyle(
                        color: _neuGreen,
                        fontWeight: FontWeight.w900,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Bottom Stats & Action Buttons
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
            child: Row(
              children: [
                // Perimeter & Markers Info
                Row(
                  children: [
                    const Icon(Icons.straighten_rounded, color: _neuTextMuted, size: 14),
                    const SizedBox(width: 4),
                    Text(
                      '${item.perimeterM.toStringAsFixed(0)}m',
                      style: const TextStyle(color: _neuTextDark, fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.pin_drop_rounded, color: _neuTextMuted, size: 14),
                    const SizedBox(width: 3),
                    Text(
                      '$pointsCount បង្គោល',
                      style: const TextStyle(color: _neuTextDark, fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const Spacer(),

                // Coordinates Sheet Button
                GestureDetector(
                  onTap: () => _showCoordinatesSheet(item),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: _neuBg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white, width: 1.2),
                      boxShadow: neuExtrudedShadows(distance: 2, blur: 4),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.format_list_numbered_rounded, color: _neuCobalt, size: 13),
                        SizedBox(width: 4),
                        Text(
                          'កូអរដោនេ',
                          style: TextStyle(color: _neuCobalt, fontSize: 11, fontWeight: FontWeight.w900),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),

                // Share Button
                GestureDetector(
                  onTap: () => _showShareSummaryDialog(item),
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: _neuBg,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 1.2),
                      boxShadow: neuExtrudedShadows(distance: 2, blur: 4),
                    ),
                    child: const Icon(Icons.share_rounded, color: _neuCobalt, size: 15),
                  ),
                ),
                const SizedBox(width: 8),

                // Open Map Button
                GestureDetector(
                  onTap: () {
                    if (widget.onSelectMeasurement != null) {
                      widget.onSelectMeasurement!(item);
                    } else {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const MapMeasurementScreen(),
                        ),
                      );
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [_neuCobalt, _neuCobaltDark]),
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: _neuCobalt.withOpacity(0.4),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.map_rounded, color: Colors.white, size: 13),
                        SizedBox(width: 5),
                        Text(
                          'បើកលើផែនទី',
                          style: TextStyle(
                            color: Colors.white,
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
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // 6. RICH EMPTY STATE
  // ─────────────────────────────────────────────────────────────
  Widget _buildRichEmptyState(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.only(
          left: 30,
          right: 30,
          top: 10,
          bottom: widget.isEmbedded ? 140 : 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 90,
              height: 90,
              decoration: BoxDecoration(
                color: _neuBg,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2.2),
                boxShadow: neuExtrudedShadows(distance: 5, blur: 14),
              ),
              child: const Center(
                child: Icon(
                  Icons.bookmark_add_rounded,
                  color: _neuCobalt,
                  size: 42,
                ),
              ),
            ),
            const SizedBox(height: 20),

            const Text(
              'មិនទាន់មានទិន្នន័យប្លង់ដីនៅឡើយទេ',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _neuTextDark,
                fontSize: 17,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'រាល់ពេលលោកអ្នកវាស់ដីលើផែនទីចប់ សូមចុច "រក្សាទុកប្លង់ដី" ដើម្បីរក្សាទុកក្បាលដី និងទំហំផ្ទៃដីនៅទីនេះ។ ឬចុចខាងក្រោមដើម្បីបញ្ចូលប្លង់ដីគំរូសាកល្បង។',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _neuTextMuted,
                fontSize: 12.5,
                height: 1.45,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 22),

            // Add Sample Button
            GestureDetector(
              onTap: _addSampleParcels,
              child: Container(
                width: double.infinity,
                height: 48,
                decoration: BoxDecoration(
                  color: _neuBg,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: Colors.white, width: 1.5),
                  boxShadow: neuExtrudedShadows(distance: 3, blur: 8),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.playlist_add_rounded, color: _neuCobalt, size: 20),
                    SizedBox(width: 8),
                    Text(
                      'បញ្ចូលប្លង់ដីគំរូសាកល្បង (Add Demo Parcels)',
                      style: TextStyle(
                        color: _neuCobalt,
                        fontSize: 13.5,
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
    );
  }
}
