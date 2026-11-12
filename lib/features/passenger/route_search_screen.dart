import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme.dart';
import '../../widgets/smartbus_header.dart';
import '../operations/models/operations_models.dart';
import '../operations/services/operations_service.dart';
import 'buses_in_progress_screen.dart' show PassengerMessage;

/// Passenger "Buscar ruta" (`/passenger/search`), opened from the search bar
/// on the home map.
///
/// Searches the public Dashboard catalogue (`GET ops/routes`, no token) by
/// route name, number or destination, with or without accents, while the
/// user types ([OperationsService.searchRoutes]):
/// - waits [debounce] after the last key and needs [minLength] characters;
/// - only the latest search is shown (older answers are ignored);
/// - "Cargar más" asks for the next page;
/// - tapping a result opens the route detail (`/passenger/route`).
class RouteSearchScreen extends StatefulWidget {
  const RouteSearchScreen({
    super.key,
    this.operations,
    this.debounce = const Duration(milliseconds: 400),
  });

  /// Injectable for tests; defaults to a real [OperationsService].
  final OperationsService? operations;

  /// Time without typing before searching.
  final Duration debounce;

  /// Shorter queries are not sent.
  static const minLength = 2;

  @override
  State<RouteSearchScreen> createState() => _RouteSearchScreenState();
}

class _RouteSearchScreenState extends State<RouteSearchScreen> {
  late final OperationsService _operations =
      widget.operations ?? OperationsService();
  final TextEditingController _controller = TextEditingController();
  Timer? _debounce;

  /// Text of the search whose results are shown (or being loaded).
  String _query = '';
  List<TransitRoute>? _results;
  int _page = 1;
  bool _hasMore = false;
  bool _loading = false;
  bool _loadingMore = false;

  /// The search failed (no results to show).
  String? _error;

  /// "Cargar más" failed (the results stay).
  String? _moreError;

