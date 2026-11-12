import 'package:flutter/material.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme.dart';
import '../../widgets/smartbus_header.dart';
import '../operations/models/operations_models.dart';
import '../operations/services/operations_service.dart';
import 'buses_in_progress_screen.dart';
import 'favorite_star.dart';
import 'models/favorite_route.dart';
import 'services/favorites_controller.dart';

/// "Mis favoritos" (`/passenger/favorites`): the routes the passenger saved,
/// most recent first. Swipe or tap the star to remove one ("Deshacer" brings
/// it back); tap a route to open it. "Ver ruta" there closes this screen with
/// a [RouteSelection], so the home map draws it.
class FavoriteRoutesScreen extends StatefulWidget {
  const FavoriteRoutesScreen({super.key, this.favorites, this.operations});

  /// Defaults to [FavoritesController.shared].
  final FavoritesController? favorites;

  /// For the route detail ([RouteBusesScreen]).
  final OperationsService? operations;

  @override
  State<FavoriteRoutesScreen> createState() => _FavoriteRoutesScreenState();
}

class _FavoriteRoutesScreenState extends State<FavoriteRoutesScreen> {
  FavoritesController get _favorites =>
      widget.favorites ?? FavoritesController.shared;

  @override
  void initState() {
    super.initState();
    _favorites.addListener(_onChange);
    // Always ask: favorites may have changed on another device.
    _favorites.load(force: true);
  }

  @override
  void dispose() {
    _favorites.removeListener(_onChange);
    super.dispose();
  }

  bool _leaving = false;

  void _onChange() {
    final error = _favorites.error;
    if (_leaving || error?.type != ApiErrorType.unauthorized) return;
    _leaving = true;
    sessionExpired(
      ScaffoldMessenger.of(context),
      Navigator.of(context),
      error!.message,
    );
  }

  Future<void> _refresh() async {
    await _favorites.load(force: true);
    final error = _favorites.error;
    // With a list already shown, a failed refresh keeps it and just says so.
    if (!mounted || error == null || _favorites.favorites == null) return;
    if (error.type == ApiErrorType.unauthorized) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(error.message),
          backgroundColor: SmartBusColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  Future<void> _open(TransitRoute route) async {
    final selection = await Navigator.push<RouteSelection>(
      context,
      MaterialPageRoute<RouteSelection>(
        builder: (_) => RouteBusesScreen(
          route: route,
          operations: widget.operations,
          favorites: widget.favorites,
        ),
      ),
    );
    if (selection != null && mounted) Navigator.pop(context, selection);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SmartBusColors.blanco,
      body: Column(
        children: [
          SmartBusHeader(
            title: 'Mis favoritos',
            subtitle: 'Tus rutas guardadas',
            type: SmartBusUserType.passenger,
            compact: true,
            onBack: Navigator.canPop(context)
                ? () => Navigator.pop(context)
                : null,
          ),
          Expanded(
            child: ListenableBuilder(
              listenable: _favorites,
              builder: (context, _) => _body(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _body() {
    final favorites = _favorites.favorites;
    final error = _favorites.error;

    if (favorites == null) {
      if (error != null && error.type != ApiErrorType.unauthorized) {
        return PassengerMessage(
          key: const Key('favorites-error'),
          icon: Icons.cloud_off_outlined,
          title: 'No se pudieron cargar tus favoritos',
          message: error.message,
          actionLabel: 'Reintentar',
          onAction: () => _favorites.load(force: true),
        );
      }
      return const Center(
        key: Key('favorites-loading'),
        child: CircularProgressIndicator(),
      );
    }

    if (favorites.isEmpty) {
      return PassengerMessage(
        key: const Key('favorites-empty'),
        icon: Icons.star_border_rounded,
        title: 'Aún no tienes rutas favoritas.',
        message:
            'Toca la estrella de una ruta (en el mapa o en "Buses en curso") '
            'para guardarla aquí.',
        actionLabel: 'Actualizar',
        onAction: _refresh,
      );
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.separated(
        key: const Key('favorites-list'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: favorites.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, i) {
          final favorite = favorites[i];
          return Dismissible(
            key: Key('favorite-${favorite.routeId}'),
            direction: DismissDirection.endToStart,
            background: const _RemoveBackground(),
            // The controller removes it (and puts it back if that fails).
            confirmDismiss: (_) async {
              removeFavorite(context, _favorites, favorite.routeId);
              return false;
            },
            child: FavoriteRouteTile(
              favorite: favorite,
              favorites: _favorites,
              onTap: () => _open(favorite.route),
            ),
          );
        },
      ),
    );
  }
}

/// One favorite: code, name (2 lines max), alias / company, and its star.
class FavoriteRouteTile extends StatelessWidget {
  const FavoriteRouteTile({
    super.key,
    required this.favorite,
    required this.favorites,
    required this.onTap,
  });

  final FavoriteRoute favorite;
  final FavoritesController favorites;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final route = favorite.route;
    final details = [
      if (favorite.label != null) favorite.label!,
      if (favorite.companyName != null) favorite.companyName!,
    ].join(' · ');

    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.fromLTRB(20, 4, 8, 4),
      leading: Container(
        constraints: const BoxConstraints(minWidth: 48, maxWidth: 72),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: SmartBusColors.verdePasajero,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          route.code.isEmpty ? '—' : route.code,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: SmartBusColors.blanco,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      title: Text(
        route.name.isEmpty ? 'Ruta' : route.name,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: details.isEmpty
          ? null
          : Text(details, maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: FavoriteStarButton(route: route, controller: favorites),
    );
  }
}

class _RemoveBackground extends StatelessWidget {
  const _RemoveBackground();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: SmartBusColors.error,
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.delete_outline, color: SmartBusColors.blanco),
          SizedBox(width: 8),
          Text(
            'Quitar',
            style: TextStyle(
              color: SmartBusColors.blanco,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
