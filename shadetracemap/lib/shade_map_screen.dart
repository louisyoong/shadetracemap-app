import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import 'device_location.dart';
import 'glass_panel.dart';
import 'location_search.dart';
import 'sun_math.dart';

const _styleUrl = 'https://tiles.openfreemap.org/styles/liberty';

// Light-mode panel tint shared by the info legend and the corner-control
// toggle group - a touch darker than pure white so both floating panels
// still read as distinct cards against the map instead of blending in.
const _kLightPanelTint = Color(0xFFE9EBEE);

// ---- Initial location ----
const _centerLng = 101.68653;
const _centerLat = 3.1412;
const _initialUtcOffset = 8; // Asia/Kuala_Lumpur, UTC+8 year-round (no DST)
const _buildingLayerId = 'building-3d'; // native layer in the "liberty" style

// Free, no-API-key satellite imagery (Esri World Imagery XYZ tiles), added
// as a raster layer under the buildings/shadows so toggling it on swaps the
// vector base map for satellite photography without disturbing the 3D
// buildings or shadow overlay rendered above it.
const _satelliteSourceId = 'satellite-source';
const _satelliteLayerId = 'satellite-layer';
const _satelliteTileUrl =
    'https://server.arcgisonline.com/ArcGIS/rest/services/'
    'World_Imagery/MapServer/tile/{z}/{y}/{x}';

class ShadeMapScreen extends StatefulWidget {
  const ShadeMapScreen({super.key});

  @override
  State<ShadeMapScreen> createState() => _ShadeMapScreenState();
}

class _ShadeMapScreenState extends State<ShadeMapScreen> {
  MapLibreMapController? _controller;
  bool _mapLoaded = false;
  bool _shadowsReady = false;
  int _recomputeGen = 0;
  bool _recomputeBusy = false;
  bool _recomputeQueued = false;

  late DateTime _currentInstant;
  String _lastSunTimesKey = '';

  late String _dateStr;
  late int _minutes;
  int _utcOffsetHours = _initialUtcOffset;

  int _opacity = 65;
  bool _playing = false;
  Timer? _playTimer;

  double? _sunAlt;
  double? _sunAz;
  int? _sunrise;
  int? _sunset;

  String _statusMsg = 'Loading map…';
  bool _statusError = false;
  String _locationLabel = 'Kuala Lumpur, Malaysia';

  Color _ambientColor = const Color(0xFF3A4A73);
  double _ambientOpacity = 0;

  final _locationSearch = LocationSearchController();

  double _bearing = -12;
  double _liveTilt = 58;
  bool _is3D = true;
  bool _showInfo = false;
  bool _satellite = false;
  bool _locating = false;

  @override
  void initState() {
    super.initState();
    final initialFields = localFieldsFromInstant(
      DateTime.now().millisecondsSinceEpoch,
      _initialUtcOffset,
    );
    _dateStr = dateStrFromFields(initialFields);
    _minutes = initialFields.minutesOfDay;
    _currentInstant = DateTime.fromMillisecondsSinceEpoch(
      instantFromLocalFields(
        initialFields.year,
        initialFields.month,
        initialFields.day,
        _minutes,
        _utcOffsetHours,
      ),
      isUtc: true,
    );
  }

  @override
  void dispose() {
    _playTimer?.cancel();
    _locationSearch.dispose();
    super.dispose();
  }

  Map<String, dynamic> _emptyFeatureCollection() => {
    'type': 'FeatureCollection',
    'features': <dynamic>[],
  };

  Future<void> _ensureShadowLayers(
    MapLibreMapController controller,
    int initialOpacityPct,
  ) async {
    await controller.addGeoJsonSource('shadow-soft', _emptyFeatureCollection());
    await controller.addGeoJsonSource('shadow-core', _emptyFeatureCollection());

    final v = initialOpacityPct / 100;
    await controller.addFillLayer(
      'shadow-soft',
      'shadow-soft-layer',
      FillLayerProperties(
        fillColor: '#1c2440',
        fillOpacity: softMaxOpacity * v,
      ),
      belowLayerId: _buildingLayerId,
    );
    await controller.addFillLayer(
      'shadow-core',
      'shadow-core-layer',
      FillLayerProperties(
        fillColor: '#151b33',
        fillOpacity: coreMaxOpacity * v,
      ),
      belowLayerId: _buildingLayerId,
    );
  }

  // Added once, below the shadow overlay, so it starts out hidden (behind
  // the vector base map) and toggling satellite mode just flips its
  // visibility rather than tearing the layer down and rebuilding it.
  Future<void> _ensureSatelliteLayer(MapLibreMapController controller) async {
    await controller.addSource(
      _satelliteSourceId,
      const RasterSourceProperties(
        tiles: [_satelliteTileUrl],
        tileSize: 256,
        attribution: 'Esri, Maxar, Earthstar Geographics',
      ),
    );
    await controller.addLayer(
      _satelliteSourceId,
      _satelliteLayerId,
      const RasterLayerProperties(),
      belowLayerId: 'shadow-soft-layer',
    );
    await controller.setLayerVisibility(_satelliteLayerId, _satellite);
  }

  void _toggleSatellite() {
    final controller = _controller;
    if (controller == null) return;
    setState(() => _satellite = !_satellite);
    controller.setLayerVisibility(_satelliteLayerId, _satellite);
  }

