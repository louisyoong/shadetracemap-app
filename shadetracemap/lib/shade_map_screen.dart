import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

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

  Future<void> _pickDate() async {
    final parts = _dateStr.split('-').map(int.parse).toList();
    final initial = DateTime(parts[0], parts[1], parts[2]);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1970),
      lastDate: DateTime(2100),
      builder: (ctx, child) => Theme(data: ThemeData.dark(), child: child!),
    );
    if (picked == null) return;
    setState(() {
      _dateStr = '${picked.year}-${pad2(picked.month)}-${pad2(picked.day)}';
    });
    _onWallClockChanged();
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
              onDateTap: _pickDate,
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
  });

  final double bearing;
  final VoidCallback onCompassTap;
  final bool showInfo;
  final VoidCallback onInfoTap;
  final bool is3D;
  final VoidCallback onDimTap;
  final bool satellite;
  final VoidCallback onSatelliteTap;

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
    required this.onDateTap,
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
  final VoidCallback onDateTap;
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
    final buttonBg = isDark ? const Color(0xFF1E2126) : const Color(0xFFE6E8EB);
    final buttonBorder = isDark
        ? const Color(0xFF3A3F47)
        : const Color(0xFFCBCFD4);
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
              Row(
                children: [
                  GestureDetector(
                    onTap: onDateTap,
                    child: Container(
                      width: 30,
                      height: 30,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: buttonBg,
                        border: Border.all(color: buttonBorder),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.calendar_today,
                        size: 13,
                        color: onPanel,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
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
            ],
          ),
          SizedBox(
            height: 34,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  height: 16,
                  // Flutter insets a Slider's track by
                  // max(overlayRadius, thumbRadius) on each side (15px here,
                  // from the overlayShape below) so the thumb can travel
                  // edge-to-edge without clipping. This custom gradient
                  // "track" drawn underneath the (invisible) real one has to
                  // use the same inset, or the thumb visibly drifts away
                  // from the gradient's own color stops as you drag toward
                  // either end.
                  margin: const EdgeInsets.symmetric(horizontal: 15),
                  decoration: BoxDecoration(
                    gradient: buildDayGradient(sunrise, sunset, isDark: isDark),
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 0,
                    activeTrackColor: Colors.transparent,
                    inactiveTrackColor: Colors.transparent,
                    thumbColor: Colors.white,
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 10,
                      elevation: 1,
                    ),
                    overlayShape: const RoundSliderOverlayShape(
                      overlayRadius: 15,
                    ),
                  ),
                  child: Slider(
                    min: 0,
                    max: 1439,
                    value: minutes.toDouble(),
                    onChanged: (v) => onMinutesChanged(v.round()),
                  ),
                ),
              ],
            ),
          ),
          Text(
            formatSunTimes(sunrise, sunset),
            style: TextStyle(color: onPanelMuted, fontSize: 10.5),
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
