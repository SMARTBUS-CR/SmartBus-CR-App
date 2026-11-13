import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../../../core/config/map_config.dart';
import '../../../core/location/location_service.dart';
import '../../operations/models/operations_models.dart';
import '../../operations/services/nearby_stops.dart';

export '../../operations/services/nearby_stops.dart' show NearbyStop;

/// What the passenger home screen can do with the map, without depending on
/// MapLibre (so tests can plug in a fake map).
abstract interface class PassengerMapHandle {
  /// Moves the camera to a point; keeps the current zoom when [zoom] is null.
  Future<void> moveTo(double latitude, double longitude, {double? zoom});

  /// Draws (or updates) the user's position marker and accuracy circle.
  Future<void> showUserLocation(DeviceLocation location);

  /// Draws (or moves) the bus marker; `null` hides it.
  Future<void> showBus(BusMarker? bus);

  /// Draws every bus in [buses] (the buses running on the selected route),
  /// replacing the ones drawn before; empty hides them. Same layer as
  /// [showBus]. A tap on one reports its [BusMarker.id]
  /// ([PassengerMapOptions.onBusTap]).
  Future<void> showBuses(List<BusMarker> buses);

  /// Draws the line of [pattern] and its stops as numbered markers, replacing
  /// any route already drawn. Without `route_geometry` the stops are joined in
  /// order (approximate path), drawn the same way.
  Future<void> showRoute(RoutePattern pattern);

  /// Removes the route line and its stops.
  Future<void> clearRoute();

  /// Highlights one stop of the drawn route (a halo around its marker);
  /// `null` removes the highlight.
  Future<void> highlightStop(PatternStop? stop);

  /// Moves the camera so every point is visible, leaving [padding] free (the
  /// search bar on top, the bottom sheet below).
  Future<void> fitBounds(
    List<GeoPoint> points, {
    EdgeInsets padding = EdgeInsets.zero,
  });

  /// Draws the stops near the passenger ("Paradas cercanas"), replacing the
  /// ones drawn before; empty hides them. [selectedId] is drawn bigger. A tap
  /// on one reports its [NearbyStop.stopId]
  /// ([PassengerMapOptions.onNearbyStopTap]).
  Future<void> showNearbyStops(List<NearbyStop> stops, {String? selectedId});

  /// Draws the destination pin of "¿Cómo llego?"; `null` hides it.
  Future<void> showDestination(GeoPoint? point);
}

/// The destination pin as a GeoJSON FeatureCollection (empty without one).
Map<String, dynamic> destinationFeatureCollection(GeoPoint? point) => {
  'type': 'FeatureCollection',
  'features': [
    if (point != null)
      {
        'type': 'Feature',
        'geometry': {
          'type': 'Point',
          'coordinates': [point.longitude, point.latitude],
        },
        'properties': <String, dynamic>{},
      },
  ],
};

/// The stops of "Paradas cercanas" as one GeoJSON FeatureCollection: `id` =
/// `nearby-<stopId>`, `properties.selected` = it is [selectedId]. Kept apart
/// from MapLibre so it can be unit-tested.
Map<String, dynamic> nearbyStopsFeatureCollection(
  List<NearbyStop> stops, {
  String? selectedId,
}) => {
  'type': 'FeatureCollection',
  'features': [
    for (final stop in stops)
      {
        'type': 'Feature',
        'id': '$nearbyStopIdPrefix${stop.stopId}',
        'geometry': {
          'type': 'Point',
          'coordinates': [stop.location.longitude, stop.location.latitude],
        },
        'properties': {'selected': stop.stopId == selectedId},
      },
  ],
};

/// Prefix of the GeoJSON id of each nearby stop marker.
const nearbyStopIdPrefix = 'nearby-';