  // There is no maplibre_gl equivalent of the JS SDK's map.setLight(): the
  // plugin never implemented a light API on either platform (confirmed by
  // reading the native Android/iOS source), and the natural workaround —
  // tinting the building-3d fill-extrusion layer's own paint properties at
  // runtime — also fails (setLayerProperties explicitly doesn't support
  // fill-extrusion layers on iOS or Android). This screen-space tint over
  // the whole map is a Flutter-side stand-in for the same visual intent
  // (warm near sunrise/sunset, dim + blue after dark, clear at high sun).
  ({Color color, double opacity}) _ambientOverlayFor(SunPosition pos) {
    if (pos.altitude <= 0.5) {
      return (color: const Color(0xFF3A4A73), opacity: 0.34);
    }
    final t = clampD(pos.altitude / 90, 0, 1);
    final intensity = clampD(0.28 + 0.42 * t, 0.28, 0.7);
    final warm = pos.altitude < 12;
    if (warm) {
      return (color: const Color(0xFFFFC48F), opacity: 0.20);
    }
    return (color: Colors.white, opacity: (1 - intensity) * 0.14);
  }

  Future<int> _computeAndDrawShadows(
    MapLibreMapController controller,
    SunPosition pos,
    int gen,
    Size viewportSize,
  ) async {
    if (pos.altitude <= 0.5) {
      await controller.setGeoJsonSource(
        'shadow-core',
        _emptyFeatureCollection(),
      );
      await controller.setGeoJsonSource(
        'shadow-soft',
        _emptyFeatureCollection(),
      );
      return 0;
    }

    final shadowAz = norm360(pos.azimuth + 180);
    final baseLen = math.min(
      1 / math.max(math.tan(toRad(pos.altitude)), 0.02),
      maxShadowLen,
    );

    List features = [];
    try {
      features = await controller.queryRenderedFeaturesInRect(
        Rect.fromLTWH(0, 0, viewportSize.width, viewportSize.height),
        [_buildingLayerId],
        null,
      );
    } catch (_) {
      features = [];
    }
    if (gen != _recomputeGen) return 0;

    final seen = <String>{};
    final coreFeats = <Map<String, dynamic>>[];
    final softFeats = <Map<String, dynamic>>[];

    for (final f in features) {
      final feature = f as Map;
      final geometry = feature['geometry'] as Map?;
      if (geometry == null) continue;
      final rings = <List>[];
      final type = geometry['type'];
      if (type == 'Polygon') {
        rings.add((geometry['coordinates'] as List)[0] as List);
      } else if (type == 'MultiPolygon') {
        for (final p in geometry['coordinates'] as List) {
          rings.add((p as List)[0] as List);
        }
      }
      final props = (feature['properties'] as Map?)?.cast<String, dynamic>();
      final height = buildingHeightOf(props);
      final lenM = math.min(height * baseLen, maxShadowLen);
      if (lenM < 1) continue;

      for (final ring in rings) {
        if (ring.length < 4) continue;
        final first = ring[0] as List;
        final key =
            '${(first[0] as num).toStringAsFixed(5)},'
            '${(first[1] as num).toStringAsFixed(5)},${height.toStringAsFixed(0)}';
        if (seen.contains(key)) continue;
        seen.add(key);

        final verts = ring
            .sublist(0, ring.length - 1)
            .map((v) => [(v[0] as num).toDouble(), (v[1] as num).toDouble()])
            .toList();
        if (verts.length < 3) continue;

        final projected = verts
            .map((v) => offsetPoint(v[0], v[1], lenM, shadowAz))
            .toList();
        final hull = convexHull([...verts, ...projected]);
        if (hull.length >= 3) {
          coreFeats.add({
            'type': 'Feature',
            'properties': {},
            'geometry': {
              'type': 'Polygon',
              'coordinates': [
                [...hull, hull[0]],
              ],
            },
          });
        }

        final lenSoft = math.min(lenM * 1.35, maxShadowLen * 1.3);
        final projectedSoft = verts
            .map((v) => offsetPoint(v[0], v[1], lenSoft, shadowAz))
            .toList();
        final hullSoft = convexHull([...verts, ...projectedSoft]);
        if (hullSoft.length >= 3) {
          softFeats.add({
            'type': 'Feature',
            'properties': {},
            'geometry': {
              'type': 'Polygon',
              'coordinates': [
                [...hullSoft, hullSoft[0]],
              ],
            },
          });
        }
      }
    }

    if (gen != _recomputeGen) return coreFeats.length;
    await controller.setGeoJsonSource('shadow-core', {
      'type': 'FeatureCollection',
      'features': coreFeats,
    });
    await controller.setGeoJsonSource('shadow-soft', {
      'type': 'FeatureCollection',
      'features': softFeats,
    });
    return coreFeats.length;
  }

