import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../models/photo_data.dart';
import '../services/location_service.dart';
import '../services/storage_service.dart';
import '../utils/constants.dart';
import '../widgets/gps_overlay.dart';

class EditPhotoStampScreen extends StatefulWidget {
  final PhotoData photo;

  const EditPhotoStampScreen({super.key, required this.photo});

  @override
  State<EditPhotoStampScreen> createState() => _EditPhotoStampScreenState();
}

class _EditPhotoStampScreenState extends State<EditPhotoStampScreen> {
  final StorageService _storageService = StorageService();
  final LocationService _locationService = LocationService();

  late TextEditingController _titleController;
  late TextEditingController _addressController;
  late TextEditingController _latController;
  late TextEditingController _lngController;
  late TextEditingController _altController;
  late TextEditingController _companyController;

  late DateTime _selectedDateTime;
  late AppMapType _selectedMapType;
  late StampTemplate _selectedTemplate;
  String? _companyLogoPath;
  String _stampPosition = 'bottom';
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final p = widget.photo;
    _titleController = TextEditingController(
      text: p.city.isNotEmpty ? '${p.city}, ${p.country}' : p.shortAddress,
    );
    _addressController = TextEditingController(text: p.address);
    _latController = TextEditingController(text: p.latitude.toStringAsFixed(6));
    _lngController = TextEditingController(text: p.longitude.toStringAsFixed(6));
    _altController = TextEditingController(
      text: p.altitude != null ? p.altitude!.toStringAsFixed(1) : '15.0',
    );
    _companyController = TextEditingController(text: p.companyName);
    _selectedDateTime = p.timestamp;
    _selectedMapType = AppMapTypeExt.fromString(p.mapType);
    _selectedTemplate = StampTemplate.values.firstWhere(
      (t) => t.name == p.stampTemplate,
      orElse: () => StampTemplate.sidmaxPro,
    );
    _loadCompanyLogoPath();
  }

  Future<void> _loadCompanyLogoPath() async {
    final logoPath = await _storageService.getCompanyLogoPath();
    if (mounted) {
      setState(() => _companyLogoPath = logoPath);
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _addressController.dispose();
    _latController.dispose();
    _lngController.dispose();
    _altController.dispose();
    _companyController.dispose();
    super.dispose();
  }

  LocationData _buildCurrentLocationData() {
    final lat = double.tryParse(_latController.text) ?? widget.photo.latitude;
    final lng = double.tryParse(_lngController.text) ?? widget.photo.longitude;
    final alt = double.tryParse(_altController.text);

    return LocationData(
      latitude: lat,
      longitude: lng,
      altitude: alt,
      address: _addressController.text,
      city: _titleController.text,
      country: '',
    );
  }

  Future<void> _fetchCurrentGps() async {
    final pos = await _locationService.getCurrentPosition();
    if (pos != null && mounted) {
      setState(() {
        _latController.text = pos.latitude.toStringAsFixed(6);
        _lngController.text = pos.longitude.toStringAsFixed(6);
        if (pos.altitude != 0) {
          _altController.text = pos.altitude.toStringAsFixed(1);
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Updated with current GPS coordinates'),
          duration: Duration(seconds: 1),
        ),
      );
    }
  }

  Future<void> _pickDate() async {
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: _selectedDateTime,
      firstDate: DateTime(2000),
      lastDate: DateTime(2035),
    );
    if (pickedDate != null && mounted) {
      setState(() {
        _selectedDateTime = DateTime(
          pickedDate.year,
          pickedDate.month,
          pickedDate.day,
          _selectedDateTime.hour,
          _selectedDateTime.minute,
          _selectedDateTime.second,
        );
      });
    }
  }

  Future<void> _pickTime() async {
    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_selectedDateTime),
    );
    if (pickedTime != null && mounted) {
      setState(() {
        _selectedDateTime = DateTime(
          _selectedDateTime.year,
          _selectedDateTime.month,
          _selectedDateTime.day,
          pickedTime.hour,
          pickedTime.minute,
        );
      });
    }
  }

  Future<void> _saveAndBurnStamp() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);

    try {
      final double lat = double.tryParse(_latController.text) ?? widget.photo.latitude;
      final double lng = double.tryParse(_lngController.text) ?? widget.photo.longitude;
      final double? alt = double.tryParse(_altController.text);
      final String address = _addressController.text;
      final String city = _titleController.text;
      final String companyName = _companyController.text.trim().isNotEmpty
          ? _companyController.text.trim()
          : AppStrings.defaultCompany;

      // 1. Read original photo file
      final file = File(widget.photo.imagePath);
      final bytes = await file.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final originalImage = frame.image;

      // 2. Load company logo
      ui.Image? logoUiImage;
      try {
        final ByteData logoData = await rootBundle.load(AppStrings.logoAsset);
        final logoCodec = await ui.instantiateImageCodec(
          logoData.buffer.asUint8List(),
        );
        final logoFrame = await logoCodec.getNextFrame();
        logoUiImage = logoFrame.image;
      } catch (e) {
        debugPrint('Logo load error: $e');
      }

      // 3. Render Canvas
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      final imgWidth = originalImage.width.toDouble();
      final imgHeight = originalImage.height.toDouble();

      canvas.drawImage(originalImage, Offset.zero, Paint());

      // Render updated stamp overlay on canvas
      _drawEditedStampOnCanvas(
        canvas: canvas,
        imgWidth: imgWidth,
        imgHeight: imgHeight,
        logoImage: logoUiImage,
        lat: lat,
        lng: lng,
        alt: alt,
        address: address,
        cityTitle: city,
        companyName: companyName,
        dateTime: _selectedDateTime,
      );

      final picture = recorder.endRecording();
      final stampedImage = await picture.toImage(
        originalImage.width,
        originalImage.height,
      );

      final byteData = await stampedImage.toByteData(
        format: ui.ImageByteFormat.png,
      );
      if (byteData != null) {
        await file.writeAsBytes(byteData.buffer.asUint8List());
      }

      originalImage.dispose();
      logoUiImage?.dispose();
      stampedImage.dispose();

      // 4. Save/Re-export directly to Phone Gallery
      await _storageService.saveToDeviceGallery(
        widget.photo.imagePath,
        fileName: 'SidmaxGeotag_${widget.photo.id}_edited.jpg',
      );

      // 5. Update PhotoData in storage
      final updatedPhoto = PhotoData(
        id: widget.photo.id,
        imagePath: widget.photo.imagePath,
        latitude: lat,
        longitude: lng,
        altitude: alt,
        address: address,
        city: city,
        country: widget.photo.country,
        timestamp: _selectedDateTime,
        stampTemplate: _selectedTemplate.name,
        mapType: _selectedMapType.name,
        companyName: companyName,
      );

      await _storageService.updatePhotoData(updatedPhoto);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.check_circle, color: AppColors.accentGreen, size: 20),
                SizedBox(width: 8),
                Text('Stamp updated & re-saved to phone Gallery!'),
              ],
            ),
            backgroundColor: AppColors.surface,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
        Navigator.pop(context, updatedPhoto);
      }
    } catch (e) {
      debugPrint('Error updating stamp: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error updating stamp: $e'),
            backgroundColor: AppColors.accentRed,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _drawEditedStampOnCanvas({
    required Canvas canvas,
    required double imgWidth,
    required double imgHeight,
    required ui.Image? logoImage,
    required double lat,
    required double lng,
    required double? alt,
    required String address,
    required String cityTitle,
    required String companyName,
    required DateTime dateTime,
  }) {
    final isLandscape = imgWidth > imgHeight;
    final scale = (imgWidth / 480.0).clamp(1.0, 8.0);

    final cardPadding = 12.0 * scale;
    final cardWidth = isLandscape
        ? (imgWidth * 0.55).clamp(380.0 * scale, imgWidth - (24.0 * scale))
        : imgWidth - (24.0 * scale);
    final cardHeight = 110.0 * scale;
    final cardX = 12.0 * scale;
    final cardY = _stampPosition == 'top'
        ? (36.0 * scale)
        : (imgHeight - cardHeight - (18.0 * scale));

    // Badge
    final badgeHeight = 22.0 * scale;
    final badgeY = cardY - badgeHeight - (6.0 * scale);
    final badgeFontSize = 10.5 * scale;

    final badgeTextBuilder = ui.ParagraphBuilder(
      ui.ParagraphStyle(fontSize: badgeFontSize, fontWeight: ui.FontWeight.bold),
    )
      ..pushStyle(ui.TextStyle(
        color: const Color(0xFFFFFFFF),
        fontSize: badgeFontSize,
        fontWeight: ui.FontWeight.w700,
      ))
      ..addText(companyName);

    final badgeText = badgeTextBuilder.build()
      ..layout(ui.ParagraphConstraints(width: cardWidth * 0.6));

    final logoSize = 14.0 * scale;
    final badgeWidth = badgeText.longestLine + logoSize + (22.0 * scale);
    final badgeX = cardX + cardWidth - badgeWidth;

    final badgeRRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(badgeX, badgeY, badgeWidth, badgeHeight),
      Radius.circular(badgeHeight / 2),
    );
    canvas.drawRRect(
      badgeRRect,
      Paint()..color = const Color(0xEB000000)..style = PaintingStyle.fill,
    );
    canvas.drawRRect(
      badgeRRect,
      Paint()
        ..color = const Color(0x55FFFFFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0 * scale,
    );

    final logoDrawX = badgeX + (6.0 * scale);
    final logoDrawY = badgeY + (badgeHeight - logoSize) / 2;
    if (logoImage != null) {
      canvas.drawImageRect(
        logoImage,
        Rect.fromLTWH(0, 0, logoImage.width.toDouble(), logoImage.height.toDouble()),
        Rect.fromLTWH(logoDrawX, logoDrawY, logoSize, logoSize),
        Paint(),
      );
    }

    canvas.drawParagraph(
      badgeText,
      Offset(logoDrawX + logoSize + (6.0 * scale), badgeY + (badgeHeight - badgeFontSize) / 2 - (1.0 * scale)),
    );

    // Card background
    final cardRRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(cardX, cardY, cardWidth, cardHeight),
      Radius.circular(16.0 * scale),
    );
    canvas.drawRRect(
      cardRRect,
      Paint()..color = const Color(0xDE10141A)..style = PaintingStyle.fill,
    );
    canvas.drawRRect(
      cardRRect,
      Paint()
        ..color = const Color(0x38FFFFFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2 * scale,
    );

    // Mini Map graphics on left
    final mapSize = cardHeight - (cardPadding * 2);
    final mapX = cardX + cardPadding;
    final mapY = cardY + cardPadding;
    final mapRRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(mapX, mapY, mapSize, mapSize),
      Radius.circular(10.0 * scale),
    );

    canvas.save();
    canvas.clipRRect(mapRRect);
    canvas.drawRect(
      Rect.fromLTWH(mapX, mapY, mapSize, mapSize),
      Paint()..color = const Color(0xFF1B232E),
    );
    // Grid lines
    final gridPaint = Paint()
      ..color = const Color(0x3358A6FF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0 * scale;
    for (int i = 1; i <= 3; i++) {
      final step = mapSize * (i / 4.0);
      canvas.drawLine(Offset(mapX + step, mapY), Offset(mapX + step, mapY + mapSize), gridPaint);
      canvas.drawLine(Offset(mapX, mapY + step), Offset(mapX + mapSize, mapY + step), gridPaint);
    }

    // Center red pin marker
    final pinCenterX = mapX + mapSize / 2;
    final pinCenterY = mapY + mapSize / 2 - (3.0 * scale);
    final pinRadius = 6.5 * scale;
    canvas.drawCircle(Offset(pinCenterX, pinCenterY), pinRadius, Paint()..color = const Color(0xFFEA4335));
    canvas.drawCircle(Offset(pinCenterX, pinCenterY), 2.5 * scale, Paint()..color = const Color(0xFFFFFFFF));
    final path = Path()
      ..moveTo(pinCenterX - (3.5 * scale), pinCenterY + (3.5 * scale))
      ..lineTo(pinCenterX, pinCenterY + (9.0 * scale))
      ..lineTo(pinCenterX + (3.5 * scale), pinCenterY + (3.5 * scale))
      ..close();
    canvas.drawPath(path, Paint()..color = const Color(0xFFEA4335));

    // Watermark "Google"
    final wmBuilder = ui.ParagraphBuilder(
      ui.ParagraphStyle(fontSize: 7.0 * scale, fontWeight: ui.FontWeight.bold),
    )
      ..pushStyle(ui.TextStyle(color: const Color(0xCCFFFFFF), fontSize: 7.0 * scale))
      ..addText('Google');
    final wmPara = wmBuilder.build()..layout(ui.ParagraphConstraints(width: mapSize));
    canvas.drawParagraph(wmPara, Offset(mapX + (4.0 * scale), mapY + mapSize - (11.0 * scale)));

    // Map type tag
    final mtBuilder = ui.ParagraphBuilder(
      ui.ParagraphStyle(fontSize: 6.5 * scale, fontWeight: ui.FontWeight.bold),
    )
      ..pushStyle(ui.TextStyle(color: const Color(0xFFFFFFFF), fontSize: 6.5 * scale))
      ..addText(_selectedMapType.name.substring(0, 3).toUpperCase());
    final mtPara = mtBuilder.build()..layout(ui.ParagraphConstraints(width: 30.0 * scale));
    final mtRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(mapX + mapSize - (24.0 * scale), mapY + (3.0 * scale), 21.0 * scale, 9.0 * scale),
      Radius.circular(3.0 * scale),
    );
    canvas.drawRRect(mtRect, Paint()..color = const Color(0xCC238636));
    canvas.drawParagraph(mtPara, Offset(mapX + mapSize - (22.5 * scale), mapY + (3.5 * scale)));

    canvas.restore();

    canvas.drawRRect(
      mapRRect,
      Paint()..color = const Color(0x44FFFFFF)..style = PaintingStyle.stroke..strokeWidth = 1.0 * scale,
    );

    // Text on right
    final textLeft = mapX + mapSize + (10.0 * scale);
    final textWidth = cardWidth - (textLeft - cardX) - cardPadding;
    double currentY = cardY + cardPadding + (1.0 * scale);

    // Title
    final titleFontSize = 12.5 * scale;
    final titleBuilder = ui.ParagraphBuilder(
      ui.ParagraphStyle(fontSize: titleFontSize, fontWeight: ui.FontWeight.w700, maxLines: 1, ellipsis: '...'),
    )
      ..pushStyle(ui.TextStyle(color: const Color(0xFFFFFFFF), fontSize: titleFontSize, fontWeight: ui.FontWeight.w700))
      ..addText(cityTitle);
    final titlePara = titleBuilder.build()..layout(ui.ParagraphConstraints(width: textWidth));
    canvas.drawParagraph(titlePara, Offset(textLeft, currentY));
    currentY += titleFontSize * 1.35;

    // Address
    final addrFontSize = 9.2 * scale;
    final addrBuilder = ui.ParagraphBuilder(
      ui.ParagraphStyle(fontSize: addrFontSize, maxLines: 2, ellipsis: '...'),
    )
      ..pushStyle(ui.TextStyle(color: const Color(0xE6FFFFFF), fontSize: addrFontSize))
      ..addText('📍 $address');
    final addrPara = addrBuilder.build()..layout(ui.ParagraphConstraints(width: textWidth));
    canvas.drawParagraph(addrPara, Offset(textLeft, currentY));
    currentY += (addrPara.height + (3.0 * scale)).clamp(addrFontSize * 1.2, addrFontSize * 2.5);

    // Coordinates
    final coordFontSize = 9.0 * scale;
    final latDir = lat >= 0 ? 'N' : 'S';
    final lngDir = lng >= 0 ? 'E' : 'W';
    final coordStr = '🎯 Lat ${lat.abs().toStringAsFixed(4)}° $latDir  |  Long ${lng.abs().toStringAsFixed(4)}° $lngDir';
    final coordBuilder = ui.ParagraphBuilder(
      ui.ParagraphStyle(fontSize: coordFontSize),
    )
      ..pushStyle(ui.TextStyle(color: const Color(0xF258A6FF), fontSize: coordFontSize, fontFamily: 'monospace', fontWeight: ui.FontWeight.w600))
      ..addText(coordStr);
    final coordPara = coordBuilder.build()..layout(ui.ParagraphConstraints(width: textWidth));
    canvas.drawParagraph(coordPara, Offset(textLeft, currentY));
    currentY += coordFontSize * 1.35;

    // Date & Time
    final dateFontSize = 8.8 * scale;
    final dateFormatted = DateFormat('dd/MM/yyyy HH:mm').format(dateTime);
    String dateStr = '📅 $dateFormatted';
    if (alt != null) {
      dateStr += '  |  ⛰️ ${alt.toStringAsFixed(1)}m';
    }
    final dateBuilder = ui.ParagraphBuilder(
      ui.ParagraphStyle(fontSize: dateFontSize),
    )
      ..pushStyle(ui.TextStyle(color: const Color(0xE63FB950), fontSize: dateFontSize, fontWeight: ui.FontWeight.w500))
      ..addText(dateStr);
    final datePara = dateBuilder.build()..layout(ui.ParagraphConstraints(width: textWidth));
    canvas.drawParagraph(datePara, Offset(textLeft, currentY));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primaryDark,
      appBar: AppBar(
        title: const Text('Edit Photo Stamp'),
        actions: [
          IconButton(
            icon: _isSaving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.check, color: AppColors.accentGreen),
            onPressed: _isSaving ? null : _saveAndBurnStamp,
            tooltip: 'Save and Export to Gallery',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ─── Live Stamp Preview on Photo ───────────
          Container(
            height: 230,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.file(
                  File(widget.photo.imagePath),
                  fit: BoxFit.cover,
                ),
                Positioned(
                  bottom: _stampPosition == 'bottom' ? 6 : null,
                  top: _stampPosition == 'top' ? 6 : null,
                  left: 0,
                  right: 0,
                  child: GpsOverlay(
                    locationData: _buildCurrentLocationData(),
                    template: _selectedTemplate,
                    mapType: _selectedMapType,
                    companyName: _companyController.text,
                    companyLogoPath: _companyLogoPath,
                    dateFormat: 'dd/MM/yyyy HH:mm',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          const Center(
            child: Text(
              'Real-Time Live Stamp Preview',
              style: TextStyle(color: AppColors.textMuted, fontSize: 11),
            ),
          ),
          const SizedBox(height: 20),

          // ─── Location & Address Fields ─────────────
          _sectionTitle('Location Information', Icons.edit_location),
          const SizedBox(height: 10),
          TextField(
            controller: _titleController,
            style: const TextStyle(color: AppColors.textPrimary),
            decoration: _inputDecoration('Locality / City Title', Icons.location_city),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _addressController,
            maxLines: 2,
            style: const TextStyle(color: AppColors.textPrimary),
            decoration: _inputDecoration('Street / Full Address', Icons.place),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 20),

          // ─── Coordinates & Altitude ────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _sectionTitle('GPS Coordinates', Icons.gps_fixed),
              TextButton.icon(
                onPressed: _fetchCurrentGps,
                icon: const Icon(Icons.my_location, size: 16, color: AppColors.accent),
                label: const Text('Use Current GPS', style: TextStyle(color: AppColors.accent, fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _latController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                  style: const TextStyle(color: AppColors.textPrimary, fontFamily: 'monospace'),
                  decoration: _inputDecoration('Latitude', Icons.north),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _lngController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                  style: const TextStyle(color: AppColors.textPrimary, fontFamily: 'monospace'),
                  decoration: _inputDecoration('Longitude', Icons.east),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _altController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(color: AppColors.textPrimary, fontFamily: 'monospace'),
            decoration: _inputDecoration('Altitude (meters)', Icons.terrain),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 20),

          // ─── Date & Time ───────────────────────────
          _sectionTitle('Date & Timestamp', Icons.calendar_today),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _pickDate,
                  icon: const Icon(Icons.calendar_month, color: AppColors.accentGreen, size: 18),
                  label: Text(
                    DateFormat('MMM dd, yyyy').format(_selectedDateTime),
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                  ),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: const BorderSide(color: AppColors.border),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _pickTime,
                  icon: const Icon(Icons.access_time, color: AppColors.accent, size: 18),
                  label: Text(
                    DateFormat('hh:mm a').format(_selectedDateTime),
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                  ),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: const BorderSide(color: AppColors.border),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // ─── Company Branding ──────────────────────
          _sectionTitle('Company Branding', Icons.business),
          const SizedBox(height: 10),
          TextField(
            controller: _companyController,
            style: const TextStyle(color: AppColors.textPrimary),
            decoration: _inputDecoration('Company / Brand Name', Icons.badge),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 20),

          // ─── Map Type on Stamp ─────────────────────
          _sectionTitle('Map Layer on Stamp', Icons.layers),
          const SizedBox(height: 10),
          Row(
            children: AppMapType.values.map((type) {
              final isSelected = type == _selectedMapType;
              return Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _selectedMapType = type),
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: isSelected ? AppColors.accent.withValues(alpha: 0.2) : AppColors.surface,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: isSelected ? AppColors.accent : AppColors.border),
                    ),
                    child: Column(
                      children: [
                        Icon(type.icon, color: isSelected ? AppColors.accent : AppColors.textMuted, size: 18),
                        const SizedBox(height: 4),
                        Text(
                          type.displayName,
                          style: TextStyle(
                            color: isSelected ? AppColors.accent : AppColors.textSecondary,
                            fontSize: 10,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 20),

          // ─── Stamp Position ────────────────────────
          _sectionTitle('Stamp Placement', Icons.vertical_align_bottom),
          const SizedBox(height: 10),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'bottom', label: Text('Bottom of Photo')),
              ButtonSegment(value: 'top', label: Text('Top of Photo')),
            ],
            selected: {_stampPosition},
            onSelectionChanged: (val) => setState(() => _stampPosition = val.first),
          ),
          const SizedBox(height: 30),

          // ─── Big Save Button ───────────────────────
          ElevatedButton.icon(
            onPressed: _isSaving ? null : _saveAndBurnStamp,
            icon: _isSaving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.save),
            label: Text(_isSaving ? 'Re-Rendering & Saving...' : 'Save & Re-Export to Gallery'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              backgroundColor: AppColors.accent,
              foregroundColor: Colors.white,
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: AppColors.accent, size: 17),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  InputDecoration _inputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
      prefixIcon: Icon(icon, color: AppColors.accent, size: 18),
      filled: true,
      fillColor: AppColors.surface,
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
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    );
  }
}
