import 'dart:math' as math;

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

  /// `SmartBusColors.verdePasajero`.
  static const _brandColor = '#01856D';

  MapLibreMapController? _controller;
  bool _styleReady = false;
  bool _readyNotified = false;
  DeviceLocation? _userLocation;

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

    _styleReady = true;
    final location = _userLocation;
    if (location != null) await _drawUser(location);

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
