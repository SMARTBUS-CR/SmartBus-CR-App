import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../features/operations/models/route_timetable.dart';

/// Today's departures of a direction: "Próxima salida: 10:30" and every
/// departure of the day (the ones already gone in gray). Used by the
/// passenger's route detail and the driver's home.
class DeparturesToday extends StatelessWidget {
  const DeparturesToday({
    super.key,
    required this.departures,
    required this.now,
    this.color = SmartBusColors.verdePasajero,
  });

  /// Today's departures, earliest first ([departuresOn]).
  final List<RouteSchedule> departures;
  final DateTime now;

  /// Accent of the icon and the next departure (passenger green, driver blue).
  final Color color;

  @override
  Widget build(BuildContext context) {
    final muted = TextStyle(color: Colors.grey.shade700, fontSize: 13);
    if (departures.isEmpty) {
      return Text('Hoy no hay salidas en este sentido.', style: muted);
    }
    final minutesNow = now.hour * 60 + now.minute;
    final next = departures
        .where((d) => d.minutesOfDay >= minutesNow)
        .firstOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.schedule, size: 16, color: color),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                next == null
                    ? 'Ya no hay más salidas hoy'
                    : 'Próxima salida: ${next.label}',
                key: const Key('next-departure'),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final departure in departures)
              _DepartureChip(
                label: departure.label,
                gone: departure.minutesOfDay < minutesNow,
                next: identical(departure, next),
                color: color,
              ),
          ],
        ),
      ],
    );
  }
}

class _DepartureChip extends StatelessWidget {
  const _DepartureChip({
    required this.label,
    required this.gone,
    required this.next,
    required this.color,
  });

  final String label;
  final bool gone;
  final bool next;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: next ? color : SmartBusColors.blanco,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          color: next
              ? SmartBusColors.blanco
              : (gone ? Colors.grey.shade500 : Colors.grey.shade800),
          decoration: gone ? TextDecoration.lineThrough : null,
        ),
      ),
    );
  }
}
