import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/config/api_config.dart';
import '../../../core/realtime/pusher_connection.dart';
import '../models/trip_tracking.dart';
import 'gps_location_service.dart';

/// Live `BusLocationUpdated` events of one trip.
abstract interface class TripLiveFeed {
  /// Positions received in real time.
  Stream<BusLocationUpdate> get locations;

  /// `true` while the real-time connection is up. Events sent while it is
  /// down are lost: refresh the position when it comes back.
  ValueListenable<bool> get connected;

  /// The channel was refused (the trip finished, was cancelled or does not
  /// exist) — check the trip status.
  Stream<Object> get rejections;

  void follow(String tripId);

  Future<void> dispose();
}

/// [TripLiveFeed] over the GPS service's Reverb: channel `private-trip.{id}`,
/// event `BusLocationUpdated`. Authorized through the Gateway.
class ReverbTripFeed implements TripLiveFeed {
  ReverbTripFeed(this._connection) {
    _connection.state.addListener(_onState);
    _eventSub = _connection.events.listen(_onEvent);
    _errorSub = _connection.subscriptionErrors.listen(
      (e) => _rejections.add(e.error),
    );
  }

  /// Real feed with the app config, or `null` when `REVERB_APP_KEY` is not set
  /// (the tracker then works by asking the position periodically).
  static ReverbTripFeed? fromConfig({GpsLocationService? service}) {
    final uri = ApiConfig.reverbUri();
    if (uri == null) return null;
    final gps = service ?? GpsLocationService();
    return ReverbTripFeed(
      PusherConnection(
        uri: uri,
        authorize: (socketId, channel) =>
            gps.authorizeChannel(socketId: socketId, channelName: channel),
      ),
    );
  }

  static const eventName = 'BusLocationUpdated';

  final PusherConnection _connection;
  final StreamController<BusLocationUpdate> _locations =
      StreamController.broadcast();
  final StreamController<Object> _rejections = StreamController.broadcast();
  final ValueNotifier<bool> _connected = ValueNotifier(false);
  late final StreamSubscription<RealtimeEvent> _eventSub;
  late final StreamSubscription<RealtimeSubscriptionError> _errorSub;

  @override
  Stream<BusLocationUpdate> get locations => _locations.stream;

  @override
  ValueListenable<bool> get connected => _connected;

  @override
  Stream<Object> get rejections => _rejections.stream;

  static String channelFor(String tripId) => 'private-trip.$tripId';

  @override
  void follow(String tripId) {
    _connection
      ..subscribe(channelFor(tripId))
      ..connect();
  }

  void _onState() => _connected.value =
      _connection.state.value == RealtimeConnectionState.connected;

  void _onEvent(RealtimeEvent event) {
    if (event.event != eventName) return;
    try {
      _locations.add(BusLocationUpdate.fromJson(event.data));
    } catch (_) {
      // Malformed payload: ignore it, the next one will move the bus.
    }
  }

  @override
  Future<void> dispose() async {
    _connection.state.removeListener(_onState);
    await _eventSub.cancel();
    await _errorSub.cancel();
    await _connection.dispose();
    await _locations.close();
    await _rejections.close();
    _connected.dispose();
  }
}
