import 'dart:math' as math;

import 'package:dewdrop/decor/decor_backdrop.dart';
import 'package:dewdrop/decor/reception_signal.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

/// Seasonal « 1er avril » decor — the world is playfully "under construction".
/// A realistic roadworks scene (photo/illustrated backdrop) with amber warning
/// **beacons** blinking out of phase over the barriers, cones and machinery,
/// exactly where the real lights sit in the photo (fixed composition → fixed
/// positions).
///
/// Reception (a pensée arrived) = a quick ripple where every beacon flashes in
/// sequence, brighter. Single variant (the marronnier locks the world).
class AprilDecor extends StatefulWidget {
  const AprilDecor({
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
  State<AprilDecor> createState() => _AprilDecorState();
}

class _AprilDecorState extends State<AprilDecor>
    with SingleTickerProviderStateMixin {
  final _model = _SceneModel();
  late final Ticker _ticker;

  // Beacon anchor points, in normalised (x, y), aligned with the warning lights
  // in the april/0 photo. Each blinks on its own period + phase.
  static const List<Offset> _spots = [
    Offset(0.085, 0.605),
    Offset(0.150, 0.615),
    Offset(0.140, 0.520),
    Offset(0.380, 0.790),
    Offset(0.700, 0.790),
    Offset(0.930, 0.720),
  ];

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
    widget.reception?.addListener(_onReception);
  }

  @override
  void didUpdateWidget(AprilDecor old) {
    super.didUpdateWidget(old);
    if (old.reception != widget.reception) {
      old.reception?.removeListener(_onReception);
      widget.reception?.addListener(_onReception);
    }
  }

  void _onTick(Duration elapsed) {
    final now = elapsed.inMicroseconds / 1e6;
    _model.time = now;
    _model.ripple = math.max(0, _model.ripple - 0.016 * 0.6);
    _model.notify();
  }

  void _onReception() {
    _model.ripple = 1.0; // a full sweep across all beacons
    HapticFeedback.mediumImpact();
  }

  void _tap() {
    _model.ripple = 0.7;
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
            env: 'april',
            variant: widget.variant,
            assetRoot: widget.assetRoot,
            baseColor: const Color(0xFF26364A), // dusk blue
          ),
        ),
        Positioned.fill(
          child: RepaintBoundary(
            child: CustomPaint(
              painter: _AprilFx(model: _model, spots: _spots),
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
  double ripple = 0; // reception sweep, decays
  void notify() => notifyListeners();
}

class _AprilFx extends CustomPainter {
  _AprilFx({required this.model, required this.spots}) : super(repaint: model);

  final _SceneModel model;
  final List<Offset> spots;

  static const _amber = Color(0xFFFFA31A);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final now = model.time;

    for (var i = 0; i < spots.length; i++) {
      // Idle blink: a punchy on/off (period ~1.1–1.5s, staggered by index).
      final speed = 4.2 + (i % 3) * 0.7;
      final s = 0.5 + 0.5 * math.sin(now * speed + i * 1.7);
      var lvl = math.pow(s, 8).toDouble();
      // Reception ripple: a bright wave passing beacon by beacon.
      if (model.ripple > 0) {
        final head = (1 - model.ripple) * spots.length;
        final d = (i - head).abs();
        lvl = math.max(lvl, model.ripple * math.exp(-d * d * 1.2));
      }
      if (lvl <= 0.02) continue;
      _drawBeacon(canvas, spots[i], w, h, lvl);
    }
  }

  void _drawBeacon(Canvas c, Offset spot, double w, double h, double lvl) {
    final pos = Offset(spot.dx * w, spot.dy * h);
    final r = math.min(w, h);
    c.drawCircle(
      pos,
      r * 0.10,
      Paint()
        ..blendMode = BlendMode.plus
        ..color = _amber.withValues(alpha: 0.28 * lvl),
    );
    c.drawCircle(
      pos,
      r * 0.028,
      Paint()
        ..blendMode = BlendMode.plus
        ..color = _amber.withValues(alpha: 0.95 * lvl),
    );
  }

  @override
  bool shouldRepaint(_AprilFx old) => false;
}
