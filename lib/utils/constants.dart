import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' show MapType;

// ─── App Colors ──────────────────────────────────────────────
class AppColors {
  // Primary gradient
  static const Color primaryDark = Color(0xFF0D1117);
  static const Color primaryMid = Color(0xFF161B22);
  static const Color primaryLight = Color(0xFF21262D);

  // Accent colors
  static const Color accent = Color(0xFF58A6FF);
  static const Color accentGreen = Color(0xFF3FB950);
  static const Color accentOrange = Color(0xFFF0883E);
  static const Color accentPurple = Color(0xFFBC8CFF);
  static const Color accentPink = Color(0xFFF778BA);
  static const Color accentRed = Color(0xFFFF7B72);

  // Surface colors
  static const Color surface = Color(0xFF1C2128);
  static const Color surfaceLight = Color(0xFF2D333B);
  static const Color cardBackground = Color(0xFF161B22);
  static const Color border = Color(0xFF30363D);

  // Text
  static const Color textPrimary = Color(0xFFE6EDF3);
  static const Color textSecondary = Color(0xFF8B949E);
  static const Color textMuted = Color(0xFF6E7681);

  // Gradients
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [Color(0xFF58A6FF), Color(0xFFBC8CFF)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient accentGradient = LinearGradient(
    colors: [Color(0xFF3FB950), Color(0xFF58A6FF)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient warmGradient = LinearGradient(
    colors: [Color(0xFFF0883E), Color(0xFFF778BA)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient surfaceGradient = LinearGradient(
    colors: [Color(0xFF0D1117), Color(0xFF161B22)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );
}

// ─── App Strings ─────────────────────────────────────────────
class AppStrings {
  static const String appName = 'Sidmax Technology Geotag';
  static const String appTagline = 'GPS Camera with Live Map on Photo';
  static const String defaultCompany = 'Sidmax Technology';
  static const String appVersion = '1.1.0';
  static const String logoAsset = 'assets/images/logo.png';
  static const String defaultAlbum = 'SidmaxGeotag';

  // Tab labels
  static const String camera = 'Camera';
  static const String gallery = 'Gallery';
  static const String map = 'Map';
  static const String settings = 'Settings';
}

// ─── App Dimensions ──────────────────────────────────────────
class AppDimensions {
  static const double borderRadius = 16.0;
  static const double borderRadiusSmall = 8.0;
  static const double borderRadiusLarge = 24.0;

  static const double paddingSmall = 8.0;
  static const double padding = 16.0;
  static const double paddingLarge = 24.0;

  static const double iconSize = 24.0;
  static const double iconSizeLarge = 32.0;

  static const double stampFontSize = 11.0;
  static const double stampPadding = 12.0;
}

// ─── Stamp Template IDs ──────────────────────────────────────
enum StampTemplate {
  sidmaxPro, // Reference image template with mini map & logo badge
  classic,
  modern,
  minimal,
  explorer,
}

extension StampTemplateExt on StampTemplate {
  String get displayName {
    switch (this) {
      case StampTemplate.sidmaxPro:
        return 'Sidmax Pro (Live Map)';
      case StampTemplate.classic:
        return 'Classic';
      case StampTemplate.modern:
        return 'Modern';
      case StampTemplate.minimal:
        return 'Minimal';
      case StampTemplate.explorer:
        return 'Explorer';
    }
  }

  IconData get icon {
    switch (this) {
      case StampTemplate.sidmaxPro:
        return Icons.map;
      case StampTemplate.classic:
        return Icons.photo_camera;
      case StampTemplate.modern:
        return Icons.auto_awesome;
      case StampTemplate.minimal:
        return Icons.crop_square;
      case StampTemplate.explorer:
        return Icons.explore;
    }
  }
}

// ─── Map Types ───────────────────────────────────────────────
enum AppMapType {
  satellite,
  normal,
  terrain,
  hybrid,
}

extension AppMapTypeExt on AppMapType {
  String get displayName {
    switch (this) {
      case AppMapType.satellite:
        return 'Satellite';
      case AppMapType.normal:
        return 'Normal';
      case AppMapType.terrain:
        return 'Terrain';
      case AppMapType.hybrid:
        return 'Hybrid';
    }
  }

  IconData get icon {
    switch (this) {
      case AppMapType.satellite:
        return Icons.satellite_alt;
      case AppMapType.normal:
        return Icons.map_outlined;
      case AppMapType.terrain:
        return Icons.terrain;
      case AppMapType.hybrid:
        return Icons.layers;
    }
  }

  MapType get toGoogleMapType {
    switch (this) {
      case AppMapType.satellite:
        return MapType.satellite;
      case AppMapType.normal:
        return MapType.normal;
      case AppMapType.terrain:
        return MapType.terrain;
      case AppMapType.hybrid:
        return MapType.hybrid;
    }
  }

  static AppMapType fromString(String val) {
    switch (val.toLowerCase()) {
      case 'normal':
        return AppMapType.normal;
      case 'terrain':
        return AppMapType.terrain;
      case 'hybrid':
        return AppMapType.hybrid;
      case 'satellite':
      default:
        return AppMapType.satellite;
    }
  }
}

// ─── Color Extensions ────────────────────────────────────────
extension ColorExtension on Color {
  /// Returns a copy of this color with the given [alpha] (0.0‑1.0).
  /// The [alpha] value is clamped between 0.0 and 1.0.
  Color withValues({required double alpha}) {
    final clamped = alpha.clamp(0.0, 1.0);
    return withAlpha((clamped * 255).toInt());
  }
}
