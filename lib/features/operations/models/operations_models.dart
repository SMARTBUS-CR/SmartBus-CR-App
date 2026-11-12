import '../../trip_tracking/models/trip_tracking.dart';

// Models of the Dashboard "operations" API (JSON:API), reached through the
// Gateway under `/ops/*`. Only the fields the app uses are parsed; unknown or
// missing values become `null` instead of failing.

/// A trip assigned to the logged-in driver (`GET ops/driver/trips`,
/// `POST ops/trips/{id}/start | complete`).
class DriverTrip {
  const DriverTrip({
    required this.id,
    required this.status,
    this.routePatternId,
    this.scheduledDepartureAt,
    this.scheduledArrivalAt,
    this.actualDepartureAt,
    this.routeCode,
    this.routeName,
    this.headsign,
  });

  /// [resource] is one item of `data` (`{id, type, attributes}`).
  factory DriverTrip.fromJsonApi(Map<String, dynamic> resource) {
    final attributes = _attributes(resource);
    // The Dashboard copies the route into the trip when it is planned.
    final snapshot = attributes['planned_route_snapshot'];
    final route = snapshot is Map ? snapshot : const {};
    return DriverTrip(
      id: resource['id'].toString(),
      status: TripStatus.fromApi(attributes['status']),
      routePatternId: _string(attributes['route_pattern_id']),
      scheduledDepartureAt: _date(attributes['scheduled_departure_at']),
      scheduledArrivalAt: _date(attributes['scheduled_arrival_at']),
      actualDepartureAt: _date(attributes['actual_departure_at']),
      routeCode: _string(route['route_code']),
      routeName: _string(route['route_name']),
      headsign: _string(route['headsign']),
    );
  }

  final String id;
  final TripStatus status;
  final String? routePatternId;
  final DateTime? scheduledDepartureAt;
  final DateTime? scheduledArrivalAt;
  final DateTime? actualDepartureAt;
  final String? routeCode;
  final String? routeName;
  final String? headsign;

  /// "PV-RF · Puerto Viejo", or whatever part is known.
  String get title {
    final parts = [routeCode, routeName].whereType<String>().toList();
    return parts.isEmpty ? 'Viaje asignado' : parts.join(' · ');
  }
}

/// A route of the public catalogue (`GET ops/routes`).
class TransitRoute {
  const TransitRoute({
    required this.id,
    required this.code,
    required this.name,
    this.companyName,
    this.destinations = const [],
  });

  /// [included] is the document's `included` array (`include=company,patterns`):
  /// it gives the company name and the destinations (`headsign`) of each
  /// direction. Without it only code and name are known.
  factory TransitRoute.fromJsonApi(
    Map<String, dynamic> resource, [
    JsonApiIncluded included = const JsonApiIncluded.empty(),
  ]) {
    final attributes = _attributes(resource);
    final relationships = resource['relationships'];
    final links = relationships is Map ? relationships : const {};

    final company = included.single(links['company']);
    final companyAttributes = company == null
        ? const <String, dynamic>{}
        : _attributes(company);

    final destinations = <String>[];
    for (final pattern in included.many(links['patterns'])) {
      final headsign = _string(_attributes(pattern)['headsign']);
      if (headsign != null && !destinations.contains(headsign)) {
        destinations.add(headsign);
      }
    }

    return TransitRoute(
      id: resource['id'].toString(),
      code: _string(attributes['code']) ?? '',
      name: _string(attributes['name']) ?? '',
      companyName:
          _string(companyAttributes['trade_name']) ??
          _string(companyAttributes['legal_name']) ??
          _string(companyAttributes['name']),
      destinations: destinations,
    );
  }

  final String id;
  final String code;
  final String name;

  /// Operator of the route (trade name), when the company was included.
  final String? companyName;

  /// Distinct destinations of its directions ("Heredia", "San José"), when the
  /// patterns were included.
  final List<String> destinations;
}

/// One page of route search results.
class RoutePage {
  const RoutePage({required this.routes, required this.hasMore});

