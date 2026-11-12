import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/config/map_config.dart';
import '../../core/location/location_service.dart';
import '../../core/storage/secure_session_store.dart';
import '../../widgets/passenger_bottom_nav.dart';
import '../auth/models/auth_user.dart';
import 'map/map_overlay.dart';
import 'map/passenger_map.dart';

/// Passenger home: full-screen map (MapLibre + OpenFreeMap) with a floating
/// search bar, quick-access chips, "my location" button and a bottom sheet.
///
/// Routes, stops and buses are added on top of this map in later stories.
class PassengerHomeScreen extends StatefulWidget {
  const PassengerHomeScreen({
    super.key,
    this.locationService = const LocationService(),
    this.mapBuilder = buildMapLibrePassengerMap,
    this.sessionStore,
  });

  final LocationService locationService;

  /// Builds the map; tests replace the native MapLibre map with a fake.
  final PassengerMapBuilder mapBuilder;

  final SecureSessionStore? sessionStore;

  @override
  State<PassengerHomeScreen> createState() => _PassengerHomeScreenState();
}

class _PassengerHomeScreenState extends State<PassengerHomeScreen>
    with WidgetsBindingObserver {
  static const _chips = [
    MapQuickChip(Icons.signpost_outlined, 'Paradas cercanas'),
    MapQuickChip(Icons.directions_bus_outlined, 'Buses en curso'),
    MapQuickChip(Icons.star_border, 'Favoritos'),
  ];

  static const _sheetMin = 0.12;
  static const _sheetInitial = 0.2;
  static const _sheetMax = 0.5;

  PassengerMapHandle? _map;
  LocationAccess? _access;
  DeviceLocation? _location;
  StreamSubscription<DeviceLocation>? _locationSub;
  String? _firstName;
  double _sheetExtent = _sheetInitial;
  MapMode _mapMode = MapMode.streets;

  /// Center on the user only the first time a position arrives.
  bool _centeredOnUser = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadUserName();
    _initLocation(request: true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _locationSub?.cancel();
    super.dispose();
  }

  void _openSearch() => Navigator.pushNamed(context, '/passenger/search');

  void _toggleMapMode() {
    setState(
      () => _mapMode = _mapMode == MapMode.streets
          ? MapMode.satellite
          : MapMode.streets,
    );
  }

  /// Coming back from the settings: the user may have enabled the location.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        _access != null &&
        _access != LocationAccess.granted) {
      _initLocation(request: false);
    }
  }

  Future<void> _loadUserName() async {
    final stored = await (widget.sessionStore ?? SecureSessionStore())
        .readUser();
    if (stored == null || !mounted) return;
    final name = AuthUser.fromStorage(stored).name.trim();
    setState(() => _firstName = name.isEmpty ? null : name.split(' ').first);
  }

  Future<void> _initLocation({required bool request}) async {
    final access = await widget.locationService.checkAccess(request: request);
    if (!mounted) return;
    setState(() => _access = access);
    if (access != LocationAccess.granted) return;

    final current = await widget.locationService.currentLocation();
    if (current != null) _onLocation(current);

    await _locationSub?.cancel();
    _locationSub = widget.locationService.watch().listen(_onLocation);
  }

  void _onLocation(DeviceLocation location) {
    if (!mounted) return;
    setState(() => _location = location);
    final map = _map;
    if (map == null) return;
    map.showUserLocation(location);
    if (!_centeredOnUser) _centerOn(map, location);
  }

  void _onMapReady(PassengerMapHandle map) {
    _map = map;
    final location = _location;
    if (location != null) {
      map.showUserLocation(location);
      _centerOn(map, location);
    }
  }

  void _centerOn(PassengerMapHandle map, DeviceLocation location) {
    _centeredOnUser = true;
    map.moveTo(location.latitude, location.longitude, zoom: MapConfig.userZoom);
  }

  Future<void> _onMyLocationPressed() async {
    final location = _location;
    final map = _map;
    if (_access == LocationAccess.granted && location != null) {
      if (map != null) _centerOn(map, location);
      return;
    }
    await _fixLocationAccess();
  }

  /// Asks for the permission again, or opens the settings when it can no
  /// longer be asked (denied forever / location off).
  Future<void> _fixLocationAccess() async {
    final access = _access;
    if (access == LocationAccess.deniedForever ||
        access == LocationAccess.serviceDisabled) {
      await widget.locationService.openSettings(access!);
      return;
    }
    await _initLocation(request: true);
  }

  void _onTabTap(int index) {
    switch (index) {
      case 0:
        return; // already on Home
      case 1:
        Navigator.pushReplacementNamed(context, '/passenger/trips');
        return;
      case 2:
        Navigator.pushReplacementNamed(context, '/passenger/account');
        return;
    }
  }

  void _onChipTap(MapQuickChip chip) {
    // Route -> buses running now -> live tracking.
    if (chip.label == 'Buses en curso') {
      Navigator.pushNamed(context, '/passenger/buses');
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('${chip.label}: próximamente.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    // SmartBus map design: dark cards over a light map, in any phone theme.
    const colors = MapOverlayColors.smartBus;
    final topInset = MediaQuery.paddingOf(context).top;
    final showBanner = _access != null && _access != LocationAccess.granted;

    return Scaffold(
      bottomNavigationBar: PassengerBottomNav(
        currentIndex: 0,
        onTap: _onTabTap,
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final height = constraints.maxHeight;
          return Stack(
            children: [
              Positioned.fill(
                child: widget.mapBuilder(
                  context,
                  PassengerMapOptions(
                    mode: _mapMode,
                    onReady: _onMapReady,
                    // Below the search bar and the chips.
                    compassTopMargin: topInset + 128,
                  ),
                ),
              ),

              // Search bar (opens "Buscar ruta"), chips and location notice.
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: SafeArea(
                  bottom: false,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
                        child: MapSearchBar(
                          colors: MapOverlayColors.searchBar,
                          onTap: _openSearch,
                        ),
                      ),
                      MapQuickChips(
                        chips: _chips,
                        colors: colors,
                        onTap: _onChipTap,
                      ),
                      if (showBanner) ...[
                        const SizedBox(height: 10),
                        LocationAccessBanner(
                          access: _access!,
                          colors: colors,
                          onAction: _fixLocationAccess,
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              // License attribution: its own line, right above the sheet.
              Positioned(
                left: 12,
                right: 12,
                bottom: height * _sheetExtent + 6,
                child: MapAttribution(mode: _mapMode),
              ),

              // Map mode + "my location": against the right edge, above the
              // attribution line (never on top of it).
              Positioned(
                right: 16,
                bottom: height * _sheetExtent + 24,
                child: Column(
                  key: const Key('map-buttons'),
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    MapModeButton(
                      colors: colors,
                      mode: _mapMode,
                      onPressed: _toggleMapMode,
                    ),
                    const SizedBox(height: 10),
                    MyLocationButton(
                      colors: colors,
                      active:
                          _access == LocationAccess.granted &&
                          _location != null,
                      onPressed: _onMyLocationPressed,
                    ),
                  ],
                ),
              ),

              NotificationListener<DraggableScrollableNotification>(
                onNotification: (notification) {
                  setState(() => _sheetExtent = notification.extent);
                  return false;
                },
                child: DraggableScrollableSheet(
                  initialChildSize: _sheetInitial,
                  minChildSize: _sheetMin,
                  maxChildSize: _sheetMax,
                  snap: true,
                  builder: (context, scrollController) => MapBottomSheetContent(
                    colors: MapOverlayColors.sheet,
                    scrollController: scrollController,
                    firstName: _firstName,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
