import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:dewdrop/decor/decor_backdrop.dart';
import 'package:dewdrop/decor/reception_signal.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

/// Immersive "montagne" decor — jagged alpine peaks. Two variants:
///  - 0 "Aube": snow peaks lit by pink dawn alpenglow over a sea of fog, a pine
///    forest band and a foreground flower meadow. Gently drifting valley fog.
///  - 1 "Nuit": dark snowy peaks under a vivid Milky Way and twinkling stars,
///    with OCCASIONAL shooting stars passing behind the peak.
///
/// Sky, peak ranges and foreground are static; the drifting fog (dawn) or
/// twinkling + occasional shooting stars (night) animate on top. A tap or a
/// received "pensée" rolls soft white fog in from the left and right edges
/// toward the centre — like real fog — on BOTH variants. Pure Canvas.
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
  late final List<_Flower> _flowers = _genFlowers();

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

  List<_Flower> _genFlowers() => List.generate(90, (_) {
    final t = _rng.nextDouble();
    return _Flower(
      x: _rng.nextDouble(),
      y: 0.76 + t * 0.22,
      r: 1.5 + (1 - t) * 1.0 + _rng.nextDouble() * 1.5,
      color: _flowerColor(_rng),
      phase: _rng.nextDouble() * math.pi * 2,
    );
  });

  void _tap() {
    // Both variants: roll the soft fog in from the edges (manual preview).
    _model.fogBurst = _model.time;
    HapticFeedback.lightImpact();
  }

  /// A pensée arrived (both variants): soft white fog rolls in from the left and
  /// right edges, drifts toward the centre, then dissipates — like real fog. The
  /// occasional ambient shooting stars (Nuit) are unaffected.
  void _onReception() {
    _model.fogBurst = _model.time;
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
            fallback: RepaintBoundary(
              child: CustomPaint(painter: _MountainBgPainter(cfg, _flowers)),
            ),
          ),
        ),
        Positioned.fill(
          child: RepaintBoundary(
            child: CustomPaint(
              painter: _MountainFxPainter(
                model: _model,
                cfg: cfg,
                stars: _stars,
                flowers: _flowers,
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

Color _flowerColor(math.Random rng) {
  final r = rng.nextDouble();
  if (r < 0.30) return const Color(0xFFB57BD6); // purple
  if (r < 0.55) return const Color(0xFFF4F0F4); // white
  if (r < 0.78) return const Color(0xFFF2D24E); // yellow
  return const Color(0xFFE87AA8); // pink
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

class _Flower {
  const _Flower({
    required this.x,
    required this.y,
    required this.r,
    required this.color,
    required this.phase,
  });
  final double x;
  final double y;
  final double r;
  final Color color;
  final double phase;
}

// Triangle wave, period 1, ranging 0 → 1 → 0 with a sharp crest at 0.5.
double _tri(double x) {
  final f = x - x.floorToDouble();
  return 1 - (2 * (f - 0.5)).abs();
}

// Jagged mountain ridge across the width, peaks at vertical [baseY] (fraction
// of h) reaching up by [amp]. [freq] scales how many peaks (and how sharp).
// Layered triangle waves give pointed alpine crests rather than round humps.
Path _peakPath(
  double w,
  double h,
  double baseY,
  double amp,
  double shift,
  double freq,
) {
  final path = Path()..moveTo(0, h);
  path.lineTo(0, baseY * h);
  const steps = 96;
  for (var i = 0; i <= steps; i++) {
    final xN = i / steps;
    final jag =
        0.55 * _tri(xN * (3.0 * freq) + shift) +
        0.30 * _tri(xN * (6.0 * freq) + shift * 1.7) +
        0.15 * _tri(xN * (11.0 * freq) + shift * 0.6);
    final y = baseY - amp * jag;
    path.lineTo(xN * w, y * h);
  }
  path
    ..lineTo(w, h)
    ..close();
  return path;
}

class _MountainBgPainter extends CustomPainter {
  const _MountainBgPainter(this.cfg, this.flowers);
  final _MountainConfig cfg;
  final List<_Flower> flowers;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Sky.
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = ui.Gradient.linear(
          const Offset(0, 0),
          Offset(0, h * 0.7),
          [cfg.skyTop, cfg.skyMid, cfg.skyHorizon],
          const [0.0, 0.55, 1.0],
        ),
    );

    if (cfg.night) {
      _paintMilkyWay(canvas, size);
    } else {
      // Soft dawn sun glow behind the peaks.
      final sunPos = Offset(w * 0.5, h * 0.34);
      canvas.drawCircle(
        sunPos,
        h * 0.26,
        Paint()
          ..blendMode = BlendMode.plus
          ..shader = ui.Gradient.radial(sunPos, h * 0.26, const [
            Color(0x66FFE0C0),
            Color(0x00FFE0C0),
          ]),
      );
    }

    // Mountain ranges, far (hazy) to near.
    _paintRange(
      canvas,
      w,
      h,
      baseY: 0.46,
      amp: 0.20,
      shift: 0.5,
      sharp: 1.6,
      depth: 0.65,
    );
    _paintRange(
      canvas,
      w,
      h,
      baseY: 0.52,
      amp: 0.26,
      shift: 2.4,
      sharp: 1.3,
      depth: 0.30,
    );
    _paintRange(
      canvas,
      w,
      h,
      baseY: 0.58,
      amp: 0.22,
      shift: 4.1,
      sharp: 1.1,
      depth: 0.0,
    );

    if (!cfg.night) {
      // Sea of fog in the valley + a band of pine forest below the peaks.
      _paintPineBand(canvas, w, h, 0.64, const Color(0xFF2C4A30));
      _paintMeadow(canvas, w, h);
    } else {
      // Snowy foreground ridge + pine silhouettes.
      _paintSnowRidge(canvas, w, h);
      _paintPineBand(canvas, w, h, 0.70, const Color(0xFF0C1322));
    }

    // Depth vignette.
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(w / 2, h * 0.45),
          size.longestSide * 0.82,
          [
            const Color(0x00000000),
            cfg.night ? const Color(0x66060B20) : const Color(0x2E2A1E26),
          ],
          const [0.5, 1.0],
        ),
    );
  }

  void _paintRange(
    Canvas canvas,
    double w,
    double h, {
    required double baseY,
    required double amp,
    required double shift,
    required double sharp,
    required double depth,
  }) {
    final path = _peakPath(w, h, baseY, amp, shift, sharp);
    final rock = Color.lerp(cfg.rock, cfg.skyHorizon, depth * 0.55)!;
    canvas.drawPath(
      path,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, (baseY - amp) * h),
          Offset(0, h),
          [rock, Color.lerp(rock, Colors.black, 0.25)!],
        ),
    );
    // Snow cap: a top-down white gradient clipped to the peaks (alpenglow tint).
    canvas.save();
    canvas.clipPath(path);
    final snow = Color.lerp(cfg.snow, cfg.skyHorizon, depth * 0.4)!;
    canvas.drawRect(
      Rect.fromLTRB(0, (baseY - amp) * h, w, (baseY + amp * 0.3) * h),
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, (baseY - amp) * h),
          Offset(0, (baseY + amp * 0.4) * h),
          [snow.withValues(alpha: 0.95), snow.withValues(alpha: 0)],
        ),
    );
    canvas.restore();
  }

  void _paintPineBand(
    Canvas canvas,
    double w,
    double h,
    double yN,
    Color color,
  ) {
    final rng = math.Random(31);
    final y = yN * h;
    for (var i = 0; i < 60; i++) {
      final x = rng.nextDouble() * w;
      final ph = h * (0.03 + rng.nextDouble() * 0.05);
      final pw = ph * 0.5;
      final yy = y + (rng.nextDouble() - 0.5) * h * 0.04;
      final tri = Path()
        ..moveTo(x, yy - ph)
        ..lineTo(x - pw / 2, yy)
        ..lineTo(x + pw / 2, yy)
        ..close();
      canvas.drawPath(tri, Paint()..color = color);
    }
  }

  void _paintMeadow(Canvas canvas, double w, double h) {
    canvas.drawRect(
      Rect.fromLTRB(0, 0.72 * h, w, h),
      Paint()
        ..shader = ui.Gradient.linear(Offset(0, 0.72 * h), Offset(0, h), const [
          Color(0xFF4E7A3C),
          Color(0xFF2A4A24),
        ]),
    );
    // Flowers are drawn statically here; the fx layer adds a gentle sway.
    for (final f in flowers) {
      canvas.drawCircle(
        Offset(f.x * w, f.y * h),
        f.r,
        Paint()..color = f.color,
      );
    }
  }

  void _paintSnowRidge(Canvas canvas, double w, double h) {
    final path = Path()
      ..moveTo(0, h)
      ..lineTo(0, 0.82 * h);
    for (var i = 0; i <= 20; i++) {
      final xN = i / 20;
      final y =
          0.82 -
          0.06 * math.sin(xN * math.pi * 1.3 + 0.5) -
          0.02 * math.sin(xN * 7);
      path.lineTo(xN * w, y * h);
    }
    path
      ..lineTo(w, h)
      ..close();
    canvas.drawPath(
      path,
      Paint()
        ..shader = ui.Gradient.linear(Offset(0, 0.74 * h), Offset(0, h), const [
          Color(0xFFB8C8E4),
          Color(0xFF3A4866),
        ]),
    );
  }

  // Colourful galactic band arcing across the night sky.
  void _paintMilkyWay(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    canvas.save();
    canvas.translate(w * 0.5, h * 0.22);
    canvas.rotate(-0.35);
    final bandW = size.longestSide * 1.4;
    final bandH = h * 0.36;
    canvas.drawRect(
      Rect.fromCenter(center: Offset.zero, width: bandW, height: bandH),
      Paint()
        ..blendMode = BlendMode.plus
        ..shader = ui.Gradient.linear(
          Offset(0, -bandH / 2),
          Offset(0, bandH / 2),
          const [
            Color(0x00284070),
            Color(0x33425496),
            Color(0x4A9A6AB0),
            Color(0x33C08A6A),
            Color(0x00284070),
          ],
          const [0.0, 0.35, 0.5, 0.65, 1.0],
        ),
    );
    final rng = math.Random(13);
    for (var i = 0; i < 16; i++) {
      final x = (rng.nextDouble() - 0.5) * bandW * 0.82;
      final y = (rng.nextDouble() - 0.5) * bandH * 0.5;
      canvas.drawCircle(
        Offset(x, y),
        h * (0.02 + rng.nextDouble() * 0.05),
        Paint()
          ..blendMode = BlendMode.plus
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 20)
          ..color = const Color(
            0xFFC2CEF2,
          ).withValues(alpha: 0.05 + rng.nextDouble() * 0.05),
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_MountainBgPainter old) => old.cfg.night != cfg.night;
}

