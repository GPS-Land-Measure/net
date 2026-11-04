import 'package:flutter/material.dart';

class MeasurementBottomSheet extends StatefulWidget {
  final double areaM2;
  final double perimeterM;
  final int pointsCount;
  final bool canSave;
  final VoidCallback onSave;
  final VoidCallback onClear;
  final double bottomPadding;
  final bool isDistanceMode;
  final List<double>? segmentLengths;
  
  // Multi-Parcel Support
  final List<String>? parcelNames;
  final int activeParcelIndex;
  final ValueChanged<int>? onSelectParcel;
  final VoidCallback? onAddNewParcel;
  final double totalCombinedAreaM2;

  const MeasurementBottomSheet({
    super.key,
    required this.areaM2,
    required this.perimeterM,
    this.pointsCount = 0,
    required this.canSave,
    required this.onSave,
    required this.onClear,
    this.bottomPadding = 24,
    this.isDistanceMode = false,
    this.segmentLengths,
    this.parcelNames,
    this.activeParcelIndex = 0,
    this.onSelectParcel,
    this.onAddNewParcel,
    this.totalCombinedAreaM2 = 0,
  });

  @override
  State<MeasurementBottomSheet> createState() => _MeasurementBottomSheetState();
}

class _MeasurementBottomSheetState extends State<MeasurementBottomSheet> {
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

  bool _isExpanded = false;
  String _selectedUnit = 'ម៉ែត្រការ៉េ (m²)';
  double _pricePerM2 = 80.0;
  final List<String> _units = [
    'ម៉ែត្រការ៉េ (m²)',
    'អា (Are)',
    'ហិកតា (Ha)',
    'ហ្វីតការ៉េ (ft²)',
    'Acres',
  ];

