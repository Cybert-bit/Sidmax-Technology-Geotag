import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../models/photo_data.dart';
import '../services/location_service.dart';
import '../services/storage_service.dart';
import '../utils/constants.dart';
import '../widgets/offline_map_painter.dart';
import '../services/offline_cache_service.dart';
import 'photo_detail_screen.dart';

class MapScreen extends StatefulWidget {
  final double? initialLat;
  final double? initialLng;
  final bool startInLiveView;

  const MapScreen({
    super.key,
    this.initialLat,
    this.initialLng,
    this.startInLiveView = false,
  });

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final StorageService _storageService = StorageService();
  final LocationService _locationService = LocationService();
  final OfflineCacheService _offlineCache = OfflineCacheService();

  List<PhotoData> _photos = [];
  Set<Marker> _markers = {};
  bool _isLoading = true;
  bool _isOnline = true;
  GoogleMapController? _mapController;

  // Live View & Map modes
  bool _is3DLiveView = false;
  MapType _currentMapType = MapType.satellite;
  bool _trafficEnabled = false;

  // Real-time tracking
  StreamSubscription<Position>? _positionStreamSub;
  Position? _currentPosition;
  LocationData? _currentLocationData;
  PhotoData? _selectedPhoto;

  static const CameraPosition _defaultPosition = CameraPosition(
    target: LatLng(14.5995, 120.9842),
    zoom: 14,
  );

  @override
  void initState() {
    super.initState();
    _is3DLiveView = widget.startInLiveView;
    _initMapScreen();
  }

  Future<void> _initMapScreen() async {
    final online = await _offlineCache.isOnline();
    if (mounted) {
      setState(() => _isOnline = online);
    }
    await _loadPhotos();
    await _fetchCurrentLocation();
    _startLivePositionStream();
  }

  Future<void> _fetchCurrentLocation() async {
    final pos = await _locationService.getCurrentPosition();
    final locData = await _locationService.getLocationData();
    if (mounted) {
      setState(() {
        _currentPosition = pos;
        _currentLocationData = locData;
      });

      if (_is3DLiveView && pos != null) {
        _animateTo3DLiveView(pos.latitude, pos.longitude, pos.heading);
      }
    }
  }

  void _startLivePositionStream() {
    _positionStreamSub = _locationService.getPositionStream().listen((pos) {
      if (!mounted) return;
      setState(() {
        _currentPosition = pos;
      });

      if (_is3DLiveView && _mapController != null) {
        _animateTo3DLiveView(pos.latitude, pos.longitude, pos.heading);
      }
    });
  }

  Future<void> _loadPhotos() async {
    final photos = await _storageService.getPhotos();
    final markers = <Marker>{};

    for (final photo in photos) {
      if (photo.latitude == 0 && photo.longitude == 0) continue;
      markers.add(
        Marker(
          markerId: MarkerId(photo.id),
          position: LatLng(photo.latitude, photo.longitude),
          infoWindow: InfoWindow(
            title: photo.shortAddress,
            snippet: photo.formattedCoordinates,
          ),
          onTap: () {
            setState(() {
              _selectedPhoto = photo;
            });
            _mapController?.animateCamera(
              CameraUpdate.newCameraPosition(
                CameraPosition(
                  target: LatLng(photo.latitude, photo.longitude),
                  zoom: 17,
                  tilt: _is3DLiveView ? 55 : 0,
                  bearing: 0,
                ),
              ),
            );
          },
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueCyan,
          ),
        ),
      );
    }

