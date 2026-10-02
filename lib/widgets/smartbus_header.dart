import 'dart:ui' as ui;
import 'dart:ui' show PathMetric;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme.dart';

/// Role the header is drawn for: sets the gradient and the illustration.
enum SmartBusUserType { driver, passenger }

/// Branded header shared by every internal screen (after login).
///
/// Everything is drawn in code so it adapts to any width and height:
/// theme gradient, wavy bottom edge, dashed route with stops, a destination
/// pin with rings, a faint map grid and — for drivers — a bus.
///
/// ```
/// ┌──────────────────────────────────┐ ← status bar (light icons)
/// │ (←)          Mi Cuenta           │
/// │  - - -●- - - - - - - 🚌 - - 📍   │
/// ╰────────╮               ╭─────────╯
/// ```
///
/// The bus is a PNG illustration (`assets/images/header/header_bus.png`, with
/// 2.0x/3.0x variants); everything else is drawn.
class SmartBusHeader extends StatelessWidget {
  const SmartBusHeader({
    super.key,
    required this.title,
    required this.type,
    this.subtitle,
    this.onBack,
    this.compact = false,
    this.backgroundColor = SmartBusColors.blanco,
  });

  final String title;
  final SmartBusUserType type;

  /// Optional second line under the title (e.g. "Viaje #a1b2").
  final String? subtitle;

  /// Shows a back button when provided.
  final VoidCallback? onBack;

  /// Shorter illustration area, for screens that need room (maps).
  final bool compact;

  /// Color under the wave: must match the content right below the header.
  final Color backgroundColor;

  /// Height of the title row (below the status bar).
  static const titleBarHeight = 56.0;

  /// Passenger: shorter header; the route and pin share the title row.
  static const passengerArtHeight = 46.0;
  static const passengerCompactArtHeight = 34.0;

  /// Passenger with a subtitle: the drawing moves below the title row so the
  /// route never crosses the text, so it needs its own room.
  static const passengerSubtitleArtHeight = 56.0;
  static const passengerSubtitleCompactArtHeight = 46.0;

  /// Depth of the bottom wave (see [_PassengerWaveClipper]).
  static const _passengerWaveDepth = 24.0;
  static const _passengerCompactWaveDepth = 22.0;

  bool get _isDriver => type == SmartBusUserType.driver;

  _HeaderStyle get _style =>
      _isDriver ? _HeaderStyle.driver : _HeaderStyle.passenger;

