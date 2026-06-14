import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

/// Palette + motion profile for a [ThemedDecor]. A lightweight, on-theme
/// starting point ("ébauche") for an environment before it gets a bespoke
/// renderer like space/underwater.
class ThemedPalette {
  const ThemedPalette({
    required this.top,
    required this.bottom,
    required this.mote,
    required this.accent,
    required this.moteCount,
    required this.drift,
  });

  final Color top;
  final Color bottom;
  final Color mote; // carries its own alpha
  final Color accent; // tap-ripple colour
  final int moteCount;
  final bool drift; // true = falling motes (dust/petals), false = static twinkle
}

/// Generic atmospheric decor: a themed gradient with drifting or twinkling
/// motes and a soft ripple when a "pensée" arrives. Placeholder until the
/// environment gets its own immersive renderer.
class ThemedDecor extends StatefulWidget {
  const ThemedDecor({super.key, required this.palette, this.child});

  final ThemedPalette palette;
  final Widget? child;

  @override
  State<ThemedDecor> createState() => _ThemedDecorState();
}

class _ThemedDecorState extends State<ThemedDecor>
    with SingleTickerProviderStateMixin {
  final _model = _ThemedModel();
  final math.Random _rng = math.Random(23);

  late final Ticker _ticker;
  late List<_Mote> _motes = _genMotes(widget.palette);

  double _lastTick = 0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void didUpdateWidget(ThemedDecor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.palette.moteCount != widget.palette.moteCount ||
        oldWidget.palette.drift != widget.palette.drift) {
      _motes = _genMotes(widget.palette);
    }
  }

  void _onTick(Duration elapsed) {
    final now = elapsed.inMicroseconds / 1e6;
    final dt = (now - _lastTick).clamp(0.0, 0.05);
    _lastTick = now;
    _model.time = now;

    if (widget.palette.drift) {
      for (final m in _motes) {
        m.y += m.speed * dt;
        m.x += math.sin(now * 0.5 + m.phase) * 0.0005;
        if (m.y > 1.05) {
          m.y = -0.05;
          m.x = _rng.nextDouble();
        }
      }
    }

    _model.ripples.removeWhere((r) => r.life(now) >= 1);
    _model.notify();
  }

  void _emitRipple() {
    _model.ripples.add(_Ripple(Offset(0.5, 0.5), _model.time));
    HapticFeedback.lightImpact();
  }

  List<_Mote> _genMotes(ThemedPalette p) => List.generate(p.moteCount, (_) {
        return _Mote(
          x: _rng.nextDouble(),
          y: _rng.nextDouble(),
          size: 0.6 + _rng.nextDouble() * 1.8,
          speed: 0.02 + _rng.nextDouble() * 0.05,
          phase: _rng.nextDouble() * math.pi * 2,
          twinkleSpeed: 0.4 + _rng.nextDouble() * 1.2,
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
    return LayoutBuilder(
      builder: (context, constraints) {
        return Stack(
          children: [
            Positioned.fill(
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: _ThemedPainter(
                    model: _model,
                    motes: _motes,
                    palette: widget.palette,
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _emitRipple,
              ),
            ),
            if (widget.child != null) Positioned.fill(child: widget.child!),
          ],
        );
      },
    );
  }
}

class _ThemedModel extends ChangeNotifier {
  double time = 0;
  final List<_Ripple> ripples = [];
  void notify() => notifyListeners();
}

class _Mote {
  _Mote({
    required this.x,
    required this.y,
    required this.size,
    required this.speed,
    required this.phase,
    required this.twinkleSpeed,
  });
  double x;
  double y;
  final double size;
  final double speed;
  final double phase;
  final double twinkleSpeed;
}

class _Ripple {
  _Ripple(this.center, this.startTime);
  final Offset center;
  final double startTime;
  static const double duration = 1.6;
  double life(double now) => ((now - startTime) / duration).clamp(0.0, 1.0);
}

class _ThemedPainter extends CustomPainter {
  _ThemedPainter({
    required this.model,
    required this.motes,
    required this.palette,
  }) : super(repaint: model);

  final _ThemedModel model;
  final List<_Mote> motes;
  final ThemedPalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final rect = Offset.zero & size;
    final time = model.time;

    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(w / 2, 0),
          Offset(w / 2, h),
          [palette.top, palette.bottom],
        ),
    );

    for (final m in motes) {
      final twinkle = palette.drift
          ? 1.0
          : 0.55 + 0.45 * math.sin(time * m.twinkleSpeed + m.phase);
      final baseA = (palette.mote.a) * twinkle;
      final color = palette.mote.withValues(alpha: baseA.clamp(0.0, 1.0));
      canvas.drawCircle(Offset(m.x * w, m.y * h), m.size, Paint()..color = color);
    }

    for (final r in model.ripples) {
      final t = r.life(time);
      final radius = (0.05 + t * 0.45) * size.shortestSide;
      final alpha = (1 - t) * 0.4;
      final center = Offset(r.center.dx * w, r.center.dy * h);
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = palette.accent.withValues(alpha: alpha),
      );
    }

    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.radial(
          size.center(Offset.zero),
          size.longestSide * 0.78,
          const [Color(0x00000000), Color(0x59000000)],
          const [0.45, 1.0],
        ),
    );
  }

  @override
  bool shouldRepaint(_ThemedPainter old) =>
      old.palette.top != palette.top ||
      old.palette.bottom != palette.bottom ||
      old.palette.mote != palette.mote;
}
