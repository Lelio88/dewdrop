import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:dewdrop/decor/decor_backdrop.dart';
import 'package:dewdrop/decor/reception_signal.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

/// Immersive "champs" decor — two variants supplied by the parallax photo
/// backdrop:
///  - Variant 0 « Prairie » : a summer wildflower meadow at golden morning.
///  - Variant 1 « Blé » : a wheat field at flaming sunset.
///
/// FX in pure Canvas, over the photo backdrop, like every other decor.
///
/// Ambient layer = warm pollen / golden dust drifting + a few **dandelion seeds**
/// riding the breeze forever, respawning once they sail off an edge.
///
/// Reception effect = a **puff of dandelion seeds blown in from the bottom-left**
/// in **two gusts** (§ _gust): the first sweeps them up and across into view, the
/// breeze lulls and they sink a touch, then a second gust carries them off-screen
/// — slow and dreamy (the "make a wish" image). Each seed integrates toward the
/// wind with its own inertia ([_Seed.drag]) + turbulence, so light seeds whip and
/// heavier ones lag — never a straight line. Each is a small luminous feathery
/// pappus (radial filaments + a soft glow) with its little seed below; white in
/// the Prairie morning, backlit gold in the Blé sunset. Scales with
/// [ReceptionSignal.intensity] — more seeds on a catch-up.
///
/// (Earlier tries — drawn stalks bent by wind, then a photo-mesh ripple — read
/// as an artificial overlay / didn't survive on a fixed photo. Particles, like
/// the other universes, are the right call here.)
///
/// Invariants:
///  - One variant = one real scene (Prairie morning / Blé sunset), same scene in
///    Photo and Drawn — the FX only differ by palette (white vs gold seeds).
class FieldsDecor extends StatefulWidget {
  const FieldsDecor({
    super.key,
    this.variant = 0,
    this.reception,
    this.child,
    this.assetRoot = 'photo',
  });

  final int variant;
  final ReceptionSignal? reception;
  final Widget? child;
  // 'photo' or 'illustrated' — which parallax backdrop the bespoke FX sit on.
  final String assetRoot;

  @override
  State<FieldsDecor> createState() => _FieldsDecorState();
}

