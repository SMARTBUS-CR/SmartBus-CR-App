import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../operations/models/operations_models.dart';
import '../../operations/models/route_timetable.dart';
import '../../operations/services/nearby_routes_filter.dart';
import '../../trip_tracking/models/trip_tracking.dart';
import '../../trip_tracking/services/live_trip_tracker.dart';
import '../../trip_tracking/services/route_live_buses.dart';
import '../favorite_star.dart';
import '../services/favorites_controller.dart';
import 'map_overlay.dart';

/// One row of the routes list: the route and, when the passenger's location is
/// known, its stop closest to them.
class RouteListEntry {
  const RouteListEntry(this.route, {this.nearest});

  final TransitRoute route;
  final NearbyRoute? nearest;
}

/// What the routes list shows.
enum RouteListMode {
  /// Routes with a stop within the radius (location known).
  nearby,

  /// Every route ("Ver todas las rutas", or no location).
  all,
}

/// Routes section of the home bottom sheet: title, then loading / error /
/// empty state or the list of routes.
class RoutesSection extends StatelessWidget {
  const RoutesSection({
    super.key,
    required this.colors,
    required this.mode,
    required this.entries,
    required this.loading,
    required this.error,
    required this.canShowNearby,
    required this.onRetry,
    required this.onSelect,
    required this.onShowAll,
    required this.onShowNearby,
    this.fares = const {},
  });

  /// Today's fare of each route by id (missing while loading or without one).
  final Map<String, RouteFare?> fares;

  final MapOverlayColors colors;
  final RouteListMode mode;

  /// `null` while the routes have not been loaded.
  final List<RouteListEntry>? entries;
  final bool loading;

  /// Message of the last failed request (shown when there are no routes).
  final String? error;

  /// The location is known, so the nearby list can be shown.
  final bool canShowNearby;
  final VoidCallback onRetry;
  final ValueChanged<RouteListEntry> onSelect;
  final VoidCallback onShowAll;
  final VoidCallback onShowNearby;

  @override
  Widget build(BuildContext context) {
    final nearby = mode == RouteListMode.nearby;
    final list = entries;
    return Column(
      key: const Key('routes-section'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(Icons.alt_route, color: colors.accent),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                nearby ? 'Rutas cercanas' : 'Todas las rutas',
                style: TextStyle(
                  color: colors.onSurface,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (!nearby && canShowNearby && list != null)
              TextButton(
                key: const Key('show-nearby-routes'),
                onPressed: onShowNearby,
                child: const Text('Ver cercanas'),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (list == null && error != null)
          _StateMessage(
            key: const Key('routes-error'),
            colors: colors,
            icon: Icons.cloud_off_outlined,
            title: 'No se pudieron cargar las rutas',
            message: error!,
            actionLabel: 'Reintentar',
            onAction: onRetry,
          )
        else if (list == null || (loading && list.isEmpty))
          Padding(
            key: const Key('routes-loading'),
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Row(
              children: [
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
                const SizedBox(width: 12),
                Text('Buscando rutas…', style: TextStyle(color: colors.muted)),
              ],
            ),
          )
        else if (list.isEmpty && nearby)
          _StateMessage(
            key: const Key('routes-empty'),
            colors: colors,
            icon: Icons.wrong_location_outlined,
            title: 'No hay rutas cerca de ti',
            message:
                'Ninguna ruta tiene paradas a menos de '
                '${formatDistance(NearbyRoutesFilter.defaultRadiusMeters)}.',
            actionLabel: 'Ver todas las rutas',
            onAction: onShowAll,
          )
        else if (list.isEmpty)
          _StateMessage(
            key: const Key('routes-empty'),
            colors: colors,
            icon: Icons.route_outlined,
            title: 'No hay rutas disponibles',
            message: 'Todavía no hay rutas publicadas.',
            actionLabel: 'Actualizar',
            onAction: onRetry,
          )
        else ...[
          for (final entry in list)
            RouteListTile(
              entry: entry,
              colors: colors,
              fare: fares[entry.route.id],
              onTap: () => onSelect(entry),
            ),
          if (nearby)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const Key('show-all-routes'),
                onPressed: onShowAll,
                icon: const Icon(Icons.list),
                label: const Text('Ver todas las rutas'),
              ),
            ),
        ],
      ],
    );
  }
}