  // Re-run the sun/shadow calculation against whatever map + time are
  // current. A generation counter guards against out-of-order writes when
  // recomputes overlap (e.g. dragging the time slider fast, or play mode
  // ticking faster than a query round-trip).
  Future<void> _recompute() async {
    final controller = _controller;
    if (controller == null || !_mapLoaded) return;
    final gen = ++_recomputeGen;

    final center =
        controller.cameraPosition?.target ??
        const LatLng(_centerLat, _centerLng);
    final pos = sunPosition(_currentInstant, center.latitude, center.longitude);
    final overlay = _ambientOverlayFor(pos);

    final viewportSize = context.size ?? MediaQuery.of(context).size;
    var count = 0;
    if (_shadowsReady) {
      count = await _computeAndDrawShadows(controller, pos, gen, viewportSize);
    }
    if (gen != _recomputeGen || !mounted) return;

    // Sunrise/sunset are cached per local-day + rounded location, since both
    // moving the map and changing the date can change them. Uses the
    // location's own local midnight, not the device's.
    final dayStartMs = localMidnightMs(
      _currentInstant.millisecondsSinceEpoch,
      _utcOffsetHours,
    );
    final key =
        '$dayStartMs@${center.latitude.toStringAsFixed(2)},'
        '${center.longitude.toStringAsFixed(2)}';
    SunTimes? newSunTimes;
    if (key != _lastSunTimesKey) {
      _lastSunTimesKey = key;
      newSunTimes = findSunriseSunset(
        dayStartMs,
        center.latitude,
        center.longitude,
      );
    }

    String statusMsg = _statusMsg;
    bool statusError = _statusError;
    if (pos.altitude <= 0.5) {
      statusMsg = 'Sun below horizon — no shadows right now.';
      statusError = false;
    } else if (_shadowsReady) {
      final zoom = controller.cameraPosition?.zoom ?? 0;
      if (zoom < 14) {
        statusMsg = 'Zoom in (≥14) to see buildings and their shadows.';
        statusError = true;
      } else {
        statusMsg = 'Casting shadows for $count buildings in view.';
        statusError = false;
      }
    }

    setState(() {
      _sunAlt = pos.altitude;
      _sunAz = pos.azimuth;
      _ambientColor = overlay.color;
      _ambientOpacity = overlay.opacity;
      if (newSunTimes != null) {
        _sunrise = newSunTimes.sunrise;
        _sunset = newSunTimes.sunset;
      }
      _statusMsg = statusMsg;
      _statusError = statusError;
    });
  }

  // Fast slider drags (or play-mode ticks) can fire far more often than a
  // single recompute's native query round-trip completes. Awaiting each
  // one serially would make dragging feel laggy, while firing them all
  // concurrently floods the platform channel with overlapping queries -
  // this coalesces a burst down to "at most one recompute in flight, plus
  // one more queued run once it's free" so only the latest time actually
  // gets drawn.
  Future<void> _scheduleRecompute() async {
    if (_recomputeBusy) {
      _recomputeQueued = true;
      return;
    }
    _recomputeBusy = true;
    try {
      await _recompute();
      while (_recomputeQueued) {
        _recomputeQueued = false;
        await _recompute();
      }
    } finally {
      _recomputeBusy = false;
    }
  }

  void _onWallClockChanged() {
    final parts = _dateStr.split('-').map(int.parse).toList();
    final instantMs = instantFromLocalFields(
      parts[0],
      parts[1],
      parts[2],
      _minutes,
      _utcOffsetHours,
    );
    _currentInstant = DateTime.fromMillisecondsSinceEpoch(
      instantMs,
      isUtc: true,
    );
    _scheduleRecompute();
  }

  Future<void> _onStyleLoaded() async {
    final controller = _controller;
    if (controller == null) return;
    _mapLoaded = true;

    await _ensureShadowLayers(controller, _opacity);
    await _ensureSatelliteLayer(controller);
    _shadowsReady = true;
    if (mounted) {
      setState(() {
        _statusMsg = 'Map loaded. Rendering buildings…';
        _statusError = false;
      });
    }
    await _recompute();
    // Catch any tiles that were still loading right at style-load time.
    Future.delayed(const Duration(milliseconds: 800), _scheduleRecompute);
    Future.delayed(const Duration(milliseconds: 2000), _scheduleRecompute);

    // Workaround for a maplibre_gl iOS cold-launch crash (plugin issue
    // #819): setting tilt/bearing directly in initialCameraPosition races
    // the platform view's zero-sized initial frame -> mbgl::LatLng ctor
    // throws std::domain_error -> uncatchable SIGABRT. Applying the tilted
    // 3D view here instead, once the map has fully settled, avoids it.
    await Future.delayed(const Duration(milliseconds: 400));
    await controller.moveCamera(CameraUpdate.tiltTo(58));
    await controller.moveCamera(CameraUpdate.bearingTo(-12));

    // Auto-center on the device's own location once the map has settled,
    // same as Sun Simulator and Weather do on open - silently keeps the
    // Kuala Lumpur default if location services/permission aren't available.
    _goToCurrentLocation(silent: true);
  }

  void _onCameraMove(CameraPosition pos) {
    setState(() {
      _bearing = pos.bearing;
      _liveTilt = pos.tilt;
      _is3D = pos.tilt > 5;
    });
  }

  void _resetNorth() {
    _controller?.animateCamera(CameraUpdate.bearingTo(0));
  }

  void _toggleDimension() {
    final controller = _controller;
    if (controller == null) return;
    final goTo3D = _liveTilt <= 5;
    controller.animateCamera(
      CameraUpdate.tiltTo(goTo3D ? 58 : 0),
      duration: const Duration(milliseconds: 500),
    );
  }

