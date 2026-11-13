import 'dart:async';

import 'package:smartbus_drivers/core/network/api_exception.dart';
import 'package:smartbus_drivers/features/operations/models/operations_models.dart';
import 'package:smartbus_drivers/features/passenger/models/favorite_route.dart';
import 'package:smartbus_drivers/features/passenger/services/favorites_service.dart';

/// Favorite of [route], saved at [savedAt].
FavoriteRoute favoriteOf(
  TransitRoute route, {
  DateTime? savedAt,
  String? label,
  String? companyName,
}) => FavoriteRoute(
  id: 'fav-${route.id}',
  route: route,
  label: label,
  companyName: companyName,
  savedAt: savedAt ?? DateTime(2026, 11, 11),
);

/// FavoritesService in memory: records the calls; [error] makes the next
/// calls fail; [gate] holds add / remove until completed.
class FakeFavoritesService extends FavoritesService {
  FakeFavoritesService({List<FavoriteRoute> favorites = const []})
    : stored = [...favorites];

  final List<FavoriteRoute> stored;
  final List<String> calls = [];

  /// Thrown by every call while not null.
  Exception? error;

  /// Thrown only by [fetchFavorites] while not null.
  Exception? fetchError;

  /// While not null, add / remove wait for it.
  Completer<void>? gate;

  /// While not null, [fetchFavorites] waits for it.
  Completer<void>? fetchGate;

  /// Routes whose remove / add fails with [failure] (partial failures).
  final Set<String> failingRoutes = {};
  Exception failure = const ApiException(
    ApiErrorType.noConnection,
    'Sin conexión a Internet.',
  );

  /// Requests waiting at the same time, and the most seen (parallelism).
  int _inFlight = 0;
  int maxInFlight = 0;

  Future<void> _request(String routeId) async {
    _inFlight++;
    if (_inFlight > maxInFlight) maxInFlight = _inFlight;
    try {
      await gate?.future;
      // Let the other parallel requests start before answering.
      await Future<void>.delayed(Duration.zero);
      if (error != null) throw error!;
      if (failingRoutes.contains(routeId)) throw failure;
    } finally {
      _inFlight--;
    }
  }

  @override
  Future<List<FavoriteRoute>> fetchFavorites() async {
    calls.add('fetch');
    await fetchGate?.future;
    if (fetchError != null) throw fetchError!;
    if (error != null) throw error!;
    return FavoritesService.sortedBySavedAt(stored);
  }

  @override
  Future<FavoriteRoute?> addFavorite(String routeId, {String? label}) async {
    calls.add(label == null ? 'add $routeId' : 'add $routeId ($label)');
    await _request(routeId);
    final saved = FavoriteRoute(
      id: 'fav-$routeId',
      route: TransitRoute(id: routeId, code: '', name: ''),
      label: label,
      savedAt: DateTime(2026, 11, 12),
    );
    stored.add(saved);
    return saved;
  }

  @override
  Future<void> renameFavorite(String routeId, String? label) async {
    calls.add('rename $routeId ${label ?? '-'}');
    await _request(routeId);
    final i = stored.indexWhere((f) => f.routeId == routeId);
    if (i >= 0) stored[i] = stored[i].withLabel(label);
  }

  @override
  Future<void> removeFavorite(String routeId) async {
    calls.add('remove $routeId');
    await _request(routeId);
    stored.removeWhere((f) => f.routeId == routeId);
  }
}
