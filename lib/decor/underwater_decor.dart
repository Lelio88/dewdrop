import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:dewdrop/decor/decor_backdrop.dart';
import 'package:dewdrop/decor/reception_signal.dart';
import 'package:dewdrop/decor/tilt.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

/// Immersive "sous l'eau" decor with two distinct scenes:
///  - variant 0 "Fonds marins": the seabed — an undulating floor, rocks, and
///    swaying seaweed rising from it. Dark and deep. Its ambient particle layer
///    is drifting marine snow / plankton — sparse pale specks sinking gently.
///  - variant 1 "Poissons": brighter open water with bubbles rising, lit by
///    surface god-rays. Its ambient particle layer is a handful of small fish
///    silhouettes darting across at varied depths — no marine snow here.
///
/// Each variant therefore owns a *different* ambient particle TYPE (snow vs
/// fish), gated by [_UWConfig.showSnow] / [_UWConfig.showFish]. Both share
/// ambient bubbles and the bubble burst. A tap spawns a
/// light preview burst ([_spawnBubbleBurst]); a decoupled [ReceptionSignal]
/// pulse — fired by the host when a "pensée" actually arrives — spawns the big
/// amplified celebratory swell ([_onReception]), flavoured per variant.
/// Rendered entirely on the Canvas.
class UnderwaterDecor extends StatefulWidget {
  const UnderwaterDecor({
    super.key,
    this.variant = 0,
    this.reception,
    this.parallax = true,
    this.child,
    this.assetRoot = 'photo',
  });

  final int variant;
  final ReceptionSignal? reception;
  final bool parallax;
  final Widget? child;
  // 'photo' or 'illustrated' — which parallax backdrop the ambient FX (fish,
  // plankton, bubbles) sit on.
  final String assetRoot;

  @override
  State<UnderwaterDecor> createState() => _UnderwaterDecorState();
}