  void _togglePlaying() {
    setState(() => _playing = !_playing);
    if (_playing) {
      _playTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
        setState(() => _minutes = (_minutes + 5) % 1440);
        _onWallClockChanged();
      });
    } else {
      _playTimer?.cancel();
      _playTimer = null;
    }
  }

  Future<void> _setOpacity(int value) async {
    setState(() => _opacity = value);
    final controller = _controller;
    if (controller == null || !_shadowsReady) return;
    final v = value / 100;
    // Always pass every paint property this layer cares about together:
    // setLayerProperties sends unset fields as explicit nulls, and the
    // native side treats a null as "clear this property" rather than
    // "leave it alone" - a partial update here would blank the fill color.
    await controller.setLayerProperties(
      'shadow-core-layer',
      FillLayerProperties(
        fillColor: '#151b33',
        fillOpacity: coreMaxOpacity * v,
      ),
    );
    await controller.setLayerProperties(
      'shadow-soft-layer',
      FillLayerProperties(
        fillColor: '#1c2440',
        fillOpacity: softMaxOpacity * v,
      ),
    );
  }

  void _selectSearchResult(dynamic result) {
    final controller = _controller;
    if (controller == null) return;
    final lon = double.tryParse('${result['lon']}');
    final lat = double.tryParse('${result['lat']}');
    if (lon == null || lat == null) return;

    // Keep whatever 2D/3D view + rotation the user currently has instead of
    // forcing a default 3D angle.
    controller.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: LatLng(lat, lon),
          zoom: 16.4,
          tilt: _liveTilt,
          bearing: _bearing,
        ),
      ),
      duration: const Duration(milliseconds: 1500),
    );

    // Jump the clock to "now" in this location's (approximate) local time.
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
      _utcOffsetHours = offset;
      _dateStr = dateStrFromFields(nowFields);
      _minutes = nowFields.minutesOfDay;
      _locationLabel = label;
    });
    _locationSearch.selected(label);
    _onWallClockChanged();
  }

  // [silent] is used for the automatic on-launch detection below: unlike a
  // deliberate tap of the locate button, the user didn't ask for this one,
  // so a denied/unavailable location shouldn't interrupt them with a
  // snackbar - it just quietly keeps the Kuala Lumpur default.
  Future<void> _goToCurrentLocation({bool silent = false}) async {
    final controller = _controller;
    if (controller == null || _locating) return;

    setState(() => _locating = true);
    try {
      final position = await resolveDeviceLocation();
      if (!mounted) return;

      controller.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: LatLng(position.latitude, position.longitude),
            zoom: 16.4,
            tilt: _liveTilt,
            bearing: _bearing,
          ),
        ),
        duration: const Duration(milliseconds: 1500),
      );

      final offset = approxUtcOffsetHours(position.longitude);
      final nowFields = localFieldsFromInstant(
        DateTime.now().millisecondsSinceEpoch,
        offset,
      );
      setState(() {
        _utcOffsetHours = offset;
        _dateStr = dateStrFromFields(nowFields);
        _minutes = nowFields.minutesOfDay;
        _locationLabel = 'My Location';
      });
      _locationSearch.selected('My Location');
      _onWallClockChanged();

      // Best-effort follow-up: swap the generic placeholder for a real
      // place name once reverse geocoding resolves, without blocking the
      // camera move/recompute on it.
      final label = await reverseGeocodeLabel(
        position.latitude,
        position.longitude,
      );
      if (label != null && mounted) {
        setState(() => _locationLabel = label);
        _locationSearch.selected(label);
      }
    } on DeviceLocationException catch (e) {
      if (!silent) _showLocationError(e.message);
    } catch (_) {
      if (!silent) _showLocationError("Couldn't determine your location.");
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  void _showLocationError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    // The map itself stays edge-to-edge (full bleed under the status bar /
    // home indicator), but the floating chrome on top of it needs to clear
    // those system insets or it collides with the clock / notch / gesture
    // bar on real devices.
    final topInset = mq.padding.top;
    final bottomInset = mq.padding.bottom;

    return Stack(
      children: [
        MapLibreMap(
          styleString: _styleUrl,
          initialCameraPosition: const CameraPosition(
            target: LatLng(_centerLat, _centerLng),
            zoom: 16.4,
          ),
          trackCameraPosition: true,
          compassEnabled: false,
          onMapCreated: (c) => _controller = c,
          onStyleLoadedCallback: _onStyleLoaded,
          onCameraIdle: _scheduleRecompute,
          onCameraMove: _onCameraMove,
        ),
        IgnorePointer(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 400),
            color: _ambientColor.withValues(alpha: _ambientOpacity),
          ),
        ),
        // Search is the primary top-of-screen action, so it takes the full
        // prominent top bar now that info + 2D/3D have moved to the
        // bottom-right corner.
        Positioned(
          top: 12 + topInset,
          left: 12,
          right: 12,
          child: Center(
            child: SizedBox(
              width: math.min(360, mq.size.width - 24),
              child: LocationSearchField(
                controller: _locationSearch,
                onSelect: _selectSearchResult,
              ),
            ),
          ),
        ),
        if (_showInfo)
          // Anchored below the search bar rather than near the corner
          // button that opens it: the bottom-right corner is too close to
          // the (variable-height) bottom bar to reliably fit a panel above
          // it without overlap, but the top of the screen is always clear.
          Positioned(
            top: 76 + topInset,
            right: 12,
            child: _Legend(
              locationLabel: _locationLabel,
              sunAlt: _sunAlt,
              sunAz: _sunAz,
              statusMsg: _statusMsg,
              statusError: _statusError,
            ),
          ),
        Positioned(
          // The corner control group (compass + info + 3D) now lives only
          // in the bottom-right, so the bar can hug the left edge and only
          // needs to clear that one group on the right.
          left: 12,
          right: 64,
          bottom: 18 + bottomInset,
          child: SizedBox(
            width: mq.size.width - 76,
            child: _BottomBar(
              minutes: _minutes,
              dateStr: _dateStr,
              playing: _playing,
              sunrise: _sunrise,
              sunset: _sunset,
              opacity: _opacity,
              onPlayToggle: _togglePlaying,
              onMinutesChanged: (v) {
                setState(() => _minutes = v);
                _onWallClockChanged();
              },
              onOpacityChanged: _setOpacity,
            ),
          ),
        ),
        // Painted after the bottom bar so it stays tappable above it on
        // narrow phone widths, where the bar's edges can reach close to
        // the screen edges and would otherwise cover this corner control.
        Positioned(
          right: 12,
          bottom: 12 + bottomInset,
          child: _CornerControls(
            bearing: _bearing,
            onCompassTap: _resetNorth,
            showInfo: _showInfo,
            onInfoTap: () => setState(() => _showInfo = !_showInfo),
            is3D: _is3D,
            onDimTap: _toggleDimension,
            satellite: _satellite,
            onSatelliteTap: _toggleSatellite,
            locating: _locating,
            onLocateTap: _goToCurrentLocation,
          ),
        ),
      ],
    );
  }
}

