import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// A soft cumulus-shaped speech bubble — the tour's whole visual identity.
///
/// The silhouette is ONE path (rounded body ∪ three lobes), unioned before it
/// is filled: drawing overlapping circles separately would show their seams
/// through the gradient and the shadow. [_kLobeBand] is the vertical strip the
/// lobes live in, and the child is padded by exactly that much so text never
/// climbs into the bumpy part.
///
/// ```dart
/// CloudBubble(
///   tail: CloudTail.below,   // little puffs trailing down toward the target
///   tailAlignX: 0.0,         // -1 = left edge, 1 = right edge of the bubble
///   child: Text('…'),
/// )
/// ```
class CloudBubble extends StatelessWidget {
  const CloudBubble({
    super.key,
    required this.child,
    this.tail = CloudTail.none,
    this.tailAlignX = 0,
  });

  final Widget child;

  /// Which side the trailing puffs sit on — they point at what the bubble is
  /// talking about.
  final CloudTail tail;

  /// Where those puffs sit across the bubble: -1 left edge, 0 centre, 1 right.
  final double tailAlignX;

  // Vertical band reserved at the top of the bubble for the cloud's lobes.
  static const double _kLobeBand = 40;

  @override
  Widget build(BuildContext context) {
    final puffs = _Puffs(alignX: tailAlignX.clamp(-1.0, 1.0));
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (tail == CloudTail.above) _flip(puffs),
        CustomPaint(
          painter: _CloudPainter(lobeBand: _kLobeBand),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, _kLobeBand + 14, 24, 22),
            child: child,
          ),
        ),
        if (tail == CloudTail.below) puffs,
      ],
    );
  }

  // The puffs shrink away from the bubble; above the bubble that means
  // mirroring them vertically.
  Widget _flip(Widget puffs) => Transform(
    alignment: Alignment.center,
    transform: Matrix4.rotationX(3.14159),
    child: puffs,
  );
}

/// Which side of a [CloudBubble] the trailing puffs sit on.
enum CloudTail { none, above, below }

/// Three shrinking puffs that lead the eye from the bubble to its target.
class _Puffs extends StatelessWidget {
  const _Puffs({required this.alignX});

  final double alignX;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment(alignX, 0),
    child: Padding(
      padding: const EdgeInsets.only(top: 6, left: 22, right: 22),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Each puff carries its own soft white glow, so the trail fades out
          // the way the cloud's edge does instead of ending in hard dots.
          for (final (d, a) in const [
            (12.0, 0.95),
            (7.5, 0.75),
            (4.0, 0.5),
          ]) ...[
            Container(
              width: d,
              height: d,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFF4F8FF).withValues(alpha: a),
                boxShadow: [
                  BoxShadow(
                    color: Colors.white.withValues(alpha: a * 0.55),
                    blurRadius: d * 0.9,
                    spreadRadius: d * 0.15,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 5),
          ],
        ],
      ),
    ),
  );
}

class _CloudPainter extends CustomPainter {
  const _CloudPainter({required this.lobeBand});

  final double lobeBand;

  // The silhouette costs nine boolean path unions to build, and it was rebuilt
  // on every paint — which, while a drawer slides, means every frame. The shape
  // depends only on (size, lobeBand), and exactly one bubble is ever on screen,
  // so a single-entry cache removes that work entirely.
  static Size? _cachedSize;
  static double? _cachedBand;
  static Path? _cachedPath;

  Path _cloudCached(Size size) {
    final hit = _cachedPath;
    if (hit != null && _cachedSize == size && _cachedBand == lobeBand) {
      return hit;
    }
    final built = _cloud(size);
    _cachedSize = size;
    _cachedBand = lobeBand;
    _cachedPath = built;
    return built;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final path = _cloudCached(size);

    // The cottony look is three passes, not one shape. Painting the fill alone
    // gives a crisp cut-out that reads as a sticker; the blurred passes are
    // what make the edge look like vapour.

    // 1. Ground shadow — lets the cloud float instead of lying flat.
    canvas.drawPath(
      path.shift(const Offset(0, 7)),
      Paint()
        ..color = const Color(0x26000000)
        ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 16),
    );

    // 2. Two haloes of decreasing spread. Because they are drawn UNDER the
    // fill and bleed past the outline, the silhouette dissolves outward — the
    // fluff. Wide-then-tight beats a single blur, which just looks out of focus.
    for (final (blur, alpha) in const [(22.0, 0.34), (10.0, 0.55)]) {
      canvas.drawPath(
        path,
        Paint()
          ..color = Colors.white.withValues(alpha: alpha)
          ..maskFilter = ui.MaskFilter.blur(ui.BlurStyle.normal, blur),
      );
    }

    // 3. The body itself, kept very pale so the haloes blend into it instead
    // of stopping at a visible border. No stroke on purpose: any rim, however
    // faint, brings the sticker look straight back.
    canvas.drawPath(
      path,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFFFFFF), Color(0xFFF2F6FF), Color(0xFFE7EEFF)],
          stops: [0.0, 0.55, 1.0],
        ).createShader(Offset.zero & size),
    );

    // 4. A soft light pooling in the upper lobes, so the cloud has a volume
    // rather than being a flat gradient.
    canvas.drawPath(
      path,
      Paint()
        ..blendMode = BlendMode.plus
        ..shader = ui.Gradient.radial(
          Offset(size.width * 0.42, lobeBand * 0.7),
          size.width * 0.55,
          [const Color(0x1AFFFFFF), const Color(0x00FFFFFF)],
        ),
    );
  }

  /// Rounded body ∪ lobes all around it, unioned into a single outline.
  ///
  /// The lobes are deliberately uneven — different radii, off-centre spacing,
  /// smaller ones tucked at the bottom and sides. Evenly spaced identical
  /// circles read as a machine-drawn scallop; real cumulus never repeats.
  Path _cloud(Size size) {
    final w = size.width;
    final h = size.height;
    final r = lobeBand;
    var path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(r * 0.30, r * 0.58, w - r * 0.30, h - r * 0.34),
          Radius.circular(r * 0.9),
        ),
      );

    // (fraction of width, fraction of height, radius as a fraction of the band)
    const lobes = <(double, double, double)>[
      // crown
      (0.20, 0.0, 0.78),
      (0.40, 0.0, 1.02),
      (0.62, 0.0, 0.86),
      (0.82, 0.0, 0.62),
      // shoulders
      (0.06, 0.34, 0.52),
      (0.95, 0.42, 0.46),
      // underside — small, so the bottom stays calm enough to read text over
      (0.28, 1.0, 0.40),
      (0.58, 1.0, 0.34),
      (0.80, 1.0, 0.28),
    ];

    for (final (fx, fy, fr) in lobes) {
      // fy is expressed against the band at the top and the body's bottom edge,
      // so a lobe never drifts into the text area.
      final cy = fy == 0.0 ? r : (fy == 1.0 ? h - r * 0.34 : r + (h - r) * fy);
      path = Path.combine(
        PathOperation.union,
        path,
        Path()..addOval(
          Rect.fromCircle(center: Offset(w * fx, cy), radius: r * fr),
        ),
      );
    }
    return path;
  }

  @override
  bool shouldRepaint(_CloudPainter old) => old.lobeBand != lobeBand;
}