/// Line + numbered stops to draw for a pattern, as one GeoJSON
/// FeatureCollection. Kept apart from MapLibre so it can be unit-tested.
///
/// - Line: `properties.approximate` is `true` when the pattern has no geometry
///   (stops joined in order). Not drawn with fewer than 2 points.
/// - Stops: `id` = `stop-<index in pattern.stops>`, `properties.seq` = the
///   number shown on the marker (1, 2, 3… in travel order),
///   `properties.kind` = `start` (first stop), `end` (last) or `mid`, and
///   `properties.selected` = it is [selected] (highlighted).
Map<String, dynamic> routeFeatureCollection(
  RoutePattern? pattern, {
  PatternStop? selected,
}) {
  if (pattern == null) {
    return {'type': 'FeatureCollection', 'features': <dynamic>[]};
  }
  final path = pattern.path;
  final features = <Map<String, dynamic>>[
    if (path.length >= 2)
      {
        'type': 'Feature',
        'geometry': {
          'type': 'LineString',
          'coordinates': [
            for (final point in path) [point.longitude, point.latitude],
          ],
        },
        'properties': {'approximate': !pattern.hasGeometry},
      },
  ];
  final last = pattern.stops.length - 1;
  for (var i = 0; i <= last; i++) {
    final stop = pattern.stops[i];
    final location = stop.location;
    if (location == null) continue;
    features.add({
      'type': 'Feature',
      'id': '$routeStopIdPrefix$i',
      'geometry': {
        'type': 'Point',
        'coordinates': [location.longitude, location.latitude],
      },
      'properties': {
        'seq': '${i + 1}',
        'kind': i == 0 ? 'start' : (i == last ? 'end' : 'mid'),
        // Same object: a stop can appear twice in a loop route.
        'selected': identical(stop, selected),
      },
    });
  }
  return {'type': 'FeatureCollection', 'features': features};
}

/// Prefix of the GeoJSON id of each stop marker (see [routeFeatureCollection]).
const routeStopIdPrefix = 'stop-';

/// The bus on the map, drawn as a pin with a bus icon whose tip is the bus
/// position, so the passenger's own dot stays visible even at the same spot.
/// [live] = recent position (brand color); otherwise it is drawn in gray (weak
/// signal / old position).
@immutable
class BusMarker {
  const BusMarker({
    required this.latitude,
    required this.longitude,
    this.live = true,
    this.id,
  });

  final double latitude;
  final double longitude;
  final bool live;

  /// Identifies the bus when it is tapped (the trip id); optional.
  final String? id;

  @override
  bool operator ==(Object other) =>
      other is BusMarker &&
      other.latitude == latitude &&
      other.longitude == longitude &&
      other.live == live &&
      other.id == id;

  @override
  int get hashCode => Object.hash(latitude, longitude, live, id);
}

/// Prefix of the GeoJSON id of each bus pin (`bus-<BusMarker.id>`).
const busIdPrefix = 'bus-';

/// Builds the map widget. [onReady] is called once the map can be controlled.
typedef PassengerMapBuilder = Widget Function(
  BuildContext context,
  PassengerMapOptions options,
);

class PassengerMapOptions {
  const PassengerMapOptions({
    required this.mode,
    required this.onReady,
    this.compassTopMargin = 16,
    this.onStopTap,
    this.onBusTap,
    this.onNearbyStopTap,
    this.onLongPress,
  });

  /// The passenger kept a finger on the map: that point ("¿Cómo llego?").
  final ValueChanged<GeoPoint>? onLongPress;

  /// The passenger tapped a bus pin drawn with [PassengerMapHandle.showBuses];
  /// receives its [BusMarker.id].
  final ValueChanged<String>? onBusTap;

  /// The passenger tapped a stop drawn with
  /// [PassengerMapHandle.showNearbyStops]; receives its [NearbyStop.stopId].
  final ValueChanged<String>? onNearbyStopTap;

  /// Streets or satellite base map.
  final MapMode mode;

  final ValueChanged<PassengerMapHandle> onReady;

  /// The passenger tapped a stop marker of the route drawn with
  /// [PassengerMapHandle.showRoute].
  final ValueChanged<PatternStop>? onStopTap;

  /// Distance from the top so the compass is not hidden by the search bar.
  final double compassTopMargin;
}

/// Default builder: the real MapLibre map with the OpenFreeMap style.
Widget buildMapLibrePassengerMap(
  BuildContext context,
  PassengerMapOptions options,
) => MapLibrePassengerMap(options: options);

/// Interactive map (MapLibre: OpenFreeMap streets or EOX satellite) for the
/// passenger home.
///
/// The user location is drawn with SmartBus colors as a GeoJSON source with two
/// circle layers (accuracy halo + dot), instead of the SDK's default blue puck.
class MapLibrePassengerMap extends StatefulWidget {
  const MapLibrePassengerMap({super.key, required this.options});

