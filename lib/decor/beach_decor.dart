import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

/// Immersive "plage" decor — a paradise tropical shore. Two variants:
///  - 0 "Jour": vivid turquoise lagoon, white sand, lush green coconut palms
///    (with a cluster of coconuts), a distant island, beach foliage, a starfish
///    and seashells, and a few gliding birds. A real postcard.
///  - 1 "Coucher": the same scene at golden hour — warm pink/orange sky, the
///    sun melting on the sea, everything rendered as warm silhouettes.
///
/// Sky, sun, island, sea base, sand, palms and props are static; the sea
/// shimmer, the sun's reflection, the wave wash and the birds animate on top.
/// A "pensée" (tap) sends a soft sparkle across the water. Pure Canvas.
///
/// Fronds are built as explicit tapering polygons (not stroked spokes) so the
/// palms read as full, lush leaves.
class BeachDecor extends StatefulWidget {
  const BeachDecor({super.key, this.variant = 0, this.child});

  final int variant;
  final Widget? child;

  @override
  State<BeachDecor> createState() => _BeachDecorState();
}

const double _horizon = 0.50;

class _BeachDecorState extends State<BeachDecor>
    with SingleTickerProviderStateMixin {
  final _model = _BeachModel();
  late final Ticker _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((e) {
      _model.time = e.inMicroseconds / 1e6;
      _model.notify();
    })..start();
  }

  void _sparkle() {
    _model.sparkle = _model.time;
    HapticFeedback.lightImpact();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _model.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cfg = widget.variant == 0 ? _day : _sunset;
    return Stack(
      children: [
        Positioned.fill(
          child: RepaintBoundary(child: CustomPaint(painter: _BeachBgPainter(cfg))),
        ),
        Positioned.fill(
          child: RepaintBoundary(
            child: CustomPaint(painter: _BeachFxPainter(model: _model, cfg: cfg)),
          ),
        ),
        Positioned.fill(
          child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: _sparkle),
        ),
        if (widget.child != null) Positioned.fill(child: widget.child!),
      ],
    );
  }
}

class _BeachConfig {
  const _BeachConfig({
    required this.daytime,
    required this.skyTop,
    required this.skyMid,
    required this.skyHorizon,
    required this.seaFar,
    required this.seaNear,
    required this.shallow,
    required this.sandFar,
    required this.sandNear,
    required this.sun,
    required this.sunGlow,
    required this.sunX,
    required this.sunY,
    required this.frondLit,
    required this.frondDark,
    required this.trunk,
    required this.island,
  });

  final bool daytime;
  final Color skyTop;
  final Color skyMid;
  final Color skyHorizon;
  final Color seaFar;
  final Color seaNear;
  final Color shallow; // pale lagoon band near the shore
  final Color sandFar;
  final Color sandNear;
  final Color sun;
  final Color sunGlow;
  final double sunX;
  final double sunY;
  final Color frondLit; // outer / lit part of the frond
  final Color frondDark; // inner / shadow part of the frond
  final Color trunk;
  final Color island;
}

const _day = _BeachConfig(
  daytime: true,
  skyTop: Color(0xFF2E86C8),
  skyMid: Color(0xFF74BCE6),
  skyHorizon: Color(0xFFD6F1FA),
  seaFar: Color(0xFF1FB6C4),
  seaNear: Color(0xFF0E6F96),
  shallow: Color(0xFF8FE6DC),
  sandFar: Color(0xFFF4E6C2),
  sandNear: Color(0xFFDFC089),
  sun: Color(0xFFFFF4C4),
  sunGlow: Color(0xFFFFE89A),
  sunX: 0.76,
  sunY: 0.16,
  frondLit: Color(0xFF86D262),
  frondDark: Color(0xFF246E36),
  trunk: Color(0xFF8A5A33),
  island: Color(0xFF2E7E62),
);

const _sunset = _BeachConfig(
  daytime: false,
  skyTop: Color(0xFF3A2A5E),
  skyMid: Color(0xFF9A3F72),
  skyHorizon: Color(0xFFFFB25A),
  seaFar: Color(0xFFC56A4E),
  seaNear: Color(0xFF3A2740),
  shallow: Color(0xFFE08A5A),
  sandFar: Color(0xFF7A5060),
  sandNear: Color(0xFF241A26),
  sun: Color(0xFFFFE39A),
  sunGlow: Color(0xFFFF9C46),
  sunX: 0.44,
  sunY: 0.46,
  frondLit: Color(0xFF231528),
  frondDark: Color(0xFF140A14),
  trunk: Color(0xFF160E14),
  island: Color(0xFF231526),
);