/// A route of the list: code badge, name, direction, closest stop and fare.
class RouteListTile extends StatelessWidget {
  const RouteListTile({
    super.key,
    required this.entry,
    required this.colors,
    required this.onTap,
    this.fare,
  });

  final RouteListEntry entry;
  final MapOverlayColors colors;
  final VoidCallback onTap;

  /// Today's fare; `null` while loading or when the route has none.
  final RouteFare? fare;

  @override
  Widget build(BuildContext context) {
    final route = entry.route;
    final nearest = entry.nearest;
    final directions = route.patterns.length;
    final lines = nearest != null
        ? [
            route.directionLabel(nearest.pattern),
            '${nearest.stop.name} · ${formatDistance(nearest.distanceMeters)}',
          ]
        : [
            if (directions == 1)
              route.directionLabel(route.patterns.single)
            else if (directions > 1)
              '$directions direcciones',
          ];

    return ListTile(
      key: Key('route-tile-${route.id}'),
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(vertical: 2),
      leading: RouteCodeBadge(code: route.code),
      title: Text(
        route.name,
        style: TextStyle(color: colors.onSurface, fontWeight: FontWeight.w500),
      ),
      subtitle: lines.isEmpty
          ? null
          : Text(
              lines.join('\n'),
              style: TextStyle(color: colors.muted, fontSize: 13),
            ),
      isThreeLine: lines.length > 1,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (fare case final fare?)
            FareLabel(key: Key('route-fare-${route.id}'), fare: fare),
          Icon(Icons.chevron_right, color: colors.muted),
        ],
      ),
    );
  }
}

/// White pill with a fare (readable on the green sheet): "₡1.570", or
/// "Tarifa ₡1.570" with [prefix].
class FareLabel extends StatelessWidget {
  const FareLabel({super.key, required this.fare, this.prefix = false});

  final RouteFare fare;
  final bool prefix;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: SmartBusColors.blanco,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        prefix ? 'Tarifa ${fare.label}' : fare.label,
        style: const TextStyle(
          color: SmartBusColors.verdePasajero,
          fontWeight: FontWeight.w600,
          fontSize: 13,
        ),
      ),
    );
  }
}

/// Green rounded badge with the route code ("PV-RF").
class RouteCodeBadge extends StatelessWidget {
  const RouteCodeBadge({super.key, required this.code});

  final String code;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 52),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: SmartBusColors.verdePasajero,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        code.isEmpty ? '—' : code,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: SmartBusColors.blanco,
          fontWeight: FontWeight.bold,
          fontSize: 13,
        ),
      ),
    );
  }
}

/// The route drawn on the map: name, close button, one chip per direction,
/// and the details of the tapped stop.
class SelectedRoutePanel extends StatelessWidget {
  const SelectedRoutePanel({
    super.key,
    required this.colors,
    required this.route,
    required this.pattern,
    required this.onPatternSelected,
    required this.onClose,
    required this.now,
    required this.onOpenBus,
    required this.onStopSelected,
    this.tappedStop,
    this.liveBuses,
    this.favorites,
    this.fare,
    this.schedules,
    this.timetableLoading = false,
  });

  /// Today's fare of the route; `null` while loading or without one.
  final RouteFare? fare;

  /// Weekly departures of [pattern]; `null` while not loaded.
  final List<RouteSchedule>? schedules;

  /// The timetable of [pattern] is being requested.
  final bool timetableLoading;

  /// For the favorite star; defaults to [FavoritesController.shared].
  final FavoritesController? favorites;

  /// A stop of the list was tapped (center the map on it).
  final ValueChanged<PatternStop> onStopSelected;

  final MapOverlayColors colors;
  final TransitRoute route;

  /// `null` when the route has no published directions.
  final RoutePattern? pattern;
  final ValueChanged<RoutePattern> onPatternSelected;
  final VoidCallback onClose;
  final PatternStop? tappedStop;

  /// Buses running on [pattern]; `null` while not followed.
  final RouteLiveBusesState? liveBuses;

  /// "Now", for how old each bus position is.
  final DateTime now;

  /// Opens "Rastreando tu bus" for a trip id.
  final ValueChanged<String> onOpenBus;