// ================= UI chrome =================

class _Legend extends StatelessWidget {
  const _Legend({
    required this.locationLabel,
    required this.sunAlt,
    required this.sunAz,
    required this.statusMsg,
    required this.statusError,
  });

  final String locationLabel;
  final double? sunAlt;
  final double? sunAz;
  final String statusMsg;
  final bool statusError;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final panelTint = isDark ? const Color(0xFF15171C) : _kLightPanelTint;
    final onPanel = isDark ? const Color(0xFFF2F2F2) : const Color(0xFF1B1D22);
    final onPanelMuted = isDark
        ? const Color(0xFFA4AAB2)
        : const Color(0xFF52575E);
    final labelMuted = isDark
        ? const Color(0xFF8A9099)
        : const Color(0xFF61666D);
    final accent = isDark ? const Color(0xFFFFD580) : const Color(0xFF9C5300);
    return SizedBox(
      width: 250,
      child: GlassPanel(
        borderRadius: 12,
        tint: panelTint,
        tintOpacity: isDark ? 0.5 : 0.7,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Shade Map Demo',
              style: TextStyle(
                color: onPanel,
                fontSize: 14.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.1,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Real 3D buildings + computed sun-cast shadows — $locationLabel',
              style: TextStyle(color: onPanelMuted, fontSize: 11, height: 1.42),
            ),
            const SizedBox(height: 9),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'ALTITUDE',
                        style: TextStyle(
                          color: labelMuted,
                          fontSize: 10,
                          letterSpacing: 0.4,
                        ),
                      ),
                      Text(
                        sunAlt == null
                            ? '--°'
                            : '${sunAlt!.toStringAsFixed(1)}°',
                        style: TextStyle(
                          color: accent,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'AZIMUTH',
                        style: TextStyle(
                          color: labelMuted,
                          fontSize: 10,
                          letterSpacing: 0.4,
                        ),
                      ),
                      Text(
                        sunAz == null ? '--°' : '${sunAz!.toStringAsFixed(0)}°',
                        style: TextStyle(
                          color: accent,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  margin: const EdgeInsets.only(top: 2, right: 6),
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    color: accent,
                    shape: BoxShape.circle,
                    boxShadow: [BoxShadow(color: accent, blurRadius: 6)],
                  ),
                ),
                Expanded(
                  child: Text(
                    statusMsg,
                    style: TextStyle(
                      color: statusError
                          ? const Color(0xFFFF9A8A)
                          : (isDark
                                ? const Color(0xFF71C686)
                                : const Color(0xFF267A45)),
                      fontSize: 10.5,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// The compass, info toggle and 2D/3D toggle grouped into a single pill in
// the bottom-right corner, like Apple Maps' combined compass/dimension
// control - reads as one coherent control instead of three separate
// floating buttons.
class _CornerControls extends StatelessWidget {
  const _CornerControls({
    required this.bearing,
    required this.onCompassTap,
    required this.showInfo,
    required this.onInfoTap,
    required this.is3D,
    required this.onDimTap,
    required this.satellite,
    required this.onSatelliteTap,
    required this.locating,
    required this.onLocateTap,
  });

  final double bearing;
  final VoidCallback onCompassTap;
  final bool showInfo;
  final VoidCallback onInfoTap;
  final bool is3D;
  final VoidCallback onDimTap;
  final bool satellite;
  final VoidCallback onSatelliteTap;
  final bool locating;
  final VoidCallback onLocateTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final panelTint = isDark ? const Color(0xFF15171C) : _kLightPanelTint;
    final iconColor = isDark
        ? const Color(0xFFECEDEF)
        : const Color(0xFF1B1D22);
    final compassLabelColor = isDark
        ? const Color(0xFFDFE3E8)
        : const Color(0xFF6B7078);
    final northAccent = isDark
        ? const Color(0xFFFF8A7A)
        : const Color(0xFFE04B36);
    final needleTail = isDark
        ? const Color(0xFF6F7580)
        : const Color(0xFF9AA0A8);
    final divider = Container(
      height: 1,
      color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.1),
    );
    return SizedBox(
      width: 44,
      child: GlassPanel(
        borderRadius: 20,
        tint: panelTint,
        tintOpacity: 0.5,
        blurSigma: 18,
        padding: EdgeInsets.zero,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _CornerButton(
              onTap: onCompassTap,
              height: 52,
              child: Transform.rotate(
                angle: -bearing * math.pi / 180,
                child: SizedBox(
                  width: 38,
                  height: 38,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Positioned(
                        top: 0,
                        child: _CompassLabel('N', color: northAccent),
                      ),
                      Positioned(
                        bottom: 0,
                        child: _CompassLabel('S', color: compassLabelColor),
                      ),
                      Positioned(
                        left: 0,
                        child: _CompassLabel('W', color: compassLabelColor),
                      ),
                      Positioned(
                        right: 0,
                        child: _CompassLabel('E', color: compassLabelColor),
                      ),
                      _CompassNeedle(
                        headColor: northAccent,
                        tailColor: needleTail,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            divider,
            _CornerButton(
              onTap: onInfoTap,
              child: Icon(
                showInfo ? Icons.close : Icons.info_outline,
                size: 19,
                color: iconColor,
              ),
            ),
            divider,
            _CornerButton(
              onTap: onDimTap,
              child: Text(
                is3D ? '3D' : '2D',
                style: TextStyle(
                  color: iconColor,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                ),
              ),
            ),
            divider,
            _CornerButton(
              onTap: onSatelliteTap,
              child: Icon(
                Icons.satellite_alt,
                size: 18,
                color: satellite
                    ? (isDark
                          ? const Color(0xFFFFD580)
                          : const Color(0xFF9C5300))
                    : iconColor,
              ),
            ),
            divider,
            _CornerButton(
              onTap: onLocateTap,
              child: locating
                  ? SizedBox(
                      width: 15,
                      height: 15,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.8,
                        color: iconColor,
                      ),
                    )
                  : Icon(Icons.my_location, size: 18, color: iconColor),
            ),
          ],
        ),
      ),
    );
  }
}

class _CornerButton extends StatelessWidget {
  const _CornerButton({
    required this.onTap,
    required this.child,
    this.height = 44,
  });
  final VoidCallback onTap;
  final Widget child;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 44,
          height: height,
          child: Center(child: child),
        ),
      ),
    );
  }
}

class _CompassLabel extends StatelessWidget {
  const _CompassLabel(this.text, {this.color = const Color(0xFFDFE3E8)});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        color: color,
        fontSize: 7.5,
        fontWeight: FontWeight.bold,
      ),
    );
  }
}

