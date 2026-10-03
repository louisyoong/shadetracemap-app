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

/// Keeps the iOS home-screen widget's sunrise/sunset data in sync with the
/// device's last known location.
///
/// Pushes four instants - yesterday's sunset, today's sunrise/sunset, and
/// tomorrow's sunrise - so the widget can always count down to whichever
/// event is actually next (sunrise before dawn, sunset during the day,
/// tomorrow's sunrise once tonight's sun has already set) instead of only
/// ever knowing about today's daylight span. The widget itself renders
/// "now" - and a live countdown - with WidgetKit/SwiftUI's own
/// live-updating `Text(date, style:)`/`Text(timerInterval:)`, so this only
/// ever needs to push instants (as epoch milliseconds, so Swift can format
/// and countdown against them itself), not a per-second clock. Those
/// instants only meaningfully change once a day, so there's no need to push
/// updates more often than app launch/resume. iOS-only: there's no Android
/// widget to sync yet, and the underlying platform channel isn't
/// implemented on desktop/web, so this is a no-op everywhere else.
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

  /// Re-resolves the device location and pushes today's sunrise/sunset (and
  /// a location label) into the widget's shared storage, then asks
  /// WidgetKit to reload it. Safe to call repeatedly (e.g. on every app
  /// resume).
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
    const dayMs = 24 * 60 * 60000;

    // Today's sunrise/sunset, plus yesterday's sunset and tomorrow's
    // sunrise - the widget needs all four so it can always show whichever
    // event is actually next (sunrise before dawn, sunset during the day,
    // *tomorrow's* sunrise once the sun has already set tonight) with a
    // precise progress fraction through whichever window that is, not just
    // today's daylight span.
    int? epochFor(int dayStart, int? minutesOfDay) =>
        minutesOfDay == null ? null : dayStart + minutesOfDay * 60000;

    final todayTimes = findSunriseSunset(dayStartMs, lat, lng);
    final yesterdayTimes = findSunriseSunset(dayStartMs - dayMs, lat, lng);
    final tomorrowTimes = findSunriseSunset(dayStartMs + dayMs, lat, lng);

    final prevSunsetEpochMs = epochFor(dayStartMs - dayMs, yesterdayTimes.sunset);
    final sunriseEpochMs = epochFor(dayStartMs, todayTimes.sunrise);
    final sunsetEpochMs = epochFor(dayStartMs, todayTimes.sunset);
    final nextSunriseEpochMs = epochFor(dayStartMs + dayMs, tomorrowTimes.sunrise);

    try {
      await HomeWidget.saveWidgetData<String>(
        'prev_sunset_epoch_ms',
        prevSunsetEpochMs?.toString() ?? '',
      );
      await HomeWidget.saveWidgetData<String>(
        'sunrise_epoch_ms',
        sunriseEpochMs?.toString() ?? '',
      );
      await HomeWidget.saveWidgetData<String>(
        'sunset_epoch_ms',
        sunsetEpochMs?.toString() ?? '',
      );
      await HomeWidget.saveWidgetData<String>(
        'next_sunrise_epoch_ms',
        nextSunriseEpochMs?.toString() ?? '',
      );
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