  @override
  Widget build(BuildContext context) {
    final pattern = this.pattern;
    return Column(
      key: const Key('selected-route-panel'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            RouteCodeBadge(code: route.code),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                route.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: colors.onSurface,
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            FavoriteStarButton(route: route, controller: favorites),
            IconButton(
              key: const Key('close-route'),
              tooltip: 'Cerrar ruta',
              icon: Icon(Icons.close, color: colors.onSurface),
              onPressed: onClose,
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (pattern == null)
          Text(
            'Esta ruta aún no tiene recorridos publicados.',
            style: TextStyle(color: colors.muted),
          )
        else ...[
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final option in route.patterns)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      key: Key('direction-${option.id}'),
                      label: Text(route.directionLabel(option)),
                      selected: option.id == pattern.id,
                      onSelected: (_) => onPatternSelected(option),
                      selectedColor: SmartBusColors.verdePasajero.withValues(
                        alpha: 0.15,
                      ),
                      side: BorderSide(
                        color: option.id == pattern.id
                            ? SmartBusColors.verdePasajero
                            : Colors.grey.shade300,
                      ),
                      showCheckmark: false,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  _summary(pattern),
                  key: const Key('route-summary'),
                  style: TextStyle(color: colors.muted, fontSize: 13),
                ),
              ),
              if (fare case final fare?)
                FareLabel(
                  key: const Key('selected-route-fare'),
                  fare: fare,
                  prefix: true,
                ),
            ],
          ),
          if (!pattern.hasGeometry && pattern.locatedStops.length >= 2) ...[
            const SizedBox(height: 4),
            Row(
              key: const Key('approximate-path-note'),
              children: [
                Icon(Icons.more_horiz, size: 18, color: colors.muted),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    approximateRouteText,
                    style: TextStyle(color: colors.muted, fontSize: 12),
                  ),
                ),
              ],
            ),
          ],
          if (tappedStop case final stop?) ...[
            const SizedBox(height: 12),
            _StopDetails(colors: colors, pattern: pattern, stop: stop),
          ],
          const SizedBox(height: 16),
          ScheduleSection(
            key: ValueKey('schedule-${pattern.id}'),
            colors: colors,
            schedules: schedules,
            loading: timetableLoading,
            now: now,
          ),
          if (liveBuses case final live?) ...[
            const SizedBox(height: 16),
            LiveBusesSection(
              colors: colors,
              state: live,
              now: now,
              onOpen: onOpenBus,
            ),
          ],
          if (pattern.stops.isNotEmpty) ...[
            const SizedBox(height: 16),
            StopsTimeline(
              colors: colors,
              pattern: pattern,
              selected: tappedStop,
              onSelect: onStopSelected,
            ),
          ],
        ],
      ],
    );
  }

  static String _summary(RoutePattern pattern) {
    final duration = pattern.drivingDurationSeconds;
    final distance = pattern.distanceMeters;
    return [
      '${pattern.stops.length} paradas',
      if (distance != null) formatDistance(distance),
      if (duration != null) '~${(duration / 60).round()} min',
    ].join(' · ');
  }
}

/// "Horario" of the selected direction: the next departure, today's
/// departures (the ones already gone crossed out) and, on demand, the next
/// six days.
class ScheduleSection extends StatefulWidget {
  const ScheduleSection({
    super.key,
    required this.colors,
    required this.schedules,
    required this.loading,
    required this.now,
  });

  final MapOverlayColors colors;

  /// Weekly departures; `null` while loading or when they could not be loaded.
  final List<RouteSchedule>? schedules;
  final bool loading;
  final DateTime now;

  @override
  State<ScheduleSection> createState() => _ScheduleSectionState();
}

class _ScheduleSectionState extends State<ScheduleSection> {
  bool _showWeek = false;

  static const _weekdays = [
    'Lunes',
    'Martes',
    'Miércoles',
    'Jueves',
    'Viernes',
    'Sábado',
    'Domingo',
  ];

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    final weekly = widget.schedules;
    final muted = TextStyle(color: colors.muted, fontSize: 13);