class _CompassNeedle extends StatelessWidget {
  const _CompassNeedle({required this.headColor, required this.tailColor});
  final Color headColor;
  final Color tailColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 2,
      height: 16,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [headColor, tailColor],
          stops: const [0.5, 0.5],
        ),
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.minutes,
    required this.dateStr,
    required this.playing,
    required this.sunrise,
    required this.sunset,
    required this.opacity,
    required this.onPlayToggle,
    required this.onMinutesChanged,
    required this.onOpacityChanged,
  });

  final int minutes;
  final String dateStr;
  final bool playing;
  final int? sunrise;
  final int? sunset;
  final int opacity;
  final VoidCallback onPlayToggle;
  final ValueChanged<int> onMinutesChanged;
  final ValueChanged<int> onOpacityChanged;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final panelTint = isDark ? const Color(0xFF15171C) : Colors.white;
    final onPanel = isDark ? const Color(0xFFEEEEEE) : const Color(0xFF1B1D22);
    final onPanelMuted = isDark
        ? const Color(0xFF9AA0A8)
        : const Color(0xFF6B7078);
    return GlassPanel(
      borderRadius: 18,
      tint: panelTint,
      tintOpacity: isDark ? 0.6 : 0.75,
      blurSigma: 20,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    formatBigTime(minutes),
                    style: TextStyle(
                      color: onPanel,
                      fontSize: 19,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.3,
                    ),
                  ),
                  Text(
                    dateStr,
                    style: TextStyle(color: onPanelMuted, fontSize: 12),
                  ),
                ],
              ),
              GestureDetector(
                onTap: onPlayToggle,
                child: Container(
                  width: 30,
                  height: 30,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: const Color(0xFF3B7CFF),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    playing ? Icons.pause : Icons.play_arrow,
                    size: 15,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          _TimeSlider(
            minutes: minutes,
            sunrise: sunrise,
            sunset: sunset,
            isDark: isDark,
            onChanged: onMinutesChanged,
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(Icons.wb_twilight, size: 13, color: onPanelMuted),
              const SizedBox(width: 4),
              Text(
                sunrise == null
                    ? '--:--'
                    : '${pad2(sunrise! ~/ 60)}:${pad2(sunrise! % 60)}',
                style: TextStyle(color: onPanelMuted, fontSize: 10.5),
              ),
              const SizedBox(width: 14),
              Icon(Icons.nights_stay_outlined, size: 13, color: onPanelMuted),
              const SizedBox(width: 4),
              Text(
                sunset == null
                    ? '--:--'
                    : '${pad2(sunset! ~/ 60)}:${pad2(sunset! % 60)}',
                style: TextStyle(color: onPanelMuted, fontSize: 10.5),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Text(
                'Shadow strength',
                style: TextStyle(color: onPanelMuted, fontSize: 10.5),
              ),
              const Spacer(),
              SizedBox(
                width: 110,
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3,
                    activeTrackColor: const Color(0xFF3B7CFF),
                    inactiveTrackColor: const Color(0x333B7CFF),
                    thumbColor: Colors.white,
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 6,
                    ),
                    overlayShape: const RoundSliderOverlayShape(
                      overlayRadius: 14,
                    ),
                  ),
                  child: Slider(
                    min: 0,
                    max: 100,
                    value: opacity.toDouble(),
                    onChanged: (v) => onOpacityChanged(v.round()),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A small pinned badge marking sunrise/sunset's minute-of-day position on
/// the time slider's track, so both are visible at a glance instead of only
/// readable from the text line underneath.
class _SunMarker extends StatelessWidget {
  const _SunMarker({required this.icon});
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: 14,
        height: 14,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xFF1B1D22).withValues(alpha: 0.75),
          shape: BoxShape.circle,
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.85),
            width: 1,
          ),
        ),
        child: Icon(icon, size: 8, color: Colors.white),
      ),
    );
  }
}

