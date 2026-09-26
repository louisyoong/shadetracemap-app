import 'dart:io';

import 'package:home_widget/home_widget.dart';

import 'device_location.dart';
import 'sun_math.dart';

// Must match the App Group configured in Xcode for both the Runner app
// target and the SunsetWidget extension target (Signing & Capabilities ->
// App Groups) - this is how the two processes share data on iOS. See
// ios/SunsetWidget/README.md for the one-time Xcode setup this needs.
const _iosAppGroupId = 'group.com.shadetracemap.shadetracemap';

// Must match the `kind`/@main struct name of the iOS Widget in
// ios/SunsetWidget/SunsetWidget.swift.
const _sunsetWidgetName = 'SunsetWidget';

const _initialLat = 3.1412;
const _initialLng = 101.68653;

/// Keeps the iOS home-screen widget's "today's sunset" data in sync with
/// the device's last known location.
///
/// The widget itself renders "now" with WidgetKit's own live-updating
/// `Text(date, style: .time)`, so this only ever needs to push the sunset
/// time - which only meaningfully changes by a couple of minutes a day -
/// not a per-second clock. iOS-only: there's no Android widget to sync yet,
/// and the underlying platform channel isn't implemented on desktop/web, so
/// this is a no-op everywhere else.
class HomeWidgetService {
  static Future<void> init() async {
    if (!Platform.isIOS) return;
    try {
      await HomeWidget.setAppGroupId(_iosAppGroupId);
      await sync();
    } catch (_) {
      // Best-effort: a widget that's a launch behind is better than a
      // crash on startup over something the user never directly asked for.
    }
  }

  /// Re-resolves the device location and pushes today's sunset (and a
  /// location label) into the widget's shared storage, then asks WidgetKit
  /// to reload it. Safe to call repeatedly (e.g. on every app resume).
  static Future<void> sync() async {
    if (!Platform.isIOS) return;

    var lat = _initialLat;
    var lng = _initialLng;
    var locationLabel = 'Kuala Lumpur';
    try {
      final position = await resolveDeviceLocation();
      lat = position.latitude;
      lng = position.longitude;
      locationLabel = 'My Location';
    } catch (_) {
      // Best-effort, same as every other screen's own location detection:
      // silently keep the default location rather than leaving the widget
      // without data over something the user didn't explicitly trigger.
    }

    final offsetHours = approxUtcOffsetHours(lng);
    final dayStartMs = localMidnightMs(
      DateTime.now().millisecondsSinceEpoch,
      offsetHours,
    );
    final sunTimes = findSunriseSunset(dayStartMs, lat, lng);
    final sunsetText = sunTimes.sunset == null
        ? '--:--'
        : '${pad2(sunTimes.sunset! ~/ 60)}:${pad2(sunTimes.sunset! % 60)}';

    try {
      await HomeWidget.saveWidgetData<String>('sunset_time', sunsetText);
      await HomeWidget.saveWidgetData<String>(
        'location_label',
        locationLabel,
      );
      await HomeWidget.updateWidget(iOSName: _sunsetWidgetName);
    } catch (_) {
      // Best-effort - see init().
    }
  }
}
