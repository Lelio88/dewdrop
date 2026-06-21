import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:dewdrop/decor/decor_backdrop.dart';
import 'package:dewdrop/decor/reception_signal.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

/// Immersive "plage" decor — a paradise tropical shore. Two variants (Jour /
/// Coucher) supplied by the parallax photo/illustrated backdrop. Gliding birds
/// and ambient fireflies animate on top; a received pensée makes the fireflies
/// surge (every one flares + a small extra swarm drifts in). FX in pure Canvas.
class BeachDecor extends StatefulWidget {
  const BeachDecor({
    super.key,
    this.variant = 0,
    this.reception,
    this.child,
    this.assetRoot = 'photo',
  });

  // 'photo' or 'illustrated' — which parallax backdrop the bespoke FX sit on.
  final String assetRoot;

  final int variant;
  final ReceptionSignal? reception;
  final Widget? child;

  @override
  State<BeachDecor> createState() => _BeachDecorState();
}

class _BeachDecorState extends State<BeachDecor>
    with SingleTickerProviderStateMixin {
  final _model = _BeachModel();
  final math.Random _rng = math.Random(23);
  late final Ticker _ticker;
  late final List<_Firefly> _fireflies = _genFireflies();
  // Ephemeral extra fireflies that drift in on a reception "surge"; self-cull.
  final List<_Firefly> _surge = [];
  double _lastTick = 0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((e) {
      final now = e.inMicroseconds / 1e6;
      final dt = (now - _lastTick).clamp(0.0, 0.05);
      _lastTick = now;
      _model.time = now;
      _advanceFireflies(_fireflies, dt);
      if (_surge.isNotEmpty) {
        _advanceFireflies(_surge, dt);
        _surge.removeWhere(
          (f) => now - f.born > _surgeFlyLife * (1 + (_model.surgeK - 1) * 0.5),
        );
      }
      _model.notify();
    })..start();
    widget.reception?.addListener(_onReception);
  }

  @override
  void didUpdateWidget(BeachDecor old) {
    super.didUpdateWidget(old);
    if (old.reception != widget.reception) {
      old.reception?.removeListener(_onReception);
      widget.reception?.addListener(_onReception);
    }
  }

  // ~28 fireflies drifting slowly in the lower half, blinking out of phase.
  // TUNABLE: count (density) and the drift/size ranges below.
  List<_Firefly> _genFireflies() => List.generate(28, (_) {
    return _Firefly(
      x: _rng.nextDouble(),
      y: 0.48 + _rng.nextDouble() * 0.52,
      vx: (_rng.nextDouble() - 0.5) * 0.04,
      vy: (_rng.nextDouble() - 0.5) * 0.03,
      phase: _rng.nextDouble() * math.pi * 2,
      freq: 0.8 + _rng.nextDouble() * 1.4,
      size: 1.2 + _rng.nextDouble() * 1.4,
    );
  });

  void _advanceFireflies(List<_Firefly> flies, double dt) {
    for (final f in flies) {
      f.x += f.vx * dt;
      f.y += f.vy * dt;
      // Keep them wandering within the lower-half band; wrap at the edges.
      if (f.x < -0.04) f.x = 1.04;
      if (f.x > 1.04) f.x = -0.04;
      if (f.y < 0.42) f.y = 1.02;
      if (f.y > 1.04) f.y = 0.44;
    }
  }

  /// Spawn the firefly surge: every ambient fly flares at once and a small extra
  /// swarm drifts in (ephemeral), then it all settles back. Shared by the
  /// reception pulse and the manual tap preview.
  void _spawnSurge([double k = 1.0]) {
    _model.surge = _model.time;
    _model.surgeK = k;
    for (var i = 0; i < (16 * k).round(); i++) {
      _surge.add(
        _Firefly(
          x: _rng.nextDouble(),
          y: 0.5 + _rng.nextDouble() * 0.5,
          vx: (_rng.nextDouble() - 0.5) * 0.06,
          vy: (_rng.nextDouble() - 0.5) * 0.05,
          phase: _rng.nextDouble() * math.pi * 2,
          freq: 1.0 + _rng.nextDouble() * 1.6,
          size: 1.4 + _rng.nextDouble() * 1.6,
          born: _model.time,
        ),
      );
    }
  }

  /// A pensée arrived: fire the firefly surge, scaled by how many pensées were
  /// caught up at once (a bigger swarm that flares + lingers longer).
  void _onReception() {
    _spawnSurge(widget.reception?.intensity ?? 1.0);
    HapticFeedback.mediumImpact();
  }

  /// Manual preview: tapping the scene fires the same surge (lighter haptic).
  void _tap() {
    _spawnSurge();
    HapticFeedback.lightImpact();
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
    final daytime = widget.variant == 0;
    // Beach: gliding birds + ambient fireflies; a received pensée makes the
    // fireflies surge (every one flares + a small extra swarm drifts in).
    return Stack(
      children: [
        Positioned.fill(
          child: DecorBackdrop(
            env: 'beach',
            variant: widget.variant,
            assetRoot: widget.assetRoot,
            baseColor: daytime
                ? const Color(0xFF2E86C8) // Jour — turquoise sky
                : const Color(0xFF3A2A5E), // Coucher — dusky violet sky
          ),
        ),
        Positioned.fill(
          child: RepaintBoundary(
            child: CustomPaint(
              painter: _BeachFxPainter(
                model: _model,
                daytime: daytime,
                fireflies: _fireflies,
                surge: _surge,
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

// Reception "surge" flare window, and how long the extra swarm flies live (s).
const double _surgeLife = 1.6;
const double _surgeFlyLife = 2.6;

class _BeachModel extends ChangeNotifier {
  double time = 0;
  double surge = -10; // last reception surge trigger time
  double surgeK = 1.0; // intensity of that surge (1 = one pensée / a tap)
  void notify() => notifyListeners();
}

/// A drifting, blinking firefly. [born] is the spawn time for ephemeral surge
/// flies (so they can fade out); persistent ambient flies use -1. Mutable: the
/// ticker advances [x]/[y].
class _Firefly {
  _Firefly({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.phase,
    required this.freq,
    required this.size,
    this.born = -1,
  });
  double x;
  double y;
  final double vx;
  final double vy;
  final double phase;
  final double freq;
  final double size;
  final double born;
}

class _BeachFxPainter extends CustomPainter {
  _BeachFxPainter({
    required this.model,
    required this.daytime,
    required this.fireflies,
    required this.surge,
  }) : super(repaint: model);

  final _BeachModel model;
  final bool daytime;
  final List<_Firefly> fireflies;
  final List<_Firefly> surge;

  // Firefly glow halo — warm yellow-green.
  static const Color _fireflyGlow = Color(0xFFB6FF5A);
  // Saturated firefly core — drawn with a NORMAL blend so the firefly reads the
  // SAME yellow-green on the bright day sky as on the dark sunset (an additive
  // core washes out to white over a light background).
  static const Color _fireflyCore = Color(0xFF8FE000);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final time = model.time;

    // Gliding birds…
    _paintBirds(canvas, w, h, time);
    // …and ambient fireflies (which surge on reception).
    _paintFireflies(canvas, w, h, time);

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
    final col = daytime ? const Color(0x99203040) : const Color(0x88160E14);
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

  // Ambient fireflies: warm yellow-green points that drift and blink out of
  // phase. On a reception surge every one flares bright and an extra swarm
  // (the ephemeral [surge] list) fades in then out.
  void _paintFireflies(Canvas canvas, double w, double h, double time) {
    final flare =
        (1 -
                (time - model.surge) /
                    (_surgeLife * (1 + (model.surgeK - 1) * 0.5)))
            .clamp(0.0, 1.0);

    void drawFlies(List<_Firefly> flies, {required bool ephemeral}) {
      for (final f in flies) {
        // Sharp blink: mostly dim with brief bright pulses.
        final pulse = math
            .pow(0.5 + 0.5 * math.sin(time * f.freq + f.phase), 3)
            .toDouble();
        var a = (0.22 + 0.78 * pulse + flare).clamp(0.0, 1.0);
        if (ephemeral) {
          final age = time - f.born;
          final inFade = (age / 0.3).clamp(0.0, 1.0);
          final outFade =
              (1 - age / (_surgeFlyLife * (1 + (model.surgeK - 1) * 0.5)))
                  .clamp(0.0, 1.0);
          a *= inFade * outFade;
        }
        if (a <= 0.02) continue;
        final c = Offset(f.x * w, f.y * h);
        // Additive glow halo (reads as light bloom on either background).
        canvas.drawCircle(
          c,
          f.size * 3.0,
          Paint()
            ..blendMode = BlendMode.plus
            ..color = _fireflyGlow.withValues(alpha: 0.18 * a),
        );
        // Saturated coloured core (NORMAL blend) — same hue on both variants.
        canvas.drawCircle(
          c,
          f.size * 1.2,
          Paint()
            ..color = _fireflyCore.withValues(
              alpha: (0.95 * a).clamp(0.0, 1.0),
            ),
        );
        // Tiny additive hot point for a glint.
        canvas.drawCircle(
          c,
          f.size * 0.5,
          Paint()
            ..blendMode = BlendMode.plus
            ..color = Colors.white.withValues(alpha: 0.7 * a),
        );
      }
    }

    drawFlies(fireflies, ephemeral: false);
    drawFlies(surge, ephemeral: true);
  }

  @override
  bool shouldRepaint(_BeachFxPainter old) => old.daytime != daytime;
}
