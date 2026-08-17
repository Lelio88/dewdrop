import 'dart:math' as math;

import 'package:dewdrop/src/features/tour/domain/tour_step.dart';
import 'package:dewdrop/src/features/tour/presentation/cloud_bubble.dart';
import 'package:flutter/material.dart';

/// The home tour: a dimmed screen with a hole punched over the element being
/// explained, and a cloud bubble ([CloudBubble]) next to it. Steps come from
/// [kHomeTour]; a tap anywhere advances, "Passer" ends it.
///
/// Anchoring, and why it is resolved in a post-frame callback: the tour is a
/// sibling of the widgets it points at, inside the same [Stack]. During the
/// first build those siblings have no layout yet, so `localToGlobal` cannot be
/// called on them. The first frame therefore paints with no hole (invisible —
/// the whole overlay fades in over ~450 ms) and the real rectangle lands on the
/// frame after. From step two onward everything is laid out, so each rectangle
/// is resolved synchronously as the step changes.
///
/// A missing or unmounted key degrades to "no spotlight, bubble centred"
/// instead of throwing — a step whose target got hidden still reads fine.
class CloudTour extends StatefulWidget {
  const CloudTour({
    super.key,
    required this.anchors,
    required this.onFinish,
    this.steps = kHomeTour,
  });

  /// Keys of the real widgets each [TourAnchor] designates. Anchors absent from
  /// the map simply get no spotlight.
  final Map<TourAnchor, GlobalKey> anchors;

  /// Called once, when the tour is finished or skipped.
  final VoidCallback onFinish;

  final List<TourStep> steps;

  @override
  State<CloudTour> createState() => _CloudTourState();
}

class _CloudTourState extends State<CloudTour> {
  int _index = 0;
  Rect? _target;
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _visible = true;
        _target = _resolve(widget.steps[_index].anchor);
      });
    });
  }

  /// The on-screen rectangle of [anchor]'s widget, or null when it has no key,
  /// isn't mounted, or hasn't been laid out.
  Rect? _resolve(TourAnchor anchor) {
    if (anchor == TourAnchor.none) return null;
    final context = widget.anchors[anchor]?.currentContext;
    if (context == null) return null;
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  void _next() {
    final last = _index >= widget.steps.length - 1;
    if (last) {
      widget.onFinish();
      return;
    }
    final next = _index + 1;
    setState(() {
      _index = next;
      _target = _resolve(widget.steps[next].anchor);
    });
  }

  @override
  Widget build(BuildContext context) {
    final step = widget.steps[_index];
    final size = MediaQuery.sizeOf(context);
    final target = _target;
    // Below the target when it sits in the upper part of the screen, above it
    // otherwise — the bubble always grows toward the free space.
    final below = target != null && target.center.dy < size.height * 0.45;
    final bubbleWidth = math.min(360.0, size.width - 40);
    final isLast = _index >= widget.steps.length - 1;
    // RectTween needs a non-null end. A zero-size rect at the centre stands in
    // for "this step has no target": the painter skips empty rectangles, so it
    // reads as the spotlight closing inward rather than blinking out.
    final hole =
        target ??
        Rect.fromCenter(
          center: Offset(size.width / 2, size.height / 2),
          width: 0,
          height: 0,
        );

    return AnimatedOpacity(
      opacity: _visible ? 1 : 0,
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOut,
      child: Material(
        type: MaterialType.transparency,
        child: Stack(
          children: [
            // Dim + spotlight. Also the tap surface that advances the tour.
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _next,
                child: TweenAnimationBuilder<Rect?>(
                  tween: RectTween(end: hole),
                  duration: const Duration(milliseconds: 320),
                  curve: Curves.easeOutCubic,
                  builder: (_, hole, _) => CustomPaint(
                    painter: _SpotlightPainter(hole: hole),
                    size: Size.infinite,
                  ),
                ),
              ),
            ),

            _positionBubble(
              size: size,
              target: target,
              below: below,
              width: bubbleWidth,
              child: CloudBubble(
                tail: target == null
                    ? CloudTail.none
                    : (below ? CloudTail.above : CloudTail.below),
                tailAlignX: target == null
                    ? 0
                    : ((target.center.dx - size.width / 2) / (bubbleWidth / 2))
                          .clamp(-0.75, 0.75),
                child: _bubbleContent(step, isLast),
              ),
            ),

            if (!isLast)
              Positioned(
                top: 0,
                right: 0,
                child: SafeArea(
                  child: TextButton(
                    onPressed: widget.onFinish,
                    child: Text(
                      'Passer',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.75),
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Places the bubble under the target, over it, or dead centre when the step
  /// has none. `AnimatedSwitcher` cross-fades the text between steps so the
  /// cloud never blinks.
  Widget _positionBubble({
    required Size size,
    required Rect? target,
    required bool below,
    required double width,
    required Widget child,
  }) {
    final animated = AnimatedSwitcher(
      duration: const Duration(milliseconds: 260),
      child: KeyedSubtree(key: ValueKey(_index), child: child),
    );
    if (target == null) {
      return Positioned.fill(
        child: Center(child: SizedBox(width: width, child: animated)),
      );
    }
    const gap = 12.0;
    return Positioned(
      left: (size.width - width) / 2,
      width: width,
      top: below ? target.bottom + gap : null,
      bottom: below ? null : size.height - target.top + gap,
      child: animated,
    );
  }

  Widget _bubbleContent(TourStep step, bool isLast) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        step.title,
        style: const TextStyle(
          color: Color(0xFF1B2340),
          fontSize: 17,
          fontWeight: FontWeight.w700,
          height: 1.2,
        ),
      ),
      const SizedBox(height: 7),
      Text(
        step.body,
        style: const TextStyle(
          color: Color(0xFF4A5578),
          fontSize: 14,
          height: 1.45,
        ),
      ),
      const SizedBox(height: 16),
      Row(
        children: [
          for (var i = 0; i < widget.steps.length; i++)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Container(
                width: i == _index ? 18 : 6,
                height: 6,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(3),
                  color: i == _index
                      ? const Color(0xFF7E9BE0)
                      : const Color(0xFFC6D2EC),
                ),
              ),
            ),
          const Spacer(),
          TextButton(
            onPressed: _next,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              isLast ? 'C’est parti' : 'Suivant',
              style: const TextStyle(
                color: Color(0xFF3A63C0),
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    ],
  );
}

/// Dims everything, then erases a soft-edged rounded hole over the target so
/// the real element stays readable underneath. The erase is a `dstOut` draw
/// inside a `saveLayer` — without the layer it would punch through to whatever
/// was painted before the overlay.
class _SpotlightPainter extends CustomPainter {
  const _SpotlightPainter({required this.hole});

  final Rect? hole;

  @override
  void paint(Canvas canvas, Size size) {
    final full = Offset.zero & size;
    canvas.saveLayer(full, Paint());
    canvas.drawRect(full, Paint()..color = const Color(0x9E000000));
    final h = hole;
    if (h != null && !h.isEmpty) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(h.inflate(18), const Radius.circular(26)),
        Paint()
          ..blendMode = BlendMode.dstOut
          ..color = Colors.black
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14),
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_SpotlightPainter old) => old.hole != hole;
}
