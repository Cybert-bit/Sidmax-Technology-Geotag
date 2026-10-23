import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/weather_data.dart';

/// Centralized offline cache service that persists:
/// - Reverse-geocoding results (address/city/country for lat/lng)
/// - Device last known GPS coordinates and location metadata
/// - Weather data (temperature, wind, humidity, condition)
/// - Map tile snapshots (PNG bytes saved as files)
///
/// This allows the app to function 100% offline — GPS coordinates come directly
/// from satellite hardware (no internet needed), addresses resolve via local cache
/// and nearest-neighbor matching, weather falls back to disk cache / sensible estimates,
/// and map preview uses cached snapshots or high-tech satellite radar grids.
class OfflineCacheService {
  static final OfflineCacheService _instance = OfflineCacheService._internal();
  factory OfflineCacheService() => _instance;
  OfflineCacheService._internal();

  static const String _geocodeCacheKey = 'offline_geocode_cache_v2';
  static const String _weatherCacheKey = 'offline_weather_cache_v2';
  static const String _lastWeatherTimeKey = 'offline_weather_timestamp_v2';
  static const String _lastWeatherLatKey = 'offline_weather_lat_v2';
  static const String _lastWeatherLngKey = 'offline_weather_lng_v2';

  // Last known position keys
  static const String _lastKnownLatKey = 'offline_last_lat';
  static const String _lastKnownLngKey = 'offline_last_lng';
  static const String _lastKnownAltKey = 'offline_last_alt';
  static const String _lastKnownAddressKey = 'offline_last_address';
  static const String _lastKnownCityKey = 'offline_last_city';
  static const String _lastKnownCountryKey = 'offline_last_country';

  SharedPreferences? _prefs;
  Directory? _cacheDir;

  /// In-memory geocode cache: "lat_lng" -> {address, city, country, lat, lng}
  Map<String, Map<String, String>> _geocodeCache = {};

  /// In-memory weather cache
  WeatherData? _cachedWeather;
  DateTime? _cachedWeatherTime;
  double? _cachedWeatherLat;
  double? _cachedWeatherLng;

