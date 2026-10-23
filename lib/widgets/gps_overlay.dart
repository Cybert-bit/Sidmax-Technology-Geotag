import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';
import '../services/location_service.dart';
import '../utils/constants.dart';
import 'offline_map_painter.dart';

/// Detects the device's physical orientation using accelerometer data.
/// Returns the angle in quarter turns (0, 1, 2, 3) that represents
/// how much the stamp should rotate to stay upright relative to the photo.
enum DeviceNaturalOrientation {
  portrait,       // 0° rotation
  landscapeLeft,  // 90° CCW (device rotated left, top is on left)
  portraitDown,   // 180°
  landscapeRight, // 90° CW (device rotated right, top is on right)
}

/// The GPS data overlay widget displayed on camera preview and on captured photos.
/// Matches the "Sidmax Technology" reference style with satellite mini-map,
/// large location title with flag, coordinates, date/time with timezone,
/// weather data, and branding badge.
///
/// KEY FEATURE: The stamp auto-rotates when device orientation changes
/// while the camera UI controls stay fixed. This is achieved through
/// a Transform.rotate wrapper that responds to device sensor data.
class GpsOverlay extends StatefulWidget {
  final LocationData? locationData;
  final StampTemplate template;
  final AppMapType mapType;
  final bool showCoordinates;
  final bool showAddress;
  final bool showDate;
  final bool showAltitude;
  final bool showCompass;
  final bool showMap;
  final bool showCompanyBadge;
  final String companyName;
  final String? companyLogoPath;
  final String dateFormat;
  final String? weatherSummary;
  final Uint8List? mapSnapshotBytes;
  final void Function(GoogleMapController controller)? onMapCreated;
  final VoidCallback? onMapTap;
  final bool isLandscape;
  final bool isOnline;

  const GpsOverlay({
    super.key,
    this.locationData,
    this.template = StampTemplate.sidmaxPro,
    this.mapType = AppMapType.satellite,
    this.showCoordinates = true,
    this.showAddress = true,
    this.showDate = true,
    this.showAltitude = false,
    this.showCompass = true,
    this.showMap = true,
    this.showCompanyBadge = true,
    this.companyName = AppStrings.defaultCompany,
    this.companyLogoPath,
    this.dateFormat = 'dd/MM/yyyy HH:mm',
    this.weatherSummary,
    this.mapSnapshotBytes,
    this.onMapCreated,
    this.onMapTap,
    this.isLandscape = false,
    this.isOnline = true,
  });

  @override
  State<GpsOverlay> createState() => _GpsOverlayState();
}

class _GpsOverlayState extends State<GpsOverlay> with SingleTickerProviderStateMixin {
  @override
  Widget build(BuildContext context) {
    switch (widget.template) {
      case StampTemplate.sidmaxPro:
        return _buildSidmaxProStamp(context);
      case StampTemplate.classic:
        return _buildClassicStamp(context);
      case StampTemplate.modern:
        return _buildModernStamp(context);
      case StampTemplate.minimal:
        return _buildMinimalStamp(context);
      case StampTemplate.explorer:
        return _buildExplorerStamp(context);
    }
  }

  // ─── Country flag helper ───────────────────────────────────
  String _getCountryFlag(String country) {
    final Map<String, String> countryFlags = {
      'Philippines': '🇵🇭',
      'United States': '🇺🇸',
      'Japan': '🇯🇵',
      'South Korea': '🇰🇷',
      'China': '🇨🇳',
      'India': '🇮🇳',
      'United Kingdom': '🇬🇧',
      'Australia': '🇦🇺',
      'Canada': '🇨🇦',
      'Germany': '🇩🇪',
      'France': '🇫🇷',
      'Italy': '🇮🇹',
      'Spain': '🇪🇸',
      'Brazil': '🇧🇷',
      'Mexico': '🇲🇽',
      'Indonesia': '🇮🇩',
      'Thailand': '🇹🇭',
      'Vietnam': '🇻🇳',
      'Malaysia': '🇲🇾',
      'Singapore': '🇸🇬',
      'Taiwan': '🇹🇼',
      'Hong Kong': '🇭🇰',
      'New Zealand': '🇳🇿',
      'Saudi Arabia': '🇸🇦',
      'UAE': '🇦🇪',
      'Russia': '🇷🇺',
      'Turkey': '🇹🇷',
      'Netherlands': '🇳🇱',
      'Sweden': '🇸🇪',
      'Norway': '🇳🇴',
      'Denmark': '🇩🇰',
      'Finland': '🇫🇮',
      'Switzerland': '🇨🇭',
      'Austria': '🇦🇹',
      'Belgium': '🇧🇪',
      'Portugal': '🇵🇹',
      'Poland': '🇵🇱',
      'Argentina': '🇦🇷',
      'Colombia': '🇨🇴',
      'Chile': '🇨🇱',
      'Peru': '🇵🇪',
      'Egypt': '🇪🇬',
      'South Africa': '🇿🇦',
      'Nigeria': '🇳🇬',
      'Kenya': '🇰🇪',
      'Pakistan': '🇵🇰',
      'Bangladesh': '🇧🇩',
      'Sri Lanka': '🇱🇰',
      'Nepal': '🇳🇵',
      'Myanmar': '🇲🇲',
      'Cambodia': '🇰🇭',
      'Laos': '🇱🇦',
    };
    return countryFlags[country] ?? '📍';
  }

