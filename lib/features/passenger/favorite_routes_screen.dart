import 'package:flutter/material.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme.dart';
import '../../widgets/passenger_bottom_nav.dart';
import '../../widgets/smartbus_header.dart';
import '../operations/models/operations_models.dart';
import '../operations/services/operations_service.dart';
import 'buses_in_progress_screen.dart';
import 'favorite_star.dart';
import 'models/favorite_route.dart';
import 'services/favorites_controller.dart';

/// "Mis favoritos" (`/passenger/favorites`, the **Favoritos** tab of the
/// bottom bar): the routes the passenger saved, most recent first. Tap a route
/// to open it; "Ver ruta" there goes to the home map with a [RouteSelection],
/// which draws it.
///
/// Removing:
/// - one route: its star, or swipe it ("Deshacer" brings it back);
/// - several: "Editar" → select → "Eliminar (N)" (with confirmation);
/// - all: menu ⋮ → "Eliminar todos" (with confirmation).
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

  /// Edit mode: checkboxes instead of stars, no swipe.
  bool _editing = false;
  final Set<String> _selected = {};

  /// A bulk removal is waiting for the server.
  bool _deleting = false;

  bool _leaving = false;

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

  void _onChange() {
    final error = _favorites.error;
    if (error?.type == ApiErrorType.unauthorized) _sessionExpired(error!);
  }

  void _sessionExpired(ApiException error) {
    if (_leaving || !mounted) return;
    _leaving = true;
    sessionExpired(
      ScaffoldMessenger.of(context),
      Navigator.of(context),
      error.message,
    );
  }

  Future<void> _refresh() async {
    await _favorites.load(force: true);
    final error = _favorites.error;
    // With a list already shown, a failed refresh keeps it and just says so.
    if (!mounted || error == null || _favorites.favorites == null) return;
    if (error.type == ApiErrorType.unauthorized) return;
    showFavoritesMessage(
      ScaffoldMessenger.of(context),
      error.message,
      color: SmartBusColors.error,
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
    if (selection == null || !mounted) return;
    // "Ver ruta": back to the map that opened this screen, or — as the
    // "Favoritos" tab — to the home map, which draws the route.
    if (Navigator.canPop(context)) {
      Navigator.pop(context, selection);
    } else {
      Navigator.pushReplacementNamed(
        context,
        '/passenger/home',
        arguments: selection,
      );
    }
  }

  void _onTabTap(int index) {
    switch (index) {
      case 0:
        Navigator.pushReplacementNamed(context, '/passenger/home');
      case 1:
        return; // already on Favoritos
      case 2:
        Navigator.pushReplacementNamed(context, '/passenger/account');
    }
  }

  // --- Edit mode ------------------------------------------------------------

  void _startEditing() => setState(() {
    _editing = true;
    _selected.clear();
  });

  void _stopEditing() => setState(() {
    _editing = false;
    _selected.clear();
  });

  void _toggle(String routeId) => setState(() {
    if (!_selected.remove(routeId)) _selected.add(routeId);
  });

  void _toggleAll(List<FavoriteRoute> favorites) => setState(() {
    final all = favorites.every((f) => _selected.contains(f.routeId));
    _selected.clear();
    if (!all) _selected.addAll(favorites.map((f) => f.routeId));
  });

  // --- Removing several -----------------------------------------------------

  Future<void> _deleteSelected() async {
    final ids = _selected.toList();
    final confirmed = await _confirm(
      title: '¿Eliminar ${_routes(ids.length)} de tus favoritos?',
      message: 'Podrás deshacerlo justo después.',
    );
    if (confirmed) await _delete(ids);
  }

  Future<void> _deleteAll() async {
    final favorites = _favorites.favorites ?? const <FavoriteRoute>[];
    if (favorites.isEmpty) return;
    final confirmed = await _confirm(
      title: '¿Eliminar todas tus rutas favoritas?',
      message:
          'Se quitarán ${_routes(favorites.length)}. Podrás deshacerlo '
          'justo después.',
    );
    if (confirmed) await _delete([for (final f in favorites) f.routeId]);
  }

  Future<bool> _confirm({
    required String title,
    required String message,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const Key('delete-favorites-dialog'),
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            key: const Key('delete-favorites-cancel'),
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            key: const Key('delete-favorites-confirm'),
            style: FilledButton.styleFrom(
              backgroundColor: SmartBusColors.error,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  /// Removes [routeIds]; edit mode closes at once.
  Future<void> _delete(List<String> routeIds) async {
    if (_deleting || routeIds.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _deleting = true;
      _editing = false;
      _selected.clear();
    });

    final result = await _favorites.removeMany(routeIds);
    if (mounted) setState(() => _deleting = false);
    if (!mounted || result.nothingSent) return;

    final error = result.error;
    if (error?.type == ApiErrorType.unauthorized) {
      _sessionExpired(error!);
      return;
    }

    if (result.failed.isNotEmpty) {
      final failed = [for (final f in result.failed) f.routeId];
      showFavoritesMessage(
        messenger,
        '${_couldNot(failed.length, 'eliminar')}.'
        '${error == null ? '' : ' ${error.message}'}',
        color: SmartBusColors.error,
        action: SnackBarAction(
          label: 'Reintentar',
          textColor: SmartBusColors.blanco,
          onPressed: () => _delete(failed),
        ),
      );
      return;
    }

    final count = result.removed.length;
    showFavoritesMessage(
      messenger,
      count == 1
          ? 'Ruta eliminada de favoritos.'
          : '$count rutas eliminadas de favoritos.',
      action: SnackBarAction(
        label: 'Deshacer',
        onPressed: () => _undo(result, messenger),
      ),
    );
  }

  Future<void> _undo(
    BulkRemoval removal,
    ScaffoldMessengerState messenger,
  ) async {
    final result = await _favorites.restore(removal);
    final error = result.error;
    if (error == null || !mounted) return;
    if (error.type == ApiErrorType.unauthorized) {
      _sessionExpired(error);
      return;
    }
    showFavoritesMessage(
      messenger,
      '${_couldNot(result.failed.length, 'recuperar')}. '
      '${error.message}',
      color: SmartBusColors.error,
    );
  }

  // --- UI -------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Android "back" leaves edit mode first.
      canPop: !_editing,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _editing) _stopEditing();
      },
      child: Scaffold(
        backgroundColor: SmartBusColors.blanco,
        // A tab of its own ("Favoritos"); pushed over another screen it is a
        // plain page with "back".
        bottomNavigationBar: Navigator.canPop(context)
            ? null
            : PassengerBottomNav(currentIndex: 1, onTap: _onTabTap),
        body: Column(
          children: [
            SmartBusHeader(
              title: 'Mis favoritos',
              type: SmartBusUserType.passenger,
              onBack: Navigator.canPop(context)
                  ? () => Navigator.maybePop(context)
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

    // Routes removed meanwhile (another screen, a refresh) leave the selection.
    _selected.removeWhere((id) => !favorites.any((f) => f.routeId == id));
    final editing = _editing && favorites.isNotEmpty;

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

    return Column(
      children: [
        _Toolbar(
          count: favorites.length,
          editing: editing,
          deleting: _deleting,
          allSelected: favorites.every((f) => _selected.contains(f.routeId)),
          noneSelected: _selected.isEmpty,
          onEdit: _startEditing,
          onDone: _stopEditing,
          onToggleAll: () => _toggleAll(favorites),
          onDeleteAll: _deleteAll,
        ),
        const Divider(height: 1),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _refresh,
            child: ListView.separated(
              key: const Key('favorites-list'),
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: favorites.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, i) => _item(favorites[i], editing),
            ),
          ),
        ),
        if (editing) _deleteBar(),
      ],
    );
  }

  // --- Alias ("Casa", "Trabajo") ---------------------------------------------

  /// Asks for the alias of [favorite] and saves it (empty removes it).
  Future<void> _rename(FavoriteRoute favorite) async {
    final messenger = ScaffoldMessenger.of(context);
    final label = await showDialog<String>(
      context: context,
      builder: (_) => _RenameDialog(favorite: favorite),
    );
    if (label == null || !mounted) return; // cancelled
    try {
      final sent = await _favorites.rename(favorite.routeId, label);
      if (!sent || !mounted) return;
      showFavoritesMessage(
        messenger,
        label.trim().isEmpty ? 'Nombre quitado.' : 'Nombre guardado.',
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.type == ApiErrorType.unauthorized) {
        _sessionExpired(e);
        return;
      }
      showFavoritesMessage(
        messenger,
        'No se pudo guardar el nombre. ${e.message}',
        color: SmartBusColors.error,
      );
    }
  }

  Widget _item(FavoriteRoute favorite, bool editing) {
    final tile = FavoriteRouteTile(
      favorite: favorite,
      favorites: _favorites,
      onRename: editing ? null : () => _rename(favorite),
      selected: editing ? _selected.contains(favorite.routeId) : null,
      onTap: editing
          ? () => _toggle(favorite.routeId)
          : () => _open(favorite.route),
    );
    if (editing) {
      return KeyedSubtree(
        key: Key('favorite-${favorite.routeId}'),
        child: tile,
      );
    }
    return Dismissible(
      key: Key('favorite-${favorite.routeId}'),
      direction: DismissDirection.endToStart,
      background: const _RemoveBackground(),
      // The controller removes it (and puts it back if that fails).
      confirmDismiss: (_) async {
        removeFavorite(context, _favorites, favorite.routeId);
        return false;
      },
      child: tile,
    );
  }

  Widget _deleteBar() {
    final count = _selected.length;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: SizedBox(
          width: double.infinity,
          child: Semantics(
            label: count == 0
                ? 'Eliminar: selecciona al menos una ruta'
                : 'Eliminar ${_routes(count)} seleccionadas',
            excludeSemantics: true,
            button: true,
            enabled: count > 0 && !_deleting,
            child: FilledButton.icon(
              key: const Key('delete-selected'),
              style: FilledButton.styleFrom(
                backgroundColor: SmartBusColors.error,
              ),
              onPressed: count == 0 || _deleting ? null : _deleteSelected,
              icon: const Icon(Icons.delete_outline),
              label: Text('Eliminar ($count)'),
            ),
          ),
        ),
      ),
    );
  }
}

