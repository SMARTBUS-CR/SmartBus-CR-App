import 'package:geolocator/geolocator.dart';

/// Whether the app can read the device location, and if not, why.
enum LocationAccess {
  /// Permission granted ("while in use") and location services on.
  granted,

  /// The user denied the permission; it can be requested again.
  denied,

  /// The user denied it permanently; only the app settings can change it.
  deniedForever,

  /// The device location (GPS) is turned off.
  serviceDisabled,
}

/// A position of the device, already reduced to what the map needs.
class DeviceLocation {
  const DeviceLocation({
    required this.latitude,
    required this.longitude,
    this.accuracyMeters = 0,
  });

  final double latitude;
  final double longitude;

  /// Radius (meters) of the 68% confidence circle reported by the device.
  final double accuracyMeters;

  factory DeviceLocation.fromPosition(Position position) => DeviceLocation(
    latitude: position.latitude,
    longitude: position.longitude,
    accuracyMeters: position.accuracy,
  );
}

/// Foreground ("while in use") location for the passenger screens.
///
/// Thin wrapper over `geolocator` so the screens never deal with permissions or
/// platform details, and tests can replace it with a fake.
class LocationService {
  const LocationService();

  /// Checks the access, asking for the permission when [request] is `true`
  /// and it can still be asked.
  Future<LocationAccess> checkAccess({bool request = true}) async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return LocationAccess.serviceDisabled;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied && request) {
      permission = await Geolocator.requestPermission();
    }

    return switch (permission) {
      LocationPermission.always ||
      LocationPermission.whileInUse => LocationAccess.granted,
      LocationPermission.deniedForever => LocationAccess.deniedForever,
      _ => LocationAccess.denied,
    };
  }

  /// Current position, or `null` if it cannot be obtained.
  Future<DeviceLocation?> currentLocation() async {
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      return DeviceLocation.fromPosition(position);
    } catch (_) {
      final last = await Geolocator.getLastKnownPosition();
      return last != null ? DeviceLocation.fromPosition(last) : null;
    }
  }

  /// Position updates while the screen is open (every ~10 m).
  Stream<DeviceLocation> watch() => Geolocator.getPositionStream(
    locationSettings: const LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 10,
    ),
  ).map(DeviceLocation.fromPosition);

  /// Opens the screen where the user can fix [access]: the device location
  /// settings (GPS off) or the app settings (permission denied forever).
  Future<void> openSettings(LocationAccess access) async {
    if (access == LocationAccess.serviceDisabled) {
      await Geolocator.openLocationSettings();
    } else {
      await Geolocator.openAppSettings();
    }
  }
}
