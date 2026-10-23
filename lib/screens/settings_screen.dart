import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../services/storage_service.dart';
import '../utils/constants.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final StorageService _storageService = StorageService();

  StampTemplate _selectedTemplate = StampTemplate.sidmaxPro;
  AppMapType _selectedMapType = AppMapType.satellite;
  String _companyName = AppStrings.defaultCompany;
  String? _companyLogoPath;
  bool _showCompanyBadge = true;
  bool _showMap = true;
  bool _showCoordinates = true;
  bool _showAddress = true;
  bool _showDate = true;
  bool _showAltitude = false;
  bool _showCompass = true;
  bool _saveToGallery = true;
  String _stampPosition = 'bottom';
  String _dateFormat = 'dd/MM/yyyy HH:mm';
  bool _showWeather = true;
  bool _showWind = true;
  bool _showHumidity = false;
  String _tempUnit = 'C';
  String _windUnit = 'km/h';
  bool _isLoading = true;

  late TextEditingController _companyController;

  final List<String> _dateFormats = [
    'dd/MM/yyyy HH:mm',
    'MM/dd/yyyy hh:mm a',
    'yyyy-MM-dd HH:mm',
    'dd MMM yyyy, hh:mm a',
    'MMM dd, yyyy HH:mm',
  ];

  @override
  void initState() {
    super.initState();
    _companyController = TextEditingController();
    _loadSettings();
  }

  @override
  void dispose() {
    _companyController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final template = await _storageService.getStampTemplate();
    final mapType = await _storageService.getMapType();
    final company = await _storageService.getCompanyName();
    final logoPath = await _storageService.getCompanyLogoPath();
    final showBadge = await _storageService.getShowCompanyBadge();
    final showMap = await _storageService.getShowMap();
    final showCoordinates = await _storageService.getShowCoordinates();
    final showAddress = await _storageService.getShowAddress();
    final showDate = await _storageService.getShowDate();
    final showAltitude = await _storageService.getShowAltitude();
    final showCompass = await _storageService.getShowCompass();
    final saveGallery = await _storageService.getSaveToGallery();
    final stampPos = await _storageService.getStampPosition();
    final dateFormat = await _storageService.getDateFormat();
    final showWeather = await _storageService.getShowWeather();
    final showWind = await _storageService.getShowWind();
    final showHumidity = await _storageService.getShowHumidity();
    final tempUnit = await _storageService.getTempUnit();
    final windUnit = await _storageService.getWindUnit();

    if (mounted) {
      setState(() {
        _selectedTemplate = template;
        _selectedMapType = mapType;
        _companyName = company;
        _companyLogoPath = logoPath;
        _companyController.text = company;
        _showCompanyBadge = showBadge;
        _showMap = showMap;
        _showCoordinates = showCoordinates;
        _showAddress = showAddress;
        _showDate = showDate;
        _showAltitude = showAltitude;
        _showCompass = showCompass;
        _saveToGallery = saveGallery;
        _stampPosition = stampPos;
        _dateFormat = dateFormat;
        _showWeather = showWeather;
        _showWind = showWind;
        _showHumidity = showHumidity;
        _tempUnit = tempUnit;
        _windUnit = windUnit;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primaryDark,
      appBar: AppBar(
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.settings, color: AppColors.accent, size: 22),
            SizedBox(width: 8),
            Text('Settings & Customization'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.accent),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // ─── Company Branding ────────────────────────
                _sectionHeader('Company Branding & Logo', Icons.business),
                const SizedBox(height: 10),
                _buildCompanyCard(),
                const SizedBox(height: 24),

                // ─── Map Settings ────────────────────────────
                _sectionHeader('Map Type & View', Icons.map),
                const SizedBox(height: 10),
                _buildMapTypeSelector(),
                const SizedBox(height: 10),
                _buildToggle(
                  'Show Map on Stamp',
                  'Display live mini-map snapshot on photo card',
                  Icons.map_outlined,
                  _showMap,
                  AppColors.accent,
                  (val) {
                    setState(() => _showMap = val);
                    _storageService.setShowMap(val);
                  },
                ),
                const SizedBox(height: 24),

                // ─── Stamp Template ──────────────────────────
                _sectionHeader('Stamp Template', Icons.style),
                const SizedBox(height: 10),
                _buildTemplateSelector(),
                const SizedBox(height: 24),

                // ─── Storage & Gallery ───────────────────────
                _sectionHeader('Device Storage & Gallery', Icons.save_alt),
                const SizedBox(height: 10),
                _buildToggle(
                  'Save to Mobile Phone Gallery',
                  'Auto-save stamped photos to Pictures/SidmaxGeotag album in phone Photos app',
                  Icons.photo_library,
                  _saveToGallery,
                  AppColors.accentGreen,
                  (val) {
                    setState(() => _saveToGallery = val);
                    _storageService.setSaveToGallery(val);
                  },
                ),
                const SizedBox(height: 10),
                _buildStampPositionSelector(),
                const SizedBox(height: 24),

                // ─── Overlay Elements ────────────────────────
                _sectionHeader('Overlay Elements', Icons.layers),
                const SizedBox(height: 10),
                _buildToggle(
                  'Show Coordinates',
                  'Display GPS latitude & longitude',
                  Icons.my_location,
                  _showCoordinates,
                  AppColors.accentGreen,
                  (val) {
                    setState(() => _showCoordinates = val);
                    _storageService.setShowCoordinates(val);
                  },
                ),
                _buildToggle(
                  'Show Address',
                  'Display reverse-geocoded street & city address',
                  Icons.location_on,
                  _showAddress,
                  AppColors.accent,
                  (val) {
                    setState(() => _showAddress = val);
                    _storageService.setShowAddress(val);
                  },
                ),
                _buildToggle(
                  'Show Date & Time',
                  'Display photo capture timestamp',
                  Icons.access_time,
                  _showDate,
                  AppColors.accentPurple,
                  (val) {
                    setState(() => _showDate = val);
                    _storageService.setShowDate(val);
                  },
                ),
                _buildToggle(
                  'Show Altitude',
                  'Display elevation above sea level in meters',
                  Icons.terrain,
                  _showAltitude,
                  AppColors.accentOrange,
                  (val) {
                    setState(() => _showAltitude = val);
                    _storageService.setShowAltitude(val);
                  },
                ),
                _buildToggle(
                  'Show Compass Indicator',
                  'Display direction heading',
                  Icons.explore,
                  _showCompass,
                  AppColors.accentPink,
                  (val) {
                    setState(() => _showCompass = val);
                    _storageService.setShowCompass(val);
                  },
                ),
                const SizedBox(height: 24),

                // ─── Weather & Atmosphere ────────────────────
                _sectionHeader('Weather & Atmosphere', Icons.cloud_outlined),
                const SizedBox(height: 10),
                _buildToggle(
                  'Show Weather on Stamp',
                  'Display live temperature & weather condition icon',
                  Icons.wb_sunny_outlined,
                  _showWeather,
                  Colors.orangeAccent,
                  (val) {
                    setState(() => _showWeather = val);
                    _storageService.setShowWeather(val);
                  },
                ),
                _buildToggle(
                  'Show Wind on Stamp',
                  'Display real-time wind speed & compass direction',
                  Icons.air,
                  _showWind,
                  AppColors.accent,
                  (val) {
                    setState(() => _showWind = val);
                    _storageService.setShowWind(val);
                  },
                ),
                _buildToggle(
                  'Show Humidity on Stamp',
                  'Display relative air humidity percentage',
                  Icons.water_drop_outlined,
                  _showHumidity,
                  Colors.lightBlueAccent,
                  (val) {
                    setState(() => _showHumidity = val);
                    _storageService.setShowHumidity(val);
                  },
                ),
                const SizedBox(height: 10),
                _buildUnitSelectorsCard(),
                const SizedBox(height: 24),

                // ─── Date Format ─────────────────────────────
                _sectionHeader('Date & Time Format', Icons.calendar_today),
                const SizedBox(height: 10),
                _buildDateFormatSelector(),
                const SizedBox(height: 24),

                // ─── About ───────────────────────────────────
                _sectionHeader('About', Icons.info_outline),
                const SizedBox(height: 10),
                _buildAboutCard(),
                const SizedBox(height: 32),
              ],
            ),
    );
  }

  Widget _sectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: AppColors.accent, size: 18),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }

  Widget _buildCompanyCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.asset(
                  AppStrings.logoAsset,
                  width: 44,
                  height: 44,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => Container(
                    width: 44,
                    height: 44,
                    color: AppColors.surfaceLight,
                    child: const Icon(Icons.business, color: AppColors.accent),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Brand Logo & Name',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Appears in the header pill badge of the photo stamp',
                      style: TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _companyController,
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
            decoration: InputDecoration(
              labelText: 'Company / Business Name',
              labelStyle: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
              ),
              hintText: AppStrings.defaultCompany,
              hintStyle: const TextStyle(color: AppColors.textMuted),
              prefixIcon: const Icon(
                Icons.edit,
                color: AppColors.accent,
                size: 18,
              ),
              filled: true,
              fillColor: AppColors.primaryMid,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.accent),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 12,
              ),
            ),
            onChanged: (val) {
              final newName = val.trim().isNotEmpty
                  ? val.trim()
                  : AppStrings.defaultCompany;
              setState(() => _companyName = newName);
              _storageService.setCompanyName(newName);
            },
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.border),
                ),
                clipBehavior: Clip.antiAlias,
                child: _companyLogoPath != null
                    ? Image.file(
                        File(_companyLogoPath!),
                        fit: BoxFit.cover,
                      )
                    : const Icon(
                        Icons.image,
                        color: AppColors.textMuted,
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Company Logo',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _companyLogoPath != null ? 'Logo selected' : 'No logo selected',
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              if (_companyLogoPath != null)
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                  onPressed: () {
                    setState(() => _companyLogoPath = null);
                    _storageService.setCompanyLogoPath(null);
                  },
                ),
              ElevatedButton(
                onPressed: () async {
                  final ImagePicker picker = ImagePicker();
                  final XFile? image = await picker.pickImage(source: ImageSource.gallery);
                  if (image != null) {
                    setState(() => _companyLogoPath = image.path);
                    _storageService.setCompanyLogoPath(image.path);
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text('Pick Logo'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildToggle(
            'Show Company Pill Badge',
            'Display the logo & company name pill on top of stamp card',
            Icons.badge,
            _showCompanyBadge,
            AppColors.accentPurple,
            (val) {
              setState(() => _showCompanyBadge = val);
              _storageService.setShowCompanyBadge(val);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildMapTypeSelector() {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Text(
              'Select Default Map Layer:',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: AppMapType.values.map((type) {
              final isSelected = type == _selectedMapType;
              return Expanded(
                child: GestureDetector(
                  onTap: () {
                    setState(() => _selectedMapType = type);
                    _storageService.setMapType(type);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppColors.accent.withValues(alpha: 0.18)
                          : AppColors.primaryMid,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isSelected ? AppColors.accent : AppColors.border,
                        width: isSelected ? 1.5 : 1.0,
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          type.icon,
                          color: isSelected
                              ? AppColors.accent
                              : AppColors.textSecondary,
                          size: 22,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          type.displayName,
                          style: TextStyle(
                            color: isSelected
                                ? AppColors.accent
                                : AppColors.textPrimary,
                            fontSize: 11,
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildStampPositionSelector() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Row(
            children: [
              Icon(
                Icons.vertical_align_bottom,
                color: AppColors.accent,
                size: 20,
              ),
              SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Stamp Card Position',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    'Placement on captured photo',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 11),
                  ),
                ],
              ),
            ],
          ),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'bottom', label: Text('Bottom')),
              ButtonSegment(value: 'top', label: Text('Top')),
            ],
            selected: {_stampPosition},
            onSelectionChanged: (val) {
              setState(() => _stampPosition = val.first);
              _storageService.setStampPosition(val.first);
            },
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
          ),
        ],
      ),
    );
  }

  Widget _buildTemplateSelector() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: StampTemplate.values.map((template) {
          final isSelected = template == _selectedTemplate;
          final isRecommended = template == StampTemplate.sidmaxPro;

          return GestureDetector(
            onTap: () {
              setState(() => _selectedTemplate = template);
              _storageService.setStampTemplate(template);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.all(4),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
              decoration: BoxDecoration(
                color: isSelected
                    ? AppColors.accent.withValues(alpha: 0.12)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isSelected ? AppColors.accent : Colors.transparent,
                  width: 1.5,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppColors.accent.withValues(alpha: 0.2)
                          : AppColors.surfaceLight,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      template.icon,
                      color: isSelected
                          ? AppColors.accent
                          : AppColors.textMuted,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              template.displayName,
                              style: TextStyle(
                                color: isSelected
                                    ? AppColors.textPrimary
                                    : AppColors.textSecondary,
                                fontSize: 14,
                                fontWeight: isSelected
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                              ),
                            ),
                            if (isRecommended) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.accentGreen.withValues(
                                    alpha: 0.2,
                                  ),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Text(
                                  'DEFAULT',
                                  style: TextStyle(
                                    color: AppColors.accentGreen,
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        Text(
                          isRecommended
                              ? 'Live Google Map + Sidmax Logo + GPS stamp'
                              : 'Standard geotag stamp',
                          style: const TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (isSelected)
                    const Icon(
                      Icons.check_circle,
                      color: AppColors.accent,
                      size: 22,
                    ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildToggle(
    String title,
    String subtitle,
    IconData icon,
    bool value,
    Color color,
    ValueChanged<bool> onChanged,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          Switch(value: value, activeThumbColor: color, onChanged: onChanged),
        ],
      ),
    );
  }

  Widget _buildDateFormatSelector() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: _dateFormats.map((format) {
          final isSelected = format == _dateFormat;
          return GestureDetector(
            onTap: () {
              setState(() => _dateFormat = format);
              _storageService.setDateFormat(format);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.all(4),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: isSelected
                    ? AppColors.accentPurple.withValues(alpha: 0.12)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isSelected
                      ? AppColors.accentPurple
                      : Colors.transparent,
                  width: 1.5,
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      format,
                      style: TextStyle(
                        color: isSelected
                            ? AppColors.textPrimary
                            : AppColors.textSecondary,
                        fontSize: 13.5,
                        fontWeight: isSelected
                            ? FontWeight.w600
                            : FontWeight.w400,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                  if (isSelected)
                    const Icon(
                      Icons.check_circle,
                      color: AppColors.accentPurple,
                      size: 20,
                    ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildAboutCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.accent.withValues(alpha: 0.08),
            AppColors.accentPurple.withValues(alpha: 0.08),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Image.asset(
              AppStrings.logoAsset,
              width: 64,
              height: 64,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            _companyName,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            AppStrings.appTagline,
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.surfaceLight,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              'v${AppStrings.appVersion} • Build by Cybert S. Romero',
              style: TextStyle(
                color: AppColors.textMuted,
                fontSize: 11,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUnitSelectorsCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Weather Measurement Units',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          // Temperature Unit
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Temperature Unit',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
              Row(
                children: [
                  _buildUnitPill(
                    label: '°C Celsius',
                    isSelected: _tempUnit == 'C',
                    onTap: () {
                      setState(() => _tempUnit = 'C');
                      _storageService.setTempUnit('C');
                    },
                  ),
                  const SizedBox(width: 8),
                  _buildUnitPill(
                    label: '°F Fahrenheit',
                    isSelected: _tempUnit == 'F',
                    onTap: () {
                      setState(() => _tempUnit = 'F');
                      _storageService.setTempUnit('F');
                    },
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(color: AppColors.border, height: 1),
          const SizedBox(height: 12),
          // Wind Unit
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Wind Speed Unit',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
              Row(
                children: [
                  _buildUnitPill(
                    label: 'km/h',
                    isSelected: _windUnit == 'km/h',
                    onTap: () {
                      setState(() => _windUnit = 'km/h');
                      _storageService.setWindUnit('km/h');
                    },
                  ),
                  const SizedBox(width: 8),
                  _buildUnitPill(
                    label: 'mph',
                    isSelected: _windUnit == 'mph',
                    onTap: () {
                      setState(() => _windUnit = 'mph');
                      _storageService.setWindUnit('mph');
                    },
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildUnitPill({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.accent.withValues(alpha: 0.2)
              : AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? AppColors.accent : AppColors.border,
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? AppColors.accent : AppColors.textMuted,
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}