class _FieldsDecorState extends State<FieldsDecor>
    with SingleTickerProviderStateMixin {
  final _model = _FieldsModel();
  final math.Random _rng = math.Random(41);
  late final Ticker _ticker;

  // Always-on ambient layer.
  late final List<_Mote> _motes = _genMotes();
  late final List<_Seed> _drift = _genDrift(); // seeds floating up forever

  // Ephemeral reception seeds (self-cull once their life elapses).
  final List<_Seed> _burst = [];

  double _lastTick = 0;

  bool get _wheat => widget.variant == 1;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
    widget.reception?.addListener(_onReception);
  }

  @override
  void didUpdateWidget(FieldsDecor old) {
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

    // Ambient motes drift forever, wrapping around the edges.
    for (final m in _motes) {
      m.x += m.vx * dt;
      m.y += m.vy * dt;
      if (m.y < -0.05) {
        m.y = 1.05;
      } else if (m.y > 1.05) {
        m.y = -0.05;
      }
      if (m.x < -0.05) {
        m.x = 1.05;
      } else if (m.x > 1.05) {
        m.x = -0.05;
      }
    }

    // Shared breeze (gusty, rightward + a gentle lift) — all seeds respond to it.
    final bx = _breezeX(now);
    final by = _breezeY(now);

    // Ambient seeds ride the breeze forever; respawn at the bottom-left once they
    // drift off the top or the right.
    for (var i = 0; i < _drift.length; i++) {
      final s = _drift[i];
      _step(s, now, dt, bx, by);
      if (s.y < -0.14 || s.x > 1.14) {
        _drift[i] = _newSeed(
          x: _rng.nextDouble() * 0.7,
          y: 1.1 + _rng.nextDouble() * 0.05,
          ambient: true,
        );
      }
    }

    // Reception seeds ride the two-gust choreography; cull once spent or carried
    // off the top/right edge.
    if (_burst.isNotEmpty) {
      _burst.removeWhere(
        (s) => now - s.born > s.life || s.x > 1.2 || s.y < -0.2,
      );
      for (final s in _burst) {
        _step(s, now, dt, bx, by);
      }
    }

    _model.notify();
  }

  // The breeze the whole field shares: mostly horizontal (rightward) with slow
  // gusts, plus a gentle upward lift that also breathes.
  double _breezeX(double now) =>
      0.05 +
      0.06 * (0.5 + 0.5 * math.sin(now * 0.25)) +
      0.03 * math.sin(now * 0.09 + 0.7);

  double _breezeY(double now) =>
      -(0.028 + 0.022 * (0.5 + 0.5 * math.sin(now * 0.19 + 1.0)));

  // Reception gust envelope (t from the seed's birth): two bumps with a clear
  // lull between. Gust 1 (~0.6s) sweeps the puff in from the bottom-left; the
  // lull (~1.5–2.8s) lets it sink a little; gust 2 (~3.6s) carries it off-screen.
  double _gust(double t) {
    final g1 = math.exp(-(t - 0.6) * (t - 0.6) / 0.5);
    // Second gust is deliberately stronger + a touch longer — it should whip the
    // whole puff clean off the screen, harder than the entrance gust.
    final g2 = 1.8 * math.exp(-(t - 3.6) * (t - 3.6) / 1.1);
    return g1 + g2;
  }

  // Integrate one seed toward its target wind (rate = drag) then advance; it
  // tumbles faster the faster it is carried. Burst seeds ride the two-gust
  // choreography (up-right gusts + a gentle residual drift + gravity in the
  // lull); ambient seeds ride the gentle continuous breeze.
  void _step(_Seed s, double now, double dt, double bx, double by) {
    final double tx;
    final double ty;
    if (s.life > 0) {
      final g = _gust(now - s.born);
      final lull = (1 - g).clamp(0.0, 1.0);
      tx = 0.05 + g * 0.26 + math.sin(now * 1.7 + s.phase) * 0.03;
      ty = -g * 0.18 + lull * 0.05 + math.cos(now * 1.3 + s.phase) * 0.02;
    } else {
      tx =
          bx +
          math.sin(now * 1.3 + s.phase) * 0.035 +
          math.sin(now * 0.6 + s.phase * 1.7) * 0.02;
      ty = by + s.lift + math.cos(now * 1.1 + s.phase) * 0.03;
    }
    s.vx += (tx - s.vx) * s.drag * dt;
    s.vy += (ty - s.vy) * s.drag * dt;
    s.x += s.vx * dt;
    s.y += s.vy * dt;
    s.rot += (s.rotSpeed + s.vx * 3.0) * dt;
  }

  /// A pensée arrived → a puff of seeds lifts off, sized by the catch-up.
  void _onReception() {
    final k = widget.reception?.intensity ?? 1.0;
    _spawnBurst((22 * k).round());
    HapticFeedback.mediumImpact();
  }

  /// Manual preview (tap): a smaller puff.
  void _tap() {
    _spawnBurst(10);
    HapticFeedback.lightImpact();
  }

  // The whole puff blows in from the BOTTOM-LEFT (some seeds start just off the
  // left edge), all sharing one birth time so the two gusts (see _gust) hit them
  // together: sweep in → settle in the lull → carried off-screen.
  void _spawnBurst(int n) {
    for (var i = 0; i < n; i++) {
      _burst.add(
        _newSeed(
          x: -0.1 + _rng.nextDouble() * 0.32,
          y: 0.78 + _rng.nextDouble() * 0.3,
          ambient: false,
        ),
      );
    }
  }

  // A dandelion seed. Ambient seeds rise slowly forever; burst seeds rise a bit
  // faster, sway more, and carry a finite [life] (with born) so they fade out.
  _Seed _newSeed({
    required double x,
    required double y,
    required bool ambient,
  }) {
    return _Seed(
      x: x,
      y: y,
      // Small initial velocity (a gentle lift-off pop); the breeze + drag take
      // over from here.
      vx: (_rng.nextDouble() - 0.5) * 0.02,
      vy: ambient
          ? -(0.015 + _rng.nextDouble() * 0.02)
          : -(0.05 + _rng.nextDouble() * 0.06),
      size: (ambient ? 7.0 : 6.0) + _rng.nextDouble() * 6.0,
      rot: _rng.nextDouble() * math.pi * 2,
      rotSpeed: (_rng.nextDouble() - 0.5) * (ambient ? 0.7 : 1.2),
      phase: _rng.nextDouble() * math.pi * 2,
      glow: _rng.nextDouble(),
      // Lighter seeds (higher drag) whip with the gusts; heavier ones lag.
      drag: 1.5 + _rng.nextDouble() * 2.2,
      lift: -(_rng.nextDouble() * 0.018),
      life: ambient ? 0 : (6.0 + _rng.nextDouble() * 2.0),
      born: ambient ? 0 : _model.time,
    );
  }

  List<_Seed> _genDrift() => List.generate(
    _wheat ? 3 : 4,
    (_) => _newSeed(x: _rng.nextDouble(), y: _rng.nextDouble(), ambient: true),
  );

  List<_Mote> _genMotes() => List.generate(_wheat ? 32 : 22, (_) {
    return _Mote(
      x: _rng.nextDouble(),
      y: _rng.nextDouble(),
      // Wheat dust drifts sideways; prairie pollen rises gently.
      vx: _wheat
          ? (0.02 + _rng.nextDouble() * 0.04)
          : (_rng.nextDouble() - 0.5) * 0.012,
      vy: _wheat
          ? (_rng.nextDouble() - 0.5) * 0.012
          : -(0.01 + _rng.nextDouble() * 0.02),
      r: 0.8 + _rng.nextDouble() * 1.6,
      phase: _rng.nextDouble() * math.pi * 2,
    );
  });

  // Dominant tone shown for the one frame before the photo decodes.
  Color get _baseColor => _wheat
      ? const Color(0xFFE9A34E) // sunset amber
      : const Color(0xFFB8C77E); // morning meadow gold-green

  @override
  void dispose() {
    widget.reception?.removeListener(_onReception);
    _ticker.dispose();
    _model.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: DecorBackdrop(
            env: 'fields',
            variant: widget.variant,
            assetRoot: widget.assetRoot,
            baseColor: _baseColor,
          ),
        ),
        Positioned.fill(
          child: RepaintBoundary(
            child: CustomPaint(
              painter: _FieldsFxPainter(
                model: _model,
                wheat: _wheat,
                motes: _motes,
                drift: _drift,
                burst: _burst,
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

class _FieldsModel extends ChangeNotifier {
  double time = 0;
  void notify() => notifyListeners();
}

/// An always-on ambient particle (prairie pollen / wheat golden dust).
class _Mote {
  _Mote({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.r,
    required this.phase,
  });
  double x;
  double y;
  final double vx;
  final double vy;
  final double r;
  final double phase;
}

/// A dandelion seed: a feathery pappus + a little seed below, carried by the
/// breeze. [vx]/[vy] are integrated each tick (the seed accelerates toward the
/// breeze + its own turbulence at rate [drag] — light seeds whip, heavy ones
/// lag). [lift] is its individual buoyancy. When [life] is 0 it is an ambient
/// looping seed; otherwise a reception seed that fades over [life] from [born].
class _Seed {
  _Seed({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.size,
    required this.rot,
    required this.rotSpeed,
    required this.phase,
    required this.glow,
    required this.drag,
    required this.lift,
    required this.life,
    required this.born,
  });
  double x;
  double y;
  double rot;
  double vx;
  double vy;
  final double size;
  final double rotSpeed;
  final double phase;
  final double glow;
  final double drag;
  final double lift;
  final double life;
  final double born;
}

class _FieldsFxPainter extends CustomPainter {
  _FieldsFxPainter({
    required this.model,
    required this.wheat,
    required this.motes,
    required this.drift,
    required this.burst,
  }) : super(repaint: model);

  final _FieldsModel model;
  final bool wheat;
  final List<_Mote> motes;
  final List<_Seed> drift;
  final List<_Seed> burst;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final now = model.time;

    // Ambient motes: warm pollen (prairie) / golden dust (wheat).
    final moteColor = wheat ? const Color(0xFFFFE8A8) : const Color(0xFFFFF6D8);
    for (final m in motes) {
      final x = (m.x + math.sin(now * 0.3 + m.phase) * 0.01) * w;
      final y = m.y * h;
      final tw = 0.4 + 0.6 * (0.5 + 0.5 * math.sin(now * 1.2 + m.phase));
      canvas.drawCircle(
        Offset(x, y),
        m.r,
        Paint()..color = moteColor.withValues(alpha: (wheat ? 0.5 : 0.42) * tw),
      );
    }

    // Ambient seeds: full presence with a gentle twinkle.
    for (final s in drift) {
      final tw = 0.7 + 0.3 * (0.5 + 0.5 * math.sin(now * 1.5 + s.phase));
      _drawSeed(canvas, w, h, s, tw);
    }
    // Reception seeds: fade in on lift-off, fade out near the end of life.
    for (final s in burst) {
      final age = now - s.born;
      final fin = (age / 0.5).clamp(0.0, 1.0);
      final fout = ((s.life - age) / 1.2).clamp(0.0, 1.0);
      _drawSeed(canvas, w, h, s, fin * fout);
    }

    // Depth vignette.
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(w / 2, h * 0.42),
          size.longestSide * 0.85,
          const [Color(0x00000000), Color(0x3D000000)],
          const [0.5, 1.0],
        ),
    );
  }

  // A dandelion seed: a soft luminous pappus (radial feathery filaments + a glow)
  // with a thin beak and a little seed body hanging below. White in the prairie,
  // backlit gold in the wheat.
  void _drawSeed(Canvas canvas, double w, double h, _Seed s, double alpha) {
    if (alpha <= 0) return;
    final size = s.size;
    canvas.save();
    canvas.translate(s.x * w, s.y * h);
    canvas.rotate(s.rot);

    final pappus = wheat ? const Color(0xFFFFF2D0) : const Color(0xFFFFFFFF);
    final glowC = wheat ? const Color(0xFFFFD98E) : const Color(0xFFFFF6E2);
    final hub = Offset(0, -size * 0.12);

    // Soft luminous halo + a brighter tight core (reads as a glowing puff).
    canvas.drawCircle(
      hub,
      size * 1.1,
      Paint()
        ..blendMode = BlendMode.plus
        ..color = glowC.withValues(alpha: 0.26 * alpha * (0.6 + 0.4 * s.glow)),
    );
    canvas.drawCircle(
      hub,
      size * 0.42,
      Paint()
        ..blendMode = BlendMode.plus
        ..color = glowC.withValues(alpha: 0.40 * alpha),
    );

    // Feathery parachute filaments radiating from the hub.
    final fil = Paint()
      ..strokeWidth = math.max(0.7, size * 0.05)
      ..strokeCap = StrokeCap.round
      ..color = pappus.withValues(alpha: 0.62 * alpha);
    final tipPaint = Paint()..color = pappus.withValues(alpha: 0.5 * alpha);
    const n = 14;
    for (var i = 0; i < n; i++) {
      final a = (i / n) * math.pi * 2;
      final tip = hub + Offset(math.cos(a), math.sin(a)) * size;
      canvas.drawLine(hub, tip, fil);
      canvas.drawCircle(tip, size * 0.05, tipPaint);
    }

    // Beak + seed body hanging below the hub.
    canvas.drawLine(
      hub,
      Offset(0, size * 0.42),
      Paint()
        ..strokeWidth = math.max(0.5, size * 0.04)
        ..strokeCap = StrokeCap.round
        ..color = const Color(0xFF7A6038).withValues(alpha: 0.55 * alpha),
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(0, size * 0.56),
        width: size * 0.16,
        height: size * 0.4,
      ),
      Paint()..color = const Color(0xFF6B5436).withValues(alpha: 0.65 * alpha),
    );

    canvas.restore();
  }

  @override
  bool shouldRepaint(_FieldsFxPainter old) => old.wheat != wheat;
}
