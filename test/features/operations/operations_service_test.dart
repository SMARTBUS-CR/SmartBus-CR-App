import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:smartbus_drivers/core/network/api_client.dart';
import 'package:smartbus_drivers/core/network/api_exception.dart';
import 'package:smartbus_drivers/core/storage/secure_session_store.dart';
import 'package:smartbus_drivers/features/operations/models/operations_models.dart';
import 'package:smartbus_drivers/features/operations/services/operations_service.dart';
import 'package:smartbus_drivers/features/trip_tracking/models/trip_tracking.dart';

import 'operations_fixtures.dart';

class _Harness {
  _Harness(Object body, {int status = 200}) {
    final store = SecureSessionStore();
    service = OperationsService(
      client: ApiClient(
        sessionStore: store,
        httpClient: MockClient((request) async {
          requests.add(request);
          return http.Response(
            jsonEncode(body),
            status,
            headers: {
              'content-type': 'application/vnd.api+json; charset=utf-8',
            },
          );
        }),
      ),
    );
  }

  final List<http.Request> requests = [];
  late final OperationsService service;
}

void main() {
  setUp(
    () => FlutterSecureStorage.setMockInitialValues({'sb_access_token': 'tok'}),
  );

  group('driver', () {
    test('driverTrips: today\'s trips of the driver, with the route', () async {
      final h = _Harness({
        'data': [tripResource(status: 'scheduled')],
      });

      final trips = await h.service.driverTrips(
        serviceDate: DateTime(2026, 11, 11, 9, 30),
      );

      final request = h.requests.single;
      expect(request.method, 'GET');
      expect(request.url.path, endsWith('/ops/driver/trips'));
      expect(request.url.queryParameters['filter[service_date]'], '2026-11-11');
      expect(request.url.queryParameters.containsKey('filter[status]'), false);
      expect(request.url.queryParameters['include'], 'pattern,bus');
      expect(request.url.queryParameters['sort'], 'scheduled_departure_at');
      expect(request.headers['Authorization'], 'Bearer tok');

      final trip = trips.single;
      expect(trip.id, tripId);
      expect(trip.status, TripStatus.scheduled);
      expect(trip.routePatternId, patternId);
      expect(trip.title, 'PV-RF · Puerto Viejo');
      expect(trip.headsign, 'Puerto Viejo');
      expect(
        trip.scheduledDepartureAt?.toUtc(),
        DateTime.utc(2026, 11, 11, 13),
      );
    });

    test('driverTrips: bus plate and unit from the included bus', () async {
      final h = _Harness({
        'data': [tripResource(withRelationships: true)],
        'included': driverTripsIncluded(),
      });

      final trip = (await h.service.driverTrips()).single;

      expect(trip.busPlate, 'SJB-1234');
      expect(trip.busUnit, '07');
      expect(trip.busLabel, 'Bus SJB-1234 · Unidad 07');
      // The route snapshot wins over the pattern headsign.
      expect(trip.headsign, 'Puerto Viejo');
    });

    test('driverTrips: without snapshot, headsign of the pattern', () async {
      final h = _Harness({
        'data': [tripResource(snapshot: null, withRelationships: true)],
        'included': driverTripsIncluded(),
      });

      final trip = (await h.service.driverTrips()).single;

      expect(trip.headsign, 'Terminal Puerto Viejo');
    });

    test('driverTrips: the planned route of the trip (snapshot)', () async {
      final h = _Harness({
        'data': [tripResource(snapshot: plannedSnapshot)],
      });

      final route = (await h.service.driverTrips()).single.plannedPattern!;

      expect(route.id, patternId);
      expect(route.headsign, 'Puerto Viejo');
      expect(route.geometry, hasLength(3));
      expect(route.geometry.first.latitude, 10.46);
      expect(route.geometry.first.longitude, -84.0);
      // Sorted by stop_sequence; lat / lng arrive as strings.
      expect(route.stops.map((s) => s.name), ['Terminal', 'Centro', 'Muelle']);
      expect(route.stops[1].latitude, 10.47);
      expect(route.stops[1].minutesFromStart, 10);
      expect(route.distanceMeters, 2200);
    });

    test('driverTrips: a snapshot without route data → no planned route', () {
      final trip = DriverTrip.fromJsonApi(tripResource());
      expect(trip.plannedPattern, isNull);
    });

    test('routePattern: GET ops/route-patterns/{id}', () async {
      final h = _Harness({'data': patternResource()});

      final pattern = await h.service.routePattern(patternId);

      expect(
        h.requests.single.url.path,
        endsWith('/ops/route-patterns/$patternId'),
      );
      expect(pattern.stops.map((s) => s.name), ['Terminal', 'Centro']);
    });

    test('driverTrips: no bus included → no bus label', () async {
      final h = _Harness({
        'data': [tripResource()],
      });

      expect((await h.service.driverTrips()).single.busLabel, isNull);
    });

    test('driverTrips: filters by status', () async {
      final h = _Harness({'data': <Object>[]});

      await h.service.driverTrips(status: TripStatus.inProgress);

      expect(
        h.requests.single.url.queryParameters['filter[status]'],
        'in_progress',
      );
    });

    test('a trip without route snapshot still has a title', () async {
      final h = _Harness({
        'data': [tripResource(snapshot: null)],
      });

      final trip = (await h.service.driverTrips()).single;

      expect(trip.title, 'Viaje asignado');
      expect(trip.headsign, isNull);
    });

    test('startTrip / completeTrip: POST and return the new status', () async {
      final h = _Harness({
        'data': tripResource(
          status: 'in_progress',
          actualDepartureAt: '2026-11-11T13:05:00.000000Z',
        ),
      });

      final started = await h.service.startTrip(tripId);
      await h.service.completeTrip(tripId);

      expect(started.status, TripStatus.inProgress);
      expect(
        started.actualDepartureAt?.toUtc(),
        DateTime.utc(2026, 11, 11, 13, 5),
      );
      expect(started.actualDepartureAt!.isUtc, isFalse); // shown in local time
      expect(h.requests.first.headers['Authorization'], 'Bearer tok');
      expect(h.requests.map((r) => r.method), ['POST', 'POST']);
      expect(h.requests[0].url.path, endsWith('/ops/trips/$tripId/start'));
      expect(h.requests[1].url.path, endsWith('/ops/trips/$tripId/complete'));
    });

    test('startTrip: 409 arrives as a conflict with the backend message', () {
      final h = _Harness({
        'errors': [
          {'status': '409', 'detail': 'El viaje ya fue iniciado.'},
        ],
      }, status: 409);

      expect(
        h.service.startTrip(tripId),
        throwsA(
          isA<ApiException>()
              .having((e) => e.type, 'type', ApiErrorType.conflict)
              .having((e) => e.message, 'message', 'El viaje ya fue iniciado.'),
        ),
      );
    });

    test('startTrip: 422 business rule arrives with the backend message', () {
      final h = _Harness({
        'errors': [
          {
            'status': '422',
            'detail': 'The driver already has a trip in progress.',
            'source': {'pointer': '/data/attributes/driver_id'},
          },
        ],
      }, status: 422);

      expect(
        h.service.startTrip(tripId),
        throwsA(
          isA<ApiException>()
              .having((e) => e.type, 'type', ApiErrorType.validation)
              .having(
                (e) => e.message,
                'message',
                'The driver already has a trip in progress.',
              ),
        ),
      );
    });

    test('startTrip: 403 / 404 arrive as forbidden / notFound', () async {
      for (final (status, type) in [
        (403, ApiErrorType.forbidden),
        (404, ApiErrorType.notFound),
      ]) {
        final h = _Harness({'errors': <Object>[]}, status: status);
        await expectLater(
          h.service.startTrip(tripId),
          throwsA(isA<ApiException>().having((e) => e.type, 'type', type)),
        );
      }
    });

    test('completeTrip: completed with the backend actual_arrival_at '
        '(read as UTC, shown in local time)', () async {
      final h = _Harness({
        'data': tripResource(
          status: 'completed',
          actualDepartureAt: '2026-11-11T13:05:00.000000Z',
          actualArrivalAt: '2026-11-11T14:07:00.000000Z',
        ),
      });

      final done = await h.service.completeTrip(tripId);

      expect(done.status, TripStatus.completed);
      expect(done.actualArrivalAt?.toUtc(), DateTime.utc(2026, 11, 11, 14, 7));
      expect(done.actualArrivalAt!.isUtc, isFalse);
      expect(h.requests.single.body, isEmpty);
    });

    test(
      'completeTrip: 409 arrives as a conflict with the backend message',
      () {
        final h = _Harness({
          'errors': [
            {
              'status': '409',
              'detail': 'Solo se pueden completar viajes en curso.',
            },
          ],
        }, status: 409);

        expect(
          h.service.completeTrip(tripId),
          throwsA(
            isA<ApiException>()
                .having((e) => e.type, 'type', ApiErrorType.conflict)
                .having(
                  (e) => e.message,
                  'message',
                  'Solo se pueden completar viajes en curso.',
                ),
          ),
        );
      },
    );

    test('trip: GET ops/trips/{id} with the token, current status', () async {
      final h = _Harness({'data': tripResource(status: 'cancelled')});

      final trip = await h.service.trip(tripId);

      expect(trip.status, TripStatus.cancelled);
      expect(h.requests.single.method, 'GET');
      expect(h.requests.single.url.path, endsWith('/ops/trips/$tripId'));
      expect(h.requests.single.headers['Authorization'], 'Bearer tok');
    });
  });

  group('cache (each Dashboard request takes seconds)', () {
    test('the catalogue is asked once: later calls reuse it', () async {
      final h = _Harness({
        'data': [routeResource()],
      });

      await h.service.routes();
      await h.service.routes();
      await h.service.routePatterns(routeId);
      await h.service.routePatterns(routeId);
      await h.service.routeFares(routeId);
      await h.service.routeFares(routeId);

      expect(h.requests, hasLength(3));
    });

    test('two screens asking at once share one request', () async {
      final h = _Harness({'data': <Object>[]});

      await Future.wait([
        h.service.patternSchedules(patternId),
        h.service.patternSchedules(patternId),
      ]);

      expect(h.requests, hasLength(1));
    });

    test('a failed request is not kept: the next call asks again', () async {
      final h = _Harness({'message': 'down'}, status: 503);

      await expectLater(h.service.routes(), throwsA(isA<ApiException>()));
      await expectLater(h.service.routes(), throwsA(isA<ApiException>()));

      expect(h.requests, hasLength(2));
    });

    test('live data is never cached (driver trips, buses running)', () async {
      final h = _Harness({'data': <Object>[]});

      await h.service.driverTrips();
      await h.service.driverTrips();
      await h.service.ongoingTrips(patternId);
      await h.service.ongoingTrips(patternId);

      expect(h.requests, hasLength(4));
    });
  });

  group('passenger catalogue', () {
    test('routes', () async {
      final h = _Harness({
        'data': [routeResource()],
      });

      final route = (await h.service.routes()).single;

      expect(h.requests.single.url.path, endsWith('/ops/routes'));
      expect(route.id, routeId);
      expect(route.code, 'PV-RF');
      expect(route.name, 'Puerto Viejo');
    });

    test('routePatterns: stops in order and the line as lat/lng', () async {
      final h = _Harness({
        'data': [patternResource()],
      });

      final pattern = (await h.service.routePatterns(routeId)).single;

      expect(
        h.requests.single.url.path,
        endsWith('/ops/routes/$routeId/patterns'),
      );
      expect(pattern.label, 'Hacia Puerto Viejo');
      expect(pattern.stops.map((s) => s.name), ['Terminal', 'Centro']);
      expect(pattern.stops.last.minutesFromStart, 12);
      // GeoJSON is [lng, lat].
      expect(pattern.geometry.first.latitude, 10.46);
      expect(pattern.geometry.first.longitude, -83.99);
      expect(pattern.drivingDurationSeconds, 1500);
    });

    test('routePatterns: no geometry -> empty line', () async {
      final h = _Harness({
        'data': [patternResource(geometry: null)],
      });

      final pattern = (await h.service.routePatterns(routeId)).single;

      expect(pattern.geometry, isEmpty);
    });

    group('routesWithPatterns (include=patterns)', () {
      // Shape checked against -dev: patterns in `included`, linked from
      // `relationships.patterns.data`; other included types are ignored.
      Map<String, dynamic> routeWith(
        String id,
        String code,
        List<String> ids,
      ) => {
        'id': id,
        'type': 'routes',
        'attributes': {'code': code, 'name': 'Ruta $code'},
        'relationships': {
          'company': {
            'data': {'id': 'c1', 'type': 'companies'},
          },
          'patterns': {
            'data': [
              for (final p in ids) {'id': p, 'type': 'route-patterns'},
            ],
          },
        },
      };

      Map<String, dynamic> patternWith(
        String id,
        String routeId, {
        Object? geometry,
        Object? distance,
      }) => {
        'id': id,
        'type': 'route-patterns',
        'attributes': {
          'code': id.toUpperCase(),
          'name': 'Patrón $id',
          'headsign': 'Destino $id',
          'route_id': routeId,
          'route_geometry': geometry,
          'distance_meters': distance,
          'driving_duration_seconds': null,
          'stops': [
            {
              'stop_id': 's-$id',
              'stop_name': 'Parada $id',
              'stop_sequence': 1,
              'minutes_from_start': 0,
              'latitude': 9.9281,
              'longitude': -84.0907,
            },
          ],
        },
        'relationships': <String, dynamic>{},
      };

      test('one request; patterns linked to their route, in order', () async {
        final h = _Harness({
          'data': [
            routeWith('r1', 'DEMO-CITY', ['p1']),
            routeWith('r2', 'PV-RF', ['p3', 'p2']),
          ],
          'included': [
            {
              'id': 'c1',
              'type': 'companies',
              'attributes': {'name': 'SmartBus'},
            },
            patternWith(
              'p1',
              'r1',
              geometry: {
                'type': 'LineString',
                'coordinates': [
                  [-84.0907, 9.9281],
                  [-84.0800, 9.9350],
                ],
              },
              distance: 1800,
            ),
            patternWith('p2', 'r2'),
            patternWith('p3', 'r2'),
          ],
        });

        final routes = await h.service.routesWithPatterns();

        final request = h.requests.single;
        expect(request.url.path, endsWith('/ops/routes'));
        expect(request.url.queryParameters['include'], 'patterns');
        expect(request.url.queryParameters['page[size]'], '100');

        expect(routes.map((r) => r.code), ['DEMO-CITY', 'PV-RF']);
        // The relationship order wins.
        expect(routes[1].patterns.map((p) => p.id), ['p3', 'p2']);

        final withGeometry = routes[0].patterns.single;
        expect(withGeometry.hasGeometry, isTrue);
        expect(withGeometry.geometry.last.latitude, 9.935);
        expect(withGeometry.distanceMeters, 1800);
        expect(withGeometry.stops.single.name, 'Parada p1');

        final withoutGeometry = routes[1].patterns.first;
        expect(withoutGeometry.hasGeometry, isFalse);
        expect(withoutGeometry.distanceMeters, isNull);
        // Without geometry, the path joins the stops.
        expect(withoutGeometry.path.single.latitude, 9.9281);
      });

      test('no relationships: patterns linked by their route_id', () async {
        final h = _Harness({
          'data': [
            {
              'id': 'r1',
              'type': 'routes',
              'attributes': {'code': 'A', 'name': 'A'},
            },
          ],
          'included': [
            patternWith('p2', 'r1'),
            patternWith('p1', 'r1'),
            patternWith('px', 'other'),
          ],
        });

        final route = (await h.service.routesWithPatterns()).single;

        expect(route.patterns.map((p) => p.id), ['p1', 'p2']);
      });

      test('no included: routes without patterns', () async {
        final h = _Harness({
          'data': [
            routeWith('r1', 'A', ['p1']),
          ],
        });

        final route = (await h.service.routesWithPatterns()).single;

        expect(route.patterns, isEmpty);
      });
    });

    test('directionLabel tells apart patterns with the same headsign', () {
      RoutePattern p(String id, String name, String headsign) =>
          RoutePattern(id: id, name: name, headsign: headsign);
      final route = TransitRoute(
        id: 'r',
        code: 'SJ-PV',
        name: 'San José - Puerto Viejo',
        patterns: [
          p('a', 'Puerto Viejo - San José por Vara Blanca', 'San José'),
          p('b', 'Puerto Viejo - San José por Zurquí', 'San José'),
          p('c', 'San José - Puerto Viejo', 'Puerto Viejo'),
        ],
      );

      expect(route.patterns.map(route.directionLabel), [
        'Hacia San José por Vara Blanca',
        'Hacia San José por Zurquí',
        'Hacia Puerto Viejo',
      ]);
    });

    test('ongoingTrips: buses running on a pattern', () async {
      final h = _Harness({
        'data': [liveTripResource()],
      });

      final bus = (await h.service.ongoingTrips(patternId)).single;

      expect(
        h.requests.single.url.path,
        endsWith('/ops/route-patterns/$patternId/trips'),
      );
      expect(bus.id, tripId);
      expect(bus.status, TripStatus.inProgress);
      expect(bus.busLabel, 'Unidad 12 · ABC-123');
    });
  });
}