/// The time-of-day slider: a custom gesture surface (not the stock Material
/// Slider) so one recognizer can own both interactions at once -
/// single-finger drag scrubs the selected minute, and a two-finger pinch
/// zooms the visible window down to as little as one hour for finer
/// scrubbing precision. A single `GestureDetector` is used deliberately
/// instead of layering a separate pinch detector over a Slider: once a
/// Slider's own drag recognizer claims a pointer, no later widget state
/// change can wrestle that pointer back, so a second finger joining
/// mid-drag would fight the first for control of the value. Doing both
/// gestures through one `onScale*` stream sidesteps that entirely.
class _TimeSlider extends StatefulWidget {
  const _TimeSlider({
    required this.minutes,
    required this.sunrise,
    required this.sunset,
    required this.isDark,
    required this.onChanged,
  });

  final int minutes;
  final int? sunrise;
  final int? sunset;
  final bool isDark;
  final ValueChanged<int> onChanged;

  @override
  State<_TimeSlider> createState() => _TimeSliderState();
}

class _TimeSliderState extends State<_TimeSlider> {
  static const _minSpan = 60.0; // most zoomed-in: 1 hour visible
  static const _maxSpan = 1440.0; // fully zoomed-out: the whole day
  static const _inset = 18.0;

  double _span = _maxSpan;
  double _center = 720;

  // Baseline captured at gesture start, and re-captured any time the active
  // pointer count changes mid-gesture (e.g. a second finger joins a drag to
  // start a pinch) - `ScaleGestureRecognizer` keeps `scale`/`focalPoint`
  // relative to whenever the pointer count last changed, not to true
  // gesture start, so our own math has to track that same reference frame.
  int _basePointerCount = 0;
  double _baseSpan = _maxSpan;
  double _baseCenter = 720;
  double _baseScale = 1;
  Offset _baseFocal = Offset.zero;
  double _baseMinutes = 0;
  double _trackWidth = 1;

  double get _start => (_center - _span / 2).clamp(0.0, _maxSpan - _span);
  bool get _zoomed => _span < _maxSpan - 1;

  void _captureBaseline(int pointerCount, double scale, Offset focal) {
    _basePointerCount = pointerCount;
    _baseSpan = _span;
    _baseCenter = _center;
    _baseScale = scale;
    _baseFocal = focal;
    _baseMinutes = widget.minutes.toDouble();
  }

  void _handleScaleStart(ScaleStartDetails d) =>
      _captureBaseline(d.pointerCount, 1, d.localFocalPoint);

  void _handleScaleUpdate(ScaleUpdateDetails d) {
    if (d.pointerCount != _basePointerCount) {
      _captureBaseline(d.pointerCount, d.scale, d.localFocalPoint);
      return;
    }
    if (d.pointerCount >= 2) {
      final newSpan = (_baseSpan / (d.scale / _baseScale)).clamp(
        _minSpan,
        _maxSpan,
      );
      // Keep the minute under the pinch's midpoint stationary on screen
      // while zooming, the same anchor-on-focal-point behaviour as a map
      // pinch, instead of always re-centering on the middle of the window.
      final focalFrac = (_baseFocal.dx / _trackWidth).clamp(0.0, 1.0);
      final anchorMinute = _baseCenter - _baseSpan / 2 + focalFrac * _baseSpan;
      setState(() {
        _span = newSpan;
        _center = (anchorMinute - (focalFrac - 0.5) * newSpan).clamp(
          newSpan / 2,
          _maxSpan - newSpan / 2,
        );
      });
    } else {
      final dMinutes =
          (d.localFocalPoint.dx - _baseFocal.dx) / _trackWidth * _span;
      widget.onChanged((_baseMinutes + dMinutes).round().clamp(0, 1439));
    }
  }

  void _handleScaleEnd(ScaleEndDetails d) => _basePointerCount = 0;

  void _resetZoom() => setState(() {
    _span = _maxSpan;
    _center = 720;
  });

