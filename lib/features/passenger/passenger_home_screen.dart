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
import '../operations/services/nearby_stops.dart';
import '../operations/services/operations_service.dart';
import '../operations/services/route_proximity.dart';
import '../trip_tracking/models/trip_tracking.dart';
import '../trip_tracking/services/route_live_buses.dart';
import 'map/journey_planner_panel.dart';
import 'map/map_overlay.dart';
import 'map/nearby_stops_panel.dart';
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
///
/// **Paradas cercanas** (chip): the stops within
/// [NearbyRoutesFilter.radiusMeters] of the passenger, on the map
/// ([PassengerMapHandle.showNearbyStops]) and in the sheet, with the routes
/// that stop at each one ([nearbyStops], from the catalogue already loaded).
/// Tapping one of those routes draws it.
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
    this.initialSelection,
  });

  /// A route to draw as soon as the screen opens ("Ver ruta" from the
  /// "Favoritos" tab).
  final RouteSelection? initialSelection;

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
    MapQuickChip(Icons.directions_outlined, '¿Cómo llego?'),
    MapQuickChip(Icons.signpost_outlined, 'Paradas cercanas'),
    MapQuickChip(Icons.directions_bus_outlined, 'Buses en curso'),
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

  /// Height of the sheet (0–1). A notifier, not state: dragging the sheet
  /// only moves the buttons above it, it does not rebuild the whole screen
  /// (map included) on every frame.
  final ValueNotifier<double> _sheetExtent = ValueNotifier(_sheetInitial);
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

  /// Today's fare of each route by id (`null` = it has none). Best effort:
  /// a route whose fare failed to load just shows no price.
  final Map<String, RouteFare?> _fares = {};

  /// Weekly departures of each direction by pattern id; a failed request
  /// leaves it out (the panel says the timetable is unavailable).
  final Map<String, List<RouteSchedule>> _schedules = {};

  /// Directions whose timetable is being requested.
  final Set<String> _schedulesLoading = {};

  /// Buses running on [_selectedPattern] (`null` without a selection).
  RouteLiveBuses? _liveBuses;

  /// Redraws "hace N s" / live → weak signal while buses are shown.
  Timer? _freshnessTicker;

  /// Last known height of the screen body (for the camera padding).
  double _bodyHeight = 0;

  /// Center on the user only the first time a position arrives.
  bool _centeredOnUser = false;

  /// "Paradas cercanas" is shown (in the sheet and on the map).
  bool _nearbyMode = false;

  /// The stops near the passenger; `null` until the routes are loaded.
  List<NearbyStop>? _nearbyStops;

  /// The nearby stop tapped (list or map).
  String? _nearbySelectedId;

  bool get _hasLocation =>
      _access == LocationAccess.granted && _location != null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadUserName();
    _initLocation(request: true);
    _loadRoutes();
    final selection = widget.initialSelection;
    if (selection != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showSelection(selection);
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _locationSub?.cancel();
    _stopLiveBuses();
    _sheetController.dispose();
    _sheetExtent.dispose();
    super.dispose();
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
    if (_nearbyMode) _updateNearbyStops();
    final map = _map;
    if (map == null) return;
    map.showUserLocation(location);
    // With a route (or the nearby stops) on screen the camera belongs to it.
    if (!_centeredOnUser &&
        _selectedRoute == null &&
        !_nearbyMode &&
        !_plannerMode) {
      _centerOn(map, location);
    }
  }

  void _onMapReady(PassengerMapHandle map) {
    _map = map;
    final location = _location;
    if (location != null) map.showUserLocation(location);
    if (_destination case final destination?) map.showDestination(destination);
    if (_nearbyMode) {
      _drawNearbyStops(fit: true);
    } else if (_selectedPattern != null) {
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
      unawaited(_loadFares(routes));
      if (_nearbyMode) {
        _updateNearbyStops();
        _drawNearbyStops(fit: true);
      }
      if (_plannerMode) _updatePassing();
    } on ApiException catch (e) {
      if (mounted) setState(() => _routesError = e.message);
    } finally {
      if (mounted) setState(() => _routesLoading = false);
    }
  }

  /// The fare of every route of the list, all at the same time (each request
  /// takes a moment; the service caches them).
  Future<void> _loadFares(List<TransitRoute> routes) async {
    Future<void> fareOf(TransitRoute route) async {
      if (_fares.containsKey(route.id)) return;
      try {
        final fares = await _operations.routeFares(route.id);
        if (mounted) {
          setState(() => _fares[route.id] = fareOn(fares, widget.clock()));
        }
      } on ApiException catch (_) {}
    }

    await Future.wait([for (final route in routes) fareOf(route)]);
  }

  /// The weekly departures of [pattern], once.
  Future<void> _loadSchedules(RoutePattern pattern) async {
    final id = pattern.id;
    if (_schedules.containsKey(id) || _schedulesLoading.contains(id)) return;
    setState(() => _schedulesLoading.add(id));
    try {
      final schedules = await _operations.patternSchedules(id);
      if (mounted) setState(() => _schedules[id] = schedules);
    } on ApiException catch (_) {
      // Shown as "No se pudo cargar el horario."; retried on the next visit.
    } finally {
      if (mounted) setState(() => _schedulesLoading.remove(id));
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
    _closeNearbyStops(recenter: false);
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
    // Usually loaded with the list; not for a route that came from elsewhere.
    unawaited(_loadFares([route]));
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
    // Back to the "¿Cómo llego?" options, with the destination in view.
    if (_plannerMode) _fitPlanner();
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

  /// SnackBar with [message] and "Permitir" / "Ajustes" to turn location on.
  void _askForLocation(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          action: SnackBarAction(
            label:
                _access == LocationAccess.deniedForever ||
                    _access == LocationAccess.serviceDisabled
                ? 'Ajustes'
                : 'Permitir',
            onPressed: _fixLocationAccess,
          ),
        ),
      );
  }

  // --- "¿Cómo llego?" ------------------------------------------------------------

  /// The planner is shown (in the sheet; the destination pin on the map).
  bool _plannerMode = false;

  /// The point the passenger kept a finger on.
  GeoPoint? _destination;

  /// Ways to get there; `null` until loaded (or when it failed).
  List<JourneyOption>? _journeyOptions;
  bool _journeysLoading = false;
  String? _journeysError;

  /// Only the answer to the latest destination is shown.
  int _journeyRequest = 0;

  /// "¿Cómo llego?" chip: explains how to mark the destination (or shows
  /// the one already marked). Needs the location (it is the origin).
  void _openPlanner() {
    if (!_hasLocation) {
      _askForLocation('Activa tu ubicación para saber cómo llegar.');
      return;
    }
    _closeNearbyStops(recenter: false);
    if (_selectedRoute != null) _clearSelection();
    setState(() => _plannerMode = true);
    _fitPlanner();
    _collapseSheet(_sheetInitial);
  }

  /// A finger kept on the map: that point is the destination.
  void _onMapLongPress(GeoPoint point) {
    if (!_hasLocation) {
      _askForLocation('Activa tu ubicación para saber cómo llegar ahí.');
      return;
    }
    _closeNearbyStops(recenter: false);
    if (_selectedRoute != null) _clearSelection();
    setState(() {
      _plannerMode = true;
      _destination = point;
    });
    _updatePassing();
    _map?.showDestination(point);
    _fitPlanner();
    _collapseSheet(_sheetInitial);
    unawaited(_loadJourneys());
  }

  /// Directions whose line passes near the passenger and the destination
  /// (no stop needed), computed on the phone from the loaded catalogue.
  List<PassingRoute> _passing = const [];

  /// How far from the line (the road) the passenger may be.
  static const _passingRadiusMeters = 1000.0;

  void _updatePassing() {
    final routes = _routes;
    final destination = _destination;
    final location = _location;
    if (routes == null || destination == null || location == null) {
      setState(() => _passing = const []);
      return;
    }
    final passing = routesPassingBetween(
      origin: GeoPoint(location.latitude, location.longitude),
      destination: destination,
      routes: routes,
      radiusMeters: _passingRadiusMeters,
    );
    setState(() => _passing = passing);
    // Their timetables, for "Pasa ~10:47" (cached; also used by the panel).
    for (final p in passing) {
      unawaited(_loadSchedules(p.pattern));
    }
  }

  /// [_passing] as the panel shows it, without the directions the Dashboard
  /// already offers (by stops).
  List<PassingOption> _passingOptions() {
    final byStops = {
      for (final o in _journeyOptions ?? const <JourneyOption>[])
        o.journey.patternId,
    };
    final now = widget.clock();
    return [
      for (final p in _passing)
        if (!byStops.contains(p.pattern.id))
          PassingOption(
            passing: p,
            nextPassAt: switch (_schedules[p.pattern.id]) {
              final weekly? => p.nextPassAt(weekly, now),
              null => null,
            },
            timetableLoading: _schedulesLoading.contains(p.pattern.id),
            fare: _fares[p.route.id],
          ),
    ];
  }

  /// "El bus pasa cerca": draws that direction and shows where to wait.
  void _selectPassing(PassingOption option) {
    final p = option.passing;
    _selectRoute(p.route, pattern: p.pattern);
    _map?.moveTo(
      p.origin.point.latitude,
      p.origin.point.longitude,
      zoom: _stopZoom,
    );
  }

  Future<void> _loadJourneys() async {
    final destination = _destination;
    final location = _location;
    if (destination == null || location == null) return;
    final request = ++_journeyRequest;
    setState(() {
      _journeysLoading = true;
      _journeysError = null;
      _journeyOptions = null;
    });
    try {
      final journeys = await _operations.journeys(
        originLatitude: location.latitude,
        originLongitude: location.longitude,
        destinationLatitude: destination.latitude,
        destinationLongitude: destination.longitude,
        walkingRadiusMeters: _walkingRadiusMeters,
        departureAt: widget.clock(),
      );
      if (!mounted || request != _journeyRequest) return;
      setState(() => _journeyOptions = journeyOptions(journeys));
    } on ApiException catch (e) {
      if (mounted && request == _journeyRequest) {
        setState(() => _journeysError = e.message);
      }
    } finally {
      if (mounted && request == _journeyRequest) {
        setState(() => _journeysLoading = false);
      }
    }
  }

  /// How far the passenger may walk to a stop (and from the last one).
  static const _walkingRadiusMeters = 800;

  /// Leaves "¿Cómo llego?": removes the pin and, when [recenter], goes back
  /// to the passenger.
  void _closePlanner({bool recenter = true}) {
    if (!_plannerMode) return;
    _journeyRequest++; // an answer still on its way is ignored
    setState(() {
      _plannerMode = false;
      _destination = null;
      _passing = const [];
      _journeyOptions = null;
      _journeysLoading = false;
      _journeysError = null;
    });
    _map?.showDestination(null);
    final map = _map;
    final location = _location;
    if (recenter && map != null && location != null) _centerOn(map, location);
  }

  /// The passenger and the destination in view.
  void _fitPlanner() {
    final map = _map;
    final destination = _destination;
    final location = _location;
    if (map == null || destination == null) return;
    map.fitBounds([
      destination,
      if (location != null) GeoPoint(location.latitude, location.longitude),
    ], padding: _nearbyPadding());
  }

  /// An option was tapped: draws its direction with the boarding stop
  /// highlighted (the destination pin stays). Closing the route goes back
  /// to the options.
  void _selectJourney(JourneyOption option) {
    final journey = option.journey;
    final route = _routes?.where((r) => r.id == journey.routeId).firstOrNull;
    final pattern = route?.patterns
        .where((p) => p.id == journey.patternId)
        .firstOrNull;
    if (route == null || pattern == null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('No se pudo abrir esa ruta. Inténtalo de nuevo.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      return;
    }
    _selectRoute(route, pattern: pattern);
    final boarding = pattern.stops
        .where((s) => s.stopId == journey.boarding.stopId)
        .firstOrNull;
    if (boarding != null) _onStopTap(boarding);
  }

  // --- Nearby stops ("Paradas cercanas") -----------------------------------------

  /// Shows the stops near the passenger. Without location, offers to turn it
  /// on (the stops depend on where the passenger is).
  void _openNearbyStops() {
    if (!_hasLocation) {
      _askForLocation('Activa tu ubicación para ver las paradas cercanas.');
      return;
    }
    _closePlanner(recenter: false);
    if (_selectedRoute != null) _clearSelection();
    setState(() {
      _nearbyMode = true;
      _nearbySelectedId = null;
    });
    _updateNearbyStops();
    _drawNearbyStops(fit: true);
    _collapseSheet(_sheetInitial);
  }

  /// Leaves "Paradas cercanas": hides the stops and, when [recenter], goes
  /// back to the passenger.
  void _closeNearbyStops({bool recenter = true}) {
    if (!_nearbyMode) return;
    setState(() {
      _nearbyMode = false;
      _nearbyStops = null;
      _nearbySelectedId = null;
    });
    _map?.showNearbyStops(const []);
    final map = _map;
    final location = _location;
    if (recenter && map != null && location != null) _centerOn(map, location);
  }

  /// Recomputes the stops from the loaded routes and the current location.
  void _updateNearbyStops() {
    final routes = _routes;
    final location = _location;
    if (routes == null || location == null) return;
    setState(() {
      _nearbyStops = nearbyStops(
        latitude: location.latitude,
        longitude: location.longitude,
        routes: routes,
        radiusMeters: widget.routesFilter.radiusMeters,
      );
      // Routes whose line (the road) passes near, with or without a stop.
      _passingNear = routesPassingNear(
        latitude: location.latitude,
        longitude: location.longitude,
        routes: routes,
        radiusMeters: widget.routesFilter.radiusMeters,
      );
    });
    _drawNearbyStops();
  }

  /// "Rutas que pasan cerca de ti" (by their line, not their stops).
  List<PassingRoute> _passingNear = const [];

  /// One of them: draws that direction and goes to where it passes closest.
  void _showPassingRoute(PassingRoute passing) {
    _selectRoute(passing.route, pattern: passing.pattern);
    _map?.moveTo(
      passing.origin.point.latitude,
      passing.origin.point.longitude,
      zoom: _stopZoom,
    );
  }

  void _drawNearbyStops({bool fit = false}) {
    final map = _map;
    final stops = _nearbyStops;
    if (map == null || stops == null) return;
    map.showNearbyStops(stops, selectedId: _nearbySelectedId);
    if (!fit || stops.isEmpty) return;
    final location = _location;
    map.fitBounds([
      for (final stop in stops) stop.location,
      if (location != null) GeoPoint(location.latitude, location.longitude),
    ], padding: _nearbyPadding());
  }

  /// Free space for the stops: below the search bar, above the sheet.
  EdgeInsets _nearbyPadding() {
    final top = MediaQuery.paddingOf(context).top + _topOverlayHeight;
    final bottom = _bodyHeight * _sheetInitial + 24;
    return EdgeInsets.fromLTRB(40, top, 72, bottom);
  }

  /// A nearby stop was tapped (list or map): bigger on the map, centered.
  void _selectNearbyStop(String stopId) {
    final stop = _nearbyStops?.where((s) => s.stopId == stopId).firstOrNull;
    if (stop == null) return;
    setState(() => _nearbySelectedId = stopId);
    _drawNearbyStops();
    unawaited(_loadStopDepartures(stopId));
    _map?.moveTo(
      stop.location.latitude,
      stop.location.longitude,
      zoom: _stopZoom,
    );
  }

  /// One of the routes of a nearby stop: draws that direction with the stop
  /// highlighted.
  void _showStopRoute(NearbyStop stop, StopRoute stopRoute) {
    _selectRoute(stopRoute.route, pattern: stopRoute.pattern);
    final patternStop = stopRoute.pattern.stops
        .where((s) => s.stopId == stop.stopId)
        .firstOrNull;
    if (patternStop != null) _onStopTap(patternStop);
  }

  // --- Next departures of a stop ("Próximas salidas") ----------------------------

  /// Departures of the selected stop (by stop id) and when they were asked.
  final Map<String, (DateTime, List<StopDeparture>)> _departures = {};
  final Set<String> _departuresLoading = {};
  final Map<String, String> _departuresError = {};

  /// Answers older than this are asked again when the stop is selected.
  static const _departuresMaxAge = Duration(minutes: 1);

  Future<void> _loadStopDepartures(String stopId, {bool force = false}) async {
    if (_departuresLoading.contains(stopId)) return;
    final cached = _departures[stopId];
    final now = widget.clock();
    if (!force &&
        cached != null &&
        now.difference(cached.$1) < _departuresMaxAge) {
      return;
    }
    setState(() {
      _departuresLoading.add(stopId);
      _departuresError.remove(stopId);
    });
    try {
      final departures = await _operations.stopDepartures(stopId, from: now);
      if (mounted) setState(() => _departures[stopId] = (now, departures));
    } on ApiException catch (e) {
      if (mounted) setState(() => _departuresError[stopId] = e.message);
    } finally {
      if (mounted) setState(() => _departuresLoading.remove(stopId));
    }
  }

  StopDeparturesState _departuresOf(String? stopId) => stopId == null
      ? const StopDeparturesState()
      : StopDeparturesState(
          departures: _departures[stopId]?.$2,
          loading: _departuresLoading.contains(stopId),
          error: _departuresError[stopId],
        );

  /// A departure of "Próximas salidas": draws its direction with the stop.
  void _showDeparture(NearbyStop stop, StopDeparture departure) {
    final stopRoute = stop.routes
        .where((r) => r.pattern.id == departure.patternId)
        .firstOrNull;
    if (stopRoute != null) _showStopRoute(stop, stopRoute);
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
    unawaited(_loadSchedules(pattern));
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
        Navigator.pushReplacementNamed(context, '/passenger/favorites');
        return;
      case 2:
        Navigator.pushReplacementNamed(context, '/passenger/account');
        return;
    }
  }

  /// The search bar is a button: the user types on "Buscar ruta".
  /// Search -> route detail -> "Ver ruta" comes back here with the route.
  Future<void> _openSearch() async {
    final result = await Navigator.pushNamed<Object?>(
      context,
      '/passenger/search',
    );
    if (result is RouteSelection && mounted) _showSelection(result);
  }

  Future<void> _onChipTap(MapQuickChip chip) async {
    switch (chip.label) {
      case '¿Cómo llego?':
        _openPlanner();
      case 'Paradas cercanas':
        _openNearbyStops();
      case 'Buses en curso':
        // Route -> buses running now -> live tracking, or "Ver ruta" back here.
        final result = await Navigator.pushNamed<Object?>(
          context,
          '/passenger/buses',
        );
        if (result is RouteSelection && mounted) _showSelection(result);
    }
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
    if (_nearbyMode) {
      return [
        NearbyStopsPanel(
          colors: colors,
          stops: _nearbyStops,
          loading: _routesLoading,
          error: _routesError,
          radiusMeters: widget.routesFilter.radiusMeters,
          selectedId: _nearbySelectedId,
          onStopSelected: (stop) => _selectNearbyStop(stop.stopId),
          onRouteSelected: _showStopRoute,
          onRetry: _loadRoutes,
          onClose: _closeNearbyStops,
          passingRoutes: _passingNear,
          onPassingRouteSelected: _showPassingRoute,
          departures: _departuresOf(_nearbySelectedId),
          onDepartureSelected: _showDeparture,
          onRetryDepartures: _nearbySelectedId == null
              ? null
              : () => _loadStopDepartures(_nearbySelectedId!, force: true),
          now: widget.clock(),
        ),
      ];
    }
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
          fare: _fares[route.id],
          schedules: _schedules[_selectedPattern?.id],
          timetableLoading: _schedulesLoading.contains(_selectedPattern?.id),
        ),
      ];
    }
    if (_plannerMode) {
      final destination = _destination;
      final location = _location;
      return [
        JourneyPlannerPanel(
          colors: colors,
          hasDestination: destination != null,
          destinationMeters: destination == null || location == null
              ? null
              : haversineMeters(
                  location.latitude,
                  location.longitude,
                  destination.latitude,
                  destination.longitude,
                ),
          options: _journeyOptions,
          loading: _journeysLoading,
          error: _journeysError,
          now: widget.clock(),
          onSelected: _selectJourney,
          onRetry: _loadJourneys,
          onClose: _closePlanner,
          passing: _passingOptions(),
          onPassingSelected: _selectPassing,
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
        fares: _fares,
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

  Widget? _mapWidget;
  MapMode? _mapBuiltFor;

  /// The map widget, built again only when its mode changes: the same
  /// instance makes Flutter skip it when the screen rebuilds (location,
  /// live buses, the list), so the native map is not touched for nothing.
  Widget _mapView(BuildContext context, double topInset) {
    if (_mapWidget == null || _mapBuiltFor != _mapMode) {
      _mapBuiltFor = _mapMode;
      _mapWidget = widget.mapBuilder(
        context,
        PassengerMapOptions(
          mode: _mapMode,
          onReady: _onMapReady,
          onStopTap: _onStopTap,
          onBusTap: _openLiveTracking,
          onNearbyStopTap: _selectNearbyStop,
          onLongPress: _onMapLongPress,
          // Below the search bar and the chips.
          compassTopMargin: topInset + 128,
        ),
      );
    }
    return _mapWidget!;
  }

  @override
  Widget build(BuildContext context) {
    // SmartBus map design: dark cards over a light map, in any phone theme.
    const colors = MapOverlayColors.smartBus;
    final topInset = MediaQuery.paddingOf(context).top;
    final routeShown = _selectedRoute != null;
    final showBanner = _access != null && _access != LocationAccess.granted;

    // Android "back" closes the shown route (or the nearby stops) first.
    return PopScope(
      canPop: !routeShown && !_nearbyMode && !_plannerMode,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (routeShown) {
          _clearSelection();
        } else if (_nearbyMode) {
          _closeNearbyStops();
        } else if (_plannerMode) {
          _closePlanner();
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
                Positioned.fill(child: _mapView(context, topInset)),

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

                // License attribution (its own line, right above the sheet)
                // and the map buttons above it. Only this part follows the
                // sheet while it is dragged.
                Positioned.fill(
                  child: ValueListenableBuilder<double>(
                    valueListenable: _sheetExtent,
                    builder: (context, extent, _) => Stack(
                      children: [
                        Positioned(
                          left: 12,
                          right: 12,
                          bottom: height * extent + 6,
                          child: MapAttribution(mode: _mapMode),
                        ),
                        // Map mode + "my location": against the right edge,
                        // above the attribution line (never on top of it).
                        Positioned(
                          right: 16,
                          bottom: height * extent + 24,
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
                      ],
                    ),
                  ),
                ),

                NotificationListener<DraggableScrollableNotification>(
                  onNotification: (notification) {
                    _sheetExtent.value = notification.extent;
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
