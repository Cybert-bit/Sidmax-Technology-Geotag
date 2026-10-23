import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import '../models/photo_data.dart';
import '../services/storage_service.dart';
import '../utils/constants.dart';
import '../widgets/photo_card.dart';
import 'photo_detail_screen.dart';

class GalleryScreen extends StatefulWidget {
  const GalleryScreen({super.key});

  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen> {
  final StorageService _storageService = StorageService();
  List<PhotoData> _photos = [];
  bool _isLoading = true;
  bool _isGridView = true;
  bool _isSelectionMode = false;
  final Set<String> _selectedIds = {};
  String _sortBy = 'newest'; // newest, oldest, location

  @override
  void initState() {
    super.initState();
    _loadPhotos();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadPhotos();
  }

  Future<void> _loadPhotos() async {
    final photos = await _storageService.getPhotos();
    if (mounted) {
      setState(() {
        _photos = photos;
        _isLoading = false;
        _sortPhotos();
      });
    }
  }

  void _sortPhotos() {
    switch (_sortBy) {
      case 'oldest':
        _photos.sort((a, b) => a.timestamp.compareTo(b.timestamp));
        break;
      case 'location':
        _photos.sort((a, b) => a.shortAddress.compareTo(b.shortAddress));
        break;
      case 'newest':
      default:
        _photos.sort((a, b) => b.timestamp.compareTo(a.timestamp));
        break;
    }
  }

  void _toggleSelection(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
        if (_selectedIds.isEmpty) _isSelectionMode = false;
      } else {
        _selectedIds.add(id);
      }
    });
  }

  void _selectAll() {
    setState(() {
      if (_selectedIds.length == _photos.length) {
        _selectedIds.clear();
        _isSelectionMode = false;
      } else {
        _selectedIds.addAll(_photos.map((p) => p.id));
      }
    });
  }

  Future<void> _deleteSelected() async {
    if (_selectedIds.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: const Text(
          'Delete Photos',
          style: TextStyle(color: AppColors.textPrimary),
        ),
        content: Text(
          'Are you sure you want to delete ${_selectedIds.length} photo${_selectedIds.length > 1 ? 's' : ''}?',
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Delete',
              style: TextStyle(color: AppColors.accentRed),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      for (final id in _selectedIds) {
        await _storageService.deletePhoto(id);
      }
      _selectedIds.clear();
      _isSelectionMode = false;
      _loadPhotos();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.delete_outline, color: AppColors.accentRed, size: 18),
                SizedBox(width: 8),
                Text('Photos deleted successfully'),
              ],
            ),
            backgroundColor: AppColors.surface,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    }
  }

  Future<void> _deletePhoto(PhotoData photo) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: const Text(
          'Delete Photo',
          style: TextStyle(color: AppColors.textPrimary),
        ),
        content: const Text(
          'Are you sure you want to delete this photo?',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Delete',
              style: TextStyle(color: AppColors.accentRed),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _storageService.deletePhoto(photo.id);
      _loadPhotos();
    }
  }

  Future<void> _saveSinglePhoto(PhotoData photo) async {
    final res = await _storageService.saveToDeviceGallery(
      photo.imagePath,
      fileName: 'SidmaxGeotag_${photo.id}.jpg',
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(res != null
            ? 'Saved to Gallery'
            : 'Error saving to Gallery'),
        backgroundColor: AppColors.surface,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Future<void> _exportSelectedToGallery() async {
    if (_selectedIds.isEmpty) return;
    int saved = 0;
    for (final id in _selectedIds) {
      final photo = _photos.firstWhere((p) => p.id == id);
      final result = await _storageService.saveToDeviceGallery(
        photo.imagePath,
        fileName: 'SidmaxGeotag_${photo.id}.jpg',
      );
      if (result != null) saved++;
    }
    _selectedIds.clear();
    _isSelectionMode = false;
    setState(() {});

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.download_done, color: AppColors.accentGreen, size: 18),
              const SizedBox(width: 8),
              Text('$saved photo${saved > 1 ? 's' : ''} saved to Gallery'),
            ],
          ),
          backgroundColor: AppColors.surface,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primaryDark,
      appBar: AppBar(
        title: _isSelectionMode
            ? Text('${_selectedIds.length} selected')
            : const Text('Gallery'),
        leading: _isSelectionMode
            ? IconButton(
                icon: const Icon(Icons.close),
                onPressed: () {
                  setState(() {
                    _isSelectionMode = false;
                    _selectedIds.clear();
                  });
                },
              )
            : null,
        actions: [
          if (_isSelectionMode) ...[
            // Select All
            IconButton(
              icon: Icon(
                _selectedIds.length == _photos.length
                    ? Icons.deselect
                    : Icons.select_all,
                color: AppColors.accent,
              ),
              onPressed: _selectAll,
              tooltip: 'Select All',
            ),
            // Export selected
            IconButton(
              icon: const Icon(Icons.file_download_outlined, color: AppColors.accentGreen),
              onPressed: _exportSelectedToGallery,
              tooltip: 'Save to Gallery',
            ),
            // Delete selected
            IconButton(
              icon: const Icon(Icons.delete_outline, color: AppColors.accentRed),
              onPressed: _deleteSelected,
              tooltip: 'Delete Selected',
            ),
          ] else ...[
            if (_photos.isNotEmpty) ...[
              // Photo count badge
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.accent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${_photos.length} photos',
                      style: const TextStyle(
                        color: AppColors.accent,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
              // Sort button
              PopupMenuButton<String>(
                icon: const Icon(Icons.sort, size: 20),
                color: AppColors.surface,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                onSelected: (value) {
                  setState(() {
                    _sortBy = value;
                    _sortPhotos();
                  });
                },
                itemBuilder: (context) => [
                  _buildSortItem('newest', 'Newest First', Icons.arrow_downward),
                  _buildSortItem('oldest', 'Oldest First', Icons.arrow_upward),
                  _buildSortItem('location', 'By Location', Icons.location_on),
                ],
              ),
              // Grid/List toggle
              IconButton(
                icon: Icon(
                  _isGridView ? Icons.view_list : Icons.grid_view,
                  size: 20,
                ),
                onPressed: () => setState(() => _isGridView = !_isGridView),
              ),
            ],
            IconButton(
              icon: const Icon(Icons.refresh, size: 20),
              onPressed: _loadPhotos,
            ),
          ],
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.accent),
            )
          : _photos.isEmpty
              ? _buildEmptyState()
              : RefreshIndicator(
                  onRefresh: _loadPhotos,
                  color: AppColors.accent,
                  child: Column(
                    children: [
                      // Stats bar
                      if (_photos.isNotEmpty && !_isSelectionMode)
                        _buildStatsBar(),
                      // Photo grid or list
                      Expanded(
                        child: _isGridView
                            ? _buildGridView()
                            : _buildListView(),
                      ),
                    ],
                  ),
                ),
    );
  }

  Widget _buildStatsBar() {
    final uniqueLocations = _photos.map((p) => p.shortAddress).toSet().length;
    final latestDate = _photos.isNotEmpty
        ? DateFormat('MMM dd, yyyy').format(_photos.first.timestamp)
        : '';
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          _statChip(Icons.photo_library, '${_photos.length}', 'Photos'),
          const SizedBox(width: 12),
          Container(width: 1, height: 24, color: AppColors.border),
          const SizedBox(width: 12),
          _statChip(Icons.place, '$uniqueLocations', 'Locations'),
          const SizedBox(width: 12),
          Container(width: 1, height: 24, color: AppColors.border),
          const SizedBox(width: 12),
          Expanded(
            child: _statChip(Icons.calendar_today, latestDate, 'Latest'),
          ),
        ],
      ),
    );
  }

  Widget _statChip(IconData icon, String value, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: AppColors.accent, size: 14),
        const SizedBox(width: 6),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              value,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              label,
              style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 9,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildGridView() {
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 0.75,
      ),
      itemCount: _photos.length,
      itemBuilder: (context, index) {
        final photo = _photos[index];
        final isSelected = _selectedIds.contains(photo.id);
        return GestureDetector(
          onLongPress: () {
            setState(() {
              _isSelectionMode = true;
              _selectedIds.add(photo.id);
            });
          },
          onTap: () {
            if (_isSelectionMode) {
              _toggleSelection(photo.id);
            } else {
              _openPhoto(photo);
            }
          },
          child: Stack(
            children: [
              PhotoCard(
                photo: photo,
                onTap: () {
                  if (_isSelectionMode) {
                    _toggleSelection(photo.id);
                  } else {
                    _openPhoto(photo);
                  }
                },
                onLongPress: () {
                  setState(() {
                    _isSelectionMode = true;
                    _selectedIds.add(photo.id);
                  });
                },
              ),
              if (_isSelectionMode)
                Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppColors.accent
                          : Colors.black.withValues(alpha: 0.5),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isSelected ? AppColors.accent : Colors.white70,
                        width: 2,
                      ),
                    ),
                    child: isSelected
                        ? const Icon(Icons.check, color: Colors.white, size: 14)
                        : null,
                  ),
                ),
            ],
          ),
        ).animate(delay: (index * 50).ms).fadeIn().scale(
              begin: const Offset(0.95, 0.95),
              end: const Offset(1.0, 1.0),
              duration: 300.ms,
            );
      },
    );
  }

  Widget _buildListView() {
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _photos.length,
      itemBuilder: (context, index) {
        final photo = _photos[index];
        final isSelected = _selectedIds.contains(photo.id);
        return GestureDetector(
          onLongPress: () {
            setState(() {
              _isSelectionMode = true;
              _selectedIds.add(photo.id);
            });
          },
          onTap: () {
            if (_isSelectionMode) {
              _toggleSelection(photo.id);
            } else {
              _openPhoto(photo);
            }
          },
          child: Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isSelected
                  ? AppColors.accent.withValues(alpha: 0.1)
                  : AppColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isSelected ? AppColors.accent : AppColors.border,
                width: isSelected ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: [
                if (_isSelectionMode)
                  Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppColors.accent
                            : Colors.transparent,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isSelected ? AppColors.accent : AppColors.textMuted,
                          width: 2,
                        ),
                      ),
                      child: isSelected
                          ? const Icon(Icons.check, color: Colors.white, size: 13)
                          : null,
                    ),
                  ),
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox(
                    width: 64,
                    height: 64,
                    child: File(photo.imagePath).existsSync()
                        ? Image.file(
                            File(photo.imagePath),
                            fit: BoxFit.cover,
                          )
                        : Container(
                            color: AppColors.surfaceLight,
                            child: const Icon(Icons.image, color: AppColors.textMuted),
                          ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        photo.shortAddress,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Icon(Icons.gps_fixed, size: 10, color: AppColors.accent.withValues(alpha: 0.7)),
                          const SizedBox(width: 4),
                          Text(
                            photo.formattedCoordinates,
                            style: const TextStyle(
                              color: AppColors.accent,
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          const Icon(Icons.access_time, size: 10, color: AppColors.textMuted),
                          const SizedBox(width: 4),
                          Text(
                            photo.formattedDate,
                            style: const TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 10,
                            ),
                          ),
                          if (photo.weatherSummary.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            const Icon(Icons.cloud_outlined, size: 10, color: AppColors.textMuted),
                            const SizedBox(width: 3),
                            Expanded(
                              child: Text(
                                photo.weatherSummary,
                                style: const TextStyle(
                                  color: AppColors.textMuted,
                                  fontSize: 10,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                if (!_isSelectionMode)
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert, size: 18, color: AppColors.textMuted),
                    color: AppColors.surface,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    onSelected: (value) {
                      if (value == 'delete') {
                        _deletePhoto(photo);
                      } else if (value == 'save') {
                        _saveSinglePhoto(photo);
                      }
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                        value: 'save',
                        child: Row(
                          children: [
                            Icon(Icons.file_download, size: 16, color: AppColors.accentGreen),
                            SizedBox(width: 8),
                            Text('Save to Gallery', style: TextStyle(color: AppColors.textPrimary, fontSize: 13)),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(Icons.delete_outline, size: 16, color: AppColors.accentRed),
                            SizedBox(width: 8),
                            Text('Delete', style: TextStyle(color: AppColors.accentRed, fontSize: 13)),
                          ],
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ).animate(delay: (index * 40).ms).fadeIn().slideX(
              begin: 0.05,
              end: 0,
              duration: 250.ms,
            );
      },
    );
  }

  PopupMenuItem<String> _buildSortItem(String value, String label, IconData icon) {
    final isActive = _sortBy == value;
    return PopupMenuItem(
      value: value,
      child: Row(
        children: [
          Icon(icon, size: 16, color: isActive ? AppColors.accent : AppColors.textMuted),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: isActive ? AppColors.accent : AppColors.textPrimary,
              fontSize: 13,
              fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          if (isActive) ...[
            const Spacer(),
            const Icon(Icons.check, size: 14, color: AppColors.accent),
          ],
        ],
      ),
    );
  }

  void _openPhoto(PhotoData photo) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PhotoDetailScreen(photo: photo),
      ),
    ).then((_) => _loadPhotos());
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.accent.withValues(alpha: 0.08),
                  AppColors.accentPurple.withValues(alpha: 0.08),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              shape: BoxShape.circle,
              border: Border.all(
                color: AppColors.accent.withValues(alpha: 0.15),
                width: 2,
              ),
            ),
            child: const Icon(
              Icons.photo_library_outlined,
              color: AppColors.textMuted,
              size: 56,
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'No Photos Yet',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 20,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Take photos with the GPS Camera\nto see them here',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.accent.withValues(alpha: 0.3)),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.camera_alt, color: AppColors.accent, size: 16),
                SizedBox(width: 6),
                Text(
                  'Switch to Camera tab to start',
                  style: TextStyle(
                    color: AppColors.accent,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