  LinearGradient get _gradient => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: _style.gradient,
  );

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top;
    // Driver and passenger share the same composition: only the palette and
    // the bus change. A subtitle gets a separate art area so the route never
    // crosses the text.
    final drawBehindTitle = subtitle == null;
    final double art = switch ((drawBehindTitle, compact)) {
      (true, false) => passengerArtHeight,
      (true, true) => passengerCompactArtHeight,
      (false, false) => passengerSubtitleArtHeight,
      (false, true) => passengerSubtitleCompactArtHeight,
    };
    final wave = _PassengerWaveClipper(
      depth: compact ? _passengerCompactWaveDepth : _passengerWaveDepth,
    );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      // Light status bar icons over the gradient.
      value: SystemUiOverlayStyle.light,
      child: ColoredBox(
        color: backgroundColor,
        child: ClipPath(
          clipper: wave,
          child: DecoratedBox(
            decoration: BoxDecoration(gradient: _gradient),
            child: SizedBox(
              key: const Key('smartbus_header'),
              width: double.infinity,
              height: topInset + titleBarHeight + art,
              child: Stack(
                children: [
                  // Decoration (route, grid, pin, bus): ignored by screen
                  // readers. The regular driver and passenger compositions
                  // both sit behind the title row.
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    top: drawBehindTitle ? topInset : null,
                    height: drawBehindTitle ? null : art,
                    child: ExcludeSemantics(
                      child: _PassengerIllustration(
                        style: _style,
                        showBus: _isDriver,
                      ),
                    ),
                  ),
                  Positioned(
                    top: topInset,
                    left: 0,
                    right: 0,
                    height: titleBarHeight,
                    child: _TitleBar(
                      title: title,
                      subtitle: subtitle,
                      onBack: onBack,
                      backBorder: _style.backBorder,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Colors per role
// ---------------------------------------------------------------------------

/// Colors of the gradient and the drawn illustration for each role.
class _HeaderStyle {
  const _HeaderStyle({
    required this.gradient,
    required this.innerWave,
    required this.route,
    required this.stop,
    required this.stopHalo,
    required this.rings,
    required this.grid,
    this.frontHill = const [Color(0x00FFFFFF), Color(0x00FFFFFF)],
    this.glow,
    this.backBorder,
  });

  /// Lighter hill resting on the bottom wave, left → right (passenger).
  final List<Color> frontHill;

  /// Background, top-left → bottom-right.
  final List<Color> gradient;

  /// Lighter inner wave, left → right.
  final List<Color> innerWave;

  /// Dashed route.
  final Color route;

  /// Stop dot and its soft halo.
  final Color stop;
  final Color stopHalo;

  /// Inner ring under the pin (the outer ring is fainter).
  final Color rings;

  /// Map grid (passenger).
  final Color grid;

  /// Radial light behind the destination pin, if any.
  final Color? glow;

  /// Thin border of the back button, if any.
  final Color? backBorder;

  /// Blue driver header with the extracted SmartBus blue palette.
  static const driver = _HeaderStyle(
    gradient: [
      SmartBusColors.azulDriverCobalto,
      SmartBusColors.azulDriverBrillante,
      SmartBusColors.azulDriverIndigo,
      SmartBusColors.azulDriverMarino,
      SmartBusColors.azulDriverElectrico,
    ],
    innerWave: [Color(0x66005AC5), Color(0x520077E0)],
    route: Color(0xD9FFFFFF),
    stop: SmartBusColors.blanco,
    stopHalo: Color(0x38FFFFFF),
    rings: Color(0x8CFFFFFF),
    grid: Color(0x12FFFFFF),
  );

  /// Emerald header with jade highlights and mint drawing, from the approved
  /// passenger design (#008163, #01856D, #029775, #049473, #0BD961).
  static const passenger = _HeaderStyle(
    gradient: [
      SmartBusColors.verdePasajeroIntenso,
      SmartBusColors.verdePasajero,
      SmartBusColors.verdePasajeroClaro,
    ],
    innerWave: [Color(0xA6049473), Color(0x9922AE8A)],
    frontHill: [Color(0x5926B58C), Color(0x8033C79B)],
    route: Color(0xBFC8F5DA),
    stop: Color(0xFFD9FBE6),
    stopHalo: Color(0x4D0BD961),
    rings: Color(0xB3C8F5DA),
    grid: Color(0x40C8F5DA),
    glow: Color(0x400BD961),
    backBorder: Color(0x59FFFFFF),
  );
}

// ---------------------------------------------------------------------------
// Title bar
// ---------------------------------------------------------------------------

class _TitleBar extends StatelessWidget {
  const _TitleBar({
    required this.title,
    this.subtitle,
    this.onBack,
    this.backBorder,
  });

  final String title;
  final String? subtitle;
  final VoidCallback? onBack;
  final Color? backBorder;

  static const _sideSlot = 56.0;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: _sideSlot,
          child: onBack == null
              ? null
              : Center(
                  child: _BackButton(onPressed: onBack!, border: backBorder),
                ),
        ),
        Expanded(
          child: Semantics(
            header: true,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: SmartBusColors.blanco,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: SmartBusColors.blanco.withValues(alpha: 0.85),
                      fontSize: 13,
                    ),
                  ),
              ],
            ),
          ),
        ),
        // Keeps the title centered whether or not there is a back button.
        const SizedBox(width: _sideSlot),
      ],
    );
  }
}

class _BackButton extends StatelessWidget {
  const _BackButton({required this.onPressed, this.border});

