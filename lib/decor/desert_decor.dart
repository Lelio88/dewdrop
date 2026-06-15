import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

/// Immersive "désert" decor — flowing sand dunes. Two variants:
///  - 0 "Dunes": warm golden dunes under a clear blue sky, a high sun, drifting
///    wind streaks blowing off the crests and a faint heat shimmer.
///  - 1 "Étoilé": the same dunes at night as cool moonlit silhouettes under a
///    vivid Milky Way and a field of twinkling stars.
///
/// Sky, sun/galaxy, dune layers and rippled foreground are static; the wind
/// streaks (day) or twinkling stars + slow galaxy drift (night) animate on top.
/// A "pensée" (tap) puffs sand into the wind (day) or sends a shooting star
/// (night). Pure Canvas.
class DesertDecor extends StatefulWidget {
  const DesertDecor({super.key, this.variant = 0, this.child});

  final int variant;
  final Widget? child;

  @override
  State<DesertDecor> createState() => _DesertDecorState();
}

class _DesertDecorState extends State<DesertDecor>
    with SingleTickerProviderStateMixin {
  final _model = _DesertModel();
  final math.Random _rng = math.Random(19);
  late final Ticker _ticker;
  late final List<_DStar> _stars = _genStars();

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((e) {
      _model.time = e.inMicroseconds / 1e6;
      _model.notify();
    })..start();
  }

  List<_DStar> _genStars() => List.generate(150, (_) {
        return _DStar(
          x: _rng.nextDouble(),
          y: _rng.nextDouble() * 0.6,
          r: 0.4 + _rng.nextDouble() * 1.5,
          phase: _rng.nextDouble() * math.pi * 2,
          twinkle: 0.3 + _rng.nextDouble() * 0.7,
        );
      });

  void _tap() {
    _model.burst = _model.time;
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
    final cfg = widget.variant == 0 ? _dunes : _starry;
    return Stack(
      children: [
        Positioned.fill(
          child: RepaintBoundary(child: CustomPaint(painter: _DesertBgPainter(cfg))),
        ),
        Positioned.fill(
          child: RepaintBoundary(
            child: CustomPaint(
              painter: _DesertFxPainter(model: _model, cfg: cfg, stars: _stars),
            ),
          ),
        ),
        Positioned.fill(
          child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: _tap),
        ),
        if (widget.child != null) Positioned.fill(child: widget.child!),
      ],
    );
  }
}

class _DesertConfig {
  const _DesertConfig({
    required this.night,
    required this.skyTop,
    required this.skyHorizon,
    required this.duneLit,
    required this.duneShadow,
    required this.sun,
  });

  final bool night;
  final Color skyTop;
  final Color skyHorizon;
  final Color duneLit; // crest / lit face
  final Color duneShadow; // valley / shadow face
  final Color sun;
}

const _dunes = _DesertConfig(
  night: false,
  skyTop: Color(0xFF3E8FD0),
  skyHorizon: Color(0xFFCDE7F2),
  duneLit: Color(0xFFE9C079),
  duneShadow: Color(0xFFB07B3C),
  sun: Color(0xFFFFF6DC),
);

const _starry = _DesertConfig(
  night: true,
  skyTop: Color(0xFF070B1E),
  skyHorizon: Color(0xFF1A2746),
  duneLit: Color(0xFF6E7C98),
  duneShadow: Color(0xFF161D2E),
  sun: Color(0xFFBFD0F0),
);

const double _dHorizon = 0.42;

class _DesertModel extends ChangeNotifier {
  double time = 0;
  double burst = -10;
  void notify() => notifyListeners();
}

class _DStar {
  const _DStar({
    required this.x,
    required this.y,
    required this.r,
    required this.phase,
    required this.twinkle,
  });
  final double x;
  final double y;
  final double r;
  final double phase;
  final double twinkle;
}

// Smooth dune ridge across the width at vertical [baseY] (fraction of h), with
// crest [amp] and a horizontal [shift] so each layer differs.
Path _dunePath(double w, double h, double baseY, double amp, double shift) {
  final path = Path()..moveTo(0, h);
  path.lineTo(0, baseY * h);
  const steps = 24;
  for (var i = 0; i <= steps; i++) {
    final xN = i / steps;
    final y = baseY +
        amp *
            (0.55 * math.sin(xN * math.pi * 1.4 + shift) +
                0.30 * math.sin(xN * math.pi * 3.1 + shift * 1.7) +
                0.15 * math.sin(xN * math.pi * 5.7 + shift * 0.6));
    path.lineTo(xN * w, y * h);
  }
  path
    ..lineTo(w, h)
    ..close();
  return path;
}

