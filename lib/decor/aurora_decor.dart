import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:dewdrop/decor/decor_backdrop.dart';
import 'package:dewdrop/decor/reception_signal.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

/// Immersive "aurores boréales" decor — the Arctic night. Two variants
/// (Émeraude / Magenta) supplied by the parallax photo/illustrated backdrop.
/// The stars twinkle, the aurora curtains wave and white snowflakes drift on
/// top. A tap makes the aurora surge brighter; a received pensée sweeps it to
/// full brightness and rains shimmering ice crystals. FX in pure Canvas.
class AuroraDecor extends StatefulWidget {
  const AuroraDecor({
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
  State<AuroraDecor> createState() => _AuroraDecorState();
}

class _AuroraDecorState extends State<AuroraDecor>
    with SingleTickerProviderStateMixin {
  final _model = _AuroraModel();
  final math.Random _rng = math.Random(7);

  late final Ticker _ticker;
  late final List<_Star> _stars = _genStars();
  late final List<_Curtain> _curtains = _genCurtains();

  // Always-on ambient particle layer, calm and sparse: real WHITE snowflakes
  // (six-branched ice crystals) drifting slowly DOWNWARD on BOTH variants.
  // Generated once; the ticker advances them and wraps them around the screen
  // so the layer runs forever at constant density (distinct from the ephemeral
  // reception sparkles below, which self-cull).
  late final List<_Ambient> _ambient = _genAmbient();

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

    _advanceAmbient(dt);

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

  /// Advances the always-on ambient snowflake layer: each flake drifts DOWN with
  /// a gentle sinusoidal sway, wrapping around the opposite edge so the layer
  /// keeps a constant, calm density forever.
  void _advanceAmbient(double dt) {
    final double time = _model.time;
    for (final p in _ambient) {
      p.y += p.speed * dt;
      // Lateral sway, each particle on its own phase/frequency.
      p.x += math.sin(time * p.swayFreq + p.swayPhase) * p.swayAmp * dt;

      // Wrap vertically; re-randomise x so the recycled particle reads as new.
      if (p.y > 1.04) {
        p.y = -0.04;
        p.x = _rng.nextDouble();
      }
      // Wrap horizontally to keep the sway from pushing particles off-screen.
      if (p.x < -0.04) p.x = 1.04;
      if (p.x > 1.04) p.x = -0.04;
    }
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

  // ~38 ambient particles — sparse and calm.
  List<_Ambient> _genAmbient() => List.generate(38, (_) {
    return _Ambient(
      x: _rng.nextDouble(),
      y: _rng.nextDouble(),
      size: 0.8 + _rng.nextDouble() * 1.8,
      speed: 0.012 + _rng.nextDouble() * 0.028, // fraction of height / sec
      swayAmp: 0.006 + _rng.nextDouble() * 0.018,
      swayFreq: 0.4 + _rng.nextDouble() * 0.9,
      swayPhase: _rng.nextDouble() * math.pi * 2,
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
          child: DecorBackdrop(
            env: 'aurora',
            variant: v,
            assetRoot: widget.assetRoot,
            baseColor: const Color(0xFF050A1E), // deep Arctic night sky
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
                ambient: _ambient,
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

/// An always-on ambient snowflake. Mutable: the ticker advances [x]/[y].
/// [speed] is a fraction of the canvas height per second.
class _Ambient {
  _Ambient({
    required this.x,
    required this.y,
    required this.size,
    required this.speed,
    required this.swayAmp,
    required this.swayFreq,
    required this.swayPhase,
  });
  double x;
  double y;
  final double size;
  final double speed;
  final double swayAmp;
  final double swayFreq;
  final double swayPhase;
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

class _AuroraFxPainter extends CustomPainter {
  _AuroraFxPainter({
    required this.model,
    required this.variant,
    required this.stars,
    required this.curtains,
    required this.ambient,
    required this.sparkles,
  }) : super(repaint: model);

  final _AuroraModel model;
  final int variant;
  final List<_Star> stars;
  final List<_Curtain> curtains;
  final List<_Ambient> ambient;
  final List<_Sparkle> sparkles;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final time = model.time;
    // Tap/reception surge: instead of a single fade it now BLINKS ~4× and a
    // touch brighter (per design — « ça clignote 3-5 fois, plus fort »).
    final flashAge = time - model.flash;
    final flashFade = (1 - flashAge / 2.0).clamp(0.0, 1.0);
    final surge =
        (flashFade * (0.55 + 0.45 * math.cos(flashAge * 2 * math.pi * 4)))
            .clamp(0.0, 1.0);
    // The reception swell: bigger amplitude, longer decay than a tap surge, so
    // the whole sky visibly intensifies for the celebratory burst.
    final burst = (1 - (time - model.burst) / 2.8).clamp(0.0, 1.0);
    final cols = _auroraColors(variant);

    // Stars (behind the aurora) — brighten with the burst for a sparkling sky.
    final starBoost = 1 + burst * 0.9;
    for (final s in stars) {
      final a =
          s.twinkle *
          (0.55 + 0.45 * math.sin(time * 1.5 + s.phase)) *
          starBoost;
      canvas.drawCircle(
        Offset(s.x * w, s.y * h),
        s.r * (1 + burst * 0.4),
        Paint()..color = Color.fromRGBO(255, 255, 255, a.clamp(0.0, 1.0)),
      );
    }

    // Aurora curtains — the tap surge plus the amplified reception swell sweep
    // every curtain to its brightest.
    final drive = (surge * 0.85 + burst).clamp(0.0, 1.0);
    for (final c in curtains) {
      _paintCurtain(canvas, w, h, time, c, cols, drive);
    }

    // Always-on ambient texture: white snowflakes.
    _paintAmbient(canvas, w, h, time, cols);

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

  void _paintCurtain(
    Canvas canvas,
    double w,
    double h,
    double time,
    _Curtain c,
    List<Color> cols,
    double surge,
  ) {
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
    final intensity =
        (c.bright * (0.7 + 0.3 * math.sin(time * 0.5 + c.phase)) + surge * 0.5)
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

  // Always-on ambient layer: real WHITE snowflakes — six-branched ice crystals
  // (not circles) — on BOTH variants. Each is drawn as 6 barbed arms radiating
  // from the centre, slowly rotating, with a faint soft halo so it doesn't look
  // harsh. Kept small and low-alpha so it stays a calm texture that never
  // competes with the curtains or the reception burst.
  void _paintAmbient(
    Canvas canvas,
    double w,
    double h,
    double time,
    List<Color> cols,
  ) {
    for (final p in ambient) {
      final px = p.x * w;
      final py = p.y * h;
      // Fade flakes gently as they approach the very bottom so they melt into
      // the snowfield instead of popping out at the wrap line.
      final fade = p.y > _snowLine
          ? (1 - (p.y - _snowLine) / (1 - _snowLine))
          : 1.0;
      final a = (0.6 * fade).clamp(0.0, 1.0);
      final arm = p.size * 1.75; // crystal radius (kept small/delicate)

      // Faint soft halo (white) so the crystal sits softly on the sky.
      canvas.drawCircle(
        Offset(px, py),
        arm * 0.9,
        Paint()..color = Colors.white.withValues(alpha: 0.07 * fade),
      );

      // Six barbed arms — a proper snowflake, slowly turning.
      canvas.save();
      canvas.translate(px, py);
      canvas.rotate(p.swayPhase + time * 0.15);
      final stroke = Paint()
        ..color = Colors.white.withValues(alpha: a)
        ..strokeCap = StrokeCap.round
        ..strokeWidth = (p.size * 0.32).clamp(0.6, 1.3);
      for (var k = 0; k < 6; k++) {
        canvas.drawLine(Offset.zero, Offset(arm, 0), stroke);
        canvas.drawLine(
          Offset(arm * 0.6, 0),
          Offset(arm * 0.8, arm * 0.18),
          stroke,
        );
        canvas.drawLine(
          Offset(arm * 0.6, 0),
          Offset(arm * 0.8, -arm * 0.18),
          stroke,
        );
        canvas.rotate(math.pi / 3);
      }
      canvas.restore();
    }
  }

  // The reception shower: each particle is a soft glow halo plus a four-point
  // shimmer cross (an icy star crystal). Tinted between the variant's two
  // aurora colours toward a white-hot core, drawn additively to sit in the same
  // luminous register as the curtains.
  void _paintSparkles(
    Canvas canvas,
    double w,
    double h,
    double time,
    List<Color> cols,
  ) {
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