    return Column(
      key: const Key('schedule-section'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(Icons.schedule, size: 20, color: colors.accent),
            const SizedBox(width: 8),
            Text(
              'Horario',
              style: TextStyle(
                color: colors.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (widget.loading) ...[
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
        const SizedBox(height: 6),
        if (weekly == null && !widget.loading)
          Text(
            'No se pudo cargar el horario.',
            key: const Key('schedule-unavailable'),
            style: muted,
          )
        else if (weekly != null && weekly.isEmpty)
          Text(
            'Este sentido no tiene horario publicado.',
            key: const Key('schedule-empty'),
            style: muted,
          )
        else if (weekly != null) ...[
          ..._today(weekly, muted),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const Key('schedule-week-toggle'),
              style: TextButton.styleFrom(
                foregroundColor: colors.onSurface,
                padding: EdgeInsets.zero,
              ),
              onPressed: () => setState(() => _showWeek = !_showWeek),
              icon: Icon(_showWeek ? Icons.expand_less : Icons.expand_more),
              label: Text(
                _showWeek ? 'Ocultar la semana' : 'Ver horario de la semana',
              ),
            ),
          ),
          if (_showWeek) ..._week(weekly, muted),
        ],
      ],
    );
  }

  /// "Próxima salida: 10:30" and today's departures as chips.
  List<Widget> _today(List<RouteSchedule> weekly, TextStyle muted) {
    final now = widget.now;
    final today = departuresOn(weekly, now);
    if (today.isEmpty) {
      return [
        Text(
          'Hoy no hay salidas en este sentido.',
          key: const Key('next-departure'),
          style: muted,
        ),
      ];
    }
    final minutesNow = now.hour * 60 + now.minute;
    final next = today.where((d) => d.minutesOfDay >= minutesNow).firstOrNull;
    return [
      Text(
        next == null
            ? 'Ya no hay más salidas hoy'
            : 'Próxima salida: ${next.label}',
        key: const Key('next-departure'),
        style: TextStyle(
          color: widget.colors.onSurface,
          fontWeight: FontWeight.w600,
        ),
      ),
      const SizedBox(height: 6),
      Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final departure in today)
            _DepartureChip(
              label: departure.label,
              gone: departure.minutesOfDay < minutesNow,
              next: identical(departure, next),
            ),
        ],
      ),
    ];
  }

  /// One line per day after today: "Lunes 16 · 05:30, 06:00…".
  List<Widget> _week(List<RouteSchedule> weekly, TextStyle muted) {
    final now = widget.now;
    return [
      for (var i = 1; i <= 6; i++)
        Builder(
          builder: (_) {
            final day = DateTime(now.year, now.month, now.day + i);
            final departures = departuresOn(weekly, day);
            final name = i == 1
                ? 'Mañana'
                : '${_weekdays[day.weekday - 1]} ${day.day}';
            return Padding(
              key: Key('schedule-day-$i'),
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 104,
                    child: Text(
                      name,
                      style: TextStyle(
                        color: widget.colors.onSurface,
                        fontWeight: FontWeight.w500,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      departures.isEmpty
                          ? 'Sin salidas'
                          : departures.map((d) => d.label).join(' · '),
                      style: muted,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
    ];
  }
}

class _DepartureChip extends StatelessWidget {
  const _DepartureChip({
    required this.label,
    required this.gone,
    required this.next,
  });

  final String label;
  final bool gone;
  final bool next;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: next
            ? SmartBusColors.blanco
            : SmartBusColors.blanco.withValues(alpha: gone ? 0.12 : 0.22),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: next ? FontWeight.bold : FontWeight.w500,
          color: next
              ? SmartBusColors.verdePasajero
              : SmartBusColors.blanco.withValues(alpha: gone ? 0.55 : 1),
          decoration: gone ? TextDecoration.lineThrough : null,
          decorationColor: SmartBusColors.blanco,
        ),
      ),
    );
  }
}

/// Every stop of the direction as a vertical timeline, like the map: the
/// start (teal) and the end (blue) filled, the stops in between numbered, and
/// a line whose color goes from the start color to the end color.
class StopsTimeline extends StatelessWidget {
  const StopsTimeline({
    super.key,
    required this.colors,
    required this.pattern,
    required this.onSelect,
    this.selected,
  });

  final MapOverlayColors colors;
  final RoutePattern pattern;
  final PatternStop? selected;
  final ValueChanged<PatternStop> onSelect;

  /// Same colors as the line on the map.
  static const startColor = SmartBusColors.verdeTurquesa;
  static const endColor = SmartBusColors.azulPrincipal;