class _DesertBgPainter extends CustomPainter {
  const _DesertBgPainter(this.cfg);
  final _DesertConfig cfg;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Sky.
    canvas.drawRect(
      Rect.fromLTRB(0, 0, w, _dHorizon * h + h * 0.04),
      Paint()
        ..shader = ui.Gradient.linear(
          const Offset(0, 0),
          Offset(0, _dHorizon * h),
          [cfg.skyTop, cfg.skyHorizon],
        ),
    );

    if (!cfg.night) {
      // Daytime sun high in the sky with a soft halo.
      final sunPos = Offset(w * 0.70, h * 0.16);
      canvas.drawCircle(
        sunPos,
        h * 0.22,
        Paint()
          ..blendMode = BlendMode.plus
          ..shader = ui.Gradient.radial(
            sunPos,
            h * 0.22,
            [cfg.sun.withValues(alpha: 0.5), cfg.sun.withValues(alpha: 0)],
          ),
      );
      canvas.drawCircle(sunPos, h * 0.04, Paint()..color = cfg.sun);
    } else {
      _paintMilkyWay(canvas, size);
    }

    // Dune layers, back (light, hazy) to front (darker), each lit on top.
    final layers = <(double, double, double, double)>[
      (0.40, 0.030, 0.4, 0.18), // baseY, amp, shift, darken
      (0.50, 0.045, 2.1, 0.34),
      (0.62, 0.060, 4.3, 0.52),
      (0.78, 0.075, 1.2, 0.72),
    ];
    for (final (baseY, amp, shift, darken) in layers) {
      final lit = Color.lerp(cfg.duneLit, cfg.duneShadow, darken)!;
      final shadow = Color.lerp(cfg.duneShadow, Colors.black, darken * 0.4)!;
      // Distant layers fade into the horizon haze.
      final hazed = Color.lerp(lit, cfg.skyHorizon, (1 - darken) * 0.35)!;
      final path = _dunePath(w, h, baseY, amp, shift);
      canvas.drawPath(
        path,
        Paint()
          ..shader = ui.Gradient.linear(
            Offset(0, baseY * h),
            Offset(0, h),
            [hazed, shadow],
          ),
      );
    }

    // Rippled foreground sand (subtle wavy contour lines).
    final ripple = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = (cfg.night ? Colors.white : Colors.black).withValues(alpha: 0.06);
    for (var i = 0; i < 16; i++) {
      final t = i / 15;
      final y = (0.80 + t * 0.19) * h;
      final path = Path()..moveTo(0, y);
      for (var x = 0; x <= 20; x++) {
        final xN = x / 20;
        path.lineTo(xN * w, y + math.sin(xN * 9 + i) * (2 + t * 3));
      }
      canvas.drawPath(path, ripple);
    }

    // Depth vignette.
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(w / 2, h * 0.5),
          size.longestSide * 0.8,
          [const Color(0x00000000), (cfg.night ? const Color(0x66060A18) : const Color(0x33000000))],
          const [0.5, 1.0],
        ),
    );
  }

  // A colourful galactic band rising on a diagonal over the dunes (night).
  void _paintMilkyWay(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    canvas.save();
    canvas.translate(w * 0.55, h * 0.18);
    canvas.rotate(-0.5);
    final bandW = size.longestSide * 1.3;
    final bandH = h * 0.34;
    canvas.drawRect(
      Rect.fromCenter(center: Offset.zero, width: bandW, height: bandH),
      Paint()
        ..blendMode = BlendMode.plus
        ..shader = ui.Gradient.linear(
          Offset(0, -bandH / 2),
          Offset(0, bandH / 2),
          const [
            Color(0x00203A6A),
            Color(0x33384E8C),
            Color(0x4A8A6AB0),
            Color(0x33B08A6A),
            Color(0x00203A6A),
          ],
          const [0.0, 0.35, 0.5, 0.65, 1.0],
        ),
    );
    final rng = math.Random(5);
    for (var i = 0; i < 14; i++) {
      final x = (rng.nextDouble() - 0.5) * bandW * 0.8;
      final y = (rng.nextDouble() - 0.5) * bandH * 0.5;
      canvas.drawCircle(
        Offset(x, y),
        h * (0.02 + rng.nextDouble() * 0.05),
        Paint()
          ..blendMode = BlendMode.plus
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18)
          ..color = const Color(0xFFB9C6F0).withValues(alpha: 0.05 + rng.nextDouble() * 0.05),
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_DesertBgPainter old) => old.cfg.night != cfg.night;
}

