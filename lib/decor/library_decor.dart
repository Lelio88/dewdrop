import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:dewdrop/decor/decor_backdrop.dart';
import 'package:dewdrop/decor/reception_signal.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

/// Immersive "bibliothèque" decor — a warm reading sanctuary. Two variants
/// (Cosy / Ancienne) supplied by the parallax photo/illustrated backdrop. The
/// ambient dust motes (warm lamp-lit dust vs cold suspended dust) and, in Cosy,
/// the soft lamp glow animate on top. A received pensée swells a denser flurry
/// of lit motes that rise and fade. FX in pure Canvas.
class LibraryDecor extends StatefulWidget {
  const LibraryDecor({
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
  State<LibraryDecor> createState() => _LibraryDecorState();
}

class _LibraryDecorState extends State<LibraryDecor>
    with SingleTickerProviderStateMixin {
  final _model = _LibraryModel();
  final math.Random _rng = math.Random(29);
  late final Ticker _ticker;
  late final List<_Mote> _motes = _genMotes(widget.variant == 0);

  // Ephemeral burst sparks spawned on a reception (a swell of drifting motes
  // that rise, sway and fade out). Ambient [_motes] keep looping untouched.
  final List<_Spark> _sparks = [];

  double _lastTick = 0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
    widget.reception?.addListener(_onReception);
  }

  @override
  void didUpdateWidget(LibraryDecor old) {
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

    if (_sparks.isNotEmpty) {
      final remove = <_Spark>[];
      for (final s in _sparks) {
        s.life -= dt / s.ttl;
        s.y += s.fall * dt;
        if (s.life <= 0 || s.y > 1.05) remove.add(s);
      }
      if (remove.isNotEmpty) _sparks.removeWhere(remove.contains);
    }

    _model.notify();
  }

  /// Ambient particles — round dust motes for BOTH variants, suspended and
  /// barely sinking, distinguished only by tint (the fx painter colours them):
  ///  - Cosy (0): warm golden dust biased toward the lamp pool, catching its
  ///    glow (brighter the nearer it drifts to the lamp).
  ///  - Ancienne (1): cold pale-grey dust suspended in the central light shaft.
  List<_Mote> _genMotes(bool cosy) {
    return List.generate(60, (_) {
      // Dust drifts across the FULL width of the screen (not a central band),
      // spread over most of the height too.
      final x = 0.02 + _rng.nextDouble() * 0.96;
      final y = cosy
          ? 0.20 + _rng.nextDouble() * 0.70
          : 0.12 + _rng.nextDouble() * 0.76;
      return _Mote(
        x: x,
        y: y,
        // Fine floating dust — visible but not chunky.
        r: 1.2 + _rng.nextDouble() * 1.8,
        // Both barely sink — dust suspended in the air, not falling.
        speed: 0.002 + _rng.nextDouble() * 0.006,
        phase: _rng.nextDouble() * math.pi * 2,
        drift: 0.006 + _rng.nextDouble() * 0.02,
      );
    });
  }

  /// Light manual preview: a small puff of drifting dust — a reduced version of
  /// the reception swell, so a tap shows something instead of nothing.
  void _tap() {
    _spawnDust(18);
    HapticFeedback.lightImpact();
  }

  /// A pensée arrived: an AMPLIFIED celebratory swell — a dense flurry of
  /// drifting motes rises and fades across the whole room. Variant-flavoured by
  /// the fx painter: warm golden dust in the Cosy nook (0), cool pale dust in
  /// the Ancienne hall (1).
  void _onReception() {
    // Intensity = how many pensées were caught up at once: more motes
    // (stronger) that linger a little longer (lifeScale).
    final k = widget.reception?.intensity ?? 1.0;
    _spawnDust((54 * k).round(), lifeScale: 1 + (k - 1) * 0.5);
    HapticFeedback.mediumImpact();
  }

  /// Spawn [count] ephemeral drifting motes that settle DOWNWARD, sway and fade.
  /// Shared by a tap (small puff) and a reception (large swell). [lifeScale]
  /// stretches how long the motes linger — a bigger catch-up lasts longer.
  void _spawnDust(int count, {double lifeScale = 1.0}) {
    final cosy = widget.variant == 0;
    for (var i = 0; i < count; i++) {
      _sparks.add(
        _Spark(
          x: _rng.nextDouble(),
          // Spawn across the upper-mid room (full width either variant) so the
          // kicked-up dust has room to settle DOWNWARD as it fades.
          y: 0.15 + _rng.nextDouble() * 0.5,
          r: (cosy ? 0.8 : 0.6) + _rng.nextDouble() * 2.2,
          // Faster settle than the ambient motes — kicked-up dust dropping back.
          fall: 0.10 + _rng.nextDouble() * 0.12,
          drift: 0.02 + _rng.nextDouble() * 0.05,
          phase: _rng.nextDouble() * math.pi * 2,
          ttl: (1.4 + _rng.nextDouble() * 1.6) * lifeScale,
        ),
      );
    }
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
    final cosy = widget.variant == 0;
    return Stack(
      children: [
        Positioned.fill(
          child: DecorBackdrop(
            env: 'library',
            variant: widget.variant,
            assetRoot: widget.assetRoot,
            baseColor: cosy
                ? const Color(0xFF1A120A) // Cosy — warm dark wood
                : const Color(0xFF120C07), // Ancienne — warm stone shadow
          ),
        ),
        Positioned.fill(
          child: RepaintBoundary(
            child: CustomPaint(
              painter: _LibraryFxPainter(
                model: _model,
                cosy: cosy,
                motes: _motes,
                sparks: _sparks,
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

class _LibraryModel extends ChangeNotifier {
  double time = 0;
  void notify() => notifyListeners();
}

/// An ambient dust mote, suspended and barely sinking ([speed] = a very slow
/// downward drift). The fx painter tints it per variant — warm golden, lamp-lit
/// in Cosy (0), cold pale-grey in the Ancienne (1) light shaft. [drift] is the
/// sideways sway amplitude; [phase] desyncs the twinkle/sway.
class _Mote {
  const _Mote({
    required this.x,
    required this.y,
    required this.r,
    required this.speed,
    required this.phase,
    required this.drift,
  });
  final double x;
  final double y;
  final double r;
  final double speed;
  final double phase;
  final double drift;
}

/// An ephemeral reception spark: a mote that drifts DOWN, sways and fades.
/// Mutable — the ticker advances [y] and [life]; the fx painter renders by [life].
class _Spark {
  _Spark({
    required this.x,
    required this.y,
    required this.r,
    required this.fall,
    required this.drift,
    required this.phase,
    required this.ttl,
  });
  final double x;
  double y;
  final double r;
  final double fall;
  final double drift;
  final double phase;
  final double ttl;
  double life = 1.0; // 1 → 0 over [ttl] seconds
}

class _LibraryFxPainter extends CustomPainter {
  _LibraryFxPainter({
    required this.model,
    required this.cosy,
    required this.motes,
    required this.sparks,
  }) : super(repaint: model);

  final _LibraryModel model;
  final bool cosy;
  final List<_Mote> motes;
  final List<_Spark> sparks;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final time = model.time;

    if (cosy) {
      // Soft table-lamp pool of light (no fireplace fire any more).
      _glow(
        canvas,
        Offset(w * 0.54, h * 0.565),
        w * 0.22,
        const Color(0xFFFFD884),
        0.12 + 0.02 * math.sin(time * 2),
      );
    }

    // Ambient round dust motes on BOTH variants — warm golden lamp-lit dust in
    // the Cosy nook; cold pale-grey suspended dust in the Ancienne shaft.
    _paintDust(canvas, w, h, time);

    _paintSparks(canvas, w, h, time);
  }

  // Ambient round dust motes, one tint per variant. Cosy (0): warm golden dust
  // that brightens as it nears the lamp pool, drawn additively so it reads as
  // catching the light. Ancienne (1): cold pale-grey dust suspended in the
  // shaft, drawn flat and faint. Both barely sink + sway — suspended, not snow.
  void _paintDust(Canvas canvas, double w, double h, double time) {
    final dustColor = cosy
        ? const Color(0xFFFFD8A0) // warm golden
        : const Color(0xFFE6ECF2); // cold pale-grey
    // Centre of the lamp pool (Cosy), used to brighten nearby motes.
    const lamp = Offset(0.54, 0.565);
    for (final m in motes) {
      final y = (m.y + time * m.speed) % 1.0;
      final x = m.x + math.sin(time * 0.18 + m.phase) * m.drift;
      final tw = 0.5 + 0.5 * math.sin(time * 0.8 + m.phase);
      var a = cosy ? 0.18 + 0.20 * tw : 0.16 + 0.14 * tw;
      if (cosy) {
        // Catch the lamp glow: brighter the nearer the mote is to the lamp.
        final near = (1 - (Offset(x, y) - lamp).distance / 0.42).clamp(
          0.0,
          1.0,
        );
        a *= 0.5 + 0.9 * near;
      }
      a = a.clamp(0.0, 1.0);
      final c = Offset(x * w, y * h);
      if (cosy) {
        canvas.drawCircle(
          c,
          m.r * 2.2,
          Paint()
            ..blendMode = BlendMode.plus
            ..color = dustColor.withValues(alpha: 0.30 * a),
        );
        canvas.drawCircle(
          c,
          m.r,
          Paint()..color = dustColor.withValues(alpha: a),
        );
      } else {
        // Soft halo so the cold dust reads against the dark hall, plus the mote.
        canvas.drawCircle(
          c,
          m.r * 2.0,
          Paint()
            ..blendMode = BlendMode.plus
            ..color = dustColor.withValues(alpha: 0.20 * a),
        );
        canvas.drawCircle(
          c,
          m.r,
          Paint()..color = dustColor.withValues(alpha: a),
        );
      }
    }
  }

  // Reception burst: a swell of drifting, fading glints. Reuses the per-variant
  // mote palette so it reads as "the room's own dust, lit up" — warm golden
  // embers in the Cosy nook, cool pale dust in the Ancienne light shaft.
  void _paintSparks(Canvas canvas, double w, double h, double time) {
    if (sparks.isEmpty) return;
    // Same palette + luminance as the ambient dust — it's the room's own dust
    // kicked up, just more of it and settling faster. NOT a brighter burst.
    final dustColor = cosy
        ? const Color(0xFFFFD8A0) // warm golden
        : const Color(0xFFE6ECF2); // cold pale-grey
    for (final s in sparks) {
      // Ease-out fade (present at birth, gentle tail).
      final fade = (s.life * s.life).clamp(0.0, 1.0);
      final x = (s.x + math.sin(time * 0.6 + s.phase) * s.drift) * w;
      final y = s.y * h;
      final r = s.r;
      // Soft halo, matching the ambient mote halo.
      canvas.drawCircle(
        Offset(x, y),
        r * 2.2,
        Paint()
          ..blendMode = BlendMode.plus
          ..color = dustColor.withValues(alpha: 0.16 * fade),
      );
      // Core at the ambient mote's luminance (not brighter).
      canvas.drawCircle(
        Offset(x, y),
        r,
        Paint()..color = dustColor.withValues(alpha: 0.38 * fade),
      );
    }
  }

  void _glow(Canvas canvas, Offset c, double r, Color color, double a) {
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..blendMode = BlendMode.plus
        ..shader = ui.Gradient.radial(c, r, [
          color.withValues(alpha: a),
          color.withValues(alpha: 0),
        ]),
    );
  }

  @override
  bool shouldRepaint(_LibraryFxPainter old) => false;
}
