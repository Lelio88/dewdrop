import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:dewdrop/decor/sky_clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

// Deep-space volume. The camera sits at the origin; stars are placed once in
// a box and stay put (calm, cosy — no forward motion). Depth (z) only drives
// parallax when you look around. z is biased toward the far plane so the
// field stays fine rather than full of huge blobs.
const double _zNear = 0.22;
const double _zFar = 3.6;
const double _spread = 1.7;
const double _focal = 0.9;
const int _starCount = 440;

/// The variants of the "espace" environment.
enum SpaceVariant {
  /// Stars + soft coloured nebulae (the default cosy cosmos).
  cosmos,

  /// Pure black void; only the stars twinkle. The most minimal.
  voidNight,

  /// Stars + a couple of stylised planets drifting in view.
  planets,
}

/// Immersive "espace" decor: you float, still, in the middle of a 3-D
/// starfield — calm and cosy, with only a soft twinkle and a whisper of sway.
/// The pointer/gyroscope lets you gently look around. Receiving a "pensée"
/// (here a tap on the open sky) triggers a shower of shooting stars.
///
/// [variant] selects the mood (see [SpaceVariant]). Rendered entirely on the
/// Canvas, so it works on every platform (Windows desktop included for dev).
///
/// [child] floats over the scene (the app UI).
class SpaceDecor extends StatefulWidget {
  const SpaceDecor({
    super.key,
    this.variant = SpaceVariant.cosmos,
    this.child,
  });

  final SpaceVariant variant;
  final Widget? child;

  @override
  State<SpaceDecor> createState() => _SpaceDecorState();
}

