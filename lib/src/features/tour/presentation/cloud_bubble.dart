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
  Widget _flip(Widget puffs) =>
      Transform(alignment: Alignment.center, transform: Matrix4.rotationX(3.14159), child: puffs);
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
          for (final d in const [11.0, 7.0, 4.0]) ...[
            Container(
              width: d,
              height: d,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFFEFF4FF),
              ),
            ),
            const SizedBox(height: 4),
          ],
        ],
      ),
    ),
  );
}

class _CloudPainter extends CustomPainter {
  const _CloudPainter({required this.lobeBand});

  final double lobeBand;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final path = _cloud(size);

    // Soft ground shadow so the cloud floats over the decor rather than sitting
    // flat on it.
    canvas.drawPath(
      path.shift(const Offset(0, 6)),
      Paint()
        ..color = const Color(0x33000000)
        ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 14),
    );

    canvas.drawPath(
      path,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFBFCFF), Color(0xFFE6EDFF)],
        ).createShader(Offset.zero & size),
    );

    // Barely-there rim: keeps the silhouette readable on a bright decor.
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = const Color(0x22405080),
    );
  }

  /// Rounded body ∪ three lobes, unioned into a single outline.
  Path _cloud(Size size) {
    final body = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(0, lobeBand * 0.62, size.width, size.height),
          const Radius.circular(30),
        ),
      );
    // Lobe centres sit ON the band line, so each circle rises above it by its
    // radius minus the band — all three stay inside the canvas.
    const lobes = [(0.24, 0.85), (0.5, 1.0), (0.78, 0.72)];
    var path = body;
    for (final (fx, fr) in lobes) {
      path = Path.combine(
        PathOperation.union,
        path,
        Path()..addOval(
          Rect.fromCircle(
            center: Offset(size.width * fx, lobeBand),
            radius: lobeBand * fr,
          ),
        ),
      );
    }
    return path;
  }

  @override
  bool shouldRepaint(_CloudPainter old) => old.lobeBand != lobeBand;
}
