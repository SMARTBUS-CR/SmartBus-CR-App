import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Android 13+ notification permission (`POST_NOTIFICATIONS`).
///
/// The driver's GPS runs as a foreground service whose notification
/// ("SmartBus · recorrido activo") tells the driver it is still sending. On
/// Android 13+ that notification is hidden unless notifications are allowed.
/// The GPS works either way, so a denial never blocks the trip.
///
/// Implemented in `MainActivity.kt` (no extra package).
class NotificationPermission {
  const NotificationPermission();

  static const _channel = MethodChannel('smartbus/notifications');

  /// Asks for the permission if needed. `true` when allowed (or not needed:
  /// older Android, iOS); `false` when denied or the request failed.
  Future<bool> request() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return true;
    try {
      return await _channel.invokeMethod<bool>('requestNotifications') ?? false;
    } catch (_) {
      return false; // no native side (tests) or the request failed
    }
  }
}
