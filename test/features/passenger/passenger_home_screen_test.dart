import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartbus_drivers/core/config/map_config.dart';
import 'package:smartbus_drivers/core/location/location_service.dart';
import 'package:smartbus_drivers/core/network/api_exception.dart';
import 'package:smartbus_drivers/core/theme.dart';
import 'package:smartbus_drivers/features/operations/models/operations_models.dart';
import 'package:smartbus_drivers/features/passenger/map/map_overlay.dart';
import 'package:smartbus_drivers/features/passenger/map/passenger_map.dart';
import 'package:smartbus_drivers/features/passenger/passenger_home_screen.dart';
import 'package:smartbus_drivers/features/passenger/services/favorites_controller.dart';
import 'package:smartbus_drivers/features/trip_tracking/models/trip_tracking.dart';
import 'package:smartbus_drivers/features/trip_tracking/services/route_live_buses.dart';

import '../operations/operations_fixtures.dart';
import '../trip_tracking/trip_tracking_fakes.dart';
import 'favorites_fakes.dart';

// ---------------------------------------------------------------------------
// Test doubles: the native MapLibre map cannot run in widget tests.
// ---------------------------------------------------------------------------

class _FakeMap implements PassengerMapHandle {
  final List<({double lat, double lng, double? zoom})> moves = [];
  final List<DeviceLocation> userLocations = [];
  MapMode? mode;

  /// Pattern drawn right now (`null` = no route on the map).
  RoutePattern? route;

  /// Every `showRoute` / `clearRoute`, in order: the pattern id or 'clear'.
  final List<String> routeCalls = [];
  final List<({List<GeoPoint> points, EdgeInsets padding})> fits = [];
  ValueChanged<PatternStop>? onStopTap;
  ValueChanged<String>? onBusTap;

  @override
  Future<void> moveTo(
    double latitude,
    double longitude, {
    double? zoom,
  }) async => moves.add((lat: latitude, lng: longitude, zoom: zoom));

  @override
  Future<void> showUserLocation(DeviceLocation location) async =>
      userLocations.add(location);

  @override
  Future<void> showBus(BusMarker? bus) async {}

  /// Bus pins drawn right now.
  List<BusMarker> buses = const [];

  @override
  Future<void> showBuses(List<BusMarker> buses) async => this.buses = buses;

  @override
  Future<void> showRoute(RoutePattern pattern) async {
    route = pattern;
    highlighted = null;
    routeCalls.add(pattern.id);
  }

  @override
  Future<void> clearRoute() async {
    route = null;
    highlighted = null;
    routeCalls.add('clear');
  }

  /// Stop with the halo right now.
  PatternStop? highlighted;

  @override
  Future<void> highlightStop(PatternStop? stop) async => highlighted = stop;

  @override
  Future<void> fitBounds(
    List<GeoPoint> points, {
    EdgeInsets padding = EdgeInsets.zero,
  }) async => fits.add((points: points, padding: padding));

  /// What the GeoJSON source of the real map would contain.
  Map<String, dynamic> get drawn =>
      routeFeatureCollection(route, selected: highlighted);

  PassengerMapBuilder get builder => (context, options) {
    mode = options.mode;
    onStopTap = options.onStopTap;
    onBusTap = options.onBusTap;
    return _FakeMapWidget(onReady: () => options.onReady(this));
  };
}

class _FakeMapWidget extends StatefulWidget {
  const _FakeMapWidget({required this.onReady});

  final VoidCallback onReady;

  @override
  State<_FakeMapWidget> createState() => _FakeMapWidgetState();
}

class _FakeMapWidgetState extends State<_FakeMapWidget> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => widget.onReady());
  }

  @override
  Widget build(BuildContext context) =>
      const ColoredBox(key: Key('fake-map'), color: Color(0xFFE5E7EB));
}

class _FakeLocationService extends LocationService {
  _FakeLocationService({required this.access, this.location});

  LocationAccess access;
  DeviceLocation? location;
  final List<bool> accessChecks = [];
  final List<LocationAccess> openedSettings = [];

  @override
  Future<LocationAccess> checkAccess({bool request = true}) async {
    accessChecks.add(request);
    return access;
  }

  @override
  Future<DeviceLocation?> currentLocation() async => location;

  @override
  Stream<DeviceLocation> watch() => const Stream.empty();

  @override
  Future<void> openSettings(LocationAccess access) async =>
      openedSettings.add(access);
}

const _user = DeviceLocation(
  latitude: 9.9350,
  longitude: -84.0800,
  accuracyMeters: 12,
);

