import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartbus_drivers/core/config/map_config.dart';
import 'package:smartbus_drivers/core/location/location_service.dart';
import 'package:smartbus_drivers/core/theme.dart';
import 'package:smartbus_drivers/features/passenger/map/map_overlay.dart';
import 'package:smartbus_drivers/features/passenger/map/passenger_map.dart';
import 'package:smartbus_drivers/features/passenger/passenger_home_screen.dart';

// ---------------------------------------------------------------------------
// Test doubles: the native MapLibre map cannot run in widget tests.
// ---------------------------------------------------------------------------

class _FakeMap implements PassengerMapHandle {
  final List<({double lat, double lng, double? zoom})> moves = [];
  final List<DeviceLocation> userLocations = [];
  MapMode? mode;

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

  PassengerMapBuilder get builder => (context, options) {
    mode = options.mode;
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
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: PassengerHomeScreen(
        locationService: location,
        mapBuilder: map.builder,
      ),
      routes: {
        '/passenger/search': (_) => const Scaffold(body: Text('search-screen')),
        '/passenger/buses': (_) => const Scaffold(body: Text('buses-screen')),
      },
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
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

    await tester.tap(find.text('Favoritos'));
    await tester.pump();

    expect(find.text('Favoritos: próximamente.'), findsOneWidget);
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
  });
}
