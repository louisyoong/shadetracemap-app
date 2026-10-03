import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'app_style.dart';
import 'device_location.dart';
import 'glass_panel.dart';
import 'location_search.dart';
import 'sun_math.dart';

const _initialUtcOffset = 8; // Asia/Kuala_Lumpur, UTC+8 year-round (no DST)
const _initialLat = 3.1412;
const _initialLng = 101.68653;

/// A standalone sun-path simulator: no map, just the astronomy. Lets you
/// scrub date/time/location and see the sun's full-day journey as a single
/// golden arc from sunrise to sunset (altitude over time, the way Apple
/// Weather/Lumy present a sun-path widget) plus where "now" sits on it.
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

  // Altitude sampled every 8 minutes across the full day (181 points), used
  // to draw the day's sun arc.
  List<double> _dayAltitudes = const [];
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

      // Best-effort follow-up: swap the generic placeholder for a real
      // place name once reverse geocoding resolves, without blocking the
      // sun-path recompute on it.
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

    final altitudes = <double>[];
    for (var m = 0; m <= 1440; m += 8) {
      final t = DateTime.fromMillisecondsSinceEpoch(
        dayStartMs + m * 60000,
        isUtc: true,
      );
      altitudes.add(sunPosition(t, _lat, _lng).altitude);
    }
    _dayAltitudes = altitudes;
    _sunTimes = findSunriseSunset(dayStartMs, _lat, _lng);
  }

  void _onWallClockOrLocationChanged() {
    setState(_recomputeDayPath);
  }

  /// "Xh Ym of daylight" from this day's sunrise/sunset, or null at
  /// latitudes/dates with no sunrise or sunset (polar day/night).
  String? _daylightText() {
    final sunrise = _sunTimes.sunrise;
    final sunset = _sunTimes.sunset;
    if (sunrise == null || sunset == null || sunset <= sunrise) return null;
    final mins = sunset - sunrise;
    return '${mins ~/ 60}h ${pad2(mins % 60)}m of daylight';
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
    final onPanel = textColorFor(isDark);
    final onPanelMuted = textMutedFor(isDark);
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
            Center(
              child: LocationChip(
                label: _locationLabel,
                textColor: onPanel,
                isDark: isDark,
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: GlassPanel(
                  borderRadius: kCardRadius,
                  tint: panelTint,
                  tintOpacity: 0.6,
                  blurSigma: 20,
                  padding: const EdgeInsets.fromLTRB(16, 14, 12, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          SectionLabel('TODAY\'S SUN PATH', color: onPanelMuted),
                          if (_daylightText() case final text?)
                            Text(
                              text,
                              style: TextStyle(
                                color: onPanelMuted,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Expanded(
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            return CustomPaint(
                              size: Size(
                                constraints.maxWidth,
                                constraints.maxHeight,
                              ),
                              painter: _SunArcPainter(
                                altitudes: _dayAltitudes,
                                nowMinutes: _minutes,
                                sunPos: pos,
                                sunTimes: _sunTimes,
                                labelColor: onPanelMuted,
                                isDark: isDark,
                              ),
                            );
                          },
                        ),
                      ),
                    ],
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
                borderRadius: kCardRadius,
                tint: panelTint,
                tintOpacity: 0.6,
                blurSigma: 20,
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
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
                                fontSize: 24,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.5,
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
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Expanded(
                          child: StatTile(
                            icon: Icons.wb_sunny_outlined,
                            label: 'ALTITUDE',
                            value: '${pos.altitude.toStringAsFixed(1)}°',
                            textColor: onPanel,
                            textMuted: onPanelMuted,
                            accent: const Color(0xFFFFB74D),
                          ),
                        ),
                        Expanded(
                          child: StatTile(
                            icon: Icons.explore_outlined,
                            label: 'AZIMUTH',
                            value: '${pos.azimuth.toStringAsFixed(0)}°',
                            textColor: onPanel,
                            textMuted: onPanelMuted,
                            accent: const Color(0xFF3B7CFF),
                          ),
                        ),
                        // Clear-sky direct irradiance - the "how strong is
                        // the sun right now" readout, same idea as the
                        // W/m² figures solar-analysis tools like ShadeMap /
                        // Shadowmap surface.
                        Expanded(
                          child: StatTile(
                            icon: Icons.bolt_outlined,
                            label: 'IRRADIANCE',
                            value:
                                '${solarIrradianceWm2(pos.altitude).round()} W/m²',
                            textColor: onPanel,
                            textMuted: onPanelMuted,
                            accent: const Color(0xFFFFCA28),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: StatTile(
                            icon: Icons.wb_twilight,
                            label: 'SUNRISE',
                            value: _sunTimes.sunrise == null
                                ? '--:--'
                                : '${pad2(_sunTimes.sunrise! ~/ 60)}:${pad2(_sunTimes.sunrise! % 60)}',
                            textColor: onPanel,
                            textMuted: onPanelMuted,
                            accent: const Color(0xFFFFB74D),
                          ),
                        ),
                        Expanded(
                          child: StatTile(
                            icon: Icons.nights_stay_outlined,
                            label: 'SUNSET',
                            value: _sunTimes.sunset == null
                                ? '--:--'
                                : '${pad2(_sunTimes.sunset! ~/ 60)}:${pad2(_sunTimes.sunset! % 60)}',
                            textColor: onPanel,
                            textMuted: onPanelMuted,
                            accent: const Color(0xFF8B93FF),
                          ),
                        ),
                        const Expanded(child: SizedBox()),
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
        child: Icon(icon, size: size, color: textColorFor(isDark)),
      ),
    );
  }
}

enum _HAlign { left, center }

/// Draws the day's "sun arc": altitude over the course of the day as one
/// dome-shaped golden curve from sunrise to sunset - the same idea Apple
/// Weather/Lumy use for their own sun-path widgets - with the currently
/// scrubbed time marked as a glowing dot on it. Reads at a glance without
/// needing to parse a technical azimuth-vs-altitude chart, while still
/// driven by the same real per-minute altitude samples the old chart used.
class _SunArcPainter extends CustomPainter {
  _SunArcPainter({
    required this.altitudes,
    required this.nowMinutes,
    required this.sunPos,
    required this.sunTimes,
    required this.labelColor,
    required this.isDark,
  });

  /// Altitude sampled every [_stepMinutes] minutes across the day.
  final List<double> altitudes;
  final int nowMinutes;
  final SunPosition sunPos;
  final SunTimes sunTimes;
  final Color labelColor;
  final bool isDark;

  static const _stepMinutes = 8;
  static const _minAltitude = -16.0;

  @override
  void paint(Canvas canvas, Size size) {
    if (altitudes.isEmpty) return;

    // Scale the vertical axis to this day's own peak (with headroom) rather
    // than a fixed 0-90, so the dome always fills the card nicely whether
    // it's the tropics (sun near-overhead) or a high latitude (sun always
    // low) instead of looking cramped or oversized.
    var peak = 10.0;
    for (final a in altitudes) {
      if (a > peak) peak = a;
    }
    final maxAltitude = peak + 12;

    double xFor(int minutes) => size.width * (minutes / 1440);
    double yFor(double altitude) {
      final t = (altitude - _minAltitude) / (maxAltitude - _minAltitude);
      return size.height * (1 - t.clamp(0.0, 1.0));
    }

    final horizonY = yFor(0);

    // Sky fill: warm near the horizon, cooler toward the top; dims overall
    // when the scrubbed instant itself is below the horizon.
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
    canvas.drawRect(
      Rect.fromLTRB(0, horizonY, size.width, size.height),
      Paint()
        ..color = isDark ? const Color(0xFF0C0E12) : const Color(0xFFCED3D9),
    );

    // Hour ticks every 6 hours along the horizon (12A/6A/12P/6P) - plain
    // clock time instead of compass bearings, so reading the chart doesn't
    // require knowing which way is east.
    for (var m = 0; m <= 1440; m += 360) {
      final x = xFor(m);
      canvas.drawLine(
        Offset(x, horizonY - 3),
        Offset(x, horizonY + 3),
        Paint()..color = labelColor.withValues(alpha: 0.3),
      );
      _drawText(
        canvas,
        _hourLabel(m),
        Offset(x, math.min(horizonY + 8, size.height - 12)),
        labelColor.withValues(alpha: 0.75),
        9.5,
        align: _HAlign.center,
      );
    }

    // Split the day into contiguous "above horizon" / "below horizon" runs
    // so each draws as one continuous stroke - matters at high latitudes
    // where a day can have more than one sunrise/sunset crossing, or none.
    final dayRuns = <List<Offset>>[];
    final nightRuns = <List<Offset>>[];
    List<Offset>? currentDay;
    List<Offset>? currentNight;
    for (var m = 0; m <= 1440; m += _stepMinutes) {
      final alt = altitudes[(m ~/ _stepMinutes).clamp(0, altitudes.length - 1)];
      final pt = Offset(xFor(m), yFor(alt));
      if (alt >= 0) {
        (currentDay ??= []).add(pt);
        if (currentNight != null) {
          nightRuns.add(currentNight);
          currentNight = null;
        }
      } else {
        (currentNight ??= []).add(pt);
        if (currentDay != null) {
          dayRuns.add(currentDay);
          currentDay = null;
        }
      }
    }
    if (currentDay != null) dayRuns.add(currentDay);
    if (currentNight != null) nightRuns.add(currentNight);

    // A faint night dip so the arc still reads as one continuous day/night
    // cycle rather than the curve simply stopping at the horizon.
    final nightPaint = Paint()
      ..color = (isDark ? Colors.white : Colors.black).withValues(alpha: 0.16)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;
    for (final run in nightRuns) {
      if (run.length < 2) continue;
      final line = Path()..moveTo(run.first.dx, run.first.dy);
      for (final pt in run.skip(1)) {
        line.lineTo(pt.dx, pt.dy);
      }
      canvas.drawPath(line, nightPaint);
    }

    // The golden daylight dome: a soft fill underneath plus a warm gradient
    // stroke along its length.
    for (final run in dayRuns) {
      if (run.length < 2) continue;
      final stroke = Path()..moveTo(run.first.dx, run.first.dy);
      for (final pt in run.skip(1)) {
        stroke.lineTo(pt.dx, pt.dy);
      }
      final fill = Path.from(stroke)
        ..lineTo(run.last.dx, horizonY)
        ..lineTo(run.first.dx, horizonY)
        ..close();
      final bounds = Rect.fromLTRB(run.first.dx, 0, run.last.dx, horizonY);
      canvas.drawPath(
        fill,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              const Color(0xFFFFD580).withValues(alpha: isDark ? 0.22 : 0.32),
              const Color(0xFFFFD580).withValues(alpha: 0.0),
            ],
          ).createShader(bounds),
      );
      canvas.drawPath(
        stroke,
        Paint()
          ..shader = const LinearGradient(
            colors: [Color(0xFFFFB74D), Color(0xFFFFE0A3)],
          ).createShader(bounds)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }

    _drawEdgeMarker(
      canvas,
      sunTimes.sunrise,
      horizonY,
      xFor,
      Icons.wb_twilight,
      const Color(0xFFFFB74D),
      labelColor,
    );
    _drawEdgeMarker(
      canvas,
      sunTimes.sunset,
      horizonY,
      xFor,
      Icons.nights_stay_outlined,
      const Color(0xFF8B93FF),
      labelColor,
    );

    // Current position: a glowing marker plus a thin guide line down to the
    // horizon, so it's obvious where "now" sits along the whole day.
    final nowX = xFor(nowMinutes);
    final nowY = yFor(sunPos.altitude);
    final aboveHorizon = sunPos.altitude > 0.5;
    canvas.drawLine(
      Offset(nowX, nowY),
      Offset(nowX, horizonY),
      Paint()
        ..color = (aboveHorizon ? const Color(0xFFFFB74D) : labelColor)
            .withValues(alpha: 0.35)
        ..strokeWidth = 1.2,
    );
    if (aboveHorizon) {
      canvas.drawCircle(
        Offset(nowX, nowY),
        16,
        Paint()..color = const Color(0xFFFFD580).withValues(alpha: 0.3),
      );
    }
    canvas.drawCircle(
      Offset(nowX, nowY),
      8,
      Paint()..color = aboveHorizon ? const Color(0xFFFFD580) : Colors.white38,
    );
    canvas.drawCircle(
      Offset(nowX, nowY),
      8,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.25)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );
  }

  /// A small labelled marker at the horizon for sunrise/sunset, with an
  /// icon inside so the two ends of the arc are identifiable without
  /// reading the time label - same painted-icon technique the compass
  /// dial's sun/moon marker uses.
  void _drawEdgeMarker(
    Canvas canvas,
    int? minutes,
    double horizonY,
    double Function(int) xFor,
    IconData icon,
    Color accent,
    Color labelColor,
  ) {
    if (minutes == null) return;
    final center = Offset(xFor(minutes), horizonY);
    canvas.drawCircle(center, 11, Paint()..color = accent);
    canvas.drawCircle(
      center,
      11,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.85)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4,
    );
    final iconPainter = TextPainter(textDirection: TextDirection.ltr)
      ..text = TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          fontSize: 12,
          fontFamily: icon.fontFamily,
          package: icon.fontPackage,
          color: Colors.white,
        ),
      )
      ..layout();
    iconPainter.paint(
      canvas,
      center - Offset(iconPainter.width / 2, iconPainter.height / 2),
    );
    _drawText(
      canvas,
      '${pad2(minutes ~/ 60)}:${pad2(minutes % 60)}',
      Offset(center.dx, horizonY + 15),
      labelColor,
      9.5,
      bold: true,
      align: _HAlign.center,
    );
  }

  String _hourLabel(int minutes) {
    final h = minutes ~/ 60;
    if (h == 0 || h == 24) return '12A';
    if (h == 12) return '12P';
    return h < 12 ? '${h}A' : '${h - 12}P';
  }

  void _drawText(
    Canvas canvas,
    String text,
    Offset offset,
    Color color,
    double fontSize, {
    bool bold = false,
    _HAlign align = _HAlign.left,
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
    final dx = align == _HAlign.center
        ? offset.dx - painter.width / 2
        : offset.dx;
    painter.paint(canvas, Offset(dx, offset.dy));
  }

  @override
  bool shouldRepaint(covariant _SunArcPainter oldDelegate) {
    return oldDelegate.altitudes != altitudes ||
        oldDelegate.nowMinutes != nowMinutes ||
        oldDelegate.sunPos.altitude != sunPos.altitude ||
        oldDelegate.isDark != isDark;
  }
}
