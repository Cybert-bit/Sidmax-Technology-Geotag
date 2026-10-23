import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import '../models/photo_data.dart';
import '../services/storage_service.dart';
import '../utils/constants.dart';

/// Represents a draggable text annotation placed on the photo
class DraggableTextItem {
  final String id;
  String text;
  Offset position;
  Color textColor;
  Color backgroundColor;
  double fontSize;
  bool isBold;
  bool hasBackground;

  DraggableTextItem({
    required this.id,
    required this.text,
    required this.position,
    this.textColor = Colors.white,
    this.backgroundColor = const Color(0xCC000000),
    this.fontSize = 16.0,
    this.isBold = true,
    this.hasBackground = true,
  });
}

class PhotoAnnotateScreen extends StatefulWidget {
  final PhotoData photo;

  const PhotoAnnotateScreen({super.key, required this.photo});

  @override
  State<PhotoAnnotateScreen> createState() => _PhotoAnnotateScreenState();
}

class _PhotoAnnotateScreenState extends State<PhotoAnnotateScreen> {
  final StorageService _storageService = StorageService();
  final List<DraggableTextItem> _textItems = [];
  String? _selectedItemId;
  bool _isSaving = false;

  // Rendered photo layout dimensions
  Size _imageDisplaySize = Size.zero;
  final Offset _imageDisplayOffset = Offset.zero;

  final List<Color> _paletteColors = [
    Colors.white,
    const Color(0xFFFFEB3B), // Yellow
    const Color(0xFF58A6FF), // Blue/Cyan
    const Color(0xFF3FB950), // Green
    const Color(0xFFEA4335), // Red
    const Color(0xFFFFA726), // Orange
    Colors.black,
  ];

  @override
  void initState() {
    super.initState();
    // Pre-populate with a starter text item
    _textItems.add(
      DraggableTextItem(
        id: 'initial_text',
        text: '📍 ${widget.photo.city.isNotEmpty ? widget.photo.city : 'Survey Note'}',
        position: const Offset(30, 40),
        textColor: Colors.white,
        backgroundColor: const Color(0xDE000000),
        fontSize: 16,
        isBold: true,
        hasBackground: true,
      ),
    );
  }

  void _addNewText([String defaultText = 'New Note']) {
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    final double yOffset = (60.0 + (_textItems.length * 40.0)).clamp(40.0, 300.0);
    final newItem = DraggableTextItem(
      id: id,
      text: defaultText,
      position: Offset(40, yOffset),
      textColor: Colors.white,
      backgroundColor: const Color(0xDE10141A),
      fontSize: 16,
      isBold: true,
      hasBackground: true,
    );
    setState(() {
      _textItems.add(newItem);
      _selectedItemId = id;
    });
    _openEditModal(newItem);
  }

