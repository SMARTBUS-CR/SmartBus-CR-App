import '../../../core/config/api_config.dart';
import '../../../core/network/api_client.dart';
import '../models/gps_fix.dart';
import '../models/trip_tracking.dart';

/// Talks to the **GPS microservice through the API Gateway**.
///
/// Reuses the shared [ApiClient], so:
/// - the base URL is always the Gateway ([ApiConfig.gatewayBaseUrl]),
/// - the `Authorization: Bearer <token>` header is attached automatically,
/// - network / HTTP errors arrive as `ApiException`.
class GpsLocationService {
  GpsLocationService({ApiClient? client}) : _client = client ?? ApiClient();

  final ApiClient _client;

  /// `POST {gateway}/gps/locations` — the driver sends one GPS reading.
  ///
  /// - `201`: stored → returns the id of the `gps-locations` resource.
  /// - `202` (`broadcast_only`, `duplicate`, `stale`): accepted but not stored
  ///   → returns `null`. Both are successes: no retry needed.
  ///
  /// Throws `ApiException` on failure (403 not the assigned driver, 409 the
  /// trip is not in progress, …).
  Future<String?> send(GpsFix fix) async {
    final body = await _client.post(
      ApiConfig.gpsLocations(),
      body: fix.toJsonApi(),
    );
    final data = body['data'];
    return data is Map ? data['id']?.toString() : null;
  }

  /// `GET {gateway}/gps/trips/{tripId}/location` — trip status, current bus
  /// position and its freshness (passenger map: when it opens, when the
  /// connection comes back and when the updates stop).
  ///
  /// Throws `ApiException` (`notFound` when the trip does not exist).
  Future<TripTracking> latestForTrip(String tripId) async {
    final body = await _client.get(ApiConfig.gpsTripLocation(tripId));
    return TripTracking.fromJsonApi(body);
  }

  /// `POST {gateway}/gps/broadcasting/auth` — signature to subscribe to a
  /// private channel (`private-trip.{tripId}`) of the GPS real-time server.
  ///
  /// Throws `ApiException` (`forbidden` when the trip finished, was cancelled
  /// or does not exist).
  Future<String> authorizeChannel({
    required String socketId,
    required String channelName,
  }) async {
    final body = await _client.post(
      ApiConfig.gpsBroadcastingAuth(),
      body: {'socket_id': socketId, 'channel_name': channelName},
    );
    final auth = body['auth'];
    if (auth is! String || auth.isEmpty) {
      throw const FormatException('broadcasting/auth: missing "auth".');
    }
    return auth;
  }
}
