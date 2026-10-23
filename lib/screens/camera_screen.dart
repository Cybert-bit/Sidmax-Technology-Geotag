import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:permission_handler/permission_handler.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../models/photo_data.dart';
import '../models/weather_data.dart';
import '../services/location_service.dart';
import '../services/offline_cache_service.dart';
import '../services/storage_service.dart';
import '../services/weather_service.dart';
import '../utils/constants.dart';
import '../widgets/gps_overlay.dart';
import '../widgets/offline_map_painter.dart';
import 'gallery_screen.dart';
import 'map_screen.dart';

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => CameraScreenState();
}

class CameraScreenState extends State<CameraScreen>
    with WidgetsBindingObserver {
  CameraController? _cameraController;
  List<CameraDescription> _cameras = [];
  bool _isInitialized = false;
  bool _isCapturing = false;
  bool _hasPermission = false;
  int _selectedCameraIndex = 0;
  FlashMode _flashMode = FlashMode.auto;
  bool _isSwitchingCamera = false;

  final LocationService _locationService = LocationService();
  final StorageService _storageService = StorageService();
  final WeatherService _weatherService = WeatherService();
  final OfflineCacheService _offlineCache = OfflineCacheService();
  LocationData? _currentLocation;
  WeatherData? _currentWeather;
  Timer? _locationTimer;

  // Google Map Controller for mini map snapshot
  GoogleMapController? _miniMapController;

  // Stamp settings
  StampTemplate _stampTemplate = StampTemplate.sidmaxPro;
  AppMapType _mapType = AppMapType.satellite;
  String _companyName = AppStrings.defaultCompany;
  String? _companyLogoPath;
  bool _showCompanyBadge = true;
  bool _showMap = true;
  bool _showCoordinates = true;
  bool _showAddress = true;
  bool _showDate = true;
  bool _showAltitude = false;
  bool _showCompass = true;
  bool _showWeather = true;
  bool _showWind = true;
  bool _showHumidity = false;
  String _tempUnit = 'celsius';
  String _speedUnit = 'kmh';
  String _dateFormat = 'dd/MM/yyyy HH:mm';
  bool _saveToGallery = true;
  String _stampPosition = 'bottom';
  bool _isOnline = true;

  // Last photo for thumbnail preview
  PhotoData? _lastPhoto;

  // ── Device Orientation via Accelerometer ──
  // This tracks the physical device orientation using sensors,
  // independent of the screen orientation lock.
  // The stamp rotates based on this while UI controls stay fixed.
  StreamSubscription<AccelerometerEvent>? _accelerometerSubscription;
  int _deviceQuarterTurns = 0;       // 0=portrait, 1=landscapeRight, 2=upsideDown, 3=landscapeLeft
  bool _isDeviceLandscape = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeAll();
    _startAccelerometerListener();
  }

  /// Listen to accelerometer to detect physical device orientation.
  /// This lets us rotate the stamp even when the UI orientation is locked.
  void _startAccelerometerListener() {
    _accelerometerSubscription = accelerometerEventStream(
      samplingPeriod: const Duration(milliseconds: 150),
    ).listen((AccelerometerEvent event) {
      final x = event.x;
      final y = event.y;
      final z = event.z;

      // When the phone is laying flat on a table (z dominates), retain current orientation
      if (z.abs() > 8.5 && x.abs() < 2.5 && y.abs() < 2.5) {
        return;
      }

      int newQuarterTurns;
      bool newIsLandscape;

      // Hysteresis threshold to prevent flickering around 45°
      const hysteresis = 1.2;
      final currentIsHorizontal = (_deviceQuarterTurns == 1 || _deviceQuarterTurns == 3);

      final isHorizontal = currentIsHorizontal
          ? (x.abs() > (y.abs() - hysteresis))
          : (x.abs() > (y.abs() + hysteresis));

      if (!isHorizontal) {
        // Vertical (Portrait normal or upside down)
        if (y > 0) {
          newQuarterTurns = 0; // Portrait
          newIsLandscape = false;
        } else {
          newQuarterTurns = 2; // Upside down
          newIsLandscape = false;
        }
      } else {
        // Horizontal (Landscape Left or Landscape Right)
        if (x > 0) {
          newQuarterTurns = 3; // Landscape left (top of device is on left)
          newIsLandscape = true;
        } else {
          newQuarterTurns = 1; // Landscape right (top of device is on right)
          newIsLandscape = true;
        }
      }

      if (newQuarterTurns != _deviceQuarterTurns && mounted) {
        setState(() {
          _deviceQuarterTurns = newQuarterTurns;
          _isDeviceLandscape = newIsLandscape;
        });
      }
    });
  }

  Future<void> _initializeAll() async {
    // Pre-populate with disk cached location immediately (zero delay when offline)
    final cachedLoc = await _offlineCache.getLastKnownLocation();
    if (cachedLoc != null && _currentLocation == null && mounted) {
      final dLat = cachedLoc['lat'] as double;
      final dLng = cachedLoc['lng'] as double;
      final off = _locationService.lastLocationData ??
          LocationData(
            latitude: dLat,
            longitude: dLng,
            altitude: cachedLoc['alt'] as double?,
            accuracy: 5.0,
            address: cachedLoc['address'] as String? ?? '',
            city: cachedLoc['city'] as String? ?? '',
            country: cachedLoc['country'] as String? ?? 'Philippines',
            isOfflineCached: true,
          );
      setState(() => _currentLocation = off);
    }

    await _requestPermissions();
    if (_hasPermission) {
      await _initializeCamera();
      _startLocationUpdates();
      await loadSettings();
      _loadLastPhoto();
    }
  }

  Future<void> _requestPermissions() async {
    final cameraStatus = await Permission.camera.request();
    final locationStatus = await Permission.locationWhenInUse.request();

    // Storage permissions for saving to gallery on Android <= 12
    if (Platform.isAndroid) {
      await Permission.storage.request();
    }

    setState(() {
      _hasPermission = cameraStatus.isGranted && locationStatus.isGranted;
    });
  }

  Future<void> _initializeCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) return;

      await _setupCamera(_selectedCameraIndex);
    } catch (e) {
      debugPrint('Camera init error: $e');
    }
  }

  Future<void> _setupCamera(int index) async {
    if (_cameras.isEmpty || index >= _cameras.length) return;

    // 1. Release previous camera controller to avoid hardware lock
    final oldController = _cameraController;
    if (mounted) {
      setState(() {
        _isInitialized = false;
        _cameraController = null;
      });
    }

    if (oldController != null) {
      try {
        await oldController.dispose();
      } catch (e) {
        debugPrint('Error disposing old camera controller: $e');
      }
    }

    // 2. Initialize new controller with robust resolution fallback
    CameraController newController = CameraController(
      _cameras[index],
      ResolutionPreset.high,
      enableAudio: false,
    );

    try {
      await newController.initialize();
    } catch (e) {
      debugPrint('Camera init error with high preset, falling back to medium: $e');
      try {
        await newController.dispose();
        newController = CameraController(
          _cameras[index],
          ResolutionPreset.medium,
          enableAudio: false,
        );
        await newController.initialize();
      } catch (e2) {
        debugPrint('Camera fallback failed: $e2');
        return;
      }
    }

    // 3. Configure flash safely (front camera does not support flash)
    try {
      final isBackCamera =
          _cameras[index].lensDirection == CameraLensDirection.back;
      if (isBackCamera) {
        await newController.setFlashMode(_flashMode);
      } else {
        await newController.setFlashMode(FlashMode.off);
      }
    } catch (e) {
      debugPrint('Flash mode not supported on this camera: $e');
    }

    if (mounted) {
      setState(() {
        _cameraController = newController;
        _isInitialized = true;
        _selectedCameraIndex = index;
      });
    }
  }

  void _startLocationUpdates() {
    _updateLocation();
    _locationTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _updateLocation();
    });
  }

  Future<void> _updateLocation() async {
    final online = await _offlineCache.isOnline();
    if (mounted && online != _isOnline) {
      setState(() => _isOnline = online);
    }

    final data = await _locationService.getLocationData();
    if (mounted && data != null) {
      final prevLocation = _currentLocation;
      setState(() => _currentLocation = data);
      // Animate mini map to current location
      if (_miniMapController != null) {
        _miniMapController!.animateCamera(
          CameraUpdate.newLatLng(LatLng(data.latitude, data.longitude)),
        );
        // Pre-cache map snapshot periodically when moving (only when online)
        if (_isOnline) {
          _miniMapController!.takeSnapshot().then((bytes) {
            if (bytes != null && mounted) {
              _offlineCache.cacheMapSnapshot(bytes, data.latitude, data.longitude);
            }
          }).catchError((_) {});
        }
      }
      // Update weather if not fetched yet or moved significantly
      if (_currentWeather == null ||
          prevLocation == null ||
          (prevLocation.latitude - data.latitude).abs() > 0.05 ||
          (prevLocation.longitude - data.longitude).abs() > 0.05) {
        _updateWeather(data.latitude, data.longitude);
      }
    }
  }

  Future<void> _updateWeather(double lat, double lng) async {
    if (!_showWeather && !_showWind && !_showHumidity) return;
    try {
      final weather = await _weatherService.fetchWeather(lat, lng);
      if (mounted) {
        setState(() => _currentWeather = weather);
      }
    } catch (e) {
      debugPrint('Weather update error: $e');
    }
  }

  Future<void> loadSettings() async {
    _stampTemplate = await _storageService.getStampTemplate();
    _mapType = await _storageService.getMapType();
    _companyName = await _storageService.getCompanyName();
    _companyLogoPath = await _storageService.getCompanyLogoPath();
    _showCompanyBadge = await _storageService.getShowCompanyBadge();
    _showMap = await _storageService.getShowMap();
    _showCoordinates = await _storageService.getShowCoordinates();
    _showAddress = await _storageService.getShowAddress();
    _showDate = await _storageService.getShowDate();
    _showAltitude = await _storageService.getShowAltitude();
    _showCompass = await _storageService.getShowCompass();
    _showWeather = await _storageService.getShowWeather();
    _showWind = await _storageService.getShowWind();
    _showHumidity = await _storageService.getShowHumidity();
    _tempUnit = await _storageService.getTemperatureUnit();
    _speedUnit = await _storageService.getWindSpeedUnit();
    _dateFormat = await _storageService.getDateFormat();
    _saveToGallery = await _storageService.getSaveToGallery();
    _stampPosition = await _storageService.getStampPosition();
    if (mounted) {
      setState(() {});
      if (_currentLocation != null) {
        _updateWeather(_currentLocation!.latitude, _currentLocation!.longitude);
      }
    }
  }

  Future<void> _loadLastPhoto() async {
    final photos = await _storageService.getPhotos();
    if (mounted && photos.isNotEmpty) {
      setState(() => _lastPhoto = photos.first);
    }
  }

  void _cycleMapType() {
    final nextIdx = (_mapType.index + 1) % AppMapType.values.length;
    final newMapType = AppMapType.values[nextIdx];
    setState(() => _mapType = newMapType);
    _storageService.setMapType(newMapType);

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(newMapType.icon, color: AppColors.accent, size: 18),
            const SizedBox(width: 8),
            Text('Map Type: ${newMapType.displayName}'),
          ],
        ),
        duration: const Duration(milliseconds: 1200),
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  /// Check if current camera is the front camera
  bool get _isFrontCamera {
    if (_cameras.isEmpty || _selectedCameraIndex >= _cameras.length) return false;
    return _cameras[_selectedCameraIndex].lensDirection == CameraLensDirection.front;
  }

  Future<void> _capturePhoto() async {
    if (_isCapturing ||
        _cameraController == null ||
        !_cameraController!.value.isInitialized) {
      return;
    }

    setState(() => _isCapturing = true);

    try {
      // 1. Snapshot the mini map before taking photo
      Uint8List? mapSnapshotBytes;
      if (_showMap) {
        // Only attempt live Google Map snapshot when connected to internet
        if (_isOnline && _miniMapController != null) {
          try {
            mapSnapshotBytes = await _miniMapController!.takeSnapshot();
          } catch (e) {
            debugPrint('Map snapshot capture error: $e');
          }
        }

        // Offline cache synchronization
        if (mapSnapshotBytes != null && _currentLocation != null) {
          // Online: Save live snapshot to disk cache for future offline use
          unawaited(_offlineCache.cacheMapSnapshot(
            mapSnapshotBytes,
            _currentLocation!.latitude,
            _currentLocation!.longitude,
          ));
        } else if (_currentLocation != null) {
          // Offline: Retrieve cached snapshot from disk if available
          mapSnapshotBytes = await _offlineCache.getCachedMapSnapshot(
            _currentLocation!.latitude,
            _currentLocation!.longitude,
          );
        }
      }

      // 2. Take the photo
      final XFile photo = await _cameraController!.takePicture();

      // 3. Prepare target file in app storage
      final photoDir = await _storageService.getPhotoDirectory();
      final timestamp = DateTime.now();
      final fileName = 'SidmaxGeotag_${timestamp.millisecondsSinceEpoch}.jpg';
      final savedPath = p.join(photoDir.path, fileName);

      // Copy raw photo
      await File(photo.path).copy(savedPath);

      // 4. Burn the GPS card, logo, map snapshot into the saved image
      await _stampImage(savedPath, mapSnapshotBytes);

      // 5. Save to device public gallery (DCIM / Pictures / SidmaxGeotag)
      String? galleryResult;
      if (_saveToGallery) {
        galleryResult = await _storageService.saveToDeviceGallery(
          savedPath,
          fileName: fileName,
        );
      }

      // 6. Save metadata
      final photoData = PhotoData(
        id: timestamp.millisecondsSinceEpoch.toString(),
        imagePath: savedPath,
        latitude: _currentLocation?.latitude ?? 0,
        longitude: _currentLocation?.longitude ?? 0,
        altitude: _currentLocation?.altitude,
        address: _currentLocation?.address ?? '',
        city: _currentLocation?.city ?? '',
        country: _currentLocation?.country ?? '',
        timestamp: timestamp,
        stampTemplate: _stampTemplate.name,
        mapType: _mapType.name,
        companyName: _companyName,
        temperature: _showWeather ? _currentWeather?.temperature : null,
        weatherCondition: _showWeather ? _currentWeather?.condition : null,
        windSpeed: _showWind ? _currentWeather?.windSpeed : null,
        windDirection: _showWind ? _currentWeather?.windDirection : null,
        humidity: _showHumidity ? _currentWeather?.humidity : null,
      );

      await _storageService.savePhotoData(photoData);
      setState(() => _lastPhoto = photoData);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(
                  Icons.check_circle,
                  color: AppColors.accentGreen,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    galleryResult != null
                        ? 'Photo saved to Gallery & App ($fileName)'
                        : 'Photo saved with GPS stamp',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
            backgroundColor: AppColors.surface,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            duration: const Duration(seconds: 3),
            action: SnackBarAction(
              label: 'VIEW',
              textColor: AppColors.accent,
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const GalleryScreen()),
                );
              },
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('Capture error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error capturing photo: $e'),
            backgroundColor: AppColors.accentRed,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isCapturing = false);
    }
  }

  Future<void> _stampImage(String imagePath, Uint8List? mapSnapshotBytes) async {
    try {
      final file = File(imagePath);
      final bytes = await file.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final originalImage = frame.image;

      // Decode map snapshot if available
      ui.Image? mapUiImage;
      if (mapSnapshotBytes != null) {
        try {
          final mapCodec = await ui.instantiateImageCodec(mapSnapshotBytes);
          final mapFrame = await mapCodec.getNextFrame();
          mapUiImage = mapFrame.image;
        } catch (e) {
          debugPrint('Error decoding map snapshot: $e');
        }
      }

      // Load company logo
      ui.Image? logoUiImage;
      try {
        if (_companyLogoPath != null &&
            _companyLogoPath!.isNotEmpty &&
            File(_companyLogoPath!).existsSync()) {
          final logoBytes = await File(_companyLogoPath!).readAsBytes();
          final logoCodec = await ui.instantiateImageCodec(logoBytes);
          final logoFrame = await logoCodec.getNextFrame();
          logoUiImage = logoFrame.image;
        } else {
          final ByteData logoData = await rootBundle.load(AppStrings.logoAsset);
          final logoCodec = await ui.instantiateImageCodec(
            logoData.buffer.asUint8List(),
          );
          final logoFrame = await logoCodec.getNextFrame();
          logoUiImage = logoFrame.image;
        }
      } catch (e) {
        debugPrint('Error loading logo asset: $e');
      }

      final isDeviceLandscape = (_deviceQuarterTurns == 1 || _deviceQuarterTurns == 3);
      final isImageAlreadyLandscape = (originalImage.width > originalImage.height);

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);

      double targetWidth;
      double targetHeight;

      if (isDeviceLandscape) {
        // User held device in LANDSCAPE -> Output MUST be TRUE LANDSCAPE (width > height)
        if (!isImageAlreadyLandscape) {
          // Camera delivered portrait buffer (e.g. 3000x4000) -> rotate onto landscape canvas (4000x3000)
          targetWidth = originalImage.height.toDouble();
          targetHeight = originalImage.width.toDouble();

          canvas.save();
          if (_isFrontCamera) {
            // Front camera sensor is mounted at 270° (180° opposite back camera).
            // When held in landscape, rotating it directly onto the landscape canvas
            // produces the upright selfie-mirrored perspective matching the live camera preview.
            if (_deviceQuarterTurns == 3) {
              // Landscape Left (top of device is on user's left):
              // Maps (x, y) -> (y, x), upright landscape with selfie mirror
              canvas.scale(1, -1);
              canvas.rotate(-math.pi / 2);
            } else {
              // Landscape Right (top of device is on user's right):
              // Maps (x, y) -> (targetWidth - y, targetHeight - x), upright landscape with selfie mirror
              canvas.translate(targetWidth, targetHeight);
              canvas.scale(-1, 1);
              canvas.rotate(-math.pi / 2);
            }
          } else {
            // Back camera:
            if (_deviceQuarterTurns == 3) {
              // Landscape Left (rotated 90° CCW, top is on left)
              canvas.translate(0, targetHeight);
              canvas.rotate(-math.pi / 2);
            } else {
              // Landscape Right (rotated 90° CW, top is on right)
              canvas.translate(targetWidth, 0);
              canvas.rotate(math.pi / 2);
            }
          }

          canvas.drawImage(originalImage, Offset.zero, Paint());
          canvas.restore();
        } else {
          // Image buffer is already landscape
          targetWidth = originalImage.width.toDouble();
          targetHeight = originalImage.height.toDouble();

          canvas.save();
          if (_isFrontCamera) {
            canvas.translate(targetWidth, 0);
            canvas.scale(-1, 1);
          }
          canvas.drawImage(originalImage, Offset.zero, Paint());
          canvas.restore();
        }
      } else {
        // User held device in PORTRAIT -> Output MUST be TRUE PORTRAIT (height > width)
        if (isImageAlreadyLandscape) {
          // Image buffer is landscape -> rotate to portrait
          targetWidth = originalImage.height.toDouble();
          targetHeight = originalImage.width.toDouble();

          canvas.save();
          if (_isFrontCamera) {
            canvas.translate(targetWidth, 0);
            canvas.scale(-1, 1);
          }
          canvas.translate(targetWidth, 0);
          canvas.rotate(math.pi / 2);
          canvas.drawImage(originalImage, Offset.zero, Paint());
          canvas.restore();
        } else {
          // Standard portrait buffer
          targetWidth = originalImage.width.toDouble();
          targetHeight = originalImage.height.toDouble();

          canvas.save();
          if (_isFrontCamera) {
            // Front camera portrait: flip horizontally to match selfie mirror preview
            canvas.translate(targetWidth, 0);
            canvas.scale(-1, 1);
          }
          if (_deviceQuarterTurns == 2) {
            // Upside down
            canvas.translate(targetWidth, targetHeight);
            canvas.rotate(math.pi);
          }
          canvas.drawImage(originalImage, Offset.zero, Paint());
          canvas.restore();
        }
      }

      // Draw the Sidmax Pro stamp overlay — always at bottom center
      _drawSidmaxProStampOnCanvas(
        canvas: canvas,
        imgWidth: targetWidth,
        imgHeight: targetHeight,
        mapImage: mapUiImage,
        logoImage: logoUiImage,
      );

      final picture = recorder.endRecording();
      final stampedImage = await picture.toImage(
        targetWidth.toInt(),
        targetHeight.toInt(),
      );

      // Encode as JPEG / PNG
      final byteData = await stampedImage.toByteData(
        format: ui.ImageByteFormat.png,
      );
      if (byteData != null) {
        await file.writeAsBytes(byteData.buffer.asUint8List());
      }

      originalImage.dispose();
      mapUiImage?.dispose();
      logoUiImage?.dispose();
      stampedImage.dispose();
    } catch (e) {
      debugPrint('Stamp error: $e');
    }
  }

  /// Helper to get the country flag emoji
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
      'New Zealand': '🇳🇿',
      'Russia': '🇷🇺',
      'Turkey': '🇹🇷',
      'Netherlands': '🇳🇱',
      'Switzerland': '🇨🇭',
      'South Africa': '🇿🇦',
      'Nigeria': '🇳🇬',
      'Pakistan': '🇵🇰',
      'Bangladesh': '🇧🇩',
    };
    return countryFlags[country] ?? '📍';
  }

  /// Get locality string with region info for the stamp
  String _getLocalityWithRegion(LocationData? loc) {
    if (loc == null) return 'Live GPS Location';
    final parts = <String>[];
    if (loc.city.isNotEmpty) parts.add(loc.city);
    if (loc.address.isNotEmpty) {
      final addressParts = loc.address.split(',').map((s) => s.trim()).toList();
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

  /// Draws the Sidmax Pro stamp overlay on the canvas.
  /// ALWAYS places the stamp at the bottom center of the final image,
  /// regardless of whether the image is portrait or landscape.
  /// The stamp layout adapts its width to the image dimensions.
  void _drawSidmaxProStampOnCanvas({
    required Canvas canvas,
    required double imgWidth,
    required double imgHeight,
    required ui.Image? mapImage,
    required ui.Image? logoImage,
  }) {
    final loc = _currentLocation;
    final isLandscape = imgWidth > imgHeight;

    // Proportional scale:
    // In portrait, base scale on width (short side, 480 ref)
    // In landscape, base scale on height (short side, 530 ref)
    // This gives the exact ~24% height and ~54% width, matching the live camera screen!
    final scale = isLandscape
        ? (imgHeight / 530.0).clamp(1.0, 5.8)
        : (imgWidth / 480.0).clamp(1.0, 6.5);

    // Total width of the stamp row — adaptive to orientation:
    // In landscape: 54% of photo width (centered), identical to camera preview (screenH * 0.54)
    // In portrait: full width with small side margin
    final totalWidth = isLandscape
        ? (imgWidth * 0.54).clamp(400.0 * scale, imgWidth * 0.62)
        : imgWidth - (20.0 * scale);

    final mapSize = (isLandscape ? 104.0 : 112.0) * scale;
    final gap = 6.0 * scale;
    final infoWidth = totalWidth - mapSize - gap;
    final rowHeight = mapSize;

    // Stamp X position (centered horizontally)
    final startX = (imgWidth - totalWidth) / 2;

    // Pill badge height and gap
    final pillHeight = (isLandscape ? 20.0 : 22.0) * scale;
    final pillGap = (isLandscape ? 4.5 : 5.0) * scale;
    final totalStampHeight = pillHeight + pillGap + rowHeight;

    // Stamp Y position — ALWAYS bottom center
    final startY = _stampPosition == 'top'
        ? (isLandscape ? 24.0 : 36.0) * scale
        : (imgHeight - totalStampHeight - (isLandscape ? 20.0 : 22.0) * scale);

    // ── 1. Floating Pill Badge (Top Right above Info Box) ──
    if (_showCompanyBadge) {
      final pillText = _companyName;
      final pillFontSize = (isLandscape ? 9.2 : 10.0) * scale;
      final pillTextBuilder = ui.ParagraphBuilder(
        ui.ParagraphStyle(fontSize: pillFontSize, fontWeight: ui.FontWeight.bold),
      )
        ..pushStyle(ui.TextStyle(
          color: const Color(0xFFFFFFFF),
          fontSize: pillFontSize,
          fontWeight: ui.FontWeight.bold,
        ))
        ..addText(pillText);
      final pillTextPara = pillTextBuilder.build()
        ..layout(ui.ParagraphConstraints(width: infoWidth));

      final pillContentWidth = (logoImage != null ? (16.0 * scale) : (14.0 * scale)) +
          (6.0 * scale) +
          pillTextPara.maxIntrinsicWidth +
          (18.0 * scale);

      final pillX = startX + totalWidth - pillContentWidth;
      final pillY = startY;

      final pillRRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(pillX, pillY, pillContentWidth, pillHeight),
        Radius.circular(12.0 * scale),
      );

      // Pill background
      canvas.drawRRect(
        pillRRect,
        Paint()..color = const Color(0xCC000000)..style = PaintingStyle.fill,
      );
      // Pill border
      canvas.drawRRect(
        pillRRect,
        Paint()
          ..color = const Color(0x66FFFFFF)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8 * scale,
      );

      // Pill logo
      final iconSize = 13.0 * scale;
      final iconX = pillX + 8.0 * scale;
      final iconY = pillY + (pillHeight - iconSize) / 2;

      if (logoImage != null) {
        canvas.drawImageRect(
          logoImage,
          Rect.fromLTWH(0, 0, logoImage.width.toDouble(), logoImage.height.toDouble()),
          Rect.fromLTWH(iconX, iconY, iconSize, iconSize),
          Paint(),
        );
      } else {
        // Fallback camera/logo dot
        canvas.drawCircle(
          Offset(iconX + iconSize / 2, iconY + iconSize / 2),
          iconSize / 2,
          Paint()..color = const Color(0xFF58A6FF),
        );
      }

      // Pill text
      canvas.drawParagraph(
        pillTextPara,
        Offset(iconX + iconSize + (5.0 * scale), pillY + (pillHeight - pillTextPara.height) / 2),
      );
    }

    final cardY = startY + pillHeight + pillGap;

    // ── 2. Mini Map Box on Left (Separate Rounded Box) ──
    if (_showMap) {
      final mapRect = Rect.fromLTWH(startX, cardY, mapSize, mapSize);
      final mapRRect = RRect.fromRectAndRadius(mapRect, Radius.circular(12.0 * scale));

      canvas.save();
      canvas.clipRRect(mapRRect);

      if (mapImage != null) {
        canvas.drawImageRect(
          mapImage,
          Rect.fromLTWH(0, 0, mapImage.width.toDouble(), mapImage.height.toDouble()),
          mapRect,
          Paint(),
        );

        // Green SAT badge in top right corner of the map (matches reference photo!)
        final satW = (isLandscape ? 22.0 : 24.0) * scale;
        final satH = (isLandscape ? 11.0 : 12.0) * scale;
        final satX = startX + mapSize - satW - (3.8 * scale);
        final satY = cardY + (3.8 * scale);
        final satRRect = RRect.fromRectAndRadius(
          Rect.fromLTWH(satX, satY, satW, satH),
          Radius.circular(3.0 * scale),
        );
        canvas.drawRRect(satRRect, Paint()..color = const Color(0xFF2E7D32));
        final satBuilder = ui.ParagraphBuilder(
          ui.ParagraphStyle(fontSize: (isLandscape ? 7.0 : 7.5) * scale, fontWeight: ui.FontWeight.bold, textAlign: ui.TextAlign.center),
        )
          ..pushStyle(ui.TextStyle(
            color: const Color(0xFFFFFFFF),
            fontSize: (isLandscape ? 7.0 : 7.5) * scale,
            fontWeight: ui.FontWeight.bold,
          ))
          ..addText('SAT');
        final satPara = satBuilder.build()..layout(ui.ParagraphConstraints(width: satW));
        canvas.drawParagraph(satPara, Offset(satX, satY + (satH - satPara.height) / 2));

        // Center red Google pin marker
        final pinCenterX = startX + mapSize / 2;
        final pinCenterY = cardY + mapSize / 2 - (3.0 * scale);
        final pinRadius = 7.0 * scale;

        // Shadow
        canvas.drawCircle(
          Offset(pinCenterX, pinCenterY + (10.0 * scale)),
          3.0 * scale,
          Paint()..color = const Color(0x55000000),
        );
        // Pin head
        canvas.drawCircle(
          Offset(pinCenterX, pinCenterY),
          pinRadius,
          Paint()..color = const Color(0xFFEA4335),
        );
        // Pin dot
        canvas.drawCircle(
          Offset(pinCenterX, pinCenterY),
          2.5 * scale,
          Paint()..color = const Color(0xFFFFFFFF),
        );
        // Pin stem
        final pinPath = Path()
          ..moveTo(pinCenterX - (4.0 * scale), pinCenterY + (4.0 * scale))
          ..lineTo(pinCenterX, pinCenterY + (10.0 * scale))
          ..lineTo(pinCenterX + (4.0 * scale), pinCenterY + (4.0 * scale))
          ..close();
        canvas.drawPath(pinPath, Paint()..color = const Color(0xFFEA4335));

        // "Google" watermark bottom-left
        final wmBuilder = ui.ParagraphBuilder(
          ui.ParagraphStyle(fontSize: 8.5 * scale, fontWeight: ui.FontWeight.bold),
        )
          ..pushStyle(ui.TextStyle(
            color: const Color(0xE6FFFFFF),
            fontSize: 8.5 * scale,
            fontWeight: ui.FontWeight.bold,
          ))
          ..addText('Google');
        final wmPara = wmBuilder.build()..layout(ui.ParagraphConstraints(width: mapSize));
        canvas.drawParagraph(wmPara, Offset(startX + (5.0 * scale), cardY + mapSize - wmPara.height - (4.0 * scale)));
      } else {
        // High-precision Leaflet / OpenStreetMap offline vector map
        // Renders realistic streets, blocks, parks, water, coordinate ticks,
        // center pin, and Google watermark directly on canvas with zero internet needed!
        LeafletOfflineMapPainter.drawLeafletMap(
          canvas: canvas,
          rect: mapRect,
          latitude: loc?.latitude ?? 14.5995,
          longitude: loc?.longitude ?? 120.9842,
          heading: loc?.heading ?? 0.0,
          isSatellite: _mapType == AppMapType.satellite,
          scale: scale,
          attributionText: 'Google',
        );
      }

      canvas.restore();

      // Border around map
      canvas.drawRRect(
        mapRRect,
        Paint()
          ..color = const Color(0xB3FFFFFF)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0 * scale,
      );
    }

    // ── 3. Info Box on Right (Separate Rounded Box) ──
    final infoX = startX + (_showMap ? (mapSize + gap) : 0);
    final actualInfoWidth = _showMap ? infoWidth : totalWidth;
    final infoRect = Rect.fromLTWH(infoX, cardY, actualInfoWidth, rowHeight);
    final infoRRect = RRect.fromRectAndRadius(infoRect, Radius.circular(12.0 * scale));

    // Background
    canvas.drawRRect(
      infoRRect,
      Paint()..color = const Color(0xA6000000)..style = PaintingStyle.fill,
    );
    // Border
    canvas.drawRRect(
      infoRRect,
      Paint()
        ..color = const Color(0xB3FFFFFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0 * scale,
    );

    // Padding inside info box
    final padX = 8.0 * scale;
    final textX = infoX + padX;
    final textW = actualInfoWidth - (padX * 2);
    double currentY = cardY + (6.0 * scale);

    // Line 1: City, Country Title (bold white with flag)
    final localityTitle = _getLocalityWithRegion(loc);
    final flag = _getCountryFlag(loc?.country ?? '');
    final titleFontSize = (isLandscape ? 11.5 : 12.5) * scale;
    final titleBuilder = ui.ParagraphBuilder(
      ui.ParagraphStyle(
        fontSize: titleFontSize,
        fontWeight: ui.FontWeight.bold,
        maxLines: 2,
        ellipsis: '...',
      ),
    )
      ..pushStyle(ui.TextStyle(
        color: const Color(0xFFFFFFFF),
        fontSize: titleFontSize,
        fontWeight: ui.FontWeight.bold,
      ))
      ..addText('$localityTitle $flag');
    final titlePara = titleBuilder.build()..layout(ui.ParagraphConstraints(width: textW));
    canvas.drawParagraph(titlePara, Offset(textX, currentY));
    currentY += titlePara.height + (3.0 * scale);

    // Line 2: Full Address with 📍
    if (_showAddress) {
      final addrFontSize = (isLandscape ? 8.2 : 9.0) * scale;
      final addrText = loc != null && loc.address.isNotEmpty
          ? '📍 ${loc.address}'
          : '📍 Getting location address...';
      final addrBuilder = ui.ParagraphBuilder(
        ui.ParagraphStyle(
          fontSize: addrFontSize,
          maxLines: 2,
          ellipsis: '...',
        ),
      )
        ..pushStyle(ui.TextStyle(
          color: const Color(0xE6FFFFFF),
          fontSize: addrFontSize,
        ))
        ..addText(addrText);
      final addrPara = addrBuilder.build()..layout(ui.ParagraphConstraints(width: textW));
      canvas.drawParagraph(addrPara, Offset(textX, currentY));
      currentY += addrPara.height + (2.5 * scale);
    }

    // Line 3: Coordinates (Lat / Long) with colored dots
    if (_showCoordinates && loc != null) {
      final coordFontSize = (isLandscape ? 8.2 : 9.0) * scale;
      final dotRadius = 2.5 * scale;

      // Red dot for Lat
      canvas.drawCircle(
        Offset(textX + dotRadius, currentY + coordFontSize * 0.55),
        dotRadius,
        Paint()..color = const Color(0xFFEA4335),
      );

      final latStr = 'Lat ${loc.latitude.toStringAsFixed(4)}° ${loc.latitude >= 0 ? "N" : "S"}';
      final latBuilder = ui.ParagraphBuilder(
        ui.ParagraphStyle(fontSize: coordFontSize),
      )
        ..pushStyle(ui.TextStyle(
          color: const Color(0xFF8AB4F8),
          fontSize: coordFontSize,
          fontWeight: ui.FontWeight.w600,
        ))
        ..addText(latStr);
      final latPara = latBuilder.build()..layout(ui.ParagraphConstraints(width: textW * 0.44));
      canvas.drawParagraph(latPara, Offset(textX + dotRadius * 3, currentY));

      // Separator |
      final sepX = textX + dotRadius * 3 + latPara.maxIntrinsicWidth + (6.0 * scale);
      final sepBuilder = ui.ParagraphBuilder(
        ui.ParagraphStyle(fontSize: coordFontSize),
      )
        ..pushStyle(ui.TextStyle(
          color: const Color(0x66FFFFFF),
          fontSize: coordFontSize,
        ))
        ..addText('|');
      final sepPara = sepBuilder.build()..layout(ui.ParagraphConstraints(width: 15.0 * scale));
      canvas.drawParagraph(sepPara, Offset(sepX, currentY));

      // Blue dot for Long
      final longDotX = sepX + (10.0 * scale);
      canvas.drawCircle(
        Offset(longDotX + dotRadius, currentY + coordFontSize * 0.55),
        dotRadius,
        Paint()..color = const Color(0xFF4285F4),
      );

      final longStr = 'Long ${loc.longitude.toStringAsFixed(4)}° ${loc.longitude >= 0 ? "E" : "W"}';
      final longBuilder = ui.ParagraphBuilder(
        ui.ParagraphStyle(fontSize: coordFontSize),
      )
        ..pushStyle(ui.TextStyle(
          color: const Color(0xFF8AB4F8),
          fontSize: coordFontSize,
          fontWeight: ui.FontWeight.w600,
        ))
        ..addText(longStr);
      final longPara = longBuilder.build()..layout(ui.ParagraphConstraints(width: textW - longDotX + textX));
      canvas.drawParagraph(longPara, Offset(longDotX + dotRadius * 3, currentY));

      currentY += coordFontSize * 1.35;
    }

    // Line 4: Date & Time with calendar emoji
    if (_showDate) {
      final dateFontSize = (isLandscape ? 8.2 : 9.0) * scale;
      final now = DateTime.now();
      String dateTimeLine;
      try {
        dateTimeLine = '📅 ${DateFormat(_dateFormat).format(now)}';
      } catch (_) {
        dateTimeLine = '📅 ${DateFormat('dd/MM/yyyy HH:mm').format(now)}';
      }

      final dateBuilder = ui.ParagraphBuilder(
        ui.ParagraphStyle(fontSize: dateFontSize),
      )
        ..pushStyle(ui.TextStyle(
          color: const Color(0xCCFFFFFF),
          fontSize: dateFontSize,
        ))
        ..addText(dateTimeLine);
      final datePara = dateBuilder.build()..layout(ui.ParagraphConstraints(width: textW));
      canvas.drawParagraph(datePara, Offset(textX, currentY));
      currentY += dateFontSize * 1.3;
    }

    // Line 5: Altitude / Compass if enabled
    if ((_showAltitude && loc?.altitude != null) || (_showCompass && loc?.heading != null)) {
      final extraParts = <String>[];
      if (_showAltitude && loc?.altitude != null) {
        extraParts.add('⛰️ Alt: ${loc!.altitude!.toStringAsFixed(1)}m');
      }
      if (_showCompass && loc?.heading != null) {
        final heading = loc!.heading!;
        final dir = _getCompassDirection(heading);
        extraParts.add('🧭 ${heading.toStringAsFixed(0)}° $dir');
      }
      if (extraParts.isNotEmpty) {
        final extraFontSize = (isLandscape ? 7.8 : 8.5) * scale;
        final extraBuilder = ui.ParagraphBuilder(
          ui.ParagraphStyle(fontSize: extraFontSize),
        )
          ..pushStyle(ui.TextStyle(
            color: const Color(0xCCFFFFFF),
            fontSize: extraFontSize,
          ))
          ..addText(extraParts.join('  •  '));
        final extraPara = extraBuilder.build()..layout(ui.ParagraphConstraints(width: textW));
        canvas.drawParagraph(extraPara, Offset(textX, currentY));
        currentY += extraFontSize * 1.3;
      }
    }

    // Line 6: Weather & Wind & Humidity
    if ((_showWeather || _showWind || _showHumidity) && _currentWeather != null) {
      final weatherSummary = _currentWeather!.formatSummary(
        includeWeather: _showWeather,
        includeWind: _showWind,
        showHumidity: _showHumidity,
        tempUnit: _tempUnit,
        speedUnit: _speedUnit,
      );
      if (weatherSummary.isNotEmpty) {
        final weatherFontSize = (isLandscape ? 8.2 : 9.0) * scale;
        final weatherBuilder = ui.ParagraphBuilder(
          ui.ParagraphStyle(fontSize: weatherFontSize),
        )
          ..pushStyle(ui.TextStyle(
            color: const Color(0xCCFFFFFF),
            fontSize: weatherFontSize,
          ))
          ..addText('⛅ $weatherSummary');
        final weatherPara = weatherBuilder.build()..layout(ui.ParagraphConstraints(width: textW));
        canvas.drawParagraph(weatherPara, Offset(textX, currentY));
      }
    }
  }

  String _getCompassDirection(double heading) {
    const directions = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];
    final index = ((heading + 22.5) % 360 ~/ 45);
    return directions[index];
  }


  void _toggleFlash() {
    if (_cameras.isNotEmpty &&
        _cameras[_selectedCameraIndex].lensDirection ==
            CameraLensDirection.front) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.info_outline, color: AppColors.accent, size: 18),
              SizedBox(width: 8),
              Text('Flash is not available on front camera'),
            ],
          ),
          duration: const Duration(milliseconds: 1200),
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
      return;
    }

    setState(() {
      switch (_flashMode) {
        case FlashMode.off:
          _flashMode = FlashMode.auto;
          break;
        case FlashMode.auto:
          _flashMode = FlashMode.always;
          break;
        case FlashMode.always:
          _flashMode = FlashMode.torch;
          break;
        case FlashMode.torch:
          _flashMode = FlashMode.off;
          break;
      }
    });
    try {
      _cameraController?.setFlashMode(_flashMode);
    } catch (e) {
      debugPrint('Failed to set flash mode: $e');
    }
  }

  void _switchCamera() async {
    if (_cameras.length < 2 || _isSwitchingCamera) return;
    _isSwitchingCamera = true;
    try {
      final newIndex = (_selectedCameraIndex + 1) % _cameras.length;
      await _setupCamera(newIndex);
    } finally {
      _isSwitchingCamera = false;
    }
  }

  IconData get _flashIcon {
    if (_cameras.isNotEmpty &&
        _cameras[_selectedCameraIndex].lensDirection ==
            CameraLensDirection.front) {
      return Icons.flash_off;
    }
    switch (_flashMode) {
      case FlashMode.off:
        return Icons.flash_off;
      case FlashMode.auto:
        return Icons.flash_auto;
      case FlashMode.always:
        return Icons.flash_on;
      case FlashMode.torch:
        return Icons.flashlight_on;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive) {
      _cameraController?.dispose();
      _cameraController = null;
      _isInitialized = false;
    } else if (state == AppLifecycleState.resumed) {
      if (_cameraController == null || !_cameraController!.value.isInitialized) {
        _initializeCamera();
        loadSettings();
        _loadLastPhoto();
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cameraController?.dispose();
    _locationTimer?.cancel();
    _accelerometerSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_hasPermission) {
      return _buildPermissionRequired();
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 1. Camera Viewfinder
            if (_isInitialized && _cameraController != null)
              Stack(
                fit: StackFit.expand,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(0),
                    child: CameraPreview(_cameraController!),
                  ),

                  // 2. Real-time GPS Overlay — stays at bottom center
                  // When device rotates, ONLY this stamp rotates to stay upright!
                  _buildRotatingStamp(),
                ],
              )
            else
              const Center(
                child: CircularProgressIndicator(color: AppColors.accent),
              ),

            // 3. Top controls bar (stays FIXED, does NOT rotate)
            Positioned(
              top: 8,
              left: 14,
              right: 14,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Flash toggle
                  _controlButton(icon: _flashIcon, onTap: _toggleFlash),

                  // Map Type quick switcher pill
                  GestureDetector(
                    onTap: _cycleMapType,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.65),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: AppColors.accent.withValues(alpha: 0.5),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(_mapType.icon, color: AppColors.accent, size: 14),
                          const SizedBox(width: 5),
                          Text(
                            _mapType.displayName,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Icon(Icons.swap_horiz, color: Colors.white70, size: 12),
                        ],
                      ),
                    ),
                  ),

                  // 2026 Google Maps Live View Quick Button
                  GestureDetector(
                    onTap: _openLiveViewModal,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.65),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: AppColors.accent.withValues(alpha: 0.7),
                        ),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.streetview, color: AppColors.accent, size: 14),
                          SizedBox(width: 4),
                          Text(
                            'Live View',
                            style: TextStyle(
                              color: AppColors.accent,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Location status with high-precision readout
                  GestureDetector(
                    onTap: _openLiveViewModal,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.65),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: _currentLocation != null
                              ? AppColors.accentGreen.withValues(alpha: 0.6)
                              : AppColors.accentRed.withValues(alpha: 0.6),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _currentLocation != null
                                ? Icons.gps_fixed
                                : Icons.gps_not_fixed,
                            color: _currentLocation != null
                                ? AppColors.accentGreen
                                : AppColors.accentRed,
                            size: 13,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _currentLocation != null
                                ? 'GPS ${_currentLocation!.formattedAccuracy}'
                                : 'Locating...',
                            style: TextStyle(
                              color: _currentLocation != null
                                  ? AppColors.accentGreen
                                  : AppColors.accentRed,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Switch camera (front / back)
                  _controlButton(
                    icon: Icons.cameraswitch,
                    onTap: _switchCamera,
                  ),
                ],
              ),
            ),

            // 4. Capture Controls Bar (stays FIXED at bottom, does NOT rotate)
            Positioned(
              bottom: 14,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildGalleryThumbnail(),
                  _buildCaptureButton(),
                  _controlButton(
                    icon: _stampTemplate.icon,
                    onTap: _cycleTemplate,
                    size: 48,
                  ),
                ],
              ),
            ),

            // 5. Orientation indicator (subtle badge)
            if (_isDeviceLandscape)
              Positioned(
                top: 60,
                left: 0,
                right: 0,
                child: Center(
                  child: AnimatedOpacity(
                    opacity: 1.0,
                    duration: const Duration(milliseconds: 300),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.accent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.accent.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.screen_rotation, color: AppColors.accent, size: 12),
                          const SizedBox(width: 4),
                          Text(
                            _deviceQuarterTurns == 3 ? 'Landscape Left' : 'Landscape Right',
                            style: const TextStyle(
                              color: AppColors.accent,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Builds the stamp overlay that auto-rotates based on device physical orientation.
  /// When the device is held in landscape, ONLY the stamp rotates — the camera controls stay fixed.
  /// The stamp ALWAYS remains at the bottom center of the user's visual field.
  Widget _buildRotatingStamp() {
    final screenSize = MediaQuery.of(context).size;
    final screenW = screenSize.width;
    final screenH = screenSize.height;

    double stampW;
    const double stampH = 152.0;

    if (_isDeviceLandscape) {
      // In landscape, user sees the phone rotated - stamp width based on the long edge (screenH)
      stampW = (screenH * 0.54).clamp(360.0, 520.0);
    } else {
      stampW = (screenW - 16.0).clamp(320.0, 480.0);
    }

    double left;
    double top;
    double turns;

    final bool isStampAtTop = _stampPosition == 'top';

    if (_deviceQuarterTurns == 3) {
      // Landscape Left (device rotated 90° CCW, top is on user's left):
      // User's visual bottom = physical LEFT edge of phone (x = 0).
      // User's visual top = physical RIGHT edge of phone (x = screenW).
      // Rotate stamp 90° CW (turns: 0.25) so text stays right-side-up.
      turns = 0.25;
      final cx = isStampAtTop
          ? screenW - (stampH / 2) - 14.0
          : (stampH / 2) + 14.0;
      final cy = screenH / 2;
      left = cx - (stampW / 2);
      top = cy - (stampH / 2);
    } else if (_deviceQuarterTurns == 1) {
      // Landscape Right (device rotated 90° CW, top is on user's right):
      // User's visual bottom = physical RIGHT edge of phone (x = screenW).
      // User's visual top = physical LEFT edge of phone (x = 0).
      // Rotate stamp 90° CCW (turns: -0.25) so text stays right-side-up.
      turns = -0.25;
      final cx = isStampAtTop
          ? (stampH / 2) + 14.0
          : screenW - (stampH / 2) - 14.0;
      final cy = screenH / 2;
      left = cx - (stampW / 2);
      top = cy - (stampH / 2);
    } else if (_deviceQuarterTurns == 2) {
      // Upside Down:
      turns = 0.5;
      final cx = screenW / 2;
      final cy = isStampAtTop
          ? screenH - (stampH / 2) - 100.0
          : (stampH / 2) + 55.0;
      left = cx - (stampW / 2);
      top = cy - (stampH / 2);
    } else {
      // Portrait Normal:
      turns = 0.0;
      final cx = screenW / 2;
      final cy = isStampAtTop
          ? (stampH / 2) + 55.0
          : screenH - (stampH / 2) - 100.0;
      left = cx - (stampW / 2);
      top = cy - (stampH / 2);
    }

    return AnimatedPositioned(
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOutCubic,
      left: left,
      top: top,
      width: stampW,
      height: stampH,
      child: AnimatedRotation(
        turns: turns,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOutCubic,
        child: GpsOverlay(
          locationData: _currentLocation,
          template: _stampTemplate,
          mapType: _mapType,
          showCoordinates: _showCoordinates,
          showAddress: _showAddress,
          showDate: _showDate,
          showAltitude: _showAltitude,
          showCompass: _showCompass,
          showMap: _showMap,
          showCompanyBadge: _showCompanyBadge,
          companyName: _companyName,
          companyLogoPath: _companyLogoPath,
          dateFormat: _dateFormat,
          isLandscape: _isDeviceLandscape,
          isOnline: _isOnline,
          weatherSummary: (_showWeather || _showWind || _showHumidity)
              ? _currentWeather?.formatSummary(
                  includeWeather: _showWeather,
                  includeWind: _showWind,
                  showHumidity: _showHumidity,
                  tempUnit: _tempUnit,
                  speedUnit: _speedUnit,
                )
              : null,
          onMapCreated: (controller) {
            _miniMapController = controller;
          },
          onMapTap: _cycleMapType,
        ),
      ),
    );
  }

  Widget _buildGalleryThumbnail() {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const GalleryScreen()),
        ).then((_) => _loadLastPhoto());
      },
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.4),
            width: 1.5,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: _lastPhoto != null && File(_lastPhoto!.imagePath).existsSync()
            ? Image.file(
                File(_lastPhoto!.imagePath),
                fit: BoxFit.cover,
              )
            : const Icon(
                Icons.photo_library_outlined,
                color: Colors.white,
                size: 22,
              ),
      ),
    );
  }

  Widget _buildCaptureButton() {
    return GestureDetector(
      onTap: _capturePhoto,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 76,
        height: 76,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 4),
          boxShadow: [
            BoxShadow(
              color: AppColors.accent.withValues(alpha: 0.35),
              blurRadius: 20,
            ),
          ],
        ),
        child: Container(
          margin: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _isCapturing ? AppColors.accentRed : Colors.white,
          ),
          child: _isCapturing
              ? const Padding(
                  padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: Colors.white,
                  ),
                )
              : null,
        ),
      ),
    );
  }

  void _cycleTemplate() {
    final idx = (_stampTemplate.index + 1) % StampTemplate.values.length;
    final nextTemplate = StampTemplate.values[idx];
    setState(() => _stampTemplate = nextTemplate);
    _storageService.setStampTemplate(nextTemplate);

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Template: ${nextTemplate.displayName}'),
        duration: const Duration(milliseconds: 1000),
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Widget _controlButton({
    required IconData icon,
    required VoidCallback onTap,
    double size = 42,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
        ),
        child: Icon(icon, color: Colors.white, size: size * 0.46),
      ),
    );
  }

  void _openLiveViewModal() {
    final loc = _currentLocation;
    if (loc == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Acquiring high accuracy GPS fix...'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      isScrollControlled: true,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
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
                      child: const Icon(Icons.view_in_ar, color: Colors.white, size: 24),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '2026 Google Maps Live View',
                            style: TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'Precision: ${loc.formattedAccuracy}',
                            style: const TextStyle(
                              color: AppColors.accentGreen,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: AppColors.textMuted),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                // 3D Mini Map Preview
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: SizedBox(
                    height: 160,
                    width: double.infinity,
                    child: GoogleMap(
                      initialCameraPosition: CameraPosition(
                        target: LatLng(loc.latitude, loc.longitude),
                        zoom: 18,
                        tilt: 58,
                        bearing: loc.heading ?? 0,
                      ),
                      myLocationEnabled: true,
                      myLocationButtonEnabled: false,
                      zoomControlsEnabled: false,
                      compassEnabled: true,
                      mapType: MapType.satellite,
                      markers: {
                        Marker(
                          markerId: const MarkerId('current_pos'),
                          position: LatLng(loc.latitude, loc.longitude),
                          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueCyan),
                        ),
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                // Telemetry Row
                Row(
                  children: [
                    _buildModalBadge(
                      icon: Icons.place,
                      label: '${loc.latitude.toStringAsFixed(4)}°, ${loc.longitude.toStringAsFixed(4)}°',
                      sub: 'Coordinates',
                    ),
                    const SizedBox(width: 8),
                    _buildModalBadge(
                      icon: Icons.explore,
                      label: '${loc.heading?.toStringAsFixed(0) ?? '0'}° ${loc.compassDirection}',
                      sub: 'Bearing',
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // Buttons
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Navigator.pop(ctx);
                          _storageService.openGoogleMapsLiveView(
                            loc.latitude,
                            loc.longitude,
                            mode: 'streetView',
                          );
                        },
                        icon: const Icon(Icons.streetview, size: 18),
                        label: const Text('Street View'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.accent,
                          foregroundColor: Colors.black,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.pop(ctx);
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => MapScreen(
                                initialLat: loc.latitude,
                                initialLng: loc.longitude,
                                startInLiveView: true,
                              ),
                            ),
                          );
                        },
                        icon: const Icon(Icons.map, size: 18),
                        label: const Text('3D Photo Map'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.accent,
                          side: const BorderSide(color: AppColors.accent),
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
          ),
        );
      },
    );
  }

  Widget _buildModalBadge({
    required IconData icon,
    required String label,
    required String sub,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: AppColors.accent),
            const SizedBox(width: 8),
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

  Widget _buildPermissionRequired() {
    return Scaffold(
      backgroundColor: AppColors.primaryDark,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.camera_alt,
                  color: AppColors.accent,
                  size: 48,
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Permissions Required',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                '${AppStrings.appName} needs camera, location, and storage permissions to take and save GPS-stamped photos to your gallery.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary, fontSize: 15),
              ),
              const SizedBox(height: 32),
              ElevatedButton.icon(
                onPressed: () async {
                  await _requestPermissions();
                  if (_hasPermission) {
                    await _initializeCamera();
                    _startLocationUpdates();
                    await loadSettings();
                    _loadLastPhoto();
                  }
                },
                icon: const Icon(Icons.security),
                label: const Text('Grant Permissions'),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => openAppSettings(),
                child: const Text(
                  'Open Settings',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