class _SpaceDecorState extends State<SpaceDecor>
    with SingleTickerProviderStateMixin {
  final _model = _DecorModel();
  final math.Random _rng = math.Random(7);

  late final Ticker _ticker;
  late final List<_Star3D> _stars = _generateStars();
  late final List<_Nebula> _nebulae = _generateNebulae();
  late final List<_Planet> _planets = _generatePlanets();
  late final List<_Debris> _debris = _generateDebris();

  double _lastTick = 0;
  Size _size = Size.zero;
  Offset _pointerLook = Offset.zero;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
  }

  void _onTick(Duration elapsed) {
    final now = elapsed.inMicroseconds / 1e6;
    final dt = (now - _lastTick).clamp(0.0, 0.05);
    _lastTick = now;

    _model.time = now;
    _model.daylight = daylightFactor(DateTime.now());

    final auto = Offset(
      math.sin(now * 0.05) * 0.006,
      math.cos(now * 0.04) * 0.005,
    );
    final target = auto + _pointerLook;
    final k = 1 - math.exp(-dt * 3);
    _model.look = Offset.lerp(_model.look, target, k)!;

    _model.shooting.removeWhere((s) => s.isDead(now));
    _model.notify();
  }

  void _updatePointer(PointerEvent event) {
    if (_size == Size.zero) return;
    final nx = (event.localPosition.dx / _size.width) * 2 - 1;
    final ny = (event.localPosition.dy / _size.height) * 2 - 1;
    _pointerLook = Offset(-nx * 0.10, -ny * 0.08);
  }

  /// A "pensée" arrives: rain a staggered shower of shooting stars.
  void _spawnThoughtShower() {
    const count = 14;
    for (var i = 0; i < count; i++) {
      final from = Offset(
        _rng.nextDouble() * 1.1 - 0.05,
        _rng.nextDouble() * 0.4 - 0.05,
      );
      final dir = Offset(
        0.55 + (_rng.nextDouble() - 0.5) * 0.25,
        0.65 + (_rng.nextDouble() - 0.5) * 0.25,
      );
      final length = 0.4 + _rng.nextDouble() * 0.35;
      _model.shooting.add(
        _ShootingStar(
          startTime: _model.time + _rng.nextDouble(),
          from: from,
          to: from + dir * length,
          duration: 0.9 + _rng.nextDouble() * 0.6,
        ),
      );
    }
    HapticFeedback.mediumImpact();
  }

  List<_Star3D> _generateStars() {
    return List.generate(_starCount, (_) {
      final z = _zNear + (_zFar - _zNear) * math.sqrt(_rng.nextDouble());
      return _Star3D(
        x: (_rng.nextDouble() * 2 - 1) * _spread,
        y: (_rng.nextDouble() * 2 - 1) * _spread,
        z: z,
        size: 0.6 + _rng.nextDouble() * 1.1,
        baseAlpha: 0.5 + _rng.nextDouble() * 0.5,
        phase: _rng.nextDouble() * math.pi * 2,
        twinkleSpeed: 0.4 + _rng.nextDouble() * 0.9,
        color: _starColor(_rng),
      );
    });
  }

  List<_Nebula> _generateNebulae() {
    return const [
      _Nebula(Offset(0.28, 0.34), 0.62, Color(0x40402A8A), 0.4, 0.03),
      _Nebula(Offset(0.74, 0.62), 0.70, Color(0x3a1E5A7A), 1.7, 0.025),
      _Nebula(Offset(0.58, 0.22), 0.50, Color(0x33802A6A), 3.1, 0.035),
      _Nebula(Offset(0.18, 0.78), 0.55, Color(0x301E6A5A), 4.6, 0.03),
    ];
  }

  List<_Planet> _generatePlanets() {
    return const [
      _Planet(Offset(0.76, 0.28), 0.11, Color(0xFFC9A36B), true, 0.35),
      _Planet(Offset(0.19, 0.70), 0.075, Color(0xFF5A86C0), false, 0.5),
    ];
  }

  // A sweep of bright dust/debris in the lower-left (for the "nuit noire" photo).
  List<_Debris> _generateDebris() => List.generate(170, (_) {
        final t = _rng.nextDouble();
        final bx = t * 0.5;
        final by = 1.0 - t * 0.42;
        return _Debris(
          x: (bx + (_rng.nextDouble() - 0.5) * 0.14).clamp(0.0, 1.0),
          y: (by + (_rng.nextDouble() - 0.5) * 0.14).clamp(0.0, 1.0),
          size: 0.5 + _rng.nextDouble() * 1.8,
          phase: _rng.nextDouble() * math.pi * 2,
          twinkleSpeed: 0.8 + _rng.nextDouble() * 2.0,
          bright: 0.4 + _rng.nextDouble() * 0.6,
        );
      });

  @override
  void dispose() {
    _ticker.dispose();
    _model.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final config = _configFor(widget.variant);
    return Listener(
      onPointerHover: _updatePointer,
      onPointerMove: _updatePointer,
      child: LayoutBuilder(
        builder: (context, constraints) {
          _size = constraints.biggest;
          return Stack(
            children: [
              Positioned.fill(
                child: RepaintBoundary(
                  child: CustomPaint(
                    painter: _SpacePainter(
                      model: _model,
                      stars: _stars,
                      nebulae: _nebulae,
                      planets: _planets,
                      debris: _debris,
                      config: config,
                    ),
                  ),
                ),
              ),
              // Tap anywhere on the open sky to send a "pensée".
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _spawnThoughtShower,
                ),
              ),
              Positioned.fill(
                child: IgnorePointer(
                  child: RepaintBoundary(
                    child: CustomPaint(painter: _ShootingStarPainter(_model)),
                  ),
                ),
              ),
              if (widget.child != null) Positioned.fill(child: widget.child!),
            ],
          );
        },
      ),
    );
  }
}

_SpaceConfig _configFor(SpaceVariant variant) => switch (variant) {
      SpaceVariant.cosmos => const _SpaceConfig(
          base: Color(0xFF03030A),
          showNebulae: true,
          showPlanets: false,
          showDebris: false,
          twinkleDepth: 0.25,
        ),
      SpaceVariant.voidNight => const _SpaceConfig(
          base: Color(0xFF05060E),
          showNebulae: true,
          showPlanets: false,
          showDebris: true,
          twinkleDepth: 0.38,
        ),
      SpaceVariant.planets => const _SpaceConfig(
          base: Color(0xFF03030A),
          showNebulae: true,
          showPlanets: true,
          showDebris: false,
          twinkleDepth: 0.25,
        ),
    };

Color _starColor(math.Random rng) {
  final r = rng.nextDouble();
  if (r < 0.70) return const Color(0xFFEAF2FF); // cool white
  if (r < 0.85) return const Color(0xFFFFE9C8); // warm
  if (r < 0.95) return const Color(0xFFBFD8FF); // blue
  return const Color(0xFFFFD0E0); // pink
}

class _SpaceConfig {
  const _SpaceConfig({
    required this.base,
    required this.showNebulae,
    required this.showPlanets,
    required this.showDebris,
    required this.twinkleDepth,
  });

  final Color base;
  final bool showNebulae;
  final bool showPlanets;
  final bool showDebris;
  final double twinkleDepth;
}