  // ─── Sidmax Pro Template (Matching Reference Image 1:1) ────────
  Widget _buildSidmaxProStamp(BuildContext context) {
    final loc = widget.locationData;
    final String cityRegion = _getLocalityWithRegion(loc);
    final String flag = _getCountryFlag(loc?.country ?? '');
    final String fullAddress = loc != null && loc.address.isNotEmpty
        ? '📍 ${loc.address}'
        : '📍 Getting location address...';

    final String latStr = loc != null
        ? 'Lat ${loc.latitude.toStringAsFixed(4)}° ${loc.latitude >= 0 ? "N" : "S"}'
        : 'Lat --.----° N';
    final String longStr = loc != null
        ? 'Long ${loc.longitude.toStringAsFixed(4)}° ${loc.longitude >= 0 ? "E" : "W"}'
        : 'Long --.----° E';

    final now = DateTime.now();
    final String dateStr = DateFormat('dd/MM/yyyy').format(now);
    final String timeStr = DateFormat('HH:mm').format(now);
    final String dateTimeLine = '📅 $dateStr $timeStr';

    // Map thumbnail size
    final double mapSize = widget.isLandscape ? 104 : 112;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // ── Floating Pill Badge (Sidmax Technology) ──
          if (widget.showCompanyBadge)
            Padding(
              padding: const EdgeInsets.only(bottom: 6, right: 2),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.75),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.35),
                    width: 0.8,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (widget.companyLogoPath != null && widget.companyLogoPath!.isNotEmpty)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: Image.file(
                          File(widget.companyLogoPath!),
                          width: 14,
                          height: 14,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) => const Icon(
                            Icons.grid_view_rounded,
                            color: Colors.white,
                            size: 13,
                          ),
                        ),
                      )
                    else
                      Image.asset(
                        'assets/images/logo.png',
                        width: 14,
                        height: 14,
                        errorBuilder: (context, error, stackTrace) => const Icon(
                          Icons.grid_view_rounded,
                          color: Colors.white,
                          size: 13,
                        ),
                      ),
                    const SizedBox(width: 6),
                    Text(
                      widget.companyName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // ── Map and Info Card Row ──
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Left: Mini Map Box ──
                if (widget.showMap) ...[
                  GestureDetector(
                    onTap: widget.onMapTap,
                    child: Container(
                      width: mapSize,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.7),
                          width: 1,
                        ),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          if (widget.mapSnapshotBytes != null)
                            Image.memory(
                              widget.mapSnapshotBytes!,
                              fit: BoxFit.cover,
                            )
                          else if (loc != null) ...[
                            // High-precision Leaflet / OpenStreetMap offline vector map
                            LeafletOfflineMapWidget(
                              latitude: loc.latitude,
                              longitude: loc.longitude,
                              heading: loc.heading ?? 0.0,
                              isSatellite: widget.mapType == AppMapType.satellite,
                            ),
                            // Live GoogleMap on top (only renders when online to avoid grey blank box offline)
                            if (widget.isOnline)
                              GoogleMap(
                                initialCameraPosition: CameraPosition(
                                  target: LatLng(loc.latitude, loc.longitude),
                                  zoom: 15,
                                ),
                                mapType: widget.mapType.toGoogleMapType,
                                zoomControlsEnabled: false,
                                myLocationButtonEnabled: false,
                                compassEnabled: false,
                                rotateGesturesEnabled: false,
                                scrollGesturesEnabled: false,
                                tiltGesturesEnabled: false,
                                zoomGesturesEnabled: false,
                                mapToolbarEnabled: false,
                                onMapCreated: widget.onMapCreated,
                              ),
                          ] else
                            LeafletOfflineMapWidget(
                              latitude: 14.5995,
                              longitude: 120.9842,
                              heading: 0.0,
                              isSatellite: widget.mapType == AppMapType.satellite,
                            ),

                          // SAT badge top-right of map (exact match to reference photo!)
                          Positioned(
                            top: 4,
                            right: 4,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                              decoration: BoxDecoration(
                                color: widget.isOnline
                                    ? const Color(0xFF2E7D32)
                                    : const Color(0xFF1E88E5),
                                borderRadius: BorderRadius.circular(3),
                              ),
                              child: Text(
                                widget.isOnline ? _getMapTypeLabel() : '🛰️ SAT',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 8,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                          ),

                          // Center red Google pin marker
                          Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  decoration: const BoxDecoration(
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black54,
                                        blurRadius: 4,
                                        offset: Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: const Icon(
                                    Icons.location_on,
                                    color: Color(0xFFEA4335),
                                    size: 28,
                                  ),
                                ),
                                Container(
                                  width: 6,
                                  height: 3,
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.5),
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          // Google watermark bottom left
                          Positioned(
                            bottom: 4,
                            left: 5,
                            child: Text(
                              'Google',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.95),
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.3,
                                shadows: const [
                                  Shadow(
                                    color: Colors.black87,
                                    blurRadius: 3,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                ],

                // ── Right: Data Box ──
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.65),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.7),
                        width: 1,
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // City, Country title (bold white with flag)
                        Text(
                          '$cityRegion $flag',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            height: 1.2,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 3),

                        // Full address with pin emoji
                        if (widget.showAddress) ...[
                          Text(
                            fullAddress,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.9),
                              fontSize: 9.5,
                              height: 1.25,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 3),
                        ],

                        // Coordinates with colored dots
                        if (widget.showCoordinates) ...[
                          Row(
                            children: [
                              Container(
                                width: 6,
                                height: 6,
                                decoration: const BoxDecoration(
                                  color: Color(0xFFEA4335),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                latStr,
                                style: const TextStyle(
                                  color: Color(0xFF8AB4F8),
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '|',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.4),
                                  fontSize: 9.5,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                width: 6,
                                height: 6,
                                decoration: const BoxDecoration(
                                  color: Color(0xFF4285F4),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  longStr,
                                  style: const TextStyle(
                                    color: Color(0xFF8AB4F8),
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                        ],

                        // Date/Time
                        if (widget.showDate) ...[
                          Text(
                            dateTimeLine,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.85),
                              fontSize: 9.5,
                            ),
                          ),
                          const SizedBox(height: 2),
                        ],

                        // Weather & Wind
                        if (widget.weatherSummary != null && widget.weatherSummary!.isNotEmpty) ...[
                          Text(
                            '⛅ ${widget.weatherSummary}',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.85),
                              fontSize: 9.5,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
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

  /// Get the map type label text for the badge
  String _getMapTypeLabel() {
    switch (widget.mapType) {
      case AppMapType.satellite:
        return 'SAT';
      case AppMapType.normal:
        return 'MAP';
      case AppMapType.terrain:
        return 'TER';
      case AppMapType.hybrid:
        return 'HYB';
    }
  }

  String _getLocalityWithRegion(LocationData? loc) {
    if (loc == null) return 'Live GPS Location';
    final parts = <String>[];
    if (loc.city.isNotEmpty) parts.add(loc.city);

    // Try to extract the region/province from address
    if (loc.address.isNotEmpty) {
      final addressParts = loc.address.split(',').map((s) => s.trim()).toList();
      // Add region info (usually 2nd to last before country)
      if (addressParts.length >= 3) {
        final region = addressParts[addressParts.length - 2];
        if (region.isNotEmpty && region != loc.city && region != loc.country) {
          parts.add(region);
        }
      }
    }

    if (loc.country.isNotEmpty) parts.add(loc.country);
    if (parts.isNotEmpty) return parts.join(', ');

    if (loc.address.isNotEmpty) {
      final sub = loc.address.split(',');
      if (sub.isNotEmpty) return sub.first.trim();
    }
    return 'Live GPS Location';
  }


  // ─── Classic Template ──────────────────────────────────────
  Widget _buildClassicStamp(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.accent.withValues(alpha: 0.5),
          width: 1,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.location_on, color: AppColors.accent, size: 16),
              const SizedBox(width: 6),
              Text(
                widget.companyName,
                style: const TextStyle(
                  color: AppColors.accent,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (widget.showCoordinates && widget.locationData != null) ...[
            _stampRow(
              Icons.my_location,
              _formatCoordinates(widget.locationData!.latitude, widget.locationData!.longitude),
            ),
            const SizedBox(height: 4),
          ],
          if (widget.showAddress && widget.locationData != null && widget.locationData!.address.isNotEmpty) ...[
            _stampRow(Icons.place, widget.locationData!.address, maxLines: 2),
            const SizedBox(height: 4),
          ],
          if (widget.showAltitude && widget.locationData?.altitude != null) ...[
            _stampRow(
              Icons.terrain,
              'Alt: ${widget.locationData!.altitude!.toStringAsFixed(1)}m',
            ),
            const SizedBox(height: 4),
          ],
          if (widget.showDate) ...[
            _stampRow(
              Icons.access_time,
              DateFormat(widget.dateFormat).format(DateTime.now()),
            ),
          ],
          if (widget.weatherSummary != null && widget.weatherSummary!.isNotEmpty) ...[
            const SizedBox(height: 4),
            _stampRow(
              Icons.cloud_outlined,
              widget.weatherSummary!,
            ),
          ],
        ],
      ),
    );
  }

  // ─── Modern Template ───────────────────────────────────────
  Widget _buildModernStamp(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.black.withValues(alpha: 0.7),
            Colors.black.withValues(alpha: 0.5),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.15),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.accentPurple.withValues(alpha: 0.2),
            blurRadius: 20,
            spreadRadius: -5,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              gradient: AppColors.primaryGradient,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.gps_fixed, color: Colors.white, size: 13),
                const SizedBox(width: 5),
                Text(
                  widget.companyName.toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          if (widget.showCoordinates && widget.locationData != null) ...[
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _modernCoordChip(
                  'LAT',
                  widget.locationData!.latitude.toStringAsFixed(6),
                  AppColors.accent,
                ),
                const SizedBox(width: 8),
                _modernCoordChip(
                  'LNG',
                  widget.locationData!.longitude.toStringAsFixed(6),
                  AppColors.accentPurple,
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
          if (widget.showAddress && widget.locationData != null && widget.locationData!.address.isNotEmpty) ...[
            Text(
              '📍 ${widget.locationData!.address}',
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 11,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 6),
          ],
          if (widget.showDate)
            Text(
              '🕐 ${DateFormat(widget.dateFormat).format(DateTime.now())}',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
                fontSize: 10,
              ),
            ),
          if (widget.weatherSummary != null && widget.weatherSummary!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.cloud_outlined, color: Colors.orangeAccent, size: 12),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    widget.weatherSummary!,
                    style: const TextStyle(
                      color: Colors.orangeAccent,
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _modernCoordChip(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 8,
              fontWeight: FontWeight.bold,
              letterSpacing: 1,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }

  // ─── Minimal Template ──────────────────────────────────────
  Widget _buildMinimalStamp(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.showCoordinates && widget.locationData != null)
            Text(
              _formatCoordinates(widget.locationData!.latitude, widget.locationData!.longitude),
              style: const TextStyle(
                color: Colors.black87,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                fontFamily: 'monospace',
              ),
            ),
          if (widget.showAddress && widget.locationData != null && widget.locationData!.address.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              widget.locationData!.address,
              style: const TextStyle(
                color: Colors.black54,
                fontSize: 10,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          if (widget.showDate) ...[
            const SizedBox(height: 2),
            Text(
              DateFormat(widget.dateFormat).format(DateTime.now()),
              style: const TextStyle(
                color: Colors.black45,
                fontSize: 9,
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ─── Explorer Template ─────────────────────────────────────
  Widget _buildExplorerStamp(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.accentGreen.withValues(alpha: 0.6),
          width: 1.5,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.explore, color: AppColors.accentGreen, size: 18),
              const SizedBox(width: 6),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'EXPLORER',
                    style: TextStyle(
                      color: AppColors.accentGreen,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2,
                    ),
                  ),
                  if (widget.showDate)
                    Text(
                      DateFormat(widget.dateFormat).format(DateTime.now()),
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 9,
                      ),
                    ),
                ],
              ),
            ],
          ),
          const Divider(
            color: AppColors.accentGreen,
            height: 16,
          ),
          if (widget.showCoordinates && widget.locationData != null) ...[
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.gps_fixed, color: AppColors.accentGreen, size: 12),
                const SizedBox(width: 6),
                Text(
                  _formatCoordinates(widget.locationData!.latitude, widget.locationData!.longitude),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
          ],
          if (widget.showAltitude && widget.locationData?.altitude != null) ...[
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.terrain, color: AppColors.accentOrange, size: 12),
                const SizedBox(width: 6),
                Text(
                  '${widget.locationData!.altitude!.toStringAsFixed(1)}m',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 11,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
          ],
          if (widget.showAddress && widget.locationData != null && widget.locationData!.address.isNotEmpty)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.map, color: AppColors.accentOrange, size: 12),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    widget.locationData!.address,
                    style: const TextStyle(
                      color: Colors.white60,
                      fontSize: 10,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  // ─── Helpers ───────────────────────────────────────────────
  Widget _stampRow(IconData icon, String text, {int maxLines = 1}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: Colors.white70, size: 13),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              height: 1.3,
            ),
            maxLines: maxLines,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  String _formatCoordinates(double lat, double lng) {
    final latDir = lat >= 0 ? 'N' : 'S';
    final lngDir = lng >= 0 ? 'E' : 'W';
    return '${lat.abs().toStringAsFixed(6)}° $latDir, ${lng.abs().toStringAsFixed(6)}° $lngDir';
  }
}