  /// Increases with every search: answers of an older one are dropped.
  int _generation = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    final text = value.trim();
    if (text.length < RouteSearchScreen.minLength) {
      _reset();
      return;
    }
    _debounce = Timer(widget.debounce, () => _search(text));
  }

  void _clear() {
    _debounce?.cancel();
    _controller.clear();
    _reset();
  }

  /// No search: back to the hint, and any pending answer is ignored.
  void _reset() {
    _generation++;
    setState(() {
      _query = '';
      _results = null;
      _hasMore = false;
      _loading = false;
      _loadingMore = false;
      _error = null;
      _moreError = null;
    });
  }

  Future<void> _search(String text) async {
    final generation = ++_generation;
    setState(() {
      _query = text;
      _loading = true;
      _loadingMore = false;
      _error = null;
      _moreError = null;
    });
    try {
      final page = await _operations.searchRoutes(text);
      if (!mounted || generation != _generation) return;
      setState(() {
        _results = page.routes;
        _page = 1;
        _hasMore = page.hasMore;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _results = null;
        _error = _messageOf(e);
        _loading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    final results = _results;
    if (results == null || _loadingMore || _loading) return;
    final generation = _generation;
    setState(() {
      _loadingMore = true;
      _moreError = null;
    });
    try {
      final page = await _operations.searchRoutes(_query, page: _page + 1);
      if (!mounted || generation != _generation) return;
      final known = results.map((route) => route.id).toSet();
      setState(() {
        _results = [
          ...results,
          ...page.routes.where((route) => known.add(route.id)),
        ];
        _page++;
        _hasMore = page.hasMore;
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _moreError = _messageOf(e);
        _loadingMore = false;
      });
    }
  }

  static String _messageOf(Object error) => error is ApiException
      ? error.message
      : 'No se pudo completar la búsqueda. Inténtalo nuevamente.';

  void _open(TransitRoute route) =>
      Navigator.pushNamed(context, '/passenger/route', arguments: route);

  void _back() {
    if (Navigator.canPop(context)) {
      Navigator.pop(context);
    } else {
      Navigator.pushReplacementNamed(context, '/passenger/home');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SmartBusColors.blanco,
      body: Column(
        children: [
          SmartBusHeader(
            title: 'Buscar ruta',
            type: SmartBusUserType.passenger,
            compact: true,
            onBack: _back,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: _SearchField(
              controller: _controller,
              onChanged: _onChanged,
              onClear: _clear,
            ),
          ),
          SizedBox(
            height: 3,
            child: _loading && _results != null
                ? const LinearProgressIndicator(
                    key: Key('route-search-refreshing'),
                    minHeight: 3,
                    color: SmartBusColors.verdePasajero,
                    backgroundColor: Colors.transparent,
                  )
                : null,
          ),
          Expanded(child: _body()),
        ],
      ),
    );
  }

  Widget _body() {
    final results = _results;
    if (_loading && results == null) {
      return const Center(
        child: CircularProgressIndicator(key: Key('route-search-loading')),
      );
    }
    final error = _error;
    if (error != null) {
      return PassengerMessage(
        key: const Key('route-search-error'),
        icon: Icons.cloud_off_outlined,
        title: 'No se pudo buscar',
        message: error,
        actionLabel: 'Reintentar',
        onAction: () => _search(_query),
      );
    }
    if (results == null) {
      return const _Hint();
    }
    if (results.isEmpty) {
      return _NoMatches(query: _query);
    }
    return ListView.separated(
      key: const Key('route-search-results'),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: results.length + 1,
      separatorBuilder: (_, _) => const Divider(height: 1, indent: 20),
      itemBuilder: (_, i) => i < results.length
          ? _RouteResultTile(
              route: results[i],
              query: _query,
              onTap: () => _open(results[i]),
            )
          : _MoreFooter(
              hasMore: _hasMore,
              loading: _loadingMore,
              error: _moreError,
              onLoadMore: _loadMore,
            ),
    );
  }
}

// ---------------------------------------------------------------------------

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return TextField(
      key: const Key('route-search-field'),
      controller: controller,
      autofocus: true,
      textInputAction: TextInputAction.search,
      onChanged: onChanged,
      decoration: InputDecoration(
        hintText: 'Nombre, número o destino',
        prefixIcon: const Icon(
          Icons.search,
          color: SmartBusColors.verdePasajero,
        ),
        suffixIcon: ValueListenableBuilder<TextEditingValue>(
          valueListenable: controller,
          builder: (context, value, _) => value.text.isEmpty
              ? const SizedBox.shrink()
              : IconButton(
                  key: const Key('route-search-clear'),
                  tooltip: 'Borrar',
                  icon: const Icon(Icons.close),
                  onPressed: onClear,
                ),
        ),
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint();

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: const Key('route-search-hint'),
      padding: const EdgeInsets.fromLTRB(28, 32, 28, 0),
      child: Column(
        children: [
          Icon(
            Icons.alt_route,
            size: 56,
            color: SmartBusColors.verdePasajero.withValues(alpha: 0.35),
          ),
          const SizedBox(height: 12),
          Text(
            'Escribe al menos ${RouteSearchScreen.minLength} letras del nombre, '
            'el número o el destino de la ruta.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }
}

class _NoMatches extends StatelessWidget {
  const _NoMatches({required this.query});

  final String query;

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: const Key('route-search-empty'),
      padding: const EdgeInsets.fromLTRB(28, 32, 28, 0),
      child: Column(
        children: [
          Icon(
            Icons.search_off,
            size: 56,
            color: SmartBusColors.verdePasajero.withValues(alpha: 0.35),
          ),
          const SizedBox(height: 12),
          Text(
            'No encontramos rutas para "$query".',
            textAlign: TextAlign.center,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          Text(
            'Prueba con otro nombre, número o destino.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }
}

/// Code badge, name (with the typed text in bold), company and destinations.
class _RouteResultTile extends StatelessWidget {
  const _RouteResultTile({
    required this.route,
    required this.query,
    required this.onTap,
  });

  final TransitRoute route;
  final String query;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final destinations = route.destinations;
    final details = [
      ?route.companyName,
      if (destinations.isNotEmpty) 'Hacia ${destinations.join(', ')}',
    ];

    return InkWell(
      key: Key('route-result-${route.id}'),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(
          children: [
            Container(
              constraints: const BoxConstraints(minWidth: 52, maxWidth: 96),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: SmartBusColors.verdePasajero,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text.rich(
                highlightMatch(
                  route.code,
                  query,
                  const TextStyle(
                    color: SmartBusColors.blanco,
                    fontWeight: FontWeight.w600,
                  ),
                  const TextStyle(
                    fontWeight: FontWeight.w900,
                    decoration: TextDecoration.underline,
                    decorationColor: SmartBusColors.blanco,
                  ),
                ),
                key: const Key('route-result-code'),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text.rich(
                    highlightMatch(
                      route.name,
                      query,
                      const TextStyle(
                        fontSize: 15,
                        color: SmartBusColors.grisOscuro,
                      ),
                      const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: SmartBusColors.verdePasajeroIntenso,
                      ),
                    ),
                    key: const Key('route-result-name'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (details.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      details.join(' · '),
                      key: const Key('route-result-details'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.grey),
          ],
        ),
      ),
    );
  }
}

class _MoreFooter extends StatelessWidget {
  const _MoreFooter({
    required this.hasMore,
    required this.loading,
    required this.error,
    required this.onLoadMore,
  });

  final bool hasMore;
  final bool loading;
  final String? error;
  final VoidCallback onLoadMore;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(
          child: CircularProgressIndicator(
            key: Key('route-search-more-loading'),
          ),
        ),
      );
    }
    if (!hasMore) return const SizedBox.shrink();
    final message = error;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Column(
        children: [
          if (message != null) ...[
            Text(
              message,
              key: const Key('route-search-more-error'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: SmartBusColors.error, fontSize: 13),
            ),
            const SizedBox(height: 8),
          ],
          OutlinedButton(
            key: const Key('route-search-more'),
            onPressed: onLoadMore,
            child: Text(message == null ? 'Cargar más' : 'Reintentar'),
          ),
        ],
      ),
    );
  }
}

/// [text] with every occurrence of [query] in [match] style, ignoring case and
/// accents ("jose" highlights "José").
@visibleForTesting
TextSpan highlightMatch(
  String text,
  String query,
  TextStyle base,
  TextStyle match,
) {
  final needle = foldForSearch(query.trim());
  if (needle.isEmpty) return TextSpan(text: text, style: base);

  // Same length as [text], so positions match the original.
  final haystack = foldForSearch(text);
  final spans = <TextSpan>[];
  var start = 0;
  while (true) {
    final index = haystack.indexOf(needle, start);
    if (index < 0) break;
    if (index > start) spans.add(TextSpan(text: text.substring(start, index)));
    spans.add(
      TextSpan(
        text: text.substring(index, index + needle.length),
        style: match,
      ),
    );
    start = index + needle.length;
  }
  if (start < text.length) spans.add(TextSpan(text: text.substring(start)));
  return TextSpan(style: base, children: spans);
}
