import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:dewdrop/decor/decor_backdrop.dart';
import 'package:dewdrop/decor/reception_signal.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

/// The variants of the "espace" environment.
enum SpaceVariant {
  /// Stars + soft coloured nebulae (the default cosy cosmos).
  cosmos,

  /// Pure black void; only the stars twinkle. The most minimal.
  voidNight,

  /// Stars + a couple of stylised planets drifting in view.
  planets,
}

/// Immersive "espace" decor: the parallax photo/illustrated backdrop with a
/// celebratory "pluie d'étoiles filantes" overlaid on top. A tap on the open
/// sky previews a light shower; receiving a "pensée" pulses [reception] for the
/// amplified burst, tinted per [variant].
///
/// The backdrop image (stars, nebulae, planets) is supplied by [DecorBackdrop];
/// only the shooting-star FX is drawn here, in pure Canvas. [reception] is the
/// host-owned "a pensée just arrived" pulse — the widget only listens, it never
/// disposes the signal. [child] floats over the scene (the app UI).
class SpaceDecor extends StatefulWidget {
  const SpaceDecor({
    super.key,
    this.variant = SpaceVariant.cosmos,
    this.reception,
    this.parallax = true,
    this.child,
    this.assetRoot = 'photo',
  });

  final SpaceVariant variant;
  final ReceptionSignal? reception;
  final bool parallax;
  final Widget? child;
  // 'photo' or 'illustrated' — which parallax backdrop sits behind.
  final String assetRoot;

  @override
  State<SpaceDecor> createState() => _SpaceDecorState();
}

class _SpaceDecorState extends State<SpaceDecor>
    with SingleTickerProviderStateMixin {
  final _model = _DecorModel();
  final math.Random _rng = math.Random(7);

  late final Ticker _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
    widget.reception?.addListener(_onReception);
  }

  @override
  void didUpdateWidget(SpaceDecor old) {
    super.didUpdateWidget(old);
    if (old.reception != widget.reception) {
      old.reception?.removeListener(_onReception);
      widget.reception?.addListener(_onReception);
    }
  }

  void _onTick(Duration elapsed) {
    final now = elapsed.inMicroseconds / 1e6;
    _model.time = now;
    _model.shooting.removeWhere((s) => s.isDead(now));
    _model.notify();
  }

  /// A tap on the open sky: rain a light, staggered shower of shooting stars.
  /// This is the manual preview — the real reception burst ([_onReception]) is
  /// a much bigger, denser version of the same effect.
  void _spawnThoughtShower() {
    const count = 14;
    for (var i = 0; i < count; i++) {
      final from = Offset(
        _rng.nextDouble() * 1.1 - 0.05,
        _rng.nextDouble() * 0.4 - 0.05,
      );
      final dir = Offset(
        0.55 + (_rng.nextDouble() - 0.5) * 0.25,
        0.65 + (_rng.nextDouble() - 0.5) * 0.25,
      );
      final length = 0.4 + _rng.nextDouble() * 0.35;
      _model.shooting.add(
        _ShootingStar(
          startTime: _model.time + _rng.nextDouble(),
          from: from,
          to: from + dir * length,
          duration: 0.9 + _rng.nextDouble() * 0.6,
        ),
      );
    }
    HapticFeedback.mediumImpact();
  }

  /// A "pensée" arrived: an AMPLIFIED celebratory burst — a real "pluie
  /// d'étoiles filantes". Many more streaks than the tap preview (~38 vs 14),
  /// seeded across the full width and a taller top band, with longer trails and
  /// a wider stagger so they cascade in a sustained wave. Each streak is tinted
  /// per [SpaceVariant] (reusing the decor's own palette) so the shower feels
  /// native to the current scene rather than a generic white rain.
  void _onReception() {
    // Intensity = how many pensées were caught up at once: more streaks
    // (stronger), spread over a longer stagger window so the wave lasts longer.
    final k = widget.reception?.intensity ?? 1.0;
    final count = (38 * k).round();
    final stagger = 1.4 * (1 + (k - 1) * 0.5);
    final tints = _showerTints(widget.variant);
    for (var i = 0; i < count; i++) {
      final from = Offset(
        _rng.nextDouble() * 1.2 - 0.1,
        _rng.nextDouble() * 0.55 - 0.1,
      );
      final dir = Offset(
        0.55 + (_rng.nextDouble() - 0.5) * 0.3,
        0.65 + (_rng.nextDouble() - 0.5) * 0.3,
      );
      final length = 0.55 + _rng.nextDouble() * 0.5;
      _model.shooting.add(
        _ShootingStar(
          startTime: _model.time + _rng.nextDouble() * stagger,
          from: from,
          to: from + dir * length,
          duration: 1.0 + _rng.nextDouble() * 0.8,
          color: tints[_rng.nextInt(tints.length)],
        ),
      );
    }
    HapticFeedback.mediumImpact();
  }

  /// Per-variant streak colours for the reception shower, drawn from each
  /// variant's existing palette:
  ///  - cosmos ("Cosmos", B&W Milky Way): neutral whites, no colour at all.
  ///  - voidNight ("Nuit noire"): the nebula/debris cool blues + a violet.
  ///  - planets ("Planètes"): the warm sun + planet hues riding the orbits.
  List<Color> _showerTints(SpaceVariant variant) => switch (variant) {
    SpaceVariant.cosmos => const [
      Color(0xFFF2F4F8),
      Color(0xFFEAF2FF),
      Color(0xFFD6DCEA),
    ],
    SpaceVariant.voidNight => const [
      Color(0xFFCFE0FF), // debris glow
      Color(0xFF7AB0D8), // nebula blue
      Color(0xFFB58CD8), // nebula violet
      Color(0xFFEAF2FF), // bright white
    ],
    SpaceVariant.planets => const [
      Color(0xFFFFF1C8), // sun core
      Color(0xFFE2C58A), // Vénus
      Color(0xFF5A86C0), // Terre
      Color(0xFFD8A86A), // Jupiter
    ],
  };

  // Dominant tone per variant — the flat colour shown for the one frame before
  // the photo decodes (matches the dark sky of each scene).
  Color get _baseColor => switch (widget.variant) {
    SpaceVariant.cosmos => const Color(0xFF030305),
    SpaceVariant.voidNight => const Color(0xFF05060E),
    SpaceVariant.planets => const Color(0xFF03030A),
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
    return Stack(
      children: [
        Positioned.fill(
          child: DecorBackdrop(
            env: 'space',
            variant: widget.variant.index,
            assetRoot: widget.assetRoot,
            parallax: widget.parallax,
            baseColor: _baseColor,
          ),
        ),
        // Tap anywhere on the open sky to send a "pensée".
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _spawnThoughtShower,
          ),
        ),
        Positioned.fill(
          child: IgnorePointer(
            child: RepaintBoundary(
              child: CustomPaint(painter: _ShootingStarPainter(_model)),
            ),
          ),
        ),
        if (widget.child != null) Positioned.fill(child: widget.child!),
      ],
    );
  }
}