Future<void> _pump(
  WidgetTester tester, {
  required _FakeLocationService location,
  required _FakeMap map,
  FakeOperations? operations,
  Map<String, WidgetBuilder>? routes,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: PassengerHomeScreen(
        locationService: location,
        mapBuilder: map.builder,
        operations: operations ?? FakeOperations(),
      ),
      routes:
          routes ??
          {
            '/passenger/search': (_) =>
                const Scaffold(body: Text('search-screen')),
            '/passenger/buses': (_) =>
                const Scaffold(body: Text('buses-screen')),
            '/passenger/favorites': (_) =>
                const Scaffold(body: Text('favorites-screen')),
          },
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    // The star of the route panel: no network.
    FavoritesController.shared = FavoritesController(
      service: FakeFavoritesService(),
    );
    FlutterSecureStorage.setMockInitialValues({
      'sb_user': jsonEncode({
        'id': '01a0c691-579f-731c-a034-03cc8fe8136f',
        'name': 'Keyna Castro',
        'email': 'user@passenger.com',
        'roles': [
          {'value': 'passenger', 'label': 'Pasajero'},
        ],
      }),
    });
  });

  testWidgets('AC1 · shows the map with search bar, chips, greeting and nav', (
    tester,
  ) async {
    await _pump(
      tester,
      location: _FakeLocationService(
        access: LocationAccess.granted,
        location: _user,
      ),
      map: _FakeMap(),
    );

    expect(find.byKey(const Key('fake-map')), findsOneWidget);
    expect(find.text('¿A dónde vas?'), findsOneWidget);
    expect(find.text('Paradas cercanas'), findsOneWidget);
    expect(find.text('Buses en curso'), findsOneWidget);
    expect(find.text('Mis viajes'), findsOneWidget); // bottom nav tab
    expect(find.text('Favoritos'), findsOneWidget);
    expect(find.text('Hola, Keyna'), findsOneWidget);
    expect(find.byKey(const Key('my-location-button')), findsOneWidget);
    expect(find.text(MapConfig.streetsAttribution), findsOneWidget);
    expect(find.byKey(const Key('map-mode-button')), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
  });

  testWidgets('AC2 · centers on the user and shows the location marker', (
    tester,
  ) async {
    final map = _FakeMap();
    await _pump(
      tester,
      location: _FakeLocationService(
        access: LocationAccess.granted,
        location: _user,
      ),
      map: map,
    );

    expect(map.userLocations.last.latitude, _user.latitude);
    expect(map.moves.last, (
      lat: _user.latitude,
      lng: _user.longitude,
      zoom: MapConfig.userZoom,
    ));
    expect(find.byKey(const Key('location-access-banner')), findsNothing);

    // The user pans away and taps "my location": the map comes back.
    map.moves.clear();
    await tester.tap(find.byKey(const Key('my-location-button')));
    await tester.pump();
    expect(map.moves.single, (
      lat: _user.latitude,
      lng: _user.longitude,
      zoom: MapConfig.userZoom,
    ));
  });

  testWidgets('AC3 · permission denied: notice, no marker, asks again on tap', (
    tester,
  ) async {
    final map = _FakeMap();
    final location = _FakeLocationService(access: LocationAccess.denied);
    await _pump(tester, location: location, map: map);

    expect(find.byKey(const Key('location-access-banner')), findsOneWidget);
    expect(find.text('Permitir'), findsOneWidget);
    expect(map.userLocations, isEmpty);
    expect(map.moves, isEmpty); // stays on the San José fallback camera

    // The user accepts the permission when asked again.
    location
      ..access = LocationAccess.granted
      ..location = _user;
    await tester.tap(find.byKey(const Key('my-location-button')));
    await tester.pumpAndSettle();

    expect(location.accessChecks, [true, true]);
    expect(find.byKey(const Key('location-access-banner')), findsNothing);
    expect(map.userLocations.single.latitude, _user.latitude);
  });

  testWidgets('AC3 · location off: the notice opens the location settings', (
    tester,
  ) async {
    final location = _FakeLocationService(
      access: LocationAccess.serviceDisabled,
    );
    await _pump(tester, location: location, map: _FakeMap());

    expect(
      find.textContaining('Tu ubicación está desactivada'),
      findsOneWidget,
    );
    await tester.tap(find.text('Activar'));
    await tester.pump();

    expect(location.openedSettings, [LocationAccess.serviceDisabled]);
  });

  testWidgets('AC3 · denied forever: "my location" opens the app settings', (
    tester,
  ) async {
    final location = _FakeLocationService(access: LocationAccess.deniedForever);
    await _pump(tester, location: location, map: _FakeMap());

    await tester.tap(find.byKey(const Key('my-location-button')));
    await tester.pump();

    expect(location.openedSettings, [LocationAccess.deniedForever]);
  });

  testWidgets('AC5 · typing in the search bar shows "próximamente" in place', (
    tester,
  ) async {
    await _pump(
      tester,
      location: _FakeLocationService(
        access: LocationAccess.granted,
        location: _user,
      ),
      map: _FakeMap(),
    );

    // Tapping the field opens the results panel instead of the chips.
    await tester.tap(find.byKey(const Key('map-search-field')));
    await tester.pump();
    expect(find.text('Búsqueda de rutas: próximamente'), findsOneWidget);
    expect(find.text('Escribe una ruta, parada o destino.'), findsOneWidget);
    expect(find.text('Paradas cercanas'), findsNothing);

    // The panel follows what the user types.
    await tester.enterText(
      find.byKey(const Key('map-search-field')),
      'Heredia',
    );
    await tester.pump();
    expect(
      find.text('Pronto verás aquí las rutas para "Heredia".'),
      findsOneWidget,
    );

    // It never navigates to another screen.
    expect(find.text('search-screen'), findsNothing);

    // The back arrow closes the search and brings the chips back.
    await tester.tap(find.byKey(const Key('map-search-close')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('map-search-results')), findsNothing);
    expect(find.text('Paradas cercanas'), findsOneWidget);
  });

  testWidgets('AC5 · the clear button empties the search', (tester) async {
    await _pump(
      tester,
      location: _FakeLocationService(
        access: LocationAccess.granted,
        location: _user,
      ),
      map: _FakeMap(),
    );

    await tester.enterText(
      find.byKey(const Key('map-search-field')),
      'Cartago',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('map-search-clear')));
    await tester.pump();

    expect(find.text('Escribe una ruta, parada o destino.'), findsOneWidget);
  });

  testWidgets('Satellite · the layers button switches streets <-> satellite', (
    tester,
  ) async {
    final map = _FakeMap();
    await _pump(
      tester,
      location: _FakeLocationService(
        access: LocationAccess.granted,
        location: _user,
      ),
      map: map,
    );
    expect(map.mode, MapMode.streets);

    await tester.tap(find.byKey(const Key('map-mode-button')));
    await tester.pump();
    expect(map.mode, MapMode.satellite);
    expect(find.text(MapConfig.satelliteAttribution), findsOneWidget);

    await tester.tap(find.byKey(const Key('map-mode-button')));
    await tester.pump();
    expect(map.mode, MapMode.streets);
    expect(find.text(MapConfig.streetsAttribution), findsOneWidget);
  });

  testWidgets('AC5 · a quick-access chip shows "próximamente"', (tester) async {
    await _pump(
      tester,
      location: _FakeLocationService(
        access: LocationAccess.granted,
        location: _user,
      ),
      map: _FakeMap(),
    );

    await tester.tap(find.text('Paradas cercanas'));
    await tester.pump();

    expect(find.text('Paradas cercanas: próximamente.'), findsOneWidget);
  });

  testWidgets('Favorites AC1 · "Favoritos" chip opens "Mis favoritos"', (
    tester,
  ) async {
    await _pump(
      tester,
      location: _FakeLocationService(
        access: LocationAccess.granted,
        location: _user,
      ),
      map: _FakeMap(),
    );

    await tester.tap(find.text('Favoritos'));
    await tester.pumpAndSettle();

    expect(find.text('favorites-screen'), findsOneWidget);
  });

  testWidgets('"Buses en curso" chip opens the list of routes with buses', (
    tester,
  ) async {
    await _pump(
      tester,
      location: _FakeLocationService(
        access: LocationAccess.granted,
        location: _user,
      ),
      map: _FakeMap(),
    );

    await tester.tap(
      find.descendant(
        of: find.byType(MapQuickChips),
        matching: find.text('Buses en curso'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('buses-screen'), findsOneWidget);
  });

  testWidgets('AC6 · dark mode keeps the light streets map (with places)', (
    tester,
  ) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

    final map = _FakeMap();
    await _pump(
      tester,
      location: _FakeLocationService(
        access: LocationAccess.granted,
        location: _user,
      ),
      map: map,
    );

    expect(map.mode, MapMode.streets);
    expect(MapConfig.styleFor(MapMode.streets), MapConfig.styleUrl);
  });

  testWidgets('Attribution · always visible, small and without background', (
    tester,
  ) async {
    await _pump(
      tester,
      location: _FakeLocationService(
        access: LocationAccess.granted,
        location: _user,
      ),
      map: _FakeMap(),
    );

    // Still visible after a while (it never hides).
    await tester.pump(const Duration(seconds: 10));
    final attribution = tester.widget<Text>(
      find.byKey(const Key('map-attribution')),
    );
    expect(attribution.data, MapConfig.streetsAttribution);
    expect(attribution.style!.fontSize, lessThanOrEqualTo(8));
    expect(
      find.ancestor(
        of: find.byKey(const Key('map-attribution')),
        matching: find.byType(DecoratedBox),
      ),
      findsNothing,
    );
  });

  testWidgets('Layout · map buttons on the right edge, above the attribution', (
    tester,
  ) async {
    await _pump(
      tester,
      location: _FakeLocationService(
        access: LocationAccess.granted,
        location: _user,
      ),
      map: _FakeMap(),
    );

    final screenWidth = tester.getSize(find.byType(Scaffold)).width;
    final myLocation = tester.getRect(
      find.byKey(const Key('my-location-button')),
    );
    final mapMode = tester.getRect(find.byKey(const Key('map-mode-button')));
    final attribution = tester.getRect(
      find.byKey(const Key('map-attribution')),
    );

    // Against the right edge (16 px margin).
    expect(myLocation.right, closeTo(screenWidth - 16, 0.5));
    expect(mapMode.center.dx, closeTo(myLocation.center.dx, 0.5));

    // On their own, above the license text (no overlap).
    expect(myLocation.bottom, lessThanOrEqualTo(attribution.top));
    expect(mapMode.bottom, lessThanOrEqualTo(myLocation.top));
  });

  for (final brightness in Brightness.values) {
    testWidgets(
      'Design · green passenger cards with the phone in ${brightness.name} mode',
      (tester) async {
        tester.platformDispatcher.platformBrightnessTestValue = brightness;
        addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

        final map = _FakeMap();
        await _pump(
          tester,
          location: _FakeLocationService(
            access: LocationAccess.granted,
            location: _user,
          ),
          map: map,
        );

        // Light map in both cases...
        expect(map.mode, MapMode.streets);

        // ...a white search bar...
        final searchBar = tester.widget<Container>(
          find
              .ancestor(
                of: find.byKey(const Key('map-search-field')),
                matching: find.byType(Container),
              )
              .first,
        );
        final decoration = searchBar.decoration! as BoxDecoration;
        expect(decoration.color, SmartBusColors.blanco);
        expect(decoration.gradient, isNull);

        // ...and the passenger header green on the map buttons.
        final myLocation = tester.widget<FloatingActionButton>(
          find.byKey(const Key('my-location-button')),
        );
        expect(myLocation.backgroundColor, SmartBusColors.verdePasajero);

        // ...except the bottom sheet ("Hola, <nombre>"), which is white.
        final sheet = tester.widget<Material>(
          find
              .ancestor(
                of: find.text('Hola, Keyna'),
                matching: find.byType(Material),
              )
              .first,
        );
        expect(sheet.color, MapOverlayColors.sheet.surface);
      },
    );
  }

  group('Route visualization', _routeVisualizationTests);
  group('Live buses on the route', () {
    setUp(() {
      final view =
          TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
      view.physicalSize = const Size(1236, 2745);
      view.devicePixelRatio = 3;
    });
    tearDown(() {
      TestWidgetsFlutterBinding.instance.platformDispatcher.views.first
        ..resetPhysicalSize()
        ..resetDevicePixelRatio();
    });
    _liveBusesTests();
  });

  test('AC7 · providers without API keys (OpenFreeMap + Esri imagery)', () {
    expect(MapConfig.styleUrl, 'https://tiles.openfreemap.org/styles/liberty');
    expect(MapConfig.styleUrl.contains('key='), isFalse);

    // Satellite: Esri World Imagery (development only), high resolution.
    expect(MapConfig.satelliteTilesUrl, contains('World_Imagery'));
    expect(MapConfig.satelliteTilesUrl.contains('token='), isFalse);
    expect(MapConfig.satelliteMaxZoom, greaterThanOrEqualTo(18));
    expect(MapConfig.satelliteAttribution, contains('Esri'));

    final style = jsonDecode(MapConfig.styleFor(MapMode.satellite)) as Map;
    expect(style['version'], 8);
    expect(style['sources']['satellite']['type'], 'raster');
    expect(style['sources']['satellite']['tiles'], [
      MapConfig.satelliteTilesUrl,
    ]);
    expect(
      style['sources']['satellite']['maxzoom'],
      MapConfig.satelliteMaxZoom,
    );
    // Fonts for the stop numbers on the satellite map too.
    expect(style['glyphs'], MapConfig.glyphsUrl);
  });
}

