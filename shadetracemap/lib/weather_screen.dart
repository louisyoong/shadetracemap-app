import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'device_location.dart';
import 'glass_panel.dart';
import 'location_search.dart';
import 'sun_math.dart';
import 'weather_api.dart';

const _initialLat = 3.1412;
const _initialLng = 101.68653;

const _lightText = Color(0xFF2A2620);
const _lightTextMuted = Color(0x992A2620);
const _darkText = Color(0xFFF3F1EC);
const _darkTextMuted = Color(0x99F3F1EC);

/// A location-scoped weather preview: today's sunrise/sunset, sunshine
/// duration, UV index and temperature, pulled from Open-Meteo's free
/// forecast API. Styled as a full-bleed gradient "hero card" (tinted by how
/// warm or cold it is) with a big current-temperature readout, mirroring
/// the classic iOS weather-app look. Follows system light/dark mode with
/// two parallel colour sets rather than a single fixed look.
class WeatherScreen extends StatefulWidget {
  const WeatherScreen({super.key});

  @override
  State<WeatherScreen> createState() => _WeatherScreenState();
}

class _WeatherScreenState extends State<WeatherScreen>
    with SingleTickerProviderStateMixin {
  double _lat = _initialLat;
  double _lng = _initialLng;
  String _locationLabel = 'Kuala Lumpur, Malaysia';

  final _locationSearch = LocationSearchController();

  Future<WeatherData>? _future;

  // Slowly sweeps the background gradient's axis back and forth for as
  // long as this tab stays open, so the backdrop reads as gently alive
  // instead of a flat, static wash - same technique as the Compass tab.
  late final AnimationController _bgController = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 6),
  )..repeat(reverse: true);

  @override
  void initState() {
    super.initState();
    _reload();
    _detectDeviceLocation();
  }

  // Best-effort: silently keep the Kuala Lumpur default if the device
  // won't give up a location (services off, permission denied, etc.) -
  // this runs automatically on open, so it shouldn't interrupt the user
  // with an error for something they didn't explicitly ask for.
  Future<void> _detectDeviceLocation() async {
    try {
      final position = await resolveDeviceLocation();
      if (!mounted) return;
      setState(() {
        _lat = position.latitude;
        _lng = position.longitude;
        _locationLabel = 'My Location';
      });
      _locationSearch.selected('My Location');
      _reload();

      // Best-effort follow-up: swap the generic placeholder for a real
      // place name once reverse geocoding resolves, without blocking the
      // weather fetch on it.
      final label = await reverseGeocodeLabel(
        position.latitude,
        position.longitude,
      );
      if (label != null && mounted) {
        setState(() => _locationLabel = label);
        _locationSearch.selected(label);
      }
    } catch (_) {
      // Keep default location.
    }
  }

  @override
  void dispose() {
    _locationSearch.dispose();
    _bgController.dispose();
    super.dispose();
  }

  void _reload() {
    setState(() {
      _future = fetchWeather(_lat, _lng);
    });
  }

  void _selectSearchResult(dynamic result) {
    final lon = double.tryParse('${result['lon']}');
    final lat = double.tryParse('${result['lat']}');
    if (lon == null || lat == null) return;
    final label = (result['display_name'] as String)
        .split(',')
        .take(3)
        .join(',');
    setState(() {
      _lat = lat;
      _lng = lon;
      _locationLabel = label;
    });
    _locationSearch.selected(label);
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? _darkText : _lightText;
    final textMuted = isDark ? _darkTextMuted : _lightTextMuted;
    return FutureBuilder<WeatherData>(
      future: _future,
      builder: (context, snapshot) {
        final temp = snapshot.data?.temperature;
        return AnimatedBuilder(
          animation: _bgController,
          builder: (context, child) {
            return Container(
              decoration: BoxDecoration(
                gradient: _animatedTempGradient(
                  temp,
                  isDark,
                  _bgController.value,
                ),
              ),
              child: child,
            );
          },
          child: SafeArea(
            bottom: false,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                  child: LocationSearchField(
                    controller: _locationSearch,
                    onSelect: _selectSearchResult,
                    hintText: 'Check weather for any place worldwide…',
                  ),
                ),
                Expanded(
                  child: _buildBody(
                    context,
                    snapshot,
                    isDark: isDark,
                    textColor: textColor,
                    textMuted: textMuted,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildBody(
    BuildContext context,
    AsyncSnapshot<WeatherData> snapshot, {
    required bool isDark,
    required Color textColor,
    required Color textMuted,
  }) {
    if (snapshot.connectionState == ConnectionState.waiting) {
      return Center(child: CircularProgressIndicator(color: textColor));
    }
    if (snapshot.hasError) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Could not load weather.',
                style: TextStyle(color: textColor, fontSize: 14),
              ),
              const SizedBox(height: 12),
              FilledButton(onPressed: _reload, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }
    final w = snapshot.data!;
    final stripTint = isDark ? const Color(0xFF15171C) : Colors.white;
    final stripOpacity = isDark ? 0.55 : 0.4;
    return Column(
      children: [
        Expanded(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _locationLabel,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: textColor,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${w.temperature.round()}°',
                  style: TextStyle(
                    color: textColor,
                    fontSize: 96,
                    fontWeight: FontWeight.w800,
                    height: 1,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  weatherCodeDescription(w.weatherCode),
                  style: TextStyle(
                    color: textColor,
                    fontSize: 17,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Feels like ${w.feelsLike.round()}°  •  '
                  'H:${w.temperatureMax.round()}° L:${w.temperatureMin.round()}°',
                  style: TextStyle(
                    color: textMuted,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(
            12,
            0,
            12,
            12 + MediaQuery.of(context).padding.bottom,
          ),
          child: GlassPanel(
            borderRadius: 18,
            tint: stripTint,
            tintOpacity: stripOpacity,
            blurSigma: 20,
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _StripItem(
                        icon: Icons.wb_twilight,
                        label: 'SUNRISE',
                        value: _formatTime(w.sunrise),
                        textColor: textColor,
                        textMuted: textMuted,
                      ),
                    ),
                    Expanded(
                      child: _StripItem(
                        icon: Icons.nights_stay_outlined,
                        label: 'SUNSET',
                        value: _formatTime(w.sunset),
                        textColor: textColor,
                        textMuted: textMuted,
                      ),
                    ),
                    Expanded(
                      child: _StripItem(
                        icon: Icons.timelapse,
                        label: 'SUNSHINE',
                        value: _formatDuration(w.sunshineDuration),
                        textColor: textColor,
                        textMuted: textMuted,
                      ),
                    ),
                    Expanded(
                      child: _StripItem(
                        icon: Icons.wb_sunny,
                        label: 'UV INDEX',
                        value: w.uvIndexMax.toStringAsFixed(1),
                        textColor: textColor,
                        textMuted: textMuted,
                        valueColor: Color(uvIndexCategory(w.uvIndexMax).color),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _StripItem(
                        icon: Icons.thermostat,
                        label: 'FEELS LIKE',
                        value: '${w.feelsLike.round()}°',
                        textColor: textColor,
                        textMuted: textMuted,
                      ),
                    ),
                    Expanded(
                      child: _StripItem(
                        icon: Icons.arrow_upward,
                        label: 'HIGH / LOW',
                        value:
                            '${w.temperatureMax.round()}° / '
                            '${w.temperatureMin.round()}°',
                        textColor: textColor,
                        textMuted: textMuted,
                      ),
                    ),
                    Expanded(
                      child: _StripItem(
                        icon: Icons.water_drop_outlined,
                        label: 'HUMIDITY',
                        value: '${w.humidity}%',
                        textColor: textColor,
                        textMuted: textMuted,
                      ),
                    ),
                    Expanded(
                      child: _StripItem(
                        icon: Icons.air,
                        label: 'WIND',
                        value: '${w.windSpeed.round()} km/h',
                        textColor: textColor,
                        textMuted: textMuted,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Interpolates between a cool teal gradient and a warm orange gradient
/// based on temperature, so the whole card reads "hot" or "cold" at a
/// glance - the same idea classic weather apps use. Falls back to a
/// neutral mid-tone while loading/on error (temp == null). Dark mode uses
/// its own deeper, lower-luminance version of the same two-colour idea
/// (paired with light text) rather than just dimming the light palette.
List<Color> _tempColors(double? tempC, bool isDark) {
  final Color coldTop, coldBottom, hotTop, hotBottom;
  if (isDark) {
    coldTop = const Color(0xFF123842);
    coldBottom = const Color(0xFF090D12);
    hotTop = const Color(0xFF8A3A1C);
    hotBottom = const Color(0xFF1C0E07);
  } else {
    coldTop = const Color(0xFF4FB3BF);
    coldBottom = const Color(0xFFF1FAFB);
    hotTop = const Color(0xFFFF8A50);
    hotBottom = const Color(0xFFFFF3E0);
  }
  final t = tempC == null ? 0.5 : ((tempC - 10) / 20).clamp(0.0, 1.0);
  return [
    Color.lerp(coldTop, hotTop, t)!,
    Color.lerp(coldBottom, hotBottom, t)!,
  ];
}

/// Same temperature-driven colours as [_tempColors], but the gradient
/// itself rotates back and forth by up to ±35 degrees as [sweepT] (0-1,
/// ping-ponging) advances.
///
/// This uses [GradientRotation] rather than moving `begin`/`end` via
/// `Alignment.lerp`: Alignment's x/y are normalised independently to the
/// box's width and height, so on a tall phone screen even a large swing
/// between two mostly-vertical alignments (e.g. the two diagonal corners)
/// barely rotates the *actual rendered* gradient - the projection stays
/// dominated by the screen's height either way. GradientRotation instead
/// rotates the gradient directly in real pixel space, so the angle here is
/// the angle you actually see, regardless of aspect ratio.
LinearGradient _animatedTempGradient(
  double? tempC,
  bool isDark,
  double sweepT,
) {
  final angle = (sweepT - 0.5) * 2 * (math.pi * 35 / 180);
  return LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: _tempColors(tempC, isDark),
    transform: GradientRotation(angle),
  );
}

String _formatTime(DateTime? t) {
  if (t == null) return '--:--';
  return '${pad2(t.hour)}:${pad2(t.minute)}';
}

String _formatDuration(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes % 60;
  return '${h}h ${pad2(m)}m';
}

class _StripItem extends StatelessWidget {
  const _StripItem({
    required this.icon,
    required this.label,
    required this.value,
    required this.textColor,
    required this.textMuted,
    Color? valueColor,
  }) : valueColor = valueColor ?? textColor;

  final IconData icon;
  final String label;
  final String value;
  final Color textColor;
  final Color textMuted;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: textColor, size: 18),
        const SizedBox(height: 6),
        Text(
          value,
          style: TextStyle(
            color: valueColor,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(color: textMuted, fontSize: 8.5, letterSpacing: 0.3),
        ),
      ],
    );
  }
}
