import 'package:flutter_test/flutter_test.dart';
import 'package:smartbus_drivers/features/operations/models/operations_models.dart';
import 'package:smartbus_drivers/features/operations/services/nearby_stops.dart';

import 'operations_fixtures.dart';

const _lat = 9.9350;
const _lng = -84.0800;

/// A point [meters] north of the passenger.
double _north(double meters) => _lat + meters / 111195;

void main() {
  final a = route(
    'r-a',
    code: 'B-2',
    name: 'Ruta B',
    patterns: [
      pattern(
        'p-a1',
        headsign: 'Norte',
        stops: [
          stopAt('Centro', _north(300), _lng, seq: 1),
          stopAt('Lejos', _north(3000), _lng, seq: 2),
          const PatternStop(stopId: 'no-coords', name: 'Sin GPS', sequence: 3),
        ],
      ),
      // The other direction stops at "Centro" too.
      pattern(
        'p-a2',
        headsign: 'Sur',
        stops: [stopAt('Centro', _north(300), _lng, seq: 1)],
      ),
    ],
  );
  final b = route(
    'r-b',
    code: 'A-1',
    name: 'Ruta A',
    patterns: [
      pattern(
        'p-b',
        headsign: 'Este',
        stops: [
          stopAt('Escuela', _north(100), _lng, seq: 1),
          stopAt('Centro', _north(300), _lng, seq: 2),
        ],
      ),
    ],
  );

  test(
    'within the radius, closest first; far and unlocated stops left out',
    () {
      final stops = nearbyStops(
        latitude: _lat,
        longitude: _lng,
        routes: [a, b],
      );

      expect(stops.map((s) => s.name), ['Escuela', 'Centro']);
      expect(stops.first.distanceMeters, closeTo(100, 1));
    },
  );

  test('a shared stop appears once, with every route direction, by code', () {
    final centro = nearbyStops(
      latitude: _lat,
      longitude: _lng,
      routes: [a, b],
    ).singleWhere((s) => s.name == 'Centro');

    expect(centro.routes.map((r) => '${r.route.code} ${r.pattern.headsign}'), [
      'A-1 Este',
      'B-2 Norte',
      'B-2 Sur',
    ]);
  });

  test('custom radius and limit', () {
    expect(
      nearbyStops(
        latitude: _lat,
        longitude: _lng,
        routes: [a, b],
        radiusMeters: 5000,
      ).map((s) => s.name),
      ['Escuela', 'Centro', 'Lejos'],
    );
    expect(
      nearbyStops(
        latitude: _lat,
        longitude: _lng,
        routes: [a, b],
        limit: 1,
      ).map((s) => s.name),
      ['Escuela'],
    );
  });

  test('no routes: nothing nearby', () {
    expect(nearbyStops(latitude: _lat, longitude: _lng, routes: []), isEmpty);
  });
}