  @override
  Widget build(BuildContext context) {
    final stops = pattern.stops;
    final last = stops.length - 1;
    Color colorAt(double t) => Color.lerp(startColor, endColor, t)!;
    double progress(int i) => last == 0 ? 0 : i / last;

    return Column(
      key: const Key('stops-timeline'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(Icons.route, size: 20, color: colors.accent),
            const SizedBox(width: 8),
            Text(
              'Paradas (${stops.length})',
              style: TextStyle(
                color: colors.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        for (var i = 0; i <= last; i++)
          _TimelineRow(
            key: Key('timeline-stop-$i'),
            colors: colors,
            stop: stops[i],
            order: i + 1,
            kind: i == 0
                ? _StopKind.start
                : (i == last ? _StopKind.end : _StopKind.mid),
            color: colorAt(progress(i)),
            lineAbove: i == 0
                ? null
                : colorAt((progress(i - 1) + progress(i)) / 2),
            lineBelow: i == last
                ? null
                : colorAt((progress(i) + progress(i + 1)) / 2),
            selected: identical(stops[i], selected),
            onTap: stops[i].location == null ? null : () => onSelect(stops[i]),
          ),
      ],
    );
  }
}

enum _StopKind { start, mid, end }

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({
    super.key,
    required this.colors,
    required this.stop,
    required this.order,
    required this.kind,
    required this.color,
    required this.lineAbove,
    required this.lineBelow,
    required this.selected,
    required this.onTap,
  });

  final MapOverlayColors colors;
  final PatternStop stop;
  final int order;
  final _StopKind kind;
  final Color color;
  final Color? lineAbove;
  final Color? lineBelow;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final edge = kind != _StopKind.mid;
    final minutes = stop.minutesFromStart;
    final caption = switch (kind) {
      _StopKind.start => 'Salida',
      _StopKind.end => minutes != null ? 'Llegada · +$minutes min' : 'Llegada',
      _StopKind.mid => minutes != null ? '+$minutes min' : null,
    };

    Widget segment(Color? c) => Expanded(
      child: Container(
        width: 4,
        decoration: BoxDecoration(
          color: c ?? Colors.transparent,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );

    return Material(
      color: selected
          ? StopsTimeline.endColor.withValues(alpha: 0.08)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 40,
                child: Column(
                  children: [
                    segment(lineAbove),
                    Container(
                      width: edge ? 26 : 20,
                      height: edge ? 26 : 20,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: edge ? color : SmartBusColors.blanco,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: edge ? SmartBusColors.blanco : color,
                          width: 3,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: color.withValues(
                              alpha: selected ? 0.55 : 0.25,
                            ),
                            blurRadius: selected ? 10 : 4,
                          ),
                        ],
                      ),
                      child: switch (kind) {
                        _StopKind.start => const Icon(
                          Icons.trip_origin,
                          size: 12,
                          color: SmartBusColors.blanco,
                        ),
                        _StopKind.end => const Icon(
                          Icons.flag,
                          size: 13,
                          color: SmartBusColors.blanco,
                        ),
                        _StopKind.mid => Text(
                          '$order',
                          style: TextStyle(
                            color: color,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      },
                    ),
                    segment(lineBelow),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        stop.name,
                        style: TextStyle(
                          color: colors.onSurface,
                          fontWeight: edge || selected
                              ? FontWeight.w600
                              : FontWeight.w400,
                        ),
                      ),
                      if (caption != null)
                        Text(
                          caption,
                          style: TextStyle(color: colors.muted, fontSize: 12),
                        ),
                    ],
                  ),
                ),
              ),
              if (onTap != null)
                Icon(
                  Icons.my_location,
                  size: 16,
                  color: selected ? StopsTimeline.endColor : colors.muted,
                ),
              const SizedBox(width: 8),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Buses en vivo" of the selected direction: one row per bus running
/// (driver tapped "Iniciar recorrido"), with how fresh its position is.
class LiveBusesSection extends StatelessWidget {
  const LiveBusesSection({
    super.key,
    required this.colors,
    required this.state,
    required this.now,
    required this.onOpen,
  });

