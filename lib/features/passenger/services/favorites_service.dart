import '../../../core/config/api_config.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../models/favorite_route.dart';

/// Favorite routes of the logged-in passenger, in the Dashboard through the
/// Gateway (`/ops/favorites`). Every call sends the token: the backend takes
/// the user from it, so the app never sends a user id.
class FavoritesService {
  FavoritesService({ApiClient? client}) : _client = client ?? ApiClient();

  final ApiClient _client;

  /// `GET ops/favorites` — most recently saved first.
  Future<List<FavoriteRoute>> fetchFavorites() async {
    final body = await _client.get(ApiConfig.opsFavorites());
    final data = body['data'];
    final favorites = [
      if (data is List)
        for (final item in data.whereType<Map>())
          FavoriteRoute.fromJsonApi(
            Map<String, dynamic>.from(item),
            body['included'],
          ),
    ];
    return sortedBySavedAt(favorites);
  }

  /// `POST ops/favorites {route_id}`.
  ///
  /// A 409 means the route was already a favorite (another device, a double
  /// tap): the wanted state is reached, so it returns `null` instead of
  /// failing.
  Future<FavoriteRoute?> addFavorite(String routeId) async {
    try {
      final body = await _client.post(
        ApiConfig.opsFavorites(),
        body: {'route_id': routeId},
      );
      final data = body['data'];
      if (data is! Map) return null;
      return FavoriteRoute.fromJsonApi(
        Map<String, dynamic>.from(data),
        body['included'],
      );
    } on ApiException catch (e) {
      if (e.type == ApiErrorType.conflict) return null;
      rethrow;
    }
  }

  /// `DELETE ops/favorites/{route_id}`. A 404 means it was already removed,
  /// which is what the passenger wanted.
  Future<void> removeFavorite(String routeId) async {
    try {
      await _client.delete(ApiConfig.opsFavorite(routeId));
    } on ApiException catch (e) {
      if (e.type != ApiErrorType.notFound) rethrow;
    }
  }

  /// Most recent first; favorites without date go last.
  static List<FavoriteRoute> sortedBySavedAt(List<FavoriteRoute> favorites) {
    final sorted = [...favorites];
    sorted.sort((a, b) {
      final at = a.savedAt;
      final bt = b.savedAt;
      if (at == null || bt == null) {
        return at == null ? (bt == null ? 0 : 1) : -1;
      }
      return bt.compareTo(at);
    });
    return sorted;
  }
}
