import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_compass/flutter_compass.dart';

import 'app_style.dart';
import 'device_location.dart';
import 'glass_panel.dart';
import 'location_search.dart' show reverseGeocodeLabel;
import 'sun_math.dart';

const _initialLat = 3.1412;
const _initialLng = 101.68653;

/// A live sun-finding compass: as the phone turns, the sun's marker slides
/// around the dial to always point at its real-world direction, using the
/// device's magnetometer heading plus the sun's azimuth computed for the
/// phone's current location and the current instant.
///
/// Unlike the other location-aware tabs, this one has no search field or
/// date/time control - a physical compass only makes sense for "here, right
/// now", so it always tracks the device's live location and clock instead
/// of letting either be overridden.
class CompassScreen extends StatefulWidget {
  const CompassScreen({super.key});

  @override
  State<CompassScreen> createState() => _CompassScreenState();
}

class _CompassScreenState extends State<CompassScreen>
    with TickerProviderStateMixin {
  double _lat = _initialLat;
  double _lng = _initialLng;
  String _locationLabel = 'Kuala Lumpur, Malaysia';

  StreamSubscription<CompassEvent>? _compassSub;
  double? _heading;
  bool _compassUnavailable = false;
  Timer? _compassTimeoutTimer;

  Timer? _clockTimer;
  DateTime _now = DateTime.now();

  // Edge-triggered so the phone buzzes once on the moment you swing into
  // alignment rather than continuously the whole time you hold it there.
  bool _wasFacingSun = false;

  // Slowly sweeps the background gradient's axis back and forth so the
  // backdrop reads as gently alive instead of a flat, static wash - see
  // _combinedBackground.
  late final AnimationController _bgController = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 10),
  )..repeat(reverse: true);

  // 0 (not facing) to 1 (facing) - cross-fades the backdrop from its normal
  // sky tint to a warm orange/yellow "found it" glow, driven forward/back
  // by _updateFacingEffects whenever the facing state changes.
  late final AnimationController _facingGlowController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 450),
  );

  // Continuously breathes the warm glow's brightness in and out while it's
  // visible, so it reads as radiating sunlight rather than a flat tint.
  late final AnimationController _sunPulseController = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 3),
  )..repeat(reverse: true);

  @override
  void initState() {
    super.initState();
    _detectDeviceLocation();
    _listenToCompass();
    // Sun position drifts slowly - a cheap periodic recompute of "now" is
    // plenty to keep the readout current without a per-frame rebuild.
    _clockTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (!mounted) return;
      setState(() => _now = DateTime.now());
      _updateFacingEffects();
    });
  }

  void _listenToCompass() {
    final events = FlutterCompass.events;
    if (events == null) {
      setState(() => _compassUnavailable = true);
      return;
    }
    _compassSub = events.listen((event) {
      if (!mounted || event.heading == null) return;
      setState(() {
        _heading = event.heading;
        _compassUnavailable = false;
      });
      _updateFacingEffects();
    });
    // A real device with a magnetometer emits a reading almost immediately;
    // a simulator (or a device without one) never will, so time out into a
    // clearly-labelled fallback instead of sitting on an empty dial forever.
    _compassTimeoutTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _heading == null) {
        setState(() => _compassUnavailable = true);
      }
    });
  }

  // Best-effort: silently keep the Kuala Lumpur default if the device
  // won't give up a location - this runs automatically on open, so it
  // shouldn't interrupt the user with an error for something they didn't
  // explicitly ask for.
  Future<void> _detectDeviceLocation() async {
    try {
      final position = await resolveDeviceLocation();
      if (!mounted) return;
      setState(() {
        _lat = position.latitude;
        _lng = position.longitude;
        _locationLabel = 'My Location';
      });
      _updateFacingEffects();
      final label = await reverseGeocodeLabel(
        position.latitude,
        position.longitude,
      );
      if (label != null && mounted) {
        setState(() => _locationLabel = label);
      }
    } catch (_) {
      // Keep default location.
    }
  }

  /// Whether the phone is currently pointed at the sun (within a 12-degree
  /// tolerance either side), and by how much it's off if not - shared by
  /// the on-screen message and the haptic trigger so they never disagree.
  ({double diff, bool facing}) _facingInfo(SunPosition pos) {
    if (pos.altitude <= 0.5 || _heading == null) {
      return (diff: 0, facing: false);
    }
    final diff = (norm360(pos.azimuth - _heading!) + 180) % 360 - 180;
    return (diff: diff, facing: diff.abs() <= 12);
  }

  /// Recomputes whether the phone is facing the sun and reacts to a change:
  /// a haptic buzz on the rising edge, and cross-fading the backdrop into
  /// (or out of) the warm "found it" glow via [_facingGlowController].
  void _updateFacingEffects() {
    final pos = sunPosition(DateTime.now(), _lat, _lng);
    final facing = _facingInfo(pos).facing;
    if (facing && !_wasFacingSun) {
      HapticFeedback.mediumImpact();
      Future.delayed(const Duration(milliseconds: 120), () {
        if (mounted) HapticFeedback.lightImpact();
      });
    }
    if (facing) {
      _facingGlowController.forward();
    } else {
      _facingGlowController.reverse();
    }
    _wasFacingSun = facing;
  }

  @override
  void dispose() {
    _compassSub?.cancel();
    _compassTimeoutTimer?.cancel();
    _clockTimer?.cancel();
    _bgController.dispose();
    _facingGlowController.dispose();
    _sunPulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = textColorFor(isDark);
    final textMuted = textMutedFor(isDark);

    final pos = sunPosition(_now, _lat, _lng);
    final dayStartMs = localMidnightMs(
      _now.millisecondsSinceEpoch,
      approxUtcOffsetHours(_lng),
    );
    final sunTimes = findSunriseSunset(dayStartMs, _lat, _lng);
    final aboveHorizon = pos.altitude > 0.5;

    String facingMessage;
    if (!aboveHorizon) {
      facingMessage = 'Sun is below the horizon right now.';
    } else if (_heading == null) {
      facingMessage = 'Sun is at ${pos.azimuth.round()}° from true north.';
    } else {
      final info = _facingInfo(pos);
      if (info.facing) {
        facingMessage = "You're facing the sun.";
      } else {
        facingMessage =
            'Turn ${info.diff > 0 ? 'right' : 'left'} ${info.diff.abs().round()}° to face the sun.';
      }
    }

    return AnimatedBuilder(
      animation: Listenable.merge([
        _bgController,
        _facingGlowController,
        _sunPulseController,
      ]),
      builder: (context, child) {
        return Container(
          decoration: BoxDecoration(
            gradient: _combinedBackground(
              altitude: pos.altitude,
              isDark: isDark,
              sweepT: _bgController.value,
              facingT: _facingGlowController.value,
              pulseT: _sunPulseController.value,
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
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: Center(
                child: LocationChip(
                  label: _locationLabel,
                  textColor: textColor,
                  isDark: isDark,
                ),
              ),
            ),
            Expanded(
              child: Center(
                // Scoped to its own AnimatedBuilder (rather than relying on
                // the outer one) so only this small halo+dial subtree
                // repaints on the glow/pulse ticks, instead of every frame
                // rebuilding the whole screen's readouts and text too.
                child: AnimatedBuilder(
                  animation: Listenable.merge([
                    _facingGlowController,
                    _sunPulseController,
                  ]),
                  builder: (context, _) {
                    return Stack(
                      alignment: Alignment.center,
                      children: [
                        if (_facingGlowController.value > 0)
                          Opacity(
                            opacity: _facingGlowController.value,
                            child: Container(
                              width: 300 + 50 * _sunPulseController.value,
                              height: 300 + 50 * _sunPulseController.value,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: RadialGradient(
                                  colors: [
                                    const Color(
                                      0xFFFFD54F,
                                    ).withValues(alpha: 0.45),
                                    const Color(
                                      0xFFFFD54F,
                                    ).withValues(alpha: 0.0),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        _CompassDial(
                          heading: _heading,
                          sunAzimuth: pos.azimuth,
                          sunAboveHorizon: aboveHorizon,
                          isDark: isDark,
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (aboveHorizon && _heading != null)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Icon(
                        _facingInfo(pos).facing
                            ? Icons.check_circle_rounded
                            : Icons.navigation_rounded,
                        size: 15,
                        color: textColor,
                      ),
                    ),
                  Flexible(
                    child: Text(
                      facingMessage,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: textColor,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (_compassUnavailable) ...[
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  'No live compass sensor detected (simulators don\'t have '
                  'one) - showing the sun\'s bearing from true north instead.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: textMuted, fontSize: 11.5),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Padding(
              padding: EdgeInsets.fromLTRB(
                12,
                0,
                12,
                12 + MediaQuery.of(context).padding.bottom,
              ),
              child: GlassPanel(
                borderRadius: kCardRadius,
                tint: isDark ? const Color(0xFF15171C) : Colors.white,
                tintOpacity: isDark ? 0.55 : 0.4,
                blurSigma: 20,
                padding: const EdgeInsets.symmetric(
                  vertical: 18,
                  horizontal: 8,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: StatTile(
                        icon: Icons.wb_sunny_outlined,
                        label: 'ALTITUDE',
                        value: '${pos.altitude.toStringAsFixed(1)}°',
                        textColor: textColor,
                        textMuted: textMuted,
                        accent: const Color(0xFFFFB74D),
                      ),
                    ),
                    Expanded(
                      child: StatTile(
                        icon: Icons.explore_outlined,
                        label: 'SUN AZIMUTH',
                        value: '${pos.azimuth.toStringAsFixed(0)}°',
                        textColor: textColor,
                        textMuted: textMuted,
                        accent: const Color(0xFF3B7CFF),
                      ),
                    ),
                    Expanded(
                      child: StatTile(
                        icon: Icons.navigation_outlined,
                        label: 'HEADING',
                        value: _heading == null
                            ? '--°'
                            : '${_heading!.toStringAsFixed(0)}°',
                        textColor: textColor,
                        textMuted: textMuted,
                        accent: const Color(0xFF7E57C2),
                      ),
                    ),
                    Expanded(
                      child: StatTile(
                        icon: Icons.nights_stay_outlined,
                        label: 'SUNSET',
                        value: sunTimes.sunset == null
                            ? '--:--'
                            : '${pad2(sunTimes.sunset! ~/ 60)}:${pad2(sunTimes.sunset! % 60)}',
                        textColor: textColor,
                        textMuted: textMuted,
                        accent: const Color(0xFF8B93FF),
                      ),
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

/// Interpolates the background exactly like the Sun Simulator tab's own sky
/// tint, so both "sun" screens feel like one family instead of one having a
/// gradient backdrop and the other a flat one.
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

/// Builds the compass backdrop from three independent inputs:
///  - the normal altitude-driven day/night colours ([_sunTint])
///  - [sweepT] (0-1, ping-ponging): slowly sweeps the gradient's axis back
///    and forth so the backdrop reads as gently alive rather than a flat,
///    static wash
///  - [facingT] (0-1): cross-fades the whole thing into a warm orange/yellow
///    "found it" glow once the phone lines up with the sun, itself gently
///    breathing via [pulseT] (0-1, ping-ponging) so it radiates rather than
///    sitting as a flat tint
LinearGradient _combinedBackground({
  required double altitude,
  required bool isDark,
  required double sweepT,
  required double facingT,
  required double pulseT,
}) {
  final base = _sunTint(altitude, isDark);

  final warmTop = Color.lerp(
    const Color(0xFFFFC107),
    const Color(0xFFFFECB3),
    pulseT,
  )!;
  final warmBottom = Color.lerp(
    const Color(0xFFFF6F00),
    const Color(0xFFFFB300),
    pulseT,
  )!;

  final top = Color.lerp(base.colors[0], warmTop, facingT)!;
  final bottom = Color.lerp(base.colors[1], warmBottom, facingT)!;

  final begin = Alignment.lerp(
    Alignment.topCenter,
    const Alignment(-0.35, -1),
    sweepT,
  )!;
  final end = Alignment.lerp(
    Alignment.bottomCenter,
    const Alignment(0.35, 1),
    sweepT,
  )!;
  return LinearGradient(begin: begin, end: end, colors: [top, bottom]);
}

class _CompassDial extends StatelessWidget {
  const _CompassDial({
    required this.heading,
    required this.sunAzimuth,
    required this.sunAboveHorizon,
    required this.isDark,
  });

  final double? heading;
  final double sunAzimuth;
  final bool sunAboveHorizon;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 288,
      height: 288,
      child: CustomPaint(
        painter: _CompassDialPainter(
          heading: heading ?? 0,
          hasLiveHeading: heading != null,
          sunAzimuth: sunAzimuth,
          sunAboveHorizon: sunAboveHorizon,
          isDark: isDark,
        ),
      ),
    );
  }
}

class _CompassDialPainter extends CustomPainter {
  _CompassDialPainter({
    required this.heading,
    required this.hasLiveHeading,
    required this.sunAzimuth,
    required this.sunAboveHorizon,
    required this.isDark,
  });

  final double heading;
  final bool hasLiveHeading;
  final double sunAzimuth;
  final bool sunAboveHorizon;
  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2;

    final dialFill = isDark
        ? const Color(0xFF15171C).withValues(alpha: 0.5)
        : Colors.white.withValues(alpha: 0.55);
    final ringColor = isDark
        ? Colors.white.withValues(alpha: 0.16)
        : Colors.black.withValues(alpha: 0.12);
    final tickColor = isDark
        ? Colors.white.withValues(alpha: 0.35)
        : Colors.black.withValues(alpha: 0.28);
    final labelColor = isDark
        ? const Color(0xFFDFE3E8)
        : const Color(0xFF52575E);
    final northAccent = isDark
        ? const Color(0xFFFF8A7A)
        : const Color(0xFFE04B36);
    final pointerColor = isDark
        ? const Color(0xFF6FB2FF)
        : const Color(0xFF3B7CFF);

    canvas.drawCircle(center, radius, Paint()..color = dialFill);
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = ringColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    // 0° (north) sits at the top of the dial and rotates with -heading, so
    // whatever absolute bearing the phone currently faces always reads at
    // the top - the same convention every map/compass app uses.
    double angleFor(double bearing) => toRad(bearing - heading - 90);
    Offset pointOn(double bearing, double r) {
      final a = angleFor(bearing);
      return center + Offset(math.cos(a), math.sin(a)) * r;
    }

    // Fine ticks every 30 degrees.
    for (var b = 0.0; b < 360; b += 30) {
      final from = pointOn(b, radius - 14);
      final to = pointOn(b, radius - 4);
      canvas.drawLine(
        from,
        to,
        Paint()
          ..color = tickColor
          ..strokeWidth = 2,
      );
    }

    // Cardinal labels.
    for (final entry in {0.0: 'N', 90.0: 'E', 180.0: 'S', 270.0: 'W'}.entries) {
      _drawCenteredText(
        canvas,
        entry.value,
        pointOn(entry.key, radius - 30),
        entry.key == 0 ? northAccent : labelColor,
        15,
        bold: true,
      );
    }

    // Fixed pointer at the top of the dial: this represents the direction
    // the phone itself is currently facing (it never moves - the ring and
    // sun marker rotate around it instead).
    final pointerPath = Path()
      ..moveTo(center.dx, center.dy - radius - 14)
      ..lineTo(center.dx - 8, center.dy - radius + 4)
      ..lineTo(center.dx + 8, center.dy - radius + 4)
      ..close();
    canvas.drawPath(pointerPath, Paint()..color = pointerColor);

    // Centre "you are here" dot.
    canvas.drawCircle(center, 4, Paint()..color = pointerColor);

    // Sun/moon marker at its real-world bearing relative to the dial.
    final sunPoint = pointOn(sunAzimuth, radius * 0.62);
    final sunAccent = sunAboveHorizon
        ? const Color(0xFFFFB74D)
        : const Color(0xFF7C93FF);

    canvas.drawLine(
      center,
      sunPoint,
      Paint()
        ..color = sunAccent.withValues(alpha: 0.35)
        ..strokeWidth = 2,
    );
    canvas.drawCircle(
      sunPoint,
      20,
      Paint()
        ..color = sunAccent.withValues(alpha: 0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );
    canvas.drawCircle(sunPoint, 14, Paint()..color = Colors.white);
    canvas.drawCircle(
      sunPoint,
      14,
      Paint()
        ..color = sunAccent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    final icon = sunAboveHorizon
        ? Icons.wb_sunny_rounded
        : Icons.nights_stay_rounded;
    final iconPainter = TextPainter(textDirection: TextDirection.ltr)
      ..text = TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          fontSize: 16,
          fontFamily: icon.fontFamily,
          package: icon.fontPackage,
          color: sunAccent,
        ),
      )
      ..layout();
    iconPainter.paint(
      canvas,
      sunPoint - Offset(iconPainter.width / 2, iconPainter.height / 2),
    );
  }

  void _drawCenteredText(
    Canvas canvas,
    String text,
    Offset center,
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
    painter.paint(
      canvas,
      center - Offset(painter.width / 2, painter.height / 2),
    );
  }

  @override
  bool shouldRepaint(covariant _CompassDialPainter oldDelegate) {
    return oldDelegate.heading != heading ||
        oldDelegate.sunAzimuth != sunAzimuth ||
        oldDelegate.sunAboveHorizon != sunAboveHorizon ||
        oldDelegate.isDark != isDark;
  }
}