  void _openEditModal(DraggableTextItem item) {
    final textController = TextEditingController(text: item.text);
    Color selectedColor = item.textColor;
    Color selectedBg = item.backgroundColor;
    double fontSize = item.fontSize;
    bool isBold = item.isBold;
    bool hasBg = item.hasBackground;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.cardBackground,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 18,
                right: 18,
                top: 18,
                bottom: MediaQuery.of(context).viewInsets.bottom + 18,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Edit Text Annotation',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white70),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // Text input
                  TextField(
                    controller: textController,
                    autofocus: false,
                    style: const TextStyle(color: Colors.white, fontSize: 15),
                    decoration: InputDecoration(
                      hintText: 'Enter text here...',
                      hintStyle: const TextStyle(color: Colors.white38),
                      filled: true,
                      fillColor: AppColors.surface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                      prefixIcon: const Icon(Icons.title, color: AppColors.accent),
                    ),
                    onChanged: (val) {
                      setModalState(() {});
                    },
                  ),
                  const SizedBox(height: 14),

                  // Quick presets
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _presetChip('📍 Location', () {
                        textController.text =
                            '📍 ${widget.photo.latitude.toStringAsFixed(4)}, ${widget.photo.longitude.toStringAsFixed(4)}';
                        setModalState(() {});
                      }),
                      _presetChip('📅 Date', () {
                        textController.text =
                            '📅 ${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())}';
                        setModalState(() {});
                      }),
                      _presetChip('✅ APPROVED', () {
                        textController.text = '✅ INSPECTION APPROVED';
                        setModalState(() {
                          selectedBg = const Color(0xDE2E7D32);
                          hasBg = true;
                        });
                      }),
                      _presetChip('⚠️ WARNING', () {
                        textController.text = '⚠️ REPAIR NEEDED';
                        setModalState(() {
                          selectedBg = const Color(0xDEC62828);
                          hasBg = true;
                        });
                      }),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // Font size slider
                  Row(
                    children: [
                      const Text('Size: ', style: TextStyle(color: Colors.white70, fontSize: 13)),
                      Expanded(
                        child: Slider(
                          value: fontSize,
                          min: 12,
                          max: 36,
                          divisions: 12,
                          activeColor: AppColors.accent,
                          label: fontSize.round().toString(),
                          onChanged: (v) {
                            setModalState(() => fontSize = v);
                          },
                        ),
                      ),
                      Text(
                        '${fontSize.round()}px',
                        style: const TextStyle(color: Colors.white, fontSize: 12),
                      ),
                    ],
                  ),

                  // Text color palette
                  Row(
                    children: [
                      const Text('Color: ', style: TextStyle(color: Colors.white70, fontSize: 13)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: _paletteColors.map((col) {
                              final isSelected = selectedColor.toARGB32() == col.toARGB32();
                              return GestureDetector(
                                onTap: () => setModalState(() => selectedColor = col),
                                child: Container(
                                  margin: const EdgeInsets.symmetric(horizontal: 4),
                                  width: 28,
                                  height: 28,
                                  decoration: BoxDecoration(
                                    color: col,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: isSelected ? AppColors.accent : Colors.white24,
                                      width: isSelected ? 2.5 : 1,
                                    ),
                                  ),
                                  child: isSelected
                                      ? Icon(
                                          Icons.check,
                                          size: 16,
                                          color: col == Colors.white ? Colors.black : Colors.white,
                                        )
                                      : null,
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // Background badge options & Bold toggle
                  Row(
                    children: [
                      Expanded(
                        child: FilterChip(
                          label: const Text('Background Box'),
                          selected: hasBg,
                          selectedColor: AppColors.accent.withValues(alpha: 0.3),
                          checkmarkColor: AppColors.accent,
                          labelStyle: TextStyle(
                            color: hasBg ? AppColors.accent : Colors.white70,
                            fontSize: 12,
                          ),
                          onSelected: (v) => setModalState(() => hasBg = v),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilterChip(
                          label: const Text('Bold Text'),
                          selected: isBold,
                          selectedColor: AppColors.accent.withValues(alpha: 0.3),
                          checkmarkColor: AppColors.accent,
                          labelStyle: TextStyle(
                            color: isBold ? AppColors.accent : Colors.white70,
                            fontSize: 12,
                          ),
                          onSelected: (v) => setModalState(() => isBold = v),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),

                  // Apply button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.accent,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onPressed: () {
                        setState(() {
                          item.text = textController.text.trim();
                          item.textColor = selectedColor;
                          item.backgroundColor = selectedBg;
                          item.fontSize = fontSize;
                          item.isBold = isBold;
                          item.hasBackground = hasBg;
                        });
                        Navigator.pop(context);
                      },
                      child: const Text(
                        'Apply Annotation',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      ),
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

  Widget _presetChip(String label, VoidCallback onTap) {
    return ActionChip(
      label: Text(label, style: const TextStyle(fontSize: 11, color: Colors.white)),
      backgroundColor: AppColors.surface,
      side: const BorderSide(color: Colors.white12),
      onPressed: onTap,
    );
  }

  /// Burns all annotations onto the full resolution image and saves to gallery & app storage
  Future<void> _saveAndExport() async {
    if (_textItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please add at least one text annotation')),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final originalFile = File(widget.photo.imagePath);
      if (!await originalFile.exists()) {
        throw Exception('Original photo file not found');
      }

      final bytes = await originalFile.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final originalImage = frame.image;

      final originalWidth = originalImage.width.toDouble();

      // Calculation of scale relative to the on-screen rendered photo size
      final double displayW = _imageDisplaySize.width > 0 ? _imageDisplaySize.width : 360.0;
      final double scale = originalWidth / displayW;

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);

      // 1. Draw base photo
      canvas.drawImage(originalImage, Offset.zero, Paint());

      // 2. Burn each text item at scaled high-res coordinates
      for (final item in _textItems) {
        final double scaledX = (item.position.dx - _imageDisplayOffset.dx).clamp(0.0, displayW) * scale;
        final double scaledY = (item.position.dy - _imageDisplayOffset.dy).clamp(0.0, _imageDisplaySize.height) * scale;
        final double scaledFontSize = item.fontSize * scale;

        // Build text layout
        final textStyle = ui.TextStyle(
          color: item.textColor,
          fontSize: scaledFontSize,
          fontWeight: item.isBold ? ui.FontWeight.bold : ui.FontWeight.normal,
        );

        final paragraphBuilder = ui.ParagraphBuilder(
          ui.ParagraphStyle(textAlign: TextAlign.left, fontSize: scaledFontSize),
        )
          ..pushStyle(textStyle)
          ..addText(item.text);

        final paragraph = paragraphBuilder.build()
          ..layout(ui.ParagraphConstraints(width: originalWidth - scaledX));

        final textW = paragraph.maxIntrinsicWidth;
        final textH = paragraph.height;

        // Draw background pill if enabled
        if (item.hasBackground) {
          final padH = 8.0 * scale;
          final padV = 5.0 * scale;
          final bgRect = RRect.fromRectAndRadius(
            Rect.fromLTWH(
              scaledX - padH,
              scaledY - padV,
              textW + (padH * 2),
              textH + (padV * 2),
            ),
            Radius.circular(6.0 * scale),
          );

          canvas.drawRRect(
            bgRect,
            Paint()..color = item.backgroundColor,
          );
        }

        // Draw text
        canvas.drawParagraph(paragraph, Offset(scaledX, scaledY));
      }

      final picture = recorder.endRecording();
      final stampedImage = await picture.toImage(
        originalImage.width,
        originalImage.height,
      );

      final byteData = await stampedImage.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) throw Exception('Image encoding failed');

      // Create new annotated file
      final photoDir = await _storageService.getPhotoDirectory();
      final timestamp = DateTime.now();
      final newFileName = 'Sidmax_Annotated_${timestamp.millisecondsSinceEpoch}.jpg';
      final newFilePath = p.join(photoDir.path, newFileName);
      final newFile = File(newFilePath);
      await newFile.writeAsBytes(byteData.buffer.asUint8List());

      // Save directly to device public gallery (DCIM / Pictures / SidmaxGeotag)
      final galleryResult = await _storageService.saveToDeviceGallery(
        newFilePath,
        fileName: newFileName,
      );

      // Save new PhotoData entry so it shows in app Gallery
      final newPhotoData = PhotoData(
        id: timestamp.millisecondsSinceEpoch.toString(),
        imagePath: newFilePath,
        latitude: widget.photo.latitude,
        longitude: widget.photo.longitude,
        altitude: widget.photo.altitude,
        address: widget.photo.address,
        city: widget.photo.city,
        country: widget.photo.country,
        timestamp: timestamp,
        stampTemplate: widget.photo.stampTemplate,
        mapType: widget.photo.mapType,
        companyName: widget.photo.companyName,
        temperature: widget.photo.temperature,
        weatherCondition: widget.photo.weatherCondition,
        windSpeed: widget.photo.windSpeed,
        windDirection: widget.photo.windDirection,
        humidity: widget.photo.humidity,
      );

      await _storageService.savePhotoData(newPhotoData);

      originalImage.dispose();
      stampedImage.dispose();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: AppColors.accentGreen, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    galleryResult != null
                        ? 'Annotated photo saved to Gallery & Storage!'
                        : 'Saved to app storage & gallery successfully!',
                  ),
                ),
              ],
            ),
            backgroundColor: AppColors.surface,
            duration: const Duration(seconds: 3),
          ),
        );
        Navigator.pop(context, newPhotoData);
      }
    } catch (e) {
      debugPrint('Save annotated photo error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving annotated photo: $e'),
            backgroundColor: AppColors.accentRed,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black.withValues(alpha: 0.8),
        elevation: 0,
        title: const Text(
          'Drag & Add Text',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        actions: [
          // Add Text Button
          IconButton(
            icon: const Icon(Icons.add_comment_outlined, color: AppColors.accent),
            tooltip: 'Add Text',
            onPressed: () => _addNewText(),
          ),

          // Save to Gallery Button
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: _isSaving
                ? const Center(
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.accent,
                      ),
                    ),
                  )
                : TextButton.icon(
                    onPressed: _saveAndExport,
                    icon: const Icon(Icons.save_alt, color: AppColors.accentGreen, size: 18),
                    label: const Text(
                      'SAVE',
                      style: TextStyle(
                        color: AppColors.accentGreen,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Helper instructions banner
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
            color: AppColors.surface,
            child: const Row(
              children: [
                Icon(Icons.touch_app_outlined, color: AppColors.accent, size: 16),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Drag text anywhere on photo. Tap to edit or delete.',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),

          // Main Canvas Viewport
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return Center(
                  child: AspectRatio(
                    aspectRatio: 3 / 4, // standard photo ratio
                    child: LayoutBuilder(
                      builder: (innerCtx, innerConstraints) {
                        _imageDisplaySize = Size(
                          innerConstraints.maxWidth,
                          innerConstraints.maxHeight,
                        );

                        return Stack(
                          clipBehavior: Clip.none,
                          children: [
                            // 1. Base photo
                            Positioned.fill(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: Image.file(
                                  File(widget.photo.imagePath),
                                  fit: BoxFit.cover,
                                ),
                              ),
                            ),

                            // 2. Render all draggable text items
                            for (final item in _textItems) _buildDraggableTextWidget(item),
                          ],
                        );
                      },
                    ),
                  ),
                );
              },
            ),
          ),

          // Bottom Quick Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            color: AppColors.cardBackground,
            child: SafeArea(
              top: false,
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.accent,
                        side: const BorderSide(color: AppColors.accent),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onPressed: () => _addNewText(),
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Add Text', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.accent,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onPressed: _saveAndExport,
                      icon: const Icon(Icons.check, size: 18),
                      label: const Text(
                        'Save to Gallery',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDraggableTextWidget(DraggableTextItem item) {
    final isSelected = _selectedItemId == item.id;

    return Positioned(
      left: item.position.dx,
      top: item.position.dy,
      child: GestureDetector(
        onPanUpdate: (details) {
          setState(() {
            final double maxX = (_imageDisplaySize.width - 60).clamp(0.0, 1000.0);
            final double maxY = (_imageDisplaySize.height - 30).clamp(0.0, 1000.0);
            item.position = Offset(
              (item.position.dx + details.delta.dx).clamp(0.0, maxX),
              (item.position.dy + details.delta.dy).clamp(0.0, maxY),
            );
          });
        },
        onTap: () {
          setState(() => _selectedItemId = item.id);
          _openEditModal(item);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: item.hasBackground ? item.backgroundColor : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: isSelected ? AppColors.accent : Colors.white24,
              width: isSelected ? 1.8 : 0.8,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: AppColors.accent.withValues(alpha: 0.4),
                      blurRadius: 8,
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                item.text,
                style: TextStyle(
                  color: item.textColor,
                  fontSize: item.fontSize,
                  fontWeight: item.isBold ? FontWeight.bold : FontWeight.normal,
                ),
              ),
              if (isSelected) ...[
                const SizedBox(width: 6),
                GestureDetector(
                  onTap: () {
                    setState(() {
                      _textItems.removeWhere((t) => t.id == item.id);
                      if (_selectedItemId == item.id) _selectedItemId = null;
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: const BoxDecoration(
                      color: AppColors.accentRed,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.close, size: 12, color: Colors.white),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
