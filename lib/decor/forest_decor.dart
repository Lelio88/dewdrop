import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:dewdrop/decor/decor_backdrop.dart';
import 'package:dewdrop/decor/reception_signal.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

/// Immersive "forêt" decor with three scenes (Chênes / Sakura / Canopée). The
/// scene itself is the parallax photo/illustrated backdrop; the falling
/// leaves/petals/spores and (on Canopée) the gliding birds animate on top. A
/// tap sends a gust of leaves; a received "pensée" cascades a curtain of them.
/// FX rendered in pure Canvas.
class ForestDecor extends StatefulWidget {
  const ForestDecor({
    super.key,
    this.variant = 0,
    this.reception,
    this.child,
    this.assetRoot = 'photo',
  });

  final int variant;
  final ReceptionSignal? reception;
  final Widget? child;
  // 'photo' or 'illustrated' — which parallax backdrop the bespoke forest FX
  // (falling leaves/petals, birds) sit on top of.
  final String assetRoot;

  @override
  State<ForestDecor> createState() => _ForestDecorState();
}

class _ForestDecorState extends State<ForestDecor>
    with SingleTickerProviderStateMixin {
  final _model = _ForestModel();
  final math.Random _rng = math.Random(31);

  late final Ticker _ticker;
  late final List<_Leaf> _leaves = _genLeaves();
  late final List<_Bird> _birds = _genBirds();

  double _lastTick = 0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
    widget.reception?.addListener(_onReception);
  }

  @override
  void didUpdateWidget(ForestDecor old) {
    super.didUpdateWidget(old);
    if (old.reception != widget.reception) {
      old.reception?.removeListener(_onReception);
      widget.reception?.addListener(_onReception);
    }
  }

  /// A pensée arrived: a curtain of leaves cascades in — many particles seeded
  /// across the width and staggered above the top so they fall in a wave. They
  /// are variant-flavoured for free (the fx painter colours every particle by
  /// variant: gold leaves / pink petals / pale spores).
  void _onReception() {
    // Intensity = how many pensées were caught up at once: a denser curtain
    // (more leaves) so the cascade reads as a bigger, longer celebration.
    final k = widget.reception?.intensity ?? 1.0;
    for (var i = 0; i < (44 * k).round(); i++) {
      _leaves.add(
        _Leaf(
          x: _rng.nextDouble(),
          y: -0.05 - _rng.nextDouble() * 0.9,
          size: 3 + _rng.nextDouble() * 5,
          fall: 0.06 + _rng.nextDouble() * 0.08,
          swayAmp: 0.02 + _rng.nextDouble() * 0.05,
          rot: _rng.nextDouble() * math.pi * 2,
          rotSpeed: (_rng.nextDouble() - 0.5) * 3,
          phase: _rng.nextDouble() * math.pi * 2,
          ephemeral: true,
        ),
      );
    }
    HapticFeedback.mediumImpact();
  }

  void _onTick(Duration elapsed) {
    final now = elapsed.inMicroseconds / 1e6;
    final dt = (now - _lastTick).clamp(0.0, 0.05);
    _lastTick = now;
    _model.time = now;

    final remove = <_Leaf>[];
    for (final l in _leaves) {
      l.y += l.fall * dt;
      l.rot += l.rotSpeed * dt;
      if (l.y > 1.06) {
        if (l.ephemeral) {
          remove.add(l);
        } else {
          l.y = -0.06;
          l.x = _rng.nextDouble();
        }
      }
    }
    if (remove.isNotEmpty) _leaves.removeWhere(remove.contains);

    for (final b in _birds) {
      b.x += b.dir * b.speed * dt;
      if (b.dir > 0 && b.x > 1.2) {
        b.x = -0.2;
        b.y = 0.08 + _rng.nextDouble() * 0.3;
      } else if (b.dir < 0 && b.x < -0.2) {
        b.x = 1.2;
        b.y = 0.08 + _rng.nextDouble() * 0.3;
      }
    }
    _model.notify();
  }

  void _emitGust() {
    for (var i = 0; i < 16; i++) {
      _leaves.add(
        _Leaf(
          x: _rng.nextDouble(),
          y: -0.05 - _rng.nextDouble() * 0.2,
          size: 3 + _rng.nextDouble() * 5,
          fall: 0.07 + _rng.nextDouble() * 0.07,
          swayAmp: 0.02 + _rng.nextDouble() * 0.04,
          rot: _rng.nextDouble() * math.pi * 2,
          rotSpeed: (_rng.nextDouble() - 0.5) * 3,
          phase: _rng.nextDouble() * math.pi * 2,
          ephemeral: true,
        ),
      );
    }
    HapticFeedback.lightImpact();
  }

  List<_Leaf> _genLeaves() => List.generate(30, (_) {
    return _Leaf(
      x: _rng.nextDouble(),
      y: _rng.nextDouble(),
      size: 3 + _rng.nextDouble() * 5,
      fall: 0.03 + _rng.nextDouble() * 0.05,
      swayAmp: 0.01 + _rng.nextDouble() * 0.03,
      rot: _rng.nextDouble() * math.pi * 2,
      rotSpeed: (_rng.nextDouble() - 0.5) * 2,
      phase: _rng.nextDouble() * math.pi * 2,
      ephemeral: false,
    );
  });

  List<_Bird> _genBirds() => List.generate(3, (_) {
    return _Bird(
      x: _rng.nextDouble(),
      y: 0.08 + _rng.nextDouble() * 0.3,
      dir: _rng.nextBool() ? 1.0 : -1.0,
      speed: 0.04 + _rng.nextDouble() * 0.03,
      size: 6 + _rng.nextDouble() * 5,
      phase: _rng.nextDouble() * math.pi * 2,
    );
  });

  // Dominant tone per scene — the flat colour shown for the one frame before
  // the photo decodes.
  Color get _baseColor => switch (widget.variant.clamp(0, 2)) {
    1 => const Color(0xFF2E2230), // Sakura — dusky pink-violet ground
    2 => const Color(0xFF123009), // Canopée — deep green
    _ => const Color(0xFF1A2A14), // Chênes — dark forest green
  };

  @override
  void dispose() {
    widget.reception?.removeListener(_onReception);
    _ticker.dispose();
    _model.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.variant.clamp(0, 2);
    return Stack(
      children: [
        Positioned.fill(
          child: DecorBackdrop(
            env: 'forest',
            variant: v,
            assetRoot: widget.assetRoot,
            baseColor: _baseColor,
            // Canopy birds glide BETWEEN the parallax layers (occluded by the
            // nearer foliage) for real depth, not pasted flat on top.
            midFx: v == 2
                ? RepaintBoundary(
                    child: CustomPaint(
                      painter: _ForestBirdsPainter(
                        model: _model,
                        birds: _birds,
                      ),
                    ),
                  )
                : null,
            midFxBelow: 1,
          ),
        ),
        Positioned.fill(
          child: RepaintBoundary(
            child: CustomPaint(
              painter: _ForestFxPainter(
                model: _model,
                variant: v,
                leaves: _leaves,
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _emitGust,
          ),
        ),
        if (widget.child != null) Positioned.fill(child: widget.child!),
      ],
    );
  }
}

class _ForestModel extends ChangeNotifier {
  double time = 0;
  void notify() => notifyListeners();
}

class _Leaf {
  _Leaf({
    required this.x,
    required this.y,
    required this.size,
    required this.fall,
    required this.swayAmp,
    required this.rot,
    required this.rotSpeed,
    required this.phase,
    required this.ephemeral,
  });
  double x;
  double y;
  double rot;
  final double size;
  final double fall;
  final double swayAmp;
  final double rotSpeed;
  final double phase;
  final bool ephemeral;
}

class _Bird {
  _Bird({
    required this.x,
    required this.y,
    required this.dir,
    required this.speed,
    required this.size,
    required this.phase,
  });
  double x;
  double y;
  final double dir;
  final double speed;
  final double size;
  final double phase;
}

class _ForestFxPainter extends CustomPainter {
  _ForestFxPainter({
    required this.model,
    required this.variant,
    required this.leaves,
  }) : super(repaint: model);

  final _ForestModel model;
  final int variant;
  final List<_Leaf> leaves;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final time = model.time;

    _paintParticles(canvas, w, h, time);

    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = ui.Gradient.radial(
          size.center(Offset.zero),
          size.longestSide * 0.78,
          const [Color(0x00000000), Color(0x66000000)],
          const [0.42, 1.0],
        ),
    );
  }

  void _paintParticles(Canvas canvas, double w, double h, double time) {
    final kind = variant == 2 ? 2 : variant; // 0 leaf, 1 petal, 2 spore
    final color = switch (variant) {
      0 => const Color(0xFFB8A24E),
      1 => const Color(0xFFFFC2DC),
      _ => const Color(0xFFE8F0C0),
    };
    for (final l in leaves) {
      final px = (l.x + math.sin(time * 0.7 + l.phase) * l.swayAmp) * w;
      final py = l.y * h;
      if (kind == 2) {
        canvas.drawCircle(
          Offset(px, py),
          l.size * 0.9,
          Paint()..color = color.withValues(alpha: 0.18),
        );
        canvas.drawCircle(
          Offset(px, py),
          l.size * 0.4,
          Paint()..color = color.withValues(alpha: 0.7),
        );
      } else {
        canvas.save();
        canvas.translate(px, py);
        canvas.rotate(l.rot);
        canvas.drawOval(
          Rect.fromCenter(
            center: Offset.zero,
            width: l.size * 1.7,
            height: l.size * (kind == 1 ? 0.7 : 0.9),
          ),
          Paint()..color = color.withValues(alpha: 0.88),
        );
        canvas.restore();
      }
    }
  }

  @override
  bool shouldRepaint(_ForestFxPainter old) => old.variant != variant;
}

/// Canopy birds — rendered as a mid-stack [DecorBackdrop.midFx] so the nearer
/// foliage layers occlude them (they glide BETWEEN the treetops for real depth).
class _ForestBirdsPainter extends CustomPainter {
  _ForestBirdsPainter({required this.model, required this.birds})
    : super(repaint: model);

  final _ForestModel model;
  final List<_Bird> birds;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final time = model.time;
    for (final bird in birds) {
      final flap = 0.6 + 0.4 * math.sin(time * 6 + bird.phase);
      final c = Offset(bird.x * w, bird.y * h);
      final s = bird.size;
      final path = Path()
        ..moveTo(c.dx - s, c.dy)
        ..quadraticBezierTo(c.dx - s * 0.4, c.dy - s * flap, c.dx, c.dy)
        ..quadraticBezierTo(c.dx + s * 0.4, c.dy - s * flap, c.dx + s, c.dy);
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round
          ..color = const Color(0xAA10220C),
      );
    }
  }

  @override
  bool shouldRepaint(_ForestBirdsPainter old) => false;
}
