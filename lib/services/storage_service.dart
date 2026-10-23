import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/photo_data.dart';
import '../utils/constants.dart';

class StorageService {
  static final StorageService _instance = StorageService._internal();
  factory StorageService() => _instance;
  StorageService._internal();

  static const String _photosKey = 'saved_photos';
  static const String _templateKey = 'stamp_template';
  static const String _showCoordinatesKey = 'show_coordinates';
  static const String _showAddressKey = 'show_address';
  static const String _showDateKey = 'show_date';
  static const String _showAltitudeKey = 'show_altitude';
  static const String _showCompassKey = 'show_compass';
  static const String _dateFormatKey = 'date_format';

  // New keys for Sidmax Pro, Map type, Company branding & Gallery saving
  static const String _companyNameKey = 'company_name';
  static const String _companyLogoPathKey = 'company_logo_path';
  static const String _showCompanyBadgeKey = 'show_company_badge';
  static const String _mapTypeKey = 'map_type';
  static const String _showMapKey = 'show_map';
  static const String _saveToGalleryKey = 'save_to_gallery';
  static const String _stampPositionKey = 'stamp_position';
  static const String _showWeatherKey = 'show_weather';
  static const String _showWindKey = 'show_wind';
  static const String _showHumidityKey = 'show_humidity';
  static const String _tempUnitKey = 'temp_unit';
  static const String _windUnitKey = 'wind_unit';

  static const MethodChannel _galleryChannel =
      MethodChannel('com.example.flutter_application_1/gallery');

  SharedPreferences? _prefs;

