import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:dewdrop/decor/decor_backdrop.dart';
import 'package:dewdrop/decor/forest_tree.dart';
import 'package:dewdrop/decor/reception_signal.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

/// Immersive "forêt" decor with three distinct scenes:
///  - variant 0 "Chênes": strolling through an oak wood — a dirt path receding
///    between procedurally-grown oaks, dappled light, falling leaves.
///  - variant 1 "Sakura": cherry trees lining a gentle winding stream, drifting
///    petals on the water.
///  - variant 2 "Canopée": looking out over a rainforest canopy — clumpy
///    treetops in depth, mist, gliding birds, floating spores.
///
/// The trees/scene are drawn into a static layer (repaints only on resize); the
/// leaves, light and water shimmer animate on top. A "pensée" (tap) sends a
/// gust. Rendered entirely on the Canvas.
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
  // (god-rays, falling leaves/petals, birds, water shimmer) sit on top of.
  final String assetRoot;

  @override
  State<ForestDecor> createState() => _ForestDecorState();
}

const double _horizon = 0.46;

const _oakStyle = TreeStyle(
  depth: 4,
  branches: 3,
  spread: 0.52,
  jitter: 0.38,
  lenDecay: 0.74,
  widthDecay: 0.64,
  initialLen: 0.30,
  initialWidth: 0.085,
  clusterScale: 1.15,
  clusterDepth: 1,
  trunkColor: Color(0xFF4A3526),
  foliage: [Color(0xFF33501F), Color(0xFF45642C), Color(0xFF294018)],
);

const _cherryStyle = TreeStyle(
  depth: 4,
  branches: 3,
  spread: 0.82,
  jitter: 0.42,
  lenDecay: 0.72,
  widthDecay: 0.60,
  initialLen: 0.27,
  initialWidth: 0.06,
  clusterScale: 0.7,
  clusterDepth: 2,
  trunkColor: Color(0xFF3A2A2E),
  foliage: [Color(0xFFF2B2CE), Color(0xFFFAC9DD), Color(0xFFE79BBC)],
);