/// "1 ruta" / "3 rutas".
String _routes(int n) => n == 1 ? '1 ruta' : '$n rutas';

/// "No se pudo eliminar 1 ruta" / "No se pudieron eliminar 3 rutas".
String _couldNot(int n, String verb) =>
    '${n == 1 ? 'No se pudo' : 'No se pudieron'} $verb ${_routes(n)}';

/// Above the list: how many routes (or "Seleccionar todo" while editing),
/// "Editar" / "Listo" and the ⋮ menu with "Eliminar todos".
class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.count,
    required this.editing,
    required this.deleting,
    required this.allSelected,
    required this.noneSelected,
    required this.onEdit,
    required this.onDone,
    required this.onToggleAll,
    required this.onDeleteAll,
  });

  final int count;
  final bool editing;
  final bool deleting;
  final bool allSelected;
  final bool noneSelected;
  final VoidCallback onEdit;
  final VoidCallback onDone;
  final VoidCallback onToggleAll;
  final VoidCallback onDeleteAll;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 4, 4),
      child: Row(
        children: [
          Expanded(
            child: editing
                ? InkWell(
                    key: const Key('select-all'),
                    onTap: onToggleAll,
                    borderRadius: BorderRadius.circular(8),
                    child: Row(
                      children: [
                        Checkbox(
                          value: allSelected
                              ? true
                              : (noneSelected ? false : null),
                          tristate: true,
                          onChanged: (_) => onToggleAll(),
                        ),
                        const Flexible(
                          child: Text(
                            'Seleccionar todo',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  )
                : Padding(
                    padding: const EdgeInsets.only(left: 12),
                    child: Text(
                      _routes(count),
                      style: TextStyle(color: Colors.grey.shade700),
                    ),
                  ),
          ),
          TextButton(
            key: Key(editing ? 'favorites-done' : 'favorites-edit'),
            onPressed: deleting ? null : (editing ? onDone : onEdit),
            child: Text(editing ? 'Listo' : 'Editar'),
          ),
          PopupMenuButton<void>(
            key: const Key('favorites-menu'),
            tooltip: 'Más opciones',
            enabled: !deleting,
            itemBuilder: (_) => [
              PopupMenuItem<void>(
                key: const Key('delete-all'),
                onTap: onDeleteAll,
                child: const Row(
                  children: [
                    Icon(
                      Icons.delete_sweep_outlined,
                      color: SmartBusColors.error,
                    ),
                    SizedBox(width: 12),
                    Text('Eliminar todos'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// "Nombre de la ruta": the alias of a favorite. Pops the text typed ("" to
/// remove the alias) or `null` when cancelled.
class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.favorite});

  final FavoriteRoute favorite;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final TextEditingController _text = TextEditingController(
    text: widget.favorite.label ?? '',
  );

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _save() => Navigator.pop(context, _text.text.trim());

  @override
  Widget build(BuildContext context) {
    final route = widget.favorite.route;
    return AlertDialog(
      key: const Key('rename-favorite-dialog'),
      title: const Text('Nombre de la ruta'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${route.code.isEmpty ? '' : '${route.code} · '}${route.name}',
            style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('favorite-label-field'),
            controller: _text,
            autofocus: true,
            maxLength: FavoritesController.maxLabelLength,
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _save(),
            decoration: const InputDecoration(
              hintText: 'Ej.: Casa, Trabajo, U',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        if (widget.favorite.label != null)
          TextButton(
            key: const Key('favorite-label-clear'),
            onPressed: () => Navigator.pop(context, ''),
            child: const Text('Quitar nombre'),
          ),
        TextButton(
          key: const Key('favorite-label-cancel'),
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          key: const Key('favorite-label-save'),
          onPressed: _save,
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}

/// One favorite: code, alias or name (2 lines max), name / company, the
/// "rename" pencil and its star — or, in edit mode ([selected] not `null`), a
/// checkbox.
class FavoriteRouteTile extends StatelessWidget {
  const FavoriteRouteTile({
    super.key,
    required this.favorite,
    required this.favorites,
    required this.onTap,
    this.onRename,
    this.selected,
  });

  final FavoriteRoute favorite;
  final FavoritesController favorites;
  final VoidCallback onTap;

  /// The pencil: give the route an alias. Hidden when `null`.
  final VoidCallback? onRename;

  /// `null` outside edit mode.
  final bool? selected;

  @override
  Widget build(BuildContext context) {
    final route = favorite.route;
    final selected = this.selected;
    final hasLabel = favorite.label != null;
    // With an alias the title is the alias, so the route name goes below.
    final details = [
      if (hasLabel && route.name.isNotEmpty) route.name,
      if (favorite.companyName != null) favorite.companyName!,
    ].join(' · ');
    final onRename = this.onRename;

    final tile = ListTile(
      onTap: onTap,
      onLongPress: selected == null ? onRename : null,
      selected: selected ?? false,
      selectedTileColor: SmartBusColors.verdePasajero.withValues(alpha: 0.08),
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
        favorite.title,
        key: Key('favorite-title-${route.id}'),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: SmartBusColors.grisOscuro,
          fontWeight: hasLabel ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
      subtitle: details.isEmpty
          ? null
          : Text(details, maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: selected == null
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (onRename != null)
                  IconButton(
                    key: Key('favorite-rename-${route.id}'),
                    tooltip: hasLabel ? 'Cambiar nombre' : 'Ponerle nombre',
                    icon: Icon(
                      Icons.edit_outlined,
                      color: Colors.grey.shade600,
                    ),
                    onPressed: favorites.isBusy(route.id) ? null : onRename,
                  ),
                FavoriteStarButton(route: route, controller: favorites),
              ],
            )
          : Checkbox(
              key: Key('favorite-check-${route.id}'),
              value: selected,
              onChanged: (_) => onTap(),
            ),
    );
    // The screen reader says the route and whether it is selected together.
    return selected == null ? tile : MergeSemantics(child: tile);
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