class _BeachModel extends ChangeNotifier {
  double time = 0;
  double sparkle = -10;
  void notify() => notifyListeners();
}

class _BeachBgPainter extends CustomPainter {
  const _BeachBgPainter(this.cfg);
  final _BeachConfig cfg;

  // Shoreline (top of the wet sand) per x.
  static double sandLine(double xN) => 0.66 - 0.03 * math.sin(xN * math.pi);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final hy = _horizon * h;
    final sunPos = Offset(cfg.sunX * w, cfg.sunY * h);

    // Sky.
    canvas.drawRect(
      Rect.fromLTRB(0, 0, w, hy + h * 0.02),
      Paint()
        ..shader = ui.Gradient.linear(
          const Offset(0, 0),
          Offset(0, hy),
          [cfg.skyTop, cfg.skyMid, cfg.skyHorizon],
          const [0.0, 0.5, 1.0],
        ),
    );

    // Sun halo + disc.
    canvas.drawCircle(
      sunPos,
      h * 0.30,
      Paint()
        ..blendMode = BlendMode.plus
        ..shader = ui.Gradient.radial(
          sunPos,
          h * 0.30,
          [cfg.sunGlow.withValues(alpha: 0.6), cfg.sunGlow.withValues(alpha: 0)],
        ),
    );
    canvas.drawCircle(sunPos, h * (cfg.daytime ? 0.05 : 0.055), Paint()..color = cfg.sun);

    _paintClouds(canvas, w, h);
    _paintIsland(canvas, w, h, hy);

