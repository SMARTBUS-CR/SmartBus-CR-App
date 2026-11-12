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
    this.actualArrivalAt,
    this.routeCode,
    this.routeName,
    this.headsign,
    this.busPlate,
    this.busUnit,
    this.plannedPattern,
  });

  /// [resource] is one item of `data` (`{id, type, attributes}`). [included]
  /// is the document's `included` array (`include=pattern,bus`): the bus
  /// plate, and the pattern headsign when the trip has no route snapshot.
  factory DriverTrip.fromJsonApi(
    Map<String, dynamic> resource, {
    JsonApiIncluded included = const JsonApiIncluded.empty(),
  }) {
    final attributes = _attributes(resource);
    // The Dashboard copies the route into the trip when it is planned.
    final snapshot = attributes['planned_route_snapshot'];
    final route = snapshot is Map ? snapshot : const {};
    final links = resource['relationships'];
    final relationships = links is Map ? links : const {};
    final bus = included.single(relationships['bus']);
    final busAttributes = bus == null ? const {} : _attributes(bus);
    final pattern = included.single(relationships['pattern']);
    final patternAttributes = pattern == null ? const {} : _attributes(pattern);
    return DriverTrip(
      id: resource['id'].toString(),
      status: TripStatus.fromApi(attributes['status']),
      routePatternId: _string(attributes['route_pattern_id']),
      scheduledDepartureAt: _date(attributes['scheduled_departure_at']),
      scheduledArrivalAt: _date(attributes['scheduled_arrival_at']),
      actualDepartureAt: _date(attributes['actual_departure_at']),
      actualArrivalAt: _date(attributes['actual_arrival_at']),
      routeCode: _string(route['route_code']),
      routeName: _string(route['route_name']),
      headsign:
          _string(route['headsign']) ?? _string(patternAttributes['headsign']),
      busPlate: _string(busAttributes['plate_number']),
      busUnit: _string(busAttributes['unit_number']),
      plannedPattern: _snapshotPattern(
        route,
        fallbackId: _string(attributes['route_pattern_id']),
      ),
    );
  }

  /// The route frozen in `planned_route_snapshot` when the trip was planned:
  /// line (`route_geometry`) and stops (`occurrences`, `lat` / `lng` may be
  /// strings). `null` when the snapshot has neither.
  static RoutePattern? _snapshotPattern(Map snapshot, {String? fallbackId}) {
    final occurrences = snapshot['occurrences'];
    final stops = <PatternStop>[
      if (occurrences is List)
        for (final item in occurrences.whereType<Map>())
          PatternStop(
            stopId: item['stop_id']?.toString() ?? '',
            name: _string(item['name']) ?? 'Parada',
            sequence: _number(item['stop_sequence'])?.toInt() ?? 0,
            minutesFromStart: _number(item['minutes_from_start'])?.toInt(),
            latitude: _number(item['lat']),
            longitude: _number(item['lng']),
          ),
    ]..sort((a, b) => a.sequence.compareTo(b.sequence));
    final geometry = _lineString(snapshot['route_geometry']);
    if (stops.isEmpty && geometry.isEmpty) return null;
    return RoutePattern(
      id: _string(snapshot['pattern_id']) ?? fallbackId ?? '',
      name: _string(snapshot['pattern_name']) ?? '',
      code: _string(snapshot['pattern_code']),
      headsign: _string(snapshot['headsign']),
      routeId: _string(snapshot['route_id']),
      stops: stops,
      geometry: geometry,
      distanceMeters: _number(snapshot['distance_meters']),
      drivingDurationSeconds: _number(snapshot['driving_duration_seconds']),
    );
  }

  final String id;
  final TripStatus status;
  final String? routePatternId;
  final DateTime? scheduledDepartureAt;
  final DateTime? scheduledArrivalAt;
  final DateTime? actualDepartureAt;

  /// When the trip was completed (backend `actual_arrival_at`, UTC).
  final DateTime? actualArrivalAt;
  final String? routeCode;
  final String? routeName;
  final String? headsign;

  /// Plate and unit number of the assigned bus (`include=bus`).
  final String? busPlate;
  final String? busUnit;

  /// The route the driver must follow (line + stops), as planned for this
  /// trip. `null` when the snapshot has no route data.
  final RoutePattern? plannedPattern;

  /// When the trip left: the backend's actual departure, else the scheduled.
  DateTime? get departureAt => actualDepartureAt ?? scheduledDepartureAt;

  /// The same trip with [pattern] as its planned route, or — when
  /// [pattern] is null — keeping this one's ([plannedPattern]).
  DriverTrip withPlannedPattern(RoutePattern? pattern) => DriverTrip(
    id: id,
    status: status,
    routePatternId: routePatternId,
    scheduledDepartureAt: scheduledDepartureAt,
    scheduledArrivalAt: scheduledArrivalAt,
    actualDepartureAt: actualDepartureAt,
    actualArrivalAt: actualArrivalAt,
    routeCode: routeCode,
    routeName: routeName,
    headsign: headsign,
    busPlate: busPlate,
    busUnit: busUnit,
    plannedPattern: pattern ?? plannedPattern,
  );

  /// "Bus ABC-123 · Unidad 12", or whatever part is known; `null` if none.
  String? get busLabel {
    final parts = [
      if (busPlate != null) 'Bus $busPlate',
      if (busUnit != null) 'Unidad $busUnit',
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }

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
    this.patterns = const [],
  });

  /// [included] is the document's `included` array (`include=company,patterns`):
  /// it gives the company name and the destinations (`headsign`) of each
  /// direction. [patterns] are the route's parsed directions when the caller
  /// has them (see [linkedPatternIds]); their destinations count too.
  /// Without either, only code and name are known.
  factory TransitRoute.fromJsonApi(
    Map<String, dynamic> resource, {
    JsonApiIncluded included = const JsonApiIncluded.empty(),
    List<RoutePattern> patterns = const [],
  }) {
    final attributes = _attributes(resource);
    final relationships = resource['relationships'];
    final links = relationships is Map ? relationships : const {};

    final company = included.single(links['company']);
    final companyAttributes = company == null
        ? const <String, dynamic>{}
        : _attributes(company);

    final destinations = <String>[];
    void addDestination(String? headsign) {
      if (headsign != null && !destinations.contains(headsign)) {
        destinations.add(headsign);
      }
    }

    for (final pattern in patterns) {
      addDestination(pattern.headsign);
    }
    for (final pattern in included.many(links['patterns'])) {
      addDestination(_string(_attributes(pattern)['headsign']));
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
      patterns: patterns,
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

  /// Directions / variants of the route. Empty unless they were requested
  /// (`GET ops/routes?include=patterns`) or added with [withPatterns].
  final List<RoutePattern> patterns;

  /// "PV-RF · Puerto Viejo", or whatever part is known.
  String get title => [code, name].where((part) => part.isNotEmpty).join(' · ');

  /// How the passenger tells [pattern] apart from the route's other
  /// directions: "Hacia {headsign}", plus the variant ("por Vara Blanca", from
  /// the pattern name) when another pattern goes to the same place. Falls
  /// back to the pattern name.
  String directionLabel(RoutePattern pattern) {
    final headsign = pattern.headsign;
    final shared =
        headsign != null &&
        patterns
            .where((p) => p.id != pattern.id && p.headsign == headsign)
            .isNotEmpty;
    if (!shared) return pattern.label;
    final via = pattern.name.indexOf(' por ');
    return via >= 0
        ? '${pattern.label}${pattern.name.substring(via)}'
        : (pattern.name.isEmpty ? pattern.label : pattern.name);
  }

  /// Same route with [patterns] (company and known destinations are kept).
  TransitRoute withPatterns(List<RoutePattern> patterns) => TransitRoute(
    id: id,
    code: code,
    name: name,
    companyName: companyName,
    destinations: {
      ...destinations,
      for (final pattern in patterns) ?pattern.headsign,
    }.toList(),
    patterns: patterns,
  );

  /// Ids in `relationships.patterns.data` of a route resource, in order.
  /// `null` when the document does not have that relationship.
  static List<String>? linkedPatternIds(Map<String, dynamic> resource) {
    final relationships = resource['relationships'];
    if (relationships is! Map) return null;
    final patterns = relationships['patterns'];
    if (patterns is! Map) return null;
    final data = patterns['data'];
    if (data is! List) return null;
    return [
      for (final item in data.whereType<Map>())
        if (item['id'] != null) item['id'].toString(),
    ];
  }
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

  /// `null` when the Dashboard has no coordinates for the stop.
  GeoPoint? get location => switch ((latitude, longitude)) {
    (final double lat, final double lng) => GeoPoint(lat, lng),
    _ => null,
  };
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
    this.distanceMeters,
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
      distanceMeters: _number(attributes['distance_meters']),
      drivingDurationSeconds: _number(attributes['driving_duration_seconds']),
    );
  }

  /// JSON:API `type` of a pattern resource.
  static const jsonApiType = 'route-patterns';

  final String id;
  final String name;
  final String? code;
  final String? headsign;
  final String? routeId;
  final List<PatternStop> stops;

  /// Line of the route. Empty when the Dashboard has none (`route_geometry`
  /// is nullable).
  final List<GeoPoint> geometry;
  final double? distanceMeters;
  final double? drivingDurationSeconds;

  /// What the passenger reads: "Hacia {headsign}", or the pattern name.
  String get label => headsign != null ? 'Hacia $headsign' : name;

  /// `true` when the Dashboard has the real line of the pattern.
  bool get hasGeometry => geometry.length >= 2;

  /// Stops that can be drawn (with coordinates), in travel order.
  List<PatternStop> get locatedStops =>
      stops.where((stop) => stop.location != null).toList();

  /// The line to draw: [geometry], or — when the Dashboard has none — the
  /// stops joined in order (an approximation).
  List<GeoPoint> get path => hasGeometry
      ? geometry
      : [for (final stop in locatedStops) stop.location!];
}

/// A route and one of its directions, picked by the passenger to see on the
/// map (e.g. from "Buses en curso" → **Ver ruta**).
class RouteSelection {
  const RouteSelection({required this.route, required this.pattern});

  /// The route with **all** its [TransitRoute.patterns], so the passenger can
  /// switch direction.
  final TransitRoute route;
  final RoutePattern pattern;
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
