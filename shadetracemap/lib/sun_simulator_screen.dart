import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'device_location.dart';
import 'glass_panel.dart';
import 'location_search.dart';
import 'sun_math.dart';

const _initialUtcOffset = 8; // Asia/Kuala_Lumpur, UTC+8 year-round (no DST)
const _initialLat = 3.1412;
const _initialLng = 101.68653;

// Matches the Weather tab's "hero gradient" treatment: the background is
// tinted live (there by temperature, here by how high the sun currently
// is) - here with a light-mode and dark-mode palette, so it follows system
// light/dark mode like the rest of the app rather than a single fixed look.
const _lightText = Color(0xFF2A2620);
const _lightTextMuted = Color(0x992A2620);
const _darkText = Color(0xFFF3F1EC);
const _darkTextMuted = Color(0x99F3F1EC);

/// A standalone sun-path simulator: no map, just the astronomy. Lets you
/// scrub date/time/location and see the sun's full-day arc (azimuth vs.
/// altitude - the standard "sun path diagram" format used in solar design)
/// plus where "now" sits on it.
class SunSimulatorScreen extends StatefulWidget {
  const SunSimulatorScreen({super.key});

  @override
  State<SunSimulatorScreen> createState() => _SunSimulatorScreenState();
}

class _SunSimulatorScreenState extends State<SunSimulatorScreen> {
  double _lat = _initialLat;
  double _lng = _initialLng;
  int _utcOffsetHours = _initialUtcOffset;
  String _locationLabel = 'Kuala Lumpur, Malaysia';

  late String _dateStr;
  late int _minutes;

  bool _playing = false;
  Timer? _playTimer;

  final _locationSearch = LocationSearchController();

  List<List<double>> _dayPath = const [];
  SunTimes _sunTimes = const SunTimes(null, null);
  String _lastPathKey = '';