    // Sea.
    canvas.drawRect(
      Rect.fromLTRB(0, hy, w, sandLine(0) * h),
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, hy),
          Offset(0, sandLine(0) * h),
          [cfg.seaFar, cfg.seaNear],
        ),
    );
    // Pale shallow lagoon band just before the shore.
    final shallowTop = (sandLine(0.5) - 0.06) * h;
    canvas.drawRect(
      Rect.fromLTRB(0, shallowTop, w, sandLine(0) * h),
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, shallowTop),
          Offset(0, sandLine(0) * h),
          [cfg.shallow.withValues(alpha: 0), cfg.shallow.withValues(alpha: 0.7)],
        ),
    );

    // Wet sand foreground (curved shoreline).
    final sand = Path()..moveTo(0, sandLine(0) * h);
    for (var i = 0; i <= 20; i++) {
      final xN = i / 20;
      sand.lineTo(xN * w, sandLine(xN) * h);
    }
    sand
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(
      sand,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, sandLine(0.5) * h),
          Offset(0, h),
          [cfg.sandFar, cfg.sandNear],
        ),
    );

    if (cfg.daytime) _paintProps(canvas, w, h);

    // Foliage framing the bottom corners.
    _paintFoliage(canvas, w, h, left: true);
    _paintFoliage(canvas, w, h, left: false);

    // Palms: a big one on the right, a smaller framing one on the left.
    _paintCoconutPalm(canvas, w, h,
        base: Offset(w * 0.84, h * 0.72), top: Offset(w * 0.68, h * 0.16), scale: 1.0);
    _paintCoconutPalm(canvas, w, h,
        base: Offset(w * 0.10, h * 0.74), top: Offset(w * 0.21, h * 0.28), scale: 0.6);
  }

  void _paintClouds(Canvas canvas, double w, double h) {
    final col = cfg.daytime ? const Color(0x80FFFFFF) : const Color(0x559A4F7E);
    for (var i = 0; i < 4; i++) {
      final cx = (0.10 + i * 0.27) * w;
      final cy = (0.10 + (i.isEven ? 0.05 : 0.13)) * h;
      canvas.drawOval(
        Rect.fromCenter(center: Offset(cx, cy), width: w * 0.32, height: h * 0.045),
        Paint()
          ..color = col
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18),
      );
    }
  }

  // A small distant tropical island with two tiny palms on the horizon.
  void _paintIsland(Canvas canvas, double w, double h, double hy) {
    final cx = w * 0.24;
    final base = hy + h * 0.004;
    final island = Path()
      ..moveTo(cx - w * 0.11, base)
      ..quadraticBezierTo(cx - w * 0.05, base - h * 0.05, cx, base - h * 0.055)
      ..quadraticBezierTo(cx + w * 0.06, base - h * 0.05, cx + w * 0.12, base)
      ..close();
    canvas.drawPath(island, Paint()..color = cfg.island);
    final palm = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..color = cfg.daytime ? const Color(0xFF1E5E3E) : cfg.island;
    for (final px in [cx - w * 0.02, cx + w * 0.03]) {
      final top = Offset(px, base - h * 0.082);
      canvas.drawLine(Offset(px, base - h * 0.045), top, palm);
      for (var k = -2; k <= 2; k++) {
        canvas.drawLine(top, top + Offset(k * w * 0.013, h * 0.006 + (k * k) * h * 0.0012), palm);
      }
    }
  }

  // Tropical foliage tuft in a bottom corner — broad filled leaves.
  void _paintFoliage(Canvas canvas, double w, double h, {required bool left}) {
    final ox = left ? w * 0.0 : w;
    final oy = h * 1.02;
    final dirN = left ? 1.0 : -1.0;
    final lit = cfg.daytime ? const Color(0xFF34964C) : cfg.frondLit;
    final dark = cfg.daytime ? const Color(0xFF134A1C) : cfg.frondDark;
    for (var i = 0; i < 5; i++) {
      final ang = (-math.pi / 2) + dirN * (0.18 + i * 0.32);
      final len = h * (0.20 + (i.isEven ? 0.05 : 0.0));
      _paintLeaf(canvas, Offset(ox, oy), ang, len, len * 0.16, [lit, dark]);
    }
  }

  // Beach props on the dry sand — a starfish and a couple of shells.
  void _paintProps(Canvas canvas, double w, double h) {
    _paintStarfish(canvas, Offset(w * 0.28, h * 0.88), w * 0.045);
    _paintShell(canvas, Offset(w * 0.46, h * 0.93), w * 0.024, const Color(0xFFF2D6C0));
    _paintShell(canvas, Offset(w * 0.55, h * 0.84), w * 0.018, const Color(0xFFE7C0CE));
  }

  void _paintStarfish(Canvas canvas, Offset c, double r) {
    final path = Path();
    for (var i = 0; i < 5; i++) {
      final a = -math.pi / 2 + i * 2 * math.pi / 5;
      final outer = c + Offset(math.cos(a), math.sin(a)) * r;
      final a2 = a + math.pi / 5;
      final inner = c + Offset(math.cos(a2), math.sin(a2)) * r * 0.45;
      i == 0 ? path.moveTo(outer.dx, outer.dy) : path.lineTo(outer.dx, outer.dy);
      path.lineTo(inner.dx, inner.dy);
    }
    path.close();
    canvas.drawPath(path, Paint()..color = const Color(0xFFE8893F));
    canvas.drawCircle(c, r * 0.14, Paint()..color = const Color(0xFFF6C27A));
  }

  void _paintShell(Canvas canvas, Offset c, double r, Color col) {
    canvas.drawArc(Rect.fromCircle(center: c, radius: r), math.pi, math.pi, true, Paint()..color = col);
    final ribs = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8
      ..color = col.withValues(alpha: 0.6);
    for (var k = -2; k <= 2; k++) {
      canvas.drawLine(c, c + Offset(k * r * 0.32, -r * 0.9), ribs);
    }
  }

  // A lush coconut palm: curved trunk, a cluster of coconuts and a crown of
  // feathered fronds.
  void _paintCoconutPalm(Canvas canvas, double w, double h,
      {required Offset base, required Offset top, required double scale}) {
    final tw = w * 0.018 * scale;
    final flip = top.dx > base.dx;
    final ctrlX = base.dx + (top.dx - base.dx) * 0.5 + (flip ? w * 0.03 : -w * 0.03);
    final ctrlY = base.dy + (top.dy - base.dy) * 0.45;
    final trunk = Path()
      ..moveTo(base.dx + tw, base.dy)
      ..quadraticBezierTo(ctrlX + tw * 0.5, ctrlY, top.dx + tw * 0.5, top.dy)
      ..lineTo(top.dx - tw * 0.5, top.dy)
      ..quadraticBezierTo(ctrlX - tw * 0.5, ctrlY, base.dx - tw, base.dy)
      ..close();
    canvas.drawPath(
      trunk,
      Paint()
        ..shader = ui.Gradient.linear(
          base,
          top,
          [Color.lerp(cfg.trunk, Colors.black, 0.2)!, cfg.trunk],
        ),
    );
    if (cfg.daytime) {
      final ring = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = const Color(0x33000000);
      for (var k = 1; k < 9; k++) {
        final p = Offset.lerp(base, top, k / 9)!;
        canvas.drawLine(p + Offset(-tw, 0), p + Offset(tw, 0), ring);
      }
    }

    // Coconuts under the crown.
    final coconut = Paint()..color = cfg.daytime ? const Color(0xFF6E4421) : cfg.trunk;
    for (final off in [
      Offset(-tw * 1.5, tw * 1.6),
      Offset(tw * 1.7, tw * 1.2),
      Offset(0, tw * 2.4),
      Offset(-tw * 0.2, tw * 0.7),
    ]) {
      canvas.drawCircle(top + off, tw * 1.3, coconut);
    }

    // Crown of feathered fronds: up-and-outward, tips drooping.
    const frondCount = 11;
    final len = (base.dy - top.dy) * 0.66 * scale;
    for (var i = 0; i < frondCount; i++) {
      final t = i / (frondCount - 1);
      final ang = -math.pi + t * math.pi; // left (-π) → right (0), all upward
      final horiz = math.cos(ang).abs();
      final droop = 0.35 + 0.8 * horiz;
      final l = len * (0.78 + 0.22 * (1 - horiz));
      _paintFrond(canvas, top, ang, l, droop);
    }
  }

  // One lush feathered frond as an explicit tapering polygon that arcs out and
  // droops, with leaflet strokes (daytime) for a feathered look.
  void _paintFrond(Canvas canvas, Offset origin, double ang, double len, double droop) {
    final dir = Offset(math.cos(ang), math.sin(ang));
    final perp = Offset(-dir.dy, dir.dx);
    const steps = 12;
    final left = <Offset>[];
    final right = <Offset>[];
    final spine = <Offset>[];
    for (var i = 0; i <= steps; i++) {
      final t = i / steps;
      final p = origin + dir * (len * t) + Offset(0, len * droop * 0.55 * t * t);
      spine.add(p);
      final width = len * (0.015 + 0.11 * math.sin(math.pi * math.min(t * 1.15, 1.0)));
      left.add(p + perp * width);
      right.add(p - perp * width);
    }
    final blade = Path()..moveTo(left.first.dx, left.first.dy);
    for (final p in left.skip(1)) {
      blade.lineTo(p.dx, p.dy);
    }
    for (final p in right.reversed) {
      blade.lineTo(p.dx, p.dy);
    }
    blade.close();
    canvas.drawPath(
      blade,
      Paint()..shader = ui.Gradient.linear(spine.first, spine.last, [cfg.frondLit, cfg.frondDark]),
    );
    if (cfg.daytime) {
      final leaflet = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = cfg.frondDark.withValues(alpha: 0.5);
      for (var i = 2; i < spine.length - 1; i++) {
        final s = spine[i];
        final wd = len * 0.09 * math.sin(math.pi * (i / steps));
        canvas.drawLine(s, s + perp * wd - dir * (len * 0.04), leaflet);
        canvas.drawLine(s, s - perp * wd - dir * (len * 0.04), leaflet);
      }
    }
  }

  // A generic broad leaf polygon (used by the foliage tufts).
  void _paintLeaf(Canvas canvas, Offset origin, double ang, double len, double maxW, List<Color> grad) {
    final dir = Offset(math.cos(ang), math.sin(ang));
    final perp = Offset(-dir.dy, dir.dx);
    const steps = 10;
    final left = <Offset>[];
    final right = <Offset>[];
    for (var i = 0; i <= steps; i++) {
      final t = i / steps;
      final p = origin + dir * (len * t);
      final width = maxW * math.sin(math.pi * t);
      left.add(p + perp * width);
      right.add(p - perp * width);
    }
    final leaf = Path()..moveTo(left.first.dx, left.first.dy);
    for (final p in left.skip(1)) {
      leaf.lineTo(p.dx, p.dy);
    }
    for (final p in right.reversed) {
      leaf.lineTo(p.dx, p.dy);
    }
    leaf.close();
    canvas.drawPath(
      leaf,
      Paint()..shader = ui.Gradient.linear(origin, origin + dir * len, grad),
    );
  }

  @override
  bool shouldRepaint(_BeachBgPainter old) => old.cfg.sun != cfg.sun;
}