  final List<TransitRoute> routes;

  /// There is a next page ("Cargar más").
  final bool hasMore;
}

/// The `included` array of a JSON:API document, looked up by resource id.
class JsonApiIncluded {
  JsonApiIncluded(Object? included)
    : _byId = {
        if (included is List)
          for (final item in included.whereType<Map>())
            if (item['id'] != null)
              item['id'].toString(): Map<String, dynamic>.from(item),
      };

  const JsonApiIncluded.empty() : _byId = const {};

  final Map<String, Map<String, dynamic>> _byId;

  /// Resource of a to-one relationship (`{data: {type, id}}`), if included.
  Map<String, dynamic>? single(Object? relationship) {
    final data = relationship is Map ? relationship['data'] : null;
    return data is Map ? _byId[data['id']?.toString()] : null;
  }

  /// Included resources of a to-many relationship (`{data: [{type, id}]}`).
  List<Map<String, dynamic>> many(Object? relationship) {
    final data = relationship is Map ? relationship['data'] : null;
    if (data is! List) return const [];
    return [
      for (final link in data.whereType<Map>()) ?_byId[link['id']?.toString()],
    ];
  }
}

/// A point of a line, `[lng, lat]` in GeoJSON.
class GeoPoint {
  const GeoPoint(this.latitude, this.longitude);

  final double latitude;
  final double longitude;
}

/// One stop of a [RoutePattern], in travel order.
class PatternStop {
  const PatternStop({
    required this.stopId,
    required this.name,
    required this.sequence,
    this.minutesFromStart,
    this.latitude,
    this.longitude,
  });

  factory PatternStop.fromJson(Map<String, dynamic> json) => PatternStop(
    stopId: json['stop_id'].toString(),
    name: _string(json['stop_name']) ?? 'Parada',
    sequence: _number(json['stop_sequence'])?.toInt() ?? 0,
    minutesFromStart: _number(json['minutes_from_start'])?.toInt(),
    latitude: _number(json['latitude']),
    longitude: _number(json['longitude']),
  );

  final String stopId;
  final String name;
  final int sequence;
  final int? minutesFromStart;
  final double? latitude;
  final double? longitude;
}

/// A direction / variant of a route, with its line and stops
/// (`GET ops/routes/{id}/patterns`, `GET ops/route-patterns/{id}`).
class RoutePattern {
  const RoutePattern({
    required this.id,
    required this.name,
    this.code,
    this.headsign,
    this.routeId,
    this.stops = const [],
    this.geometry = const [],
    this.drivingDurationSeconds,
  });

  factory RoutePattern.fromJsonApi(Map<String, dynamic> resource) {
    final attributes = _attributes(resource);
    final stops = attributes['stops'];
    return RoutePattern(
      id: resource['id'].toString(),
      name: _string(attributes['name']) ?? '',
      code: _string(attributes['code']),
      headsign: _string(attributes['headsign']),
      routeId: _string(attributes['route_id']),
      stops: [
        if (stops is List)
          for (final stop in stops.whereType<Map>())
            PatternStop.fromJson(Map<String, dynamic>.from(stop)),
      ]..sort((a, b) => a.sequence.compareTo(b.sequence)),
      geometry: _lineString(attributes['route_geometry']),
      drivingDurationSeconds: _number(attributes['driving_duration_seconds']),
    );
  }

  final String id;
  final String name;
  final String? code;
  final String? headsign;
  final String? routeId;
  final List<PatternStop> stops;

  /// Line of the route. Empty when the Dashboard has none (`route_geometry`
  /// is nullable).
  final List<GeoPoint> geometry;
  final double? drivingDurationSeconds;

  /// What the passenger reads: "Hacia {headsign}", or the pattern name.
  String get label => headsign != null ? 'Hacia $headsign' : name;
}

/// A bus running right now on a pattern, without driver data
/// (`GET ops/route-patterns/{id}/trips`, `GET ops/public/trips/{id}`).
class LiveBusTrip {
  const LiveBusTrip({
    required this.id,
    required this.status,
    this.routePatternId,
    this.scheduledDepartureAt,
    this.actualDepartureAt,
    this.headsign,
    this.busPlate,
    this.busUnit,
  });

