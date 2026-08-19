import 'dart:math' as math;
import 'package:flutter/material.dart';

const maxShadowLen = 320.0;
const coreMaxOpacity = 0.6;
const softMaxOpacity = 0.25;

double toRad(double d) => d * math.pi / 180;
double toDeg(double r) => r * 180 / math.pi;

double norm360(double d) {
  d = d % 360;
  if (d < 0) d += 360;
  return d;
}

double clampD(double v, double lo, double hi) => math.max(lo, math.min(hi, v));

String pad2(int n) => n < 10 ? '0$n' : '$n';

class SunPosition {
  const SunPosition(this.altitude, this.azimuth);
  final double altitude;
  final double azimuth;
}

/// Low-precision astronomical solar position (altitude/azimuth) for a given
/// instant, latitude and longitude. Accurate to a few arc-minutes - plenty
/// for a visual demo. [instant] must represent the correct absolute instant
/// (its millisecondsSinceEpoch is used directly, same as JS's Date.getTime).
SunPosition sunPosition(DateTime instant, double lat, double lon) {
  final jd = instant.millisecondsSinceEpoch / 86400000 + 2440587.5;
  final n = jd - 2451545.0;

  final l = norm360(280.46 + 0.9856474 * n);
  final g = norm360(357.528 + 0.9856003 * n);
  final lambda = norm360(
    l + 1.915 * math.sin(toRad(g)) + 0.02 * math.sin(toRad(2 * g)),
  );
  final eps = 23.439 - 0.0000004 * n;

  final alpha = norm360(
    toDeg(
      math.atan2(
        math.cos(toRad(eps)) * math.sin(toRad(lambda)),
        math.cos(toRad(lambda)),
      ),
    ),
  );
  final delta = toDeg(
    math.asin(math.sin(toRad(eps)) * math.sin(toRad(lambda))),
  );

  final gmst = norm360(280.46061837 + 360.98564736629 * n);
  final h = norm360(gmst + lon - alpha);
  final hn = h > 180 ? h - 360 : h;

  final latR = toRad(lat), deltaR = toRad(delta), hr = toRad(hn);
  final altitude = toDeg(
    math.asin(
      math.sin(latR) * math.sin(deltaR) +
          math.cos(latR) * math.cos(deltaR) * math.cos(hr),
    ),
  );
  final azimuth = norm360(
    toDeg(
          math.atan2(
            math.sin(hr),
            math.cos(hr) * math.sin(latR) - math.tan(deltaR) * math.cos(latR),
          ),
        ) +
        180,
  );

  return SunPosition(altitude, azimuth);
}

/// Approximate clear-sky direct solar irradiance (W/m²) hitting a surface
/// perpendicular to the sun, for a given sun altitude. Uses the Meinel &
/// Meinel clear-sky model (extraterrestrial constant attenuated by air
/// mass) - a standard textbook approximation good for a visual demo, not
/// an accurate energy-yield calculation (no clouds, aerosols, elevation,
/// or ground-tilt are accounted for).
double solarIrradianceWm2(double altitudeDeg) {
  if (altitudeDeg <= 0) return 0;
  const solarConstant = 1353.0;
  final airMass = 1 / math.sin(toRad(altitudeDeg));
  return solarConstant * math.pow(0.7, math.pow(airMass, 0.678));
}

class SunTimes {
  const SunTimes(this.sunrise, this.sunset);
  final int? sunrise;
  final int? sunset;
}

/// [dayStartMs] must be the absolute instant of local midnight at the
/// location (see localMidnightMs) - not the device's own midnight.
SunTimes findSunriseSunset(int dayStartMs, double lat, double lon) {
  double? last;
  int? sunrise;
  int? sunset;
  for (var m = 0; m <= 1440; m += 5) {
    final t = DateTime.fromMillisecondsSinceEpoch(
      dayStartMs + m * 60000,
      isUtc: true,
    );
    final alt = sunPosition(t, lat, lon).altitude;
    if (last != null) {
      if (last <= 0 && alt > 0 && sunrise == null) sunrise = m;
      if (last > 0 && alt <= 0 && sunset == null) sunset = m;
    }
    last = alt;
  }
  return SunTimes(sunrise, sunset);
}

// ---- Geo helpers ----
const _earthR = 6378137.0;

List<double> metersToLngLat(double cLng, double cLat, double dxE, double dyN) {
  final dLat = (dyN / _earthR) * (180 / math.pi);
  final dLng =
      (dxE / (_earthR * math.cos(math.pi * cLat / 180))) * (180 / math.pi);
  return [cLng + dLng, cLat + dLat];
}

List<double> offsetPoint(
  double lng,
  double lat,
  double distM,
  double bearingDeg,
) {
  final rad = toRad(bearingDeg);
  return metersToLngLat(lng, lat, distM * math.sin(rad), distM * math.cos(rad));
}

/// Andrew's monotone chain convex hull. Points and result are [lng, lat] pairs.
List<List<double>> convexHull(List<List<double>> points) {
  final pts = points.toList()
    ..sort((a, b) {
      final c = a[0].compareTo(b[0]);
      return c != 0 ? c : a[1].compareTo(b[1]);
    });
  if (pts.length < 3) return pts;

  double cross(List<double> o, List<double> a, List<double> b) =>
      (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0]);

  final lower = <List<double>>[];
  for (final p in pts) {
    while (lower.length >= 2 &&
        cross(lower[lower.length - 2], lower[lower.length - 1], p) <= 0) {
      lower.removeLast();
    }
    lower.add(p);
  }
  final upper = <List<double>>[];
  for (var i = pts.length - 1; i >= 0; i--) {
    final p = pts[i];
    while (upper.length >= 2 &&
        cross(upper[upper.length - 2], upper[upper.length - 1], p) <= 0) {
      upper.removeLast();
    }
    upper.add(p);
  }
  upper.removeLast();
  lower.removeLast();
  return lower + upper;
}

