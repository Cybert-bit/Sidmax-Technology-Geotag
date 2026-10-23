import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../models/photo_data.dart';
import '../services/storage_service.dart';
import '../utils/constants.dart';
import 'photo_annotate_screen.dart';

class PhotoDetailScreen extends StatefulWidget {
  final PhotoData photo;

  const PhotoDetailScreen({super.key, required this.photo});

  @override
  State<PhotoDetailScreen> createState() => _PhotoDetailScreenState();
}

class _PhotoDetailScreenState extends State<PhotoDetailScreen> {
  final StorageService _storageService = StorageService();
  late PhotoData _photo;
  int _imageKey = 0; // Key to force re-render when image file is updated

  @override
  void initState() {
    super.initState();
    _photo = widget.photo;
  }

  void _openTextAnnotator() async {
    final updated = await Navigator.push<PhotoData>(
      context,
      MaterialPageRoute(
        builder: (_) => PhotoAnnotateScreen(photo: _photo),
      ),
    );
    if (updated != null && mounted) {
      setState(() {
        _photo = updated;
        _imageKey++;
      });
    }
  }

  void _openGoogleMaps({String mode = 'liveView'}) {
    _storageService.openGoogleMapsLiveView(
      _photo.latitude,
      _photo.longitude,
      mode: mode,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: GestureDetector(
          onTap: () => Navigator.pop(context, _photo),
          child: Container(
            margin: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.55),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.arrow_back, color: Colors.white),
          ),
        ),
        actions: [
          // 1. Add Text / Draggable Annotations Button
          GestureDetector(
            onTap: _openTextAnnotator,
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.55),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.text_fields_rounded, color: AppColors.accentOrange, size: 20),
            ),
          ),


          // 3. Google Maps Live View / Street View Action
          GestureDetector(
            onTap: () => _openGoogleMaps(mode: 'liveView'),
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.55),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.explore, color: AppColors.accentGreen, size: 20),
            ),
          ),

          // 3. Save / Export to Phone Gallery
          GestureDetector(
            onTap: () async {
              final res = await _storageService.saveToDeviceGallery(
                _photo.imagePath,
                fileName: 'SidmaxGeotag_${_photo.id}.jpg',
              );
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      res != null
                          ? 'Saved to Gallery (Pictures/SidmaxGeotag)'
                          : 'Photo saved in device storage',
                    ),
                    backgroundColor: AppColors.surface,
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                );
              }
            },
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.55),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.file_download_outlined, color: Colors.white, size: 20),
            ),
          ),

          // 4. Delete photo
          GestureDetector(
            onTap: () => _deletePhoto(context),
            child: Container(
              margin: const EdgeInsets.all(8),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.55),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.delete_outline, color: AppColors.accentRed, size: 20),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Photo viewer
          Expanded(
            flex: 3,
            child: Hero(
              tag: 'photo_${_photo.id}',
              child: InteractiveViewer(
                child: Image.file(
                  File(_photo.imagePath),
                  key: ValueKey('image_${_photo.id}_$_imageKey'),
                  fit: BoxFit.contain,
                  width: double.infinity,
                  errorBuilder: (_, _, _) => const Center(
                    child: Icon(Icons.broken_image, color: AppColors.textMuted, size: 64),
                  ),
                ),
              ),
            ),
          ),

          // Details panel
          Expanded(
            flex: 2,
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: AppColors.primaryDark,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
                border: Border(
                  top: BorderSide(
                    color: AppColors.border.withValues(alpha: 0.5),
                  ),
                ),
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Handle bar
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: AppColors.textMuted,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Title & Action Chips
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Location Details',
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Row(
                          children: [
                            // Add Text button pill
                            GestureDetector(
                              onTap: _openTextAnnotator,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                                decoration: BoxDecoration(
                                  color: AppColors.accentOrange.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: AppColors.accentOrange),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.text_fields, color: AppColors.accentOrange, size: 12),
                                    SizedBox(width: 4),
                                    Text(
                                      'Add Text',
                                      style: TextStyle(
                                        color: AppColors.accentOrange,
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),

                            const SizedBox(width: 6),
                            // Map Type Pill
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: AppColors.accentGreen.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: AppColors.accentGreen.withValues(alpha: 0.3)),
                              ),
                              child: Text(
                                _photo.mapType.toUpperCase(),
                                style: const TextStyle(
                                  color: AppColors.accentGreen,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // Info cards
                    _infoTile(
                      Icons.location_on,
                      'Address',
                      _photo.address.isNotEmpty
                          ? _photo.address
                          : 'GPS Address acquired',
                      AppColors.accent,
                    ),
                    const SizedBox(height: 10),

                    // Coordinates row
                    Row(
                      children: [
                        Expanded(
                          child: _infoCard(
                            'Latitude',
                            _photo.latitude.toStringAsFixed(6),
                            Icons.north,
                            AppColors.accentGreen,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _infoCard(
                            'Longitude',
                            _photo.longitude.toStringAsFixed(6),
                            Icons.east,
                            AppColors.accentPurple,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // Altitude & Date row
                    Row(
                      children: [
                        if (_photo.altitude != null)
                          Expanded(
                            child: _infoCard(
                              'Altitude',
                              '${_photo.altitude!.toStringAsFixed(1)}m',
                              Icons.terrain,
                              AppColors.accentOrange,
                            ),
                          ),
                        if (_photo.altitude != null) const SizedBox(width: 10),
                        Expanded(
                          child: _infoCard(
                            'Date',
                            DateFormat('MMM dd, yyyy').format(_photo.timestamp),
                            Icons.calendar_today,
                            AppColors.accentPink,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    _infoTile(
                      Icons.access_time,
                      'Time',
                      DateFormat('hh:mm:ss a').format(_photo.timestamp),
                      AppColors.accent,
                    ),

                    if (_photo.weatherSummary.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      _infoTile(
                        Icons.cloud_outlined,
                        'Weather & Conditions',
                        _photo.weatherSummary,
                        Colors.orangeAccent,
                      ),
                    ],

                    const SizedBox(height: 16),

                    // Mini map with Live View / Street View Action
                    if (_photo.latitude != 0 && _photo.longitude != 0) ...[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Location on Map',
                            style: TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Row(
                            children: [
                              TextButton.icon(
                                onPressed: () => _openGoogleMaps(mode: 'streetView'),
                                icon: const Icon(Icons.streetview, size: 14, color: AppColors.accentOrange),
                                label: const Text('Street View', style: TextStyle(color: AppColors.accentOrange, fontSize: 11)),
                              ),
                              TextButton.icon(
                                onPressed: () => _openGoogleMaps(mode: 'liveView'),
                                icon: const Icon(Icons.explore, size: 14, color: AppColors.accentGreen),
                                label: const Text('Live View', style: TextStyle(color: AppColors.accentGreen, fontSize: 11)),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Container(
                        height: 170,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppColors.border),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: GoogleMap(
                          initialCameraPosition: CameraPosition(
                            target: LatLng(_photo.latitude, _photo.longitude),
                            zoom: 16,
                            tilt: 45, // 3D perspective tilt
                          ),
                          mapType: AppMapTypeExt.fromString(_photo.mapType).toGoogleMapType,
                          markers: {
                            Marker(
                              markerId: const MarkerId('photo_location'),
                              position: LatLng(_photo.latitude, _photo.longitude),
                              infoWindow: InfoWindow(
                                title: _photo.shortAddress,
                                snippet: _photo.formattedCoordinates,
                              ),
                            ),
                          },
                          buildingsEnabled: true,
                          zoomControlsEnabled: false,
                          mapToolbarEnabled: false,
                          myLocationButtonEnabled: false,
                          liteModeEnabled: false,
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoTile(IconData icon, String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(14),
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
                  label,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoCard(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 14),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w700,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }

  void _deletePhoto(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: const Text('Delete Photo', style: TextStyle(color: AppColors.textPrimary)),
        content: const Text(
          'Are you sure you want to delete this photo?',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: AppColors.accentRed)),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      await _storageService.deletePhoto(_photo.id);
      if (context.mounted) {
        Navigator.pop(context);
      }
    }
  }
}