    if (mounted) {
      setState(() {
        _photos = photos;
        _markers = markers;
        _isLoading = false;
      });

      if (widget.initialLat != null && widget.initialLng != null) {
        _animateToLocation(widget.initialLat!, widget.initialLng!, zoom: 17);
      } else if (markers.isNotEmpty && _mapController != null) {
        _fitMarkers();
      }
    }
  }

  void _animateToLocation(double lat, double lng, {double zoom = 16}) {
    _mapController?.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: LatLng(lat, lng),
          zoom: zoom,
          tilt: _is3DLiveView ? 58 : 0,
          bearing: _currentPosition?.heading ?? 0,
        ),
      ),
    );
  }

  void _animateTo3DLiveView(double lat, double lng, double heading) {
    _mapController?.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: LatLng(lat, lng),
          zoom: 18.5,
          tilt: 58.0, // 2026 3D Perspective tilt
          bearing: heading >= 0 ? heading : 0,
        ),
      ),
    );
  }

  void _toggle3DLiveView() {
    setState(() {
      _is3DLiveView = !_is3DLiveView;
    });

    final targetLat = _selectedPhoto?.latitude ??
        _currentPosition?.latitude ??
        _defaultPosition.target.latitude;
    final targetLng = _selectedPhoto?.longitude ??
        _currentPosition?.longitude ??
        _defaultPosition.target.longitude;
    final heading = _currentPosition?.heading ?? 0;

    if (_is3DLiveView) {
      _animateTo3DLiveView(targetLat, targetLng, heading);
      _showSnack('2026 3D Live View Activated (58° Tilt)');
    } else {
      _mapController?.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: LatLng(targetLat, targetLng),
            zoom: 16,
            tilt: 0,
            bearing: 0,
          ),
        ),
      );
      _showSnack('2D Map Overview Mode');
    }
  }

  void _fitMarkers() {
    if (_markers.isEmpty || _mapController == null) return;

    if (_markers.length == 1) {
      _mapController!.animateCamera(
        CameraUpdate.newLatLngZoom(_markers.first.position, 16),
      );
      return;
    }

    double minLat = 90, maxLat = -90, minLng = 180, maxLng = -180;
    for (final marker in _markers) {
      final pos = marker.position;
      if (pos.latitude < minLat) minLat = pos.latitude;
      if (pos.latitude > maxLat) maxLat = pos.latitude;
      if (pos.longitude < minLng) minLng = pos.longitude;
      if (pos.longitude > maxLng) maxLng = pos.longitude;
    }

    _mapController!.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(minLat, minLng),
          northeast: LatLng(maxLat, maxLng),
        ),
        60,
      ),
    );
  }

  void _centerMyLocation() {
    if (_currentPosition != null) {
      if (_is3DLiveView) {
        _animateTo3DLiveView(
          _currentPosition!.latitude,
          _currentPosition!.longitude,
          _currentPosition!.heading,
        );
      } else {
        _animateToLocation(
          _currentPosition!.latitude,
          _currentPosition!.longitude,
          zoom: 17,
        );
      }
      setState(() => _selectedPhoto = null);
    } else {
      _fetchCurrentLocation();
      _showSnack('Acquiring high precision GPS fix...');
    }
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        duration: const Duration(seconds: 2),
        backgroundColor: AppColors.surface,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  void _openLiveViewLauncher({double? targetLat, double? targetLng}) {
    final lat = targetLat ??
        _selectedPhoto?.latitude ??
        _currentPosition?.latitude;
    final lng = targetLng ??
        _selectedPhoto?.longitude ??
        _currentPosition?.longitude;

    if (lat == null || lng == null) {
      _showSnack('Waiting for GPS coordinates...');
      return;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        gradient: AppColors.accentGradient,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.view_in_ar,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Google Maps 2026 Live View',
                            style: TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${lat.toStringAsFixed(6)}°, ${lng.toStringAsFixed(6)}°',
                            style: const TextStyle(
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
                const SizedBox(height: 20),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.accent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.streetview, color: AppColors.accent),
                  ),
                  title: const Text(
                    'Street View / 360° Panorama',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: const Text(
                    'Launch instant 360° ground level view',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                  ),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: AppColors.textMuted),
                  onTap: () {
                    Navigator.pop(ctx);
                    _storageService.openGoogleMapsLiveView(lat, lng, mode: 'streetView');
                  },
                ),
                const Divider(color: AppColors.border, height: 16),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.accentGreen.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.travel_explore, color: AppColors.accentGreen),
                  ),
                  title: const Text(
                    'High-Resolution Satellite App View',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: const Text(
                    'Open exact coordinates in Google Maps App',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                  ),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: AppColors.textMuted),
                  onTap: () {
                    Navigator.pop(ctx);
                    _storageService.openGoogleMapsLiveView(lat, lng, mode: 'liveView');
                  },
                ),
                const Divider(color: AppColors.border, height: 16),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.blueAccent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.navigation, color: Colors.blueAccent),
                  ),
                  title: const Text(
                    'Turn-by-Turn GPS Navigation',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: const Text(
                    'Route and navigate directly to this spot',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                  ),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: AppColors.textMuted),
                  onTap: () {
                    Navigator.pop(ctx);
                    _storageService.openGoogleMapsLiveView(lat, lng, mode: 'navigation');
                  },
                ),
                const SizedBox(height: 10),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showLayersSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Map Layer & Style (Google 2026)',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildLayerOption(
                          label: 'Satellite',
                          icon: Icons.satellite_alt,
                          type: MapType.satellite,
                          selected: _currentMapType == MapType.satellite,
                          onTap: () {
                            setState(() => _currentMapType = MapType.satellite);
                            setSheetState(() {});
                          },
                        ),
                        _buildLayerOption(
                          label: 'Default',
                          icon: Icons.map,
                          type: MapType.normal,
                          selected: _currentMapType == MapType.normal,
                          onTap: () {
                            setState(() => _currentMapType = MapType.normal);
                            setSheetState(() {});
                          },
                        ),
                        _buildLayerOption(
                          label: 'Terrain',
                          icon: Icons.terrain,
                          type: MapType.terrain,
                          selected: _currentMapType == MapType.terrain,
                          onTap: () {
                            setState(() => _currentMapType = MapType.terrain);
                            setSheetState(() {});
                          },
                        ),
                        _buildLayerOption(
                          label: 'Hybrid',
                          icon: Icons.layers,
                          type: MapType.hybrid,
                          selected: _currentMapType == MapType.hybrid,
                          onTap: () {
                            setState(() => _currentMapType = MapType.hybrid);
                            setSheetState(() {});
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    const Divider(color: AppColors.border),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text(
                        'Live Traffic Layer',
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: const Text(
                        'Real-time traffic congestion flow',
                        style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                      ),
                      value: _trafficEnabled,
                      activeThumbColor: AppColors.accent,
                      activeTrackColor: AppColors.accent.withValues(alpha: 0.5),
                      onChanged: (val) {
                        setState(() => _trafficEnabled = val);
                        setSheetState(() {});
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildLayerOption({
    required String label,
    required IconData icon,
    required MapType type,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: selected
                  ? AppColors.accent.withValues(alpha: 0.2)
                  : AppColors.surfaceLight,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: selected ? AppColors.accent : AppColors.border,
                width: selected ? 2 : 1,
              ),
            ),
            child: Icon(
              icon,
              color: selected ? AppColors.accent : Colors.white70,
              size: 26,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(
              color: selected ? AppColors.accent : AppColors.textSecondary,
              fontSize: 12,
              fontWeight: selected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primaryDark,
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.accent),
            )
          : Stack(
              children: [
                // 1. Leaflet Offline Vector Map (seamless offline fallback)
                Positioned.fill(
                  child: LeafletOfflineMapWidget(
                    latitude: widget.initialLat ??
                        _currentPosition?.latitude ??
                        _defaultPosition.target.latitude,
                    longitude: widget.initialLng ??
                        _currentPosition?.longitude ??
                        _defaultPosition.target.longitude,
                    heading: _currentPosition?.heading ?? 0.0,
                    isSatellite: _currentMapType == MapType.satellite ||
                        _currentMapType == MapType.hybrid,
                  ),
                ),

                // 2. Google Map (renders on top when network tiles are available)
                if (_isOnline)
                  GoogleMap(
                    initialCameraPosition: _defaultPosition,
                    markers: _markers,
                    onMapCreated: (controller) {
                      _mapController = controller;
                      if (widget.initialLat != null && widget.initialLng != null) {
                        _animateToLocation(widget.initialLat!, widget.initialLng!, zoom: 17);
                      } else if (_markers.isNotEmpty) {
                        Future.delayed(const Duration(milliseconds: 300), () {
                          _fitMarkers();
                        });
                      } else if (_currentPosition != null) {
                        _centerMyLocation();
                      }
                    },
                    myLocationEnabled: true,
                    myLocationButtonEnabled: false,
                    zoomControlsEnabled: false,
                    mapToolbarEnabled: false,
                    compassEnabled: true,
                    trafficEnabled: _trafficEnabled,
                    buildingsEnabled: true,
                    mapType: _currentMapType,
                    onTap: (_) {
                      if (_selectedPhoto != null) {
                        setState(() => _selectedPhoto = null);
                      }
                    },
                  ),

                // 2b. Offline satellite GPS status banner when offline
                if (!_isOnline)
                  Positioned(
                    top: 60,
                    left: 14,
                    right: 14,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xE6161B22),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF1E88E5), width: 1),
                        boxShadow: const [
                          BoxShadow(color: Colors.black45, blurRadius: 6, offset: Offset(0, 2)),
                        ],
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.satellite_alt, color: Color(0xFF64B5F6), size: 18),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Offline Mode: Hardware GPS & Satellite vector map active',
                              style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                // 2. Top Header Bar
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      child: Row(
                        children: [
                          _buildGlassCircleBtn(
                            icon: Icons.arrow_back,
                            onTap: () => Navigator.pop(context),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.75),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: _is3DLiveView
                                      ? AppColors.accent.withValues(alpha: 0.7)
                                      : AppColors.border,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.4),
                                    blurRadius: 10,
                                  ),
                                ],
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    _is3DLiveView ? Icons.view_in_ar : Icons.map,
                                    color: _is3DLiveView
                                        ? AppColors.accent
                                        : Colors.white,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          _is3DLiveView
                                              ? '2026 LIVE 3D VIEW'
                                              : 'PHOTO MAP OVERVIEW',
                                          style: TextStyle(
                                            color: _is3DLiveView
                                                ? AppColors.accent
                                                : Colors.white,
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                            letterSpacing: 0.5,
                                          ),
                                        ),
                                        Text(
                                          '${_photos.length} geotagged photo${_photos.length == 1 ? '' : 's'}',
                                          style: const TextStyle(
                                            color: AppColors.textMuted,
                                            fontSize: 10,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (_is3DLiveView)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: AppColors.accentGreen,
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: const Text(
                                        '60° TILT',
                                        style: TextStyle(
                                          color: Colors.black,
                                          fontSize: 9,
                                          fontWeight: FontWeight.bold,
                                        ),
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
                ),

                // 3. Right Floating Action Buttons
                Positioned(
                  top: 90,
                  right: 14,
                  child: Column(
                    children: [
                      // 3D Perspective Toggle Button
                      _buildFloatingActionBtn(
                        icon: _is3DLiveView ? Icons.layers : Icons.view_in_ar,
                        label: _is3DLiveView ? '2D' : '3D Live',
                        isActive: _is3DLiveView,
                        onTap: _toggle3DLiveView,
                      ),
                      const SizedBox(height: 10),

                      // Layer Switcher
                      _buildFloatingActionBtn(
                        icon: Icons.layers_outlined,
                        label: 'Layers',
                        onTap: _showLayersSheet,
                      ),
                      const SizedBox(height: 10),

                      // Street View / Live View launcher
                      _buildFloatingActionBtn(
                        icon: Icons.streetview,
                        label: 'Live View',
                        color: AppColors.accent,
                        onTap: () => _openLiveViewLauncher(),
                      ),
                      const SizedBox(height: 10),

                      // Center on user location
                      _buildFloatingActionBtn(
                        icon: Icons.my_location,
                        label: 'GPS',
                        onTap: _centerMyLocation,
                      ),
                      if (_markers.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        _buildFloatingActionBtn(
                          icon: Icons.center_focus_strong,
                          label: 'Fit All',
                          onTap: _fitMarkers,
                        ),
                      ],
                    ],
                  ),
                ),

                // 4. Bottom Information Panel (Selected Photo or Live Telemetry HUD)
                Positioned(
                  bottom: 16,
                  left: 14,
                  right: 14,
                  child: _selectedPhoto != null
                      ? _buildSelectedPhotoCard(_selectedPhoto!)
                      : _buildLiveTelemetryCard(),
                ),
              ],
            ),
    );
  }

  Widget _buildGlassCircleBtn({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.75),
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.4),
              blurRadius: 8,
            ),
          ],
        ),
        child: Icon(icon, color: Colors.white, size: 20),
      ),
    );
  }

  Widget _buildFloatingActionBtn({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool isActive = false,
    Color? color,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: isActive
              ? AppColors.accent.withValues(alpha: 0.9)
              : Colors.black.withValues(alpha: 0.75),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isActive ? Colors.white : AppColors.border,
            width: isActive ? 1.5 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.4),
              blurRadius: 8,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: isActive ? Colors.black : (color ?? Colors.white),
              size: 20,
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                color: isActive ? Colors.black : Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLiveTelemetryCard() {
    final pos = _currentPosition;
    final loc = _currentLocationData;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Live coordinates & Accuracy status
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.gps_fixed,
                  color: AppColors.accent,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      pos != null
                          ? '${pos.latitude.toStringAsFixed(6)}°, ${pos.longitude.toStringAsFixed(6)}°'
                          : 'Acquiring GPS Fix...',
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.3,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      loc?.address.isNotEmpty == true
                          ? loc!.address
                          : (pos != null ? 'High Precision GPS Mode' : 'Locating device...'),
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 11,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (pos != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.accentGreen.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppColors.accentGreen.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Text(
                    '±${pos.accuracy.toStringAsFixed(1)}m',
                    style: const TextStyle(
                      color: AppColors.accentGreen,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),

          // Telemetry badges (Altitude, Speed, Heading)
          if (pos != null)
            Row(
              children: [
                _buildTelemetryBadge(
                  icon: Icons.height,
                  label: '${pos.altitude.toStringAsFixed(0)} m',
                  sub: 'Altitude',
                ),
                const SizedBox(width: 8),
                _buildTelemetryBadge(
                  icon: Icons.speed,
                  label: '${(pos.speed * 3.6).toStringAsFixed(1)} km/h',
                  sub: 'Speed',
                ),
                const SizedBox(width: 8),
                _buildTelemetryBadge(
                  icon: Icons.navigation_outlined,
                  label: '${pos.heading.toStringAsFixed(0)}° ${_getHeadingDir(pos.heading)}',
                  sub: 'Heading',
                ),
              ],
            ),
          const SizedBox(height: 14),

          // Google Maps 2026 Live View Launch Button
          SizedBox(
            width: double.infinity,
            height: 44,
            child: ElevatedButton.icon(
              onPressed: () => _openLiveViewLauncher(),
              icon: const Icon(Icons.streetview, size: 20),
              label: const Text(
                'Open in Google Maps Live View',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.3,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: Colors.black,
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTelemetryBadge({
    required IconData icon,
    required String label,
    required String sub,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Icon(icon, size: 14, color: AppColors.accent),
            const SizedBox(width: 5),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    sub,
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 9,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSelectedPhotoCard(PhotoData photo) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.6)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              // Photo Thumbnail
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: 54,
                  height: 54,
                  child: File(photo.imagePath).existsSync()
                      ? Image.file(File(photo.imagePath), fit: BoxFit.cover)
                      : Container(
                          color: AppColors.surfaceLight,
                          child: const Icon(Icons.image, color: Colors.white54),
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
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      photo.formattedCoordinates,
                      style: const TextStyle(
                        color: AppColors.accent,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      photo.formattedDate,
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: AppColors.textMuted, size: 20),
                onPressed: () => setState(() => _selectedPhoto = null),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => PhotoDetailScreen(photo: photo),
                      ),
                    ).then((_) => _loadPhotos());
                  },
                  icon: const Icon(Icons.photo_outlined, size: 16),
                  label: const Text('View Photo Details'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.accent,
                    side: const BorderSide(color: AppColors.accent),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _openLiveViewLauncher(
                    targetLat: photo.latitude,
                    targetLng: photo.longitude,
                  ),
                  icon: const Icon(Icons.streetview, size: 16),
                  label: const Text('Live View'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accentGreen,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _getHeadingDir(double heading) {
    if (heading < 0) return '';
    const directions = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];
    final index = ((heading + 22.5) % 360 / 45).floor();
    return directions[index % 8];
  }

  @override
  void dispose() {
    _positionStreamSub?.cancel();
    _mapController?.dispose();
    super.dispose();
  }
}
