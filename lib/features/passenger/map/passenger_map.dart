import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../../../core/config/map_config.dart';
import '../../../core/location/location_service.dart';

/// What the passenger home screen can do with the map, without depending on
/// MapLibre (so tests can plug in a fake map).
abstract interface class PassengerMapHandle {
  /// Moves the camera to a point; keeps the current zoom when [zoom] is null.
  Future<void> moveTo(double latitude, double longitude, {double? zoom});

  /// Draws (or updates) the user's position marker and accuracy circle.
  Future<void> showUserLocation(DeviceLocation location);

  /// Draws (or moves) the bus marker; `null` hides it.
  Future<void> showBus(BusMarker? bus);
}

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
  });

  final double latitude;
  final double longitude;
  final bool live;

  @override
  bool operator ==(Object other) =>
      other is BusMarker &&
      other.latitude == latitude &&
      other.longitude == longitude &&
      other.live == live;

  @override
  int get hashCode => Object.hash(latitude, longitude, live);
}

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
  });

  /// Streets or satellite base map.
  final MapMode mode;

  final ValueChanged<PassengerMapHandle> onReady;

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

  /// `SmartBusColors.verdePasajero`.
  static const _brandColor = '#01856D';

  /// Bus with an old position (weak signal).
  static const _staleColor = Color(0xFF9CA3AF);

  MapLibreMapController? _controller;
  bool _styleReady = false;
  bool _readyNotified = false;
  DeviceLocation? _userLocation;
  BusMarker? _bus;

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
      onMapCreated: (controller) => _controller = controller,
      onStyleLoadedCallback: _onStyleLoaded,
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
    await controller.addGeoJsonSource(_busSource, _busCollection(null));
    await controller.addSymbolLayer(
      _busSource,
      _busLayer,
      const SymbolLayerProperties(
        iconImage: ['get', 'icon'],
        iconAnchor: 'bottom',
        iconAllowOverlap: true,
        iconIgnorePlacement: true,
      ),
      enableInteraction: false,
    );

    _styleReady = true;
    final location = _userLocation;
    if (location != null) await _drawUser(location);
    if (_bus != null) await _drawBus();

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
  Future<void> showBus(BusMarker? bus) async {
    if (bus == _bus) return;
    _bus = bus;
    if (_styleReady) await _drawBus();
  }

  Future<void> _drawBus() =>
      _controller!.setGeoJsonSource(_busSource, _busCollection(_bus));

  static Map<String, dynamic> _busCollection(BusMarker? bus) => {
    'type': 'FeatureCollection',
    'features': [
      if (bus != null)
        {
          'type': 'Feature',
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
