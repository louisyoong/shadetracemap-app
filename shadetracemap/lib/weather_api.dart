import 'dart:convert';

import 'package:http/http.dart' as http;

/// Today's sunrise/sunset, sunshine duration, UV index and temperature for
/// a location, from Open-Meteo's free forecast API (no API key required).
class WeatherData {
  const WeatherData({
    required this.sunrise,
    required this.sunset,
    required this.sunshineDuration,
    required this.uvIndexMax,
    required this.temperature,
    required this.weatherCode,
  });

  final DateTime? sunrise;
  final DateTime? sunset;
  final Duration sunshineDuration;
  final double uvIndexMax;
  final double temperature;
  final int weatherCode;
}

/// `timezone=auto` makes Open-Meteo return every timestamp as that
/// location's local wall-clock time (no UTC offset suffix), so parsing it
/// with DateTime.parse and reading the hour/minute straight off is correct
/// without any extra timezone math.
Future<WeatherData> fetchWeather(double lat, double lon) async {
  final uri = Uri.parse('https://api.open-meteo.com/v1/forecast').replace(
    queryParameters: {
      'latitude': '$lat',
      'longitude': '$lon',
      'daily': 'sunrise,sunset,sunshine_duration,uv_index_max',
      'current': 'temperature_2m,weather_code',
      'forecast_days': '1',
      'timezone': 'auto',
    },
  );
  final res = await http.get(uri);
  if (res.statusCode != 200) {
    throw Exception('Open-Meteo request failed (${res.statusCode})');
  }
  final data = jsonDecode(res.body) as Map<String, dynamic>;
  final daily = data['daily'] as Map<String, dynamic>;
  final current = data['current'] as Map<String, dynamic>;

  DateTime? parseTime(String key) {
    final list = daily[key] as List<dynamic>?;
    if (list == null || list.isEmpty || list.first == null) return null;
    return DateTime.tryParse(list.first as String);
  }

  double firstDouble(Map<String, dynamic> map, String key) {
    final list = map[key] as List<dynamic>?;
    final v = (list == null || list.isEmpty) ? null : list.first;
    return (v as num?)?.toDouble() ?? 0;
  }

  return WeatherData(
    sunrise: parseTime('sunrise'),
    sunset: parseTime('sunset'),
    sunshineDuration: Duration(
      seconds: firstDouble(daily, 'sunshine_duration').round(),
    ),
    uvIndexMax: firstDouble(daily, 'uv_index_max'),
    temperature: (current['temperature_2m'] as num?)?.toDouble() ?? 0,
    weatherCode: (current['weather_code'] as num?)?.toInt() ?? 0,
  );
}

/// Open-Meteo/WMO weather-code table, condensed to the short phrases a
/// weather-app hero card shows (e.g. "Clear and sunny").
String weatherCodeDescription(int code) {
  switch (code) {
    case 0:
      return 'Clear and sunny';
    case 1:
      return 'Mainly clear';
    case 2:
      return 'Partly cloudy';
    case 3:
      return 'Overcast';
    case 45:
    case 48:
      return 'Foggy';
    case 51:
    case 53:
    case 55:
      return 'Drizzle';
    case 56:
    case 57:
      return 'Freezing drizzle';
    case 61:
    case 63:
      return 'Rain';
    case 65:
      return 'Heavy rain';
    case 66:
    case 67:
      return 'Freezing rain';
    case 71:
    case 73:
    case 75:
    case 77:
      return 'Snow';
    case 80:
    case 81:
      return 'Rain showers';
    case 82:
      return 'Heavy rain showers';
    case 85:
    case 86:
      return 'Snow showers';
    case 95:
      return 'Thunderstorm';
    case 96:
    case 99:
      return 'Thunderstorm with hail';
    default:
      return 'Unsettled weather';
  }
}

/// EPA/WHO UV index scale: 0-2 Low, 3-5 Moderate, 6-7 High, 8-10 Very High,
/// 11+ Extreme.
({String label, int color}) uvIndexCategory(double uv) {
  if (uv < 3) return (label: 'Low', color: 0xFF4CAF50);
  if (uv < 6) return (label: 'Moderate', color: 0xFFFFC107);
  if (uv < 8) return (label: 'High', color: 0xFFFF9800);
  if (uv < 11) return (label: 'Very High', color: 0xFFF4511E);
  return (label: 'Extreme', color: 0xFF9C27B0);
}
