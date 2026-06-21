import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:dewdrop/decor/decor_backdrop.dart';
import 'package:dewdrop/decor/reception_signal.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

/// Immersive "désert" decor — flowing sand dunes. Two variants (Dunes / Étoilé)
/// supplied by the parallax photo/illustrated backdrop. Both carry ambient
/// wind-blown sand drifting left → right; the night variant adds twinkling
/// stars and OCCASIONAL shooting stars. A tap or a received pensée raises a
/// SANDSTORM sweeping the scene. FX in pure Canvas.
class DesertDecor extends StatefulWidget {
  const DesertDecor({
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
  State<DesertDecor> createState() => _DesertDecorState();
}

class _DesertDecorState extends State<DesertDecor>
    with SingleTickerProviderStateMixin {
  final _model = _DesertModel();
  final math.Random _rng = math.Random(19);
  late final Ticker _ticker;
  late final List<_DStar> _stars = _genStars();
  late final List<_Grain> _grains = _genGrains();
  double _lastTick = 0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((e) {
      final now = e.inMicroseconds / 1e6;
      final dt = (now - _lastTick).clamp(0.0, 0.05);
      _lastTick = now;
      _model.time = now;
      // Drift the ambient sand grains left → right; faster during a sandstorm.
      final boost =
          (now - _model.storm) < _stormLife * (1 + (_model.stormK - 1) * 0.5)
          ? 3.0
          : 1.0;
      for (final g in _grains) {
        g.x += g.speed * boost * dt;
        if (g.x > 1.06) {
          g.x = -0.06;
          g.y = _grainY(_rng);
        }
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

  // Ambient wind-blown sand: ~140 grains drifting left → right. TUNABLE: count
  // (density of the breeze) and speed range below.
  List<_Grain> _genGrains() => List.generate(140, (_) {
    return _Grain(
      x: _rng.nextDouble(),
      y: _grainY(_rng),
      speed: 0.04 + _rng.nextDouble() * 0.10,
      len: 4 + _rng.nextDouble() * 10,
      alpha: 0.20 + _rng.nextDouble() * 0.30,
    );
  });

  /// Manual preview: triggers the full sandstorm (same as a received pensée) so
  /// the effect is visible on a tap.
  void _tap() {
    _model.storm = _model.time;
    _model.stormK = 1.0; // a tap is always a single-strength storm
    HapticFeedback.lightImpact();
  }

  /// A pensée arrived: a SANDSTORM — a dense, fast wall of sand sweeps left →
  /// right across the whole scene for ~1.8s then settles. Same flavour on both
  /// variants (the ambient grains also speed up during the window — see ticker).
  void _onReception() {
    // Intensity (how many pensées were caught up at once) makes the sandstorm
    // bigger + last longer (see the ticker boost window and the fx painter).
    _model.storm = _model.time;
    _model.stormK = widget.reception?.intensity ?? 1.0;
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
          child: DecorBackdrop(
            env: 'desert',
            variant: widget.variant,
            assetRoot: widget.assetRoot,
            baseColor: cfg.skyTop,
            // Night: shooting stars stream from the deepest mid-stack slot so
            // they pass BEHIND the dunes. Several ambient meteors at once.
            midFx: cfg.night
                ? RepaintBoundary(
                    child: CustomPaint(
                      painter: _DesertShootingStarsPainter(model: _model),
                    ),
                  )
                : null,
            midFxBelow: 1,
          ),
        ),
        Positioned.fill(
          child: RepaintBoundary(
            child: CustomPaint(
              painter: _DesertFxPainter(
                model: _model,
                cfg: cfg,
                stars: _stars,
                grains: _grains,
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

// Sandstorm duration (seconds) — fired by a tap or a received pensée.
const double _stormLife = 4.5;

// Where ambient sand drifts vertically — mostly across the lower two-thirds.
double _grainY(math.Random r) => 0.34 + r.nextDouble() * 0.62;

class _DesertModel extends ChangeNotifier {
  double time = 0;
  double storm = -10; // sandstorm trigger time (tap or reception)
  double stormK = 1.0; // intensity of that storm (1 = one pensée / a tap)

  void notify() => notifyListeners();
}

/// One ambient wind-blown sand streak drifting left → right. [x]/[y] mutate as
/// the ticker advances it; [speed] is in screen-fractions per second.
class _Grain {
  _Grain({
    required this.x,
    required this.y,
    required this.speed,
    required this.len,
    required this.alpha,
  });
  double x;
  double y;
  final double speed;
  final double len;
  final double alpha;
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

class _DesertFxPainter extends CustomPainter {
  _DesertFxPainter({
    required this.model,
    required this.cfg,
    required this.stars,
    required this.grains,
  }) : super(repaint: model);

  final _DesertModel model;
  final _DesertConfig cfg;
  final List<_DStar> stars;
  final List<_Grain> grains;

  // Real sand colour — warm BEIGE (not white), a touch lighter at night so the
  // grains still read on the dark dunes.
  Color get _sand =>
      cfg.night ? const Color(0xFFE0CDA2) : const Color(0xFFCBB082);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final time = model.time;

    if (cfg.night) {
      // Twinkling stars — the shooting stars live in the mid-stack painter so
      // they pass behind the dunes (see _DesertShootingStarsPainter).
      for (final s in stars) {
        final a = s.twinkle * (0.55 + 0.45 * math.sin(time * 1.5 + s.phase));
        canvas.drawCircle(
          Offset(s.x * w, s.y * h),
          s.r,
          Paint()..color = Color.fromRGBO(255, 255, 255, a.clamp(0.0, 1.0)),
        );
      }
    }

    // Ambient wind-blown sand drifting left → right (both variants): real
    // GRAINS (tiny round specks), not streaks. Brighter while a storm sweeps.
    final storming =
        (time - model.storm) < _stormLife * (1 + (model.stormK - 1) * 0.5);
    final grainPaint = Paint()..style = PaintingStyle.fill;
    for (final g in grains) {
      final x = g.x * w;
      final y = g.y * h;
      final gr = (g.len * 0.16).clamp(1.0, 2.4);
      canvas.drawCircle(
        Offset(x, y),
        gr,
        grainPaint
          ..color = _sand.withValues(
            alpha: (g.alpha * (storming ? 1.8 : 1.0)).clamp(0.0, 1.0),
          ),
      );
    }

    // SANDSTORM (big, dense, full-screen wall of grains): a fast cloud of sand
    // specks sweeps left → right. Fired by both a tap and a received pensée.
    // Intensity scales the storm: a longer window and a denser wall of sand
    // (count capped so a big catch-up never janks low-end devices).
    final stormScale = 1 + (model.stormK - 1) * 0.5;
    _sweep(
      canvas,
      w,
      h,
      time - model.storm,
      _stormLife * stormScale,
      math.min((850 * model.stormK).round(), 1700),
      1.5,
    );
  }

  // A burst of fast wind-blown sand GRAINS sweeping left → right over [life]
  // seconds. [count] specks spread across the FULL height (a real storm wall),
  // faded in/out by an envelope and scaled by [strength].
  void _sweep(
    Canvas canvas,
    double w,
    double h,
    double elapsed,
    double life,
    int count,
    double strength,
  ) {
    if (elapsed < 0 || elapsed > life) return;
    final t = elapsed / life;
    final env = (t < 0.18 ? t / 0.18 : 1 - (t - 0.18) / 0.82).clamp(0.0, 1.0);
    final rng = math.Random(1234);
    final paint = Paint()..style = PaintingStyle.fill;
    for (var i = 0; i < count; i++) {
      final baseX = rng.nextDouble();
      final y = rng.nextDouble() * h; // full-height wall of sand
      final speed = 1.1 + rng.nextDouble() * 1.2;
      final x = ((baseX + elapsed * speed) % 1.2 - 0.1) * w;
      final gr = 0.8 + rng.nextDouble() * 1.8;
      canvas.drawCircle(
        Offset(x, y),
        gr,
        paint
          ..color = _sand.withValues(
            alpha: (0.6 * env * strength * (0.4 + rng.nextDouble() * 0.6))
                .clamp(0.0, 1.0),
          ),
      );
    }
  }

  @override
  bool shouldRepaint(_DesertFxPainter old) => false;
}

/// Night shooting stars, rendered as a mid-stack [DecorBackdrop.midFx] so they
/// pass BEHIND the dunes. OCCASIONAL only — a meteor now and then, with gaps —
/// never a stream (reception is a sandstorm, not a star shower). TUNABLE:
/// _ambientTracks and _period set how often a star appears.
class _DesertShootingStarsPainter extends CustomPainter {
  _DesertShootingStarsPainter({required this.model}) : super(repaint: model);
  final _DesertModel model;

  // 2 tracks on a 12s cycle, offset by half a period → roughly one star every
  // ~6s, never two at once: "de temps en temps".
  static const int _ambientTracks = 2;
  static const double _period = 12.0;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final time = model.time;
    for (var k = 0; k < _ambientTracks; k++) {
      final local = (time - k * (_period / _ambientTracks)) % _period;
      final fromX = 0.06 + (k / _ambientTracks) * 0.5;
      _star(
        canvas,
        w,
        h,
        elapsed: local,
        from: Offset(w * fromX, h * (0.06 + (k % 3) * 0.04)),
        to: Offset(w * (fromX + 0.45), h * (0.32 + (k % 3) * 0.05)),
      );
    }
  }

  void _star(
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
        ..shader = ui.Gradient.linear(tail, head, [
          const Color(0x00FFFFFF),
          Color.fromRGBO(255, 255, 255, fade),
        ]),
    );
  }

  @override
  bool shouldRepaint(_DesertShootingStarsPainter old) => false;
}
