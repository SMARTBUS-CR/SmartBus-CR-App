import 'package:flutter_test/flutter_test.dart';
import 'package:smartbus_drivers/features/operations/models/operations_models.dart';
import 'package:smartbus_drivers/features/operations/services/nearby_routes_filter.dart';

import 'operations_fixtures.dart';

// Passenger in Puerto Viejo de Sarapiquí.
const _lat = 10.4560;
const _lng = -84.0170;

/// A point [meters] north of the passenger (1° of latitude ≈ 111.2 km).
double _north(double meters) => _lat + meters / 111195;

void main() {
  group('haversineMeters', () {
    test('same point: 0 m', () {
      expect(haversineMeters(_lat, _lng, _lat, _lng), 0);
    });

    test('San José -> Puerto Viejo ≈ 60 km in a straight line', () {
      final d = haversineMeters(9.9281, -84.0907, 10.4560, -84.0170);
      expect(d, closeTo(59200, 800));
    });

    test('1° of latitude ≈ 111.2 km', () {
      expect(haversineMeters(0, 0, 1, 0), closeTo(111195, 5));
    });
  });

  group('NearbyRoutesFilter', () {
    const filter = NearbyRoutesFilter();

    test('default radius is 1000 m', () {
      expect(NearbyRoutesFilter.defaultRadiusMeters, 1000);
      expect(filter.radiusMeters, 1000);
    });

    test('a stop inside the radius: the route is nearby', () {
      final result = filter.apply(
        latitude: _lat,
        longitude: _lng,
        routes: [
          route(
            'r1',
            code: 'PV-RF',
            name: 'Puerto Viejo - Río Frío',
            patterns: [
              pattern(
                'p1',
                headsign: 'Río Frío',
                stops: [stopAt('Centro', _north(230), _lng, seq: 1)],
              ),
            ],
          ),
        ],
      );

      final nearby = result.single;
      expect(nearby.route.id, 'r1');
      expect(nearby.pattern.id, 'p1');
      expect(nearby.stop.name, 'Centro');
      expect(nearby.distanceMeters, closeTo(230, 1));
    });

    test('every stop outside the radius: the route is left out', () {
      final result = filter.apply(
        latitude: _lat,
        longitude: _lng,
        routes: [
          route(
            'r1',
            code: 'SJ-PV',
            name: 'San José',
            patterns: [
              pattern(
                'p1',
                stops: [stopAt('Lejos', _north(1500), _lng, seq: 1)],
              ),
            ],
          ),
        ],
      );

      expect(result, isEmpty);
    });

    test('a stop exactly at the radius counts as nearby', () {
      final stop = stopAt('Borde', _north(1000), _lng, seq: 1);
      final exact = haversineMeters(
        _lat,
        _lng,
        stop.latitude!,
        stop.longitude!,
      );
      final result = NearbyRoutesFilter(radiusMeters: exact).apply(
        latitude: _lat,
        longitude: _lng,
        routes: [
          route(
            'r1',
            code: 'A',
            name: 'A',
            patterns: [
              pattern('p1', stops: [stop]),
            ],
          ),
        ],
      );

      expect(result.single.distanceMeters, exact);
    });

    test('sorted from the closest to the farthest', () {
      TransitRoute r(String id, double meters) => route(
        id,
        code: id,
        name: id,
        patterns: [
          pattern(
            'p-$id',
            stops: [stopAt('s-$id', _north(meters), _lng, seq: 1)],
          ),
        ],
      );

      final result = filter.apply(
        latitude: _lat,
        longitude: _lng,
        routes: [r('far', 900), r('near', 100), r('out', 2000), r('mid', 450)],
      );

      expect(result.map((n) => n.route.id), ['near', 'mid', 'far']);
    });

    test('empty list: nothing nearby', () {
      expect(
        filter.apply(latitude: _lat, longitude: _lng, routes: const []),
        isEmpty,
      );
    });

    test('several patterns: the stop and direction closest to the user', () {
      final result = filter.apply(
        latitude: _lat,
        longitude: _lng,
        routes: [
          route(
            'r1',
            code: 'PV-RF',
            name: 'PV-RF',
            patterns: [
              pattern(
                'to-pv',
                headsign: 'Puerto Viejo',
                stops: [
                  stopAt('A', _north(800), _lng, seq: 1),
                  stopAt('B', _north(600), _lng, seq: 2),
                ],
              ),
              pattern(
                'to-rf',
                headsign: 'Río Frío',
                stops: [
                  stopAt('C', _north(5000), _lng, seq: 1),
                  stopAt('D', _north(150), _lng, seq: 2),
                ],
              ),
            ],
          ),
        ],
      );

      // One entry per route, not per pattern.
      final nearby = result.single;
      expect(nearby.pattern.id, 'to-rf');
      expect(nearby.stop.name, 'D');
      expect(nearby.distanceMeters, closeTo(150, 1));
    });

    test('stops without coordinates are ignored', () {
      final result = filter.apply(
        latitude: _lat,
        longitude: _lng,
        routes: [
          route(
            'r1',
            code: 'A',
            name: 'A',
            patterns: [
              pattern(
                'p1',
                stops: [
                  const PatternStop(stopId: 'x', name: 'Sin GPS', sequence: 1),
                ],
              ),
            ],
          ),
        ],
      );

      expect(result, isEmpty);
      expect(
        NearbyRoutesFilter.closest(
          route('r2', code: 'B', name: 'B'),
          latitude: _lat,
          longitude: _lng,
        ),
        isNull,
      );
    });
  });

  test('formatDistance', () {
    expect(formatDistance(230.4), '230 m');
    expect(formatDistance(999), '1 km');
    expect(formatDistance(1000), '1 km');
    expect(formatDistance(1450), '1,4 km');
  });
}
