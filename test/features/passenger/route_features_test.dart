import 'package:flutter_test/flutter_test.dart';
import 'package:smartbus_drivers/features/operations/models/operations_models.dart';
import 'package:smartbus_drivers/features/passenger/map/passenger_map.dart';

import '../operations/operations_fixtures.dart';

void main() {
  test('no pattern: empty collection (clears the map)', () {
    expect(routeFeatureCollection(null)['features'], isEmpty);
  });

  test('with geometry: solid line from the geometry + numbered stops', () {
    final collection = routeFeatureCollection(
      pattern(
        'p1',
        stops: [
          stopAt('A', 10.0, -84.0, seq: 1),
          stopAt('B', 10.1, -84.1, seq: 2),
        ],
        geometry: const [
          GeoPoint(10.0, -84.0),
          GeoPoint(10.05, -84.02),
          GeoPoint(10.1, -84.1),
        ],
      ),
    );

    final features = collection['features'] as List;
    final line = features.first;
    expect(line['properties']['approximate'], isFalse);
    // GeoJSON order: [lng, lat].
    expect(line['geometry']['coordinates'], [
      [-84.0, 10.0],
      [-84.02, 10.05],
      [-84.1, 10.1],
    ]);
    expect(features.skip(1).map((f) => f['id']), ['stop-0', 'stop-1']);
    expect(features.skip(1).map((f) => f['properties']['seq']), ['1', '2']);
  });

  test('without geometry: line joining the located stops in order', () {
    final collection = routeFeatureCollection(
      pattern(
        'p1',
        stops: [
          stopAt('A', 10.0, -84.0, seq: 1),
          // No coordinates: not drawn, but keeps its number.
          const PatternStop(stopId: 'x', name: 'Sin GPS', sequence: 2),
          stopAt('C', 10.2, -84.2, seq: 3),
        ],
      ),
    );

    final features = collection['features'] as List;
    expect(features.first['properties']['approximate'], isTrue);
    expect(features.first['geometry']['coordinates'], [
      [-84.0, 10.0],
      [-84.2, 10.2],
    ]);
    // Ids map back to pattern.stops (index 1 is skipped).
    expect(features.skip(1).map((f) => f['id']), ['stop-0', 'stop-2']);
    expect(features.skip(1).map((f) => f['properties']['seq']), ['1', '3']);
  });

  test('start / end / mid stops, and the selected one', () {
    final stops = [
      stopAt('A', 10.0, -84.0, seq: 1),
      stopAt('B', 10.1, -84.1, seq: 2),
      stopAt('C', 10.2, -84.2, seq: 3),
    ];
    final features =
        routeFeatureCollection(
              pattern('p1', stops: stops),
              selected: stops[1],
            )['features']
            as List;

    final points = features.skip(1).map((f) => f['properties']).toList();
    expect(points.map((p) => p['kind']), ['start', 'mid', 'end']);
    expect(points.map((p) => p['selected']), [false, true, false]);
  });

  test('a single located stop: no line, just the marker', () {
    final features =
        routeFeatureCollection(
              pattern('p1', stops: [stopAt('A', 10.0, -84.0, seq: 1)]),
            )['features']
            as List;

    expect(features.single['geometry']['type'], 'Point');
  });
}
