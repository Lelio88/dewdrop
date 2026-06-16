import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:dewdrop/decor/reception_signal.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

/// Immersive "bibliothèque" decor — a warm reading sanctuary. Two variants:
///  - 0 "Cosy": a night reading nook — a window onto a lamplit street, a tall
///    bookshelf, a crackling fireplace, a green armchair with a blanket and a
///    glowing table lamp. Flickering fire and warm embers that rise off the
///    hearth, twinkling as they climb.
///  - 1 "Ancienne": a grand old hall — a vaulted ceiling, a tall arched gothic
///    window casting a cool light shaft, bookshelves along the walls and a long
///    table with an open book and a single candle. Cold pale dust hangs
///    suspended in the light beam, drifting almost imperceptibly.
///
/// The ambient particle layer is the same [_Mote] system driven two different
/// ways by [variant]: rising warm embers vs slow cool suspended dust. Distinct
/// in TYPE, not just recoloured.
///
/// Walls, furniture, shelves and windows are static; the fire / candle flames,
/// the warm glow pulse and the dust motes animate on top. A "pensée" (tap)
/// makes the flame flare and scatters sparks. Pure Canvas.
class LibraryDecor extends StatefulWidget {
  const LibraryDecor({super.key, this.variant = 0, this.reception, this.child});