class _MountainFxPainter extends CustomPainter {
  _MountainFxPainter({
    required this.model,
    required this.cfg,
    required this.stars,
    required this.flowers,
  }) : super(repaint: model);

  final _MountainModel model;
  final _MountainConfig cfg;
  final List<_MStar> stars;
  final List<_Flower> flowers;

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

      // Gentle flower sway.
      for (final f in flowers) {
        final sway = math.sin(time * 1.5 + f.phase) * 1.2;
        canvas.drawCircle(
          Offset(f.x * w + sway, f.y * h),
          f.r,
          Paint()..color = f.color.withValues(alpha: 0.5),
        );
      }
    }

    // Soft fog rolling in from BOTH screen edges on tap / reception — both
    // variants. Real-fog feel: gentle rise and fall, banks drifting to centre.
    _paintEdgeFog(canvas, w, h, time - model.fogBurst);
  }

  /// Soft white fog that rolls in from BOTH edges, fills the WHOLE width as a
  /// homogeneous veil at its peak, then dissipates GLOBALLY (a uniform alpha
  /// fade everywhere at once — the banks never retreat to the edges, which would
  /// re-expose a visible front). Three-phase time envelope on [elapsed]:
  ///  (a) rise — banks slide in from the edges to centred / full coverage;
  ///  (b) plateau — wide, overlapping, blurred banks = seamless full-width veil;
  ///  (c) fall — opacity drops uniformly across the whole screen.
  void _paintEdgeFog(Canvas canvas, double w, double h, double elapsed) {
    if (elapsed < 0 || elapsed > _fogLife) return;
    final p = elapsed / _fogLife;
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
