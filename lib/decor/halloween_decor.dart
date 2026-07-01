import 'dart:math' as math;

import 'package:dewdrop/decor/decor_backdrop.dart';
import 'package:dewdrop/decor/reception_signal.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

/// Seasonal « Halloween » decor — a misty pumpkin forest at night (photo/
/// illustrated backdrop) with two Canvas FX over it:
///  - low **fog** banks drifting slowly sideways near the ground;
///  - warm floating **orbs** (will-o'-the-wisps) that bob, twinkle and drift,
///    wrapping forever.
///
/// Reception (a pensée arrived) = a surge of extra orbs rising from the ground
/// + a brighter twinkle. Single variant (the marronnier locks the world).
class HalloweenDecor extends StatefulWidget {
  const HalloweenDecor({
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
  State<HalloweenDecor> createState() => _HalloweenDecorState();
}

class _HalloweenDecorState extends State<HalloweenDecor>
    with SingleTickerProviderStateMixin {
  final _model = _SceneModel();
  final math.Random _rng = math.Random(31);
  late final Ticker _ticker;
  late final List<_Orb> _orbs = List.generate(
    20,
    (_) => _newOrb(ambient: true),
  );
  final List<_Orb> _burst = [];
  double _lastTick = 0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
    widget.reception?.addListener(_onReception);
  }

  @override
  void didUpdateWidget(HalloweenDecor old) {
    super.didUpdateWidget(old);
    if (old.reception != widget.reception) {
      old.reception?.removeListener(_onReception);
      widget.reception?.addListener(_onReception);
    }
  }

  _Orb _newOrb({required bool ambient}) => _Orb(
    x: _rng.nextDouble(),
    y: ambient ? _rng.nextDouble() : 0.9 + _rng.nextDouble() * 0.15,
    vx: (_rng.nextDouble() - 0.5) * 0.02,
    vy: ambient
        ? -(0.006 + _rng.nextDouble() * 0.012)
        : -(0.05 + _rng.nextDouble() * 0.05),
    size: 1.6 + _rng.nextDouble() * 2.8,
    phase: _rng.nextDouble() * math.pi * 2,
    life: ambient ? 0 : (4.0 + _rng.nextDouble() * 2.0),
    born: ambient ? 0 : _model.time,
  );

  void _onTick(Duration elapsed) {
    final now = elapsed.inMicroseconds / 1e6;
    final dt = (now - _lastTick).clamp(0.0, 0.05);
    _lastTick = now;
    _model.time = now;
    _model.surge = math.max(0, _model.surge - dt * 0.8);

    for (final o in _orbs) {
      _stepOrb(o, now, dt);
      if (o.y < -0.06) {
        o.y = 1.06;
        o.x = _rng.nextDouble();
      }
      if (o.x < -0.06) {
        o.x = 1.06;
      } else if (o.x > 1.06) {
        o.x = -0.06;
      }
    }
    if (_burst.isNotEmpty) {
      _burst.removeWhere((o) => now - o.born > o.life || o.y < -0.1);
      for (final o in _burst) {
        _stepOrb(o, now, dt);
      }
    }
    _model.notify();
  }

  void _stepOrb(_Orb o, double now, double dt) {
    o.x += (o.vx + math.sin(now * 0.8 + o.phase) * 0.01) * dt;
    o.y += o.vy * dt;
  }

  void _onReception() {
    final k = widget.reception?.intensity ?? 1.0;
    _model.surge = (0.9 * k).clamp(0.0, 1.4);
    for (var i = 0; i < (14 * k).round(); i++) {
      _burst.add(_newOrb(ambient: false));
    }
    HapticFeedback.mediumImpact();
  }

  void _tap() {
    _model.surge = 0.6;
    for (var i = 0; i < 7; i++) {
      _burst.add(_newOrb(ambient: false));
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
            env: 'halloween',
            variant: widget.variant,
            assetRoot: widget.assetRoot,
            baseColor: const Color(0xFF241832), // deep violet night
          ),
        ),
        Positioned.fill(
          child: RepaintBoundary(
            child: CustomPaint(
              painter: _HalloweenFx(model: _model, orbs: _orbs, burst: _burst),
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
  double surge = 0; // reception brightness boost, decays
  void notify() => notifyListeners();
}

/// A floating orb. Ambient orbs ([life] == 0) loop forever; reception orbs rise
/// fast and cull once [life] elapses from [born].
class _Orb {
  _Orb({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.size,
    required this.phase,
    required this.life,
    required this.born,
  });
  double x;
  double y;
  final double vx;
  final double vy;
  final double size;
  final double phase;
  final double life;
  final double born;
}

class _HalloweenFx extends CustomPainter {
  _HalloweenFx({required this.model, required this.orbs, required this.burst})
    : super(repaint: model);

  final _SceneModel model;
  final List<_Orb> orbs;
  final List<_Orb> burst;

  static const _warm = Color(0xFFFFB347); // amber will-o'-wisp

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final now = model.time;

    _paintFog(canvas, w, h, now);

    for (final o in orbs) {
      _drawOrb(canvas, w, h, o, now, 1.0);
    }
    for (final o in burst) {
      final age = now - o.born;
      final a =
          (age / 0.4).clamp(0.0, 1.0) * ((o.life - age) / 1.0).clamp(0.0, 1.0);
      _drawOrb(canvas, w, h, o, now, a);
    }
  }

  // Three soft, slowly sliding fog banks low in the frame.
  void _paintFog(Canvas canvas, double w, double h, double now) {
    final fog = Paint()
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 40)
      ..color = const Color(0xFF6B5A86).withValues(alpha: 0.14);
    for (var i = 0; i < 3; i++) {
      final cx = (0.5 + 0.42 * math.sin(now * 0.06 + i * 2.1)) * w;
      final cy = (0.66 + i * 0.12) * h;
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(cx, cy),
          width: w * 1.1,
          height: h * 0.16,
        ),
        fog,
      );
    }
  }

  void _drawOrb(Canvas c, double w, double h, _Orb o, double now, double a) {
    if (a <= 0) return;
    final tw = 0.55 + 0.45 * (0.5 + 0.5 * math.sin(now * 2.2 + o.phase));
    final alpha = a * tw * (0.7 + 0.3 * model.surge);
    final pos = Offset(o.x * w, o.y * h);
    c.drawCircle(
      pos,
      o.size * 3.2,
      Paint()
        ..blendMode = BlendMode.plus
        ..color = _warm.withValues(alpha: 0.18 * alpha),
    );
    c.drawCircle(
      pos,
      o.size,
      Paint()
        ..blendMode = BlendMode.plus
        ..color = _warm.withValues(alpha: 0.9 * alpha),
    );
  }

  @override
  bool shouldRepaint(_HalloweenFx old) => false;
}