/// Mutable per-frame state shared with the shooting-star painter; notifies it
/// to repaint.
class _DecorModel extends ChangeNotifier {
  double time = 0;
  final List<_ShootingStar> shooting = [];

  void notify() => notifyListeners();
}

class _ShootingStar {
  _ShootingStar({
    required this.startTime,
    required this.from,
    required this.to,
    this.duration = 1.1,
    this.color = const Color(0xFFFFFFFF),
  });

  final Offset from;
  final Offset to;
  final double startTime;
  final double duration;

  /// Streak tint. Defaults to white (the manual tap preview); the reception
  /// burst overrides it per variant for a flavoured "pluie d'étoiles filantes".
  final Color color;

  double life(double now) => ((now - startTime) / duration).clamp(0.0, 1.0);
  bool isDead(double now) => now - startTime > duration;
}

class _ShootingStarPainter extends CustomPainter {
  _ShootingStarPainter(this.model) : super(repaint: model);

  final _DecorModel model;

  @override
  void paint(Canvas canvas, Size size) {
    for (final star in model.shooting) {
      final t = star.life(model.time);
      if (t <= 0) continue;
      final eased = Curves.easeOut.transform(t);
      final tailT = (eased - 0.12).clamp(0.0, 1.0);

      final head = Offset(
        ui.lerpDouble(star.from.dx, star.to.dx, eased)! * size.width,
        ui.lerpDouble(star.from.dy, star.to.dy, eased)! * size.height,
      );
      final tail = Offset(
        ui.lerpDouble(star.from.dx, star.to.dx, tailT)! * size.width,
        ui.lerpDouble(star.from.dy, star.to.dy, tailT)! * size.height,
      );

      final fade = (t < 0.15 ? t / 0.15 : 1 - (t - 0.15) / 0.85).clamp(
        0.0,
        1.0,
      );

      final tint = star.color;

      canvas.drawLine(
        tail,
        head,
        Paint()
          ..strokeWidth = 2.0
          ..strokeCap = StrokeCap.round
          ..shader = ui.Gradient.linear(tail, head, [
            tint.withValues(alpha: 0),
            tint.withValues(alpha: fade),
          ]),
      );
      canvas.drawCircle(
        head,
        2.4,
        Paint()
          ..color = tint.withValues(alpha: fade)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
      );
    }
  }

  @override
  bool shouldRepaint(_ShootingStarPainter oldDelegate) => false;
}
