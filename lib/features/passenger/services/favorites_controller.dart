import 'package:flutter/foundation.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/storage/secure_session_store.dart';
import '../../operations/models/operations_models.dart';
import '../models/favorite_route.dart';
import 'favorites_service.dart';

/// The passenger's favorite routes, shared by every screen that shows a star
/// ("Mis favoritos", the route on the map, the route detail) so they all agree.
///
/// Changes are **optimistic**: the star and the list change at once and go
/// back if the server fails. While a route is being saved or removed, more
/// taps on it are ignored (no duplicate requests).
///
/// The list belongs to the session that loaded it: after logging in with
/// another account, [load] drops it and asks again.
class FavoritesController extends ChangeNotifier {
  FavoritesController({
    FavoritesService? service,
    SecureSessionStore? sessionStore,
  }) : _service = service ?? FavoritesService(),
       _session = sessionStore ?? SecureSessionStore();

  static FavoritesController? _shared;

  /// The app-wide instance.
  static FavoritesController get shared => _shared ??= FavoritesController();

  /// Tests plug in a controller with a fake service.
  @visibleForTesting
  static set shared(FavoritesController? controller) => _shared = controller;

  final FavoritesService _service;
  final SecureSessionStore _session;

  List<FavoriteRoute>? _favorites;
  ApiException? _error;
  bool _loading = false;
  Future<void>? _inFlight;
  String? _loadedForToken;
  final Set<String> _busy = {};

  /// `null` until the first load answers (or after a session change).
  List<FavoriteRoute>? get favorites => _favorites;

  /// Error of the last load (`null` if it worked).
  ApiException? get error => _error;

  bool get loading => _loading;

  bool isFavorite(String routeId) =>
      _favorites?.any((f) => f.routeId == routeId) ?? false;

  /// A save / remove of [routeId] is waiting for the server.
  bool isBusy(String routeId) => _busy.contains(routeId);

  /// `GET ops/favorites`. Without [force], it only asks when nothing was
  /// loaded for the current session yet. Never throws: see [error].
  Future<void> load({bool force = false}) async {
    final token = await _readToken();
    if (token != _loadedForToken && _loadedForToken != null) {
      // Another session: never show the previous account's favorites.
      _favorites = null;
      _loadedForToken = null;
      notifyListeners();
    }
    if (!force && _favorites != null && _error == null) return;
    return _inFlight ??= _fetch(token).whenComplete(() => _inFlight = null);
  }

  Future<void> _fetch(String? token) async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final server = await _service.fetchFavorites();
      final local = _favorites ?? const <FavoriteRoute>[];
      bool inServer(String id) => server.any((f) => f.routeId == id);
      bool inLocal(String id) => local.any((f) => f.routeId == id);
      // A route still waiting for the server keeps what the passenger did.
      _favorites = [
        for (final f in local)
          if (_busy.contains(f.routeId) && !inServer(f.routeId)) f,
        for (final f in server)
          if (!_busy.contains(f.routeId) || inLocal(f.routeId)) f,
      ];
      _loadedForToken = token;
    } on ApiException catch (e) {
      _error = e;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Saves [route]. Returns `false` when nothing was sent (already a favorite
  /// or a change on it is in flight). Throws the [ApiException] after putting
  /// the star back.
  Future<bool> add(TransitRoute route) async {
    if (isBusy(route.id) || isFavorite(route.id)) return false;
    _busy.add(route.id);
    final pending = FavoriteRoute.pending(route);
    _favorites = [pending, ...?_favorites];
    notifyListeners();
    try {
      final saved = await _service.addFavorite(route.id);
      if (saved != null) {
        _favorites = [
          for (final f in _favorites!)
            identical(f, pending) ? saved.withRoute(route) : f,
        ];
      }
      return true;
    } on ApiException {
      _favorites = [
        for (final f in _favorites!)
          if (!identical(f, pending)) f,
      ];
      rethrow;
    } finally {
      _busy.remove(route.id);
      notifyListeners();
    }
  }

  /// Removes [routeId]. Returns the removed favorite (for "Deshacer"), or
  /// `null` when nothing was sent. Throws the [ApiException] after putting
  /// it back in its place.
  Future<FavoriteRoute?> remove(String routeId) async {
    final current = _favorites;
    final index = current?.indexWhere((f) => f.routeId == routeId) ?? -1;
    if (isBusy(routeId) || current == null || index < 0) return null;
    final removed = current[index];
    _busy.add(routeId);
    _favorites = [...current]..removeAt(index);
    notifyListeners();
    try {
      await _service.removeFavorite(routeId);
      return removed;
    } on ApiException {
      final list = [..._favorites!];
      list.insert(index.clamp(0, list.length), removed);
      _favorites = list;
      rethrow;
    } finally {
      _busy.remove(routeId);
      notifyListeners();
    }
  }

  Future<String?> _readToken() async {
    try {
      return await _session.readToken();
    } catch (_) {
      return null;
    }
  }
}
