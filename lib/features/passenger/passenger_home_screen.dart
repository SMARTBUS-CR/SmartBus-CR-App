import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/config/map_config.dart';
import '../../core/location/location_service.dart';
import '../../core/network/api_exception.dart';
import '../../core/storage/secure_session_store.dart';
import '../../widgets/passenger_bottom_nav.dart';
import '../auth/models/auth_user.dart';
import '../operations/models/operations_models.dart';
import '../operations/services/nearby_routes_filter.dart';
import '../operations/services/operations_service.dart';
import '../trip_tracking/models/trip_tracking.dart';
import '../trip_tracking/services/route_live_buses.dart';
import 'map/map_overlay.dart';
import 'map/passenger_map.dart';
import 'map/route_sheet.dart';

/// Builds the follower of the buses running on a pattern (tests plug in fakes).
typedef RouteLiveBusesFactory = RouteLiveBuses Function(String patternId);

/// Passenger home: full-screen map (MapLibre + OpenFreeMap) with a floating
/// search bar, quick-access chips, "my location" button and a bottom sheet.
///
/// The bottom sheet lists the routes near the passenger (stops within
/// [NearbyRoutesFilter.defaultRadiusMeters]), or every route without location.
/// Picking one draws its line and stops on the map ([PassengerMapHandle.showRoute])
/// and the buses running on that direction, in real time
/// ([PassengerMapHandle.showBuses], [RouteLiveBuses]).
class PassengerHomeScreen extends StatefulWidget {
  const PassengerHomeScreen({
    super.key,
    this.locationService = const LocationService(),
    this.mapBuilder = buildMapLibrePassengerMap,
    this.sessionStore,
    this.operations,
    this.routesFilter = const NearbyRoutesFilter(),
    this.liveBusesFactory,
    this.clock = DateTime.now,
  });

  /// Buses of the selected direction; by default [RouteLiveBuses] with the
  /// real GPS trackers.
  final RouteLiveBusesFactory? liveBusesFactory;

  /// "Now" for how fresh each bus position is (same clock as the trackers).
  final DateTime Function() clock;

  final LocationService locationService;

  /// Builds the map; tests replace the native MapLibre map with a fake.
  final PassengerMapBuilder mapBuilder;

  final SecureSessionStore? sessionStore;

  /// Routes catalogue (Dashboard through the Gateway); tests pass a fake.
  final OperationsService? operations;

  final NearbyRoutesFilter routesFilter;

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

  /// With a route selected the sheet shrinks to this, so the map is visible.
  static const _sheetRoute = 0.32;
  static const _sheetInitial = 0.36;
  static const _sheetMax = 0.6;

  /// Zoom when a stop of the list is tapped (street level).
  static const _stopZoom = 16.5;

  /// Space taken by the search bar + chips over the map (below the status bar).
  static const _topOverlayHeight = 132.0;

  late final OperationsService _operations =
      widget.operations ?? OperationsService();
  final DraggableScrollableController _sheetController =
      DraggableScrollableController();

  PassengerMapHandle? _map;
  LocationAccess? _access;
  DeviceLocation? _location;
  StreamSubscription<DeviceLocation>? _locationSub;
  String? _firstName;
  double _sheetExtent = _sheetInitial;
  MapMode _mapMode = MapMode.streets;

  /// Every route with its patterns; `null` until loaded.
  List<TransitRoute>? _routes;
  bool _routesLoading = false;
  String? _routesError;

  /// "Ver todas las rutas" was tapped (only matters with a known location).
  bool _showAllRoutes = false;

  /// The route drawn on the map, the shown direction and the tapped stop.
  TransitRoute? _selectedRoute;
  RoutePattern? _selectedPattern;
  PatternStop? _tappedStop;

  /// Buses running on [_selectedPattern] (`null` without a selection).
  RouteLiveBuses? _liveBuses;

  /// Redraws "hace N s" / live → weak signal while buses are shown.
  Timer? _freshnessTicker;