/// Mutable per-frame state shared with the painters; notifies them to repaint.
class _DecorModel extends ChangeNotifier {
  double time = 0;
  double daylight = 0;
  Offset look = Offset.zero;
  final List<_ShootingStar> shooting = [];

  void notify() => notifyListeners();
}

class _Star3D {
  const _Star3D({
    required this.x,
    required this.y,
    required this.z,
    required this.size,
    required this.baseAlpha,
    required this.phase,
    required this.twinkleSpeed,
    required this.color,
  });

  final double x;
  final double y;
  final double z;
  final double size;
  final double baseAlpha;
  final double phase;
  final double twinkleSpeed;
  final Color color;
}

class _Nebula {
  const _Nebula(this.center, this.radius, this.color, this.phase, this.drift);

  final Offset center;
  final double radius;
  final Color color;
  final double phase;
  final double drift;
}

class _Planet {
  const _Planet(this.center, this.radius, this.color, this.hasRing, this.depth);

  final Offset center; // normalized 0..1
  final double radius; // fraction of the smaller screen dimension
  final Color color;
  final bool hasRing;
  final double depth; // parallax strength when looking around
}

class _Debris {
  const _Debris({
    required this.x,
    required this.y,
    required this.size,
    required this.phase,
    required this.twinkleSpeed,
    required this.bright,
  });
  final double x;
  final double y;
  final double size;
  final double phase;
  final double twinkleSpeed;
  final double bright;
}

class _ShootingStar {
  _ShootingStar({
    required this.startTime,
    required this.from,
    required this.to,
    this.duration = 1.1,
  });

  final Offset from;
  final Offset to;
  final double startTime;
  final double duration;

  double life(double now) => ((now - startTime) / duration).clamp(0.0, 1.0);
  bool isDead(double now) => now - startTime > duration;
}

class _SpacePainter extends CustomPainter {
  _SpacePainter({
    required this.model,
    required this.stars,
    required this.nebulae,
    required this.planets,
    required this.debris,
    required this.config,
  }) : super(repaint: model);

  final _DecorModel model;
  final List<_Star3D> stars;
  final List<_Nebula> nebulae;
  final List<_Planet> planets;
  final List<_Debris> debris;
  final _SpaceConfig config;

  static const _warmTint = Color(0xFF6A4A2A);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final cx = size.width / 2;
    final cy = size.height / 2;
    final minDim = math.min(size.width, size.height);
    final time = model.time;
    final daylight = model.daylight;
    final lookX = model.look.dx;
    final lookY = model.look.dy;

    canvas.drawRect(rect, Paint()..color = config.base);

    if (config.showNebulae) {
      for (final n in nebulae) {
        final nx = (n.center.dx + math.sin(time * 0.03 + n.phase) * n.drift) *
                size.width -
            lookX * minDim * 0.2;
        final ny = (n.center.dy + math.cos(time * 0.025 + n.phase) * n.drift) *
                size.height -
            lookY * minDim * 0.2;
        final rad = n.radius * minDim;
        final col = Color.lerp(n.color, _warmTint, daylight * 0.22)!;
        canvas.drawCircle(
          Offset(nx, ny),
          rad,
          Paint()
            ..shader = ui.Gradient.radial(
              Offset(nx, ny),
              rad,
              [col, col.withValues(alpha: 0)],
            ),
        );
      }
    }

    final td = config.twinkleDepth;
    for (final s in stars) {
      final sx = cx + ((s.x + lookX) / s.z) * _focal * minDim;
      final sy = cy + ((s.y + lookY) / s.z) * _focal * minDim;
      if (sx < -40 || sx > size.width + 40 || sy < -40 || sy > size.height + 40) {
        continue;
      }

      final twinkle = (1 - td) + td * (0.5 + 0.5 * math.sin(time * s.twinkleSpeed + s.phase));
      final a = (s.baseAlpha * twinkle).clamp(0.0, 1.0);
      final r = (s.size * _focal / s.z).clamp(0.3, 4.5);

      canvas.drawCircle(
        Offset(sx, sy),
        r * 3.0,
        Paint()..color = s.color.withValues(alpha: a * 0.16),
      );
      canvas.drawCircle(
        Offset(sx, sy),
        r,
        Paint()..color = s.color.withValues(alpha: a),
      );
    }

