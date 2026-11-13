import 'package:flutter/material.dart';

import '../../operations/models/trip_planning.dart';
import '../../operations/services/nearby_routes_filter.dart';
import 'map_overlay.dart';
import 'route_sheet.dart' show FareLabel, RouteCodeBadge;

/// Content of the bottom sheet in "¿Cómo llego?": without a destination, how
/// to mark one (keep a finger on the map); with one, the direct buses that
/// go there from the passenger — where to walk, which bus, when it leaves,
/// where to get off and the fare.
class JourneyPlannerPanel extends StatelessWidget {
  const JourneyPlannerPanel({
    super.key,
    required this.colors,
    required this.hasDestination,
    required this.options,
    required this.loading,
    required this.error,
    required this.now,
    required this.onSelected,
    required this.onRetry,
    required this.onClose,
    this.destinationMeters,
  });

  final MapOverlayColors colors;

  /// A destination is marked on the map.
  final bool hasDestination;

  /// Straight-line distance from the passenger to the destination.
  final double? destinationMeters;

  /// `null` until the journeys are loaded (or when it failed).
  final List<JourneyOption>? options;
  final bool loading;
  final String? error;
  final DateTime now;
  final ValueChanged<JourneyOption> onSelected;
  final VoidCallback onRetry;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final options = this.options;
    final muted = TextStyle(color: colors.muted, fontSize: 13);
    final distance = destinationMeters;
    return Column(
      key: const Key('journey-planner-panel'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(Icons.directions, color: colors.accent),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '¿Cómo llego?',
                    style: TextStyle(
                      color: colors.onSurface,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    hasDestination
                        ? 'Desde tu ubicación al punto marcado'
                              '${distance == null ? '' : ' · ${formatDistance(distance)}'}'
                        : 'Elige a dónde quieres ir',
                    style: muted,
                  ),
                ],
              ),
            ),
            IconButton(
              key: const Key('journey-planner-close'),
              tooltip: 'Cerrar',
              icon: Icon(Icons.close, color: colors.muted),
              onPressed: onClose,
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (!hasDestination)
          _Hint(
            key: const Key('journey-planner-hint'),
            colors: colors,
            icon: Icons.touch_app_outlined,
            text:
                'Mantén presionado el mapa en el lugar al que quieres ir. '
                'Te diremos qué bus tomar, dónde subir y dónde bajarte.',
          )
        else if (options == null && error != null)
          _Hint(
            key: const Key('journey-planner-error'),
            colors: colors,
            icon: Icons.cloud_off_outlined,
            text: error!,
            actionLabel: 'Reintentar',
            onAction: onRetry,
          )
        else if (options == null || loading)
          Padding(
            key: const Key('journey-planner-loading'),
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Row(
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: colors.accent,
                  ),
                ),
                const SizedBox(width: 12),
                Text('Buscando buses…', style: TextStyle(color: colors.muted)),
              ],
            ),
          )
        else if (options.isEmpty)
          _Hint(
            key: const Key('journey-planner-empty'),
            colors: colors,
            icon: Icons.wrong_location_outlined,
            text:
                'No encontramos un bus directo que te lleve ahí en las '
                'próximas 24 horas. Prueba marcar un punto más cerca de una '
                'parada.',
          )
        else
          for (final option in options)
            JourneyOptionCard(
              colors: colors,
              option: option,
              now: now,
              onTap: () => onSelected(option),
            ),
      ],
    );
  }
}

/// One way to go: the bus, then the three steps (walk, ride, walk).
class JourneyOptionCard extends StatelessWidget {
  const JourneyOptionCard({
    super.key,
    required this.colors,
    required this.option,
    required this.now,
    required this.onTap,
  });

  final MapOverlayColors colors;
  final JourneyOption option;
  final DateTime now;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final j = option.journey;
    final fare = j.fare;
    final ride = j.rideMinutes;
    final arrival = j.arrivalAt;
    final stops = j.stopCount;
    final later = option.later.take(3).map(formatClock).join(' · ');

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: colors.muted.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          key: Key('journey-${j.patternId}'),
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    RouteCodeBadge(code: j.routeCode),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            j.headsign == null
                                ? j.routeName
                                : 'Hacia ${j.headsign}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: colors.onSurface,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            'Sale ${formatClock(j.departureAt)} · '
                            '${formatCountdown(j.departureAt, now)}',
                            key: Key('journey-departure-${j.patternId}'),
                            style: TextStyle(
                              color: colors.onSurface,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (fare != null) FareLabel(fare: fare),
                  ],
                ),
                const SizedBox(height: 8),
                _Step(
                  colors: colors,
                  icon: Icons.directions_walk,
                  text:
                      'Camina ${formatDistance(j.boarding.distanceMeters)} '
                      '(~${walkingMinutes(j.boarding.distanceMeters)} min) '
                      'a ${j.boarding.name}',
                ),
                _Step(
                  colors: colors,
                  icon: Icons.directions_bus,
                  text: [
                    'Bájate en ${j.alighting.name}',
                    if (arrival != null) 'llega ${formatClock(arrival)}',
                    if (ride != null && ride > 0) '$ride min',
                    if (stops > 0) stops == 1 ? '1 parada' : '$stops paradas',
                  ].join(' · '),
                ),
                _Step(
                  colors: colors,
                  icon: Icons.flag_outlined,
                  text:
                      'Camina ${formatDistance(j.alighting.distanceMeters)} '
                      'a tu destino',
                ),
                if (later.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'Después: $later',
                      key: Key('journey-later-${j.patternId}'),
                      style: TextStyle(color: colors.muted, fontSize: 12),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.colors, required this.icon, required this.text});

  final MapOverlayColors colors;
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: colors.muted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: colors.muted, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint({
    super.key,
    required this.colors,
    required this.icon,
    required this.text,
    this.actionLabel,
    this.onAction,
  });

  final MapOverlayColors colors;
  final IconData icon;
  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: colors.muted),
              const SizedBox(width: 10),
              Expanded(
                child: Text(text, style: TextStyle(color: colors.muted)),
              ),
            ],
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 8),
            OutlinedButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ],
      ),
    );
  }
}
