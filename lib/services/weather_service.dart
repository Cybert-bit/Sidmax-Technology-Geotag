import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../models/weather_data.dart';
import 'offline_cache_service.dart';

class WeatherService {
  static final WeatherService _instance = WeatherService._internal();
  factory WeatherService() => _instance;
  WeatherService._internal();

  final OfflineCacheService _offlineCache = OfflineCacheService();

  WeatherData? _cachedWeather;
  DateTime? _lastFetchTime;
  double? _lastLat;
  double? _lastLng;

  WeatherData? get cachedWeather => _cachedWeather;

  /// Whether the latest data was served from offline cache
  bool _isOfflineCached = false;
  bool get isOfflineCached => _isOfflineCached;

  Future<WeatherData> fetchWeather(double lat, double lng) => getWeather(lat, lng);

  /// Fetch live weather for given latitude and longitude.
  /// Falls back to persistent offline cache when no internet is available.
  Future<WeatherData> getWeather(double lat, double lng) async {
    // If in-memory cached within last 10 minutes and within ~5km, return cache
    if (_cachedWeather != null &&
        _lastFetchTime != null &&
        DateTime.now().difference(_lastFetchTime!).inMinutes < 10 &&
        _lastLat != null &&
        _lastLng != null &&
        (lat - _lastLat!).abs() < 0.05 &&
        (lng - _lastLng!).abs() < 0.05) {
      return _cachedWeather!;
    }

    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 4);

      final uri = Uri.parse(
        'https://api.open-meteo.com/v1/forecast'
        '?latitude=${lat.toStringAsFixed(4)}'
        '&longitude=${lng.toStringAsFixed(4)}'
        '&current=temperature_2m,relative_humidity_2m,weather_code,wind_speed_10m,wind_direction_10m',
      );

      final request = await client.getUrl(uri);
      final response = await request.close().timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final responseBody = await response.transform(utf8.decoder).join();
        final data = jsonDecode(responseBody) as Map<String, dynamic>;
        final current = data['current'] as Map<String, dynamic>?;

        if (current != null) {
          final temp = (current['temperature_2m'] as num?)?.toDouble() ?? 28.0;
          final wind = (current['wind_speed_10m'] as num?)?.toDouble() ?? 10.0;
          final windDir = (current['wind_direction_10m'] as num?)?.toDouble() ?? 0.0;
          final humidity = (current['relative_humidity_2m'] as num?)?.toInt() ?? 70;
          final code = (current['weather_code'] as num?)?.toInt() ?? 0;

          final condition = _mapWmoCode(code);

          final weather = WeatherData(
            temperature: temp,
            windSpeed: wind,
            windDirection: windDir,
            humidity: humidity,
            weatherCode: code,
            conditionText: condition.$1,
            iconEmoji: condition.$2,
          );

          _cachedWeather = weather;
          _lastFetchTime = DateTime.now();
          _lastLat = lat;
          _lastLng = lng;
          _isOfflineCached = false;

          // ✅ Persist to disk for offline use
          await _offlineCache.cacheWeather(weather, lat, lng);

          return weather;
        }
      }
    } catch (e) {
      debugPrint('Weather fetch notice: $e (checking offline cache)');
    }

    // ─── Offline Fallback Pipeline ───
    // 1. In-memory cache
    if (_cachedWeather != null) {
      _isOfflineCached = true;
      return _cachedWeather!;
    }

    // 2. Persistent disk cache (survives app restart)
    final diskCached = _offlineCache.getCachedWeather();
    if (diskCached != null) {
      _cachedWeather = diskCached;
      _isOfflineCached = true;
      return diskCached;
    }

    // 3. Smart time-of-day fallback
    _isOfflineCached = true;
    return _offlineCache.getFallbackWeather();
  }

  (String, String) _mapWmoCode(int code) {
    final hour = DateTime.now().hour;
    final isNight = hour < 6 || hour >= 18;

    switch (code) {
      case 0:
        return isNight ? ('Clear Sky', '🌙') : ('Clear Sky', '☀️');
      case 1:
        return isNight ? ('Mainly Clear', '🌙') : ('Mainly Clear', '🌤️');
      case 2:
        return ('Partly Cloudy', '⛅');
      case 3:
        return ('Overcast', '☁️');
      case 45:
      case 48:
        return ('Foggy', '🌫️');
      case 51:
      case 53:
      case 55:
        return ('Drizzle', '🌦️');
      case 56:
      case 57:
        return ('Freezing Drizzle', '🌧️');
      case 61:
      case 63:
      case 65:
        return ('Rain', '🌧️');
      case 66:
      case 67:
        return ('Freezing Rain', '🌧️');
      case 71:
      case 73:
      case 75:
      case 77:
        return ('Snow', '❄️');
      case 80:
      case 81:
      case 82:
        return ('Rain Showers', '🌦️');
      case 85:
      case 86:
        return ('Snow Showers', '🌨️');
      case 95:
        return ('Thunderstorm', '⛈️');
      case 96:
      case 99:
        return ('Thunderstorm w/ Hail', '⛈️');
      default:
        return isNight ? ('Clear', '🌙') : ('Sunny', '☀️');
    }
  }
}
