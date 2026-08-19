import 'package:geolocator/geolocator.dart';

/// Thrown by [resolveDeviceLocation] with a user-facing message, so callers
/// can surface it directly instead of pattern-matching platform exceptions.
class DeviceLocationException implements Exception {
  const DeviceLocationException(this.message);
  final String message;
}

// ShadeMap, Sun Simulator and Weather all call resolveDeviceLocation() on
// launch, and RootShell's IndexedStack builds every tab up front - so their
// initState calls land in the same frame. The geolocator plugin serializes
// permission requests natively and throws (rather than queuing) if a second
// requestPermission() comes in while the first is still pending, so without
// this in-flight cache whichever screen lost that race would silently fall
// back to the default location. Sharing one in-flight Future across callers
// makes concurrent calls collapse into a single platform request instead of
// racing.
Future<Position>? _inFlightLocation;

/// Resolves the device's current GPS position, handling the
/// services-enabled check and the permission-request dance shared by every
/// screen that wants to center on "where the phone is".
Future<Position> resolveDeviceLocation() {
  final inFlight = _inFlightLocation;
  if (inFlight != null) return inFlight;
  final future = _resolveDeviceLocation();
  _inFlightLocation = future;
  future.whenComplete(() => _inFlightLocation = null);
  return future;
}

Future<Position> _resolveDeviceLocation() async {
  if (!await Geolocator.isLocationServiceEnabled()) {
    throw const DeviceLocationException('Location services are off.');
  }
  var permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
  }
  if (permission == LocationPermission.denied ||
      permission == LocationPermission.deniedForever) {
    throw const DeviceLocationException('Location permission denied.');
  }
  return Geolocator.getCurrentPosition(
    locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
  );
}