  final int variant;
  final ReceptionSignal? reception;
  final Widget? child;

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
        s.y -= s.rise * dt;
        if (s.life <= 0 || s.y < -0.05) remove.add(s);
      }
      if (remove.isNotEmpty) _sparks.removeWhere(remove.contains);
    }

    _model.notify();
  }

  /// Ambient particles, distinct in TYPE per variant:
  ///  - Cosy (0): warm fireplace embers — glowing points that RISE off the
  ///    hearth (so [speed] drives upward travel), twinkle, and cluster toward
  ///    the lower-right fire. Sparse (~38), bright core + additive glow.
  ///  - Ancienne (1): cold dust motes suspended in the light shaft — pale cool
  ///    specks drifting almost imperceptibly (slow sink + sway), concentrated
  ///    in the central beam. Sparse (~36), soft and dim.
  List<_Mote> _genMotes(bool cosy) {
    final count = cosy ? 38 : 36;
    return List.generate(count, (_) {
      // Spawn position biased to where each particle "belongs": embers low
      // near the hearth, dust spread through the central shaft band.
      final x = cosy
          ? 0.58 +
                _rng.nextDouble() *
                    0.40 // hearth side (right)
          : 0.28 + _rng.nextDouble() * 0.44; // central light shaft
      final y = cosy
          ? 0.55 +
                _rng.nextDouble() *
                    0.42 // lower part (the fire)
          : 0.15 + _rng.nextDouble() * 0.68; // along the beam
      return _Mote(
        x: x,
        y: y,
        // Embers a touch larger so the glow reads; dust tiny and faint.
        r: cosy ? 0.8 + _rng.nextDouble() * 1.4 : 0.5 + _rng.nextDouble() * 1.1,
        // Embers rise briskly; dust barely sinks (almost suspended).
        speed: cosy
            ? 0.030 + _rng.nextDouble() * 0.055
            : 0.002 + _rng.nextDouble() * 0.005,
        phase: _rng.nextDouble() * math.pi * 2,
        // Embers sway a little as they rise; dust drifts very slowly sideways.
        drift: cosy
            ? 0.012 + _rng.nextDouble() * 0.03
            : 0.006 + _rng.nextDouble() * 0.02,
      );
    });
  }

  /// Light manual preview: a single flame flare, like before.
  void _tap() {
    _model.flare = _model.time;
    _model.flareScale = 1.0;
    HapticFeedback.lightImpact();
  }

  /// A pensée arrived: an AMPLIFIED celebratory swell. The flame flares far
  /// harder than a tap, and a dense flurry of drifting motes/glints rises and
  /// fades across the whole room. Variant-flavoured: warm golden embers in the
  /// Cosy nook (0), cool pale dust in the Ancienne hall's light shaft (1).
  void _onReception() {
    // 0 = Cosy (warm), 1 = Ancienne (cool).
    final cosy = widget.variant == 0;

    _model.flare = _model.time;
    _model.flareScale = 2.4; // much bigger than a tap's 1.0

    // A swell of ~54 drifting motes — far denser than the 40 ambient ones, and
    // ephemeral so the room settles back to calm afterwards.
    for (var i = 0; i < 54; i++) {
      _sparks.add(
        _Spark(
          x: _rng.nextDouble(),
          // Bias warm embers toward the lower-right hearth in Cosy; spread the
          // cool dust across the central light shaft in Ancienne.
          y: cosy
              ? 0.55 + _rng.nextDouble() * 0.40
              : 0.25 + _rng.nextDouble() * 0.55,
          r: (cosy ? 0.8 : 0.6) + _rng.nextDouble() * 2.2,
          rise: 0.06 + _rng.nextDouble() * 0.12,
          drift: 0.02 + _rng.nextDouble() * 0.05,
          phase: _rng.nextDouble() * math.pi * 2,
          ttl: 1.4 + _rng.nextDouble() * 1.6,
        ),
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
    final cosy = widget.variant == 0;
    return Stack(
      children: [
        Positioned.fill(
          child: RepaintBoundary(
            child: CustomPaint(painter: _LibraryBgPainter(cosy: cosy)),
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
  double flare = -10;
  // How big the most recent flare is: 1.0 for a tap, larger for a reception.
  double flareScale = 1.0;
  void notify() => notifyListeners();
}

/// An ambient particle. Its motion is reinterpreted per variant by the fx
/// painter: in Cosy (0) it's a fireplace ember that RISES ([speed] = upward
/// travel) and glows; in Ancienne (1) it's a cold dust mote that sinks almost
/// imperceptibly ([speed] = very slow downward drift) and just catches light.
/// [drift] is the sideways sway amplitude; [phase] desyncs twinkle/sway.
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

/// An ephemeral reception spark: a mote that rises, sways and fades. Mutable —
/// the ticker advances [y] and [life]; the fx painter renders it by [life].
class _Spark {
  _Spark({
    required this.x,
    required this.y,
    required this.r,
    required this.rise,
    required this.drift,
    required this.phase,
    required this.ttl,
  });
  final double x;
  double y;
  final double r;
  final double rise;
  final double drift;
  final double phase;
  final double ttl;
  double life = 1.0; // 1 → 0 over [ttl] seconds
}

// Warm leather book-spine palette.
const _bookColors = [
  Color(0xFF7A2E2A),
  Color(0xFF2E5A44),
  Color(0xFF6A4A22),
  Color(0xFF2A3E66),
  Color(0xFFB08A3C),
  Color(0xFFE8D8B0),
  Color(0xFF5A2E52),
  Color(0xFF3A3A40),
];

class _LibraryBgPainter extends CustomPainter {
  const _LibraryBgPainter({required this.cosy});
  final bool cosy;

  @override
  void paint(Canvas canvas, Size size) {
    if (cosy) {
      _paintCosy(canvas, size);
    } else {
      _paintAncienne(canvas, size);
    }
  }

  // ── Variant 0 — Cosy reading nook ──────────────────────────────────────────
  void _paintCosy(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Warm dark wall.
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = ui.Gradient.linear(const Offset(0, 0), Offset(0, h), const [
          Color(0xFF2E2014),
          Color(0xFF150D07),
        ]),
    );

    // Wood floor (lower quarter).
    canvas.drawRect(
      Rect.fromLTRB(0, 0.80 * h, w, h),
      Paint()
        ..shader = ui.Gradient.linear(Offset(0, 0.80 * h), Offset(0, h), const [
          Color(0xFF4A3018),
          Color(0xFF2A1A0C),
        ]),
    );
    final board = Paint()
      ..color = const Color(0x33000000)
      ..strokeWidth = 1;
    for (var i = 1; i < 6; i++) {
      final y = (0.80 + i * 0.04) * h;
      canvas.drawLine(Offset(0, y), Offset(w, y), board);
    }

    // Window onto a lamplit street (left).
    _paintWindow(
      canvas,
      Rect.fromLTRB(w * 0.05, h * 0.07, w * 0.33, h * 0.54),
      night: true,
    );

    // Tall bookshelf (right).
    _paintBookshelf(
      canvas,
      Rect.fromLTRB(w * 0.60, h * 0.05, w * 0.97, h * 0.60),
      shelves: 5,
      seed: 3,
    );

    // Fireplace (lower right).
    _paintFireplace(
      canvas,
      Rect.fromLTRB(w * 0.62, h * 0.60, w * 0.93, h * 0.85),
    );

    // Armchair (centre-left) with a plaid blanket.
    _paintArmchair(canvas, w, h);

    // Side table + lamp (between the chair and the fire).
    _paintLampTable(canvas, w, h);
  }

  void _paintWindow(Canvas canvas, Rect r, {required bool night}) {
    // Frame.
    canvas.drawRect(
      r.inflate(r.width * 0.04),
      Paint()..color = const Color(0xFF3A2616),
    );
    // Glass.
    canvas.drawRect(
      r,
      Paint()
        ..shader = night
            ? ui.Gradient.radial(
                Offset(r.left + r.width * 0.3, r.top + r.height * 0.4),
                r.height * 0.7,
                const [Color(0xFF3E5A78), Color(0xFF0E1A2C)],
              )
            : ui.Gradient.linear(r.topCenter, r.bottomCenter, const [
                Color(0xFFBFD8E8),
                Color(0xFF6E90A8),
              ]),
    );
    if (night) {
      // Warm street-lamp glow outside.
      final lamp = Offset(r.left + r.width * 0.28, r.top + r.height * 0.34);
      canvas.drawCircle(
        lamp,
        r.width * 0.5,
        Paint()
          ..blendMode = BlendMode.plus
          ..shader = ui.Gradient.radial(lamp, r.width * 0.5, const [
            Color(0x88FFD27A),
            Color(0x00FFD27A),
          ]),
      );
      canvas.drawCircle(
        lamp,
        r.width * 0.05,
        Paint()..color = const Color(0xFFFFE6A8),
      );
    }
    // Mullions (cross bars).
    final bar = Paint()..color = const Color(0xFF3A2616);
    canvas.drawRect(
      Rect.fromLTRB(r.center.dx - 2, r.top, r.center.dx + 2, r.bottom),
      bar,
    );
    canvas.drawRect(
      Rect.fromLTRB(r.left, r.center.dy - 2, r.right, r.center.dy + 2),
      bar,
    );
  }

  void _paintBookshelf(
    Canvas canvas,
    Rect r, {
    required int shelves,
    required int seed,
  }) {
    // Cabinet.
    canvas.drawRect(r.inflate(4), Paint()..color = const Color(0xFF2A1A0E));
    canvas.drawRect(r, Paint()..color = const Color(0xFF3A2616));
    final rng = math.Random(seed);
    final shelfH = r.height / shelves;
    for (var s = 0; s < shelves; s++) {
      final top = r.top + s * shelfH;
      final bottom = top + shelfH;
      // Shelf plank.
      canvas.drawRect(
        Rect.fromLTRB(r.left, bottom - shelfH * 0.06, r.right, bottom),
        Paint()..color = const Color(0xFF24160B),
      );
      // Books.
      var x = r.left + 4;
      while (x < r.right - 6) {
        final bw = 5 + rng.nextDouble() * 12;
        if (x + bw > r.right - 4) break;
        final bh = shelfH * (0.62 + rng.nextDouble() * 0.30);
        final color = _bookColors[rng.nextInt(_bookColors.length)];
        final lean = rng.nextDouble() < 0.12;
        final rect = Rect.fromLTRB(
          x,
          bottom - shelfH * 0.06 - bh,
          x + bw,
          bottom - shelfH * 0.06,
        );
        if (lean) {
          canvas.save();
          canvas.translate(rect.center.dx, rect.bottom);
          canvas.rotate(0.12);
          canvas.translate(-rect.center.dx, -rect.bottom);
          canvas.drawRect(rect, Paint()..color = color);
          canvas.restore();
        } else {
          canvas.drawRect(rect, Paint()..color = color);
          // A faint spine highlight.
          canvas.drawRect(
            Rect.fromLTRB(
              x + 1,
              rect.top + bh * 0.15,
              x + 2,
              rect.bottom - bh * 0.15,
            ),
            Paint()..color = Colors.white.withValues(alpha: 0.12),
          );
        }
        x += bw + 1.5;
      }
    }
  }

  void _paintFireplace(Canvas canvas, Rect r) {
    // Stone surround.
    canvas.drawRect(
      r.inflate(r.width * 0.08),
      Paint()..color = const Color(0xFF3E342A),
    );
    // Hearth opening (dark).
    final opening = Rect.fromLTRB(r.left, r.top, r.right, r.bottom);
    canvas.drawRRect(
      RRect.fromRectAndCorners(
        opening,
        topLeft: const Radius.circular(18),
        topRight: const Radius.circular(18),
      ),
      Paint()..color = const Color(0xFF0A0604),
    );
    // Warm glow inside (the flames themselves are drawn in the fx layer).
    canvas.drawRRect(
      RRect.fromRectAndCorners(
        opening,
        topLeft: const Radius.circular(18),
        topRight: const Radius.circular(18),
      ),
      Paint()
        ..shader = ui.Gradient.radial(
          opening.bottomCenter,
          opening.height,
          const [Color(0x66FF7A2A), Color(0x00FF7A2A)],
        ),
    );
    // Logs.
    final log = Paint()..color = const Color(0xFF3A2412);
    for (var i = 0; i < 3; i++) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(
              opening.center.dx + (i - 1) * opening.width * 0.18,
              opening.bottom - 8,
            ),
            width: opening.width * 0.42,
            height: 8,
          ),
          const Radius.circular(4),
        ),
        log,
      );
    }
  }

  void _paintArmchair(Canvas canvas, double w, double h) {
    final body = const Color(0xFF3E6E4A);
    final shade = const Color(0xFF2A4E34);
    final base = Rect.fromLTRB(w * 0.16, h * 0.55, w * 0.50, h * 0.86);
    final paint = Paint()
      ..shader = ui.Gradient.linear(base.topCenter, base.bottomCenter, [
        body,
        shade,
      ]);
    // Backrest.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(
          base.left + base.width * 0.16,
          base.top,
          base.right - base.width * 0.16,
          base.bottom - base.height * 0.18,
        ),
        const Radius.circular(22),
      ),
      paint,
    );
    // Armrests.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(
          base.left,
          base.top + base.height * 0.28,
          base.left + base.width * 0.22,
          base.bottom,
        ),
        const Radius.circular(16),
      ),
      paint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(
          base.right - base.width * 0.22,
          base.top + base.height * 0.28,
          base.right,
          base.bottom,
        ),
        const Radius.circular(16),
      ),
      paint,
    );
    // Seat cushion.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(
          base.left + base.width * 0.12,
          base.bottom - base.height * 0.34,
          base.right - base.width * 0.12,
          base.bottom,
        ),
        const Radius.circular(16),
      ),
      paint,
    );
    // Plaid blanket draped over an armrest.
    final plaid = Rect.fromLTRB(
      base.left + base.width * 0.02,
      base.top + base.height * 0.30,
      base.left + base.width * 0.30,
      base.bottom - base.height * 0.06,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(plaid, const Radius.circular(8)),
      Paint()..color = const Color(0xFFB5573E),
    );
    final check = Paint()
      ..color = const Color(0x44FFE0C0)
      ..strokeWidth = 2;
    for (var i = 0; i < 4; i++) {
      final yy = plaid.top + plaid.height * (i + 1) / 5;
      canvas.drawLine(Offset(plaid.left, yy), Offset(plaid.right, yy), check);
    }
    // A small cushion.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(
            base.center.dx + base.width * 0.06,
            base.top + base.height * 0.36,
          ),
          width: base.width * 0.32,
          height: base.height * 0.26,
        ),
        const Radius.circular(12),
      ),
      Paint()..color = const Color(0xFFD8B26A),
    );
  }

  void _paintLampTable(Canvas canvas, double w, double h) {
    // Side table.
    final top = Rect.fromLTRB(w * 0.48, h * 0.62, w * 0.60, h * 0.65);
    canvas.drawRect(top, Paint()..color = const Color(0xFF3A2414));
    canvas.drawRect(
      Rect.fromLTRB(w * 0.50, top.bottom, w * 0.505, h * 0.80),
      Paint()..color = const Color(0xFF2A1A0E),
    );
    canvas.drawRect(
      Rect.fromLTRB(w * 0.575, top.bottom, w * 0.58, h * 0.80),
      Paint()..color = const Color(0xFF2A1A0E),
    );
    // Lamp base + shade.
    final shadeCenter = Offset(w * 0.54, h * 0.575);
    canvas.drawRect(
      Rect.fromLTRB(w * 0.535, h * 0.585, w * 0.545, top.top),
      Paint()..color = const Color(0xFF6A4A2A),
    );
    final shade = Path()
      ..moveTo(shadeCenter.dx - w * 0.045, shadeCenter.dy + h * 0.025)
      ..lineTo(shadeCenter.dx + w * 0.045, shadeCenter.dy + h * 0.025)
      ..lineTo(shadeCenter.dx + w * 0.030, shadeCenter.dy - h * 0.025)
      ..lineTo(shadeCenter.dx - w * 0.030, shadeCenter.dy - h * 0.025)
      ..close();
    canvas.drawPath(shade, Paint()..color = const Color(0xFFFFD884));
  }

  // ── Variant 1 — Grand old hall ─────────────────────────────────────────────
  void _paintAncienne(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Warm stone hall.
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = ui.Gradient.linear(const Offset(0, 0), Offset(0, h), const [
          Color(0xFF2A2016),
          Color(0xFF120C07),
        ]),
    );

    // Vaulted ceiling ribs (top), converging toward the centre.
    final rib = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = const Color(0xFF5A4226);
    final apex = Offset(w * 0.5, -h * 0.05);
    for (final sx in [0.0, 0.2, 0.4, 0.6, 0.8, 1.0]) {
      final path = Path()
        ..moveTo(sx * w, h * 0.30)
        ..quadraticBezierTo(w * 0.5, h * 0.02, apex.dx, apex.dy);
      canvas.drawPath(path, rib);
    }
    canvas.drawRect(
      Rect.fromLTRB(0, 0, w, h * 0.30),
      Paint()
        ..shader = ui.Gradient.linear(
          const Offset(0, 0),
          Offset(0, h * 0.30),
          const [Color(0x553A2C18), Color(0x00000000)],
        ),
    );

    // Side bookshelves (receding walls).
    _paintBookshelf(
      canvas,
      Rect.fromLTRB(0, h * 0.18, w * 0.26, h * 0.74),
      shelves: 6,
      seed: 7,
    );
    _paintBookshelf(
      canvas,
      Rect.fromLTRB(w * 0.74, h * 0.18, w, h * 0.74),
      shelves: 6,
      seed: 11,
    );

    // Tall arched gothic window (back centre) with cool daylight.
    _paintGothicWindow(canvas, w, h);

    // Stone floor.
    canvas.drawRect(
      Rect.fromLTRB(0, h * 0.74, w, h),
      Paint()
        ..shader = ui.Gradient.linear(Offset(0, h * 0.74), Offset(0, h), const [
          Color(0xFF3A2E20),
          Color(0xFF1A140C),
        ]),
    );

    // Long reading table with an open book + candle.
    _paintTable(canvas, w, h);
  }

  void _paintGothicWindow(Canvas canvas, double w, double h) {
    final r = Rect.fromLTRB(w * 0.37, h * 0.12, w * 0.63, h * 0.52);
    final arch = Path()
      ..moveTo(r.left, r.bottom)
      ..lineTo(r.left, r.top + r.height * 0.28)
      ..quadraticBezierTo(
        r.center.dx,
        r.top - r.height * 0.10,
        r.center.dx,
        r.top - r.height * 0.10,
      )
      ..quadraticBezierTo(
        r.center.dx,
        r.top - r.height * 0.10,
        r.right,
        r.top + r.height * 0.28,
      )
      ..lineTo(r.right, r.bottom)
      ..close();
    // Stone reveal.
    canvas.drawPath(
      arch,
      Paint()
        ..color = const Color(0xFF4A3A28)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8,
    );
    canvas.drawPath(
      arch,
      Paint()
        ..shader = ui.Gradient.linear(r.topCenter, r.bottomCenter, const [
          Color(0xFFEAF2F8),
          Color(0xFF8FB0C8),
        ]),
    );
    // Tracery (mullions).
    final bar = Paint()
      ..color = const Color(0xFF3A2C1A)
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke;
    canvas.drawLine(
      Offset(r.center.dx, r.top - r.height * 0.06),
      Offset(r.center.dx, r.bottom),
      bar,
    );
    for (final fy in [0.35, 0.6, 0.82]) {
      canvas.drawLine(
        Offset(r.left, r.top + r.height * fy),
        Offset(r.right, r.top + r.height * fy),
        bar,
      );
    }
  }

  void _paintTable(Canvas canvas, double w, double h) {
    final top = Rect.fromLTRB(w * 0.18, h * 0.78, w * 0.82, h * 0.84);
    canvas.drawRect(
      top,
      Paint()
        ..shader = ui.Gradient.linear(top.topCenter, top.bottomCenter, const [
          Color(0xFF5A3A1E),
          Color(0xFF3A2410),
        ]),
    );
    canvas.drawRect(
      Rect.fromLTRB(top.left + 10, top.bottom, top.left + 24, h),
      Paint()..color = const Color(0xFF2E1C0E),
    );
    canvas.drawRect(
      Rect.fromLTRB(top.right - 24, top.bottom, top.right - 10, h),
      Paint()..color = const Color(0xFF2E1C0E),
    );
    // Open book (two cream pages).
    final bookC = Offset(w * 0.42, top.top - 2);
    final page = Paint()..color = const Color(0xFFEFE2C4);
    final lp = Path()
      ..moveTo(bookC.dx, bookC.dy)
      ..lineTo(bookC.dx - w * 0.085, bookC.dy - h * 0.006)
      ..lineTo(bookC.dx - w * 0.080, bookC.dy - h * 0.028)
      ..lineTo(bookC.dx, bookC.dy - h * 0.022)
      ..close();
    final rp = Path()
      ..moveTo(bookC.dx, bookC.dy)
      ..lineTo(bookC.dx + w * 0.085, bookC.dy - h * 0.006)
      ..lineTo(bookC.dx + w * 0.080, bookC.dy - h * 0.028)
      ..lineTo(bookC.dx, bookC.dy - h * 0.022)
      ..close();
    canvas.drawPath(lp, page);
    canvas.drawPath(rp, page);
    // The candle body (flame is drawn in the fx layer).
    canvas.drawRect(
      Rect.fromLTRB(w * 0.60, top.top - h * 0.05, w * 0.612, top.top),
      Paint()..color = const Color(0xFFE8DCC0),
    );
  }

  @override
  bool shouldRepaint(_LibraryBgPainter old) => old.cosy != cosy;
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
    // Scale the flare envelope by how big the triggering pulse was (a reception
    // flares far harder, and for a touch longer, than a manual tap).
    final flareScale = model.flareScale;
    final flare =
        ((1 - (time - model.flare) / 1.2).clamp(0.0, 1.0)) * flareScale;

    if (cosy) {
      _paintFire(
        canvas,
        Rect.fromLTRB(w * 0.62, h * 0.60, w * 0.93, h * 0.85),
        time,
        flare,
      );
      // Lamp warm pool of light.
      _glow(
        canvas,
        Offset(w * 0.54, h * 0.565),
        w * 0.22,
        const Color(0xFFFFD884),
        0.12 + 0.02 * math.sin(time * 2),
      );
    } else {
      // Cool light shaft from the window.
      _paintLightShaft(canvas, w, h, time);
      // Candle flame on the table.
      _paintCandle(canvas, Offset(w * 0.606, h * 0.73), time, flare);
    }

    // Ambient particle layer — distinct TYPE per variant. Gentler than the
    // reception burst (_paintSparks), but continuously alive.
    if (cosy) {
      _paintEmbers(canvas, w, h, time);
    } else {
      _paintColdDust(canvas, w, h, time);
    }

    _paintSparks(canvas, w, h, time);
  }

  // Ambient variant 0 — fireplace embers. Warm glowing points that RISE off
  // the hearth (subtract `time * speed` from y so they travel upward), twinkle,
  // and sway a touch. Additive glow + bright core so they read as live sparks.
  void _paintEmbers(Canvas canvas, double w, double h, double time) {
    const core = Color(0xFFFFC766); // warm amber core
    const halo = Color(0xFFFF8A3A); // orange glow
    for (final m in motes) {
      // Rise from the spawn band toward the top, looping in the lower-2/3 so
      // embers stay biased to the fire rather than filling the whole ceiling.
      final travel = (time * m.speed) % 0.95;
      final y = m.y - travel;
      if (y < 0.02) continue; // faded out above the hearth's reach
      final x = m.x + math.sin(time * 0.7 + m.phase) * m.drift;
      // Twinkle, and dim as the ember climbs (cools as it rises).
      final twinkle = 0.5 + 0.5 * math.sin(time * 3.0 + m.phase);
      final climbFade = (1.0 - travel / 0.95).clamp(0.0, 1.0);
      final a = (0.22 + 0.30 * twinkle) * climbFade;
      final px = x * w;
      final py = y * h;
      // Soft halo.
      canvas.drawCircle(
        Offset(px, py),
        m.r * 2.2,
        Paint()
          ..blendMode = BlendMode.plus
          ..color = halo.withValues(alpha: 0.22 * a),
      );
      // Bright core.
      canvas.drawCircle(
        Offset(px, py),
        m.r * 0.9,
        Paint()
          ..blendMode = BlendMode.plus
          ..color = core.withValues(alpha: a),
      );
    }
  }

  // Ambient variant 1 — cold dust in the light shaft. Pale cool specks drifting
  // almost imperceptibly: a very slow sink plus a faint sideways sway, dim and
  // suspended. No additive blend — they just catch the light softly.
  void _paintColdDust(Canvas canvas, double w, double h, double time) {
    const dustColor = Color(0xFFEAF2FA); // pale cool
    for (final m in motes) {
      // Barely sinks; wraps over the shaft band so density stays where the
      // beam is rather than streaming off the floor.
      final y = (m.y + time * m.speed) % 1.0;
      final x = m.x + math.sin(time * 0.18 + m.phase) * m.drift;
      // Slow shimmer; overall faint so it reads as suspended motes, not snow.
      final a = 0.07 + 0.07 * (0.5 + 0.5 * math.sin(time * 0.8 + m.phase));
      canvas.drawCircle(
        Offset(x * w, y * h),
        m.r,
        Paint()..color = dustColor.withValues(alpha: a),
      );
    }
  }

  // Reception burst: a swell of drifting, fading glints. Reuses the per-variant
  // mote palette so it reads as "the room's own dust, lit up" — warm golden
  // embers in the Cosy nook, cool pale dust in the Ancienne light shaft.
  void _paintSparks(Canvas canvas, double w, double h, double time) {
    if (sparks.isEmpty) return;
    // A touch brighter/warmer than the ambient motes for a celebratory feel.
    final core = cosy ? const Color(0xFFFFC766) : const Color(0xFFEAF2FA);
    final halo = cosy ? const Color(0xFFFF8A3A) : const Color(0xFFBFD4E8);
    for (final s in sparks) {
      // Ease-out fade (bright at birth, gentle tail).
      final fade = (s.life * s.life).clamp(0.0, 1.0);
      final x = (s.x + math.sin(time * 0.6 + s.phase) * s.drift) * w;
      final y = s.y * h;
      final r = s.r;
      // Soft halo.
      canvas.drawCircle(
        Offset(x, y),
        r * 2.4,
        Paint()
          ..blendMode = BlendMode.plus
          ..color = halo.withValues(alpha: 0.28 * fade),
      );
      // Bright core.
      canvas.drawCircle(
        Offset(x, y),
        r,
        Paint()
          ..blendMode = BlendMode.plus
          ..color = core.withValues(alpha: 0.85 * fade),
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

  void _paintFire(Canvas canvas, Rect hearth, double time, double flare) {
    final base = Offset(hearth.center.dx, hearth.bottom - 8);
    final intensity = 1.0 + flare * 0.6;
    // Pulsing warm glow on the room.
    _glow(
      canvas,
      base,
      hearth.width * (0.9 + 0.1 * math.sin(time * 6)) * intensity,
      const Color(0xFFFF8A3A),
      (0.22 + 0.05 * math.sin(time * 7)) * intensity,
    );
    // Flame tongues.
    for (var i = 0; i < 5; i++) {
      final sway = math.sin(time * 5 + i * 1.3) * hearth.width * 0.04;
      final fx = base.dx + (i - 2) * hearth.width * 0.10 + sway;
      final fh =
          hearth.height *
          (0.34 + 0.16 * (0.5 + 0.5 * math.sin(time * 8 + i))) *
          intensity;
      final fw = hearth.width * 0.10;
      final flame = Path()
        ..moveTo(fx - fw / 2, base.dy)
        ..quadraticBezierTo(fx - fw * 0.2, base.dy - fh * 0.6, fx, base.dy - fh)
        ..quadraticBezierTo(
          fx + fw * 0.2,
          base.dy - fh * 0.6,
          fx + fw / 2,
          base.dy,
        )
        ..close();
      canvas.drawPath(
        flame,
        Paint()
          ..blendMode = BlendMode.plus
          ..shader = ui.Gradient.linear(
            Offset(fx, base.dy),
            Offset(fx, base.dy - fh),
            const [Color(0xFFFFE26A), Color(0xFFFF6A1E), Color(0x00FF4A0E)],
            const [0.0, 0.5, 1.0],
          ),
      );
    }
    // Rising embers.
    final rng = math.Random(2);
    for (var i = 0; i < 8; i++) {
      final t =
          (time * (0.3 + rng.nextDouble() * 0.3) + rng.nextDouble()) % 1.0;
      final x = base.dx + (rng.nextDouble() - 0.5) * hearth.width * 0.6;
      final y = base.dy - t * hearth.height * 1.1;
      canvas.drawCircle(
        Offset(x + math.sin(time * 3 + i) * 4, y),
        1.2 * (1 - t),
        Paint()
          ..color = const Color(0xFFFFB860).withValues(alpha: (1 - t) * 0.8),
      );
    }
  }

  void _paintCandle(Canvas canvas, Offset wick, double time, double flare) {
    final intensity = 1.0 + flare * 0.8;
    final fh = 26.0 * (0.85 + 0.15 * math.sin(time * 9)) * intensity;
    final sway = math.sin(time * 6) * 2;
    _glow(
      canvas,
      wick + const Offset(0, -6),
      90 * intensity,
      const Color(0xFFFFC766),
      0.16 + 0.04 * math.sin(time * 8),
    );
    final flame = Path()
      ..moveTo(wick.dx - 5, wick.dy)
      ..quadraticBezierTo(
        wick.dx - 3 + sway,
        wick.dy - fh * 0.6,
        wick.dx + sway,
        wick.dy - fh,
      )
      ..quadraticBezierTo(
        wick.dx + 3 + sway,
        wick.dy - fh * 0.6,
        wick.dx + 5,
        wick.dy,
      )
      ..close();
    canvas.drawPath(
      flame,
      Paint()
        ..blendMode = BlendMode.plus
        ..shader = ui.Gradient.linear(
          Offset(wick.dx, wick.dy),
          Offset(wick.dx, wick.dy - fh),
          const [Color(0xFFFFF0A0), Color(0xFFFF9A3A), Color(0x00FF6A1E)],
          const [0.0, 0.5, 1.0],
        ),
    );
  }

  void _paintLightShaft(Canvas canvas, double w, double h, double time) {
    final shaft = Path()
      ..moveTo(w * 0.40, h * 0.18)
      ..lineTo(w * 0.60, h * 0.18)
      ..lineTo(w * 0.74, h * 0.78)
      ..lineTo(w * 0.30, h * 0.78)
      ..close();
    final a = 0.06 + 0.02 * math.sin(time * 0.8);
    canvas.drawPath(
      shaft,
      Paint()
        ..blendMode = BlendMode.plus
        ..shader = ui.Gradient.linear(
          Offset(w * 0.5, h * 0.18),
          Offset(w * 0.5, h * 0.78),
          [
            const Color(0xFFDCEAF6).withValues(alpha: a),
            const Color(0x00DCEAF6),
          ],
        ),
    );
  }

  @override
  bool shouldRepaint(_LibraryFxPainter old) => false;
}