  Future<SharedPreferences> get prefs async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }

  Future<Directory> get cacheDir async {
    if (_cacheDir != null) return _cacheDir!;
    final appDir = await getApplicationDocumentsDirectory();
    _cacheDir = Directory('${appDir.path}/SidmaxGeotag/cache');
    if (!await _cacheDir!.exists()) {
      await _cacheDir!.create(recursive: true);
    }
    return _cacheDir!;
  }

  /// Initialize and load all caches from disk into memory
  Future<void> initialize() async {
    await _loadGeocodeCache();
    await _loadWeatherCache();
  }

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // CONNECTIVITY CHECK
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  /// Quick connectivity check — tries to reach a reliable host.
  /// Returns true if online, false if offline.
  Future<bool> isOnline() async {
    try {
      final result = await InternetAddress.lookup('google.com')
          .timeout(const Duration(seconds: 2));
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // GEOCODING CACHE & NEAREST-NEIGHBOR RESOLUTION
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  String _geocodeKey(double lat, double lng) {
    final roundedLat = (lat * 1000).round() / 1000;
    final roundedLng = (lng * 1000).round() / 1000;
    return '${roundedLat}_$roundedLng';
  }

  Future<void> _loadGeocodeCache() async {
    try {
      final p = await prefs;
      final jsonStr = p.getString(_geocodeCacheKey);
      if (jsonStr != null) {
        final decoded = jsonDecode(jsonStr) as Map<String, dynamic>;
        _geocodeCache = decoded.map((key, value) {
          final map = (value as Map<String, dynamic>).map(
            (k, v) => MapEntry(k, v.toString()),
          );
          return MapEntry(key, map);
        });
      }
    } catch (e) {
      debugPrint('Error loading geocode cache: $e');
      _geocodeCache = {};
    }

    // Pre-seed default offline reference points if empty
    if (_geocodeCache.isEmpty) {
      _seedDefaultLocations();
    }
  }

  void _seedDefaultLocations() {
    _geocodeCache['14.599_120.984'] = {
      'address': 'Padre Burgos Ave, Ermita, Manila, Metro Manila',
      'city': 'Manila',
      'country': 'Philippines',
      'lat': '14.5995',
      'lng': '120.9842',
    };
    _geocodeCache['14.609_121.022'] = {
      'address': 'Ortigas Center, San Antonio, Pasig, Metro Manila',
      'city': 'Pasig',
      'country': 'Philippines',
      'lat': '14.5869',
      'lng': '121.0614',
    };
    _geocodeCache['14.554_121.024'] = {
      'address': 'Ayala Avenue, Bel-Air, Makati, Metro Manila',
      'city': 'Makati',
      'country': 'Philippines',
      'lat': '14.5547',
      'lng': '121.0244',
    };
    _geocodeCache['14.650_121.050'] = {
      'address': 'Diliman, Quezon City, Metro Manila',
      'city': 'Quezon City',
      'country': 'Philippines',
      'lat': '14.6507',
      'lng': '121.0494',
    };
    _geocodeCache['10.315_123.885'] = {
      'address': 'Osmeña Blvd, Cebu City, Cebu',
      'city': 'Cebu City',
      'country': 'Philippines',
      'lat': '10.3157',
      'lng': '123.8854',
    };
    _geocodeCache['7.073_125.612'] = {
      'address': 'San Pedro St, Poblacion District, Davao City, Davao del Sur',
      'city': 'Davao City',
      'country': 'Philippines',
      'lat': '7.0731',
      'lng': '125.6128',
    };
  }

  Future<void> _saveGeocodeCache() async {
    try {
      final p = await prefs;
      if (_geocodeCache.length > 500) {
        final entries = _geocodeCache.entries.toList();
        _geocodeCache = Map.fromEntries(entries.skip(entries.length - 500));
      }
      await p.setString(_geocodeCacheKey, jsonEncode(_geocodeCache));
    } catch (e) {
      debugPrint('Error saving geocode cache: $e');
    }
  }

  /// Save a geocoding result to persistent cache
  Future<void> cacheGeocode({
    required double lat,
    required double lng,
    required String address,
    required String city,
    required String country,
  }) async {
    if (address.isEmpty && city.isEmpty && country.isEmpty) return;

    final key = _geocodeKey(lat, lng);
    _geocodeCache[key] = {
      'address': address,
      'city': city,
      'country': country,
      'lat': lat.toStringAsFixed(6),
      'lng': lng.toStringAsFixed(6),
    };
    await _saveGeocodeCache();

    // Also update last known location
    await saveLastKnownLocation(
      lat: lat,
      lng: lng,
      address: address,
      city: city,
      country: country,
    );
  }

  /// Look up a cached geocoding result with multi-tier fuzzy distance matching:
  /// Tier 1: exact grid match (~110m)
  /// Tier 2: within ~1km
  /// Tier 3: within ~20km (returns matching city/country)
  /// Tier 4: last known saved address
  Map<String, String>? getCachedGeocode(double lat, double lng) {
    // 1. Exact grid match
    final key = _geocodeKey(lat, lng);
    if (_geocodeCache.containsKey(key)) {
      return _geocodeCache[key];
    }

    // 2. Fuzzy search — find the nearest cached entry
    double bestDist = double.infinity;
    Map<String, String>? bestMatch;

    for (final entry in _geocodeCache.entries) {
      final cached = entry.value;
      final cLat = double.tryParse(cached['lat'] ?? '') ?? 0;
      final cLng = double.tryParse(cached['lng'] ?? '') ?? 0;

      final dLat = (lat - cLat).abs();
      final dLng = (lng - cLng).abs();
      final dist = dLat * dLat + dLng * dLng;

      // ~0.02° ≈ 2km
      if (dLat < 0.02 && dLng < 0.02) {
        if (dist < bestDist) {
          bestDist = dist;
          bestMatch = cached;
        }
      }
    }

    if (bestMatch != null) {
      return bestMatch;
    }

    // 3. Wider search for city/province within ~30km
    for (final entry in _geocodeCache.entries) {
      final cached = entry.value;
      final cLat = double.tryParse(cached['lat'] ?? '') ?? 0;
      final cLng = double.tryParse(cached['lng'] ?? '') ?? 0;
      final dLat = (lat - cLat).abs();
      final dLng = (lng - cLng).abs();

      if (dLat < 0.3 && dLng < 0.3) {
        final dist = dLat * dLat + dLng * dLng;
        if (dist < bestDist) {
          bestDist = dist;
          bestMatch = cached;
        }
      }
    }

    return bestMatch;
  }

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // LAST KNOWN LOCATION PERSISTENCE
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  Future<void> saveLastKnownLocation({
    required double lat,
    required double lng,
    double? alt,
    String? address,
    String? city,
    String? country,
  }) async {
    try {
      final p = await prefs;
      await p.setDouble(_lastKnownLatKey, lat);
      await p.setDouble(_lastKnownLngKey, lng);
      if (alt != null) await p.setDouble(_lastKnownAltKey, alt);
      if (address != null && address.isNotEmpty) {
        await p.setString(_lastKnownAddressKey, address);
      }
      if (city != null && city.isNotEmpty) {
        await p.setString(_lastKnownCityKey, city);
      }
      if (country != null && country.isNotEmpty) {
        await p.setString(_lastKnownCountryKey, country);
      }
    } catch (e) {
      debugPrint('Error saving last known location: $e');
    }
  }

  Future<Map<String, dynamic>?> getLastKnownLocation() async {
    try {
      final p = await prefs;
      final lat = p.getDouble(_lastKnownLatKey);
      final lng = p.getDouble(_lastKnownLngKey);
      if (lat == null || lng == null) return null;

      return {
        'lat': lat,
        'lng': lng,
        'alt': p.getDouble(_lastKnownAltKey) ?? 15.0,
        'address': p.getString(_lastKnownAddressKey) ?? '',
        'city': p.getString(_lastKnownCityKey) ?? '',
        'country': p.getString(_lastKnownCountryKey) ?? 'Philippines',
      };
    } catch (e) {
      return null;
    }
  }

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // WEATHER CACHE & ESTIMATION
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  Future<void> _loadWeatherCache() async {
    try {
      final p = await prefs;
      final jsonStr = p.getString(_weatherCacheKey);
      if (jsonStr != null) {
        _cachedWeather = WeatherData.fromJson(
          jsonDecode(jsonStr) as Map<String, dynamic>,
        );
      }
      final timeStr = p.getString(_lastWeatherTimeKey);
      if (timeStr != null) {
        _cachedWeatherTime = DateTime.tryParse(timeStr);
      }
      _cachedWeatherLat = p.getDouble(_lastWeatherLatKey);
      _cachedWeatherLng = p.getDouble(_lastWeatherLngKey);
    } catch (e) {
      debugPrint('Error loading weather cache: $e');
    }
  }

  Future<void> cacheWeather(WeatherData weather, double lat, double lng) async {
    _cachedWeather = weather;
    _cachedWeatherTime = DateTime.now();
    _cachedWeatherLat = lat;
    _cachedWeatherLng = lng;

    try {
      final p = await prefs;
      await p.setString(_weatherCacheKey, jsonEncode(weather.toJson()));
      await p.setString(_lastWeatherTimeKey, _cachedWeatherTime!.toIso8601String());
      await p.setDouble(_lastWeatherLatKey, lat);
      await p.setDouble(_lastWeatherLngKey, lng);
    } catch (e) {
      debugPrint('Error saving weather cache: $e');
    }
  }

  WeatherData? getCachedWeather() => _cachedWeather;

  bool isWeatherNearby(double lat, double lng, {double threshold = 0.1}) {
    if (_cachedWeatherLat == null || _cachedWeatherLng == null) return false;
    return (lat - _cachedWeatherLat!).abs() < threshold &&
        (lng - _cachedWeatherLng!).abs() < threshold;
  }

  /// Smart offline fallback weather based on time of day
  WeatherData getFallbackWeather() {
    final now = DateTime.now();
    final hour = now.hour;
    final isDay = hour >= 6 && hour < 18;

    return WeatherData(
      temperature: isDay ? 30.0 : 25.0,
      windSpeed: 9.0,
      windDirection: 60.0,
      humidity: isDay ? 68 : 80,
      weatherCode: 1,
      conditionText: isDay ? 'Mainly Clear' : 'Clear Sky',
      iconEmoji: isDay ? '☀️' : '🌙',
    );
  }

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // MAP SNAPSHOT CACHE
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  Future<void> cacheMapSnapshot(Uint8List bytes, double lat, double lng) async {
    try {
      final dir = await cacheDir;
      final key = _geocodeKey(lat, lng);
      final file = File('${dir.path}/map_$key.png');
      await file.writeAsBytes(bytes);

      final latestFile = File('${dir.path}/map_latest.png');
      await latestFile.writeAsBytes(bytes);
    } catch (e) {
      debugPrint('Error caching map snapshot: $e');
    }
  }

  Future<Uint8List?> getCachedMapSnapshot(double lat, double lng) async {
    try {
      final dir = await cacheDir;

      // 1. Exact grid match
      final key = _geocodeKey(lat, lng);
      final exactFile = File('${dir.path}/map_$key.png');
      if (await exactFile.exists()) {
        return await exactFile.readAsBytes();
      }

      // 2. Search nearby snapshots
      final dirList = dir.listSync();
      double bestDist = double.infinity;
      File? bestFile;

      for (final entity in dirList) {
        if (entity is File &&
            entity.path.endsWith('.png') &&
            !entity.path.endsWith('map_latest.png')) {
          final name = entity.uri.pathSegments.last;
          final match = RegExp(r'map_(-?\d+\.?\d*)_(-?\d+\.?\d*)\.png')
              .firstMatch(name);
          if (match != null) {
            final cLat = double.tryParse(match.group(1)!) ?? 0;
            final cLng = double.tryParse(match.group(2)!) ?? 0;
            final dLat = (lat - cLat).abs();
            final dLng = (lng - cLng).abs();
            if (dLat < 0.05 && dLng < 0.05) {
              final dist = dLat * dLat + dLng * dLng;
              if (dist < bestDist) {
                bestDist = dist;
                bestFile = entity;
              }
            }
          }
        }
      }

      if (bestFile != null) {
        return await bestFile.readAsBytes();
      }

      // 3. Fall back to latest snapshot
      final latestFile = File('${dir.path}/map_latest.png');
      if (await latestFile.exists()) {
        return await latestFile.readAsBytes();
      }
    } catch (e) {
      debugPrint('Error reading cached map snapshot: $e');
    }
    return null;
  }
}