// ---------------------------------------------------------------------------
// Route visualization
// ---------------------------------------------------------------------------

/// A point [meters] north of the passenger (1° of latitude ≈ 111.2 km).
double _north(double meters) => _user.latitude + meters / 111195;

final _rfStops = [
  stopAt('Terminal', _north(600), _user.longitude, seq: 1, minutes: 0),
  stopAt('Centro', _north(200), _user.longitude, seq: 2, minutes: 12),
  stopAt('Río Frío', _north(9000), _user.longitude, seq: 3),
];

/// PV-RF: two directions without geometry; "Hacia Río Frío" has the stop
/// closest to the passenger (200 m), but it is the second pattern.
final _pvRf = route(
  'r-pvrf',
  code: 'PV-RF',
  name: 'Puerto Viejo - Río Frío',
  patterns: [
    pattern(
      'p-pv',
      headsign: 'Puerto Viejo',
      stops: [
        stopAt('Río Frío', _north(9000), _user.longitude, seq: 1),
        stopAt('Escuela', _north(800), _user.longitude, seq: 2),
      ],
    ),
    pattern('p-rf', headsign: 'Río Frío', stops: _rfStops),
  ],
);

/// DEMO-CITY: one direction with real geometry; nearest stop at 450 m.
final _demo = route(
  'r-demo',
  code: 'DEMO-CITY',
  name: 'Demo City',
  patterns: [
    pattern(
      'p-demo',
      headsign: 'Demo Destination',
      stops: [
        stopAt('Demo Terminal', _north(450), _user.longitude, seq: 1),
        stopAt('Demo Plaza', _north(900), _user.longitude + 0.003, seq: 2),
      ],
      geometry: [
        GeoPoint(_north(450), _user.longitude),
        GeoPoint(_north(700), _user.longitude + 0.002),
        GeoPoint(_north(900), _user.longitude + 0.003),
      ],
    ),
  ],
);

