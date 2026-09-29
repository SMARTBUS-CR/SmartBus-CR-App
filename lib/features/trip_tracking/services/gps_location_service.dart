import '../../../core/config/api_config.dart';
import '../../../core/network/api_client.dart';
import '../models/gps_fix.dart';

/// Talks to the **GPS microservice through the API Gateway**.
///
/// Reuses the shared [ApiClient], so:
/// - the base URL is always the Gateway ([ApiConfig.gatewayBaseUrl]),
/// - the `Authorization: Bearer <token>` header is attached automatically,
/// - network / HTTP errors arrive as `ApiException`.
class GpsLocationService {
  GpsLocationService({ApiClient? client}) : _client = client ?? ApiClient();

  final ApiClient _client;

  /// `POST {gateway}/gps/locations` — stores one GPS reading (HU1).
  ///
  /// Returns the id of the created `gps-locations` resource (may be `null` if
  /// the backend omits it). Throws `ApiException` on failure.
  Future<String?> send(GpsFix fix) async {
    final body = await _client.post(ApiConfig.gpsLocations(), body: fix.toJsonApi());
    final data = body['data'];
    return data is Map ? data['id']?.toString() : null;
  }

  /// `GET {gateway}/gps/trips/{tripId}/location` — latest known position of a
  /// trip (HU3, e.g. to place the marker when opening the map). Returns the raw
  /// JSON:API document.
  Future<Map<String, dynamic>> latestForTrip(String tripId) =>
      _client.get(ApiConfig.gpsTripLocation(tripId));
}
