/// Upcoming departures from a stop and direct journeys between two points,
/// from the Dashboard (`GET ops/stops/{id}/departures`, `GET ops/journeys`).
library;

import 'route_timetable.dart';

/// One planned departure of a route from a stop (`stop-departures`): the
/// time the bus is due **at that stop** (its departure from the terminal plus
/// the minutes to reach the stop).
class StopDeparture {
  const StopDeparture({
    required this.id,
    required this.routeId,
    required this.routeCode,
    required this.routeName,
    required this.patternId,
    required this.departureAt,
    this.headsign,
    this.fare,
  });

  factory StopDeparture.fromJsonApi(Map<String, dynamic> resource) {
    final a = _attributes(resource);
    return StopDeparture(
      id: resource['id']?.toString() ?? '',
      routeId: _text(a['route_id']) ?? '',
      routeCode: _text(a['route_code']) ?? '',
      routeName: _text(a['route_name']) ?? '',
      patternId: _text(a['pattern_id']) ?? '',
      headsign: _text(a['headsign']),
      departureAt: _time(a['scheduled_stop_departure_at']) ?? DateTime(0),
      fare: _fare(a['fare']),
    );
  }

  final String id;
  final String routeId;
  final String routeCode;
  final String routeName;
  final String patternId;

  /// Destination of the direction ("Río Frío").
  final String? headsign;

  /// When the bus is due at the stop (local time).
  final DateTime departureAt;

  /// The fare that applies that day.
  final RouteFare? fare;
}

/// A stop of a [Journey]: where to board or get off, and how far it is from
/// the point the passenger asked for.
class JourneyStop {
  const JourneyStop({
    required this.stopId,
    required this.name,
    required this.sequence,
    required this.distanceMeters,
  });

  factory JourneyStop.fromJson(Object? value) {
    final m = value is Map ? Map<String, dynamic>.from(value) : const {};
    return JourneyStop(
      stopId: _text(m['stop_id']) ?? '',
      name: _text(m['stop_name']) ?? 'Parada',
      sequence: _number(m['stop_sequence'])?.toInt() ?? 0,
      distanceMeters: _number(m['distance_m'])?.toDouble() ?? 0,
    );
  }

  final String stopId;
  final String name;

  /// Position in the direction (1 = first stop).
  final int sequence;

  /// Walking distance (straight line) from the origin / to the destination.
  final double distanceMeters;
}

/// A direct way to get from the origin to the destination (`journeys`): one
/// bus, boarding at [boarding] and getting off at [alighting].
class Journey {
  const Journey({
    required this.id,
    required this.routeId,
    required this.routeCode,
    required this.routeName,
    required this.patternId,
    required this.boarding,
    required this.alighting,
    required this.departureAt,
    this.headsign,
    this.companyName,
    this.arrivalAt,
    this.fare,
  });

  factory Journey.fromJsonApi(Map<String, dynamic> resource) {
    final a = _attributes(resource);
    return Journey(
      id: resource['id']?.toString() ?? '',
      routeId: _text(a['route_id']) ?? '',
      routeCode: _text(a['route_code']) ?? '',
      routeName: _text(a['route_name']) ?? '',
      patternId: _text(a['pattern_id']) ?? '',
      headsign: _text(a['headsign']),
      companyName: _text(a['company_name']),
      boarding: JourneyStop.fromJson(a['boarding_stop']),
      alighting: JourneyStop.fromJson(a['alighting_stop']),
      departureAt: _time(a['scheduled_departure_at']) ?? DateTime(0),
      arrivalAt: _time(a['estimated_arrival_at']),
      fare: _fare(a['fare']),
    );
  }

  final String id;
  final String routeId;
  final String routeCode;
  final String routeName;
  final String patternId;
  final String? headsign;
  final String? companyName;
  final JourneyStop boarding;
  final JourneyStop alighting;

  /// When the bus is due at [boarding] (local time).
  final DateTime departureAt;

  /// When it reaches [alighting]; `null` when the timetable does not say.
  final DateTime? arrivalAt;

  final RouteFare? fare;

  /// Minutes on the bus; `null` without [arrivalAt].
  int? get rideMinutes => arrivalAt?.difference(departureAt).inMinutes;