double buildingHeightOf(Map<String, dynamic>? props) {
  props ??= const {};
  num? h;
  if (props['render_height'] != null) {
    h = props['render_height'] as num;
  } else if (props['height'] != null) {
    h = props['height'] as num;
  } else if (props['levels'] != null) {
    h = (props['levels'] as num) * 3;
  }
  var height = h?.toDouble() ?? 12.0;
  if (height <= 0) height = 12.0;
  return height;
}

// ---- Location-local wall-clock helpers ----
// There's no timezone database, so a location's UTC offset is approximated
// from its longitude (15 degrees of longitude ~= 1 hour). This is wrong near
// political timezone boundaries and ignores DST, but it keeps the displayed
// clock roughly matching the sun instead of silently reusing the device's own
// timezone for every location on Earth.
int approxUtcOffsetHours(double lon) =>
    clampD((lon / 15).roundToDouble(), -12, 14).toInt();

class LocalFields {
  const LocalFields(this.year, this.month, this.day, this.minutesOfDay);
  final int year;
  final int month; // 1-based, matches DateTime.month
  final int day;
  final int minutesOfDay;
}

/// Reads what the wall clock at [offsetHours] shows at absolute [instantMs],
/// using UTC getters so the result never depends on the device's own zone.
LocalFields localFieldsFromInstant(int instantMs, int offsetHours) {
  final shifted = DateTime.fromMillisecondsSinceEpoch(
    instantMs + offsetHours * 3600000,
    isUtc: true,
  );
  return LocalFields(
    shifted.year,
    shifted.month,
    shifted.day,
    shifted.hour * 60 + shifted.minute,
  );
}

String dateStrFromFields(LocalFields f) =>
    '${f.year}-${pad2(f.month)}-${pad2(f.day)}';

/// Inverse of [localFieldsFromInstant]: given a location-local wall-clock
/// date + minute-of-day, returns the true absolute instant (ms).
int instantFromLocalFields(
  int year,
  int month,
  int day,
  int minutesOfDay,
  int offsetHours,
) {
  final midnightUtc = DateTime.utc(year, month, day).millisecondsSinceEpoch;
  return midnightUtc + minutesOfDay * 60000 - offsetHours * 3600000;
}

/// Absolute instant of the most recent local midnight at [offsetHours],
/// computed arithmetically so it never depends on the device's own zone.
int localMidnightMs(int instantMs, int offsetHours) {
  const dayMs = 86400000;
  final shifted = instantMs + offsetHours * 3600000;
  return (shifted / dayMs).floor() * dayMs - offsetHours * 3600000;
}

String formatBigTime(int mins) {
  final h = mins ~/ 60, m = mins % 60;
  final display = h % 12 == 0 ? 12 : h % 12;
  return '$display:${pad2(m)} ${h < 12 ? 'AM' : 'PM'}';
}

/// Builds the day/night/twilight gradient for the time-of-day slider track,
/// mirroring the web app's CSS linear-gradient stop layout. [windowStart]
/// and [windowSpan] (both in minutes-of-day) let the track represent a
/// zoomed-in slice of the day rather than the full 0-1440 range - the
/// dawn/dusk transition bands stay a fixed width in minutes, so zooming in
/// spreads them out over more of the visible track, same as zooming a map.
LinearGradient buildDayGradient(
  int? sunrise,
  int? sunset, {
  bool isDark = true,
  double windowStart = 0,
  double windowSpan = 1440,
}) {
  // Sun times not resolved yet - approximate with the same 29%/81% of-day
  // fallback the slider used before real sunrise/sunset were available.
  final sr = (sunrise ?? (0.29 * 1440).round()).toDouble();
  final ss = (sunset ?? (0.81 * 1440).round()).toDouble();
  const night = Color(0xFF171F38);
  const dawnDusk1 = Color(0xFFFFCF94);
  // The pale "day" blue reads fine against the bottom bar's dark glass, but
  // all but disappears against the light-mode panel's near-white
  // background - use a more saturated blue there for the same contrast.
  final day = isDark ? const Color(0xFFBFE4FF) : const Color(0xFF3D7FC4);
  const dawnDusk2 = Color(0xFFFFB877);

  // Original stops were expressed as ±2/±6 percentage-points of the day
  // (i.e. of 1440 minutes) - keep that same absolute-minutes softness
  // regardless of how much of the day the window currently covers.
  const softNear = 0.02 * 1440;
  const softFar = 0.06 * 1440;
  double frac(double mins) =>
      ((mins - windowStart) / windowSpan).clamp(0.0, 1.0);

  final stops = <double>[
    0,
    frac(sr - softNear),
    frac(sr),
    frac(sr + softFar),
    frac(ss - softFar),
    frac(ss),
    frac(ss + softNear),
    1,
  ];
  // Stops must be non-decreasing for LinearGradient; clamp any inversion
  // that can occur with extreme/near-polar sunrise-sunset values.
  for (var i = 1; i < stops.length; i++) {
    if (stops[i] < stops[i - 1]) stops[i] = stops[i - 1];
  }
  return LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [night, night, dawnDusk1, day, day, dawnDusk2, night, night],
    stops: stops,
  );
}
