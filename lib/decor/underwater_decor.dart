import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:dewdrop/decor/decor_backdrop.dart';
import 'package:dewdrop/decor/reception_signal.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

/// Immersive "sous l'eau" decor with two scenes (Fonds marins / Poissons)
/// supplied by the parallax photo/illustrated backdrop. Each variant owns a
/// different ambient particle TYPE — drifting marine snow / plankton (variant 0)
/// vs darting fish (variant 1) — gated by [_UWConfig.showSnow] /
/// [_UWConfig.showFish]; both share rising bubbles and the bubble burst. A tap
/// spawns a light preview burst; a received [ReceptionSignal] pulse spawns the
/// big amplified celebratory swell, flavoured per variant. FX in pure Canvas.
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
  late final List<_Fish> _fish = _genFish();

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
  ///    undulating floor line, and a low cluster of teal glows hugging the bed.
  ///  - variant 1 "Poissons": a bright, fast, wide surge fanned across the full
  ///    width and rising quickly toward the surface — many smaller bubbles and
  ///    glows spread higher where the light is.
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

  // Darting fish silhouettes — the open-water ambient layer (variant 1 only).
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
            baseColor: config.base,
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
                fish: _fish,
                config: config,
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
/// higher on screen. Gentle dunes via two sine terms. Used to seed the seabed
/// reception bubbles so they rise from the (photographed) floor line.
double _floorY(double xN) =>
    0.84 -
    0.05 * math.sin(xN * math.pi * 2) -
    0.03 * math.sin(xN * math.pi * 5 + 1.3);

const _seabed = _UWConfig(
  base: Color(0xFF06141A),
  brightness: 0.6,
  showFish: false,
  showSnow: true,
);
const _openWater = _UWConfig(
  base: Color(0xFF1C7FA0),
  brightness: 1.0,
  showFish: true,
  showSnow: false,
);

class _UWConfig {
  const _UWConfig({
    required this.base,
    required this.brightness,
    required this.showFish,
    required this.showSnow,
  });

  // Dominant tone shown for the one frame before the photo decodes.
  final Color base;
  final double brightness;
  final bool showFish;
  // Marine snow / plankton drifts only in the deep seabed scene (variant 0).
  // The open-water scene (variant 1) uses darting fish silhouettes instead, so
  // each variant carries a genuinely distinct ambient particle type.
  final bool showSnow;
}

class _UWModel extends ChangeNotifier {
  double time = 0;
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

/// Draws ONLY the ambient FX (fish, plankton, bubbles, bioluminescent glow)
/// over the [DecorBackdrop] image — the scene itself is the photo, not a
/// procedural drawing.
class _UWPainter extends CustomPainter {
  _UWPainter({
    required this.model,
    required this.snow,
    required this.bubbles,
    required this.fish,
    required this.config,
  }) : super(repaint: model);

  final _UWModel model;
  final List<_Mote> snow;
  final List<_Bubble> bubbles;
  final List<_Fish> fish;
  final _UWConfig config;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final rect = Offset.zero & size;
    final time = model.time;
    final bright = config.brightness;

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
      old.config.base != config.base ||
      old.config.showFish != config.showFish ||
      old.config.showSnow != config.showSnow;
}