  Future<SharedPreferences> get prefs async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }

  // ─── Photo Storage ───────────────────────────────────────────

  /// Get the app's photo directory
  Future<Directory> getPhotoDirectory() async {
    final appDir = await getApplicationDocumentsDirectory();
    final photoDir = Directory('${appDir.path}/SidmaxGeotag');
    if (!await photoDir.exists()) {
      await photoDir.create(recursive: true);
    }
    return photoDir;
  }

  /// Save a photo's metadata
  Future<void> savePhotoData(PhotoData photo) async {
    final p = await prefs;
    final photos = await getPhotos();
    photos.insert(0, photo); // newest first
    final jsonList = photos.map((e) => e.toJsonString()).toList();
    await p.setStringList(_photosKey, jsonList);
  }

  /// Get all saved photos
  Future<List<PhotoData>> getPhotos() async {
    final p = await prefs;
    final jsonList = p.getStringList(_photosKey) ?? [];
    return jsonList
        .map((e) {
          try {
            return PhotoData.fromJsonString(e);
          } catch (_) {
            return null;
          }
        })
        .whereType<PhotoData>()
        .toList();
  }

  /// Delete a photo (file + metadata)
  Future<void> deletePhoto(String photoId) async {
    final p = await prefs;
    final photos = await getPhotos();
    final photo = photos.where((e) => e.id == photoId).firstOrNull;

    // Delete file
    if (photo != null) {
      final file = File(photo.imagePath);
      if (await file.exists()) {
        await file.delete();
      }
    }

    // Remove from list
    photos.removeWhere((e) => e.id == photoId);
    final jsonList = photos.map((e) => e.toJsonString()).toList();
    await p.setStringList(_photosKey, jsonList);
  }

  /// Update an existing photo's metadata
  Future<void> updatePhotoData(PhotoData updatedPhoto) async {
    final p = await prefs;
    final photos = await getPhotos();
    final index = photos.indexWhere((e) => e.id == updatedPhoto.id);
    if (index != -1) {
      photos[index] = updatedPhoto;
    } else {
      photos.insert(0, updatedPhoto);
    }
    final jsonList = photos.map((e) => e.toJsonString()).toList();
    await p.setStringList(_photosKey, jsonList);
  }

  /// Save photo directly to device public gallery/photos (Pictures/SidmaxGeotag)
  Future<String?> saveToDeviceGallery(
    String filePath, {
    String? fileName,
    String? albumName,
  }) async {
    try {
      final result = await _galleryChannel.invokeMethod<String>(
        'saveImageToGallery',
        {
          'filePath': filePath,
          'fileName': fileName ?? 'SidmaxGeotag_${DateTime.now().millisecondsSinceEpoch}.jpg',
          'albumName': albumName ?? AppStrings.defaultAlbum,
        },
      );
      debugPrint('Photo saved to gallery: $result');
      return result;
    } catch (e) {
      debugPrint('Error saving to device gallery via channel: $e');
      return null;
    }
  }

  /// Open Google Maps in Live View, Street View, or Navigation
  Future<bool> openGoogleMapsLiveView(
    double lat,
    double lng, {
    String mode = 'liveView', // 'liveView', 'streetView', 'navigation'
  }) async {
    try {
      final result = await _galleryChannel.invokeMethod<bool>(
        'openGoogleMaps',
        {
          'latitude': lat,
          'longitude': lng,
          'mode': mode,
        },
      );
      return result ?? false;
    } catch (e) {
      debugPrint('Error launching Google Maps Live View: $e');
      return false;
    }
  }

  // ─── Settings ────────────────────────────────────────────────

  Future<StampTemplate> getStampTemplate() async {
    final p = await prefs;
    final index = p.getInt(_templateKey) ?? StampTemplate.sidmaxPro.index;
    return StampTemplate.values[index.clamp(0, StampTemplate.values.length - 1)];
  }

  Future<void> setStampTemplate(StampTemplate template) async {
    final p = await prefs;
    await p.setInt(_templateKey, template.index);
  }

  Future<bool> getShowCoordinates() async {
    final p = await prefs;
    return p.getBool(_showCoordinatesKey) ?? true;
  }

  Future<void> setShowCoordinates(bool value) async {
    final p = await prefs;
    await p.setBool(_showCoordinatesKey, value);
  }

  Future<bool> getShowAddress() async {
    final p = await prefs;
    return p.getBool(_showAddressKey) ?? true;
  }

  Future<void> setShowAddress(bool value) async {
    final p = await prefs;
    await p.setBool(_showAddressKey, value);
  }

  Future<bool> getShowDate() async {
    final p = await prefs;
    return p.getBool(_showDateKey) ?? true;
  }

  Future<void> setShowDate(bool value) async {
    final p = await prefs;
    await p.setBool(_showDateKey, value);
  }

  Future<bool> getShowAltitude() async {
    final p = await prefs;
    return p.getBool(_showAltitudeKey) ?? false;
  }

  Future<void> setShowAltitude(bool value) async {
    final p = await prefs;
    await p.setBool(_showAltitudeKey, value);
  }

  Future<bool> getShowCompass() async {
    final p = await prefs;
    return p.getBool(_showCompassKey) ?? true;
  }

  Future<void> setShowCompass(bool value) async {
    final p = await prefs;
    await p.setBool(_showCompassKey, value);
  }

  Future<String> getDateFormat() async {
    final p = await prefs;
    return p.getString(_dateFormatKey) ?? 'dd/MM/yyyy HH:mm';
  }

  Future<void> setDateFormat(String format) async {
    final p = await prefs;
    await p.setString(_dateFormatKey, format);
  }

  // ─── Company & Map Settings ──────────────────────────────────

  Future<String> getCompanyName() async {
    final p = await prefs;
    return p.getString(_companyNameKey) ?? AppStrings.defaultCompany;
  }

  Future<void> setCompanyName(String name) async {
    final p = await prefs;
    await p.setString(_companyNameKey, name);
  }

  Future<String?> getCompanyLogoPath() async {
    final p = await prefs;
    return p.getString(_companyLogoPathKey);
  }

  Future<void> setCompanyLogoPath(String? path) async {
    final p = await prefs;
    if (path == null || path.isEmpty) {
      await p.remove(_companyLogoPathKey);
    } else {
      await p.setString(_companyLogoPathKey, path);
    }
  }

  Future<bool> getShowCompanyBadge() async {
    final p = await prefs;
    return p.getBool(_showCompanyBadgeKey) ?? true;
  }

  Future<void> setShowCompanyBadge(bool value) async {
    final p = await prefs;
    await p.setBool(_showCompanyBadgeKey, value);
  }

  Future<AppMapType> getMapType() async {
    final p = await prefs;
    final val = p.getString(_mapTypeKey) ?? 'satellite';
    return AppMapTypeExt.fromString(val);
  }

  Future<void> setMapType(AppMapType mapType) async {
    final p = await prefs;
    await p.setString(_mapTypeKey, mapType.name);
  }

  Future<bool> getShowMap() async {
    final p = await prefs;
    return p.getBool(_showMapKey) ?? true;
  }

  Future<void> setShowMap(bool value) async {
    final p = await prefs;
    await p.setBool(_showMapKey, value);
  }

  Future<bool> getSaveToGallery() async {
    final p = await prefs;
    return p.getBool(_saveToGalleryKey) ?? true;
  }

  Future<void> setSaveToGallery(bool value) async {
    final p = await prefs;
    await p.setBool(_saveToGalleryKey, value);
  }

  Future<String> getStampPosition() async {
    final p = await prefs;
    return p.getString(_stampPositionKey) ?? 'bottom';
  }

  Future<void> setStampPosition(String position) async {
    final p = await prefs;
    await p.setString(_stampPositionKey, position);
  }

  // ─── Weather & Wind Settings ─────────────────────────────────

  Future<bool> getShowWeather() async {
    final p = await prefs;
    return p.getBool(_showWeatherKey) ?? true;
  }

  Future<void> setShowWeather(bool value) async {
    final p = await prefs;
    await p.setBool(_showWeatherKey, value);
  }

  Future<bool> getShowWind() async {
    final p = await prefs;
    return p.getBool(_showWindKey) ?? true;
  }

  Future<void> setShowWind(bool value) async {
    final p = await prefs;
    await p.setBool(_showWindKey, value);
  }

  Future<bool> getShowHumidity() async {
    final p = await prefs;
    return p.getBool(_showHumidityKey) ?? false;
  }

  Future<void> setShowHumidity(bool value) async {
    final p = await prefs;
    await p.setBool(_showHumidityKey, value);
  }

  Future<String> getTempUnit() async {
    final p = await prefs;
    return p.getString(_tempUnitKey) ?? 'C';
  }

  Future<String> getTemperatureUnit() => getTempUnit();

  Future<void> setTempUnit(String unit) async {
    final p = await prefs;
    await p.setString(_tempUnitKey, unit);
  }

  Future<String> getWindUnit() async {
    final p = await prefs;
    return p.getString(_windUnitKey) ?? 'km/h';
  }

  Future<String> getWindSpeedUnit() => getWindUnit();

  Future<void> setWindUnit(String unit) async {
    final p = await prefs;
    await p.setString(_windUnitKey, unit);
  }
}
