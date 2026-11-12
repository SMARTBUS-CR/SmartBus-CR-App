import 'package:flutter/material.dart';

import '../../../core/config/map_config.dart';
import '../../../core/location/location_service.dart';
import '../../../core/theme.dart';

/// Colors of the floating elements over the map.
///
/// This is the SmartBus map **design**, not a dark mode: it does not change with
/// the phone's theme.
class MapOverlayColors {
  const MapOverlayColors._({
    required this.surface,
    required this.onSurface,
    required this.muted,
    required this.accent,
    this.gradient,
  });

  /// Background of the element.
  final Color surface;

  /// Main text.
  final Color onSurface;

  /// Secondary text (hints, descriptions).
  final Color muted;

  /// Icons and highlighted actions.
  final Color accent;

  /// Optional background gradient (overrides [surface] where supported).
  final Gradient? gradient;

  /// Search bar, chips and map buttons: the green of the passenger header.
  static const smartBus = MapOverlayColors._(
    surface: SmartBusColors.verdePasajero,
    onSurface: SmartBusColors.blanco,
    muted: Color(0xD9FFFFFF), // white 85%
    accent: SmartBusColors.blanco,
    gradient: LinearGradient(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      colors: [
        SmartBusColors.verdePasajeroIntenso,
        SmartBusColors.verdePasajero,
        SmartBusColors.verdePasajeroClaro,
      ],
    ),
  );

  /// Search bar and its results panel: white with dark text and green icons.
  static const searchBar = MapOverlayColors._(
    surface: SmartBusColors.blanco,
    onSurface: SmartBusColors.grisOscuro,
    muted: Color(0xFF6B7280),
    accent: SmartBusColors.verdePasajero,
  );

  /// Bottom sheet (`Hola, <nombre>`): white with dark text and green icons.
  static const sheet = MapOverlayColors._(
    surface: SmartBusColors.blanco,
    onSurface: SmartBusColors.grisOscuro,
    muted: Color(0xFF6B7280),
    accent: SmartBusColors.verdePasajero,
  );
}

const _cardRadius = 28.0;

List<BoxShadow> _shadow(double opacity) => [
  BoxShadow(
    color: Colors.black.withValues(alpha: opacity),
    blurRadius: 10,
    offset: const Offset(0, 3),
  ),
];

/// Floating search field with the SmartBus logo ("¿A dónde vas?").
///
/// The user types right here (no extra screen). While searching, the logo turns
/// into a back arrow that closes the search, and a clear button empties it.
class MapSearchBar extends StatelessWidget {
  const MapSearchBar({
    super.key,
    required this.colors,
    required this.controller,
    required this.focusNode,
    required this.searching,
    required this.onClose,
  });

  final MapOverlayColors colors;
  final TextEditingController controller;
  final FocusNode focusNode;

  /// `true` while the field is focused or has text.
  final bool searching;

  /// Closes the search: clears the text and hides the keyboard.
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 54,
      decoration: BoxDecoration(
        color: colors.surface,
        gradient: colors.gradient,
        borderRadius: BorderRadius.circular(_cardRadius),
        boxShadow: _shadow(0.18),
      ),
      child: Row(
        children: [
          const SizedBox(width: 6),
          if (searching)
            IconButton(
              key: const Key('map-search-close'),
              tooltip: 'Cerrar búsqueda',
              icon: Icon(Icons.arrow_back, color: colors.accent),
              onPressed: onClose,
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: ClipOval(
                child: Image.asset(
                  'assets/icons/icon_circle.png',
                  width: 30,
                  height: 30,
                  errorBuilder: (_, _, _) =>
                      Icon(Icons.directions_bus, color: colors.accent),
                ),
              ),
            ),
          const SizedBox(width: 6),
          Expanded(
            child: TextField(
              key: const Key('map-search-field'),
              controller: controller,
              focusNode: focusNode,
              textInputAction: TextInputAction.search,
              style: TextStyle(color: colors.onSurface, fontSize: 16),
              cursorColor: colors.accent,
              decoration: InputDecoration(
                hintText: '¿A dónde vas?',
                hintStyle: TextStyle(color: colors.muted, fontSize: 16),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
                isCollapsed: true,
              ),
            ),
          ),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (context, value, _) => value.text.isEmpty
                ? Padding(
                    padding: const EdgeInsets.only(right: 16),
                    child: Icon(Icons.search, color: colors.accent),
                  )
                : IconButton(
                    key: const Key('map-search-clear'),
                    tooltip: 'Borrar',
                    icon: Icon(Icons.close, color: colors.accent),
                    onPressed: controller.clear,
                  ),
          ),
        ],
      ),
    );
  }
}

/// Results panel under the search field. Route search is not available yet,
/// so it always says "próximamente" (echoing what the user typed).
class MapSearchResults extends StatelessWidget {
  const MapSearchResults({
    super.key,
    required this.colors,
    required this.query,
  });

  final MapOverlayColors colors;
  final String query;