  @override
  Widget build(BuildContext context) {
    final sr = widget.sunrise;
    final ss = widget.sunset;
    final isDay =
        sr != null && ss != null && widget.minutes >= sr && widget.minutes < ss;
    final mutedColor = widget.isDark
        ? const Color(0xFF9AA0A8)
        : const Color(0xFF6B7078);

    return LayoutBuilder(
      builder: (context, constraints) {
        _trackWidth = constraints.maxWidth;
        double xFor(num mins) {
          final frac = ((mins - _start) / _span).clamp(0.0, 1.0);
          return _inset + frac * (_trackWidth - _inset * 2);
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onScaleStart: _handleScaleStart,
              onScaleUpdate: _handleScaleUpdate,
              onScaleEnd: _handleScaleEnd,
              onDoubleTap: _zoomed ? _resetZoom : null,
              child: SizedBox(
                height: 44,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned(
                      top: 13,
                      left: _inset,
                      right: _inset,
                      child: Container(
                        height: 18,
                        decoration: BoxDecoration(
                          gradient: buildDayGradient(
                            sr,
                            ss,
                            isDark: widget.isDark,
                            windowStart: _start,
                            windowSpan: _span,
                          ),
                          borderRadius: BorderRadius.circular(9),
                          border: Border.all(
                            color: (widget.isDark ? Colors.white : Colors.black)
                                .withValues(alpha: 0.08),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(
                                alpha: widget.isDark ? 0.35 : 0.12,
                              ),
                              blurRadius: 5,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (sr != null && sr >= _start && sr <= _start + _span)
                      Positioned(
                        left: xFor(sr) - 7,
                        top: 15,
                        child: const _SunMarker(icon: Icons.wb_twilight),
                      ),
                    if (ss != null && ss >= _start && ss <= _start + _span)
                      Positioned(
                        left: xFor(ss) - 7,
                        top: 15,
                        child: const _SunMarker(
                          icon: Icons.nights_stay_outlined,
                        ),
                      ),
                    Positioned(
                      left: xFor(widget.minutes) - 13,
                      top: 9,
                      child: CustomPaint(
                        size: const Size(26, 26),
                        painter: _TimeThumbPainter(isDay: isDay),
                      ),
                    ),
                    if (_zoomed)
                      Positioned(
                        top: 0,
                        right: 0,
                        child: GestureDetector(
                          onTap: _resetZoom,
                          child: _ZoomBadge(span: _span),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 4),
            _HourLabels(
              start: _start,
              span: _span,
              xFor: xFor,
              color: mutedColor,
            ),
          ],
        );
      },
    );
  }
}

/// Dynamically-spaced hour/minute tick labels under the track: the label
/// interval adapts to the current zoom level (still the familiar
/// 12AM/6AM/12PM/6PM/12AM set at full-day zoom) so scrubbing a zoomed-in
/// window shows finer time markers instead of four labels 90% of an inch
/// apart.
class _HourLabels extends StatelessWidget {
  const _HourLabels({
    required this.start,
    required this.span,
    required this.xFor,
    required this.color,
  });

  final double start;
  final double span;
  final double Function(num) xFor;
  final Color color;

  static const _stepCandidates = [360, 180, 120, 60, 30, 15, 10, 5];

  int get _step {
    for (final step in _stepCandidates) {
      if (span / step >= 3.5) return step;
    }
    return 5;
  }

  String _label(int mins) {
    final m = mins % 1440;
    final h = m ~/ 60, mm = m % 60;
    final display = h % 12 == 0 ? 12 : h % 12;
    final ampm = h < 12 ? 'AM' : 'PM';
    return mm == 0 ? '$display$ampm' : '$display:${pad2(mm)}$ampm';
  }

  @override
  Widget build(BuildContext context) {
    final step = _step;
    final first = (start / step).ceil() * step;
    final labels = <Widget>[];
    for (var m = first; m <= start + span; m += step) {
      labels.add(
        Positioned(
          left: xFor(m) - 16,
          width: 32,
          child: Text(
            _label(m),
            textAlign: TextAlign.center,
            style: TextStyle(color: color, fontSize: 9),
          ),
        ),
      );
    }
    return SizedBox(height: 12, child: Stack(children: labels));
  }
}

/// Small "zoomed in" indicator over the time slider, doubling as a tap
/// target to reset back to the full-day view - shown only while zoomed, so
/// double-tap-to-reset stays discoverable without a permanent extra button.
class _ZoomBadge extends StatelessWidget {
  const _ZoomBadge({required this.span});
  final double span;

  @override
  Widget build(BuildContext context) {
    final label = span < 90
        ? '${span.round()}m'
        : '${(span / 60).toStringAsFixed(span % 60 == 0 ? 0 : 1)}h';
    return Container(
      margin: const EdgeInsets.only(top: 2, right: 2),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 9,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 3),
          const Icon(Icons.close, size: 9, color: Colors.white),
        ],
      ),
    );
  }
}

/// Time-slider thumb: a white knob with a sun/moon glyph and a soft colour
/// glow (warm gold by day, cool indigo by night), so the handle itself
/// communicates day vs. night at a glance instead of leaving that entirely
/// to the gradient track underneath it.
class _TimeThumbPainter extends CustomPainter {
  const _TimeThumbPainter({required this.isDay});
  final bool isDay;

  static const _radius = 13.0;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final accent = isDay ? const Color(0xFFFFB74D) : const Color(0xFF7C93FF);

    canvas.drawCircle(
      center,
      _radius + 6,
      Paint()
        ..color = accent.withValues(alpha: 0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.drawCircle(center, _radius, Paint()..color = Colors.white);
    canvas.drawCircle(
      center,
      _radius,
      Paint()
        ..color = accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    final icon = isDay ? Icons.wb_sunny_rounded : Icons.nights_stay_rounded;
    final iconPainter = TextPainter(textDirection: TextDirection.ltr)
      ..text = TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          fontSize: 14,
          fontFamily: icon.fontFamily,
          package: icon.fontPackage,
          color: accent,
        ),
      )
      ..layout();
    iconPainter.paint(
      canvas,
      center - Offset(iconPainter.width / 2, iconPainter.height / 2),
    );
  }

  @override
  bool shouldRepaint(covariant _TimeThumbPainter oldDelegate) =>
      oldDelegate.isDay != isDay;
}