  /// Last known height of the screen body (for the camera padding).
  double _bodyHeight = 0;

  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  /// Center on the user only the first time a position arrives.
  bool _centeredOnUser = false;

  /// The search panel is open while the field is focused or has text.
  bool get _searching =>
      _searchFocus.hasFocus || _searchController.text.isNotEmpty;

  bool get _hasLocation =>
      _access == LocationAccess.granted && _location != null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _searchFocus.addListener(_onSearchChanged);
    _searchController.addListener(_onSearchChanged);
    _loadUserName();
    _initLocation(request: true);
    _loadRoutes();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _locationSub?.cancel();
    _stopLiveBuses();
    _searchController.dispose();
    _searchFocus.dispose();
    _sheetController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    if (mounted) setState(() {});
  }

  void _closeSearch() {
    _searchController.clear();
    _searchFocus.unfocus();
  }

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

  // --- Location -------------------------------------------------------------------

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
    // With a route on screen the camera belongs to the route.
    if (!_centeredOnUser && _selectedRoute == null) _centerOn(map, location);
  }

  void _onMapReady(PassengerMapHandle map) {
    _map = map;
    final location = _location;
    if (location != null) map.showUserLocation(location);
    if (_selectedPattern != null) {
      _drawSelection();
    } else if (location != null) {
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

  // --- Routes ---------------------------------------------------------------------

  Future<void> _loadRoutes() async {
    setState(() {
      _routesLoading = true;
      _routesError = null;
    });
    try {
      final routes = await _operations.routesWithPatterns();
      if (!mounted) return;
      setState(() => _routes = routes);
    } on ApiException catch (e) {
      if (mounted) setState(() => _routesError = e.message);
    } finally {
      if (mounted) setState(() => _routesLoading = false);
    }
  }

  RouteListMode get _listMode => _hasLocation && !_showAllRoutes
      ? RouteListMode.nearby
      : RouteListMode.all;

  /// What the routes list shows, from the loaded routes and the location.
  List<RouteListEntry>? _entries() {
    final routes = _routes;
    if (routes == null) return null;
    final location = _location;
    if (!_hasLocation || location == null) {
      return [for (final route in routes) RouteListEntry(route)];
    }
    if (_listMode == RouteListMode.nearby) {
      return [
        for (final nearby in widget.routesFilter.apply(
          latitude: location.latitude,
          longitude: location.longitude,
          routes: routes,
        ))
          RouteListEntry(nearby.route, nearest: nearby),
      ];
    }
    // Every route (catalogue order), with its closest stop for reference.
    return [
      for (final route in routes)
        RouteListEntry(
          route,
          nearest: NearbyRoutesFilter.closest(
            route,
            latitude: location.latitude,
            longitude: location.longitude,
          ),
        ),
    ];
  }

  /// Draws [route] on the map. The direction shown first is [pattern], or the
  /// one with the stop closest to the passenger, or the first one.
  void _selectRoute(TransitRoute route, {RoutePattern? pattern}) {
    final location = _location;
    final nearest = _hasLocation && location != null
        ? NearbyRoutesFilter.closest(
            route,
            latitude: location.latitude,
            longitude: location.longitude,
          )
        : null;
    setState(() {
      _selectedRoute = route;
      _selectedPattern =
          pattern ??
          nearest?.pattern ??
          (route.patterns.isEmpty ? null : route.patterns.first);
      _tappedStop = null;
    });
    _drawSelection();
    _collapseSheet(_sheetRoute);
  }

  void _selectPattern(RoutePattern pattern) {
    if (pattern.id == _selectedPattern?.id) return;
    setState(() {
      _selectedPattern = pattern;
      _tappedStop = null;
    });
    _drawSelection();
  }

  void _clearSelection() {
    setState(() {
      _selectedRoute = null;
      _selectedPattern = null;
      _tappedStop = null;
    });
    _map?.clearRoute();
    _stopLiveBuses();
    _collapseSheet(_sheetInitial);
  }

  /// A stop marker was tapped on the map: details + halo on it.
  void _onStopTap(PatternStop stop) {
    if (_selectedPattern == null) return;
    setState(() => _tappedStop = stop);
    _map?.highlightStop(stop);
  }

  /// A stop of the list was tapped: same as the marker, and the map goes to it.
  void _onStopSelected(PatternStop stop) {
    _onStopTap(stop);
    final location = stop.location;
    if (location == null) return;
    _map?.moveTo(location.latitude, location.longitude, zoom: _stopZoom);
  }

  // --- Live buses of the selected direction --------------------------------------

  /// Follows the buses running on [pattern] (replacing the previous ones).
  void _startLiveBuses(RoutePattern pattern) {
    if (_liveBuses?.patternId == pattern.id) return;
    _stopLiveBuses();
    final live =
        widget.liveBusesFactory?.call(pattern.id) ??
        RouteLiveBuses(patternId: pattern.id, operations: _operations);
    _liveBuses = live;
    live.state.addListener(_onLiveBuses);
    _freshnessTicker = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _onLiveBuses(),
    );
    unawaited(live.start());
  }

  void _stopLiveBuses() {
    _freshnessTicker?.cancel();
    _freshnessTicker = null;
    final live = _liveBuses;
    _liveBuses = null;
    if (live == null) return;
    live.state.removeListener(_onLiveBuses);
    live.dispose();
    _map?.showBuses(const []);
  }

  void _onLiveBuses() {
    if (!mounted) return;
    setState(() {});
    _drawBuses();
  }

  /// One pin per bus with a known position; gray when it is not live.
  void _drawBuses() {
    final live = _liveBuses;
    final map = _map;
    if (live == null || map == null) return;
    final now = widget.clock();
    map.showBuses([
      for (final bus in live.state.value.buses)
        if (bus.state.position case final position?)
          BusMarker(
            id: bus.trip.id,
            latitude: position.latitude,
            longitude: position.longitude,
            live: bus.state.freshnessAt(now) == TrackingFreshness.live,
          ),
    ]);
  }

  /// "Ver en vivo" (list) or a tap on a bus pin: "Rastreando tu bus".
  void _openLiveTracking(String tripId) =>
      Navigator.pushNamed(context, '/passenger/tracking', arguments: tripId);

  /// Draws the selected pattern (or clears the map when there is none) and
  /// fits the camera to it.
  void _drawSelection() {
    final map = _map;
    final pattern = _selectedPattern;
    if (pattern == null) {
      map?.clearRoute();
      _stopLiveBuses();
      return;
    }
    _startLiveBuses(pattern);
    if (map == null) return;
    map.showRoute(pattern);
    _drawBuses();

    final points = [
      ...pattern.path,
      ...pattern.locatedStops.map((s) => s.location!),
    ];
    if (points.isEmpty) return;
    // Keep the passenger in view when they are near this direction.
    final location = _location;
    if (_hasLocation && location != null) {
      final nearest = NearbyRoutesFilter.closest(
        TransitRoute(id: '', code: '', name: '', patterns: [pattern]),
        latitude: location.latitude,
        longitude: location.longitude,
      );
      if (nearest != null &&
          nearest.distanceMeters <= widget.routesFilter.radiusMeters) {
        points.add(GeoPoint(location.latitude, location.longitude));
      }
    }
    map.fitBounds(points, padding: _cameraPadding());
  }

  /// Free space for the route: below the search bar + chips, above the sheet.
  EdgeInsets _cameraPadding() {
    final top = MediaQuery.paddingOf(context).top + _topOverlayHeight;
    final bottom = _bodyHeight * _sheetRoute + 24;
    return EdgeInsets.fromLTRB(40, top, 72, bottom);
  }

  void _collapseSheet(double size) {
    if (!_sheetController.isAttached) return;
    _sheetController.animateTo(
      size,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  // --- Navigation -----------------------------------------------------------------

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

  Future<void> _onChipTap(MapQuickChip chip) async {
    // Route -> buses running now -> live tracking, or "Ver ruta" back here.
    if (chip.label == 'Buses en curso') {
      final result = await Navigator.pushNamed<Object?>(
        context,
        '/passenger/buses',
      );
      if (result is RouteSelection && mounted) _showSelection(result);
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

  /// "Ver ruta" from "Buses en curso": prefer the loaded route (same data as
  /// the list), falling back to the one that came with the selection.
  void _showSelection(RouteSelection selection) {
    final loaded = _routes
        ?.where((route) => route.id == selection.route.id)
        .firstOrNull;
    final route = loaded != null && loaded.patterns.isNotEmpty
        ? loaded
        : selection.route;
    final pattern =
        route.patterns.where((p) => p.id == selection.pattern.id).firstOrNull ??
        selection.pattern;
    _selectRoute(route, pattern: pattern);
  }

  // --- UI ------------------------------------------------------------------------

  List<Widget> _sheetChildren(MapOverlayColors colors) {
    final route = _selectedRoute;
    if (route != null) {
      return [
        SelectedRoutePanel(
          colors: colors,
          route: route,
          pattern: _selectedPattern,
          tappedStop: _tappedStop,
          onPatternSelected: _selectPattern,
          onClose: _clearSelection,
          liveBuses: _liveBuses?.state.value,
          now: widget.clock(),
          onOpenBus: _openLiveTracking,
          onStopSelected: _onStopSelected,
        ),
      ];
    }
    return [
      SheetGreeting(colors: colors, firstName: _firstName),
      const SizedBox(height: 20),
      RoutesSection(
        colors: colors,
        mode: _listMode,
        entries: _entries(),
        loading: _routesLoading,
        error: _routesError,
        canShowNearby: _hasLocation,
        onRetry: _loadRoutes,
        onSelect: (entry) =>
            _selectRoute(entry.route, pattern: entry.nearest?.pattern),
        onShowAll: () => setState(() => _showAllRoutes = true),
        onShowNearby: () => setState(() => _showAllRoutes = false),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    // SmartBus map design: dark cards over a light map, in any phone theme.
    const colors = MapOverlayColors.smartBus;
    final topInset = MediaQuery.paddingOf(context).top;
    final searching = _searching;
    final routeShown = _selectedRoute != null;
    final showBanner =
        !searching && _access != null && _access != LocationAccess.granted;

    // Android "back" closes the search first, then the shown route.
    return PopScope(
      canPop: !searching && !routeShown,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (searching) {
          _closeSearch();
        } else if (routeShown) {
          _clearSelection();
        }
      },
      child: Scaffold(
        bottomNavigationBar: PassengerBottomNav(
          currentIndex: 0,
          onTap: _onTabTap,
        ),
        body: LayoutBuilder(
          builder: (context, constraints) {
            final height = constraints.maxHeight;
            _bodyHeight = height;
            return Stack(
              children: [
                Positioned.fill(
                  child: widget.mapBuilder(
                    context,
                    PassengerMapOptions(
                      mode: _mapMode,
                      onReady: _onMapReady,
                      onStopTap: _onStopTap,
                      onBusTap: _openLiveTracking,
                      // Below the search bar and the chips.
                      compassTopMargin: topInset + 128,
                    ),
                  ),
                ),

                // Search field, chips (or search results) and location notice.
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
                            controller: _searchController,
                            focusNode: _searchFocus,
                            searching: searching,
                            onClose: _closeSearch,
                          ),
                        ),
                        if (searching)
                          MapSearchResults(
                            colors: MapOverlayColors.searchBar,
                            query: _searchController.text,
                          )
                        else
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
                        active: _hasLocation,
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
                    controller: _sheetController,
                    initialChildSize: _sheetInitial,
                    minChildSize: _sheetMin,
                    maxChildSize: _sheetMax,
                    snap: true,
                    snapSizes: const [_sheetRoute, _sheetInitial],
                    builder: (context, scrollController) =>
                        MapBottomSheetContent(
                          colors: MapOverlayColors.sheet,
                          scrollController: scrollController,
                          children: _sheetChildren(MapOverlayColors.sheet),
                        ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
