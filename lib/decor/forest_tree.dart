import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Recursive branching parameters that give a tree species its silhouette.
class TreeStyle {
  const TreeStyle({
    required this.depth,
    required this.branches,
    required this.spread,
    required this.jitter,
    required this.lenDecay,
    required this.widthDecay,
    required this.initialLen,
    required this.initialWidth,
    required this.clusterScale,
    required this.clusterDepth,
    required this.trunkColor,
    required this.foliage,
  });

  final int depth; // recursion levels
  final int branches; // children per node
  final double spread; // angle between children (rad)
  final double jitter; // random angle noise (rad)
  final double lenDecay; // child length factor
  final double widthDecay; // child width factor
  final double initialLen; // trunk length (unit space)
  final double initialWidth; // trunk width (unit space)
  final double clusterScale; // foliage size vs branch length
  final int clusterDepth; // add foliage when remaining depth <= this
  final Color trunkColor;
  final List<Color> foliage;
}

class _Seg {
  const _Seg(this.a, this.b, this.width);
  final Offset a;
  final Offset b;
  final double width;
}

class _Clu {
  const _Clu(this.c, this.r, this.shade);
  final Offset c;
  final double r;
  final int shade;
}

/// A pre-built tree in unit space: base at the origin, growing up (-y).
class TreeShape {
  TreeShape(this._segments, this._clusters, this.height);
  final List<_Seg> _segments;
  final List<_Clu> _clusters;
  final double height; // topmost extent (for scaling)
}

/// Builds one tree silhouette from [style], seeded by [rng].
TreeShape buildTree(math.Random rng, TreeStyle style) {
  final segs = <_Seg>[];
  final clus = <_Clu>[];
  var maxUp = 0.0;

  void grow(Offset start, double angle, double len, double width, int d) {
    final end = start + Offset(math.sin(angle), -math.cos(angle)) * len;
    segs.add(_Seg(start, end, width));
    if (-end.dy > maxUp) maxUp = -end.dy;
    if (d <= style.clusterDepth) {
      clus.add(
        _Clu(end, len * style.clusterScale, rng.nextInt(style.foliage.length)),
      );
    }
    if (d <= 0) return;
    for (var i = 0; i < style.branches; i++) {
      final base = (i - (style.branches - 1) / 2) * style.spread;
      final jit = (rng.nextDouble() - 0.5) * style.jitter;
      grow(
        end,
        angle + base + jit,
        len * style.lenDecay,
        width * style.widthDecay,
        d - 1,
      );
    }
  }

  grow(
    Offset.zero,
    (rng.nextDouble() - 0.5) * 0.1,
    style.initialLen,
    style.initialWidth,
    style.depth,
  );
  return TreeShape(segs, clus, maxUp <= 0 ? 1 : maxUp);
}

/// Draws [shape] with its base at [base] (px), sized to [height] px.
/// [haze] (0..1) blends colours toward [hazeColor] for atmospheric distance.
/// [sway] (px) bends the crown horizontally (more at the top).
void drawTree(
  Canvas canvas,
  TreeShape shape, {
  required Offset base,
  required double height,
  required bool flip,
  required double sway,
  required TreeStyle style,
  required double haze,
  required Color hazeColor,
}) {
  final k = height / shape.height;
  Offset tp(Offset p) {
    final fx = (flip ? -p.dx : p.dx) * k;
    final up = (-p.dy) / shape.height; // 0 at base, 1 at top
    return Offset(base.dx + fx + sway * up, base.dy + p.dy * k);
  }

  final trunk = Color.lerp(style.trunkColor, hazeColor, haze)!;
  final branchPaint = Paint()
    ..color = trunk
    ..strokeCap = StrokeCap.round
    ..style = PaintingStyle.stroke;
  for (final s in shape._segments) {
    branchPaint.strokeWidth = (s.width * k).clamp(1.0, 60.0);
    canvas.drawLine(tp(s.a), tp(s.b), branchPaint);
  }

  for (final c in shape._clusters) {
    final center = tp(c.c);
    final r = (c.r * k).clamp(3.0, 400.0);
    final base0 = Color.lerp(style.foliage[c.shade], hazeColor, haze * 0.85)!;
    canvas.drawCircle(
      center,
      r,
      Paint()..color = base0.withValues(alpha: 0.96),
    );
    // soft top-left highlight for volume
    canvas.drawCircle(
      center.translate(-r * 0.28, -r * 0.28),
      r * 0.55,
      Paint()
        ..color = Color.lerp(
          base0,
          Colors.white,
          0.16,
        )!.withValues(alpha: 0.5 * (1 - haze)),
    );
  }
}
