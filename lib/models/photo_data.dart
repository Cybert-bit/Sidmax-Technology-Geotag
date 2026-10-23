import 'dart:convert';

class PhotoData {
  final String id;
  final String imagePath;
  final double latitude;
  final double longitude;
  final double? altitude;
  final String address;
  final String city;
  final String country;
  final DateTime timestamp;
  final String stampTemplate;
  final String mapType;
  final String companyName;
  final double? temperature;
  final String? weatherCondition;
  final double? windSpeed;
  final double? windDirection;
  final int? humidity;

  PhotoData({
    required this.id,
    required this.imagePath,
    required this.latitude,
    required this.longitude,
    this.altitude,
    required this.address,
    this.city = '',
    this.country = '',
    required this.timestamp,
    this.stampTemplate = 'sidmaxPro',
    this.mapType = 'satellite',
    this.companyName = 'Sidmax Technology',
    this.temperature,
    this.weatherCondition,
    this.windSpeed,
    this.windDirection,
    this.humidity,
  });

  String get formattedCoordinates {
    final latDir = latitude >= 0 ? 'N' : 'S';
    final lngDir = longitude >= 0 ? 'E' : 'W';
    return '${latitude.abs().toStringAsFixed(6)}° $latDir, ${longitude.abs().toStringAsFixed(6)}° $lngDir';
  }

  String get formattedDate {
    final d = timestamp.day.toString().padLeft(2, '0');
    final m = timestamp.month.toString().padLeft(2, '0');
    final y = timestamp.year.toString();
    final h = timestamp.hour.toString().padLeft(2, '0');
    final min = timestamp.minute.toString().padLeft(2, '0');
    return '$d/$m/$y $h:$min';
  }

  String get weatherSummary {
    if (temperature == null && weatherCondition == null && windSpeed == null) {
      return '';
    }
    final parts = <String>[];
    if (temperature != null) {
      parts.add('${temperature!.round()}°C ${weatherCondition ?? ''}'.trim());
    }
    if (windSpeed != null) {
      parts.add('💨 ${windSpeed!.round()} km/h');
    }
    if (humidity != null) {
      parts.add('💧 $humidity%');
    }
    return parts.join(' | ');
  }

  String get shortAddress {
    if (address.isEmpty) return 'Unknown Location';
    final parts = address.split(',');
    if (parts.length <= 2) return address;
    return '${parts[0].trim()}, ${parts[1].trim()}';
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'imagePath': imagePath,
      'latitude': latitude,
      'longitude': longitude,
      'altitude': altitude,
      'address': address,
      'city': city,
      'country': country,
      'timestamp': timestamp.toIso8601String(),
      'stampTemplate': stampTemplate,
      'mapType': mapType,
      'companyName': companyName,
      'temperature': temperature,
      'weatherCondition': weatherCondition,
      'windSpeed': windSpeed,
      'windDirection': windDirection,
      'humidity': humidity,
    };
  }

  factory PhotoData.fromJson(Map<String, dynamic> json) {
    return PhotoData(
      id: json['id'] as String,
      imagePath: json['imagePath'] as String,
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      altitude: json['altitude'] != null
          ? (json['altitude'] as num).toDouble()
          : null,
      address: json['address'] as String? ?? '',
      city: json['city'] as String? ?? '',
      country: json['country'] as String? ?? '',
      timestamp: DateTime.parse(json['timestamp'] as String),
      stampTemplate: json['stampTemplate'] as String? ?? 'sidmaxPro',
      mapType: json['mapType'] as String? ?? 'satellite',
      companyName: json['companyName'] as String? ?? 'Sidmax Technology',
      temperature: (json['temperature'] as num?)?.toDouble(),
      weatherCondition: json['weatherCondition'] as String?,
      windSpeed: (json['windSpeed'] as num?)?.toDouble(),
      windDirection: (json['windDirection'] as num?)?.toDouble(),
      humidity: (json['humidity'] as num?)?.toInt(),
    );
  }

  String toJsonString() => jsonEncode(toJson());

  factory PhotoData.fromJsonString(String jsonString) {
    return PhotoData.fromJson(jsonDecode(jsonString) as Map<String, dynamic>);
  }
}
