import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:dewdrop/decor/reception_signal.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

/// Immersive "aurores boréales" decor — the Arctic night: a deep starry sky
/// with undulating aurora curtains over a snowy horizon that softly reflects
/// the light. Two variants:
///  - 0 "Émeraude": green / teal aurora.
///  - 1 "Magenta": pink / violet aurora.
///
/// The sky gradient + snow horizon are a static layer; the stars (twinkle),
/// the aurora curtains (waving) and the tap "flash" animate on top. A "pensée"
/// (tap) makes the aurora surge brighter. Rendered entirely on the Canvas.
class AuroraDecor extends StatefulWidget {
  const AuroraDecor({
    super.key,
    this.variant = 0,
    this.reception,
    this.child,
  });

  final int variant;
  final ReceptionSignal? reception;
  final Widget? child;

  @override
  State<AuroraDecor> createState() => _AuroraDecorState();
}

class _AuroraDecorState extends State<AuroraDecor>
    with SingleTickerProviderStateMixin {
  final _model = _AuroraModel();
  final math.Random _rng = math.Random(7);

  late final Ticker _ticker;
  late final List<_Star> _stars = _genStars();
  late final List<_Curtain> _curtains = _genCurtains();

  // Ephemeral celebratory particles spawned by a reception burst (shimmering
  // ice crystals / star sparkles raining down across the snow). Empty at rest;
  // they self-cull once they fall past the bottom.
  final List<_Sparkle> _sparkles = [];

  double _lastTick = 0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
    widget.reception?.addListener(_onReception);
  }

  @override
  void didUpdateWidget(AuroraDecor old) {
    super.didUpdateWidget(old);
    if (old.reception != widget.reception) {
      old.reception?.removeListener(_onReception);
      widget.reception?.addListener(_onReception);
    }
  }

  void _onTick(Duration elapsed) {
    final now = elapsed.inMicroseconds / 1e6;
    final dt = (now - _lastTick).clamp(0.0, 0.05);
    _lastTick = now;
    _model.time = now;

    if (_sparkles.isNotEmpty) {
      final remove = <_Sparkle>[];
      for (final s in _sparkles) {
        s.y += s.fall * dt;
        s.x += s.drift * dt;
        s.rot += s.rotSpeed * dt;
        if (s.y > 1.06) remove.add(s);
      }
      if (remove.isNotEmpty) _sparkles.removeWhere(remove.contains);
    }

    _model.notify();
  }

  /// A pensée arrived: the whole aurora sweeps to full brightness (a longer,
  /// amplified swell distinct from the lighter tap flash) and a shower of
  /// shimmering ice crystals / star sparkles rains down across the sky. The
  /// sparkles are tinted by the active variant's palette so Émeraude rains
  /// green and Magenta rains pink.
  void _onReception() {
    _model.flash = _model.time; // ride the existing curtain surge too…
    _model.burst = _model.time; // …plus the bigger, longer reception swell.
    for (var i = 0; i < 60; i++) {
      _sparkles.add(
        _Sparkle(
          x: _rng.nextDouble(),
          y: -0.05 - _rng.nextDouble() * 0.7,
          size: 1.6 + _rng.nextDouble() * 3.2,
          fall: 0.18 + _rng.nextDouble() * 0.30,
          drift: (_rng.nextDouble() - 0.5) * 0.10,
          rot: _rng.nextDouble() * math.pi * 2,
          rotSpeed: (_rng.nextDouble() - 0.5) * 4,
          phase: _rng.nextDouble() * math.pi * 2,
          tint: _rng.nextDouble(),
        ),
      );
    }
    HapticFeedback.mediumImpact();
  }

  void _surge() {
    _model.flash = _model.time;
    HapticFeedback.lightImpact();
  }

  List<_Star> _genStars() => List.generate(140, (_) {
        final y = _rng.nextDouble();
        return _Star(
          x: _rng.nextDouble(),
          y: y * 0.72, // stars only in the sky, not the snow
          r: 0.4 + _rng.nextDouble() * 1.4,
          phase: _rng.nextDouble() * math.pi * 2,
          twinkle: 0.25 + _rng.nextDouble() * 0.7,
        );
      });

  List<_Curtain> _genCurtains() => List.generate(5, (i) {
        return _Curtain(
          cx: 0.12 + i * 0.19 + _rng.nextDouble() * 0.04,
          width: 0.16 + _rng.nextDouble() * 0.14,
          top: 0.01 + _rng.nextDouble() * 0.06,
          height: 0.40 + _rng.nextDouble() * 0.24,
          speed: 0.12 + _rng.nextDouble() * 0.18,
          phase: _rng.nextDouble() * math.pi * 2,
          waviness: 0.02 + _rng.nextDouble() * 0.035,
          bright: 0.55 + _rng.nextDouble() * 0.45,
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
    final v = widget.variant.clamp(0, 1);
    return Stack(
      children: [
        Positioned.fill(
          child: RepaintBoundary(
            child: CustomPaint(painter: _AuroraBgPainter(variant: v)),
          ),
        ),
        Positioned.fill(
          child: RepaintBoundary(
            child: CustomPaint(
              painter: _AuroraFxPainter(
                model: _model,
                variant: v,
                stars: _stars,
                curtains: _curtains,
                sparkles: _sparkles,
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _surge,
          ),
        ),
        if (widget.child != null) Positioned.fill(child: widget.child!),
      ],
    );
  }
}

// Aurora palettes (low/high colour pair per variant).
List<Color> _auroraColors(int variant) => variant == 0
    ? const [Color(0xFF38F5B0), Color(0xFF2A8CFF)] // emerald → teal-blue
    : const [Color(0xFFFF5FBF), Color(0xFF8A5BFF)]; // magenta → violet

const double _snowLine = 0.74;

class _AuroraModel extends ChangeNotifier {
  double time = 0;
  double flash = -10; // last lighter tap surge
  double burst = -10; // last amplified reception swell
  void notify() => notifyListeners();
}

class _Star {
  const _Star({
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

class _Curtain {
  const _Curtain({
    required this.cx,
    required this.width,
    required this.top,
    required this.height,
    required this.speed,
    required this.phase,
    required this.waviness,
    required this.bright,
  });
  final double cx;
  final double width;
  final double top;
  final double height;
  final double speed;
  final double phase;
  final double waviness;
  final double bright;
}

/// A falling shimmer crystal spawned by a reception burst. [tint] (0..1) blends
/// between the active variant's two aurora colours so the shower stays on
/// palette. Mutable: the ticker advances [y]/[x]/[rot].
class _Sparkle {
  _Sparkle({
    required this.x,
    required this.y,
    required this.size,
    required this.fall,
    required this.drift,
    required this.rot,
    required this.rotSpeed,
    required this.phase,
    required this.tint,
  });
  double x;
  double y;
  double rot;
  final double size;
  final double fall;
  final double drift;
  final double rotSpeed;
  final double phase;
  final double tint;
}

class _AuroraBgPainter extends CustomPainter {
  const _AuroraBgPainter({required this.variant});

  final int variant;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final glow = _auroraColors(variant).first;

    // Night sky.
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(w / 2, 0),
          Offset(w / 2, h),
          const [Color(0xFF050A1E), Color(0xFF0A1530), Color(0xFF0E2240)],
          const [0.0, 0.55, 1.0],
        ),
    );

    // Faint horizon glow where the aurora meets the snow.
    canvas.drawRect(
      Rect.fromLTRB(0, _snowLine * h - h * 0.22, w, _snowLine * h),
      Paint()
        ..blendMode = BlendMode.plus
        ..shader = ui.Gradient.linear(
          Offset(0, _snowLine * h - h * 0.22),
          Offset(0, _snowLine * h),
          [glow.withValues(alpha: 0), glow.withValues(alpha: 0.10)],
        ),
    );

    // Distant snowy ridges.
    _ridge(canvas, w, h, baseY: _snowLine, amp: 0.04, color: const Color(0xFF16263F));
    _ridge(canvas, w, h, baseY: _snowLine + 0.015, amp: 0.025, color: const Color(0xFF22324C));

    // Snowfield, softly lit by the aurora.
    canvas.drawRect(
      Rect.fromLTRB(0, _snowLine * h, w, h),
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, _snowLine * h),
          Offset(0, h),
          [
            Color.lerp(const Color(0xFFAEC4DC), glow, 0.25)!,
            const Color(0xFF2A3A52),
          ],
        ),
    );
  }

  void _ridge(Canvas canvas, double w, double h,
      {required double baseY, required double amp, required Color color}) {
    final path = Path()..moveTo(0, h);
    path.lineTo(0, baseY * h);
    const steps = 14;
    for (var i = 0; i <= steps; i++) {
      final xN = i / steps;
      final y = (baseY -
              amp * (0.5 + 0.5 * math.sin(xN * math.pi * 3 + 1.2)) *
                  (0.6 + 0.4 * math.sin(xN * 9))) *
          h;
      path.lineTo(xN * w, y);
    }
    path
      ..lineTo(w, h)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_AuroraBgPainter old) => old.variant != variant;
}

class _AuroraFxPainter extends CustomPainter {
  _AuroraFxPainter({
    required this.model,
    required this.variant,
    required this.stars,
    required this.curtains,
    required this.sparkles,
  }) : super(repaint: model);

  final _AuroraModel model;
  final int variant;
  final List<_Star> stars;
  final List<_Curtain> curtains;
  final List<_Sparkle> sparkles;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final time = model.time;
    final surge = (1 - (time - model.flash) / 1.6).clamp(0.0, 1.0);
    // The reception swell: bigger amplitude, longer decay than a tap surge, so
    // the whole sky visibly intensifies for the celebratory burst.
    final burst = (1 - (time - model.burst) / 2.8).clamp(0.0, 1.0);
    final cols = _auroraColors(variant);

    // Stars (behind the aurora) — brighten with the burst for a sparkling sky.
    final starBoost = 1 + burst * 0.9;
    for (final s in stars) {
      final a =
          s.twinkle * (0.55 + 0.45 * math.sin(time * 1.5 + s.phase)) * starBoost;
      canvas.drawCircle(
        Offset(s.x * w, s.y * h),
        s.r * (1 + burst * 0.4),
        Paint()..color = Color.fromRGBO(255, 255, 255, a.clamp(0.0, 1.0)),
      );
    }

    // Aurora curtains — the tap surge plus the amplified reception swell sweep
    // every curtain to its brightest.
    final drive = (surge * 0.5 + burst).clamp(0.0, 1.0);
    for (final c in curtains) {
      _paintCurtain(canvas, w, h, time, c, cols, drive);
    }

    // Reception shower: shimmering ice crystals / star sparkles, variant-tinted.
    if (sparkles.isNotEmpty) _paintSparkles(canvas, w, h, time, cols);

    // Depth vignette.
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(w / 2, h * 0.4),
          size.longestSide * 0.82,
          const [Color(0x00000000), Color(0x66050A1E)],
          const [0.45, 1.0],
        ),
    );
  }

  void _paintCurtain(Canvas canvas, double w, double h, double time,
      _Curtain c, List<Color> cols, double surge) {
    const steps = 16;
    double waveX(double yN) =>
        c.cx +
        math.sin(time * c.speed + c.phase + yN * 6.5) * c.waviness +
        math.sin(time * c.speed * 0.6 + yN * 13) * c.waviness * 0.4;

    final path = Path();
    for (var i = 0; i <= steps; i++) {
      final yN = c.top + c.height * i / steps;
      final x = (waveX(yN) - c.width / 2) * w;
      i == 0 ? path.moveTo(x, yN * h) : path.lineTo(x, yN * h);
    }
    for (var i = steps; i >= 0; i--) {
      final yN = c.top + c.height * i / steps;
      final x = (waveX(yN) + c.width / 2) * w;
      path.lineTo(x, yN * h);
    }
    path.close();

    final topY = c.top * h;
    final botY = (c.top + c.height) * h;
    final intensity = (c.bright * (0.7 + 0.3 * math.sin(time * 0.5 + c.phase)) +
            surge * 0.5)
        .clamp(0.0, 1.0);

    canvas.drawPath(
      path,
      Paint()
        ..blendMode = BlendMode.plus
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14)
        ..shader = ui.Gradient.linear(
          Offset(0, topY),
          Offset(0, botY),
          [
            cols[1].withValues(alpha: 0.05 * intensity),
            cols[0].withValues(alpha: 0.30 * intensity),
            cols[0].withValues(alpha: 0.0),
          ],
          const [0.0, 0.45, 1.0],
        ),
    );
  }

  // The reception shower: each particle is a soft glow halo plus a four-point
  // shimmer cross (an icy star crystal). Tinted between the variant's two
  // aurora colours toward a white-hot core, drawn additively to sit in the same
  // luminous register as the curtains.
  void _paintSparkles(
      Canvas canvas, double w, double h, double time, List<Color> cols) {
    for (final s in sparkles) {
      final px = s.x * w;
      final py = s.y * h;
      // Twinkle: the crystal pulses as it falls.
      final tw = 0.45 + 0.55 * (0.5 + 0.5 * math.sin(time * 6 + s.phase));
      // On-palette colour: blend the two variant hues, then push toward white
      // for the icy core.
      final hue = Color.lerp(cols[0], cols[1], s.tint)!;
      final core = Color.lerp(hue, Colors.white, 0.6)!;
      final r = s.size;

      // Soft halo.
      canvas.drawCircle(
        Offset(px, py),
        r * 2.2,
        Paint()
          ..blendMode = BlendMode.plus
          ..color = hue.withValues(alpha: 0.22 * tw),
      );

      // Four-point shimmer cross (rotating).
      canvas.save();
      canvas.translate(px, py);
      canvas.rotate(s.rot);
      final spike = Paint()
        ..blendMode = BlendMode.plus
        ..strokeCap = StrokeCap.round
        ..strokeWidth = r * 0.5
        ..color = core.withValues(alpha: 0.85 * tw);
      final arm = r * 2.6;
      canvas.drawLine(Offset(-arm, 0), Offset(arm, 0), spike);
      canvas.drawLine(Offset(0, -arm), Offset(0, arm), spike);
      canvas.restore();

      // Bright core dot.
      canvas.drawCircle(
        Offset(px, py),
        r * 0.55,
        Paint()
          ..blendMode = BlendMode.plus
          ..color = core.withValues(alpha: 0.95 * tw),
      );
    }
  }

  @override
  bool shouldRepaint(_AuroraFxPainter old) => old.variant != variant;
}