class _DesertFxPainter extends CustomPainter {
  _DesertFxPainter({required this.model, required this.cfg, required this.stars})
      : super(repaint: model);

  final _DesertModel model;
  final _DesertConfig cfg;
  final List<_DStar> stars;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final time = model.time;

    if (cfg.night) {
      // Twinkling stars.
      for (final s in stars) {
        final a = s.twinkle * (0.55 + 0.45 * math.sin(time * 1.5 + s.phase));
        canvas.drawCircle(
          Offset(s.x * w, s.y * h),
          s.r,
          Paint()..color = Color.fromRGBO(255, 255, 255, a.clamp(0.0, 1.0)),
        );
      }
      // Shooting star on tap.
      final t = (time - model.burst) / 1.2;
      if (t >= 0 && t <= 1) {
        final eased = Curves.easeOut.transform(t);
        final from = Offset(w * 0.2, h * 0.1);
        final to = Offset(w * 0.7, h * 0.4);
        final head = Offset.lerp(from, to, eased)!;
        final tail = Offset.lerp(from, to, (eased - 0.12).clamp(0.0, 1.0))!;
        final fade = (t < 0.15 ? t / 0.15 : 1 - (t - 0.15) / 0.85).clamp(0.0, 1.0);
        canvas.drawLine(
          tail,
          head,
          Paint()
            ..strokeWidth = 2
            ..strokeCap = StrokeCap.round
            ..shader = ui.Gradient.linear(
              tail,
              head,
              [const Color(0x00FFFFFF), Color.fromRGBO(255, 255, 255, fade)],
            ),
        );
      }
    } else {
      // Wind streaks blowing off the dune crests.
      final paint = Paint()
        ..strokeWidth = 1.4
        ..strokeCap = StrokeCap.round;
      for (var i = 0; i < 7; i++) {
        final crestY = (0.40 + i * 0.055) * h;
        final phase = time * (0.25 + i * 0.04) + i;
        for (var k = 0; k < 3; k++) {
          final prog = (phase + k * 0.33) % 1.0;
          final x = prog * w;
          final a = math.sin(prog * math.pi) * 0.18;
          canvas.drawLine(
            Offset(x, crestY - 2),
            Offset(x + w * 0.09, crestY - h * 0.02),
            paint..color = const Color(0xFFFFF3D6).withValues(alpha: a),
          );
        }
      }
      // Faint heat shimmer near the horizon.
      final shimmer = Paint()
        ..strokeWidth = 2
        ..color = Colors.white.withValues(alpha: 0.04);
      for (var i = 0; i < 5; i++) {
        final y = (_dHorizon + 0.01 + i * 0.012) * h;
        final path = Path()..moveTo(0, y);
        for (var x = 0; x <= 24; x++) {
          final xN = x / 24;
          path.lineTo(xN * w, y + math.sin(time * 2 + xN * 18 + i) * 1.4);
        }
        canvas.drawPath(path, shimmer..style = PaintingStyle.stroke);
      }
      // Sand puff on tap.
      final sp = (1 - (time - model.burst) / 1.1).clamp(0.0, 1.0);
      if (sp > 0) {
        final rng = math.Random(8);
        for (var i = 0; i < 18; i++) {
          final base = Offset(w * 0.5, h * 0.82);
          final ang = -math.pi * (0.2 + rng.nextDouble() * 0.6);
          final dist = (1 - sp) * w * 0.25 * (0.4 + rng.nextDouble());
          final p = base + Offset(math.cos(ang), math.sin(ang)) * dist;
          canvas.drawCircle(
            p,
            1 + rng.nextDouble() * 2,
            Paint()..color = const Color(0xFFE9C079).withValues(alpha: sp * 0.5),
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(_DesertFxPainter old) => false;
}
