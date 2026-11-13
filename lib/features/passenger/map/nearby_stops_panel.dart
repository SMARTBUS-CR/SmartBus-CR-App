import 'package:flutter/material.dart';

import '../../operations/models/trip_planning.dart';
import '../../operations/services/nearby_routes_filter.dart';
import '../../operations/services/nearby_stops.dart';
import '../../operations/services/route_proximity.dart';
import 'map_overlay.dart';
import 'route_sheet.dart' show FareLabel, RouteCodeBadge;

/// "Próximas salidas" of the selected stop: what the panel needs to show it.
class StopDeparturesState {
  const StopDeparturesState({
    this.departures,
    this.loading = false,
    this.error,
  });

  /// `null` until loaded (or when it failed).
  final List<StopDeparture>? departures;
  final bool loading;
  final String? error;
}

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
    this.passingRoutes = const [],
    this.onPassingRouteSelected,
    this.departures = const StopDeparturesState(),
    this.onDepartureSelected,
    this.onRetryDepartures,
    this.now,
  });

  /// Directions whose line (the road) passes within the radius, closest
  /// first: the bus can be stopped there even without an official stop.
  final List<PassingRoute> passingRoutes;
  final ValueChanged<PassingRoute>? onPassingRouteSelected;

  /// Next departures of the stop [selectedId].
  final StopDeparturesState departures;

  /// A departure was tapped: draw its route with the stop highlighted.
  final void Function(NearbyStop stop, StopDeparture departure)?
  onDepartureSelected;
  final VoidCallback? onRetryDepartures;

  /// "Now", for "en 5 min" (defaults to the clock).
  final DateTime? now;

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
            text: passingRoutes.isEmpty
                ? 'No hay paradas ni rutas a menos de '
                      '${formatDistance(radiusMeters)}. Busca una ruta para '
                      'ver todas sus paradas.'
                : 'No hay paradas oficiales a menos de '
                      '${formatDistance(radiusMeters)}, pero estas rutas '
                      'pasan cerca: puedes esperar el bus en la carretera.',
          )
        else
          for (final stop in stops)
            _StopTile(
              colors: colors,
              stop: stop,
              selected: stop.stopId == selectedId,
              onTap: () => onStopSelected(stop),
              onRoute: (route) => onRouteSelected(stop, route),
              departures: stop.stopId == selectedId
                  ? StopDeparturesView(
                      colors: colors,
                      state: departures,
                      now: now ?? DateTime.now(),
                      onSelected: onDepartureSelected == null
                          ? null
                          : (d) => onDepartureSelected!(stop, d),
                      onRetry: onRetryDepartures,
                    )
                  : null,
            ),
        if (stops != null && passingRoutes.isNotEmpty) ...[
          const SizedBox(height: 8),
          Row(
            key: const Key('passing-routes'),
            children: [
              Icon(Icons.add_road, size: 18, color: colors.accent),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Rutas que pasan cerca de ti',
                  style: TextStyle(
                    color: colors.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          for (final passing in passingRoutes)
            _PassingRouteTile(
              colors: colors,
              passing: passing,
              onTap: onPassingRouteSelected == null
                  ? null
                  : () => onPassingRouteSelected!(passing),
            ),
        ],
      ],
    );
  }
}

/// A direction whose road passes near: "PV-GUA · Hacia Guápiles — pasa a
/// 250 m". Tapping it draws the route where it passes closest.
class _PassingRouteTile extends StatelessWidget {
  const _PassingRouteTile({
    required this.colors,
    required this.passing,
    required this.onTap,
  });

  final MapOverlayColors colors;
  final PassingRoute passing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      key: Key('passing-route-${passing.pattern.id}'),
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            RouteCodeBadge(code: passing.route.code),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    passing.route.directionLabel(passing.pattern),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colors.onSurface,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    'Pasa a ${formatDistance(passing.origin.distanceMeters)} '
                    'de ti',
                    style: TextStyle(color: colors.muted, fontSize: 12),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: colors.muted),
          ],
        ),
      ),
    );
  }
}

/// "Próximas salidas" of a stop (next 2 h): code, direction, time at the
/// stop, how long until then and the fare. Tapping one draws its route.
class StopDeparturesView extends StatelessWidget {
  const StopDeparturesView({
    super.key,
    required this.colors,
    required this.state,
    required this.now,
    this.onSelected,
    this.onRetry,
  });

  final MapOverlayColors colors;
  final StopDeparturesState state;
  final DateTime now;
  final ValueChanged<StopDeparture>? onSelected;
  final VoidCallback? onRetry;

  /// Rows shown; the rest are summed up ("y 3 más").
  static const maxShown = 6;

  @override
  Widget build(BuildContext context) {
    final muted = TextStyle(color: colors.muted, fontSize: 13);
    final departures = state.departures;
    return Column(
      key: const Key('stop-departures'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(Icons.schedule, size: 18, color: colors.accent),
            const SizedBox(width: 6),
            Text(
              'Próximas salidas',
              style: TextStyle(
                color: colors.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (state.loading) ...[
              const SizedBox(width: 10),
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: colors.accent,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 4),
        if (departures == null && state.error != null)
          Row(
            children: [
              Expanded(
                child: Text(
                  state.error!,
                  key: const Key('stop-departures-error'),
                  style: muted,
                ),
              ),
              if (onRetry != null)
                TextButton(
                  key: const Key('stop-departures-retry'),
                  style: TextButton.styleFrom(
                    foregroundColor: colors.onSurface,
                  ),
                  onPressed: onRetry,
                  child: const Text('Reintentar'),
                ),
            ],
          )
        else if (departures != null && departures.isEmpty)
          Text(
            'No hay salidas en las próximas 2 horas.',
            key: const Key('stop-departures-empty'),
            style: muted,
          )
        else if (departures != null) ...[
          for (final departure in departures.take(maxShown))
            _DepartureRow(
              colors: colors,
              departure: departure,
              now: now,
              onTap: onSelected == null ? null : () => onSelected!(departure),
            ),
          if (departures.length > maxShown)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'y ${departures.length - maxShown} más',
                style: muted,
              ),
            ),
        ],
      ],
    );
  }
}

class _DepartureRow extends StatelessWidget {
  const _DepartureRow({
    required this.colors,
    required this.departure,
    required this.now,
    required this.onTap,
  });

  final MapOverlayColors colors;
  final StopDeparture departure;
  final DateTime now;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final fare = departure.fare;
    return InkWell(
      key: Key('stop-departure-${departure.id}'),
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            RouteCodeBadge(code: departure.routeCode),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    departure.headsign == null
                        ? departure.routeName
                        : 'Hacia ${departure.headsign}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colors.onSurface,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    '${formatClock(departure.departureAt)} · '
                    '${formatCountdown(departure.departureAt, now)}',
                    style: TextStyle(color: colors.muted, fontSize: 12),
                  ),
                ],
              ),
            ),
            if (fare != null) ...[
              const SizedBox(width: 8),
              FareLabel(fare: fare),
            ],
          ],
        ),
      ),
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
    this.departures,
  });

  final MapOverlayColors colors;
  final NearbyStop stop;
  final bool selected;
  final VoidCallback onTap;
  final ValueChanged<StopRoute> onRoute;

  /// "Próximas salidas", only on the selected stop.
  final Widget? departures;

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
                if (departures case final departures?) ...[
                  const SizedBox(height: 10),
                  departures,
                ],
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