  final PassengerMapOptions options;

  @override
  State<MapLibrePassengerMap> createState() => _MapLibrePassengerMapState();
}

class _MapLibrePassengerMapState extends State<MapLibrePassengerMap>
    implements PassengerMapHandle {
  static const _userSource = 'smartbus-user-location';
  static const _accuracyLayer = 'smartbus-user-accuracy';
  static const _dotLayer = 'smartbus-user-dot';
  static const _busSource = 'smartbus-bus';
  static const _busLayer = 'smartbus-bus-pin';
  static const _busLiveIcon = 'smartbus-bus-live';
  static const _busStaleIcon = 'smartbus-bus-stale';
  static const _routeSource = 'smartbus-route';
  static const _routeGlowLayer = 'smartbus-route-glow';
  static const _routeCasingLayer = 'smartbus-route-casing';
  static const _routeLineLayer = 'smartbus-route-line';
  static const _routeArrowsLayer = 'smartbus-route-arrows';
  static const _routeSelectedLayer = 'smartbus-route-selected';
  static const _routeStopsLayer = 'smartbus-route-stops';
  static const _routeStopLabelsLayer = 'smartbus-route-stop-labels';
  static const _routeArrowIcon = 'smartbus-route-arrow';
  static const _nearbySource = 'smartbus-nearby-stops';
  static const _nearbyHaloLayer = 'smartbus-nearby-stops-halo';
  static const _nearbyLayer = 'smartbus-nearby-stops-dots';
  static const _destinationSource = 'smartbus-destination';
  static const _destinationHaloLayer = 'smartbus-destination-halo';
  static const _destinationLayer = 'smartbus-destination-dot';

  /// Destination pin: `SmartBusColors.azulPrincipal`, apart from the green
  /// user dot and the turquoise stops.
  static const _destinationColor = '#1565C0';

  /// `SmartBusColors.verdePasajero`.
  static const _brandColor = '#01856D';

  /// Route gradient: `SmartBusColors.verdeTurquesa` at the start →
  /// `SmartBusColors.azulPrincipal` at the end. Stands out from the darker
  /// green user dot and bus pin.
  static const _routeStartColor = '#00BFA5';
  static const _routeEndColor = '#1565C0';

  /// Bus with an old position (weak signal).
  static const _staleColor = Color(0xFF9CA3AF);

  MapLibreMapController? _controller;
  bool _styleReady = false;
  bool _readyNotified = false;
  DeviceLocation? _userLocation;
  List<BusMarker> _buses = const [];
  RoutePattern? _route;
  PatternStop? _selectedStop;
  List<NearbyStop> _nearby = const [];
  String? _nearbySelected;
  GeoPoint? _destination;

  @override
  void dispose() {
    _controller?.onFeatureTapped.remove(_onFeatureTapped);
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant MapLibrePassengerMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A new style (streets <-> satellite) drops the custom layers: they are
    // added again in _onStyleLoaded.
    if (oldWidget.options.mode != widget.options.mode) {
      _styleReady = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return MapLibreMap(
      styleString: MapConfig.styleFor(widget.options.mode),
      initialCameraPosition: const CameraPosition(
        target: LatLng(MapConfig.fallbackLatitude, MapConfig.fallbackLongitude),
        zoom: MapConfig.fallbackZoom,
      ),
      onMapCreated: (controller) {
        _controller = controller;
        controller.onFeatureTapped.add(_onFeatureTapped);
      },
      onStyleLoadedCallback: _onStyleLoaded,
      onMapLongClick: (_, coordinates) => widget.options.onLongPress?.call(
        GeoPoint(coordinates.latitude, coordinates.longitude),
      ),
      // Native compass: hidden while facing north, tap resets the bearing.
      compassEnabled: true,
      compassViewPosition: CompassViewPosition.topRight,
      compassViewMargins: math.Point(16, widget.options.compassTopMargin),
      myLocationEnabled: false,
      rotateGesturesEnabled: true,
      tiltGesturesEnabled: true,
    );
  }

  Future<void> _onStyleLoaded() async {
    final controller = _controller;
    if (controller == null || !mounted) return;
    final ratio = MediaQuery.devicePixelRatioOf(context);

    // Route first: the user dot and the bus are drawn on top of it.
    await _addRouteLayers(controller, ratio);
    if (!mounted) return;
    await _addNearbyLayers(controller);
    if (!mounted) return;
    await _addDestinationLayers(controller);
    if (!mounted) return;

    await controller.addGeoJsonSource(_userSource, _featureCollection(null));
    await controller.addCircleLayer(
      _userSource,
      _accuracyLayer,
      CircleLayerProperties(
        // Accuracy in meters -> pixels at every zoom (exponential base 2).
        circleRadius: [
          'interpolate',
          ['exponential', 2],
          ['zoom'],
          0,
          ['get', 'accuracy_px_z0'],
          22,
          [
            '*',
            ['get', 'accuracy_px_z0'],
            math.pow(2, 22),
          ],
        ],
        circleColor: _brandColor,
        circleOpacity: 0.15,
        circleStrokeColor: _brandColor,
        circleStrokeWidth: 1,
        circleStrokeOpacity: 0.4,
        circlePitchAlignment: 'map',
      ),
      enableInteraction: false,
    );
    await controller.addCircleLayer(
      _userSource,
      _dotLayer,
      const CircleLayerProperties(
        circleRadius: 7,
        circleColor: _brandColor,
        circleStrokeColor: '#FFFFFF',
        circleStrokeWidth: 3,
      ),
      enableInteraction: false,
    );

    // Bus: a pin with a bus icon, above the user dot. Its tip (bottom anchor)
    // is the bus position, so a passenger at the same spot is still visible
    // right under it. The icon (live / stale) comes from each feature.
    await controller.addImage(
      _busLiveIcon,
      await _busPinPng(const Color(0xFF01856D), ratio),
    );
    await controller.addImage(
      _busStaleIcon,
      await _busPinPng(_staleColor, ratio),
    );
    if (!mounted) return;
    await controller.addGeoJsonSource(_busSource, _busCollection(const []));
    await controller.addSymbolLayer(
      _busSource,
      _busLayer,
      const SymbolLayerProperties(
        iconImage: ['get', 'icon'],
        iconAnchor: 'bottom',
        iconAllowOverlap: true,
        iconIgnorePlacement: true,
      ),
      // Tappable: opens "Rastreando tu bus" from the home map (onBusTap).
      enableInteraction: true,
    );

    _styleReady = true;
    final location = _userLocation;
    if (location != null) await _drawUser(location);
    if (_buses.isNotEmpty) await _drawBuses();
    if (_route != null) await _drawRoute();
    if (_nearby.isNotEmpty) await _drawNearby();
    if (_destination != null) await _drawDestination();

    if (!_readyNotified && mounted) {
      _readyNotified = true;
      widget.options.onReady(this);
    }
  }

  @override
  Future<void> moveTo(double latitude, double longitude, {double? zoom}) async {
    final target = LatLng(latitude, longitude);
    await _controller?.animateCamera(
      zoom != null
          ? CameraUpdate.newLatLngZoom(target, zoom)
          : CameraUpdate.newLatLng(target),
      duration: const Duration(milliseconds: 600),
    );
  }

  @override
  Future<void> showUserLocation(DeviceLocation location) async {
    _userLocation = location;
    if (_styleReady) await _drawUser(location);
  }

  Future<void> _drawUser(DeviceLocation location) =>
      _controller!.setGeoJsonSource(_userSource, _featureCollection(location));

  @override
  Future<void> showBus(BusMarker? bus) => showBuses([?bus]);

  @override
  Future<void> showBuses(List<BusMarker> buses) async {
    if (listEquals(buses, _buses)) return;
    _buses = List.unmodifiable(buses);
    if (_styleReady) await _drawBuses();
  }

  Future<void> _drawBuses() =>
      _controller!.setGeoJsonSource(_busSource, _busCollection(_buses));

  // --- Route --------------------------------------------------------------------

  /// One GeoJSON source (line + stops, with line metrics for the gradient) and,
  /// bottom to top:
  /// 1. a soft glow and a white casing under the line;
  /// 2. the line: a solid gradient from the start color to the end color (it
  ///    shows the direction), also when the path is approximate;
  /// 3. white chevrons along the line, pointing the way the bus goes;
  /// 4. a halo under the selected stop;
  /// 5. the stops: start (teal) and end (blue) filled and bigger, the others
  ///    white with their number.
  Future<void> _addRouteLayers(
    MapLibreMapController controller,
    double ratio,
  ) async {
    const isLine = [
      '==',
      ['geometry-type'],
      'LineString',
    ];
    const isPoint = [
      '==',
      ['geometry-type'],
      'Point',
    ];
    const kind = ['get', 'kind'];
    const isMid = ['==', kind, 'mid'];

    await controller.addImage(_routeArrowIcon, await _arrowPng(ratio));
    await controller.addSource(
      _routeSource,
      GeojsonSourceProperties(
        data: routeFeatureCollection(null),
        // Needed by `line-gradient` (['line-progress']).
        lineMetrics: true,
      ),
    );
    await controller.addLineLayer(
      _routeSource,
      _routeGlowLayer,
      const LineLayerProperties(
        lineColor: _routeEndColor,
        lineWidth: 18,
        lineBlur: 10,
        lineOpacity: 0.35,
        lineJoin: 'round',
        lineCap: 'round',
      ),
      filter: isLine,
      enableInteraction: false,
    );
    await controller.addLineLayer(
      _routeSource,
      _routeCasingLayer,
      const LineLayerProperties(
        lineColor: '#FFFFFF',
        lineWidth: 10,
        lineJoin: 'round',
        lineCap: 'round',
      ),
      filter: isLine,
      enableInteraction: false,
    );
    await controller.addLineLayer(
      _routeSource,
      _routeLineLayer,
      const LineLayerProperties(
        lineGradient: [
          'interpolate',
          ['linear'],
          ['line-progress'],
          0,
          _routeStartColor,
          1,
          _routeEndColor,
        ],
        lineWidth: 6,
        lineJoin: 'round',
        lineCap: 'round',
      ),
      // Same solid gradient with or without real geometry.
      filter: isLine,
      enableInteraction: false,
    );
    await controller.addSymbolLayer(
      _routeSource,
      _routeArrowsLayer,
      const SymbolLayerProperties(
        symbolPlacement: 'line',
        symbolSpacing: 70,
        iconImage: _routeArrowIcon,
        iconRotationAlignment: 'map',
        iconAllowOverlap: true,
        iconIgnorePlacement: true,
      ),
      filter: isLine,
      enableInteraction: false,
    );
    await controller.addCircleLayer(
      _routeSource,
      _routeSelectedLayer,
      const CircleLayerProperties(
        circleRadius: 22,
        circleColor: _routeEndColor,
        circleOpacity: 0.22,
        circleStrokeColor: _routeEndColor,
        circleStrokeWidth: 2,
        circleStrokeOpacity: 0.6,
      ),
      filter: [
        'all',
        isPoint,
        [
          '==',
          ['get', 'selected'],
          true,
        ],
      ],
      enableInteraction: false,
    );
    await controller.addCircleLayer(
      _routeSource,
      _routeStopsLayer,
      const CircleLayerProperties(
        circleRadius: ['case', isMid, 9, 13],
        circleColor: [
          'match',
          kind,
          'start',
          _routeStartColor,
          'end',
          _routeEndColor,
          '#FFFFFF',
        ],
        circleStrokeColor: ['match', kind, 'mid', _routeEndColor, '#FFFFFF'],
        circleStrokeWidth: 3,
      ),
      filter: isPoint,
      // Tappable: shows the stop details (onStopTap).
      enableInteraction: true,
    );
    await controller.addSymbolLayer(
      _routeSource,
      _routeStopLabelsLayer,
      const SymbolLayerProperties(
        textField: ['get', 'seq'],
        textFont: [MapConfig.labelFont],
        textSize: ['case', isMid, 10, 12],
        textColor: ['case', isMid, _routeEndColor, '#FFFFFF'],
        textAllowOverlap: true,
        textIgnorePlacement: true,
      ),
      filter: isPoint,
      enableInteraction: false,
    );
  }

  @override
  Future<void> showRoute(RoutePattern pattern) async {
    _route = pattern;
    _selectedStop = null;
    if (_styleReady) await _drawRoute();
  }

  @override
  Future<void> clearRoute() async {
    if (_route == null) return;
    _route = null;
    _selectedStop = null;
    if (_styleReady) await _drawRoute();
  }

  @override
  Future<void> highlightStop(PatternStop? stop) async {
    if (identical(stop, _selectedStop)) return;
    _selectedStop = stop;
    if (_styleReady && _route != null) await _drawRoute();
  }

  Future<void> _drawRoute() => _controller!.setGeoJsonSource(
    _routeSource,
    routeFeatureCollection(_route, selected: _selectedStop),
  );

  // --- Nearby stops -------------------------------------------------------------

  /// A soft halo under the selected stop and a turquoise dot per stop
  /// (tappable), under the user dot and the buses.
  Future<void> _addNearbyLayers(MapLibreMapController controller) async {
    const selected = [
      '==',
      ['get', 'selected'],
      true,
    ];
    await controller.addGeoJsonSource(
      _nearbySource,
      nearbyStopsFeatureCollection(const []),
    );
    await controller.addCircleLayer(
      _nearbySource,
      _nearbyHaloLayer,
      const CircleLayerProperties(
        circleRadius: 20,
        circleColor: _routeStartColor,
        circleOpacity: 0.25,
      ),
      filter: selected,
      enableInteraction: false,
    );
    await controller.addCircleLayer(
      _nearbySource,
      _nearbyLayer,
      const CircleLayerProperties(
        circleRadius: ['case', selected, 10, 7],
        circleColor: _routeStartColor,
        circleStrokeColor: '#FFFFFF',
        circleStrokeWidth: 3,
      ),
      // Tappable: selects the stop (onNearbyStopTap).
      enableInteraction: true,
    );
  }

  @override
  Future<void> showNearbyStops(
    List<NearbyStop> stops, {
    String? selectedId,
  }) async {
    if (identical(stops, _nearby) && selectedId == _nearbySelected) return;
    _nearby = List.unmodifiable(stops);
    _nearbySelected = selectedId;
    if (_styleReady) await _drawNearby();
  }

  Future<void> _drawNearby() => _controller!.setGeoJsonSource(
    _nearbySource,
    nearbyStopsFeatureCollection(_nearby, selectedId: _nearbySelected),
  );

  /// A blue dot with a soft halo for the destination of "¿Cómo llego?".
  Future<void> _addDestinationLayers(MapLibreMapController controller) async {
    await controller.addGeoJsonSource(
      _destinationSource,
      destinationFeatureCollection(null),
    );
    await controller.addCircleLayer(
      _destinationSource,
      _destinationHaloLayer,
      const CircleLayerProperties(
        circleRadius: 22,
        circleColor: _destinationColor,
        circleOpacity: 0.2,
      ),
      enableInteraction: false,
    );
    await controller.addCircleLayer(
      _destinationSource,
      _destinationLayer,
      const CircleLayerProperties(
        circleRadius: 9,
        circleColor: _destinationColor,
        circleStrokeColor: '#FFFFFF',
        circleStrokeWidth: 3,
      ),
      enableInteraction: false,
    );
  }

  @override
  Future<void> showDestination(GeoPoint? point) async {
    if (point == _destination) return;
    _destination = point;
    if (_styleReady) await _drawDestination();
  }

  Future<void> _drawDestination() => _controller!.setGeoJsonSource(
    _destinationSource,
    destinationFeatureCollection(_destination),
  );

  /// PNG of the direction chevron drawn along the line (white with a soft
  /// shadow, pointing right: MapLibre rotates it with the line).
  static Future<Uint8List> _arrowPng(double ratio) async {
    const size = 14.0;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..scale(ratio);
    final chevron = Path()
      ..moveTo(4, 3)
      ..lineTo(10, size / 2)
      ..lineTo(4, size - 3);
    canvas
      ..drawPath(
        chevron,
        Paint()
          ..color = const Color(0x55000000)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      )
      ..drawPath(
        chevron,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.4
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    final image = await recorder.endRecording().toImage(
      (size * ratio).ceil(),
      (size * ratio).ceil(),
    );
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return png!.buffer.asUint8List();
  }

  void _onFeatureTapped(
    math.Point<double> point,
    LatLng coordinates,
    String id,
    String layerId,
    Annotation? annotation,
  ) {
    if (id.startsWith(busIdPrefix)) {
      widget.options.onBusTap?.call(id.substring(busIdPrefix.length));
      return;
    }
    if (id.startsWith(nearbyStopIdPrefix)) {
      widget.options.onNearbyStopTap?.call(
        id.substring(nearbyStopIdPrefix.length),
      );
      return;
    }
    final route = _route;
    final onStopTap = widget.options.onStopTap;
    if (route == null || onStopTap == null) return;
    if (!id.startsWith(routeStopIdPrefix)) return;
    final index = int.tryParse(id.substring(routeStopIdPrefix.length));
    if (index == null || index < 0 || index >= route.stops.length) return;
    onStopTap(route.stops[index]);
  }

  @override
  Future<void> fitBounds(
    List<GeoPoint> points, {
    EdgeInsets padding = EdgeInsets.zero,
  }) async {
    final controller = _controller;
    if (controller == null || points.isEmpty) return;
    if (points.length == 1) {
      return moveTo(points.single.latitude, points.single.longitude);
    }
    var south = points.first.latitude, north = south;
    var west = points.first.longitude, east = west;
    for (final point in points.skip(1)) {
      south = math.min(south, point.latitude);
      north = math.max(north, point.latitude);
      west = math.min(west, point.longitude);
      east = math.max(east, point.longitude);
    }
    await controller.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(south, west),
          northeast: LatLng(north, east),
        ),
        left: padding.left,
        top: padding.top,
        right: padding.right,
        bottom: padding.bottom,
      ),
      duration: const Duration(milliseconds: 600),
    );
  }

  static Map<String, dynamic> _busCollection(List<BusMarker> buses) => {
    'type': 'FeatureCollection',
    'features': [
      for (final bus in buses)
        {
          'type': 'Feature',
          if (bus.id != null) 'id': '$busIdPrefix${bus.id}',
          'geometry': {
            'type': 'Point',
            'coordinates': [bus.longitude, bus.latitude],
          },
          'properties': {'icon': bus.live ? _busLiveIcon : _busStaleIcon},
        },
    ],
  };

  /// PNG of the bus pin: a rounded badge with a white bus icon and a pointer
  /// whose tip is the bus position. Drawn at the screen [ratio] so it stays
  /// sharp; MapLibre shows it at its logical size (44 x 54).
  static Future<Uint8List> _busPinPng(Color color, double ratio) async {
    const width = 44.0;
    const badge = 40.0; // height of the rounded badge
    const height = 54.0; // badge + pointer
    const stroke = 3.0;
    const half = stroke / 2;

    final shape = Path.combine(
      PathOperation.union,
      Path()..addRRect(
        RRect.fromLTRBR(
          half,
          half,
          width - half,
          badge,
          const Radius.circular(12),
        ),
      ),
      Path()
        ..moveTo(width / 2 - 8, badge - 2)
        ..lineTo(width / 2, height - half)
        ..lineTo(width / 2 + 8, badge - 2)
        ..close(),
    );

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..scale(ratio);
    canvas
      ..drawPath(shape, Paint()..color = color)
      ..drawPath(
        shape,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeJoin = StrokeJoin.round,
      );

    const icon = Icons.directions_bus_filled;
    final glyph = TextPainter(
      textDirection: TextDirection.ltr,
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          fontFamily: icon.fontFamily,
          package: icon.fontPackage,
          fontSize: 24,
          color: Colors.white,
        ),
      ),
    )..layout();
    glyph.paint(
      canvas,
      Offset((width - glyph.width) / 2, (badge + half - glyph.height) / 2),
    );
    glyph.dispose();

    final image = await recorder.endRecording().toImage(
      (width * ratio).ceil(),
      (height * ratio).ceil(),
    );
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return png!.buffer.asUint8List();
  }

  /// GeoJSON with the user point. `accuracy_px_z0` is the accuracy radius in
  /// pixels at zoom 0 (512 px tiles), so the style can scale it by 2^zoom.
  static Map<String, dynamic> _featureCollection(DeviceLocation? location) {
    if (location == null) {
      return {'type': 'FeatureCollection', 'features': <dynamic>[]};
    }

    const earthCircumference = 40075016.686;
    final metersPerPixelZ0 =
        earthCircumference * math.cos(location.latitude * math.pi / 180) / 512;

    return {
      'type': 'FeatureCollection',
      'features': [
        {
          'type': 'Feature',
          'geometry': {
            'type': 'Point',
            'coordinates': [location.longitude, location.latitude],
          },
          'properties': {
            'accuracy_px_z0': location.accuracyMeters / metersPerPixelZ0,
          },
        },
      ],
    };
  }
}
