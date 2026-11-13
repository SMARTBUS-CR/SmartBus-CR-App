import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:smartbus_drivers/core/network/api_client.dart';
import 'package:smartbus_drivers/core/storage/secure_session_store.dart';
import 'package:smartbus_drivers/features/operations/services/operations_service.dart';

/// A `journeys` resource as the Dashboard sends it.
Map<String, dynamic> journeyResource({
  String pattern = 'p-1',
  String boarding = 's-a',
  double boardingMeters = 300,
  String alighting = 's-z',
  double alightingMeters = 200,
  String departure = '2026-11-13T10:30:00-06:00',
  String? arrival = '2026-11-13T11:05:00-06:00',
  int boardingSeq = 2,
  int alightingSeq = 8,
}) => {
  'type': 'journeys',
  'id': '$pattern-$boarding-$alighting-$departure',
  'attributes': {
    'route_id': 'r-1',
    'route_code': 'PV-RF',
    'route_name': 'Puerto Viejo - Río Frío',
    'pattern_id': pattern,
    'pattern_name': 'Ida',
    'headsign': 'Río Frío',
    'company_id': 'c-1',
    'company_name': 'Transportes',
    'boarding_stop': {
      'stop_id': boarding,
      'stop_name': 'Escuela',
      'stop_sequence': boardingSeq,
      'distance_m': boardingMeters,
    },
    'alighting_stop': {
      'stop_id': alighting,
      'stop_name': 'Parque',
      'stop_sequence': alightingSeq,
      'distance_m': alightingMeters,
    },
    'scheduled_departure_at': departure,
    'estimated_arrival_at': arrival,
    'fare': {'amount': '650.00', 'currency': 'CRC'},
  },
};

Journey _journey({
  String pattern = 'p-1',
  String boarding = 's-a',
  double boardingMeters = 300,
  String alighting = 's-z',
  double alightingMeters = 200,
  String departure = '2026-11-13T10:30:00-06:00',
}) => Journey.fromJsonApi(
  journeyResource(
    pattern: pattern,
    boarding: boarding,
    boardingMeters: boardingMeters,
    alighting: alighting,
    alightingMeters: alightingMeters,
    departure: departure,
  ),
);

class _Harness {
  _Harness(Object body) {
    service = OperationsService(
      client: ApiClient(
        sessionStore: SecureSessionStore(),
        httpClient: MockClient((request) async {
          requests.add(request);
          return http.Response(
            jsonEncode(body),
            200,
            headers: {'content-type': 'application/vnd.api+json'},
          );
        }),
      ),
    );
  }

  final List<http.Request> requests = [];
  late final OperationsService service;
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  group('Journey.fromJsonApi', () {
    test('route, stops, times (local), ride and fare', () {
      final j = _journey();

      expect(j.routeCode, 'PV-RF');
      expect(j.patternId, 'p-1');
      expect(j.headsign, 'Río Frío');
      expect(j.companyName, 'Transportes');
      expect(j.boarding.name, 'Escuela');
      expect(j.boarding.distanceMeters, 300);
      expect(j.alighting.name, 'Parque');
      expect(j.departureAt.toUtc(), DateTime.utc(2026, 11, 13, 16, 30));
      expect(j.departureAt.isUtc, isFalse);
      expect(j.rideMinutes, 35);
      expect(j.stopCount, 6);
      expect(j.fare?.label, '₡650');
    });

    test('unknown arrival and no fare', () {
      final resource = journeyResource(arrival: null);
      (resource['attributes'] as Map)['fare'] = null;
      final j = Journey.fromJsonApi(resource);

      expect(j.arrivalAt, isNull);
      expect(j.rideMinutes, isNull);
      expect(j.fare, isNull);
    });
  });

  test('StopDeparture.fromJsonApi', () {
    final d = StopDeparture.fromJsonApi({
      'type': 'stop-departures',
      'id': 'sch-1-ps-2-2026-11-13',
      'attributes': {
        'route_id': 'r-1',
        'route_code': 'PV-RF',
        'route_name': 'Puerto Viejo - Río Frío',
        'pattern_id': 'p-1',
        'headsign': 'Río Frío',
        'stop_id': 's-a',
        'stop_name': 'Escuela',
        'stop_sequence': 2,
        'scheduled_stop_departure_at': '2026-11-13T10:42:00-06:00',
        'fare': {'amount': '1570', 'currency': 'CRC'},
      },
    });

    expect(d.id, 'sch-1-ps-2-2026-11-13');
    expect(d.routeCode, 'PV-RF');
    expect(d.patternId, 'p-1');
    expect(d.headsign, 'Río Frío');
    expect(d.departureAt.toUtc(), DateTime.utc(2026, 11, 13, 16, 42));
    expect(d.fare?.label, '₡1.570');
  });

