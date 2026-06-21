import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:dewdrop/decor/decor_backdrop.dart';
import 'package:dewdrop/decor/reception_signal.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

/// Immersive "montagne" decor — jagged alpine peaks. Two variants (Aube / Nuit)
/// supplied by the parallax photo/illustrated backdrop. On Aube the valley fog
/// drifts over the peaks; on Nuit the stars twinkle and OCCASIONAL shooting
/// stars pass behind the peak. A tap or a received pensée rolls soft white fog
/// in from both edges toward the centre. FX in pure Canvas.
class MountainDecor extends StatefulWidget {
  const MountainDecor({
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
  State<MountainDecor> createState() => _MountainDecorState();
}

class _MountainDecorState extends State<MountainDecor>
    with SingleTickerProviderStateMixin {
  final _model = _MountainModel();
  final math.Random _rng = math.Random(23);
  late final Ticker _ticker;
  late final List<_MStar> _stars = _genStars();

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((e) {
      _model.time = e.inMicroseconds / 1e6;
      _model.notify();
    })..start();
    widget.reception?.addListener(_onReception);
  }

  @override
  void didUpdateWidget(MountainDecor old) {
    super.didUpdateWidget(old);
    if (old.reception != widget.reception) {
      old.reception?.removeListener(_onReception);
      widget.reception?.addListener(_onReception);
    }
  }

  List<_MStar> _genStars() => List.generate(150, (_) {
    return _MStar(
      x: _rng.nextDouble(),
      y: _rng.nextDouble() * 0.5,
      r: 0.4 + _rng.nextDouble() * 1.5,
      phase: _rng.nextDouble() * math.pi * 2,
      twinkle: 0.3 + _rng.nextDouble() * 0.7,
    );
  });

  void _tap() {
    // Both variants: roll the soft fog in from the edges (manual preview).
    _model.fogBurst = _model.time;
    _model.fogK = 1.0; // a tap is always a single-strength billow
    HapticFeedback.lightImpact();
  }

  /// A pensée arrived (both variants): soft white fog rolls in from the left and
  /// right edges, drifts toward the centre, then dissipates — like real fog. The
  /// occasional ambient shooting stars (Nuit) are unaffected.
  void _onReception() {
    // Intensity (how many pensées were caught up at once) makes the fog roll in
    // for longer — a bigger, more sustained billow.
    _model.fogBurst = _model.time;
    _model.fogK = widget.reception?.intensity ?? 1.0;
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
    final cfg = widget.variant == 0 ? _dawn : _night;
    return Stack(
      children: [
        Positioned.fill(
          child: DecorBackdrop(
            env: 'mountain',
            variant: widget.variant,
            assetRoot: widget.assetRoot,
            baseColor: cfg.skyTop,
            // Night: shooting stars stream from the deepest mid-stack slot so
            // they vanish BEHIND the peak. Several ambient meteors at once.
            midFx: cfg.night
                ? RepaintBoundary(
                    child: CustomPaint(
                      painter: _MountainShootingStarsPainter(model: _model),
                    ),
                  )
                : null,
            midFxBelow: 1,
          ),
        ),
        Positioned.fill(
          child: RepaintBoundary(
            child: CustomPaint(
              painter: _MountainFxPainter(
                model: _model,
                cfg: cfg,
                stars: _stars,
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

class _MountainConfig {
  const _MountainConfig({
    required this.night,
    required this.skyTop,
    required this.skyMid,
    required this.skyHorizon,
    required this.snow,
    required this.rock,
  });

  final bool night;
  final Color skyTop;
  final Color skyMid;
  final Color skyHorizon;
  final Color snow; // lit snow (alpenglow tints this)
  final Color rock;
}

const _dawn = _MountainConfig(
  night: false,
  skyTop: Color(0xFF7FA6D0),
  skyMid: Color(0xFFE7A6B0),
  skyHorizon: Color(0xFFFAD6B0),
  snow: Color(0xFFFBD9DE),
  rock: Color(0xFF6E6A82),
);

const _night = _MountainConfig(
  night: true,
  skyTop: Color(0xFF060B20),
  skyMid: Color(0xFF0C1430),
  skyHorizon: Color(0xFF16203E),
  snow: Color(0xFFCBD8EE),
  rock: Color(0xFF222A40),
);

// How long the soft edge-fog takes to roll in and dissipate (seconds). Longer
// so the fog ARRIVES slowly (the rise/reach phases stretch over most of it).
const double _fogLife = 4.5;

class _MountainModel extends ChangeNotifier {
  double time = 0;
  double fogBurst = -10; // fog-billow trigger (tap or reception), both variants
  double fogK = 1.0; // intensity of that billow (1 = one pensée / a tap)

  void notify() => notifyListeners();
}

class _MStar {
  const _MStar({
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

class _MountainFxPainter extends CustomPainter {
  _MountainFxPainter({
    required this.model,
    required this.cfg,
    required this.stars,
  }) : super(repaint: model);

  final _MountainModel model;
  final _MountainConfig cfg;
  final List<_MStar> stars;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final time = model.time;

    if (cfg.night) {
      // Twinkling stars only — the shooting stars live in the mid-stack painter
      // so they pass behind the peak (see _MountainShootingStarsPainter).
      for (final s in stars) {
        final a = s.twinkle * (0.55 + 0.45 * math.sin(time * 1.5 + s.phase));
        canvas.drawCircle(
          Offset(s.x * w, s.y * h),
          s.r,
          Paint()..color = Color.fromRGBO(255, 255, 255, a.clamp(0.0, 1.0)),
        );
      }
    } else {
      // Aube ambient (unchanged): the gently drifting sea-of-fog ribbons that
      // hang in the valley below the peaks.
      for (var i = 0; i < 5; i++) {
        final baseY = (0.58 + i * 0.028) * h;
        final drift = (time * (0.01 + i * 0.004) + i * 0.3) % 1.2 - 0.1;
        final cx = drift * w;
        canvas.drawOval(
          Rect.fromCenter(
            center: Offset(cx, baseY),
            width: w * 0.7,
            height: h * 0.05,
          ),
          Paint()
            ..color = Colors.white.withValues(
              alpha: (0.10 + 0.04 * math.sin(time * 0.5 + i)).clamp(0.0, 1.0),
            )
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 22),
        );
      }
    }

    // Soft fog rolling in from BOTH screen edges on tap / reception — both
    // variants. Real-fog feel: gentle rise and fall, banks drifting to centre.
    _paintEdgeFog(canvas, w, h, time - model.fogBurst, model.fogK);
  }

  /// Soft white fog that rolls in from BOTH edges, fills the WHOLE width as a
  /// homogeneous veil at its peak, then dissipates GLOBALLY (a uniform alpha
  /// fade everywhere at once — the banks never retreat to the edges, which would
  /// re-expose a visible front). Three-phase time envelope on [elapsed]:
  ///  (a) rise — banks slide in from the edges to centred / full coverage;
  ///  (b) plateau — wide, overlapping, blurred banks = seamless full-width veil;
  ///  (c) fall — opacity drops uniformly across the whole screen.
  void _paintEdgeFog(
    Canvas canvas,
    double w,
    double h,
    double elapsed,
    double fogK,
  ) {
    // A bigger catch-up (fogK > 1) stretches how long the billow lasts, so a
    // "many pensées" reception reads as a more sustained roll of fog.
    final life = _fogLife * (1 + (fogK - 1) * 0.5);
    if (elapsed < 0 || elapsed > life) return;
    final p = elapsed / life;
    // Global opacity envelope: a SLOW rise (long arrival), a plateau, then a
    // slightly quicker uniform fade-out.
    final double env;
    if (p < 0.40) {
      env = Curves.easeIn.transform(p / 0.40);
    } else if (p < 0.74) {
      env = 1.0;
    } else {
      env = 1.0 - Curves.easeInOut.transform((p - 0.74) / 0.26);
    }
    // How far the banks have rolled in. Rolls in SLOWLY over the long rise and
    // STAYS at full coverage through the fade, so dissipation is a global alpha
    // drop, never a retreat that re-shows a bank's front.
    final reach = Curves.easeOut.transform((p / 0.45).clamp(0.0, 1.0));
    for (var i = 0; i < 4; i++) {
      final fy = (0.48 + i * 0.08) * h;
      final bh = h * (0.20 + i * 0.04);
      // Banks are very wide (and the back layers wider than the screen) so when
      // centred they overlap into a seamless full-width veil with no visible
      // front and the screen edges fully covered.
      final bw = w * (0.95 + i * 0.12);
      final a = (env * (0.14 + 0.04 * math.sin(elapsed * 0.5 + i))).clamp(
        0.0,
        0.26,
      );
      // Left bank slides from off-screen-left to centre; right bank symmetric.
      final lcx = ui.lerpDouble(-0.55, 0.5, reach)! * w;
      final rcx = ui.lerpDouble(1.55, 0.5, reach)! * w;
      final fogPaint = Paint()
        ..color = Colors.white.withValues(alpha: a)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 44);
      canvas.drawOval(
        Rect.fromCenter(center: Offset(lcx, fy), width: bw, height: bh),
        fogPaint,
      );
      canvas.drawOval(
        Rect.fromCenter(center: Offset(rcx, fy), width: bw, height: bh),
        fogPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_MountainFxPainter old) => false;
}

/// Night shooting stars, rendered as a mid-stack [DecorBackdrop.midFx] so they
/// stream BEHIND the peak. OCCASIONAL ambient meteors only — one now and then,
/// never on tap/reception (those roll the fog in instead).
class _MountainShootingStarsPainter extends CustomPainter {
  _MountainShootingStarsPainter({required this.model}) : super(repaint: model);
  final _MountainModel model;

  // Occasional ambient meteors: 2 tracks on a 12s cycle → ~one every ~6s, never
  // two at once. "De temps en temps", not a stream.
  static const int _ambientTracks = 2;
  static const double _period = 12.0;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final time = model.time;
    for (var k = 0; k < _ambientTracks; k++) {
      final local = (time - k * (_period / _ambientTracks)) % _period;
      _star(canvas, w, h, t: local / 1.2, lane: (k * 3) % 6, seed: 1000 + k);
    }
  }

  // One shooting star streaking from upper-left to mid-right. [lane] shifts the
  // trajectory across the sky and tilts its descent so a volley fans out.
  void _star(
    Canvas canvas,
    double w,
    double h, {
    required double t,
    required int lane,
    required int seed,
  }) {
    if (t < 0 || t > 1) return;
    final rng = math.Random(seed);
    final laneN = lane / 6;
    final jitter = (rng.nextDouble() - 0.5) * 0.12;
    final eased = Curves.easeOut.transform(t);
    final fromX = 0.12 + laneN * 0.5 + jitter;
    final from = Offset(w * fromX, h * (0.04 + laneN * 0.10));
    final to = Offset(w * (fromX + 0.34), h * (0.30 + laneN * 0.16));
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
  bool shouldRepaint(_MountainShootingStarsPainter old) => false;
}