class _UnderwaterDecorState extends State<UnderwaterDecor>
    with SingleTickerProviderStateMixin {
  final _model = _UWModel();
  final math.Random _rng = math.Random(11);

  late final Ticker _ticker;
  late final List<_Mote> _snow = _genSnow();
  late final List<_Bubble> _bubbles = _genBubbles();
  late final List<_Ray> _rays = _genRays();
  late final List<_Weed> _weeds = _genWeeds();
  late final List<_Rock> _rocks = _genRocks();
  late final List<_Fish> _fish = _genFish();
  // Tilt the phone to look around the scene (gyroscope-style, drift-free).
  final TiltController _tilt = TiltController();

  double _lastTick = 0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
    widget.reception?.addListener(_onReception);
  }

  @override
  void didUpdateWidget(UnderwaterDecor old) {
    super.didUpdateWidget(old);
    if (old.reception != widget.reception) {
      old.reception?.removeListener(_onReception);
      widget.reception?.addListener(_onReception);
    }
  }

  void _onTick(Duration elapsed) {
    final now = elapsed.inMicroseconds / 1e6;
    final dt = (now - _lastTick).clamp(0.0, 0.05);
    _lastTick = now;
    _model.time = now;

    for (final m in _snow) {
      m.y += m.speed * dt;
      m.x += math.sin(now * 0.6 + m.phase) * 0.0004;
      if (m.y > 1.05) {
        m.y = -0.05;
        m.x = _rng.nextDouble();
      }
    }

    final remove = <_Bubble>[];
    for (final b in _bubbles) {
      b.y -= b.speed * dt;
      b.x += math.sin(now * 1.3 + b.phase) * 0.0009;
      if (b.y < -0.06) {
        if (b.ephemeral) {
          remove.add(b);
        } else {
          b.y = 1.06;
          b.x = _rng.nextDouble();
        }
      }
    }
    if (remove.isNotEmpty) _bubbles.removeWhere(remove.contains);

    for (final f in _fish) {
      f.x += f.dir * f.speed * dt;
      if (f.dir > 0 && f.x > 1.15) {
        f.x = -0.15;
        f.y = 0.18 + _rng.nextDouble() * 0.55;
      } else if (f.dir < 0 && f.x < -0.15) {
        f.x = 1.15;
        f.y = 0.18 + _rng.nextDouble() * 0.55;
      }
    }

    final auto = Offset(math.sin(now * 0.05) * 0.005, 0);
    final target = auto + (widget.parallax ? _tilt.look : Offset.zero);
    final k = 1 - math.exp(-dt * 3);
    _model.look = Offset.lerp(_model.look, target, k)!;

    _model.glows.removeWhere((g) => g.life(now) >= 1);
    _model.notify();
  }

  /// Tap preview: a light, modest burst rising from the bottom edge — the
  /// manual "what would a pensée feel like" tease. Kept deliberately small so
  /// the real reception swell ([_onReception]) reads as much bigger.
  void _spawnBubbleBurst() {
    for (var i = 0; i < 16; i++) {
      _bubbles.add(
        _Bubble(
          x: _rng.nextDouble(),
          y: 1.05 + _rng.nextDouble() * 0.15,
          size: 1.5 + _rng.nextDouble() * 4,
          speed: 0.12 + _rng.nextDouble() * 0.12,
          phase: _rng.nextDouble() * math.pi * 2,
          ephemeral: true,
        ),
      );
    }
    _model.glows.add(_Glow(const Offset(0.5, 0.6), _model.time));
    HapticFeedback.mediumImpact();
  }

  /// A pensée arrived: an AMPLIFIED celebratory swell — a much bigger, denser
  /// wave of bubbles than a tap, plus a cluster of bioluminescent glows. The
  /// swell is flavoured by the active variant so each scene celebrates in its
  /// own register:
  ///  - variant 0 "Fonds marins": a deep, heavy welling that lifts off the
  ///    seabed floor itself — fewer, bigger, slower bubbles seeded along the
  ///    undulating floor line, and a low cluster of teal glows hugging the bed,
  ///    matching the dark/deep scene.
  ///  - variant 1 "Poissons": a bright, fast, wide surge fanned across the full
  ///    width and rising quickly toward the surface god-rays — many smaller
  ///    bubbles (the brighter open water renders them more luminous for free)
  ///    and glows spread higher where the light is.
  void _onReception() {
    final isSeabed = widget.variant == 0;

    if (isSeabed) {
      // Deep welling lifting off the seabed floor: ~48 big slow bubbles.
      for (var i = 0; i < 48; i++) {
        final x = _rng.nextDouble();
        _bubbles.add(
          _Bubble(
            x: x,
            // Seed just under the floor line so they appear to rise from the
            // bed; stagger below it so the swell arrives as a wave.
            y: _floorY(x) + 0.02 + _rng.nextDouble() * 0.18,
            size: 3 + _rng.nextDouble() * 6,
            speed: 0.10 + _rng.nextDouble() * 0.10,
            phase: _rng.nextDouble() * math.pi * 2,
            ephemeral: true,
          ),
        );
      }
      // Low cluster of glows hugging the bed (centre-weighted, deep).
      for (var i = 0; i < 4; i++) {
        _model.glows.add(
          _Glow(
            Offset(
              0.32 + _rng.nextDouble() * 0.36,
              0.66 + _rng.nextDouble() * 0.16,
            ),
            _model.time,
          ),
        );
      }
    } else {
      // Bright wide surge across the whole width, rising fast.
      for (var i = 0; i < 60; i++) {
        _bubbles.add(
          _Bubble(
            x: _rng.nextDouble(),
            y: 1.04 + _rng.nextDouble() * 0.30,
            size: 1.5 + _rng.nextDouble() * 4.5,
            speed: 0.16 + _rng.nextDouble() * 0.16,
            phase: _rng.nextDouble() * math.pi * 2,
            ephemeral: true,
          ),
        );
      }
      // Glows spread wider and higher, toward the sunlit zone.
      for (var i = 0; i < 4; i++) {
        _model.glows.add(
          _Glow(
            Offset(
              0.18 + _rng.nextDouble() * 0.64,
              0.32 + _rng.nextDouble() * 0.30,
            ),
            _model.time,
          ),
        );
      }
    }

    HapticFeedback.heavyImpact();
  }

  // Marine snow / plankton — the deep-seabed ambient layer (variant 0 only).
  // Sparse pale specks sinking very slowly with a faint sway: the calm
  // suspended-particle look of deep water. Variant 1 grows fish instead, so
  // there is no snow there.
  List<_Mote> _genSnow() {
    if (widget.variant != 0) return <_Mote>[];
    return List.generate(70, (_) {
      return _Mote(
        x: _rng.nextDouble(),
        y: _rng.nextDouble(),
        size: 0.6 + _rng.nextDouble() * 1.6,
        speed: 0.015 + _rng.nextDouble() * 0.04,
        phase: _rng.nextDouble() * math.pi * 2,
      );
    });
  }

  List<_Bubble> _genBubbles() => List.generate(12, (_) {
    return _Bubble(
      x: _rng.nextDouble(),
      y: _rng.nextDouble(),
      size: 1.5 + _rng.nextDouble() * 5,
      speed: 0.03 + _rng.nextDouble() * 0.06,
      phase: _rng.nextDouble() * math.pi * 2,
      ephemeral: false,
    );
  });

  List<_Ray> _genRays() => List.generate(5, (_) {
    return _Ray(
      x: _rng.nextDouble(),
      width: 0.05 + _rng.nextDouble() * 0.08,
      slant: (_rng.nextDouble() - 0.5) * 0.3,
      phase: _rng.nextDouble() * math.pi * 2,
    );
  });

  List<_Weed> _genWeeds() => List.generate(26, (_) {
    // Bias roots toward the edges so the kelp frames the open centre.
    final e = _rng.nextDouble();
    final rootX = (e < 0.5 ? e * 0.34 : 0.66 + (e - 0.5) * 0.68).clamp(
      0.0,
      1.0,
    );
    return _Weed(
      rootX: rootX,
      height: 0.24 + _rng.nextDouble() * 0.44,
      amp: 0.015 + _rng.nextDouble() * 0.03,
      width: 4 + _rng.nextDouble() * 5,
      speed: 0.5 + _rng.nextDouble() * 0.6,
      phase: _rng.nextDouble() * math.pi * 2,
      color: Color.fromRGBO(
        12,
        46 + _rng.nextInt(34),
        42 + _rng.nextInt(24),
        0.78,
      ),
    );
  });

  List<_Rock> _genRocks() => List.generate(6, (_) {
    return _Rock(x: _rng.nextDouble(), size: 0.08 + _rng.nextDouble() * 0.13);
  });

  // Darting fish silhouettes — the open-water ambient layer (variant 1 only).
  // A handful of little fish cross horizontally at varied depths, speeds and
  // directions, looping around when they leave the screen, with a gentle
  // vertical bob. Variant 0 has marine snow instead, so no fish there.
  // Fish removed per design. Generating zero keeps the _Fish type / _paintFish
  // referenced (no dead-code warnings) while nothing is ever drawn.
  List<_Fish> _genFish() {
    if (widget.variant != 1) return <_Fish>[];
    return List.generate(0, (_) {
      return _Fish(
        x: _rng.nextDouble(),
        y: 0.18 + _rng.nextDouble() * 0.55,
        size: 8 + _rng.nextDouble() * 13,
        dir: _rng.nextBool() ? 1.0 : -1.0,
        speed: 0.02 + _rng.nextDouble() * 0.05,
        phase: _rng.nextDouble() * math.pi * 2,
        color: _fishColor(_rng),
      );
    });
  }

  @override
  void dispose() {
    widget.reception?.removeListener(_onReception);
    _tilt.dispose();
    _ticker.dispose();
    _model.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final config = widget.variant == 0 ? _seabed : _openWater;
    return Stack(
      children: [
        Positioned.fill(
          child: DecorBackdrop(
            env: 'underwater',
            variant: widget.variant,
            assetRoot: widget.assetRoot,
            parallax: widget.parallax,
            fallback: RepaintBoundary(
              child: CustomPaint(
                painter: _UWPainter(
                  model: _model,
                  snow: _snow,
                  bubbles: _bubbles,
                  rays: _rays,
                  weeds: _weeds,
                  rocks: _rocks,
                  fish: _fish,
                  config: config,
                ),
              ),
            ),
          ),
        ),
        // Ambient FX (fish, plankton, bubbles, glow) overlaid on the image.
        Positioned.fill(
          child: RepaintBoundary(
            child: CustomPaint(
              painter: _UWPainter(
                model: _model,
                snow: _snow,
                bubbles: _bubbles,
                rays: _rays,
                weeds: _weeds,
                rocks: _rocks,
                fish: _fish,
                config: config,
                overlay: true,
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _spawnBubbleBurst,
          ),
        ),
        if (widget.child != null) Positioned.fill(child: widget.child!),
      ],
    );
  }
}

Color _fishColor(math.Random rng) {
  final r = rng.nextDouble();
  if (r < 0.40) return const Color(0xCCE8965A); // warm orange
  if (r < 0.70) return const Color(0xCCC4DCE6); // silver
  if (r < 0.90) return const Color(0xCC7AB0C8); // blue
  return const Color(0xCCE0C060); // gold
}

/// Floor height (normalized 0..1) at horizontal position [xN]. Lower value =
/// higher on screen. Gentle dunes via two sine terms.
double _floorY(double xN) =>
    0.84 -
    0.05 * math.sin(xN * math.pi * 2) -
    0.03 * math.sin(xN * math.pi * 5 + 1.3);

const _seabed = _UWConfig(
  top: Color(0xFF0A3038),
  bottom: Color(0xFF02101A),
  rayStrength: 0.12,
  brightness: 0.6,
  showSeabed: true,
  showFish: false,
  showSnow: true,
);
const _openWater = _UWConfig(
  top: Color(0xFF1C7FA0),
  bottom: Color(0xFF083848),
  rayStrength: 0.5,
  brightness: 1.0,
  showSeabed: false,
  showFish: true,
  showReef: true,
  showSnow: false,
);

class _UWConfig {
  const _UWConfig({
    required this.top,
    required this.bottom,
    required this.rayStrength,
    required this.brightness,
    required this.showSeabed,
    required this.showFish,
    required this.showSnow,
    this.showReef = false,
  });

  final Color top;
  final Color bottom;
  final double rayStrength;
  final double brightness;
  final bool showSeabed;
  final bool showFish;
  // Marine snow / plankton drifts only in the deep seabed scene (variant 0).
  // The open-water scene (variant 1) uses darting fish silhouettes instead, so
  // each variant carries a genuinely distinct ambient particle type.
  final bool showSnow;
  final bool showReef;
}

// Warm reef palette for the "Poissons" coral scene.
const _coralColors = [
  Color(0xFFCBA36A), // tan
  Color(0xFFD98A52), // orange
  Color(0xFFCE7F92), // pink
  Color(0xFFB8A14C), // mustard
  Color(0xFF6E9A86), // teal-green
  Color(0xFFA07AA8), // mauve
];

class _UWModel extends ChangeNotifier {
  double time = 0;
  Offset look = Offset.zero;
  final List<_Glow> glows = [];
  void notify() => notifyListeners();
}

class _Mote {
  _Mote({
    required this.x,
    required this.y,
    required this.size,
    required this.speed,
    required this.phase,
  });
  double x;
  double y;
  final double size;
  final double speed;
  final double phase;
}

class _Bubble {
  _Bubble({
    required this.x,
    required this.y,
    required this.size,
    required this.speed,
    required this.phase,
    required this.ephemeral,
  });
  double x;
  double y;
  final double size;
  final double speed;
  final double phase;
  final bool ephemeral;
}

class _Ray {
  const _Ray({
    required this.x,
    required this.width,
    required this.slant,
    required this.phase,
  });
  final double x;
  final double width;
  final double slant;
  final double phase;
}

class _Weed {
  const _Weed({
    required this.rootX,
    required this.height,
    required this.amp,
    required this.width,
    required this.speed,
    required this.phase,
    required this.color,
  });
  final double rootX;
  final double height;
  final double amp;
  final double width;
  final double speed;
  final double phase;
  final Color color;
}

class _Rock {
  const _Rock({required this.x, required this.size});
  final double x;
  final double size;
}

class _Fish {
  _Fish({
    required this.x,
    required this.y,
    required this.size,
    required this.dir,
    required this.speed,
    required this.phase,
    required this.color,
  });
  double x;
  double y;
  final double size;
  final double dir;
  final double speed;
  final double phase;
  final Color color;
}

class _Glow {
  _Glow(this.center, this.startTime);
  final Offset center;
  final double startTime;
  static const double duration = 1.4;
  double life(double now) => ((now - startTime) / duration).clamp(0.0, 1.0);
}

class _UWPainter extends CustomPainter {
  _UWPainter({
    required this.model,
    required this.snow,
    required this.bubbles,
    required this.rays,
    required this.weeds,
    required this.rocks,
    required this.fish,
    required this.config,
    this.overlay = false,
  }) : super(repaint: model);

  final _UWModel model;
  final List<_Mote> snow;
  final List<_Bubble> bubbles;
  final List<_Ray> rays;
  final List<_Weed> weeds;
  final List<_Rock> rocks;
  final List<_Fish> fish;
  final _UWConfig config;
  // When true, skip the static scene (gradient, surface rays, seabed, reef) and
  // draw ONLY the ambient FX (fish, plankton, bubbles, glow) — the overlay above
  // a DecorBackdrop image. When false it draws the full procedural scene (the
  // load-time fallback).
  final bool overlay;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final rect = Offset.zero & size;
    final time = model.time;
    final lookX = model.look.dx;
    final bright = config.brightness;

    if (!overlay) {
      canvas.drawRect(
        rect,
        Paint()
          ..shader = ui.Gradient.linear(Offset(w / 2, 0), Offset(w / 2, h), [
            config.top,
            config.bottom,
          ]),
      );

      _paintRays(canvas, w, h, time, lookX);
      if (config.showSeabed) _paintPrimaryBeam(canvas, w, h, time, lookX);

      if (config.showSeabed) {
        _paintSeabed(canvas, w, h, time);
      }
      if (config.showReef) {
        _paintReef(canvas, w, h, time);
      }
    }
    if (config.showFish) {
      for (final f in fish) {
        final cy = (f.y + math.sin(time * 1.5 + f.phase) * 0.01) * h;
        _paintFish(canvas, Offset(f.x * w, cy), f.size, f.dir, f.color);
      }
    }

    // Marine snow / plankton — deep-seabed ambient layer only (variant 0).
    if (config.showSnow) {
      for (final m in snow) {
        canvas.drawCircle(
          Offset(m.x * w, m.y * h),
          m.size,
          Paint()..color = Color.fromRGBO(220, 240, 255, 0.3 * bright),
        );
      }
    }

    // Bubbles.
    for (final b in bubbles) {
      final c = Offset(b.x * w, b.y * h);
      canvas.drawCircle(
        c,
        b.size,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0
          ..color = Color.fromRGBO(220, 245, 255, 0.5 * bright),
      );
      canvas.drawCircle(
        c.translate(-b.size * 0.3, -b.size * 0.3),
        b.size * 0.28,
        Paint()..color = Color.fromRGBO(255, 255, 255, 0.6 * bright),
      );
    }

    // Bioluminescent glow when a "pensée" arrives.
    for (final g in model.glows) {
      final t = g.life(time);
      final radius = (0.1 + t * 0.5) * size.shortestSide;
      final center = Offset(g.center.dx * w, g.center.dy * h);
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..blendMode = BlendMode.plus
          ..shader = ui.Gradient.radial(center, radius, [
            Color.fromRGBO(120, 230, 220, (1 - t) * 0.5 * bright),
            const Color(0x00000000),
          ]),
      );
    }

    // Depth vignette.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(w / 2, h * 0.38),
          size.longestSide * 0.8,
          const [Color(0x00000000), Color(0x73000000)],
          const [0.4, 1.0],
        ),
    );
  }

  // One dominant light shaft from the upper-right (matches the seabed photo).
  void _paintPrimaryBeam(
    Canvas canvas,
    double w,
    double h,
    double time,
    double lookX,
  ) {
    final sway = math.sin(time * 0.08) * 0.015 - lookX * 0.2;
    final topX = (0.78 + sway) * w;
    final botX = (0.46 + sway) * w;
    final halfTop = 0.04 * w;
    final halfBot = 0.16 * w;
    final endY = h * 0.72;
    final path = Path()
      ..moveTo(topX - halfTop, 0)
      ..lineTo(topX + halfTop, 0)
      ..lineTo(botX + halfBot, endY)
      ..lineTo(botX - halfBot, endY)
      ..close();
    canvas.drawPath(
      path,
      Paint()
        ..blendMode = BlendMode.plus
        ..shader = ui.Gradient.linear(Offset(topX, 0), Offset(botX, endY), [
          const Color(0xFFBFE6FF).withValues(alpha: 0.42),
          const Color(0x00BFE6FF),
        ]),
    );
  }

  void _paintRays(
    Canvas canvas,
    double w,
    double h,
    double time,
    double lookX,
  ) {
    for (final r in rays) {
      final sway = math.sin(time * 0.12 + r.phase) * 0.04 - lookX * 0.25;
      final topX = (r.x + sway) * w;
      final botX = (r.x + sway + r.slant) * w;
      final halfTop = r.width * 0.5 * w;
      final halfBot = r.width * 1.7 * 0.5 * w;
      final path = Path()
        ..moveTo(topX - halfTop, 0)
        ..lineTo(topX + halfTop, 0)
        ..lineTo(botX + halfBot, h)
        ..lineTo(botX - halfBot, h)
        ..close();
      canvas.drawPath(
        path,
        Paint()
          ..blendMode = BlendMode.plus
          ..shader = ui.Gradient.linear(
            Offset(0, 0),
            Offset(0, h),
            [
              Color.fromRGBO(200, 235, 255, config.rayStrength * 0.35),
              const Color(0x00FFFFFF),
            ],
            const [0.0, 0.8],
          ),
      );
    }
  }

  void _paintSeabed(Canvas canvas, double w, double h, double time) {
    // Floor silhouette filled to the bottom.
    final floor = Path()..moveTo(0, h);
    for (var i = 0; i <= 24; i++) {
      final xN = i / 24;
      floor.lineTo(xN * w, _floorY(xN) * h);
    }
    floor
      ..lineTo(w, h)
      ..close();
    canvas.drawPath(
      floor,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, _floorY(0.5) * h),
          Offset(0, h),
          const [Color(0xFF13323A), Color(0xFF06141A)],
        ),
    );

    // Seaweed swaying up from the floor.
    for (final wd in weeds) {
      final rootX = wd.rootX * w;
      final rootY = _floorY(wd.rootX) * h;
      final path = Path()..moveTo(rootX, rootY);
      const steps = 10;
      for (var i = 1; i <= steps; i++) {
        final t = i / steps;
        final sway =
            math.sin(time * wd.speed + wd.phase + t * 3) * wd.amp * t * w;
        path.lineTo(rootX + sway, rootY - t * wd.height * h);
      }
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = wd.width
          ..strokeCap = StrokeCap.round
          ..color = wd.color,
      );
    }

    // Rocks resting on the floor.
    for (final rock in rocks) {
      final cx = rock.x * w;
      final fy = _floorY(rock.x) * h;
      final rw = rock.size * w;
      final rh = rw * 0.6;
      final center = Offset(cx, fy - rh * 0.3);
      canvas.drawOval(
        Rect.fromCenter(center: center, width: rw, height: rh),
        Paint()..color = const Color(0xFF0B1C22),
      );
      canvas.drawArc(
        Rect.fromCenter(center: center, width: rw * 0.86, height: rh * 0.86),
        math.pi,
        math.pi,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = const Color.fromRGBO(120, 180, 190, 0.16),
      );
    }
  }

  // Sunlit coral reef bed (the "Poissons" photo's foreground).
  void _paintReef(Canvas canvas, double w, double h, double time) {
    double reefY(double xN) =>
        0.82 -
        0.05 * math.sin(xN * math.pi * 3 + 0.6) -
        0.02 * math.sin(xN * math.pi * 7);

    final bed = Path()..moveTo(0, h);
    for (var i = 0; i <= 24; i++) {
      final xN = i / 24;
      bed.lineTo(xN * w, reefY(xN) * h);
    }
    bed
      ..lineTo(w, h)
      ..close();
    canvas.drawPath(
      bed,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, reefY(0.5) * h),
          Offset(0, h),
          const [Color(0xFF2E6E66), Color(0xFF0C2830)],
        ),
    );

    final rng = math.Random(7); // deterministic layout, stable across frames
    for (var i = 0; i < 16; i++) {
      final xN = (i + 0.5) / 16 + (rng.nextDouble() - 0.5) * 0.04;
      final s = h * (0.05 + rng.nextDouble() * 0.06);
      final col = _coralColors[rng.nextInt(_coralColors.length)];
      final seed = rng.nextDouble();
      final base = Offset(xN * w, reefY(xN) * h + 4);
      switch (i % 3) {
        case 0:
          _branchCoral(canvas, base, s, col, seed);
        case 1:
          _brainCoral(canvas, base, s, col);
        default:
          _fanCoral(canvas, base, s, col, time, seed);
      }
    }
  }

  void _branchCoral(
    Canvas canvas,
    Offset base,
    double s,
    Color col,
    double seed,
  ) {
    final paint = Paint()
      ..color = col
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.22
      ..strokeCap = StrokeCap.round;
    final n = 3 + (seed * 3).floor();
    for (var i = 0; i < n; i++) {
      final a = -math.pi / 2 + (i - (n - 1) / 2) * 0.5;
      final mid = base + Offset(math.cos(a), math.sin(a)) * s * 0.6;
      final tip = base + Offset(math.cos(a) * 1.3, math.sin(a) * 1.5) * s;
      canvas.drawPath(
        Path()
          ..moveTo(base.dx, base.dy)
          ..quadraticBezierTo(mid.dx, mid.dy, tip.dx, tip.dy),
        paint,
      );
    }
  }

  void _brainCoral(Canvas canvas, Offset base, double s, Color col) {
    final c = base.translate(0, -s * 0.5);
    canvas.drawOval(
      Rect.fromCenter(center: c, width: s * 2.0, height: s * 1.3),
      Paint()..color = col,
    );
    final groove = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.07
      ..color = Color.lerp(col, Colors.black, 0.35)!;
    for (var i = 0; i < 3; i++) {
      canvas.drawArc(
        Rect.fromCenter(
          center: c,
          width: s * (1.4 - i * 0.4),
          height: s * (0.9 - i * 0.25),
        ),
        math.pi,
        math.pi,
        false,
        groove,
      );
    }
  }

  void _fanCoral(
    Canvas canvas,
    Offset base,
    double s,
    Color col,
    double time,
    double seed,
  ) {
    final sway = math.sin(time * 0.8 + seed * 6) * 0.12;
    final paint = Paint()
      ..color = col
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.05
      ..strokeCap = StrokeCap.round;
    const n = 7;
    for (var i = 0; i < n; i++) {
      final a = -math.pi / 2 + (i - (n - 1) / 2) * 0.16 + sway;
      final mid =
          base + Offset(math.cos(a) * 0.6 + sway, math.sin(a) * 0.8) * s;
      final tip = base + Offset(math.cos(a), math.sin(a)) * s * 1.5;
      canvas.drawPath(
        Path()
          ..moveTo(base.dx, base.dy)
          ..quadraticBezierTo(mid.dx, mid.dy, tip.dx, tip.dy),
        paint,
      );
    }
  }

  void _paintFish(Canvas canvas, Offset c, double s, double dir, Color color) {
    final paint = Paint()..color = color;
    canvas.drawOval(
      Rect.fromCenter(center: c, width: s * 1.9, height: s),
      paint,
    );
    final tx = c.dx - dir * s * 0.95;
    final tail = Path()
      ..moveTo(tx, c.dy)
      ..lineTo(tx - dir * s * 0.7, c.dy - s * 0.55)
      ..lineTo(tx - dir * s * 0.7, c.dy + s * 0.55)
      ..close();
    canvas.drawPath(tail, paint);
    canvas.drawCircle(
      Offset(c.dx + dir * s * 0.55, c.dy - s * 0.08),
      s * 0.1,
      Paint()..color = const Color(0xFF06181E),
    );
  }

  @override
  bool shouldRepaint(_UWPainter old) =>
      old.config.top != config.top ||
      old.config.showSeabed != config.showSeabed ||
      old.config.showFish != config.showFish ||
      old.config.showSnow != config.showSnow;
}
