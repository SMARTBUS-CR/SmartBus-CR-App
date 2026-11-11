import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:smartbus_drivers/core/network/api_client.dart';
import 'package:smartbus_drivers/core/network/api_exception.dart';
import 'package:smartbus_drivers/core/storage/secure_session_store.dart';
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
