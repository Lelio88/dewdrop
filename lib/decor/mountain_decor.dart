import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:dewdrop/decor/reception_signal.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

/// Immersive "montagne" decor — jagged alpine peaks. Two variants:
///  - 0 "Aube": snow peaks lit by pink dawn alpenglow over a sea of fog, a pine
///    forest band and a foreground flower meadow. Drifting fog + warm sun rays.
///  - 1 "Nuit": dark snowy peaks under a vivid Milky Way and twinkling stars,
///    with a snowy foreground ridge and pine silhouettes.
///
/// Sky, sun/galaxy, peak ranges and foreground are static; the drifting fog
/// (dawn) or twinkling stars (night) animate on top. A "pensée" (tap) releases
/// a single flurry of petals (dawn) or one shooting star (night) — a light
/// manual preview. When a real "pensée" arrives, the host pulses
/// [reception] and the decor plays an *amplified* celebratory burst: a whole
/// shower of staggered shooting stars (night) or a dense, multi-wave petal
/// cascade (dawn). Pure Canvas.
class MountainDecor extends StatefulWidget {
  const MountainDecor({
    super.key,
    this.variant = 0,
    this.reception,
    this.child,
  });

  final int variant;
  final ReceptionSignal? reception;
  final Widget? child;

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
      _model.prune(); // drop bursts that have fully faded
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
    _model.burst = _model.time;
    HapticFeedback.lightImpact();
  }

  /// A pensée arrived: an *amplified*, variant-flavoured shower. Where [_tap]
  /// fires one event, reception seeds a handful of staggered bursts so the
  /// painter renders a real wave — several shooting stars trailing across the
  /// sky (Nuit) or successive denser petal cascades (Aube). Each burst carries
  /// its own launch time and seed so they never overlap into a single blob.
  void _onReception() {
    const count = 6;
    for (var i = 0; i < count; i++) {
      _model.addShowerBurst(
        start: _model.time + i * 0.18, // staggered launches
        lane: (i + _model.bursts.length) % count,
        seed: _rng.nextInt(1 << 20),
      );
    }
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
          child: RepaintBoundary(
            child: CustomPaint(painter: _MountainBgPainter(cfg, _flowers)),
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

// One staggered event inside a reception shower. [start] is the launch time
// (model clock), [lane] spreads the shooting-star trajectories / petal columns
// across the width, and [seed] flavours its random scatter so each looks
// distinct. The painter derives its own progress from `time - start`.
class _ShowerBurst {
  const _ShowerBurst({
    required this.start,
    required this.lane,
    required this.seed,
  });
  final double start;
  final int lane;
  final int seed;
}

class _MountainModel extends ChangeNotifier {
  double time = 0;
  double burst = -10; // single-tap preview event
  final List<_ShowerBurst> bursts = []; // amplified reception shower

  // Longest visual lifetime of a single burst (the petal cascade), used to
  // know when a burst can be dropped. Shooting stars live ~1.2s, petals ~1.6s.
  static const double burstLifetime = 1.6;

  void addShowerBurst({
    required double start,
    required int lane,
    required int seed,
  }) {
    bursts.add(_ShowerBurst(start: start, lane: lane, seed: seed));
  }

  // Drop bursts whose animation has fully elapsed so the list stays bounded.
  void prune() {
    if (bursts.isEmpty) return;
    bursts.removeWhere((b) => time - b.start > burstLifetime);
  }

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
      for (final s in stars) {
        final a = s.twinkle * (0.55 + 0.45 * math.sin(time * 1.5 + s.phase));
        canvas.drawCircle(
          Offset(s.x * w, s.y * h),
          s.r,
          Paint()..color = Color.fromRGBO(255, 255, 255, a.clamp(0.0, 1.0)),
        );
      }
      // Single-tap preview: one shooting star on the centre lane.
      _paintShootingStar(canvas, w, h, start: model.burst, lane: 2, seed: 0);
      // Reception shower: a staggered volley of stars across all lanes.
      for (final b in model.bursts) {
        _paintShootingStar(
          canvas,
          w,
          h,
          start: b.start,
          lane: b.lane,
          seed: b.seed,
        );
      }
    } else {
      // Drifting sea-of-fog ribbons in the valley.
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
              alpha: 0.10 + 0.04 * math.sin(time * 0.5 + i),
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
      // Single-tap preview: one light petal flurry.
      _paintPetalFlurry(canvas, w, h, start: model.burst, seed: 8, count: 22);
      // Reception shower: each staggered burst is a denser petal cascade,
      // its column offset by the lane so the waves don't stack into one blob.
      for (final b in model.bursts) {
        _paintPetalFlurry(
          canvas,
          w,
          h,
          start: b.start,
          seed: b.seed,
          count: 40,
          lane: b.lane,
        );
      }
    }
  }

  // One shooting star streaking from upper-left to mid-right. [lane] shifts the
  // trajectory across the sky and tilts its descent so a volley fans out.
  void _paintShootingStar(
    Canvas canvas,
    double w,
    double h, {
    required double start,
    required int lane,
    required int seed,
  }) {
    final t = (model.time - start) / 1.2;
    if (t < 0 || t > 1) return;
    final rng = math.Random(seed);
    final laneN = lane / 6; // 0..~0.83 across the lanes
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

  // A flurry of falling petals fading over 1.6s. [count] controls density and
  // [lane] nudges the horizontal spread so successive shower waves don't align.
  void _paintPetalFlurry(
    Canvas canvas,
    double w,
    double h, {
    required double start,
    required int seed,
    required int count,
    int lane = 0,
  }) {
    final sp = (1 - (model.time - start) / 1.6).clamp(0.0, 1.0);
    if (sp <= 0) return;
    final rng = math.Random(seed);
    final laneShift = (lane / 6 - 0.4) * w * 0.25;
    for (var i = 0; i < count; i++) {
      final x = rng.nextDouble() * w + laneShift;
      final fall = (1 - sp) * h * 0.5;
      final y = rng.nextDouble() * h * 0.4 + fall;
      canvas.drawCircle(
        Offset(x + math.sin(model.time * 3 + i) * 6, y),
        1.5 + rng.nextDouble() * 2,
        Paint()..color = _flowerColor(rng).withValues(alpha: sp * 0.7),
      );
    }
  }

  @override
  bool shouldRepaint(_MountainFxPainter old) => false;
}
