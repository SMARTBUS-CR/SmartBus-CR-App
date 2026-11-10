import 'dart:convert';

/// Base map shown on the passenger home.
enum MapMode {
  /// Streets, places, businesses and zones (OpenFreeMap "Liberty").
  streets,

  /// Satellite imagery (Esri World Imagery — development only, see [MapConfig]).
  satellite,
}

/// Map configuration (passenger home map).
///
/// - Streets: **OpenFreeMap** (https://openfreemap.org) — free, no API key, no
///   usage limits, commercial use allowed. Vector tiles + MapLibre style.
///   The same light style is used in any phone theme.
/// - Satellite: **Esri World Imagery** — high resolution (houses, streets),
///   no API key needed by the public tile endpoint.
///
/// ⚠️ **Satellite = DEVELOPMENT / DEMO ONLY.** Esri's imagery is licensed under
/// the Esri Master License Agreement, which requires an ArcGIS account for apps
/// in production. Before going to production, either create a (free tier)
/// ArcGIS Location Platform account and use its authenticated URL, or switch to
/// the free, commercial-safe but low-resolution EOX layer (2016, CC BY 4.0):
/// `https://tiles.maps.eox.at/wmts/1.0.0/s2cloudless_3857/default/g/{z}/{y}/{x}.jpg`
/// (max zoom 14). Both are just a `--dart-define`, no code changes.
///
/// Both can be swapped per environment without touching code:
///
/// ```
/// flutter run \
///   --dart-define=MAP_STYLE_URL=https://tiles.openfreemap.org/styles/bright \
///   --dart-define=MAP_SATELLITE_TILES_URL=https://.../{z}/{y}/{x}.jpg
/// ```
class MapConfig {
  MapConfig._();

  /// Streets style (light; also used in dark mode).
  static const String styleUrl = String.fromEnvironment(
    'MAP_STYLE_URL',
    defaultValue: 'https://tiles.openfreemap.org/styles/liberty',
  );

  /// XYZ template of the satellite tiles (`{z}/{y}/{x}`, Web Mercator).
  /// Development / demo only — see the class documentation.
  static const String satelliteTilesUrl = String.fromEnvironment(
    'MAP_SATELLITE_TILES_URL',
    defaultValue: 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
  );

  /// Last zoom with real satellite imagery; MapLibre enlarges it beyond.
  /// Use 14 if [satelliteTilesUrl] points to the EOX layer.
  static const int satelliteMaxZoom = int.fromEnvironment(
    'MAP_SATELLITE_MAX_ZOOM',
    defaultValue: 19,
  );

  /// Attributions required by the licenses. They must always be visible.
  static const String streetsAttribution =
      '© OpenFreeMap · © OpenMapTiles · Datos de © OpenStreetMap';
  static const String satelliteAttribution = String.fromEnvironment(
    'MAP_SATELLITE_ATTRIBUTION',
    defaultValue: 'Fuente: Esri, Vantor, Earthstar Geographics y la comunidad de usuarios de GIS',
  );

  /// Initial camera when the user's location is unknown: San José, Costa Rica.
  static const double fallbackLatitude = 9.9281;
  static const double fallbackLongitude = -84.0907;
  static const double fallbackZoom = 12;

  /// Zoom used when centering the map on the user.
  static const double userZoom = 15;

  /// MapLibre style for [mode]: a URL (streets) or a raw JSON style (satellite).
  static String styleFor(MapMode mode) =>
      mode == MapMode.satellite ? satelliteStyleJson : styleUrl;

  static String attributionFor(MapMode mode) =>
      mode == MapMode.satellite ? satelliteAttribution : streetsAttribution;

  /// Minimal MapLibre style with the satellite imagery as a raster source.
  static String get satelliteStyleJson => jsonEncode({
    'version': 8,
    'name': 'SmartBus satellite',
    'sources': {
      'satellite': {
        'type': 'raster',
        'tiles': [satelliteTilesUrl],
        'tileSize': 256,
        'maxzoom': satelliteMaxZoom,
        'attribution': satelliteAttribution,
      },
    },
    'layers': [
      {
        'id': 'background',
        'type': 'background',
        'paint': {'background-color': '#0B1F14'},
      },
      {'id': 'satellite', 'type': 'raster', 'source': 'satellite'},
    ],
  });
}