/// SJ-PV: far away (5 km).
final _sjPv = route(
  'r-sjpv',
  code: 'SJ-PV',
  name: 'San José - Puerto Viejo',
  patterns: [
    pattern(
      'p-sj',
      headsign: 'San José',
      stops: [stopAt('Lejana', _north(5000), _user.longitude, seq: 1)],
    ),
  ],
);

_FakeLocationService _granted() =>
    _FakeLocationService(access: LocationAccess.granted, location: _user);

Finder _inList(String text) => find.descendant(
  of: find.byKey(const Key('routes-section')),
  matching: find.textContaining(text),
);

Future<void> _tapRoute(WidgetTester tester, TransitRoute route) =>
    _tapInSheet(tester, find.byKey(Key('route-tile-${route.id}')));

/// Scrolls the bottom sheet to [finder] and taps it.
Future<void> _tapInSheet(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

/// Top of the bottom sheet card.
double _sheetTop(WidgetTester tester) =>
    tester.getTopLeft(find.byType(MapBottomSheetContent)).dy;

void _routeVisualizationTests() {
  // A phone-sized screen (412 x 915), so the sheet shows a few routes.
  setUp(() {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.physicalSize = const Size(1236, 2745);
    view.devicePixelRatio = 3;
  });
  tearDown(() {
    TestWidgetsFlutterBinding.instance.platformDispatcher.views.first
      ..resetPhysicalSize()
      ..resetDevicePixelRatio();
  });

  testWidgets('Routes AC1 · nearby routes, closest first, with the stop', (
    tester,
  ) async {
    final operations = FakeOperations(catalogue: [_sjPv, _demo, _pvRf]);
    await _pump(
      tester,
      location: _granted(),
      map: _FakeMap(),
      operations: operations,
    );

    expect(operations.calls, ['routesWithPatterns']); // one request
    expect(find.text('Rutas cercanas'), findsOneWidget);

    // SJ-PV is 5 km away: not listed.
    expect(_inList('SJ-PV'), findsNothing);
    final pvRf = tester.getTopLeft(_inList('Puerto Viejo - Río Frío'));
    final demo = tester.getTopLeft(_inList('Demo City'));
    expect(pvRf.dy, lessThan(demo.dy)); // 200 m before 450 m

    // Direction and closest stop of each route.
    expect(_inList('Hacia Río Frío\nCentro · 200 m'), findsOneWidget);
    expect(
      _inList('Hacia Demo Destination\nDemo Terminal · 450 m'),
      findsOneWidget,
    );
  });

  testWidgets('Routes AC2 · nothing nearby: message and "see all"', (
    tester,
  ) async {
    await _pump(
      tester,
      location: _granted(),
      map: _FakeMap(),
      operations: FakeOperations(catalogue: [_sjPv]),
    );

    expect(find.text('No hay rutas cerca de ti'), findsOneWidget);
    expect(_inList('San José - Puerto Viejo'), findsNothing);

    await _tapInSheet(tester, find.text('Ver todas las rutas'));

    expect(find.text('Todas las rutas'), findsOneWidget);
    expect(_inList('San José - Puerto Viejo'), findsOneWidget);

    // And back to the nearby list.
    await _tapInSheet(tester, find.byKey(const Key('show-nearby-routes')));
    expect(find.text('No hay rutas cerca de ti'), findsOneWidget);
  });

  for (final access in [
    LocationAccess.denied,
    LocationAccess.serviceDisabled,
  ]) {
    testWidgets('Routes AC3 · without location (${access.name}): every route, '
        'no distance, still selectable', (tester) async {
      final map = _FakeMap();
      await _pump(
        tester,
        location: _FakeLocationService(access: access),
        map: map,
        operations: FakeOperations(catalogue: [_demo, _pvRf, _sjPv]),
      );

      expect(find.text('Todas las rutas'), findsOneWidget);
      expect(_inList('Demo City'), findsOneWidget);
      expect(_inList('Puerto Viejo - Río Frío'), findsOneWidget);
      expect(_inList('San José - Puerto Viejo'), findsOneWidget);
      expect(_inList(' m'), findsNothing); // no distances
      expect(_inList('2 direcciones'), findsOneWidget);

      // AC9 · without location the first direction is shown.
      await _tapRoute(tester, _pvRf);
      expect(map.routeCalls, ['p-pv']);
      expect(find.byKey(const Key('selected-route-panel')), findsOneWidget);
    });
  }

  testWidgets('Routes AC4 + AC9 · selecting a route draws its closest '
      'direction, fits the camera and collapses the sheet', (tester) async {
    final map = _FakeMap();
    await _pump(
      tester,
      location: _granted(),
      map: map,
      operations: FakeOperations(catalogue: [_demo, _pvRf]),
    );
    final sheetBefore = _sheetTop(tester);

    await _tapRoute(tester, _pvRf);

    // AC9: "Hacia Río Frío" has the closest stop, so it goes first.
    expect(map.routeCalls, ['p-rf']);
    expect(find.text('Hacia Río Frío'), findsOneWidget);
    expect(find.text('Hacia Puerto Viejo'), findsOneWidget);
    final chip = tester.widget<ChoiceChip>(
      find.byKey(const Key('direction-p-rf')),
    );
    expect(chip.selected, isTrue);

    // Line + every stop, numbered in travel order.
    final features = map.drawn['features'] as List;
    expect(features.first['geometry']['type'], 'LineString');
    final stops = features.where((f) => f['geometry']['type'] == 'Point');
    expect(stops.map((f) => f['properties']['seq']), ['1', '2', '3']);

    // The camera fits the whole pattern, and the passenger (near it) too.
    final fit = map.fits.last;
    expect(fit.points.map((p) => p.latitude), contains(_north(9000)));
    expect(
      fit.points.any(
        (p) => p.latitude == _user.latitude && p.longitude == _user.longitude,
      ),
      isTrue,
    );
    expect(fit.padding.bottom, greaterThan(0));
    expect(fit.padding.top, greaterThan(100)); // below the search bar

    // The user marker is not touched.
    expect(map.userLocations, isNotEmpty);

    // The sheet shrank so the map is visible.
    expect(_sheetTop(tester), greaterThan(sheetBefore));
    expect(find.byKey(const Key('selected-route-panel')), findsOneWidget);
    expect(find.text('Hola, Keyna'), findsNothing);
  });

  testWidgets(
    'Routes AC4 · a far route does not pull the passenger into view',
    (tester) async {
      final map = _FakeMap();
      await _pump(
        tester,
        location: _granted(),
        map: map,
        operations: FakeOperations(catalogue: [_sjPv]),
      );
      await _tapInSheet(tester, find.text('Ver todas las rutas'));
      await _tapRoute(tester, _sjPv);

      expect(map.fits.last.points.map((p) => p.latitude), [
        _north(5000),
        _north(5000),
      ]);
    },
  );

  testWidgets('Routes AC5 · tapping a stop shows its name, order and minutes', (
    tester,
  ) async {
    final map = _FakeMap();
    await _pump(
      tester,
      location: _granted(),
      map: map,
      operations: FakeOperations(catalogue: [_pvRf]),
    );
    await _tapRoute(tester, _pvRf);

    map.onStopTap!(_rfStops[1]);
    await tester.pumpAndSettle();

    final details = find.byKey(const Key('stop-details'));
    expect(
      find.descendant(of: details, matching: find.text('Centro')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: details,
        matching: find.text('Parada 2 de 3 · 12 min desde el inicio'),
      ),
      findsOneWidget,
    );

    // No minutes known: only the order.
    map.onStopTap!(_rfStops[2]);
    await tester.pumpAndSettle();
    expect(find.text('Parada 3 de 3'), findsOneWidget);
  });

  testWidgets('Routes · every stop of the direction is listed as a timeline; '
      'tapping one highlights it and moves the map there', (tester) async {
    final map = _FakeMap();
    await _pump(
      tester,
      location: _granted(),
      map: map,
      operations: FakeOperations(catalogue: [_pvRf]),
    );
    await _tapRoute(tester, _pvRf);

    final timeline = find.byKey(const Key('stops-timeline'));
    await tester.ensureVisible(timeline);
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: timeline, matching: find.text('Paradas (3)')),
      findsOneWidget,
    );
    for (final name in ['Terminal', 'Centro', 'Río Frío']) {
      expect(
        find.descendant(of: timeline, matching: find.text(name)),
        findsOneWidget,
      );
    }
    expect(
      find.descendant(of: timeline, matching: find.text('Salida')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: timeline, matching: find.text('+12 min')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: timeline, matching: find.text('Llegada')),
      findsOneWidget,
    );

    map.moves.clear();
    await _tapInSheet(tester, find.byKey(const Key('timeline-stop-1')));

    expect(map.highlighted, same(_rfStops[1]));
    expect(map.moves.single.lat, _rfStops[1].latitude);
    expect(map.moves.single.zoom, greaterThan(MapConfig.userZoom));
    // The halo is drawn on that marker only.
    final selected = (map.drawn['features'] as List)
        .where((f) => f['properties']['selected'] == true)
        .map((f) => f['id']);
    expect(selected, ['stop-1']);
    expect(find.byKey(const Key('stop-details')), findsOneWidget);

    // A marker tap highlights too (without moving the camera).
    map.moves.clear();
    map.onStopTap!(_rfStops[2]);
    await tester.pumpAndSettle();
    expect(map.highlighted, same(_rfStops[2]));
    expect(map.moves, isEmpty);
  });

  testWidgets('Routes AC6 · switching direction or closing removes the '
      'previous path and stops', (tester) async {
    final map = _FakeMap();
    await _pump(
      tester,
      location: _granted(),
      map: map,
      operations: FakeOperations(catalogue: [_demo, _pvRf]),
    );
    await _tapRoute(tester, _pvRf);
    map.onStopTap!(_rfStops[1]);
    await tester.pumpAndSettle();

    // Other direction: replaces the drawing; the stop details go away.
    await _tapInSheet(tester, find.byKey(const Key('direction-p-pv')));
    expect(map.routeCalls, ['p-rf', 'p-pv']);
    expect(map.route!.id, 'p-pv');
    expect(find.byKey(const Key('stop-details')), findsNothing);

    // Close: nothing drawn, the list is back.
    await _tapInSheet(tester, find.byKey(const Key('close-route')));
    expect(map.routeCalls.last, 'clear');
    expect(map.route, isNull);
    expect(find.text('Rutas cercanas'), findsOneWidget);

    // Another route: only that one is drawn.
    await _tapRoute(tester, _demo);
    expect(map.route!.id, 'p-demo');
  });

  testWidgets('Routes AC6 · Android back closes the shown route first', (
    tester,
  ) async {
    final map = _FakeMap();
    await _pump(
      tester,
      location: _granted(),
      map: map,
      operations: FakeOperations(catalogue: [_pvRf]),
    );
    await _tapRoute(tester, _pvRf);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(map.route, isNull);
    expect(find.text('Rutas cercanas'), findsOneWidget);
  });

  testWidgets('Routes AC7 · loading state, then error with retry', (
    tester,
  ) async {
    final gate = Completer<void>();
    final operations = _SlowOperations(gate)
      ..catalogue = [_pvRf]
      ..catalogueError = ApiException.noConnection;
    await tester.pumpWidget(
      MaterialApp(
        home: PassengerHomeScreen(
          locationService: _granted(),
          mapBuilder: _FakeMap().builder,
          operations: operations,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const Key('routes-loading')), findsOneWidget);
    expect(find.text('Buscando rutas…'), findsOneWidget);

    gate.complete();
    await tester.pumpAndSettle();
    expect(find.text('No se pudieron cargar las rutas'), findsOneWidget);
    expect(find.text(ApiException.noConnection.message), findsOneWidget);

    operations.catalogueError = null;
    await _tapInSheet(tester, find.text('Reintentar'));
    expect(_inList('Puerto Viejo - Río Frío'), findsOneWidget);
  });

  testWidgets('Routes AC8 · without geometry the stops are joined in order; '
      'with geometry, the real line', (tester) async {
    final map = _FakeMap();
    await _pump(
      tester,
      location: _granted(),
      map: map,
      operations: FakeOperations(catalogue: [_demo, _pvRf]),
    );

    await _tapRoute(tester, _pvRf);
    var line = (map.drawn['features'] as List).first;
    expect(line['properties']['approximate'], isTrue);
    expect(line['geometry']['coordinates'], [
      for (final s in _rfStops) [s.longitude, s.latitude],
    ]);
    expect(find.byKey(const Key('approximate-path-note')), findsOneWidget);
    expect(map.fits, isNotEmpty);

    await _tapInSheet(tester, find.byKey(const Key('close-route')));
    await _tapRoute(tester, _demo);
    line = (map.drawn['features'] as List).first;
    expect(line['properties']['approximate'], isFalse);
    expect((line['geometry']['coordinates'] as List).length, 3);
    expect(find.byKey(const Key('approximate-path-note')), findsNothing);
  });

  testWidgets('"Buses en curso" → "Ver ruta" draws that route and direction', (
    tester,
  ) async {
    final map = _FakeMap();
    await _pump(
      tester,
      location: _granted(),
      map: map,
      operations: FakeOperations(catalogue: [_demo, _pvRf]),
      routes: {
        '/passenger/buses': (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.pop(
              context,
              RouteSelection(route: _pvRf, pattern: _pvRf.patterns.first),
            ),
            child: const Text('ver-ruta'),
          ),
        ),
      },
    );

    // The chips row scrolls sideways on a narrow phone.
    await _tapInSheet(
      tester,
      find.descendant(
        of: find.byType(MapQuickChips),
        matching: find.text('Buses en curso'),
      ),
    );
    await tester.tap(find.text('ver-ruta'));
    await tester.pumpAndSettle();

    // The picked direction, not the closest one.
    expect(map.routeCalls, ['p-pv']);
    expect(find.byKey(const Key('selected-route-panel')), findsOneWidget);
    final chip = tester.widget<ChoiceChip>(
      find.byKey(const Key('direction-p-pv')),
    );
    expect(chip.selected, isTrue);
  });
}