  group('journeyOptions', () {
    test('per direction, the shortest walk with its departures', () {
      final options = journeyOptions([
        // p-1 from the far stop (900 m walking): left out.
        _journey(boarding: 's-far', boardingMeters: 700),
        // p-1 from the close stop: two departures.
        _journey(departure: '2026-11-13T11:30:00-06:00'),
        _journey(),
        // p-2 leaves earlier.
        _journey(pattern: 'p-2', departure: '2026-11-13T10:00:00-06:00'),
      ]);

      expect(options.map((o) => o.journey.patternId), ['p-2', 'p-1']);
      final p1 = options[1];
      expect(p1.journey.boarding.stopId, 's-a');
      expect(p1.walkingMeters, 500);
      expect(
        p1.journey.departureAt.toUtc(),
        DateTime.utc(2026, 11, 13, 16, 30),
      );
      expect(p1.later.single.toUtc(), DateTime.utc(2026, 11, 13, 17, 30));
      expect(options.first.later, isEmpty);
    });

    test('at most [limit] options; none for no journeys', () {
      final many = [
        for (var i = 0; i < 8; i++)
          _journey(pattern: 'p-$i', departure: '2026-11-13T1$i:00:00-06:00'),
      ];
      expect(journeyOptions(many), hasLength(5));
      expect(journeyOptions(many, limit: 2), hasLength(2));
      expect(journeyOptions(const []), isEmpty);
    });
  });

  test('formatCountdown, formatClock and walkingMinutes', () {
    final now = DateTime(2026, 11, 13, 10);
    expect(formatCountdown(now, now), 'ahora');
    expect(formatCountdown(DateTime(2026, 11, 13, 9, 59), now), 'ahora');
    expect(formatCountdown(DateTime(2026, 11, 13, 10, 5), now), 'en 5 min');
    expect(formatCountdown(DateTime(2026, 11, 13, 11), now), 'en 1 h');
    expect(
      formatCountdown(DateTime(2026, 11, 13, 11, 20), now),
      'en 1 h 20 min',
    );
    expect(formatClock(DateTime(2026, 11, 13, 7, 5)), '07:05');
    expect(walkingMinutes(10), 1);
    expect(walkingMinutes(400), 5);
  });

  group('requests', () {
    test('stopDepartures: next 2 h from now, 20 per page', () async {
      final h = _Harness({'data': <Object>[]});

      await h.service.stopDepartures(
        'stop-1',
        from: DateTime.utc(2026, 11, 13, 16),
      );

      final url = h.requests.single.url;
      expect(h.requests.single.method, 'GET');
      expect(url.path, endsWith('/ops/stops/stop-1/departures'));
      expect(url.queryParameters['window_minutes'], '120');
      expect(url.queryParameters['page[size]'], '20');
      expect(url.queryParameters['departure_at'], '2026-11-13T16:00:00.000Z');
    });

    test('stopDepartures is not cached (depends on the time)', () async {
      final h = _Harness({'data': <Object>[]});

      await h.service.stopDepartures('stop-1');
      await h.service.stopDepartures('stop-1');

      expect(h.requests, hasLength(2));
    });

    test('journeys: origin, destination, walking radius and time', () async {
      final h = _Harness({
        'data': [journeyResource()],
      });

      final journeys = await h.service.journeys(
        originLatitude: 9.93,
        originLongitude: -84.08,
        destinationLatitude: 10.01,
        destinationLongitude: -84.21,
        departureAt: DateTime.utc(2026, 11, 13, 16),
      );

      final url = h.requests.single.url;
      expect(url.path, endsWith('/ops/journeys'));
      expect(url.queryParameters, {
        'origin_lat': '9.93',
        'origin_lng': '-84.08',
        'destination_lat': '10.01',
        'destination_lng': '-84.21',
        'walking_radius_m': '800',
        'page[size]': '30',
        'departure_at': '2026-11-13T16:00:00.000Z',
      });
      expect(journeys.single.routeCode, 'PV-RF');
    });
  });
}