  @override
  Widget build(BuildContext context) {
    final are = widget.areaM2 / 100;
    final ha = widget.areaM2 / 10000;
    final estPrice = (widget.areaM2 * _pricePerM2).round();

    return AnimatedContainer(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: _neuBg,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white, width: 1.6),
        boxShadow: [
          BoxShadow(
            color: _neuDarkShadow.withOpacity(0.6),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
          const BoxShadow(
            color: _neuLightShadow,
            blurRadius: 10,
            offset: Offset(-2, -2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Multi-Parcel Selector Pills (If multiple parcels exist) ──
          if (widget.parcelNames != null && widget.parcelNames!.length > 1)
            Container(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 2),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    ...widget.parcelNames!.asMap().entries.map((entry) {
                      final idx = entry.key;
                      final name = entry.value;
                      final isSel = idx == widget.activeParcelIndex;
                      return Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: GestureDetector(
                          onTap: () => widget.onSelectParcel?.call(idx),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              gradient: isSel
                                  ? const LinearGradient(colors: [_neuCobalt, _neuCobaltDark])
                                  : null,
                              color: isSel ? null : _neuInputBg,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isSel ? Colors.white : Colors.white.withOpacity(0.6),
                                width: 1,
                              ),
                            ),
                            child: Text(
                              name,
                              style: TextStyle(
                                color: isSel ? Colors.white : _neuTextDark,
                                fontSize: 11,
                                fontWeight: isSel ? FontWeight.w900 : FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                    if (widget.onAddNewParcel != null)
                      GestureDetector(
                        onTap: widget.onAddNewParcel,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: _neuBg,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: _neuCobalt, width: 1),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.add_rounded, color: _neuCobalt, size: 14),
                              SizedBox(width: 2),
                              Text(
                                '+ ប្លង់ថ្មី',
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
              ),
            ),

          // ── Drag & Expand Toggle Handle ──
          GestureDetector(
            onTap: () => setState(() => _isExpanded = !_isExpanded),
            behavior: HitTestBehavior.opaque,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 6),
              width: double.infinity,
              child: Center(
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: _neuDarkShadow.withOpacity(0.7),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── COMPACT HUD ROW (Always Visible) ──
                _buildCompactHudRow(are, ha, estPrice),

                // ── EXPANDED DETAILS (When _isExpanded is true) ──
                if (_isExpanded) ...[
                  const SizedBox(height: 12),
                  _buildExpandedDetails(are, ha, estPrice),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // 1. COMPACT HUD ROW (Clean, modern, high contrast)
  // ─────────────────────────────────────────────────────────────
  Widget _buildCompactHudRow(double are, double ha, int estPrice) {
    final isDistance = widget.isDistanceMode;
    final primaryValue = isDistance
        ? '${widget.perimeterM.toStringAsFixed(1)} m'
        : _formatArea(widget.areaM2, _selectedUnit);
    final secondaryText = isDistance
        ? 'ចម្ងាយសរុប • ${widget.pointsCount} ចំណុច'
        : '= ${are.toStringAsFixed(2)} អា  •  ${ha.toStringAsFixed(3)} Ha';

    return Row(
      children: [
        // Emblem Icon
        GestureDetector(
          onTap: () => setState(() => _isExpanded = !_isExpanded),
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: _neuBg,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 1.5),
              boxShadow: neuExtrudedShadows(distance: 2.5, blur: 6),
            ),
            child: Icon(
              isDistance ? Icons.straighten_rounded : Icons.landscape_rounded,
              color: _neuCobalt,
              size: 20,
            ),
          ),
        ),
        const SizedBox(width: 10),

        // Value & Subtitle
        Expanded(
          child: GestureDetector(
            onTap: () => setState(() => _isExpanded = !_isExpanded),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Text(
                      primaryValue,
                      style: const TextStyle(
                        color: _neuTextDark,
                        fontSize: 18.5,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.4,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: _neuInputBg,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${widget.pointsCount} បង្គោល',
                        style: const TextStyle(
                          color: _neuCobalt,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                Text(
                  secondaryText,
                  style: const TextStyle(
                    color: _neuTextMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),

        // Quick Clear Button
        GestureDetector(
          onTap: widget.onClear,
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: _neuBg,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 1.2),
              boxShadow: neuExtrudedShadows(distance: 2, blur: 5),
            ),
            child: const Icon(
              Icons.delete_outline_rounded,
              color: Color(0xFFEF4444),
              size: 18,
            ),
          ),
        ),
        const SizedBox(width: 8),

        // Quick Save Button
        GestureDetector(
          onTap: widget.canSave ? widget.onSave : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
            decoration: BoxDecoration(
              gradient: widget.canSave
                  ? const LinearGradient(colors: [_neuCobalt, _neuCobaltDark])
                  : null,
              color: widget.canSave ? null : _neuInputBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: widget.canSave ? Colors.white : Colors.white.withOpacity(0.5),
                width: 1.2,
              ),
              boxShadow: widget.canSave
                  ? [
                      BoxShadow(
                        color: _neuCobalt.withOpacity(0.4),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ]
                  : [],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.bookmark_added_rounded,
                  color: widget.canSave ? _neuYellow : _neuTextMuted,
                  size: 15,
                ),
                const SizedBox(width: 4),
                Text(
                  'រក្សាទុក',
                  style: TextStyle(
                    color: widget.canSave ? Colors.white : _neuTextMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 6),

        // Expand / Collapse Chevron Button
        GestureDetector(
          onTap: () => setState(() => _isExpanded = !_isExpanded),
          child: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: _neuInputBg,
              shape: BoxShape.circle,
            ),
            child: Icon(
              _isExpanded ? Icons.keyboard_arrow_down_rounded : Icons.keyboard_arrow_up_rounded,
              color: _neuCobalt,
              size: 20,
            ),
          ),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────
  // 2. EXPANDED DETAILS (Comprehensive Surveyor Metrics)
  // ─────────────────────────────────────────────────────────────
  Widget _buildExpandedDetails(double are, double ha, int estPrice) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Header & Unit Dropdown Bar ──
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'ព័ត៌មានលម្អិតក្បាលដី',
              style: TextStyle(
                color: _neuTextDark,
                fontSize: 13.5,
                fontWeight: FontWeight.w900,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: _neuBg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white, width: 1.2),
                boxShadow: neuExtrudedShadows(distance: 2, blur: 5),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedUnit,
                  isDense: true,
                  dropdownColor: _neuBg,
                  style: const TextStyle(
                    color: _neuCobalt,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w900,
                  ),
                  icon: const Icon(
                    Icons.arrow_drop_down_rounded,
                    color: _neuCobalt,
                    size: 18,
                  ),
                  items: _units
                      .map((u) => DropdownMenuItem(value: u, child: Text(u)))
                      .toList(),
                  onChanged: (val) {
                    if (val != null) setState(() => _selectedUnit = val);
                  },
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // ── 3-Metric Stats Row ──
        Row(
          children: [
            // Perimeter
            Expanded(
              child: _buildMetricTile(
                icon: Icons.straighten_rounded,
                iconColor: _neuCobalt,
                title: 'បរិមាត្រជុំវិញ',
                value: '${widget.perimeterM.toStringAsFixed(1)} m',
              ),
            ),
            const SizedBox(width: 8),

            // Corners / Points
            Expanded(
              child: _buildMetricTile(
                icon: Icons.pin_drop_rounded,
                iconColor: _neuYellow,
                title: 'ចំនួនបង្គោលដី',
                value: '${widget.pointsCount} ចំណុច',
              ),
            ),
            const SizedBox(width: 8),

            // Price Estimation
            Expanded(
              child: _buildMetricTile(
                icon: Icons.square_foot_rounded,
                iconColor: const Color(0xFF10B981),
                title: 'ទំហំគិតជា អា',
                value: '${are.toStringAsFixed(2)} អា',
              ),
            ),
          ],
        ),

        // ── Combined Area (If multiple parcels) ──
        if (widget.totalCombinedAreaM2 > 0) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: const Color(0xFF10B981).withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF10B981).withOpacity(0.3), width: 1),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'ផ្ទៃក្រឡាសរុបគ្រប់ប្លង់ (Total):',
                  style: TextStyle(
                    color: Color(0xFF065F46),
                    fontWeight: FontWeight.bold,
                    fontSize: 11.5,
                  ),
                ),
                Text(
                  '${widget.totalCombinedAreaM2.toStringAsFixed(1)} m² (= ${(widget.totalCombinedAreaM2 / 100).toStringAsFixed(2)} អា)',
                  style: const TextStyle(
                    color: Color(0xFF065F46),
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],

        // ── Segment Side Lengths (If Available) ──
        if (widget.segmentLengths != null && widget.segmentLengths!.isNotEmpty) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: _neuInputBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withOpacity(0.7), width: 1),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.timeline_rounded, color: _neuCobalt, size: 14),
                    SizedBox(width: 6),
                    Text(
                      'ប្រវែងតាមជ្រុងនីមួយៗ (Side Lengths):',
                      style: TextStyle(
                        color: _neuTextDark,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: widget.segmentLengths!.asMap().entries.map((entry) {
                    final idx = entry.key;
                    final nextIdx = (idx + 1) % (widget.pointsCount == 0 ? 1 : widget.pointsCount);
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: _neuBg,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.white, width: 1),
                      ),
                      child: Text(
                        'ជ្រុង ${idx + 1}-${nextIdx + 1}: ${entry.value.toStringAsFixed(1)}m',
                        style: const TextStyle(
                          color: _neuCobaltDark,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        ],

        // ── Price Presets Row ──
        const SizedBox(height: 10),
        Row(
          children: [
            const Text(
              'តម្លៃក្នុង 1 m²:',
              style: TextStyle(color: _neuTextMuted, fontSize: 11, fontWeight: FontWeight.bold),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [30.0, 50.0, 80.0, 120.0, 200.0, 350.0].map((p) {
                    final isSel = _pricePerM2 == p;
                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: GestureDetector(
                        onTap: () => setState(() => _pricePerM2 = p),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                          decoration: BoxDecoration(
                            gradient: isSel
                                ? const LinearGradient(colors: [_neuCobalt, _neuCobaltDark])
                                : null,
                            color: isSel ? null : _neuBg,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isSel ? Colors.white : Colors.white.withOpacity(0.9),
                              width: 1,
                            ),
                          ),
                          child: Text(
                            '\$${p.toInt()}',
                            style: TextStyle(
                              color: isSel ? Colors.white : _neuTextDark,
                              fontSize: 10.5,
                              fontWeight: isSel ? FontWeight.w900 : FontWeight.bold,
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
      ],
    );
  }

  Widget _buildMetricTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      decoration: BoxDecoration(
        color: _neuInputBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.7), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: iconColor, size: 13),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  title,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: _neuTextMuted, fontSize: 9, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            value,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: _neuTextDark, fontSize: 12.5, fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }

  String _formatArea(double m2, String unit) {
    if (unit.contains('អា')) {
      return '${(m2 / 100).toStringAsFixed(2)} អា';
    } else if (unit.contains('ហិកតា')) {
      return '${(m2 / 10000).toStringAsFixed(4)} Ha';
    } else if (unit.contains('ft²')) {
      return '${(m2 * 10.7639).toStringAsFixed(1)} ft²';
    } else if (unit.contains('Acres')) {
      return '${(m2 / 4046.86).toStringAsFixed(4)} ac';
    } else {
      return '${m2.toStringAsFixed(1)} m²';
    }
  }
}
