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

  /// Height of the illustrated area below the title row.
  static const artHeight = 92.0;
  static const compactArtHeight = 64.0;

  /// Depth of the bottom wave (see [_WaveClipper]).
  static const _waveDepth = 44.0;
  static const _compactWaveDepth = 28.0;

  bool get _isDriver => type == SmartBusUserType.driver;

  LinearGradient get _gradient => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: _isDriver
        ? const [SmartBusColors.azulCorporativo, SmartBusColors.azulPrincipal]
        : const [
            SmartBusColors.verdePasajero,
            SmartBusColors.verdePasajeroClaro,
          ],
  );

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top;
    final art = compact ? compactArtHeight : artHeight;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      // Light status bar icons over the gradient.
      value: SystemUiOverlayStyle.light,
      child: ColoredBox(
        color: backgroundColor,
        child: ClipPath(
          clipper: _WaveClipper(
            depth: compact ? _compactWaveDepth : _waveDepth,
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(gradient: _gradient),
            child: SizedBox(
              key: const Key('smartbus_header'),
              width: double.infinity,
              height: topInset + titleBarHeight + art,
              child: Stack(
                children: [
                  // Decoration (route, grid, pin, bus): ignored by screen
                  // readers.
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    height: art,
                    child: ExcludeSemantics(
                      child: _Illustration(isDriver: _isDriver),
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
// Title bar
// ---------------------------------------------------------------------------

class _TitleBar extends StatelessWidget {
  const _TitleBar({required this.title, this.subtitle, this.onBack});

  final String title;
  final String? subtitle;
  final VoidCallback? onBack;

  static const _sideSlot = 56.0;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: _sideSlot,
          child: onBack == null
              ? null
              : Center(child: _BackButton(onPressed: onBack!)),
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
  const _BackButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: SmartBusColors.blanco.withValues(alpha: 0.16),
      shape: const CircleBorder(),
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
// Illustration
// ---------------------------------------------------------------------------

/// Normalized route (0..1 of the illustration box). Shared by the painter and
/// the widgets placed on it (pin, bus) so they always line up.
class _Route {
  static const start = Offset(0.04, 0.42);
  static const end = Offset(0.88, 0.50);

  static const stops = [Offset(0.24, 0.36), Offset(0.50, 0.54)];

  /// Where the bus sits on the route (driver only).
  static const bus = Offset(0.715, 0.60);

  static Path path(Size s) {
    Offset p(Offset o) => Offset(o.dx * s.width, o.dy * s.height);
    return Path()
      ..moveTo(p(start).dx, p(start).dy)
      ..cubicTo(
        0.14 * s.width,
        0.22 * s.height,
        0.26 * s.width,
        0.30 * s.height,
        p(stops[1]).dx,
        p(stops[1]).dy,
      )
      ..cubicTo(
        0.66 * s.width,
        0.70 * s.height,
        0.78 * s.width,
        0.42 * s.height,
        p(end).dx,
        p(end).dy,
      );
  }
}

class _Illustration extends StatelessWidget {
  const _Illustration({required this.isDriver});

  static const _busAsset = 'assets/images/header/header_bus.png';

  /// Width / height of `header_bus.png` (246×145 at 1x).
  static const _busAspectRatio = 246 / 145;

  final bool isDriver;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        // Icons scale with the box height so the compact variant stays tidy.
        final pinSize = (size.height * 0.42).clamp(20.0, 40.0);
        // Bus image height (wifi included); its width follows the image.
        final busHeight = (size.height * 0.62).clamp(34.0, 56.0);
        final busWidth = busHeight * _busAspectRatio;
        final pin = Offset(
          _Route.end.dx * size.width,
          _Route.end.dy * size.height,
        );
        final bus = Offset(
          _Route.bus.dx * size.width,
          _Route.bus.dy * size.height,
        );

        return Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _IllustrationPainter(isDriver: isDriver),
              ),
            ),
            if (isDriver)
              Positioned(
                // Bus "drives" on the route: its wheels rest on the line.
                left: bus.dx - busWidth / 2,
                top: bus.dy - busHeight * 0.92,
                width: busWidth,
                height: busHeight,
                child: Image.asset(
                  _busAsset,
                  key: const Key('smartbus_header_bus'),
                  fit: BoxFit.contain,
                  // A missing asset must never break the header.
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

/// Map grid, inner light wave, dashed route, stops and the pin's rings.
class _IllustrationPainter extends CustomPainter {
  const _IllustrationPainter({required this.isDriver});

  /// Driver: tire tracks (the one who drives). Passenger: map grid (the one
  /// who looks at the map).
  final bool isDriver;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final white = SmartBusColors.blanco;

    if (isDriver) {
      _paintTireTracks(canvas, size);
    } else {
      _paintMapGrid(canvas, size);
    }

    // Lighter inner wave (depth, like the reference design).
    final innerWave = Path()
      ..moveTo(0, h * 0.30)
      ..cubicTo(w * 0.20, h * 0.05, w * 0.38, h * 0.25, w * 0.55, h * 0.55)
      ..cubicTo(w * 0.70, h * 0.80, w * 0.85, h * 0.15, w, h * 0.05)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(innerWave, Paint()..color = white.withValues(alpha: 0.08));

    // Dashed route.
    final route = _Route.path(size);
    final dash = Paint()
      ..color = white.withValues(alpha: 0.85)
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    for (final PathMetric metric in route.computeMetrics()) {
      const on = 9.0, off = 7.0;
      for (var d = 0.0; d < metric.length; d += on + off) {
        canvas.drawPath(metric.extractPath(d, d + on), dash);
      }
    }

    // Stops: soft halo + white dot.
    for (final stop in _Route.stops) {
      final c = Offset(stop.dx * w, stop.dy * h);
      canvas.drawCircle(c, 9, Paint()..color = white.withValues(alpha: 0.22));
      canvas.drawCircle(c, 5, Paint()..color = white);
    }

    // Rings under the destination pin.
    final end = Offset(_Route.end.dx * w, _Route.end.dy * h);
    final ring = Paint()
      ..color = white.withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;
    canvas.drawOval(Rect.fromCenter(center: end, width: 30, height: 10), ring);
    canvas.drawOval(
      Rect.fromCenter(center: end, width: 46, height: 16),
      ring..color = white.withValues(alpha: 0.25),
    );
  }

  /// Faint map grid in the top-right corner.
  void _paintMapGrid(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final grid = Paint()
      ..color = SmartBusColors.blanco.withValues(alpha: 0.07)
      ..strokeWidth = 2;
    for (var i = 0; i < 5; i++) {
      final x = w * (0.70 + i * 0.08);
      canvas.drawLine(Offset(x, -h * 0.2), Offset(x - w * 0.10, h), grid);
    }
    for (var i = 0; i < 3; i++) {
      final y = h * (0.10 + i * 0.30);
      canvas.drawLine(Offset(w * 0.66, y), Offset(w, y - h * 0.18), grid);
    }
  }

  /// Two parallel tire tracks entering from the top-right corner and curving
  /// toward the center, fading out as they go. Each track is a row of short
  /// slanted tread blocks oriented along the curve.
  void _paintTireTracks(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Center line between both wheels (starts just outside the corner).
    final center = Path()
      ..moveTo(w * 1.03, -h * 0.30)
      ..cubicTo(w * 0.86, h * 0.05, w * 0.72, h * 0.10, w * 0.50, h * 0.36);

    final gap = (h * 0.11).clamp(6.0, 11.0); // half the distance between wheels
    final blockAlong = (h * 0.045).clamp(
      3.0,
      4.5,
    ); // block size along the track
    final blockAcross = (h * 0.10).clamp(6.0, 9.0); // tire width
    const step = 7.0; // tread spacing
    const maxAlpha = 0.16;
    const slant = 0.35; // radians: diagonal tread blocks

    final block = Paint()..style = PaintingStyle.fill;
    final rect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset.zero,
        width: blockAlong,
        height: blockAcross,
      ),
      const Radius.circular(1),
    );

    for (final metric in center.computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += step) {
        final tangent = metric.getTangentForOffset(d);
        if (tangent == null) continue;
        // Fully visible at the corner, gone at the center (eased, so most of
        // the track stays visible and only the last part fades).
        final t = d / metric.length;
        final fade = 1 - t * t;
        block.color = SmartBusColors.blanco.withValues(alpha: maxAlpha * fade);

        final normal = Offset(-tangent.vector.dy, tangent.vector.dx);
        for (final side in const [-1.0, 1.0]) {
          canvas
            ..save()
            ..translate(
              tangent.position.dx + normal.dx * gap * side,
              tangent.position.dy + normal.dy * gap * side,
            )
            ..rotate(-tangent.angle + slant * side)
            ..drawRRect(rect, block)
            ..restore();
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _IllustrationPainter oldDelegate) =>
      oldDelegate.isDriver != isDriver;
}

// ---------------------------------------------------------------------------
// Wave
// ---------------------------------------------------------------------------

/// Wavy bottom edge. Its [depth] is fixed in pixels (not a fraction of the
/// header) so the illustration keeps the same room above the wave in both the
/// regular and the compact variant; horizontally it stretches with the width.
class _WaveClipper extends CustomClipper<Path> {
  const _WaveClipper({required this.depth});

  /// Distance from the highest point of the wave to the bottom edge.
  final double depth;

  @override
  Path getClip(Size size) {
    final w = size.width;
    final h = size.height;
    // 0 = bottom edge, 1 = highest point of the wave.
    double y(double t) => h - depth * t;
    return Path()
      ..lineTo(w, 0)
      ..lineTo(w, y(0.54))
      ..cubicTo(w * 0.82, y(1.0), w * 0.68, y(0.0), w * 0.48, y(0.15))
      ..cubicTo(w * 0.28, y(0.31), w * 0.14, y(0.85), 0, y(0.62))
      ..close();
  }

  @override
  bool shouldReclip(covariant _WaveClipper oldClipper) =>
      oldClipper.depth != depth;
}
