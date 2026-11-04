import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/measurement.dart';
import 'login_screen.dart';

class SettingsScreen extends StatefulWidget {
  final bool isEmbedded;
  final VoidCallback? onBackToHome;

  const SettingsScreen({
    super.key,
    this.isEmbedded = false,
    this.onBackToHome,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
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

  // User Profile
  String _userName = 'Ny PhaNetz';
  String _userEmail = 'nyphanettz@gmail.com';
  String _userPhone = '+855 12 889 977';
  String _userRole = 'វិស្វករវាស់វែងដីធ្លីអាជីព (Pro Surveyor)';
  String _userLicenseId = 'CAM-SURV-2026';
  int _avatarColorIndex = 0;
  String _userAvatarEmoji = '📐';

  static const List<List<Color>> _avatarColors = [
    [_neuCobalt, _neuCobaltDark],
    [Color(0xFF059669), Color(0xFF047857)],
    [Color(0xFFD97706), Color(0xFFB45309)],
    [Color(0xFF7C3AED), Color(0xFF6D28D9)],
    [Color(0xFFE11D48), Color(0xFFBE123C)],
  ];

  // Measurement Settings
  String _selectedUnit = 'ម៉ែត្រការ៉េ (m²)';
  String _selectedMapType = 'ផ្កាយរណប (Satellite)';
  String _selectedLanguage = 'ភាសាខ្មែរ (Khmer)';
  String _selectedNumeralFormat = 'លេខខ្មែរ (០, ១, ២...)';
  bool _highAccuracyGps = true;
  bool _multiGnssSupport = true; // GPS + GLONASS + BeiDou
  bool _showElevationTags = true;

  // Preferences
  bool _hapticFeedback = true;
  bool _audioBeep = true;
  bool _autoSave = true;
  String _boundaryColorName = 'ខៀវរាជ (Cobalt Blue)';
  String _labelFontSize = 'ស្តង់ដារ (Medium)';

  // Live Surveyor Stats
  int _totalParcelsCount = 0;
  double _totalAreaM2 = 0.0;
  int _totalPointsCount = 0;
  bool _isSyncing = false;
  String _cacheSizeText = '12.4 MB';
  String _lastSyncStatus = 'ការពារទិន្នន័យប្លង់ដីកុំឱ្យបាត់បង់';

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _loadSurveyStats();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _userName = prefs.getString('user_name') ?? 'Ny PhaNetz';
      _userEmail = prefs.getString('user_email') ?? 'nyphanettz@gmail.com';
      _userPhone = prefs.getString('user_phone') ?? '+855 12 889 977';
      _userRole = prefs.getString('user_role') ?? 'វិស្វករវាស់វែងដីធ្លីអាជីព (Pro Surveyor)';
      _userLicenseId = prefs.getString('user_license') ?? 'CAM-SURV-2026';
      _avatarColorIndex = prefs.getInt('user_avatar_color') ?? 0;
      if (_avatarColorIndex < 0 || _avatarColorIndex >= _avatarColors.length) {
        _avatarColorIndex = 0;
      }
      _userAvatarEmoji = prefs.getString('user_avatar_emoji') ?? '📐';

      _selectedUnit = prefs.getString('pref_unit') ?? 'ម៉ែត្រការ៉េ (m²)';
      _selectedMapType = prefs.getString('pref_map') ?? 'ផ្កាយរណប (Satellite)';
      _selectedLanguage = prefs.getString('pref_lang') ?? 'ភាសាខ្មែរ (Khmer)';
      _selectedNumeralFormat = (prefs.getString('pref_khmer_numerals') ?? 'true') == 'true' ? 'លេខខ្មែរ (០, ១, ២...)' : 'លេខអន្តរជាតិ (0, 1, 2...)';
      _highAccuracyGps = prefs.getBool('pref_gps') ?? true;
      _multiGnssSupport = prefs.getBool('pref_gnss') ?? true;
      _showElevationTags = prefs.getBool('pref_elevation') ?? true;
      _hapticFeedback = prefs.getBool('pref_haptic') ?? true;
      _audioBeep = prefs.getBool('pref_beep') ?? true;
      _autoSave = prefs.getBool('pref_autosave') ?? true;
      _boundaryColorName = prefs.getString('pref_color') ?? 'ខៀវរាជ (Cobalt Blue)';
      _labelFontSize = prefs.getString('pref_font') ?? 'ស្តង់ដារ (Medium)';
      _lastSyncStatus = prefs.getString('pref_last_sync_time') ?? 'ការពារទិន្នន័យប្លង់ដីកុំឱ្យបាត់បង់';
    });
  }

  Future<void> _loadSurveyStats() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList('measurements') ?? [];
      int points = 0;
      double area = 0.0;
      for (final s in list) {
        final m = Measurement.fromJsonString(s);
        area += m.areaM2;
        points += m.points?.length ?? (m.type == MeasurementType.circle ? 1 : 0);
      }
      setState(() {
        _totalParcelsCount = list.length;
        _totalAreaM2 = area;
        _totalPointsCount = points;
      });
    } catch (_) {}
  }

  Future<void> _saveSetting(String key, dynamic value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value is bool) {
      await prefs.setBool(key, value);
    } else if (value is String) {
      await prefs.setString(key, value);
    }
  }

  void _openFullProfileEditorDialog() {
    final nameCtrl = TextEditingController(text: _userName);
    final emailCtrl = TextEditingController(text: _userEmail);
    final phoneCtrl = TextEditingController(text: _userPhone);
    final licenseCtrl = TextEditingController(text: _userLicenseId);
    int selectedColor = _avatarColorIndex;
    String selectedEmoji = _userAvatarEmoji;
    String selectedRole = _userRole;

    final roles = [
      'វិស្វករវាស់វែងដីធ្លីអាជីព (Pro Surveyor)',
      'ម្ចាស់ដី / ក្រុមហ៊ុនអភិវឌ្ឍន៍ (Property Owner)',
      'មន្ត្រីសុរិយោដី & រដ្ឋបាល (Cadastral Officer)',
      'ភ្នាក់ងារអចលនទ្រព្យ (Real Estate Agent)',
    ];

    final emojis = ['📐', '🏢', '🗺️', '🛰️', '⚡', '👑', 'N'];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (modalCtx, setModalState) {
          final currentColor = _avatarColors[selectedColor];

          return Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(modalCtx).size.height * 0.88,
            ),
            decoration: const BoxDecoration(
              color: _neuBg,
              borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
            ),
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 14,
              bottom: MediaQuery.of(modalCtx).viewInsets.bottom + 24,
            ),
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Pull Handle
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

                  // Header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.manage_accounts_rounded, color: _neuCobalt, size: 24),
                          SizedBox(width: 10),
                          Text(
                            'កែប្រែព័ត៌មានគណនី',
                            style: TextStyle(
                              color: _neuTextDark,
                              fontWeight: FontWeight.w900,
                              fontSize: 18,
                            ),
                          ),
                        ],
                      ),
                      GestureDetector(
                        onTap: () => Navigator.pop(ctx),
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: _neuBg,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 1.2),
                            boxShadow: neuExtrudedShadows(distance: 2, blur: 4),
                          ),
                          child: const Icon(Icons.close_rounded, color: _neuTextMuted, size: 18),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),

                  // Interactive Live Avatar Preview & Customizer
                  Center(
                    child: Column(
                      children: [
                        Container(
                          width: 76,
                          height: 76,
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: _neuBg,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                            boxShadow: neuExtrudedShadows(distance: 4, blur: 10),
                          ),
                          child: Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: LinearGradient(colors: currentColor),
                            ),
                            child: Center(
                              child: Text(
                                selectedEmoji == 'N'
                                    ? (nameCtrl.text.trim().isNotEmpty
                                        ? nameCtrl.text.trim()[0].toUpperCase()
                                        : 'N')
                                    : selectedEmoji,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: selectedEmoji == 'N' ? 28 : 30,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Color theme swatches
                        const Text(
                          'ពណ៌រូបតំណាង (Avatar Color Theme):',
                          style: TextStyle(color: _neuTextMuted, fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: List.generate(_avatarColors.length, (idx) {
                            final isSel = selectedColor == idx;
                            return GestureDetector(
                              onTap: () => setModalState(() => selectedColor = idx),
                              child: Container(
                                margin: const EdgeInsets.symmetric(horizontal: 6),
                                width: 34,
                                height: 34,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: LinearGradient(colors: _avatarColors[idx]),
                                  border: Border.all(
                                    color: isSel ? Colors.white : Colors.transparent,
                                    width: 2.2,
                                  ),
                                  boxShadow: isSel
                                      ? [
                                          BoxShadow(
                                            color: _avatarColors[idx][0].withOpacity(0.5),
                                            blurRadius: 8,
                                            offset: const Offset(0, 2),
                                          ),
                                        ]
                                      : null,
                                ),
                                child: isSel
                                    ? const Icon(Icons.check, color: Colors.white, size: 16)
                                    : null,
                              ),
                            );
                          }),
                        ),
                        const SizedBox(height: 12),

                        // Badge / Emoji selection
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          physics: const BouncingScrollPhysics(),
                          child: Row(
                            children: emojis.map((e) {
                              final isSel = selectedEmoji == e;
                              final display = e == 'N'
                                  ? (nameCtrl.text.isNotEmpty ? nameCtrl.text[0].toUpperCase() : 'N')
                                  : e;
                              return GestureDetector(
                                onTap: () => setModalState(() => selectedEmoji = e),
                                child: Container(
                                  margin: const EdgeInsets.symmetric(horizontal: 4),
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: isSel ? _neuCobalt : _neuBg,
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(color: Colors.white, width: 1.2),
                                    boxShadow: isSel
                                        ? [
                                            BoxShadow(
                                              color: _neuCobalt.withOpacity(0.4),
                                              blurRadius: 6,
                                              offset: const Offset(0, 2),
                                            ),
                                          ]
                                        : neuExtrudedShadows(distance: 2, blur: 4),
                                  ),
                                  child: Text(
                                    display,
                                    style: TextStyle(
                                      color: isSel ? Colors.white : _neuTextDark,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),

                  // Name Field
                  _buildProfileInputField(
                    label: 'ឈ្មោះអ្នកវាស់វែង (Full Name)',
                    controller: nameCtrl,
                    icon: Icons.person_rounded,
                    onChanged: (_) => setModalState(() {}),
                  ),
                  const SizedBox(height: 12),

                  // Email Field
                  _buildProfileInputField(
                    label: 'អាសយដ្ឋានអ៊ីមែល (Email Address)',
                    controller: emailCtrl,
                    icon: Icons.email_rounded,
                    keyboardType: TextInputType.emailAddress,
                  ),
                  const SizedBox(height: 12),

                  // Phone Field
                  _buildProfileInputField(
                    label: 'លេខទូរស័ព្ទទំនាក់ទំនង (Phone Number)',
                    controller: phoneCtrl,
                    icon: Icons.phone_rounded,
                    keyboardType: TextInputType.phone,
                  ),
                  const SizedBox(height: 12),

                  // Role Selector
                  const Text(
                    'តួនាទី / មុខរបរ (Role & Title):',
                    style: TextStyle(
                      color: _neuTextDark,
                      fontWeight: FontWeight.bold,
                      fontSize: 12.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Column(
                    children: roles.map((r) {
                      final isSel = selectedRole == r;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: GestureDetector(
                          onTap: () => setModalState(() => selectedRole = r),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              gradient: isSel
                                  ? const LinearGradient(colors: [_neuCobalt, _neuCobaltDark])
                                  : null,
                              color: isSel ? null : _neuBg,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: isSel ? Colors.white : Colors.white.withOpacity(0.8),
                                width: 1.2,
                              ),
                              boxShadow: isSel
                                  ? [
                                      BoxShadow(
                                        color: _neuCobalt.withOpacity(0.4),
                                        blurRadius: 8,
                                        offset: const Offset(0, 2),
                                      ),
                                    ]
                                  : neuExtrudedShadows(distance: 2, blur: 4),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  isSel ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                                  color: isSel ? Colors.white : _neuTextMuted,
                                  size: 16,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    r,
                                    style: TextStyle(
                                      color: isSel ? Colors.white : _neuTextDark,
                                      fontSize: 12,
                                      fontWeight: isSel ? FontWeight.w900 : FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 12),

                  // License ID Field
                  _buildProfileInputField(
                    label: 'លេខកូដអាជ្ញាប័ណ្ណ / ID វាស់ដី (Cadastre License ID)',
                    controller: licenseCtrl,
                    icon: Icons.badge_rounded,
                  ),
                  const SizedBox(height: 22),

                  // Save & Cancel Buttons
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
                              boxShadow: neuExtrudedShadows(distance: 2, blur: 5),
                            ),
                            child: const Center(
                              child: Text(
                                'បោះបង់',
                                style: TextStyle(
                                  color: _neuTextDark,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13.5,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: GestureDetector(
                          onTap: () async {
                            final newName = nameCtrl.text.trim();
                            if (newName.isEmpty) return;

                            final newEmail = emailCtrl.text.trim();
                            final newPhone = phoneCtrl.text.trim();
                            final newLicense = licenseCtrl.text.trim();

                            final prefs = await SharedPreferences.getInstance();
                            await prefs.setString('user_name', newName);
                            await prefs.setString('user_email', newEmail.isNotEmpty ? newEmail : _userEmail);
                            await prefs.setString('user_phone', newPhone.isNotEmpty ? newPhone : _userPhone);
                            await prefs.setString('user_role', selectedRole);
                            await prefs.setString('user_license', newLicense.isNotEmpty ? newLicense : _userLicenseId);
                            await prefs.setInt('user_avatar_color', selectedColor);
                            await prefs.setString('user_avatar_emoji', selectedEmoji);

                            setState(() {
                              _userName = newName;
                              if (newEmail.isNotEmpty) _userEmail = newEmail;
                              if (newPhone.isNotEmpty) _userPhone = newPhone;
                              _userRole = selectedRole;
                              if (newLicense.isNotEmpty) _userLicenseId = newLicense;
                              _avatarColorIndex = selectedColor;
                              _userAvatarEmoji = selectedEmoji;
                            });

                            if (ctx.mounted) Navigator.pop(ctx);
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(colors: [_neuCobalt, _neuCobaltDark]),
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: _neuCobalt.withOpacity(0.4),
                                  blurRadius: 10,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: const Center(
                              child: Text(
                                'រក្សាទុកការកែប្រែ',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 13.5,
                                ),
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
        },
      ),
    );
  }

  Widget _buildProfileInputField({
    required String label,
    required TextEditingController controller,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    Function(String)? onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: _neuTextDark,
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: _neuInputBg,
            borderRadius: BorderRadius.circular(16),
            boxShadow: neuRecessedShadows(),
            border: Border.all(color: Colors.white.withOpacity(0.7), width: 1),
          ),
          child: Row(
            children: [
              Icon(icon, color: _neuCobalt, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: controller,
                  keyboardType: keyboardType,
                  onChanged: onChanged,
                  style: const TextStyle(
                    color: _neuTextDark,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    isDense: true,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _syncCloudBackup() async {
    setState(() => _isSyncing = true);
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList('measurements') ?? [];
    await prefs.setStringList('cloud_backup_measurements', list);
    
    final now = DateTime.now();
    final timeStr = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    final syncLabel = 'បានបម្រុងទុកម៉ោង $timeStr (${list.length} ប្លង់ដី)';
    await prefs.setString('pref_last_sync_time', syncLabel);

    await Future.delayed(const Duration(milliseconds: 900));
    if (mounted) {
      setState(() {
        _isSyncing = false;
        _lastSyncStatus = syncLabel;
      });
    }
  }

  void _clearMapCache() {
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    setState(() {
      _cacheSizeText = '0.0 KB (បានសម្អាត)';
    });
  }

  Future<void> _openTelegramCommunity() async {
    final uri = Uri.parse('https://t.me/net131125');
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        await launchUrl(uri);
      }
    } catch (_) {}
  }

  void _showSurveyGuideModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withOpacity(0.35),
      isScrollControlled: true,
      builder: (ctx) => Container(
        height: MediaQuery.of(context).size.height * 0.85,
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
        decoration: BoxDecoration(
          color: _neuBg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          border: Border.all(color: Colors.white, width: 1.5),
          boxShadow: neuExtrudedShadows(distance: 8, blur: 24),
        ),
        child: Column(
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
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.menu_book_rounded, color: _neuCobalt, size: 24),
                    SizedBox(width: 10),
                    Text(
                      'សៀវភៅណែនាំវាស់ដីធ្លី',
                      style: TextStyle(
                        color: _neuTextDark,
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                      ),
                    ),
                  ],
                ),
                GestureDetector(
                  onTap: () => Navigator.pop(ctx),
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: _neuBg,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 1.2),
                      boxShadow: neuExtrudedShadows(distance: 2, blur: 4),
                    ),
                    child: const Icon(Icons.close_rounded, color: _neuTextMuted, size: 18),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView(
                physics: const BouncingScrollPhysics(),
                children: [
                  _buildGuideChapter(
                    number: '១',
                    title: 'របៀបវាស់ដីតាមពហុកោណ (Polygon Measurement)',
                    description: '• ប៉ះលើអេក្រង់ផែនទីដើម្បីដៅបង្គោលជុំវិញព្រំដី\n• ឬចុចប៊ូតុង "+ ដាក់បង្គោលដី" ចំកណ្តាលផ្ទាំង\n• ប្រព័ន្ធនឹងគណនាផ្ទៃក្រឡា m², អា, ហិកតា និងប្រវែងជ្រុងនីមួយៗភ្លាមៗ។',
                    icon: Icons.polyline_rounded,
                    color: _neuCobalt,
                  ),
                  const SizedBox(height: 12),
                  _buildGuideChapter(
                    number: '២',
                    title: 'របៀបដើរវាស់ដីតាម GPS ផ្ទាល់ដៃ (GPS Walk)',
                    description: '• ចុចលើម៉ឺនុយឧបករណ៍ខាងលើស្តាំ ហើយជ្រើសរើស "ដើរវាស់ដី (GPS Walk)"\n• កាន់ទូរស័ព្ទដើរតាមព្រំដីជាក់ស្ដែង វានឹងទម្លាក់បង្គោលស្វ័យប្រវត្តរៀងរាល់ជំហាន (១ម, ២ម, ៣ម, ៥ម)\n• ពេលមកដល់ចំណុចដើមវិញ ចុចប៊ូតុង "បិទព្រំដី" ដើម្បីទទួលបានទំហំដីសរុប។',
                    icon: Icons.directions_walk_rounded,
                    color: const Color(0xFFE11D48),
                  ),
                  const SizedBox(height: 12),
                  _buildGuideChapter(
                    number: '៣',
                    title: 'របៀបពុះដីឡូតិ៍ចែកស្មើគ្នា (Auto Parcel Splitter)',
                    description: '• គូសវាស់ពហុកោណដីចប់សព្វគ្រប់ (៣ បង្គោលឡើងទៅ)\n• ចុចលើប្រអប់ឧបករណ៍ រួចជ្រើសរើស "ពុះឡូតិ៍ចែកស្មើគ្នា"\n• កំណត់ចំនួនចំណែក (ឧ. ២ ឬ ៣ ឡូតិ៍) វានឹងពុះចែកជាឡូតិ៍ស្មើៗគ្នាដោយស្វ័យប្រវត្តិ។',
                    icon: Icons.call_split_rounded,
                    color: const Color(0xFF10B981),
                  ),
                  const SizedBox(height: 12),
                  _buildGuideChapter(
                    number: '៤',
                    title: 'របៀបគណនាតម្លៃដី និងបំប្លែងខ្នាតដីខ្មែរ',
                    description: '• ចូលទៅកាន់ផ្ទាំង "គណនាតម្លៃដី"\n• វាយបញ្ចូលតម្លៃក្នុង ១ ម៉ែត្រការ៉េ ឬក្នុង ១ ហិកតា\n• ប្រព័ន្ធនឹងគណនាតម្លៃសរុបជា USD (\$) និងប្រាក់រៀល (៛) ព្រមទាំងបំប្លែងខ្នាត អា, ហិកតា, ប្លង់, គីឡូ។',
                    icon: Icons.calculate_rounded,
                    color: _neuYellow,
                  ),
                  const SizedBox(height: 12),
                  _buildGuideChapter(
                    number: '៥',
                    title: 'របៀប Export ទិន្នន័យ & វិញ្ញាបនបត្រប្លង់ដី',
                    description: '• ចុចលើប្រអប់ "នាំចេញ / Export"\n• អាចចម្លងទិន្នន័យជា KML សម្រាប់ Google Earth, DXF សម្រាប់ AutoCAD ឬ GeoJSON សម្រាប់ ArcGIS\n• អាចចម្លងវិញ្ញាបនបត្រប្លង់ដីផ្លូវការដែលមានកូអរដោនេ WGS84 និង UTM 48N។',
                    icon: Icons.file_download_rounded,
                    color: const Color(0xFF8B5CF6),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGuideChapter({
    required String number,
    required String title,
    required String description,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _neuBg,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white, width: 1.5),
        boxShadow: neuExtrudedShadows(distance: 3, blur: 8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: _neuTextDark,
                    fontWeight: FontWeight.w900,
                    fontSize: 13.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            description,
            style: const TextStyle(
              color: _neuTextMuted,
              fontSize: 12,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  void _showClearCacheDialog() {
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.35),
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: _neuBg,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: Colors.white, width: 1.5),
            boxShadow: neuExtrudedShadows(distance: 6, blur: 20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: _neuBg,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 1.5),
                  boxShadow: neuExtrudedShadows(distance: 2.5, blur: 6),
                ),
                child: const Icon(Icons.cleaning_services_rounded, color: _neuCobalt, size: 24),
              ),
              const SizedBox(height: 12),
              const Text(
                'សម្អាតទិន្នន័យបណ្តោះអាសន្ន',
                style: TextStyle(color: _neuTextDark, fontWeight: FontWeight.w900, fontSize: 16.5),
              ),
              const SizedBox(height: 6),
              const Text(
                'តើអ្នកចង់សម្អាត Cache ផែនទី និងទិន្នន័យបណ្តោះអាសន្ន ដើម្បីឱ្យកម្មវិធីដើរលឿនជាងមុនមែនទេ?',
                textAlign: TextAlign.center,
                style: TextStyle(color: _neuTextMuted, fontSize: 12.5, height: 1.4),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => Navigator.pop(ctx),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 11),
                        decoration: BoxDecoration(
                          color: _neuBg,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.white, width: 1),
                          boxShadow: neuExtrudedShadows(distance: 2, blur: 5),
                        ),
                        child: const Center(
                          child: Text('បោះបង់', style: TextStyle(color: _neuTextDark, fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        Navigator.pop(ctx);
                        _clearMapCache();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 11),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(colors: [_neuCobalt, _neuCobaltDark]),
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(color: _neuCobalt.withOpacity(0.4), blurRadius: 10, offset: const Offset(0, 3)),
                          ],
                        ),
                        child: const Center(
                          child: Text('សម្អាតឥឡូវ', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
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
  }

  void _showLogoutDialog() {
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.35),
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: _neuBg,
            borderRadius: BorderRadius.circular(28),
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
                child: const Icon(Icons.logout_rounded, color: Color(0xFFEF4444), size: 28),
              ),
              const SizedBox(height: 16),
              const Text(
                'ចាកចេញពីគណនី',
                style: TextStyle(
                  color: _neuTextDark,
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'តើអ្នកពិតជាចង់ចាកចេញពីកម្មវិធីវាស់ដីមែនទេ?',
                textAlign: TextAlign.center,
                style: TextStyle(color: _neuTextMuted, fontSize: 13, height: 1.4),
              ),
              const SizedBox(height: 22),
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => Navigator.pop(ctx),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: _neuBg,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.white, width: 1.2),
                          boxShadow: neuExtrudedShadows(distance: 2.5, blur: 6),
                        ),
                        child: const Center(
                          child: Text(
                            'បោះបង់',
                            style: TextStyle(color: _neuTextDark, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GestureDetector(
                      onTap: () async {
                        try {
                          final prefs = await SharedPreferences.getInstance();
                          await prefs.setBool('is_logged_in', false);
                        } catch (_) {}
                        if (!ctx.mounted) return;
                        Navigator.pop(ctx);
                        if (!mounted) return;
                        Navigator.pushAndRemoveUntil(
                          context,
                          MaterialPageRoute(builder: (_) => const LoginScreen()),
                          (route) => false,
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFFEF4444), Color(0xFFDC2626)],
                          ),
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFEF4444).withOpacity(0.4),
                              blurRadius: 10,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: const Center(
                          child: Text(
                            'ចាកចេញ',
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
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _neuBg,
      body: SafeArea(
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            // ── 1. Top App Bar ──
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 10, 18, 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
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
                              border: Border.all(color: Colors.white, width: 1.5),
                              boxShadow: neuExtrudedShadows(distance: 2.5, blur: 6),
                            ),
                            child: const Icon(
                              Icons.arrow_back_ios_new_rounded,
                              color: _neuCobalt,
                              size: 17,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'ការកំណត់ (Settings)',
                              style: TextStyle(
                                color: _neuTextDark,
                                fontSize: 19,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.2,
                              ),
                            ),
                            Text(
                              'ប្រព័ន្ធគ្រប់គ្រង និងការវាស់ដី',
                              style: TextStyle(
                                color: _neuTextMuted,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: _neuBg,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white, width: 1.2),
                        boxShadow: neuExtrudedShadows(distance: 2, blur: 5),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.verified_rounded, color: _neuCobalt, size: 13),
                          SizedBox(width: 4),
                          Text(
                            'v2.5 Pro',
                            style: TextStyle(
                              color: _neuCobalt,
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ── 2. VIP Surveyor Profile Card ──
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                child: _buildProfileCard(),
              ),
            ),

            // ── 3. Real Surveyor Live Stats Grid (New Feature!) ──
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
                child: _buildSurveyorStatsGrid(),
              ),
            ),

            // ── 4. Group: Measurement & GPS Settings ──
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(22, 16, 22, 8),
                child: _buildSectionHeader('🛰️ ការវាស់ដី & GPS (Measurement & GNSS)'),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: _buildNeumorphicCard([
                  _buildDropdownTile(
                    icon: Icons.square_foot_rounded,
                    title: 'ឯកតាផ្ទៃដីចម្បង',
                    subtitle: 'ឯកតាបង្ហាញលទ្ធផលវាស់ដី',
                    value: _selectedUnit,
                    options: const [
                      'ម៉ែត្រការ៉េ (m²)',
                      'អា (Are)',
                      'ហិកតា (Ha)',
                      'ហ្វីតការ៉េ (ft²)',
                      'Acres',
                    ],
                    onChanged: (val) {
                      setState(() => _selectedUnit = val!);
                      _saveSetting('pref_unit', val);
                    },
                  ),
                  _buildDivider(),
                  _buildDropdownTile(
                    icon: Icons.layers_rounded,
                    title: 'ប្រភេទផែនទីវាស់ដី',
                    subtitle: 'ប្តូរប្រភេទ Map Tiles',
                    value: _selectedMapType,
                    options: const [
                      'ផ្កាយរណប (Satellite)',
                      'ផែនទីផ្លូវ (Street Map)',
                      'ទេសភាពដី (Topo / Terrain)',
                    ],
                    onChanged: (val) {
                      setState(() => _selectedMapType = val!);
                      _saveSetting('pref_map', val);
                    },
                  ),
                  _buildDivider(),
                  _buildSwitchTile(
                    icon: Icons.gps_fixed_rounded,
                    title: 'GPS High Precision (RTK)',
                    subtitle: 'បង្កើនភាពសុក្រឹតខ្ពស់បំផុត ±0.5m',
                    value: _highAccuracyGps,
                    onChanged: (val) {
                      setState(() => _highAccuracyGps = val);
                      _saveSetting('pref_gps', val);
                    },
                  ),
                  _buildDivider(),
                  _buildSwitchTile(
                    icon: Icons.satellite_alt_rounded,
                    title: 'ប្រព័ន្ធ Multi-GNSS ៤ ប្រព័ន្ធ',
                    subtitle: 'GPS + GLONASS + Galileo + BeiDou',
                    value: _multiGnssSupport,
                    onChanged: (val) {
                      setState(() => _multiGnssSupport = val);
                      _saveSetting('pref_gnss', val);
                    },
                  ),
                  _buildDivider(),
                  _buildSwitchTile(
                    icon: Icons.height_rounded,
                    title: 'បង្ហាញកម្ពស់ដី (Elevation Tags)',
                    subtitle: 'បង្ហាញកម្ពស់ពីនីវ៉ូសមុទ្រ (Altitude ▲)',
                    value: _showElevationTags,
                    onChanged: (val) {
                      setState(() => _showElevationTags = val);
                      _saveSetting('pref_elevation', val);
                    },
                  ),
                ]),
              ),
            ),

            // ── 5. Group: App Preferences & Experience ──
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(22, 18, 22, 8),
                child: _buildSectionHeader('⚙️ បទពិសោធន៍ប្រើប្រាស់ (Preferences)'),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: _buildNeumorphicCard([
                  _buildSwitchTile(
                    icon: Icons.vibration_rounded,
                    title: 'រំញ័រពេលចុចបង្គោលដី',
                    subtitle: 'Haptic feedback on map tap',
                    value: _hapticFeedback,
                    onChanged: (val) {
                      setState(() => _hapticFeedback = val);
                      _saveSetting('pref_haptic', val);
                    },
                  ),
                  _buildDivider(),
                  _buildSwitchTile(
                    icon: Icons.volume_up_rounded,
                    title: 'សំឡេង Beep ពេលដៅបង្គោល',
                    subtitle: 'Audible confirmation beep sound',
                    value: _audioBeep,
                    onChanged: (val) {
                      setState(() => _audioBeep = val);
                      _saveSetting('pref_beep', val);
                    },
                  ),
                  _buildDivider(),
                  _buildSwitchTile(
                    icon: Icons.cloud_done_rounded,
                    title: 'រក្សាទុកស្វ័យប្រវត្តិ (Auto-save)',
                    subtitle: 'រក្សាទុកទិន្នន័យប្លង់ដីដោយស្វ័យប្រវត្តិ',
                    value: _autoSave,
                    onChanged: (val) {
                      setState(() => _autoSave = val);
                      _saveSetting('pref_autosave', val);
                    },
                  ),
                  _buildDivider(),
                  _buildDropdownTile(
                    icon: Icons.palette_rounded,
                    title: 'ពណ៌បន្ទាត់ព្រំដីលើផែនទី',
                    subtitle: 'Boundary line color theme',
                    value: _boundaryColorName,
                    options: const [
                      'ខៀវរាជ (Cobalt Blue)',
                      'បៃតងត្បូង (Emerald Green)',
                      'ទឹកក្រូចមាស (Golden Amber)',
                      'ក្រហមផ្កាឈូក (Rose Red)',
                    ],
                    onChanged: (val) {
                      setState(() => _boundaryColorName = val!);
                      _saveSetting('pref_color', val);
                    },
                  ),
                  _buildDivider(),
                  _buildDropdownTile(
                    icon: Icons.format_size_rounded,
                    title: 'ទំហំអក្សរស្លាកលើផែនទី',
                    subtitle: 'Distance & pin label size',
                    value: _labelFontSize,
                    options: const [
                      'តូច (Compact)',
                      'ស្តង់ដារ (Medium)',
                      'ធំច្បាស់ (Large)',
                    ],
                    onChanged: (val) {
                      setState(() => _labelFontSize = val!);
                      _saveSetting('pref_font', val);
                    },
                  ),
                  _buildDivider(),
                  _buildDropdownTile(
                    icon: Icons.language_rounded,
                    title: 'ភាសាកម្មវិធី (Language)',
                    subtitle: 'ជ្រើសរើសភាសា',
                    value: _selectedLanguage,
                    options: const [
                      'ភាសាខ្មែរ (Khmer)',
                      'English',
                    ],
                    onChanged: (val) {
                      setState(() => _selectedLanguage = val!);
                      _saveSetting('pref_lang', val);
                    },
                  ),
                  _buildDivider(),
                  _buildDropdownTile(
                    icon: Icons.pin_invoke_rounded,
                    title: 'ទម្រង់លេខ (Numeral Format)',
                    subtitle: 'ជ្រើសរើសលេខខ្មែរ ឬលេខសកល',
                    value: _selectedNumeralFormat,
                    options: const [
                      'លេខខ្មែរ (០, ១, ២...)',
                      'លេខអន្តរជាតិ (0, 1, 2...)',
                    ],
                    onChanged: (val) {
                      setState(() => _selectedNumeralFormat = val!);
                      _saveSetting('pref_khmer_numerals', val == 'លេខខ្មែរ (០, ១, ២...)' ? 'true' : 'false');
                    },
                  ),
                ]),
              ),
            ),

            // ── 6. Group: Backup, Cloud Sync & Data Tools (New Feature!) ──
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(22, 18, 22, 8),
                child: _buildSectionHeader('☁️ ការបម្រុងទុក & ឧបករណ៍ទិន្នន័យ (Data & Sync)'),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: _buildNeumorphicCard([
                  // Cloud Sync Action Tile
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: _neuBg,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 1.2),
                            boxShadow: neuExtrudedShadows(distance: 2, blur: 5),
                          ),
                          child: const Icon(Icons.cloud_sync_rounded, color: _neuCobalt, size: 20),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'បម្រុងទុកលើ Cloud Drive',
                                style: TextStyle(
                                  color: _neuTextDark,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              Text(
                                _lastSyncStatus,
                                style: const TextStyle(
                                  color: _neuTextMuted,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                        GestureDetector(
                          onTap: _isSyncing ? null : _syncCloudBackup,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(colors: [_neuCobalt, _neuCobaltDark]),
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(color: _neuCobalt.withOpacity(0.4), blurRadius: 6, offset: const Offset(0, 2)),
                              ],
                            ),
                            child: _isSyncing
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                  )
                                : const Text(
                                    'Sync Now',
                                    style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w900),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  _buildDivider(),
                  // Clear Cache Tile
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: _neuBg,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 1.2),
                            boxShadow: neuExtrudedShadows(distance: 2, blur: 5),
                          ),
                          child: const Icon(Icons.cleaning_services_rounded, color: _neuCobalt, size: 20),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'សម្អាត Cache ផែនទី',
                                style: TextStyle(
                                  color: _neuTextDark,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              Text(
                                'បង្កើនល្បឿន និងសម្អាតទំហំផ្ទុក ($_cacheSizeText)',
                                style: const TextStyle(
                                  color: _neuTextMuted,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                        GestureDetector(
                          onTap: _showClearCacheDialog,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: _neuInputBg,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.white, width: 1),
                            ),
                            child: const Text(
                              'Clear',
                              style: TextStyle(color: _neuTextDark, fontSize: 11, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ]),
              ),
            ),

            // ── 7. Group: Help & Support ──
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(22, 18, 22, 8),
                child: _buildSectionHeader('💬 ជំនួយ & ការគាំទ្រ (Help & Support)'),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: _buildNeumorphicCard([
                  _buildActionTile(
                    icon: Icons.telegram_rounded,
                    iconColor: const Color(0xFF0088CC),
                    title: 'Telegram ក្រុមអ្នកវាស់ដី',
                    subtitle: '@net131125 • ចូលរួមសហគមន៍វិស្វករវាស់ដីកម្ពុជា',
                    onTap: _openTelegramCommunity,
                  ),
                  _buildDivider(),
                  _buildActionTile(
                    icon: Icons.menu_book_rounded,
                    iconColor: _neuYellow,
                    title: 'សៀវភៅណែនាំរបៀបវាស់ដី',
                    subtitle: 'រៀនពីវិធីគូសប្លង់ ដើរវាស់ និងគិតតម្លៃដី',
                    onTap: () => _showSurveyGuideModal(context),
                  ),
                ]),
              ),
            ),

            // ── 8. Group: Official App Branding & Version ──
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: _neuBg,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Colors.white, width: 1.6),
                    boxShadow: neuExtrudedShadows(distance: 3.5, blur: 10),
                  ),
                  child: Row(
                    children: [
                      // 3D Neumorphic Squircle App Icon
                      Container(
                        width: 64,
                        height: 64,
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          color: _neuBg,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: Colors.white, width: 1.5),
                          boxShadow: neuExtrudedShadows(distance: 3, blur: 8),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(15),
                          child: Image.asset(
                            'assets/icon/app_logo.png',
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const Icon(
                              Icons.terrain_rounded,
                              color: _neuCobalt,
                              size: 32,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Text(
                                  'GPS វាស់ដី',
                                  style: TextStyle(
                                    color: _neuTextDark,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                SizedBox(width: 6),
                                Text(
                                  'PRO',
                                  style: TextStyle(
                                    color: _neuCobalt,
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ],
                            ),
                            const Text(
                              'GPS Land Measure • កំណែ 1.0.0+1',
                              style: TextStyle(
                                color: _neuTextMuted,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 5,
                              runSpacing: 4,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: _neuCobalt.withOpacity(0.08),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Text(
                                    '🇰🇭 កម្ពុជា',
                                    style: TextStyle(color: _neuCobalt, fontSize: 9.5, fontWeight: FontWeight.w800),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF10B981).withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Text(
                                    '🛰️ RTK & GNSS',
                                    style: TextStyle(color: Color(0xFF047857), fontSize: 9.5, fontWeight: FontWeight.w800),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // ── 9. Group: Logout Button ──
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(18, 16, 18, widget.isEmbedded ? 120 : 36),
                child: _buildLogoutButton(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // 1. VIP SURVEYOR PROFILE HERO CARD (Interactive & Fully Editable!)
  // ─────────────────────────────────────────────────────────────
  Widget _buildProfileCard() {
    final currentColor = _avatarColors[_avatarColorIndex];
    final avatarDisplay = _userAvatarEmoji == 'N'
        ? (_userName.isNotEmpty ? _userName[0].toUpperCase() : 'N')
        : _userAvatarEmoji;

    return GestureDetector(
      onTap: _openFullProfileEditorDialog,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: _neuBg,
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: Colors.white, width: 1.6),
          boxShadow: neuExtrudedShadows(distance: 4, blur: 14),
        ),
        child: Row(
          children: [
            // 3D Avatar Disc with Dynamic Gradient & Camera Badge
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 58,
                  height: 58,
                  padding: const EdgeInsets.all(3.5),
                  decoration: BoxDecoration(
                    color: _neuBg,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: neuExtrudedShadows(distance: 3, blur: 7),
                  ),
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(colors: currentColor),
                    ),
                    child: Center(
                      child: Text(
                        avatarDisplay,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: _userAvatarEmoji == 'N' ? 24 : 26,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  right: -1,
                  bottom: -1,
                  child: Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: _neuBg,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 1.2),
                      boxShadow: neuExtrudedShadows(distance: 1.5, blur: 4),
                    ),
                    child: const Icon(Icons.edit_rounded, color: _neuCobalt, size: 12),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 14),

            // User Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          _userName,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: _neuTextDark,
                            fontSize: 16.5,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: _neuYellow,
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x66F7B731),
                              blurRadius: 6,
                              offset: Offset(0, 2),
                            ),
                          ],
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.star_rounded, size: 10, color: _neuTextDark),
                            SizedBox(width: 2),
                            Text(
                              'PRO',
                              style: TextStyle(
                                color: _neuTextDark,
                                fontSize: 9.5,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _userEmail,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _neuTextMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    _userRole,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _neuCobalt,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '🏷️ ID: $_userLicenseId • 📞 $_userPhone',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: _neuTextMuted.withOpacity(0.85),
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),

            // Edit icon button
            GestureDetector(
              onTap: _openFullProfileEditorDialog,
              child: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: _neuBg,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 1.2),
                  boxShadow: neuExtrudedShadows(distance: 2, blur: 5),
                ),
                child: const Icon(
                  Icons.edit_rounded,
                  color: _neuCobalt,
                  size: 18,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // 2. LIVE SURVEYOR STATS GRID (Dynamic from SharedPreferences!)
  // ─────────────────────────────────────────────────────────────
  Widget _buildSurveyorStatsGrid() {
    final areaAre = (_totalAreaM2 / 100).toStringAsFixed(1);
    final areaHa = (_totalAreaM2 / 10000).toStringAsFixed(2);
    final estTotalValue = (_totalAreaM2 * 80).round();

    return Row(
      children: [
        // Total Parcels
        Expanded(
          child: _buildStatItem(
            icon: Icons.landscape_rounded,
            color: _neuCobalt,
            value: '$_totalParcelsCount',
            unit: 'ប្លង់ដី',
            label: 'ក្បាលដីបានវាស់',
          ),
        ),
        const SizedBox(width: 8),

        // Total Area
        Expanded(
          child: _buildStatItem(
            icon: Icons.area_chart_rounded,
            color: const Color(0xFF10B981),
            value: areaAre,
            unit: 'អា ($areaHa Ha)',
            label: 'ផ្ទៃដីសរុប',
          ),
        ),
        const SizedBox(width: 8),

        // Total Pins Placed
        Expanded(
          child: _buildStatItem(
            icon: Icons.pin_drop_rounded,
            color: _neuYellow,
            value: '$_totalPointsCount',
            unit: 'ចំណុច',
            label: 'បង្គោលដីសរុប',
          ),
        ),
        const SizedBox(width: 8),

        // Estimated Value
        Expanded(
          child: _buildStatItem(
            icon: Icons.monetization_on_rounded,
            color: const Color(0xFF8B5CF6),
            value: estTotalValue > 0 ? '\$${(estTotalValue / 1000).toStringAsFixed(0)}k' : '\$0',
            unit: 'USD',
            label: 'តម្លៃប៉ាន់ស្មាន',
          ),
        ),
      ],
    );
  }

  Widget _buildStatItem({
    required IconData icon,
    required Color color,
    required String value,
    required String unit,
    required String label,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
      decoration: BoxDecoration(
        color: _neuBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white, width: 1.2),
        boxShadow: neuExtrudedShadows(distance: 2.5, blur: 6),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              color: _neuTextDark,
              fontSize: 14,
              fontWeight: FontWeight.w900,
            ),
          ),
          Text(
            unit,
            style: const TextStyle(
              color: _neuCobaltDark,
              fontSize: 9.5,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              color: _neuTextMuted,
              fontSize: 8.5,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // 3. HELPER COMPONENTS
  // ─────────────────────────────────────────────────────────────
  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(
        color: _neuCobalt,
        fontSize: 13,
        fontWeight: FontWeight.w900,
        letterSpacing: 0.2,
      ),
    );
  }

  Widget _buildNeumorphicCard(List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: _neuBg,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white, width: 1.5),
        boxShadow: neuExtrudedShadows(distance: 3.5, blur: 10),
      ),
      child: Column(children: children),
    );
  }

  Widget _buildDivider() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      height: 1,
      color: _neuTextMuted.withOpacity(0.12),
    );
  }

  Widget _buildDropdownTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required String value,
    required List<String> options,
    required ValueChanged<String?> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
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
            child: Icon(icon, color: _neuCobalt, size: 19),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: _neuTextDark,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: _neuTextMuted,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: _neuInputBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withOpacity(0.7), width: 1),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: value,
                isDense: true,
                dropdownColor: _neuBg,
                icon: const Icon(Icons.arrow_drop_down_rounded, color: _neuCobalt, size: 20),
                style: const TextStyle(
                  color: _neuCobalt,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
                items: options
                    .map((opt) => DropdownMenuItem(value: opt, child: Text(opt)))
                    .toList(),
                onChanged: onChanged,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSwitchTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
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
            child: Icon(icon, color: _neuCobalt, size: 19),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: _neuTextDark,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: _neuTextMuted,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: () => onChanged(!value),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              width: 48,
              height: 27,
              padding: const EdgeInsets.symmetric(horizontal: 3),
              decoration: BoxDecoration(
                color: value ? _neuCobalt : _neuInputBg,
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: Colors.white, width: 1),
                boxShadow: value
                    ? [
                        BoxShadow(
                          color: _neuCobalt.withOpacity(0.4),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ]
                    : [
                        BoxShadow(
                          color: _neuDarkShadow.withOpacity(0.3),
                          blurRadius: 4,
                          offset: const Offset(1, 1),
                        ),
                      ],
              ),
              child: AnimatedAlign(
                duration: const Duration(milliseconds: 220),
                alignment: value ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  width: 21,
                  height: 21,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black26,
                        blurRadius: 4,
                        offset: Offset(0, 1),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
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
              child: Icon(icon, color: iconColor, size: 19),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: _neuTextDark,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: _neuTextMuted,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios_rounded, color: _neuTextMuted, size: 14),
          ],
        ),
      ),
    );
  }

  Widget _buildLogoutButton() {
    return GestureDetector(
      onTap: _showLogoutDialog,
      child: Container(
        height: 50,
        decoration: BoxDecoration(
          color: _neuBg,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFEF4444).withOpacity(0.4), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFEF4444).withOpacity(0.12),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
            const BoxShadow(
              color: _neuLightShadow,
              blurRadius: 6,
              offset: Offset(-2, -2),
            ),
          ],
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.logout_rounded, color: Color(0xFFEF4444), size: 19),
            SizedBox(width: 8),
            Text(
              'ចាកចេញពីគណនី (Log Out)',
              style: TextStyle(
                color: Color(0xFFEF4444),
                fontSize: 14,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