class _BeachFxPainter extends CustomPainter {
  _BeachFxPainter({required this.model, required this.cfg}) : super(repaint: model);

  final _BeachModel model;
  final _BeachConfig cfg;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final hy = _horizon * h;
    final time = model.time;
    final sunX = cfg.sunX * w;

    // Sun reflection column on the sea — only when the sun is low (sunset).
    if (cfg.sunY > 0.30) {
      final reflectTop = hy;
      final reflectBot = _BeachBgPainter.sandLine(cfg.sunX) * h;
      for (var i = 0; i < 14; i++) {
        final t = i / 13;
        final y = reflectTop + (reflectBot - reflectTop) * t;
        final width = (0.02 + t * 0.10) * w;
        final wob = math.sin(time * 1.6 + i * 1.1) * (2 + t * 8);
        final a = (0.5 - t * 0.35) * (0.6 + 0.4 * math.sin(time * 3 + i));
        canvas.drawOval(
          Rect.fromCenter(center: Offset(sunX + wob, y), width: width, height: 2.5 + t * 2),
          Paint()..color = cfg.sunGlow.withValues(alpha: a.clamp(0.0, 1.0)),
        );
      }
    }

    // Horizontal wave shimmer lines on the sea.
    for (var i = 0; i < 9; i++) {
      final t = (i + 1) / 10;
      final y = hy + (_BeachBgPainter.sandLine(0) * h - hy) * t;
      final a = 0.05 + 0.06 * (0.5 + 0.5 * math.sin(time * 1.2 + i * 1.6));
      canvas.drawLine(
        Offset(0, y + math.sin(time + i) * 1.5),
        Offset(w, y + math.sin(time + i + 1) * 1.5),
        Paint()
          ..strokeWidth = 1 + t * 1.5
          ..color = Color.fromRGBO(255, 255, 255, a),
      );
    }

