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
      final h = _Harness({'data': tripResource(status: 'in_progress')});

      final started = await h.service.startTrip(tripId);
      await h.service.completeTrip(tripId);

      expect(started.status, TripStatus.inProgress);
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
          isA<ApiException>().having(
            (e) => e.type,
            'type',
            ApiErrorType.conflict,
          ),
        ),
      );
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
