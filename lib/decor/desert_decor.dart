import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:dewdrop/decor/reception_signal.dart';
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
  const DesertDecor({super.key, this.variant = 0, this.reception, this.child});

  final int variant;
  final ReceptionSignal? reception;
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
      final now = e.inMicroseconds / 1e6;
      _model.time = now;
      // Reap finished shower entries so the list stays bounded over a session.
      if (_model.showers.isNotEmpty) {
        _model.showers.removeWhere((s) => now - s.start > s.life);
      }
      _model.notify();
    })..start();
    widget.reception?.addListener(_onReception);
  }

  @override
  void didUpdateWidget(DesertDecor old) {
    super.didUpdateWidget(old);
    if (old.reception != widget.reception) {
      old.reception?.removeListener(_onReception);
      widget.reception?.addListener(_onReception);
    }
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

  /// Manual preview: the lighter single-event tap — one sand puff (day) or one
  /// shooting star (night), rendered by the painter off [_DesertModel.burst].
  void _tap() {
    _model.burst = _model.time;
    HapticFeedback.lightImpact();
  }

  /// A pensée arrived: an AMPLIFIED, variant-flavoured *shower* — not the single
  /// tap event but a whole staggered volley seeded into [_model.showers]. The
  /// painter renders each entry like a tap burst but driven by its own start
  /// time, so day = a sweeping fan of sand puffs blown across several origins
  /// and night = a rain of shooting stars streaking in from staggered angles.
  void _onReception() {
    final night = widget.variant != 0;
    final now = _model.time;
    final count = night ? 7 : 6;
    for (var i = 0; i < count; i++) {
      // Stagger the volley so the shower rolls in instead of flashing at once.
      final start = now + i * (night ? 0.16 : 0.1);
      if (night) {
        // Shooting stars: vary the entry corridor and slope across the sky.
        final fromX = 0.05 + _rng.nextDouble() * 0.5;
        final fromY = 0.04 + _rng.nextDouble() * 0.16;
        final span = 0.4 + _rng.nextDouble() * 0.35;
        final drop = 0.18 + _rng.nextDouble() * 0.22;
        _model.showers.add(
          _Shower(
            start: start,
            night: true,
            ox: fromX,
            oy: fromY,
            dx: span,
            dy: drop,
            seed: _rng.nextInt(1 << 20),
          ),
        );
      } else {
        // Sand puffs blown off several crest origins across the width.
        _model.showers.add(
          _Shower(
            start: start,
            night: false,
            ox: 0.12 + _rng.nextDouble() * 0.76,
            oy: 0.72 + _rng.nextDouble() * 0.16,
            dx: 0,
            dy: 0,
            seed: _rng.nextInt(1 << 20),
          ),
        );
      }
    }
    HapticFeedback.mediumImpact();
  }

  @override
  void dispose() {
    widget.reception?.removeListener(_onReception);
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
              painter: _DesertFxPainter(
                model: _model,
                cfg: cfg,
                stars: _stars,
                showers: _model.showers,
              ),
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

  /// Active reception-shower bursts. Each plays out from its own [_Shower.start]
  /// and is reaped by the ticker once past its life span. The single-event tap
  /// stays on [burst]; the amplified "many" lives here.
  final List<_Shower> showers = [];

  void notify() => notifyListeners();
}

/// One staggered burst within a reception shower. [night] picks the flavour:
/// a shooting star streaking from ([ox],[oy]) along ([dx],[dy]) (night) or a
/// sand puff erupting at ([ox],[oy]) (day). [seed] keeps each burst's particle
/// spread deterministic across frames.
class _Shower {
  _Shower({
    required this.start,
    required this.night,
    required this.ox,
    required this.oy,
    required this.dx,
    required this.dy,
    required this.seed,
  });
  final double start;
  final bool night;
  final double ox;
  final double oy;
  final double dx;
  final double dy;
  final int seed;

  /// How long this burst animates (seconds) — matches the per-flavour painter
  /// timing (shooting star 1.2s, sand puff 1.1s) used for the single tap.
  double get life => night ? 1.2 : 1.1;
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
  _DesertFxPainter({
    required this.model,
    required this.cfg,
    required this.stars,
    required this.showers,
  }) : super(repaint: model);

  final _DesertModel model;
  final _DesertConfig cfg;
  final List<_DStar> stars;
  final List<_Shower> showers;

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
      // Shooting star on tap (single, lighter preview).
      _shootingStar(
        canvas, w, h,
        elapsed: time - model.burst,
        from: Offset(w * 0.2, h * 0.1),
        to: Offset(w * 0.7, h * 0.4),
      );
      // Reception shower: a rain of staggered shooting stars.
      for (final s in showers) {
        if (!s.night) continue;
        _shootingStar(
          canvas, w, h,
          elapsed: time - s.start,
          from: Offset(s.ox * w, s.oy * h),
          to: Offset((s.ox + s.dx) * w, (s.oy + s.dy) * h),
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
      // Sand puff on tap (single, lighter preview).
      _sandPuff(
        canvas, w, h,
        elapsed: time - model.burst,
        origin: Offset(w * 0.5, h * 0.82),
        seed: 8,
      );
      // Reception shower: a sweep of sand puffs blown across several crests.
      for (final s in showers) {
        if (s.night) continue;
        _sandPuff(
          canvas, w, h,
          elapsed: time - s.start,
          origin: Offset(s.ox * w, s.oy * h),
          seed: s.seed,
        );
      }
    }
  }

  /// One shooting star — the night flavour. Shared by the single tap and every
  /// staggered burst of a reception shower so they look identical in motion and
  /// colour, only differing in their from/to corridor.
  void _shootingStar(
    Canvas canvas,
    double w,
    double h, {
    required double elapsed,
    required Offset from,
    required Offset to,
  }) {
    final t = elapsed / 1.2;
    if (t < 0 || t > 1) return;
    final eased = Curves.easeOut.transform(t);
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

  /// One sand puff — the day flavour. Shared by the single tap and every
  /// staggered burst of a reception shower; [seed] keeps each puff's spread
  /// deterministic across frames while differing between origins.
  void _sandPuff(
    Canvas canvas,
    double w,
    double h, {
    required double elapsed,
    required Offset origin,
    required int seed,
  }) {
    final sp = (1 - elapsed / 1.1).clamp(0.0, 1.0);
    if (sp <= 0) return;
    final rng = math.Random(seed);
    for (var i = 0; i < 18; i++) {
      final ang = -math.pi * (0.2 + rng.nextDouble() * 0.6);
      final dist = (1 - sp) * w * 0.25 * (0.4 + rng.nextDouble());
      final p = origin + Offset(math.cos(ang), math.sin(ang)) * dist;
      canvas.drawCircle(
        p,
        1 + rng.nextDouble() * 2,
        Paint()..color = const Color(0xFFE9C079).withValues(alpha: sp * 0.5),
      );
    }
  }

  @override
  bool shouldRepaint(_DesertFxPainter old) => false;
}
