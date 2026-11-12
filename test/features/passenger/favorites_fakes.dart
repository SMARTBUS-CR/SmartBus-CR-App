import 'dart:async';

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

  @override
  Future<List<FavoriteRoute>> fetchFavorites() async {
    calls.add('fetch');
    await fetchGate?.future;
    if (fetchError != null) throw fetchError!;
    if (error != null) throw error!;
    return FavoritesService.sortedBySavedAt(stored);
  }

  @override
  Future<FavoriteRoute?> addFavorite(String routeId) async {
    calls.add('add $routeId');
    await gate?.future;
    if (error != null) throw error!;
    final saved = FavoriteRoute(
      id: 'fav-$routeId',
      route: TransitRoute(id: routeId, code: '', name: ''),
      savedAt: DateTime(2026, 11, 12),
    );
    stored.add(saved);
    return saved;
  }

  @override
  Future<void> removeFavorite(String routeId) async {
    calls.add('remove $routeId');
    await gate?.future;
    if (error != null) throw error!;
    stored.removeWhere((f) => f.routeId == routeId);
  }
}
