import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';

import 'offline_cache_service.dart';
import 'offline_geocoding_service.dart';

class LocationData {
  final double latitude;
  final double longitude;
  final double? altitude;
  final double? accuracy;
  final double? heading;
  final double? speed;
  final String address;
  final String city;
  final String country;
  final bool isOfflineCached; // true when address came from offline cache

  LocationData({
    required this.latitude,
    required this.longitude,
    this.altitude,
    this.accuracy,
    this.heading,
    this.speed,
    this.address = '',
    this.city = '',
    this.country = '',
    this.isOfflineCached = false,
  });

  String get formattedAccuracy =>
      accuracy != null ? '±${accuracy!.toStringAsFixed(1)}m' : 'High Accuracy';

  String get compassDirection {
    if (heading == null || heading! < 0) return 'N';
    const directions = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];
    final index = ((heading! + 22.5) % 360 / 45).floor();
    return directions[index % 8];
  }
}

class LocationService {
  static final LocationService _instance = LocationService._internal();

  factory LocationService() => _instance;

  LocationService._internal();

  final Geocoding _geocoding = Geocoding();
  final OfflineCacheService _offlineCache = OfflineCacheService();
  final OfflineGeocodingService _offlineGeocoding = OfflineGeocodingService();

  Position? _lastPosition;
  LocationData? _lastLocationData;

  Position? get lastPosition => _lastPosition;
  LocationData? get lastLocationData => _lastLocationData;

  /// Check and request location permissions
  Future<bool> checkPermission() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();

    if (!serviceEnabled) {
      return false;
    }

    LocationPermission permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();

      if (permission == LocationPermission.denied) {
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      return false;
    }

    return true;
  }

  /// Get current position — GPS hardware works 100% offline via satellites.
  /// Fast fallback pipeline ensures instant response even without internet.
  Future<Position?> getCurrentPosition() async {
    try {
      final hasPermission = await checkPermission();
      if (!hasPermission) {
        return _lastPosition;
      }

      // 1. Immediately grab cached hardware position if available (zero delay)
      final lastKnown = await Geolocator.getLastKnownPosition();
      if (lastKnown != null && _lastPosition == null) {
        _lastPosition = lastKnown;
      }

      // 2. Fetch fresh satellite fix with a 4-second timeout to avoid locking UI
      try {
        _lastPosition = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.best,
            distanceFilter: 2,
            timeLimit: Duration(seconds: 4),
          ),
        );
      } catch (timeoutOrError) {
        // Satellite lock taking time or offline — fallback to last known
        _lastPosition ??= lastKnown;
      }

      return _lastPosition;
    } catch (e) {
      return _lastPosition;
    }
  }

  /// Get full location data with reverse geocoding.
  /// When offline (no data/wifi), uses the persistent offline cache and
  /// nearest-neighbor geocoding to supply the full address, city, and country.
  Future<LocationData?> getLocationData() async {
    try {
      Position? position = await getCurrentPosition();

      // If hardware position is still null, check disk cache
      if (position == null) {
        if (_lastLocationData != null) return _lastLocationData;

        final diskLast = await _offlineCache.getLastKnownLocation();
        if (diskLast != null) {
          final dLat = diskLast['lat'] as double;
          final dLng = diskLast['lng'] as double;
          var addr = diskLast['address'] as String;
          var cty = diskLast['city'] as String;
          var ctry = diskLast['country'] as String;

          if (addr.isEmpty || cty.isEmpty || cty == 'Live GPS Fix') {
            final off = _offlineGeocoding.lookup(dLat, dLng);
            addr = off.address;
            cty = off.city;
            ctry = off.country;
          }

          _lastLocationData = LocationData(
            latitude: dLat,
            longitude: dLng,
            altitude: diskLast['alt'] as double?,
            accuracy: 5.0,
            address: addr,
            city: cty,
            country: ctry,
            isOfflineCached: true,
          );
          return _lastLocationData;
        }
        return null;
      }

      String address = '';
      String city = '';
      String country = '';
      bool isOfflineCached = false;

      // ── Step 1: Try online reverse geocoding first ──
      try {
        final placemarks = await _geocoding.placemarkFromCoordinates(
          position.latitude,
          position.longitude,
        );

        if (placemarks.isNotEmpty) {
          final place = placemarks.first;
          final parts = <String>[];

          if (place.street != null && place.street!.isNotEmpty) {
            parts.add(place.street!);
          }
          if (place.subLocality != null && place.subLocality!.isNotEmpty) {
            parts.add(place.subLocality!);
          }
          if (place.locality != null && place.locality!.isNotEmpty) {
            city = place.locality!;
            parts.add(place.locality!);
          }
          if (place.administrativeArea != null &&
              place.administrativeArea!.isNotEmpty) {
            parts.add(place.administrativeArea!);
          }
          if (place.country != null && place.country!.isNotEmpty) {
            country = place.country!;
            parts.add(place.country!);
          }

          address = parts.join(', ');

          // ✅ Cache the online result to disk for offline use
          if (address.isNotEmpty) {
            await _offlineCache.cacheGeocode(
              lat: position.latitude,
              lng: position.longitude,
              address: address,
              city: city,
              country: country,
            );
          }
        }
      } catch (_) {
        // Geocoding server unreachable (device is OFFLINE) — use local cache!
        debugPrint('Geocoding offline — retrieving from local cache');
      }

      // ── Step 2: Check persistent local cache ──
      if (address.isEmpty || city.isEmpty) {
        final cached = _offlineCache.getCachedGeocode(
          position.latitude,
          position.longitude,
        );

        if (cached != null) {
          address = cached['address'] ?? '';
          city = cached['city'] ?? '';
          country = cached['country'] ?? '';
          isOfflineCached = true;
        }
      }

      // ── Step 3: High-Accuracy Built-in Philippine Offline Geocoder ──
      // Always resolves real Barangay, District, Municipality, City, Province
      // even when 100% offline with zero data/wifi.
      if (address.isEmpty || city.isEmpty || city == 'Live GPS Fix') {
        final offlineGeo = _offlineGeocoding.lookup(
          position.latitude,
          position.longitude,
        );
        address = offlineGeo.address;
        city = offlineGeo.city;
        country = offlineGeo.country;
        isOfflineCached = true;

        // Auto-cache to disk for persistence
        await _offlineCache.cacheGeocode(
          lat: position.latitude,
          lng: position.longitude,
          address: address,
          city: city,
          country: country,
        );
      }

      _lastLocationData = LocationData(
        latitude: position.latitude,
        longitude: position.longitude,
        altitude: position.altitude,
        accuracy: position.accuracy,
        heading: position.heading,
        speed: position.speed,
        address: address,
        city: city,
        country: country.isNotEmpty ? country : 'Philippines',
        isOfflineCached: isOfflineCached,
      );

      // Save to last known disk storage
      await _offlineCache.saveLastKnownLocation(
        lat: position.latitude,
        lng: position.longitude,
        alt: position.altitude,
        address: address,
        city: city,
        country: country,
      );

      return _lastLocationData;
    } catch (e) {
      return _lastLocationData;
    }
  }

  /// Stream of position updates
  Stream<Position> getPositionStream() {
    return Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 2,
      ),
    );
  }
}
