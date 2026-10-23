class WeatherData {
  final double temperature; // in Celsius
  final double windSpeed; // in km/h
  final double windDirection; // in degrees
  final int humidity; // in percent
  final int weatherCode;
  final String conditionText;
  final String iconEmoji;

  const WeatherData({
    required this.temperature,
    required this.windSpeed,
    required this.windDirection,
    required this.humidity,
    required this.weatherCode,
    required this.conditionText,
    required this.iconEmoji,
  });

  String formattedTemp([String unit = 'C']) {
    if (unit == 'F') {
      final f = (temperature * 9 / 5) + 32;
      return '${f.round()}°F';
    }
    return '${temperature.round()}°C';
  }

  String get compassDir {
    if (windDirection < 0) return 'N';
    const directions = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];
    final index = ((windDirection + 22.5) % 360 / 45).floor();
    return directions[index % 8];
  }

  String formattedWind([String unit = 'km/h']) {
    if (unit == 'mph') {
      final mph = windSpeed * 0.621371;
      return '${mph.round()} mph $compassDir';
    }
    return '${windSpeed.round()} km/h $compassDir';
  }

  String get formattedHumidity => '$humidity%';

  String summary({
    String tempUnit = 'C',
    String windUnit = 'km/h',
    bool showWeather = true,
    bool showWind = true,
    bool showHumidity = false,
  }) {
    final parts = <String>[];
    if (showWeather) {
      parts.add('$iconEmoji ${formattedTemp(tempUnit)} $conditionText');
    }
    if (showWind) {
      parts.add('💨 ${formattedWind(windUnit)}');
    }
    if (showHumidity) {
      parts.add('💧 $formattedHumidity');
    }
    return parts.join(' | ');
  }

  String get condition => conditionText;

  String formatSummary({
    bool includeWeather = true,
    bool includeWind = true,
    bool showHumidity = false,
    String tempUnit = 'celsius',
    String speedUnit = 'kmh',
  }) {
    final tUnit = (tempUnit.toLowerCase() == 'fahrenheit' || tempUnit == 'F') ? 'F' : 'C';
    final sUnit = (speedUnit.toLowerCase() == 'mph') ? 'mph' : 'km/h';
    return summary(
      showWeather: includeWeather,
      showWind: includeWind,
      showHumidity: showHumidity,
      tempUnit: tUnit,
      windUnit: sUnit,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'temperature': temperature,
      'windSpeed': windSpeed,
      'windDirection': windDirection,
      'humidity': humidity,
      'weatherCode': weatherCode,
      'conditionText': conditionText,
      'iconEmoji': iconEmoji,
    };
  }

  factory WeatherData.fromJson(Map<String, dynamic> json) {
    return WeatherData(
      temperature: (json['temperature'] as num?)?.toDouble() ?? 28.0,
      windSpeed: (json['windSpeed'] as num?)?.toDouble() ?? 10.0,
      windDirection: (json['windDirection'] as num?)?.toDouble() ?? 0.0,
      humidity: (json['humidity'] as num?)?.toInt() ?? 70,
      weatherCode: (json['weatherCode'] as num?)?.toInt() ?? 0,
      conditionText: json['conditionText'] as String? ?? 'Sunny',
      iconEmoji: json['iconEmoji'] as String? ?? '☀️',
    );
  }

  /// Default fallback weather
  factory WeatherData.defaultWeather() {
    final hour = DateTime.now().hour;
    final isNight = hour < 6 || hour >= 18;
    return WeatherData(
      temperature: isNight ? 26.0 : 31.0,
      windSpeed: 12.0,
      windDirection: 75.0,
      humidity: 72,
      weatherCode: isNight ? 0 : 1,
      conditionText: isNight ? 'Clear' : 'Sunny',
      iconEmoji: isNight ? '🌙' : '☀️',
    );
  }
}