    // Wave wash sliding up the wet sand.
    final wash = 0.5 + 0.5 * math.sin(time * 0.6);
    final washY = (_BeachBgPainter.sandLine(0.5) + 0.02 + wash * 0.06) * h;
    final foam = Path()..moveTo(0, washY);
    for (var i = 0; i <= 20; i++) {
      final xN = i / 20;
      foam.lineTo(xN * w, washY + math.sin(time * 2 + xN * 12) * 3);
    }
    canvas.drawPath(
      foam,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = const Color(0x66FFFFFF),
    );

    _paintBirds(canvas, w, h, time);

    // Tap sparkle across the water.
    final sp = (1 - (time - model.sparkle) / 1.4).clamp(0.0, 1.0);
    if (sp > 0) {
      final rng = math.Random(3);
      for (var i = 0; i < 24; i++) {
        final x = rng.nextDouble() * w;
        final y = hy + rng.nextDouble() * (_BeachBgPainter.sandLine(0) * h - hy);
        canvas.drawCircle(
          Offset(x, y),
          1.5 + rng.nextDouble() * 2,
          Paint()..color = Colors.white.withValues(alpha: sp * 0.8),
        );
      }
    }

    // Vignette.
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(w / 2, h * 0.45),
          size.longestSide * 0.8,
          const [Color(0x00000000), Color(0x4D000000)],
          const [0.5, 1.0],
        ),
    );
  }

  // A few distant birds ("M" gulls) gliding across the sky, wings flapping.
  void _paintBirds(Canvas canvas, double w, double h, double time) {
    final col = cfg.daytime ? const Color(0x99203040) : const Color(0x88160E14);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..color = col;
    for (var i = 0; i < 3; i++) {
      final bx = ((0.2 + i * 0.18 + time * 0.012) % 1.2 - 0.1) * w;
      final by = (0.14 + i * 0.04) * h;
      final flap = math.sin(time * 4 + i) * 0.35 + 0.55;
      final s = w * 0.018;
      canvas.drawLine(Offset(bx, by), Offset(bx - s, by - s * flap), paint);
      canvas.drawLine(Offset(bx, by), Offset(bx + s, by - s * flap), paint);
    }
  }

  @override
  bool shouldRepaint(_BeachFxPainter old) => old.cfg.sun != cfg.sun;
}
