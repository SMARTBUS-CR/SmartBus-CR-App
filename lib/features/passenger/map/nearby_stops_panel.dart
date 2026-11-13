import 'package:flutter/material.dart';

import '../../operations/services/nearby_routes_filter.dart';
import '../../operations/services/nearby_stops.dart';
import 'map_overlay.dart';

/// Content of the bottom sheet in "Paradas cercanas": the stops near the
/// passenger, closest first, each with its distance and the routes that stop
/// there. Tapping a stop shows it on the map; tapping one of its routes draws
/// that route.
class NearbyStopsPanel extends StatelessWidget {
  const NearbyStopsPanel({
    super.key,
    required this.colors,
    required this.stops,
    required this.loading,
    required this.error,
    required this.radiusMeters,
    required this.selectedId,
    required this.onStopSelected,
    required this.onRouteSelected,
    required this.onRetry,
    required this.onClose,
  });

  final MapOverlayColors colors;

  /// `null` while the routes catalogue has not loaded.
  final List<NearbyStop>? stops;
  final bool loading;
  final String? error;
  final double radiusMeters;
  final String? selectedId;
  final ValueChanged<NearbyStop> onStopSelected;
  final void Function(NearbyStop stop, StopRoute route) onRouteSelected;
  final VoidCallback onRetry;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final stops = this.stops;
    return Column(
      key: const Key('nearby-stops-panel'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(Icons.signpost_outlined, color: colors.accent),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Paradas cercanas',
                    style: TextStyle(
                      color: colors.onSurface,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    'A menos de ${formatDistance(radiusMeters)} de ti',
                    style: TextStyle(color: colors.muted, fontSize: 13),
                  ),
                ],
              ),
            ),
            IconButton(
              key: const Key('nearby-stops-close'),
              tooltip: 'Cerrar',
              icon: Icon(Icons.close, color: colors.muted),
              onPressed: onClose,
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (stops == null && error != null)
          _Message(
            colors: colors,
            text: error!,
            actionLabel: 'Reintentar',
            onAction: onRetry,
          )
        else if (stops == null || (loading && stops.isEmpty))
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (stops.isEmpty)
          _Message(
            colors: colors,
            text:
                'No hay paradas a menos de ${formatDistance(radiusMeters)}. '
                'Busca una ruta para ver todas sus paradas.',
          )
        else
          for (final stop in stops)
            _StopTile(
              colors: colors,
              stop: stop,
              selected: stop.stopId == selectedId,
              onTap: () => onStopSelected(stop),
              onRoute: (route) => onRouteSelected(stop, route),
            ),
      ],
    );
  }
}

class _StopTile extends StatelessWidget {
  const _StopTile({
    required this.colors,
    required this.stop,
    required this.selected,
    required this.onTap,
    required this.onRoute,
  });

  final MapOverlayColors colors;
  final NearbyStop stop;
  final bool selected;
  final VoidCallback onTap;
  final ValueChanged<StopRoute> onRoute;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: selected
            ? colors.accent.withValues(alpha: 0.10)
            : colors.muted.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          key: Key('nearby-stop-${stop.stopId}'),
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.place, size: 20, color: colors.accent),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        stop.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: colors.onSurface,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      formatDistance(stop.distanceMeters),
                      style: TextStyle(color: colors.muted, fontSize: 13),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final route in stop.routes)
                      ActionChip(
                        key: Key(
                          'nearby-stop-route-${stop.stopId}-${route.pattern.id}',
                        ),
                        visualDensity: VisualDensity.compact,
                        avatar: Icon(
                          Icons.directions_bus,
                          size: 16,
                          color: colors.accent,
                        ),
                        label: Text(
                          route.pattern.headsign == null
                              ? route.route.code
                              : '${route.route.code} · ${route.pattern.headsign}',
                          style: const TextStyle(fontSize: 12),
                        ),
                        tooltip: 'Ver ruta ${route.route.code}',
                        onPressed: () => onRoute(route),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.colors,
    required this.text,
    this.actionLabel,
    this.onAction,
  });

  final MapOverlayColors colors;
  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        children: [
          Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(color: colors.muted),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 8),
            TextButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ],
      ),
    );
  }
}
