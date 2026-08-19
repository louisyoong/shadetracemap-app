import 'package:geolocator/geolocator.dart';

/// Thrown by [resolveDeviceLocation] with a user-facing message, so callers
/// can surface it directly instead of pattern-matching platform exceptions.
class DeviceLocationException implements Exception {
  const DeviceLocationException(this.message);
  final String message;
}

/// Resolves the device's current GPS position, handling the
/// services-enabled check and the permission-request dance shared by every
/// screen that wants to center on "where the phone is".
Future<Position> resolveDeviceLocation() async {
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