  final MapOverlayColors colors;
  final RouteLiveBusesState state;
  final DateTime now;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    final buses = state.buses;
    return Column(
      key: const Key('live-buses-section'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(
              Icons.directions_bus_filled,
              size: 20,
              color: SmartBusColors.verdePasajero,
            ),
            const SizedBox(width: 8),
            Text(
              'Buses en vivo',
              style: TextStyle(
                color: colors.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (state.loading) ...[
              const SizedBox(width: 10),
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ],
          ],
        ),
        const SizedBox(height: 6),
        if (!state.loading && buses.isEmpty)
          Text(
            state.error ?? 'No hay buses en curso en este sentido.',
            key: const Key('no-live-buses'),
            style: TextStyle(color: colors.muted, fontSize: 13),
          ),
        for (final bus in buses)
          ListTile(
            key: Key('live-bus-${bus.trip.id}'),
            contentPadding: EdgeInsets.zero,
            dense: true,
            onTap: () => onOpen(bus.trip.id),
            leading: Icon(
              Icons.directions_bus_filled,
              color: _isLive(bus)
                  ? SmartBusColors.verdePasajero
                  : const Color(0xFF9CA3AF),
            ),
            title: Text(
              bus.trip.busLabel,
              style: TextStyle(color: colors.onSurface),
            ),
            subtitle: Text(
              liveBusStatus(bus, now),
              style: TextStyle(color: colors.muted, fontSize: 12),
            ),
            trailing: const Text(
              'Ver en vivo',
              style: TextStyle(
                color: SmartBusColors.verdePasajero,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
      ],
    );
  }

  bool _isLive(LiveBus bus) =>
      bus.state.freshnessAt(now) == TrackingFreshness.live;
}

/// "En vivo · hace 5 s", "Señal débil · hace 2 min", "Esperando ubicación"…
String liveBusStatus(LiveBus bus, DateTime now) {
  final state = bus.state;
  if (state.phase == LiveTripPhase.loading) return 'Buscando ubicación…';
  if (state.phase == LiveTripPhase.failed) {
    return state.error ?? 'No se pudo obtener la ubicación.';
  }
  if (state.status != TripStatus.inProgress) return 'Aún no inicia';
  final seenAt = state.positionSeenAt;
  if (state.position == null || seenAt == null) return 'Esperando ubicación';
  final ago = _ago(now.difference(seenAt));
  return switch (state.freshnessAt(now)) {
    TrackingFreshness.live => 'En vivo · $ago',
    TrackingFreshness.stale => 'Señal débil · $ago',
    _ => 'Sin señal · $ago',
  };
}

String _ago(Duration age) {
  final seconds = age.inSeconds < 0 ? 0 : age.inSeconds;
  if (seconds < 5) return 'hace un momento';
  if (seconds < 60) return 'hace $seconds s';
  if (seconds < 3600) return 'hace ${seconds ~/ 60} min';
  return 'hace ${seconds ~/ 3600} h';
}

class _StopDetails extends StatelessWidget {
  const _StopDetails({
    required this.colors,
    required this.pattern,
    required this.stop,
  });

  final MapOverlayColors colors;
  final RoutePattern pattern;
  final PatternStop stop;

  @override
  Widget build(BuildContext context) {
    // Same number as the marker: position in travel order.
    final order = pattern.stops.indexOf(stop) + 1;
    final minutes = stop.minutesFromStart;
    final details = [
      'Parada $order de ${pattern.stops.length}',
      if (minutes != null)
        minutes == 0 ? 'Inicio del recorrido' : '$minutes min desde el inicio',
    ].join(' · ');

    return Container(
      key: const Key('stop-details'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: SmartBusColors.grisClaro,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: SmartBusColors.azulPrincipal,
            child: Text(
              '$order',
              style: const TextStyle(
                color: SmartBusColors.blanco,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  stop.name,
                  style: TextStyle(
                    color: colors.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  details,
                  style: TextStyle(color: colors.muted, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StateMessage extends StatelessWidget {
  const _StateMessage({
    super.key,
    required this.colors,
    required this.icon,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  final MapOverlayColors colors;
  final IconData icon;
  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: colors.muted),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: colors.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(message, style: TextStyle(color: colors.muted, fontSize: 13)),
          const SizedBox(height: 8),
          OutlinedButton(onPressed: onAction, child: Text(actionLabel)),
        ],
      ),
    );
  }
}