  /// Stops travelled on the bus.
  int get stopCount => alighting.sequence - boarding.sequence;
}

/// One way to go, as the passenger sees it: a direction, where to board and
/// get off, the next departure ([journey]) and the ones after it ([later]).
class JourneyOption {
  const JourneyOption({required this.journey, this.later = const []});

  /// The earliest departure of this option.
  final Journey journey;

  /// The next departures (same stops), earliest first.
  final List<DateTime> later;

  /// Meters walked in all: to the boarding stop and from the last one.
  double get walkingMeters =>
      journey.boarding.distanceMeters + journey.alighting.distanceMeters;
}

/// Groups the journeys of `GET ops/journeys` (one per departure and stop
/// pair) into options: per direction, the stop pair with the **shortest
/// walk** (ties: the earliest), with its departures. Earliest option first,
/// at most [limit].
List<JourneyOption> journeyOptions(List<Journey> journeys, {int limit = 5}) {
  // Departures of each (direction, boarding, alighting), earliest first.
  final byStops = <String, List<Journey>>{};
  for (final j in journeys) {
    byStops
        .putIfAbsent(
          '${j.patternId}|${j.boarding.stopId}|${j.alighting.stopId}',
          () => [],
        )
        .add(j);
  }
  final groups = [
    for (final list in byStops.values)
      list..sort((a, b) => a.departureAt.compareTo(b.departureAt)),
  ];

  double walk(List<Journey> g) =>
      g.first.boarding.distanceMeters + g.first.alighting.distanceMeters;

  // Per direction, the stop pair with the shortest walk.
  final best = <String, List<Journey>>{};
  for (final group in groups) {
    final pattern = group.first.patternId;
    final current = best[pattern];
    if (current == null ||
        walk(group) < walk(current) ||
        (walk(group) == walk(current) &&
            group.first.departureAt.isBefore(current.first.departureAt))) {
      best[pattern] = group;
    }
  }

  final options = [
    for (final group in best.values)
      JourneyOption(
        journey: group.first,
        later: [for (final j in group.skip(1)) j.departureAt],
      ),
  ]..sort((a, b) => a.journey.departureAt.compareTo(b.journey.departureAt));
  return options.take(limit).toList();
}

/// Approximate walking time for [meters] (≈ 80 m per minute), at least 1.
int walkingMinutes(double meters) => (meters / 80).ceil().clamp(1, 999);

/// "10:30".
String formatClock(DateTime time) =>
    '${time.hour.toString().padLeft(2, '0')}:'
    '${time.minute.toString().padLeft(2, '0')}';

/// "ahora", "en 5 min", "en 1 h 20 min" — from [now] to [time].
String formatCountdown(DateTime time, DateTime now) {
  final minutes = (time.difference(now).inSeconds / 60).ceil();
  if (minutes <= 0) return 'ahora';
  if (minutes < 60) return 'en $minutes min';
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  return rest == 0 ? 'en $hours h' : 'en $hours h $rest min';
}

// --- helpers -------------------------------------------------------------------

Map<String, dynamic> _attributes(Map<String, dynamic> resource) {
  final attributes = resource['attributes'];
  return attributes is Map ? Map<String, dynamic>.from(attributes) : const {};
}

String? _text(Object? value) {
  if (value == null) return null;
  final text = value.toString().trim();
  return text.isEmpty ? null : text;
}

num? _number(Object? value) => switch (value) {
  num n => n,
  String s => num.tryParse(s),
  _ => null,
};

/// ISO 8601 with offset ("2026-11-13T10:30:00-06:00") → local time.
DateTime? _time(Object? value) {
  if (value is! String) return null;
  return DateTime.tryParse(value)?.toLocal();
}

/// `{"amount": "650.00", "currency": "CRC"}` → [RouteFare]; `null` = none.
RouteFare? _fare(Object? value) {
  if (value is! Map) return null;
  final amount = _number(value['amount']);
  if (amount == null) return null;
  return RouteFare(
    amount: amount.toDouble(),
    currency: _text(value['currency']) ?? 'CRC',
  );
}
