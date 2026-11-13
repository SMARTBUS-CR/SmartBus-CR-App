import 'package:flutter_test/flutter_test.dart';
import 'package:smartbus_drivers/features/operations/models/operations_models.dart';
import 'package:smartbus_drivers/features/operations/services/route_proximity.dart';

import 'operations_fixtures.dart';

const _lat = 9.9350;
const _lng = -84.0800;

/// [meters] north of the passenger (1° of latitude ≈ 111.2 km).
double _north(double meters) => _lat + meters / 111195;

/// A road ~220 m east of the passenger, from 5 km south to 9 km north
/// (14 km, 28 min), with stops only at its ends.
final _roadLng = _lng + 0.002;
final _road = route(
  'r-road',
  code: 'PV-GUA',
  name: 'Puerto Viejo - Guápiles',
  patterns: [
    pattern(
      'p-north',
      headsign: 'Norte',
      drivingSeconds: 28 * 60,
      geometry: [
        GeoPoint(_north(-5000), _roadLng),
        GeoPoint(_north(9000), _roadLng),
      ],
    ),
    // The other direction: north → south.
    pattern(
      'p-south',
      headsign: 'Sur',
      drivingSeconds: 28 * 60,
      geometry: [
        GeoPoint(_north(9000), _roadLng),
        GeoPoint(_north(-5000), _roadLng),
      ],
    ),
  ],
);

/// No `route_geometry`: only its stops (not used for "passes near").
final _noGeometry = route(
  'r-none',
  code: 'X',
  name: 'Sin trazo',
  patterns: [
    pattern(
      'p-none',
      stops: [
        stopAt('A', _north(-100), _lng, seq: 1),
        stopAt('B', _north(100), _lng, seq: 2),
      ],
    ),
  ],
);

void main() {
  group('closestOnPath', () {
    test(
      'perpendicular point on a segment, its distance and how far along',
      () {
        final hit = closestOnPath(
          [GeoPoint(_north(-5000), _roadLng), GeoPoint(_north(9000), _roadLng)],
          _lat,
          _lng,
        )!;

        expect(hit.point.latitude, closeTo(_lat, 1e-6));
        expect(hit.point.longitude, closeTo(_roadLng, 1e-9));
        expect(hit.distanceMeters, closeTo(219.3, 1));
        expect(hit.alongMeters, closeTo(5000, 2));
      },
    );

    test('past the end: the end point; several segments add up', () {
      final path = [
        GeoPoint(_north(0), _lng + 0.01),
        GeoPoint(_north(1000), _lng + 0.01),
        GeoPoint(_north(1000), _lng + 0.02),
      ];
      final hit = closestOnPath(path, _north(-500), _lng + 0.01)!;
      expect(hit.alongMeters, 0);
      expect(hit.distanceMeters, closeTo(500, 2));

      final second = closestOnPath(path, _north(1300), _lng + 0.015)!;
      expect(second.point.latitude, closeTo(_north(1000), 1e-9));
      expect(second.alongMeters, closeTo(1000 + 548, 3));
    });

    test('fewer than 2 points: null', () {
      expect(closestOnPath(const [], _lat, _lng), isNull);
      expect(closestOnPath([GeoPoint(_lat, _lng)], _lat, _lng), isNull);
    });
  });

  test('routesPassingNear: by the line, within the radius, closest first; '
      'routes without geometry are left out', () {
    final near = routesPassingNear(
      latitude: _lat,
      longitude: _lng,
      routes: [_road, _noGeometry],
    );
    expect(near.map((r) => r.pattern.id), ['p-north', 'p-south']);
    expect(near.first.origin.distanceMeters, closeTo(219, 1));

    expect(
      routesPassingNear(
        latitude: _lat,
        longitude: _lng,
        routes: [_road],
        radiusMeters: 200,
      ),
      isEmpty,
    );
  });

  group('routesPassingBetween', () {
    test('only the direction that reaches the origin first', () {
      final found = routesPassingBetween(
        origin: GeoPoint(_lat, _lng),
        destination: GeoPoint(_north(6000), _lng),
        routes: [_road],
      );

      final trip = found.single;
      expect(trip.pattern.id, 'p-north');
      expect(trip.destination!.distanceMeters, closeTo(219, 1));
      // 5 of 14 km from the start: 10 min; 6 km more on the bus: 12 min.
      expect(trip.minutesToOrigin, closeTo(10, 0.05));
      expect(trip.rideMinutes, closeTo(12, 0.05));
    });

    test('too far from the road (origin or destination): nothing', () {
      expect(
        routesPassingBetween(
          origin: GeoPoint(_lat, _lng - 0.01),
          destination: GeoPoint(_north(6000), _roadLng),
          routes: [_road],
        ),
        isEmpty,
      );
      expect(
        routesPassingBetween(
          origin: GeoPoint(_lat, _lng),
          destination: GeoPoint(_north(6000), _lng - 0.01),
          routes: [_road],
        ),
        isEmpty,
      );
    });
  });

  group('nextPassAt', () {
    final trip = routesPassingBetween(
      origin: GeoPoint(_lat, _lng),
      destination: GeoPoint(_north(6000), _lng),
      routes: [_road],
    ).single;
    // Friday 13 Nov 2026.
    final weekly = [departure(5, 10), departure(5, 11), departure(6, 6)];

    test('the next departure plus the minutes to reach the passenger', () {
      expect(
        trip.nextPassAt(weekly, DateTime(2026, 11, 13, 9)),
        DateTime(2026, 11, 13, 10, 10),
      );
      // 10:10 already passed.
      expect(
        trip.nextPassAt(weekly, DateTime(2026, 11, 13, 10, 15)),
        DateTime(2026, 11, 13, 11, 10),
      );
    });

    test('none left today: tomorrow; none at all: null', () {
      expect(
        trip.nextPassAt(weekly, DateTime(2026, 11, 13, 22)),
        DateTime(2026, 11, 14, 6, 10),
      );
      expect(trip.nextPassAt(const [], DateTime(2026, 11, 13, 9)), isNull);
    });
  });
}