// ---------------------------------------------------------------------------
// Live buses on the selected route
// ---------------------------------------------------------------------------

LiveBusTrip _liveTrip(String id, String pattern, {String unit = '12'}) =>
    LiveBusTrip(
      id: id,
      status: TripStatus.inProgress,
      routePatternId: pattern,
      busUnit: unit,
      busPlate: 'ABC-$unit',
    );

/// Home with PV-RF, a bus running towards Río Frío (t-rf) and one towards
/// Puerto Viejo (t-pv). Returns the opened tracking trip ids.
Future<List<Object?>> _pumpWithBuses(
  WidgetTester tester,
  _FakeMap map, {
  Map<String, TripTracking>? positions,
}) async {
  final operations = FakeOperations(
    catalogue: [_pvRf],
    buses: {
      'p-rf': [_liveTrip('t-rf', 'p-rf')],
      'p-pv': [_liveTrip('t-pv', 'p-pv', unit: '7')],
    },
  );
  final gps = FakeGps(
    positions ??
        {
          't-rf': inProgressAt('t-rf', _north(300), _user.longitude),
          't-pv': inProgressAt('t-pv', _north(4000), _user.longitude),
        },
  );
  final opened = <Object?>[];
  await tester.pumpWidget(
    MaterialApp(
      home: PassengerHomeScreen(
        locationService: _granted(),
        mapBuilder: map.builder,
        operations: operations,
        liveBusesFactory: (patternId) => RouteLiveBuses(
          patternId: patternId,
          operations: operations,
          trackerFactory: FakeTrackers(gps).call,
        ),
      ),
      onGenerateRoute: (settings) {
        opened.add(settings.arguments);
        return MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('tracking-screen')),
        );
      },
    ),
  );
  await tester.pumpAndSettle();
  return opened;
}

