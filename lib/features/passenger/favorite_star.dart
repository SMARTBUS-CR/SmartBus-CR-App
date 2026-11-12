import 'package:flutter/material.dart';

import '../../core/network/api_exception.dart';
import '../../core/storage/secure_session_store.dart';
import '../../core/theme.dart';
import '../operations/models/operations_models.dart';
import 'services/favorites_controller.dart';

/// Star that saves / removes [route] from the passenger's favorites. Used
/// wherever a route is shown (map panel, route detail, "Mis favoritos").
///
/// With [showLabel] it is a text button ("Guardar en favoritos" / "En tus
/// favoritos"); otherwise just the icon.
class FavoriteStarButton extends StatefulWidget {
  const FavoriteStarButton({
    super.key,
    required this.route,
    this.controller,
    this.showLabel = false,
    this.color = SmartBusColors.verdePasajero,
  });

  final TransitRoute route;

  /// Defaults to [FavoritesController.shared].
  final FavoritesController? controller;
  final bool showLabel;
  final Color color;

  @override
  State<FavoriteStarButton> createState() => _FavoriteStarButtonState();
}

class _FavoriteStarButtonState extends State<FavoriteStarButton> {
  FavoritesController get _favorites =>
      widget.controller ?? FavoritesController.shared;

  @override
  void initState() {
    super.initState();
    // Know whether this route is already a favorite.
    _favorites.load();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _favorites,
      builder: (context, _) {
        final route = widget.route;
        final saved = _favorites.isFavorite(route.id);
        final icon = Icon(
          saved ? Icons.star_rounded : Icons.star_border_rounded,
          color: widget.color,
        );
        final label = saved ? 'Quitar de favoritos' : 'Agregar a favoritos';
        void onPressed() => toggleFavorite(context, _favorites, route);

        if (widget.showLabel) {
          return TextButton.icon(
            key: Key('favorite-star-${route.id}'),
            onPressed: onPressed,
            icon: icon,
            label: Text(
              saved ? 'En tus favoritos' : 'Guardar en favoritos',
              style: TextStyle(
                color: widget.color,
                fontWeight: FontWeight.w600,
              ),
            ),
          );
        }
        return IconButton(
          key: Key('favorite-star-${route.id}'),
          tooltip: label,
          icon: icon,
          onPressed: onPressed,
        );
      },
    );
  }
}

/// Saves [route] if it is not a favorite, or removes it (with "Deshacer").
Future<void> toggleFavorite(
  BuildContext context,
  FavoritesController favorites,
  TransitRoute route,
) {
  return favorites.isFavorite(route.id)
      ? removeFavorite(context, favorites, route.id)
      : addFavorite(context, favorites, route);
}

Future<void> addFavorite(
  BuildContext context,
  FavoritesController favorites,
  TransitRoute route,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final navigator = Navigator.of(context);
  try {
    final sent = await favorites.add(route);
    if (sent) showFavoritesMessage(messenger, 'Ruta agregada a favoritos.');
  } on ApiException catch (e) {
    await handleFavoritesError(messenger, navigator, e);
  }
}

/// Removes [routeId]; the SnackBar offers "Deshacer", which saves it again.
Future<void> removeFavorite(
  BuildContext context,
  FavoritesController favorites,
  String routeId,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final navigator = Navigator.of(context);
  try {
    final removed = await favorites.remove(routeId);
    if (removed == null) return;
    showFavoritesMessage(
      messenger,
      'Ruta eliminada de favoritos.',
      action: SnackBarAction(
        label: 'Deshacer',
        onPressed: () async {
          try {
            await favorites.add(removed.route, label: removed.label);
          } on ApiException catch (e) {
            await handleFavoritesError(messenger, navigator, e);
          }
        },
      ),
    );
  } on ApiException catch (e) {
    await handleFavoritesError(messenger, navigator, e);
  }
}

/// 401: the session is cleared and the passenger goes to login. Anything
/// else: the star / list are already back; just say why.
Future<void> handleFavoritesError(
  ScaffoldMessengerState messenger,
  NavigatorState navigator,
  ApiException e,
) async {
  if (e.type == ApiErrorType.unauthorized) {
    await sessionExpired(messenger, navigator, e.message);
    return;
  }
  showFavoritesMessage(messenger, e.message, color: SmartBusColors.error);
}

/// Clears the session and opens login with [message].
Future<void> sessionExpired(
  ScaffoldMessengerState messenger,
  NavigatorState navigator,
  String message, {
  SecureSessionStore? sessionStore,
}) async {
  try {
    await (sessionStore ?? SecureSessionStore()).clear();
  } catch (_) {
    // Nothing stored to clear.
  }
  showFavoritesMessage(messenger, message, color: SmartBusColors.error);
  navigator.pushNamedAndRemoveUntil('/login', (_) => false);
}

void showFavoritesMessage(
  ScaffoldMessengerState messenger,
  String message, {
  Color? color,
  SnackBarAction? action,
}) {
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        action: action,
      ),
    );
}