    if (config.showDebris) {
      for (final d in debris) {
        final tw = 0.5 + 0.5 * math.sin(time * d.twinkleSpeed + d.phase);
        final a = (d.bright * tw).clamp(0.0, 1.0);
        final c = Offset(
          d.x * size.width + lookX * size.width * 0.05,
          d.y * size.height + lookY * size.height * 0.05,
        );
        canvas.drawCircle(c, d.size * 1.8,
            Paint()..color = const Color(0xFFCFE0FF).withValues(alpha: a * 0.2));
        canvas.drawCircle(c, d.size,
            Paint()..color = const Color(0xFFEAF2FF).withValues(alpha: a));
      }
    }

    if (config.showPlanets) {
      for (final p in planets) {
        _paintPlanet(canvas, size, minDim, lookX, lookY, p);
      }
    }

    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.radial(
          size.center(Offset.zero),
          size.longestSide * 0.75,
          const [Color(0x00000000), Color(0x66000000)],
          const [0.45, 1.0],
        ),
    );
  }

  void _paintPlanet(
    Canvas canvas,
    Size size,
    double minDim,
    double lookX,
    double lookY,
    _Planet p,
  ) {
    final center = Offset(
      p.center.dx * size.width - lookX * minDim * p.depth * 0.6,
      p.center.dy * size.height - lookY * minDim * p.depth * 0.6,
    );
    final rad = p.radius * minDim;
    final light = center + Offset(-rad * 0.4, -rad * 0.4);
    final lit = Color.lerp(p.color, Colors.white, 0.45)!;
    final dark = Color.lerp(p.color, Colors.black, 0.6)!;

    // Back half of the ring (drawn before the body so it tucks behind).
    if (p.hasRing) {
      _paintRing(canvas, center, rad, p.color, back: true);
    }

    // Planet body with fake directional lighting.
    canvas.drawCircle(
      center,
      rad,
      Paint()
        ..shader = ui.Gradient.radial(
          light,
          rad * 1.6,
          [lit, p.color, dark],
          const [0.0, 0.55, 1.0],
        ),
    );

    if (p.hasRing) {
      _paintRing(canvas, center, rad, p.color, back: false);
    }
  }

  void _paintRing(
    Canvas canvas,
    Offset center,
    double rad,
    Color color, {
    required bool back,
  }) {
    final ringRect = Rect.fromCenter(
      center: center,
      width: rad * 3.4,
      height: rad * 1.1,
    );
    final ringColor = Color.lerp(color, Colors.white, 0.25)!
        .withValues(alpha: back ? 0.28 : 0.55);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = rad * 0.16
      ..color = ringColor;
    // back = top arc (behind the planet), front = bottom arc.
    canvas.drawArc(ringRect, back ? math.pi : 0, math.pi, false, paint);
  }

  @override
  bool shouldRepaint(_SpacePainter old) =>
      old.config.base != config.base ||
      old.config.showNebulae != config.showNebulae ||
      old.config.showPlanets != config.showPlanets ||
      old.config.showDebris != config.showDebris ||
      old.config.twinkleDepth != config.twinkleDepth;
}

class _ShootingStarPainter extends CustomPainter {
  _ShootingStarPainter(this.model) : super(repaint: model);

  final _DecorModel model;

  @override
  void paint(Canvas canvas, Size size) {
    for (final star in model.shooting) {
      final t = star.life(model.time);
      if (t <= 0) continue;
      final eased = Curves.easeOut.transform(t);
      final tailT = (eased - 0.12).clamp(0.0, 1.0);

      final head = Offset(
        ui.lerpDouble(star.from.dx, star.to.dx, eased)! * size.width,
        ui.lerpDouble(star.from.dy, star.to.dy, eased)! * size.height,
      );
      final tail = Offset(
        ui.lerpDouble(star.from.dx, star.to.dx, tailT)! * size.width,
        ui.lerpDouble(star.from.dy, star.to.dy, tailT)! * size.height,
      );

      final fade =
          (t < 0.15 ? t / 0.15 : 1 - (t - 0.15) / 0.85).clamp(0.0, 1.0);

      canvas.drawLine(
        tail,
        head,
        Paint()
          ..strokeWidth = 2.0
          ..strokeCap = StrokeCap.round
          ..shader = ui.Gradient.linear(tail, head, [
            const Color(0x00FFFFFF),
            Color.fromRGBO(255, 255, 255, fade),
          ]),
      );
      canvas.drawCircle(
        head,
        2.4,
        Paint()
          ..color = Color.fromRGBO(255, 255, 255, fade)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
      );
    }
  }

  @override
  bool shouldRepaint(_ShootingStarPainter oldDelegate) => false;
}