  final VoidCallback onPressed;
  final Color? border;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: SmartBusColors.blanco.withValues(alpha: 0.16),
      shape: CircleBorder(
        side: border == null
            ? BorderSide.none
            : BorderSide(color: border!, width: 1.2),
      ),
      child: IconButton(
        tooltip: 'Volver',
        onPressed: onPressed,
        icon: const Icon(
          Icons.arrow_back_rounded,
          color: SmartBusColors.blanco,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Passenger illustration
// ---------------------------------------------------------------------------

/// Passenger route, normalized to the area below the status bar (title row
/// included). It leaves the back button at the title's height, dips through
/// the middle and climbs back to the destination pin on the right — the pin
/// sits next to the title, as in the approved design.
class _PassengerRoute {
  /// Fixed horizontal start (logical px): right edge of the back button slot,
  /// so the line never runs under the button on narrow phones.
  static const startX = 54.0;
  static const startY = 0.29;

  static const stop = Offset(0.30, 0.47);
  static const end = Offset(0.87, 0.56);

  static Path path(Size s) {
    final w = s.width;
    final h = s.height;
    return Path()
      ..moveTo(startX, startY * h)
      ..cubicTo(
        w * 0.20,
        h * 0.27,
        w * 0.25,
        h * 0.37,
        stop.dx * w,
        stop.dy * h,
      )
      ..cubicTo(w * 0.37, h * 0.60, w * 0.42, h * 0.74, w * 0.51, h * 0.74)
      ..cubicTo(w * 0.63, h * 0.74, w * 0.74, h * 0.52, end.dx * w, end.dy * h);
  }
}

/// Passenger illustration: drawn over the whole area below the status bar
/// (behind the title row) with only the destination pin as a widget.
class _PassengerIllustration extends StatelessWidget {
  const _PassengerIllustration({required this.style, this.showBus = false});

  final _HeaderStyle style;
  final bool showBus;

  static const _busAsset = 'assets/images/header/header_bus.png';
  static const _busAspectRatio = 246 / 145;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        final pinSize = (size.height * 0.32).clamp(22.0, 34.0);
        final pin = Offset(
          _PassengerRoute.end.dx * size.width,
          _PassengerRoute.end.dy * size.height,
        );
        final busHeight = (size.height * 0.42).clamp(28.0, 46.0);
        final busWidth = busHeight * _busAspectRatio;
        final bus = Offset(size.width * 0.76, size.height * 0.56);

        return Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: CustomPaint(painter: _PassengerPainter(style: style)),
            ),
            if (showBus)
              Positioned(
                left: bus.dx - busWidth / 2,
                top: bus.dy - busHeight * 0.92,
                width: busWidth,
                height: busHeight,
                child: Image.asset(
                  _busAsset,
                  key: const Key('smartbus_header_bus'),
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => Icon(
                    Icons.directions_bus_rounded,
                    size: busHeight * 0.8,
                    color: SmartBusColors.blanco,
                  ),
                ),
              ),
            Positioned(
              // Pin tip on the end of the route.
              left: pin.dx - pinSize / 2,
              top: pin.dy - pinSize * 0.95,
              child: Icon(
                Icons.location_on_rounded,
                key: const Key('smartbus_header_pin'),
                size: pinSize,
                color: SmartBusColors.blanco,
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Layered green hills with the map grid fused into them, glow, dashed route,
/// one stop and the pin's rings.
class _PassengerPainter extends CustomPainter {
  const _PassengerPainter({required this.style});

  final _HeaderStyle style;

  /// Ridge of the back hill: low on the left, a dip in the middle, then a
  /// sweep up to the top-right corner. [dy] shifts it down (grid contours).
  static Path _backRidge(Size s, {double dy = 0}) {
    final w = s.width;
    final h = s.height;
    return Path()
      ..moveTo(0, h * 0.66 + dy)
      ..cubicTo(
        w * 0.18,
        h * 0.36 + dy,
        w * 0.34,
        h * 0.30 + dy,
        w * 0.50,
        h * 0.54 + dy,
      )
      ..cubicTo(
        w * 0.64,
        h * 0.74 + dy,
        w * 0.80,
        h * 0.12 + dy,
        w,
        h * 0.02 + dy,
      );
  }

  /// Closes a ridge down to the bottom edge, as a fillable hill.
  static Path _hill(Path ridge, Size s) => Path.from(ridge)
    ..lineTo(s.width, s.height)
    ..lineTo(0, s.height)
    ..close();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final end = Offset(_PassengerRoute.end.dx * w, _PassengerRoute.end.dy * h);

    // Back hill: the big diagonal swoosh.
    final backHill = _hill(_backRidge(size), size);
    canvas.drawPath(
      backHill,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset.zero,
          Offset(w, 0),
          style.innerWave,
        ),
    );

    // Map grid living inside the back hill, so it follows its shape.
    canvas
      ..save()
      ..clipPath(backHill);
    _paintMapGrid(canvas, size);
    canvas.restore();

    // Front hill: lighter band resting on the bottom wave.
    final frontHill = Path()
      ..moveTo(0, h * 0.80)
      ..cubicTo(w * 0.14, h * 0.66, w * 0.24, h * 0.62, w * 0.36, h * 0.70)
      ..cubicTo(w * 0.48, h * 0.80, w * 0.62, h * 0.86, w * 0.74, h * 0.74)
      ..cubicTo(w * 0.86, h * 0.62, w * 0.94, h * 0.58, w, h * 0.60)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(
      frontHill,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset.zero,
          Offset(w, 0),
          style.frontHill,
        ),
    );

    // Soft light around the destination.
    final glow = style.glow;
    if (glow != null) {
      canvas.drawCircle(
        end,
        h * 0.8,
        Paint()
          ..shader = ui.Gradient.radial(end, h * 0.8, [
            glow,
            glow.withValues(alpha: 0),
          ]),
      );
    }

    // Thin dashed route.
    final dash = Paint()
      ..color = style.route
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    for (final PathMetric metric in _PassengerRoute.path(
      size,
    ).computeMetrics()) {
      const on = 7.0, off = 6.0;
      for (var d = 0.0; d < metric.length; d += on + off) {
        canvas.drawPath(metric.extractPath(d, d + on), dash);
      }
    }

    // Single small stop.
    final stop = Offset(
      _PassengerRoute.stop.dx * w,
      _PassengerRoute.stop.dy * h,
    );
    canvas.drawCircle(stop, 7, Paint()..color = style.stopHalo);
    canvas.drawCircle(stop, 4, Paint()..color = style.stop);

    // Rings under the destination pin.
    final ring = Paint()
      ..color = style.rings
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;
    canvas.drawOval(Rect.fromCenter(center: end, width: 26, height: 9), ring);
    canvas.drawOval(
      Rect.fromCenter(center: end, width: 42, height: 14),
      ring..color = style.rings.withValues(alpha: style.rings.a * 0.45),
    );
  }

  /// Map grid fused with the back hill: "streets" are copies of the hill's
  /// ridge (so they bend with it) crossed by slanted avenues, fading out
  /// toward the left. The caller clips it to the hill.
  void _paintMapGrid(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final grid = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..shader = ui.Gradient.linear(Offset(w * 0.40, 0), Offset(w, 0), [
        style.grid.withValues(alpha: 0),
        style.grid,
      ]);

    for (var i = 1; i <= 4; i++) {
      canvas.drawPath(_backRidge(size, dy: h * 0.15 * i), grid);
    }
    for (var i = 0; i < 7; i++) {
      final x = w * (0.52 + i * 0.08);
      canvas.drawLine(Offset(x + w * 0.10, 0), Offset(x - w * 0.06, h), grid);
    }
  }

  @override
  bool shouldRepaint(covariant _PassengerPainter oldDelegate) =>
      oldDelegate.style != style;
}

// ---------------------------------------------------------------------------
// Wave
// ---------------------------------------------------------------------------

/// Passenger bottom edge: low at both sides, two crests (left third and right
/// side) and a shallow dip in the middle, as in the approved design.
class _PassengerWaveClipper extends CustomClipper<Path> {
  const _PassengerWaveClipper({required this.depth});

  /// Distance from the crests to the bottom edge.
  final double depth;

  @override
  Path getClip(Size size) {
    final w = size.width;
    final h = size.height;
    // 0 = bottom edge, 1 = crest.
    double y(double t) => h - depth * t;
    return Path()
      ..lineTo(w, 0)
      ..lineTo(w, y(0.15))
      ..cubicTo(w * 0.95, y(0.55), w * 0.90, y(0.85), w * 0.82, y(0.85))
      ..cubicTo(w * 0.70, y(0.85), w * 0.64, y(0.12), w * 0.53, y(0.12))
      ..cubicTo(w * 0.43, y(0.12), w * 0.38, y(1.0), w * 0.27, y(1.0))
      ..cubicTo(w * 0.15, y(1.0), w * 0.06, y(0.50), 0, y(0.15))
      ..close();
  }

  @override
  bool shouldReclip(covariant _PassengerWaveClipper oldClipper) =>
      oldClipper.depth != depth;
}
