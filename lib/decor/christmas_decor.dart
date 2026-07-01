import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:dewdrop/decor/decor_backdrop.dart';
import 'package:dewdrop/decor/reception_signal.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

/// Seasonal « Noël » decor — a cozy living-room interior (photo/illustrated
/// backdrop) with two Canvas FX layered over it:
///  - ambient **snow** falling past the window, swaying on the draught and
///    wrapping from the bottom back to the top forever;
///  - a warm **fireplace glow** in the left corner that flickers like embers.
///
/// Reception (a pensée arrived) = a short flurry of faster snow + a brighter
/// flare of the hearth ([_SceneModel.flare], decays on its own). Single variant:
/// the marronnier locks the world, so there is nothing to switch between.
///
/// Invariant: one scene, same in Photo and Drawn; the FX only sit on top.
class ChristmasDecor extends StatefulWidget {
  const ChristmasDecor({
    super.key,
    this.variant = 0,
    this.reception,
    this.child,
    this.assetRoot = 'photo',
  });

  final int variant;
  final ReceptionSignal? reception;
  final Widget? child;
  final String assetRoot;

  @override
  State<ChristmasDecor> createState() => _ChristmasDecorState();
}

class _ChristmasDecorState extends State<ChristmasDecor>
    with SingleTickerProviderStateMixin {
  final _model = _SceneModel();
  final math.Random _rng = math.Random(24);
  late final Ticker _ticker;
  late final List<_Flake> _flakes = List.generate(
    46,
    (_) => _newFlake(x: _rng.nextDouble(), y: _rng.nextDouble()),
  );
  final List<_Flake> _burst = [];
  double _lastTick = 0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
    widget.reception?.addListener(_onReception);
  }

  @override
  void didUpdateWidget(ChristmasDecor old) {
    super.didUpdateWidget(old);
    if (old.reception != widget.reception) {
      old.reception?.removeListener(_onReception);
      widget.reception?.addListener(_onReception);
    }
  }

  _Flake _newFlake({required double x, required double y, bool fast = false}) =>
      _Flake(
        x: x,
        y: y,
        vy: (fast ? 0.11 : 0.045) + _rng.nextDouble() * (fast ? 0.09 : 0.05),
        size: 1.2 + _rng.nextDouble() * 2.6,
        phase: _rng.nextDouble() * math.pi * 2,
        sway: 0.012 + _rng.nextDouble() * 0.02,
      );

  void _onTick(Duration elapsed) {
    final now = elapsed.inMicroseconds / 1e6;
    final dt = (now - _lastTick).clamp(0.0, 0.05);
    _lastTick = now;
    _model.time = now;
    _model.flare = math.max(0, _model.flare - dt * 1.4);

    for (final f in _flakes) {
      _stepFlake(f, now, dt);
      if (f.y > 1.05) {
        f.y = -0.05;
        f.x = _rng.nextDouble();
      }
    }
    if (_burst.isNotEmpty) {
      _burst.removeWhere((f) => f.y > 1.1);
      for (final f in _burst) {
        _stepFlake(f, now, dt);
      }
    }
    _model.notify();
  }

  void _stepFlake(_Flake f, double now, double dt) {
    f.y += f.vy * dt;
    f.x += math.sin(now * 0.6 + f.phase) * f.sway * dt;
  }

  void _onReception() {
    final k = widget.reception?.intensity ?? 1.0;
    _model.flare = (0.8 * k).clamp(0.0, 1.2);
    for (var i = 0; i < (18 * k).round(); i++) {
      _burst.add(
        _newFlake(
          x: _rng.nextDouble(),
          y: -0.05 - _rng.nextDouble() * 0.3,
          fast: true,
        ),
      );
    }
    HapticFeedback.mediumImpact();
  }

  void _tap() {
    _model.flare = 0.5;
    for (var i = 0; i < 8; i++) {
      _burst.add(_newFlake(x: _rng.nextDouble(), y: -0.05, fast: true));
    }
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
    return Stack(
      children: [
        Positioned.fill(
          child: DecorBackdrop(
            env: 'christmas',
            variant: widget.variant,
            assetRoot: widget.assetRoot,
            baseColor: const Color(0xFF3A2A1C), // warm dark interior
          ),
        ),
        Positioned.fill(
          child: RepaintBoundary(
            child: CustomPaint(
              painter: _ChristmasFx(
                model: _model,
                flakes: _flakes,
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

class _SceneModel extends ChangeNotifier {
  double time = 0;
  double flare = 0; // 0..~1.2 hearth flare from a reception, decays
  void notify() => notifyListeners();
}

/// A snowflake: falls at [vy], drifts on a per-flake sinusoidal [sway].
class _Flake {
  _Flake({
    required this.x,
    required this.y,
    required this.vy,
    required this.size,
    required this.phase,
    required this.sway,
  });
  double x;
  double y;
  final double vy;
  final double size;
  final double phase;
  final double sway;
}

class _ChristmasFx extends CustomPainter {
  _ChristmasFx({required this.model, required this.flakes, required this.burst})
    : super(repaint: model);

  final _SceneModel model;
  final List<_Flake> flakes;
  final List<_Flake> burst;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final now = model.time;

    // Fireplace glow (left corner), flickering like embers + a reception flare.
    final flick = 0.5 + 0.5 * math.sin(now * 7.0) * math.sin(now * 2.3 + 1.0);
    final glowA = (0.14 + 0.12 * flick + model.flare * 0.5).clamp(0.0, 0.7);
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..blendMode = BlendMode.plus
        ..shader = ui.Gradient.radial(
          Offset(w * 0.09, h * 0.60),
          size.shortestSide * 0.95,
          [
            const Color(0xFFFF8A3D).withValues(alpha: glowA),
            const Color(0x00FF8A3D),
          ],
          const [0.0, 1.0],
        ),
    );

    // Snow (ambient + reception flurry).
    for (final f in flakes) {
      _drawFlake(canvas, w, h, f, now);
    }
    for (final f in burst) {
      _drawFlake(canvas, w, h, f, now);
    }
  }

  void _drawFlake(Canvas c, double w, double h, _Flake f, double now) {
    final tw = 0.6 + 0.4 * (0.5 + 0.5 * math.sin(now * 2 + f.phase));
    c.drawCircle(
      Offset(f.x * w, f.y * h),
      f.size,
      Paint()..color = Colors.white.withValues(alpha: 0.85 * tw),
    );
  }

  @override
  bool shouldRepaint(_ChristmasFx old) => false;
}