class _ForestDecorState extends State<ForestDecor>
    with SingleTickerProviderStateMixin {
  final _model = _ForestModel();
  final math.Random _rng = math.Random(31);

  late final Ticker _ticker;
  late final List<TreeShape> _oaks = List.generate(
    4,
    (_) => buildTree(_rng, _oakStyle),
  );
  late final List<TreeShape> _cherries = List.generate(
    4,
    (_) => buildTree(_rng, _cherryStyle),
  );
  late final List<_Place> _places = _genPlaces();
  late final List<_Crown> _crowns = _genCrowns();
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
    for (var i = 0; i < 44; i++) {
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

  List<_Place> _genPlaces() {
    final places = <_Place>[];
    const perSide = 5;
    for (final side in [-1.0, 1.0]) {
      for (var k = 0; k < perSide; k++) {
        final t = (k + 0.18) / perSide;
        places.add(
          _Place(
            baseX: 0.5 + side * (0.05 + t * 0.62),
            baseY: _horizon + t * (1.08 - _horizon),
            heightFrac: 0.16 + t * t * 0.95,
            depth: t,
            flip: side < 0,
            shape: _rng.nextInt(4),
          ),
        );
      }
    }
    places.sort((a, b) => a.depth.compareTo(b.depth)); // far first
    return places;
  }

  List<_Crown> _genCrowns() => List.generate(48, (_) {
    final y = _rng.nextDouble();
    final bumps = List.generate(6 + _rng.nextInt(4), (_) {
      final ang = _rng.nextDouble() * math.pi * 2;
      final rad = 0.3 + _rng.nextDouble() * 0.5;
      final dy = -0.2 + math.sin(ang) * rad * 0.7;
      return _Bump(
        math.cos(ang) * rad,
        dy,
        0.25 + _rng.nextDouble() * 0.3,
        0.12 + (-dy).clamp(0.0, 1.0) * 0.3,
      );
    });
    return _Crown(
      x: _rng.nextDouble() * 1.1 - 0.05,
      y: y,
      r: 0.05 + y * 0.10 + _rng.nextDouble() * 0.04,
      shade: _rng.nextDouble(),
      bumps: bumps,
    );
  });

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
            // The old procedural scene now serves as the load-time fallback.
            fallback: RepaintBoundary(
              child: CustomPaint(
                painter: _ForestBgPainter(
                  variant: v,
                  shapes: v == 1 ? _cherries : _oaks,
                  style: v == 1 ? _cherryStyle : _oakStyle,
                  places: _places,
                  crowns: _crowns,
                ),
              ),
            ),
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

// Winding waterway (dirt path / stream) geometry, shared by both layers.
double _wayCenter(double yN) {
  final t = ((yN - _horizon) / (1 - _horizon)).clamp(0.0, 1.0);
  return 0.5 + math.sin(t * 2.4) * 0.05 * t;
}

double _wayHalf(double yN) {
  final t = ((yN - _horizon) / (1 - _horizon)).clamp(0.0, 1.0);
  return 0.012 + t * t * 0.17;
}

Path _wayPath(double w, double h) {
  final p = Path();
  const steps = 18;
  for (var i = 0; i <= steps; i++) {
    final yN = _horizon + (1 - _horizon) * i / steps;
    final x = (_wayCenter(yN) - _wayHalf(yN)) * w;
    final y = yN * h;
    i == 0 ? p.moveTo(x, y) : p.lineTo(x, y);
  }
  for (var i = steps; i >= 0; i--) {
    final yN = _horizon + (1 - _horizon) * i / steps;
    p.lineTo((_wayCenter(yN) + _wayHalf(yN)) * w, yN * h);
  }
  return p..close();
}

class _ForestModel extends ChangeNotifier {
  double time = 0;
  void notify() => notifyListeners();
}

class _Place {
  const _Place({
    required this.baseX,
    required this.baseY,
    required this.heightFrac,
    required this.depth,
    required this.flip,
    required this.shape,
  });
  final double baseX;
  final double baseY;
  final double heightFrac;
  final double depth;
  final bool flip;
  final int shape;
}

class _Bump {
  const _Bump(this.dx, this.dy, this.r, this.light);
  final double dx;
  final double dy;
  final double r;
  final double light;
}

class _Crown {
  const _Crown({
    required this.x,
    required this.y,
    required this.r,
    required this.shade,
    required this.bumps,
  });
  final double x;
  final double y;
  final double r;
  final double shade;
  final List<_Bump> bumps;
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

const _foliageGreens = [
  Color(0xFF2E5A2A),
  Color(0xFF3E6E34),
  Color(0xFF1E4420),
  Color(0xFF4E8040),
];

class _ForestBgPainter extends CustomPainter {
  const _ForestBgPainter({
    required this.variant,
    required this.shapes,
    required this.style,
    required this.places,
    required this.crowns,
  });

  final int variant;
  final List<TreeShape> shapes;
  final TreeStyle style;
  final List<_Place> places;
  final List<_Crown> crowns;

  @override
  void paint(Canvas canvas, Size size) {
    if (variant == 2) {
      _paintCanopy(canvas, size);
    } else {
      _paintGround(canvas, size);
    }
  }

  void _paintGround(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final isCherry = variant == 1;

    final skyTop = isCherry ? const Color(0xFF5A3A4E) : const Color(0xFF2A4520);
    final skyHorizon = isCherry
        ? const Color(0xFFF2E2C8)
        : const Color(0xFFCBD89A);
    final groundFar = isCherry
        ? const Color(0xFF2E2230)
        : const Color(0xFF2E3A1E);
    final groundNear = isCherry
        ? const Color(0xFF140F18)
        : const Color(0xFF141C0C);

    // Sky (the bright distance seen between the trees).
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(w / 2, 0),
          Offset(w / 2, _horizon * h),
          [skyTop, skyHorizon],
        ),
    );

    // Forest floor.
    canvas.drawRect(
      Rect.fromLTRB(0, _horizon * h, w, h),
      Paint()
        ..shader = ui.Gradient.linear(Offset(0, _horizon * h), Offset(0, h), [
          groundFar,
          groundNear,
        ]),
    );

    // The path (dirt) or stream (water base).
    final way = _wayPath(w, h);
    if (isCherry) {
      canvas.drawPath(
        way,
        Paint()
          ..shader = ui.Gradient.linear(
            Offset(0, _horizon * h),
            Offset(0, h),
            const [Color(0xFFD8C8A4), Color(0xFF5A5042)],
          ),
      );
    } else {
      canvas.drawPath(
        way,
        Paint()
          ..shader = ui.Gradient.linear(
            Offset(0, _horizon * h),
            Offset(0, h),
            const [Color(0xFF8A7250), Color(0xFF4A3A26)],
          ),
      );
    }

    _paintVanishingGlow(canvas, w, h, isCherry);

    // Trees, far (hazy) to near.
    for (final p in places) {
      final shape = shapes[p.shape % shapes.length];
      final haze = (1 - p.depth) * 0.7;
      drawTree(
        canvas,
        shape,
        base: Offset(p.baseX * w, p.baseY * h),
        height: p.heightFrac * h,
        flip: p.flip,
        sway: 0,
        style: style,
        haze: haze,
        hazeColor: skyHorizon,
      );
    }

    // Overhanging canopy framing the top.
    final ceil = style.foliage.last;
    for (var i = 0; i < 6; i++) {
      final cx = (i / 5) * w;
      canvas.drawCircle(
        Offset(cx, h * (-0.02 + (i.isEven ? 0.0 : 0.06))),
        h * 0.16,
        Paint()..color = ceil.withValues(alpha: 0.95),
      );
    }

    _paintForegroundFrame(canvas, w, h, isCherry);
  }

  void _paintVanishingGlow(Canvas canvas, double w, double h, bool isCherry) {
    final gx = _wayCenter(_horizon) * w;
    final gy = _horizon * h;
    final glow = isCherry ? const Color(0xFFF7E6CE) : const Color(0xFFFFF1C8);
    canvas.drawCircle(
      Offset(gx, gy),
      h * 0.26,
      Paint()
        ..blendMode = BlendMode.plus
        ..shader = ui.Gradient.radial(Offset(gx, gy), h * 0.26, [
          glow.withValues(alpha: 0.5),
          glow.withValues(alpha: 0),
        ]),
    );
  }

  // Two big mossy trunks framing the foreground (matches the oak photo).
  void _paintForegroundFrame(Canvas canvas, double w, double h, bool isCherry) {
    // Both oak and cherry photos have big mossy framing trunks.
    final bark = isCherry ? const Color(0xFF3A2E2A) : const Color(0xFF33251A);
    _bigTrunk(
      canvas,
      w,
      h,
      cxBottom: 0.13,
      cxTop: 0.05,
      wBottom: 0.17,
      wTop: 0.10,
      bark: bark,
      moss: true,
      mossToward: 1,
    );
    _bigTrunk(
      canvas,
      w,
      h,
      cxBottom: 0.9,
      cxTop: 0.99,
      wBottom: 0.21,
      wTop: 0.12,
      bark: bark,
      moss: true,
      mossToward: -1,
    );
    _ferns(canvas, w, h, 0.07);
    _ferns(canvas, w, h, 0.9);
  }

  void _bigTrunk(
    Canvas canvas,
    double w,
    double h, {
    required double cxBottom,
    required double cxTop,
    required double wBottom,
    required double wTop,
    required Color bark,
    required bool moss,
    required int mossToward,
  }) {
    final cb = cxBottom * w;
    final ct = cxTop * w;
    final hb = wBottom * w / 2;
    final ht = wTop * w / 2;
    final path = Path()
      ..moveTo(cb - hb, h)
      ..lineTo(ct - ht, -h * 0.02)
      ..lineTo(ct + ht, -h * 0.02)
      ..lineTo(cb + hb, h)
      ..close();
    canvas.drawPath(path, Paint()..color = bark);
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.22)
        ..style = PaintingStyle.stroke
        ..strokeWidth = hb * 0.5
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
    );
    if (moss) {
      for (var i = 0; i < 10; i++) {
        final t = 0.32 + i / 10 * 0.62;
        final cx =
            (cb + (ct - cb) * t) +
            mossToward * hb * 0.45 * (0.6 + 0.4 * math.sin(i * 1.7));
        final y = h * (1 - t);
        final r = hb * (0.32 + 0.26 * (0.5 + 0.5 * math.sin(i * 2.3)));
        canvas.drawCircle(
          Offset(cx, y),
          r,
          Paint()
            ..color = Color.lerp(
              const Color(0xFF4E6B2C),
              const Color(0xFF6E8C3E),
              (i % 3) / 2,
            )!.withValues(alpha: 0.8),
        );
      }
    }
  }

  void _ferns(Canvas canvas, double w, double h, double xN) {
    final base = Offset(xN * w, h * 0.92);
    final paint = Paint()
      ..color = const Color(0xFF3E5A24)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    for (var f = 0; f < 8; f++) {
      final ang = -math.pi / 2 + (-0.6 + f / 7 * 1.2);
      final len = h * (0.06 + 0.05 * (0.5 + 0.5 * math.sin(f * 1.3)));
      final tip = base + Offset(math.cos(ang), math.sin(ang)) * len;
      canvas.drawLine(base, tip, paint);
    }
  }

  void _paintCanopy(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(w / 2, 0),
          Offset(w / 2, h),
          const [Color(0xFFB9D49A), Color(0xFF123009)],
        ),
    );

    // Distant misty light near the top.
    canvas.drawRect(
      Rect.fromLTRB(0, 0, w, h * 0.5),
      Paint()
        ..shader = ui.Gradient.linear(Offset(0, 0), Offset(0, h * 0.5), const [
          Color(0x55EAF6C8),
          Color(0x00EAF6C8),
        ]),
    );

    final sorted = [...crowns]..sort((a, b) => a.y.compareTo(b.y)); // far first
    for (final c in sorted) {
      final center = Offset(c.x * w, c.y * h);
      final r = c.r * w;
      final haze = (1 - c.y).clamp(0.0, 1.0) * 0.55;
      final base = Color.lerp(
        _foliageGreens[(c.shade * 4).floor().clamp(0, 3)],
        const Color(0xFFB9D49A),
        haze,
      )!;
      // underside shadow
      canvas.drawCircle(
        center.translate(0, r * 0.2),
        r,
        Paint()..color = Color.lerp(base, Colors.black, 0.4)!,
      );
      // body
      canvas.drawCircle(center, r, Paint()..color = base);
      // lit bumps (treetop texture)
      for (final b in c.bumps) {
        canvas.drawCircle(
          center + Offset(b.dx, b.dy) * r,
          b.r * r,
          Paint()..color = Color.lerp(base, Colors.white, b.light)!,
        );
      }
    }

    _paintCanopyRays(canvas, w, h);
    _paintCanopyForeground(canvas, w, h);
  }

  // Dramatic god-rays fanning down through the canopy gap (the photo's light).
  void _paintCanopyRays(Canvas canvas, double w, double h) {
    const rayColor = Color(0xFFEAF8CC);
    final originX = w * 0.36;
    for (var i = 0; i < 6; i++) {
      final t = i / 5;
      final topX = originX + (t - 0.5) * w * 0.22;
      final botX = topX + w * (0.16 + t * 0.30);
      const halfTop = 0.012;
      const halfBot = 0.05;
      final path = Path()
        ..moveTo((topX) - halfTop * w, -h * 0.02)
        ..lineTo((topX) + halfTop * w, -h * 0.02)
        ..lineTo(botX + halfBot * w, h)
        ..lineTo(botX - halfBot * w, h)
        ..close();
      canvas.drawPath(
        path,
        Paint()
          ..blendMode = BlendMode.plus
          ..shader = ui.Gradient.linear(
            Offset(0, 0),
            Offset(0, h),
            [rayColor.withValues(alpha: 0.12), rayColor.withValues(alpha: 0)],
            const [0.0, 0.72],
          ),
      );
    }
  }

  // Out-of-focus tropical framing: dark leaves + red heliconia flowers, bottom.
  void _paintCanopyForeground(Canvas canvas, double w, double h) {
    canvas.drawRect(
      Rect.fromLTRB(0, h * 0.78, w, h),
      Paint()
        ..shader = ui.Gradient.linear(Offset(0, h * 0.78), Offset(0, h), const [
          Color(0x000A1A06),
          Color(0xD607140A),
        ]),
    );
    _canopyLeaf(
      canvas,
      Offset(w * 0.05, h * 0.99),
      w * 0.36,
      -0.45,
      const Color(0xFF14320E),
    );
    _canopyLeaf(
      canvas,
      Offset(w * 0.18, h * 1.03),
      w * 0.30,
      -1.15,
      const Color(0xFF1E4416),
    );
    _canopyLeaf(
      canvas,
      Offset(w * 0.97, h * 0.99),
      w * 0.38,
      math.pi + 0.5,
      const Color(0xFF112E0C),
    );
    _canopyLeaf(
      canvas,
      Offset(w * 0.83, h * 1.03),
      w * 0.30,
      math.pi - 1.2,
      const Color(0xFF1E4416),
    );
    _heliconia(canvas, Offset(w * 0.13, h * 1.0), h * 0.30, false);
    _heliconia(canvas, Offset(w * 0.25, h * 1.03), h * 0.23, true);
  }

  void _canopyLeaf(
    Canvas canvas,
    Offset base,
    double len,
    double angle,
    Color color,
  ) {
    canvas.save();
    canvas.translate(base.dx, base.dy);
    canvas.rotate(angle);
    final path = Path()
      ..moveTo(0, 0)
      ..quadraticBezierTo(len * 0.4, -len * 0.17, len, 0)
      ..quadraticBezierTo(len * 0.4, len * 0.17, 0, 0)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
    canvas.drawLine(
      Offset.zero,
      Offset(len, 0),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.20)
        ..strokeWidth = len * 0.012,
    );
    canvas.restore();
  }

  // Stylised heliconia ("lobster claw"): a stalk with alternating red→orange
  // bracts, like the flowers framing the photo's lower-left.
  void _heliconia(Canvas canvas, Offset base, double height, bool flip) {
    canvas.save();
    canvas.translate(base.dx, base.dy);
    if (flip) canvas.scale(-1, 1);
    canvas.drawLine(
      Offset.zero,
      Offset(0, -height),
      Paint()
        ..color = const Color(0xFF2E5020)
        ..style = PaintingStyle.stroke
        ..strokeWidth = height * 0.03
        ..strokeCap = StrokeCap.round,
    );
    const n = 5;
    for (var i = 0; i < n; i++) {
      final t = i / (n - 1);
      final y = -height * (0.12 + t * 0.78);
      final side = i.isEven ? 1.0 : -1.0;
      final len = height * (0.34 - t * 0.12);
      final col = Color.lerp(
        const Color(0xFFE23A22),
        const Color(0xFFF59021),
        t,
      )!;
      final p = Path()
        ..moveTo(0, y)
        ..lineTo(side * len, y - height * 0.045)
        ..lineTo(side * len * 0.8, y - height * 0.12)
        ..lineTo(0, y - height * 0.06)
        ..close();
      canvas.drawPath(p, Paint()..color = col);
      canvas.drawCircle(
        Offset(side * len, y - height * 0.045),
        height * 0.02,
        Paint()..color = const Color(0xFFE9E36A),
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ForestBgPainter old) => old.variant != variant;
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