  @override
  Widget build(BuildContext context) {
    final text = query.trim();
    final detail = text.isEmpty
        ? 'Escribe una ruta, parada o destino.'
        : 'Pronto verás aquí las rutas para "$text".';

    return Container(
      key: const Key('map-search-results'),
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: _shadow(0.12),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: colors.accent.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.alt_route, color: colors.accent),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Búsqueda de rutas: próximamente',
                  style: TextStyle(
                    color: colors.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  detail,
                  style: TextStyle(color: colors.muted, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Quick-access chip under the search bar.
class MapQuickChip {
  const MapQuickChip(this.icon, this.label);

  final IconData icon;
  final String label;
}

/// Horizontal row of quick-access chips (SmartBus shortcuts).
class MapQuickChips extends StatelessWidget {
  const MapQuickChips({
    super.key,
    required this.chips,
    required this.colors,
    required this.onTap,
  });

  final List<MapQuickChip> chips;
  final MapOverlayColors colors;
  final ValueChanged<MapQuickChip> onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: chips.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final chip = chips[index];
          return Material(
            color: colors.surface,
            borderRadius: BorderRadius.circular(20),
            elevation: 2,
            shadowColor: Colors.black26,
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () => onTap(chip),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  children: [
                    Icon(chip.icon, size: 18, color: colors.accent),
                    const SizedBox(width: 6),
                    Text(
                      chip.label,
                      style: TextStyle(
                        color: colors.onSurface,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Non-blocking notice shown when the location cannot be used.
class LocationAccessBanner extends StatelessWidget {
  const LocationAccessBanner({
    super.key,
    required this.access,
    required this.colors,
    required this.onAction,
  });

  final LocationAccess access;
  final MapOverlayColors colors;
  final VoidCallback onAction;

  String get _message => switch (access) {
    LocationAccess.serviceDisabled =>
      'Tu ubicación está desactivada. Actívala para ver dónde estás.',
    LocationAccess.deniedForever =>
      'Permite el acceso a tu ubicación desde los ajustes de la app.',
    _ => 'Permite el acceso a tu ubicación para ver dónde estás.',
  };

  String get _action => switch (access) {
    LocationAccess.serviceDisabled => 'Activar',
    LocationAccess.deniedForever => 'Ajustes',
    _ => 'Permitir',
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('location-access-banner'),
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(14),
        boxShadow: _shadow(0.12),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.location_off_outlined,
            color: SmartBusColors.advertencia,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _message,
              style: TextStyle(color: colors.onSurface, fontSize: 13),
            ),
          ),
          TextButton(
            onPressed: onAction,
            child: Text(
              _action,
              style: TextStyle(
                color: colors.accent,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Round "my location" button in SmartBus colors.
class MyLocationButton extends StatelessWidget {
  const MyLocationButton({
    super.key,
    required this.colors,
    required this.active,
    required this.onPressed,
  });

  final MapOverlayColors colors;

  /// `true` when the location is available (filled icon).
  final bool active;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton(
      key: const Key('my-location-button'),
      heroTag: 'my-location',
      tooltip: 'Mi ubicación',
      backgroundColor: colors.surface,
      foregroundColor: colors.accent,
      elevation: 4,
      shape: const CircleBorder(),
      onPressed: onPressed,
      child: Icon(active ? Icons.my_location : Icons.location_searching),
    );
  }
}

/// Small round button that switches between the streets and satellite maps.
class MapModeButton extends StatelessWidget {
  const MapModeButton({
    super.key,
    required this.colors,
    required this.mode,
    required this.onPressed,
  });

  final MapOverlayColors colors;
  final MapMode mode;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final satellite = mode == MapMode.satellite;
    return FloatingActionButton.small(
      key: const Key('map-mode-button'),
      heroTag: 'map-mode',
      tooltip: satellite ? 'Ver mapa' : 'Ver satélite',
      backgroundColor: colors.surface,
      foregroundColor: colors.accent,
      elevation: 4,
      shape: const CircleBorder(),
      onPressed: onPressed,
      child: Icon(
        satellite ? Icons.map_outlined : Icons.satellite_alt_outlined,
      ),
    );
  }
}

/// Attribution required by the map data licenses (OpenStreetMap / OpenFreeMap /
/// EOX). Always visible, but discreet: small text with no background, with a
/// thin halo so it stays readable over the map.
class MapAttribution extends StatelessWidget {
  const MapAttribution({super.key, required this.mode});

  final MapMode mode;

  @override
  Widget build(BuildContext context) {
    final satellite = mode == MapMode.satellite;
    final textColor = satellite
        ? SmartBusColors.blanco.withValues(alpha: 0.85)
        : SmartBusColors.grisOscuro.withValues(alpha: 0.55);
    final haloColor = satellite
        ? Colors.black.withValues(alpha: 0.5)
        : SmartBusColors.blanco.withValues(alpha: 0.8);

    return Text(
      MapConfig.attributionFor(mode),
      key: const Key('map-attribution'),
      style: TextStyle(
        fontSize: 8,
        color: textColor,
        shadows: [Shadow(color: haloColor, blurRadius: 2)],
      ),
    );
  }
}

/// Shell of the draggable bottom sheet: white card with a drag handle and a
/// scrollable [children] list (routes list or the selected route).
class MapBottomSheetContent extends StatelessWidget {
  const MapBottomSheetContent({
    super.key,
    required this.colors,
    required this.scrollController,
    required this.children,
  });

  final MapOverlayColors colors;
  final ScrollController scrollController;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: colors.surface,
      elevation: 8,
      shadowColor: Colors.black38,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: ListView(
        controller: scrollController,
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: colors.muted.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }
}

/// "Hola, {nombre}" + "¿Qué bus tomas hoy?" at the top of the bottom sheet.
class SheetGreeting extends StatelessWidget {
  const SheetGreeting({super.key, required this.colors, this.firstName});

  final MapOverlayColors colors;
  final String? firstName;

  @override
  Widget build(BuildContext context) {
    final greeting = firstName == null || firstName!.isEmpty
        ? 'Hola'
        : 'Hola, $firstName';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          greeting,
          style: TextStyle(
            color: colors.onSurface,
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '¿Qué bus tomas hoy?',
          style: TextStyle(color: colors.muted, fontSize: 14),
        ),
      ],
    );
  }
}