void _liveBusesTests() {
  testWidgets('Live · the buses running on the direction appear on the map '
      'and in the panel', (tester) async {
    final map = _FakeMap();
    await _pumpWithBuses(tester, map);

    await _tapRoute(tester, _pvRf);

    // Only the bus of the shown direction (Río Frío), at its position.
    final pin = map.buses.single;
    expect(pin.id, 't-rf');
    expect(pin.latitude, _north(300));
    expect(pin.live, isTrue);

    final row = find.byKey(const Key('live-bus-t-rf'));
    expect(row, findsOneWidget);
    expect(
      find.descendant(of: row, matching: find.text('Unidad 12 · ABC-12')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: row, matching: find.textContaining('En vivo')),
      findsOneWidget,
    );
  });

  testWidgets('Live · switching direction shows that direction\'s buses; '
      'closing removes them', (tester) async {
    final map = _FakeMap();
    await _pumpWithBuses(tester, map);
    await _tapRoute(tester, _pvRf);

    await _tapInSheet(tester, find.byKey(const Key('direction-p-pv')));
    expect(map.buses.single.id, 't-pv');
    expect(find.byKey(const Key('live-bus-t-rf')), findsNothing);
    expect(find.byKey(const Key('live-bus-t-pv')), findsOneWidget);

    await _tapInSheet(tester, find.byKey(const Key('close-route')));
    expect(map.buses, isEmpty);
  });

  testWidgets('Live · no bus running: says so', (tester) async {
    final map = _FakeMap();
    await _pump(
      tester,
      location: _granted(),
      map: map,
      operations: FakeOperations(catalogue: [_pvRf]),
    );
    await _tapRoute(tester, _pvRf);

    expect(find.text('No hay buses en curso en este sentido.'), findsOneWidget);
    expect(map.buses, isEmpty);
  });

  testWidgets('Live · "Ver en vivo" and a tap on the pin open the tracking', (
    tester,
  ) async {
    final map = _FakeMap();
    final opened = await _pumpWithBuses(tester, map);
    await _tapRoute(tester, _pvRf);

    await _tapInSheet(tester, find.byKey(const Key('live-bus-t-rf')));
    expect(find.text('tracking-screen'), findsOneWidget);
    expect(opened.last, 't-rf');

    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pumpAndSettle();
    expect(find.text('tracking-screen'), findsNothing);

    map.onBusTap!('t-rf');
    await tester.pumpAndSettle();
    expect(find.text('tracking-screen'), findsOneWidget);
    expect(opened.last, 't-rf');
  });

  testWidgets('Live · an old position is drawn gray, as weak signal', (
    tester,
  ) async {
    final map = _FakeMap();
    await _pumpWithBuses(
      tester,
      map,
      positions: {
        't-rf': inProgressAt(
          't-rf',
          _north(300),
          _user.longitude,
          ageSeconds: 120,
        ),
      },
    );
    await _tapRoute(tester, _pvRf);

    expect(map.buses.single.live, isFalse);
    expect(find.textContaining('Señal débil · hace 2 min'), findsOneWidget);
  });
}

/// Answers `routesWithPatterns` only after [gate] completes.
class _SlowOperations extends FakeOperations {
  _SlowOperations(this.gate);

  final Completer<void> gate;

  @override
  Future<List<TransitRoute>> routesWithPatterns() async {
    await gate.future;
    return super.routesWithPatterns();
  }
}