  @override
  void initState() {
    super.initState();
    final initialFields = localFieldsFromInstant(
      DateTime.now().millisecondsSinceEpoch,
      _initialUtcOffset,
    );
    _dateStr = dateStrFromFields(initialFields);
    _minutes = initialFields.minutesOfDay;
    _recomputeDayPath();
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
      final offset = approxUtcOffsetHours(position.longitude);
      final nowFields = localFieldsFromInstant(
        DateTime.now().millisecondsSinceEpoch,
        offset,
      );
      setState(() {
        _lat = position.latitude;
        _lng = position.longitude;
        _utcOffsetHours = offset;
        _dateStr = dateStrFromFields(nowFields);
        _minutes = nowFields.minutesOfDay;
        _locationLabel = 'My Location';
      });
      _locationSearch.selected('My Location');
      _recomputeDayPath();
    } catch (_) {
      // Keep default location.
    }
  }

  @override
  void dispose() {
    _playTimer?.cancel();
    _locationSearch.dispose();
    super.dispose();
  }

  int get _currentInstantMs {
    final parts = _dateStr.split('-').map(int.parse).toList();
    return instantFromLocalFields(
      parts[0],
      parts[1],
      parts[2],
      _minutes,
      _utcOffsetHours,
    );
  }

  void _recomputeDayPath() {
    final dayStartMs = localMidnightMs(_currentInstantMs, _utcOffsetHours);
    final key =
        '$dayStartMs@${_lat.toStringAsFixed(2)},${_lng.toStringAsFixed(2)}';
    if (key == _lastPathKey) return;
    _lastPathKey = key;

    final points = <List<double>>[];
    for (var m = 0; m <= 1440; m += 8) {
      final t = DateTime.fromMillisecondsSinceEpoch(
        dayStartMs + m * 60000,
        isUtc: true,
      );
      final pos = sunPosition(t, _lat, _lng);
      points.add([pos.azimuth, pos.altitude]);
    }
    _dayPath = points;
    _sunTimes = findSunriseSunset(dayStartMs, _lat, _lng);
  }

  void _onWallClockOrLocationChanged() {
    setState(_recomputeDayPath);
  }

  Future<void> _pickDate() async {
    final parts = _dateStr.split('-').map(int.parse).toList();
    final initial = DateTime(parts[0], parts[1], parts[2]);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1970),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(
      () =>
          _dateStr = '${picked.year}-${pad2(picked.month)}-${pad2(picked.day)}',
    );
    _onWallClockOrLocationChanged();
  }

  void _togglePlaying() {
    setState(() => _playing = !_playing);
    if (_playing) {
      _playTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
        setState(() => _minutes = (_minutes + 5) % 1440);
      });
    } else {
      _playTimer?.cancel();
      _playTimer = null;
    }
  }

  void _selectSearchResult(dynamic result) {
    final lon = double.tryParse('${result['lon']}');
    final lat = double.tryParse('${result['lat']}');
    if (lon == null || lat == null) return;

    final offset = approxUtcOffsetHours(lon);
    final nowFields = localFieldsFromInstant(
      DateTime.now().millisecondsSinceEpoch,
      offset,
    );
    final label = (result['display_name'] as String)
        .split(',')
        .take(3)
        .join(',');

    setState(() {
      _lat = lat;
      _lng = lon;
      _utcOffsetHours = offset;
      _dateStr = dateStrFromFields(nowFields);
      _minutes = nowFields.minutesOfDay;
      _locationLabel = label;
    });
    _locationSearch.selected(label);
    _recomputeDayPath();
  }

  @override
  Widget build(BuildContext context) {
    final pos = sunPosition(
      DateTime.fromMillisecondsSinceEpoch(_currentInstantMs, isUtc: true),
      _lat,
      _lng,
    );
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final panelTint = isDark ? const Color(0xFF15171C) : Colors.white;
    final onPanel = isDark ? _darkText : _lightText;
    final onPanelMuted = isDark ? _darkTextMuted : _lightTextMuted;
    return Container(
      decoration: BoxDecoration(gradient: _sunTint(pos.altitude, isDark)),
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
              child: LocationSearchField(
                controller: _locationSearch,
                onSelect: _selectSearchResult,
                hintText: 'Simulate any place worldwide…',
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                'Sun path — $_locationLabel',
                style: TextStyle(color: onPanelMuted, fontSize: 12),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: GlassPanel(
                  borderRadius: 16,
                  tint: panelTint,
                  tintOpacity: 0.6,
                  blurSigma: 20,
                  padding: const EdgeInsets.all(12),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return CustomPaint(
                        size: Size(constraints.maxWidth, constraints.maxHeight),
                        painter: _SunPathPainter(
                          path: _dayPath,
                          sunPos: pos,
                          labelColor: onPanelMuted,
                          isDark: isDark,
                        ),
                      );
                    },
                  ),
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
                tint: panelTint,
                tintOpacity: 0.6,
                blurSigma: 20,
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              formatBigTime(_minutes),
                              style: TextStyle(
                                color: onPanel,
                                fontSize: 19,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              _dateStr,
                              style: TextStyle(
                                color: onPanelMuted,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            _RoundIconButton(
                              onTap: _pickDate,
                              icon: Icons.calendar_today,
                              size: 13,
                              isDark: isDark,
                            ),
                            const SizedBox(width: 8),
                            GestureDetector(
                              onTap: _togglePlaying,
                              child: Container(
                                width: 30,
                                height: 30,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF3B7CFF),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(
                                  _playing ? Icons.pause : Icons.play_arrow,
                                  size: 15,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 3,
                        activeTrackColor: const Color(0xFF3B7CFF),
                        inactiveTrackColor: const Color(0x333B7CFF),
                        thumbColor: Colors.white,
                        thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 7.5,
                        ),
                        overlayShape: const RoundSliderOverlayShape(
                          overlayRadius: 16,
                        ),
                      ),
                      child: Slider(
                        min: 0,
                        max: 1439,
                        value: _minutes.toDouble(),
                        onChanged: (v) => setState(() => _minutes = v.round()),
                      ),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _Readout(
                          label: 'ALTITUDE',
                          value: '${pos.altitude.toStringAsFixed(1)}°',
                          muted: onPanelMuted,
                          isDark: isDark,
                        ),
                        _Readout(
                          label: 'AZIMUTH',
                          value: '${pos.azimuth.toStringAsFixed(0)}°',
                          muted: onPanelMuted,
                          isDark: isDark,
                        ),
                        // Clear-sky direct irradiance - the "how strong is
                        // the sun right now" readout, same idea as the
                        // W/m² figures solar-analysis tools like ShadeMap /
                        // Shadowmap surface.
                        _Readout(
                          label: 'IRRADIANCE',
                          value:
                              '${solarIrradianceWm2(pos.altitude).round()} W/m²',
                          muted: onPanelMuted,
                          isDark: isDark,
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _Readout(
                          label: 'SUNRISE',
                          value: _sunTimes.sunrise == null
                              ? '--:--'
                              : '${pad2(_sunTimes.sunrise! ~/ 60)}:${pad2(_sunTimes.sunrise! % 60)}',
                          muted: onPanelMuted,
                          isDark: isDark,
                        ),
                        _Readout(
                          label: 'SUNSET',
                          value: _sunTimes.sunset == null
                              ? '--:--'
                              : '${pad2(_sunTimes.sunset! ~/ 60)}:${pad2(_sunTimes.sunset! % 60)}',
                          muted: onPanelMuted,
                          isDark: isDark,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Readout extends StatelessWidget {
  const _Readout({
    required this.label,
    required this.value,
    required this.muted,
    required this.isDark,
  });
  final String label;
  final String value;
  final Color muted;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(color: muted, fontSize: 9.5, letterSpacing: 0.4),
        ),
        Text(
          value,
          style: TextStyle(
            color: isDark ? const Color(0xFFFFD580) : const Color(0xFFC66A00),
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

/// Interpolates the background between night, golden-hour and midday-sky
/// tones based on the sun's current altitude - the same "tint the whole
/// screen by a live value" idea as the Weather tab's temperature gradient.
/// Two lerps (night->horizon, horizon->zenith) instead of hard cutoffs so
/// the colour shifts smoothly through sunrise/sunset rather than jumping.
/// Dark mode gets its own deeper, lower-luminance palette (paired with
/// light text) instead of just dimming the light one.
LinearGradient _sunTint(double altitude, bool isDark) {
  final Color nightTop, nightBottom;
  final Color horizonTop, horizonBottom;
  final Color zenithTop, zenithBottom;
  if (isDark) {
    nightTop = const Color(0xFF05060B);
    nightBottom = const Color(0xFF12141E);
    horizonTop = const Color(0xFF7A3A1E);
    horizonBottom = const Color(0xFF241209);
    zenithTop = const Color(0xFF17436A);
    zenithBottom = const Color(0xFF0B1B2E);
  } else {
    // A real dusk/night tone (not a washed-out pale blue) while still
    // light enough for the tab's dark-text scheme to stay legible.
    nightTop = const Color(0xFF54628F);
    nightBottom = const Color(0xFFC7CDE4);
    horizonTop = const Color(0xFFFF9E6D);
    horizonBottom = const Color(0xFFFFF1E0);
    zenithTop = const Color(0xFF6EC1F5);
    zenithBottom = const Color(0xFFEAF6FF);
  }

  final Color top, bottom;
  if (altitude <= 8) {
    final t = ((altitude + 10) / 18).clamp(0.0, 1.0);
    top = Color.lerp(nightTop, horizonTop, t)!;
    bottom = Color.lerp(nightBottom, horizonBottom, t)!;
  } else {
    final t = ((altitude - 8) / 52).clamp(0.0, 1.0);
    top = Color.lerp(horizonTop, zenithTop, t)!;
    bottom = Color.lerp(horizonBottom, zenithBottom, t)!;
  }
  return LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [top, bottom],
  );
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({
    required this.onTap,
    required this.icon,
    required this.size,
    required this.isDark,
  });
  final VoidCallback onTap;
  final IconData icon;
  final double size;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 30,
        height: 30,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E2126) : const Color(0xFFE6E8EB),
          border: Border.all(
            color: isDark ? const Color(0xFF3A3F47) : const Color(0xFFCBCFD4),
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, size: size, color: isDark ? _darkText : _lightText),
      ),
    );
  }
}

/// Draws the standard "sun path diagram": azimuth (compass direction) on
/// the X axis, altitude on the Y axis, the current day's full path as a
/// curve, and a marker for wherever "now" sits on it.
class _SunPathPainter extends CustomPainter {
  _SunPathPainter({
    required this.path,
    required this.sunPos,
    required this.labelColor,
    required this.isDark,
  });

  final List<List<double>> path;
  final SunPosition sunPos;
  final Color labelColor;
  final bool isDark;

  static const _minAltitude = -20.0;
  static const _maxAltitude = 90.0;

  double _xFor(double azimuth, double width) => width * (azimuth / 360);
  double _yFor(double altitude, double height) {
    final t = (altitude - _minAltitude) / (_maxAltitude - _minAltitude);
    return height * (1 - t.clamp(0, 1));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final horizonY = _yFor(0, size.height);

    // Sky gradient: warm near the horizon, cooler toward the zenith; dims
    // overall when the sun itself is below the horizon right now.
    final belowHorizon = sunPos.altitude <= 0.5;
    final skyTop = isDark
        ? (belowHorizon ? const Color(0xFF11131A) : const Color(0xFF1B2540))
        : (belowHorizon ? const Color(0xFFD8DEE8) : const Color(0xFFBFE0FF));
    final skyHorizon = isDark
        ? (belowHorizon ? const Color(0xFF232A3D) : const Color(0xFF3A2E45))
        : (belowHorizon ? const Color(0xFFEDEFF3) : const Color(0xFFFFE3C2));

    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [skyTop, skyHorizon],
        ).createShader(Offset.zero & size),
    );

    // Ground below the horizon line.
    canvas.drawRect(
      Rect.fromLTRB(0, horizonY, size.width, size.height),
      Paint()
        ..color = isDark ? const Color(0xFF0C0E12) : const Color(0xFFCED3D9),
    );

    // Altitude gridlines at 0/30/60/90.
    final gridPaint = Paint()
      ..color = labelColor.withValues(alpha: 0.18)
      ..strokeWidth = 1;
    for (final alt in [0.0, 30.0, 60.0, 90.0]) {
      final y = _yFor(alt, size.height);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
      _drawText(canvas, '${alt.toInt()}°', Offset(4, y - 13), labelColor, 9);
    }

    // Compass labels along the horizon.
    for (final entry in {
      0.0: 'N',
      90.0: 'E',
      180.0: 'S',
      270.0: 'W',
      360.0: 'N',
    }.entries) {
      final x = _xFor(entry.key, size.width);
      canvas.drawLine(
        Offset(x, horizonY - 4),
        Offset(x, horizonY + 4),
        Paint()..color = labelColor.withValues(alpha: 0.35),
      );
      _drawText(
        canvas,
        entry.value,
        Offset(x - 4, math.min(horizonY + 8, size.height - 14)),
        labelColor,
        11,
        bold: true,
      );
    }

    // The day's path. Near the equator the sun can cross due north (the
    // azimuth=0/360 branch cut) close to solar noon - that's a tiny real
    // step, not a jump, so instead of just breaking the line there (which
    // left a gap looking like two disconnected curves), extend the outgoing
    // segment to the edge it's heading toward and resume the new one from
    // the opposite edge, at the same altitude, so the wrap reads as one
    // continuous line.
    if (path.length > 1) {
      final linePaint = Paint()
        ..color = const Color(0xFFFFD580)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      Path? segment;
      double? lastAz;
      for (final p in path) {
        final az = p[0], alt = p[1];
        final x = _xFor(az, size.width);
        final y = _yFor(alt, size.height);
        if (segment == null) {
          segment = Path()..moveTo(x, y);
        } else if (lastAz != null && (az - lastAz).abs() > 180) {
          final goingUp = lastAz > az; // e.g. 359 -> 1 really means 359 -> 361
          final edgeAz = goingUp ? 360.0 : 0.0;
          final otherEdgeAz = goingUp ? 0.0 : 360.0;
          segment.lineTo(_xFor(edgeAz, size.width), y);
          canvas.drawPath(segment, linePaint);
          segment = Path()..moveTo(_xFor(otherEdgeAz, size.width), y);
          segment.lineTo(x, y);
        } else {
          segment.lineTo(x, y);
        }
        lastAz = az;
      }
      if (segment != null) canvas.drawPath(segment, linePaint);
    }

    // Current sun position marker.
    final sx = _xFor(sunPos.azimuth, size.width);
    final sy = _yFor(sunPos.altitude, size.height);
    final aboveHorizon = sunPos.altitude > 0.5;
    canvas.drawCircle(
      Offset(sx, sy),
      9,
      Paint()..color = aboveHorizon ? const Color(0xFFFFD580) : Colors.white38,
    );
    canvas.drawCircle(
      Offset(sx, sy),
      9,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.25)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );
    if (aboveHorizon) {
      canvas.drawCircle(
        Offset(sx, sy),
        16,
        Paint()..color = const Color(0xFFFFD580).withValues(alpha: 0.25),
      );
    }
  }

  void _drawText(
    Canvas canvas,
    String text,
    Offset offset,
    Color color,
    double fontSize, {
    bool bold = false,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: bold ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant _SunPathPainter oldDelegate) {
    return oldDelegate.path != path ||
        oldDelegate.sunPos.altitude != sunPos.altitude ||
        oldDelegate.sunPos.azimuth != sunPos.azimuth ||
        oldDelegate.isDark != isDark;
  }
}