  factory LiveBusTrip.fromJsonApi(Map<String, dynamic> resource) {
    final attributes = _attributes(resource);
    final bus = attributes['bus'];
    final busMap = bus is Map ? bus : const {};
    return LiveBusTrip(
      id: resource['id'].toString(),
      status: TripStatus.fromApi(attributes['status']),
      routePatternId: _string(attributes['route_pattern_id']),
      scheduledDepartureAt: _date(attributes['scheduled_departure_at']),
      actualDepartureAt: _date(attributes['actual_departure_at']),
      headsign: _string(attributes['headsign']),
      busPlate: _string(busMap['plate_number']),
      busUnit: _string(busMap['unit_number']),
    );
  }

  final String id;
  final TripStatus status;
  final String? routePatternId;
  final DateTime? scheduledDepartureAt;
  final DateTime? actualDepartureAt;
  final String? headsign;
  final String? busPlate;
  final String? busUnit;

  /// "Unidad 12 · ABC-123", or whatever part is known.
  String get busLabel {
    final parts = [if (busUnit != null) 'Unidad $busUnit', ?busPlate];
    return parts.isEmpty ? 'Bus en camino' : parts.join(' · ');
  }
}

/// [text] in lower case and without accents ("José Peña" → "jose pena"), to
/// compare searches with or without tildes.
///
/// Character by character, so the result has the **same length** as [text]:
/// a match found in the folded text is at the same position in the original
/// (used to highlight it).
String foldForSearch(String text) {
  final buffer = StringBuffer();
  for (final char in text.split('')) {
    final lower = char.toLowerCase();
    // A few characters change length when lower-cased ("İ"): keep them.
    final single = lower.length == 1 ? lower : char;
    buffer.write(_accentless[single] ?? single);
  }
  return buffer.toString();
}

const _accentless = {
  'á': 'a', 'à': 'a', 'ä': 'a', 'â': 'a', 'ã': 'a', //
  'é': 'e', 'è': 'e', 'ë': 'e', 'ê': 'e', //
  'í': 'i', 'ì': 'i', 'ï': 'i', 'î': 'i', //
  'ó': 'o', 'ò': 'o', 'ö': 'o', 'ô': 'o', 'õ': 'o', //
  'ú': 'u', 'ù': 'u', 'ü': 'u', 'û': 'u', //
  'ñ': 'n', 'ç': 'c',
};

/// "07:05" — local time, 24 h.
String formatHour(DateTime time) {
  final local = time.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(local.hour)}:${two(local.minute)}';
}

/// "2026-11-11" — the local date, as the Dashboard filters `service_date`.
String formatServiceDate(DateTime date) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${date.year}-${two(date.month)}-${two(date.day)}';
}

// --- JSON helpers --------------------------------------------------------------

Map<String, dynamic> _attributes(Map<String, dynamic> resource) {
  final attributes = resource['attributes'];
  return attributes is Map ? Map<String, dynamic>.from(attributes) : const {};
}

String? _string(Object? value) {
  if (value == null) return null;
  final text = value.toString();
  return text.isEmpty ? null : text;
}

double? _number(Object? value) => switch (value) {
  num n => n.toDouble(),
  String s => double.tryParse(s),
  _ => null,
};

DateTime? _date(Object? value) =>
    value is String ? DateTime.tryParse(value)?.toLocal() : null;

/// GeoJSON `LineString` → points. Anything else → empty.
List<GeoPoint> _lineString(Object? geometry) {
  if (geometry is! Map || geometry['type'] != 'LineString') return const [];
  final coordinates = geometry['coordinates'];
  if (coordinates is! List) return const [];
  return [
    for (final pair in coordinates)
      if (pair is List && pair.length >= 2)
        if ((_number(pair[1]), _number(pair[0])) case (
          final double lat,
          final double lng,
        ))
          GeoPoint(lat, lng),
  ];
}
