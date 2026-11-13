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
  /// [label] keeps the alias when "Deshacer" saves a route again.
  Future<bool> add(TransitRoute route, {String? label}) async {
    if (isBusy(route.id) || isFavorite(route.id)) return false;
    _busy.add(route.id);
    final pending = FavoriteRoute.pending(route, label: label);
    _favorites = [pending, ...?_favorites];
    notifyListeners();
    try {
      final saved = await _service.addFavorite(route.id, label: label);
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

  /// Longest alias the Dashboard accepts.
  static const maxLabelLength = 50;

  /// Gives [routeId] the alias [label] (trimmed; empty removes it). The list
  /// changes at once and goes back if the server fails. Returns `false` when
  /// nothing was sent (not a favorite, a change in flight, or the same
  /// alias). Throws the [ApiException] after restoring the previous alias.
  Future<bool> rename(String routeId, String? label) async {
    final current = _favorites;
    final index = current?.indexWhere((f) => f.routeId == routeId) ?? -1;
    if (isBusy(routeId) || current == null || index < 0) return false;
    final trimmed = label?.trim() ?? '';
    final wanted = trimmed.isEmpty
        ? null
        : (trimmed.length > maxLabelLength
              ? trimmed.substring(0, maxLabelLength)
              : trimmed);
    final previous = current[index];
    if (previous.label == wanted) return false;

    _busy.add(routeId);
    _replace(routeId, previous.withLabel(wanted));
    notifyListeners();
    try {
      await _service.renameFavorite(routeId, wanted);
      return true;
    } on ApiException {
      _replace(routeId, previous);
      rethrow;
    } finally {
      _busy.remove(routeId);
      notifyListeners();
    }
  }

  void _replace(String routeId, FavoriteRoute favorite) {
    _favorites = [
      for (final f in _favorites ?? const <FavoriteRoute>[])
        f.routeId == routeId ? favorite : f,
    ];
  }

  /// Requests sent at the same time by [removeMany] / [restore] (there is no
  /// bulk endpoint: one request per route).
  static const maxParallelRequests = 4;

  /// Removes several routes ("Eliminar (N)", "Eliminar todos"). They leave
  /// the list at once; the ones the server could not remove go back to their
  /// place. Routes not in the list or with a change in flight are skipped, so
  /// each route is sent at most once. Never throws: see [BulkRemoval].
  Future<BulkRemoval> removeMany(Iterable<String> routeIds) async {
    final current = _favorites ?? const <FavoriteRoute>[];
    final wanted = routeIds.toSet();
    final targets = [
      for (final f in current)
        if (wanted.contains(f.routeId) && !isBusy(f.routeId)) f,
    ];
    if (targets.isEmpty) return const BulkRemoval(removed: [], order: []);

    final order = [for (final f in current) f.routeId];
    final ids = {for (final f in targets) f.routeId};
    _busy.addAll(ids);
    _favorites = [
      for (final f in current)
        if (!ids.contains(f.routeId)) f,
    ];
    notifyListeners();

    final failed = <FavoriteRoute>[];
    final errors = <ApiException>[];
    await _limited(targets, (favorite) async {
      try {
        await _service.removeFavorite(favorite.routeId);
      } on ApiException catch (e) {
        failed.add(favorite);
        errors.add(e);
      }
    });

    _busy.removeAll(ids);
    for (final favorite in failed) {
      _putBack(favorite, order);
    }
    notifyListeners();
    return BulkRemoval(
      removed: [
        for (final f in targets)
          if (!failed.contains(f)) f,
      ],
      failed: [
        for (final f in targets)
          if (failed.contains(f)) f,
      ],
      order: order,
      error: _worst(errors),
    );
  }

  /// "Deshacer" of [removal]: saves its removed routes again (with their
  /// alias) and puts them back in their previous order at once. Returns the
  /// ones the server could not save (they leave the list again). Never
  /// throws: see [BulkRemoval.error] of the result.
  Future<BulkRemoval> restore(BulkRemoval removal) async {
    final targets = [
      for (final f in removal.removed)
        if (!isFavorite(f.routeId) && !isBusy(f.routeId)) f,
    ];
    if (targets.isEmpty) return const BulkRemoval(removed: [], order: []);

    final ids = {for (final f in targets) f.routeId};
    _busy.addAll(ids);
    for (final favorite in targets) {
      _putBack(favorite, removal.order);
    }
    notifyListeners();

    final failed = <FavoriteRoute>[];
    final errors = <ApiException>[];
    await _limited(targets, (favorite) async {
      try {
        // 409 (already saved again elsewhere) counts as saved.
        await _service.addFavorite(favorite.routeId, label: favorite.label);
      } on ApiException catch (e) {
        failed.add(favorite);
        errors.add(e);
      }
    });

    _busy.removeAll(ids);
    _favorites = [
      for (final f in _favorites ?? const <FavoriteRoute>[])
        if (!failed.any((g) => g.routeId == f.routeId)) f,
    ];
    notifyListeners();
    return BulkRemoval(
      removed: [
        for (final f in targets)
          if (!failed.contains(f)) f,
      ],
      failed: failed,
      order: removal.order,
      error: _worst(errors),
    );
  }

  /// Inserts [favorite] after the routes that were before it in [order]
  /// (routes added since then, not in [order], stay first).
  void _putBack(FavoriteRoute favorite, List<String> order) {
    final list = [...?_favorites];
    if (list.any((f) => f.routeId == favorite.routeId)) return;
    final position = order.indexOf(favorite.routeId);
    var index = 0;
    while (index < list.length) {
      final other = order.indexOf(list[index].routeId);
      if (other > position) break;
      index++;
    }
    list.insert(index, favorite);
    _favorites = list;
  }

  /// Runs [task] for every item, at most [maxParallelRequests] at a time.
  static Future<void> _limited<T>(
    List<T> items,
    Future<void> Function(T) task,
  ) async {
    var next = 0;
    Future<void> worker() async {
      while (next < items.length) {
        await task(items[next++]);
      }
    }

    final workers = items.length < maxParallelRequests
        ? items.length
        : maxParallelRequests;
    await Future.wait([for (var i = 0; i < workers; i++) worker()]);
  }

  /// The error to tell the passenger: a 401 wins (it ends the session).
  static ApiException? _worst(List<ApiException> errors) {
    if (errors.isEmpty) return null;
    return errors.firstWhere(
      (e) => e.type == ApiErrorType.unauthorized,
      orElse: () => errors.first,
    );
  }

  Future<String?> _readToken() async {
    try {
      return await _session.readToken();
    } catch (_) {
      return null;
    }
  }
}

/// Result of [FavoritesController.removeMany] (or of its "Deshacer",
/// [FavoritesController.restore]).
class BulkRemoval {
  const BulkRemoval({
    required this.removed,
    required this.order,
    this.failed = const [],
    this.error,
  });

  /// Routes the server removed (or, for [FavoritesController.restore], saved
  /// again), in list order.
  final List<FavoriteRoute> removed;

  /// Routes it could not handle: they are back in the list (or, for a
  /// restore, still out of it). Retry with their ids.
  final List<FavoriteRoute> failed;

  /// Route ids of the whole list before removing, to put routes back in place.
  final List<String> order;

  /// Why some failed (a 401 when any request had one).
  final ApiException? error;

  bool get nothingSent => removed.isEmpty && failed.isEmpty;
}
