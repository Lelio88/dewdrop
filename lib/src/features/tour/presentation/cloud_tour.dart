import 'dart:async';
import 'dart:math' as math;

import 'package:dewdrop/src/features/tour/domain/tour_step.dart';
import 'package:dewdrop/src/features/tour/presentation/cloud_bubble.dart';
import 'package:flutter/material.dart';

/// The home tour: a dimmed screen with a hole punched over the element being
/// explained, and a cloud bubble ([CloudBubble]) that DRIFTS from one step's
/// position to the next. Steps come from [kHomeTour]; a tap anywhere advances,
/// "Passer" ends it.
///
/// Three things drive the design:
///
/// **Gestures stay live.** The overlay is `translucent`, not `opaque`: it claims
/// taps (to advance) but lets drags fall through to the real home underneath.
/// A step that names a gesture ([TourStep.gesture]) completes itself once the
/// user performs it — reading "glisse vers le haut" teaches far less than doing
/// it once. [gestures] is how the home reports what the finger did.
///
/// **The bubble travels.** Position is always expressed as a single `top`
/// (never `top` for one step and `bottom` for the next — you cannot interpolate
/// between those), so [AnimatedPositioned] can slide it. That needs the
/// bubble's height, which is only known after layout: [_bubbleHeight] is
/// measured post-frame and starts from an estimate.
///
/// **Anchors resolve post-frame.** The tour is a sibling of the widgets it
/// points at, inside the same [Stack]; during the first build they have no
/// layout yet and `localToGlobal` cannot be called. The first frame paints with
/// no hole (invisible — the overlay fades in over ~450 ms) and the rectangle
/// lands on the next frame. A missing or unmounted key degrades to "no
/// spotlight, bubble centred" instead of throwing.
class CloudTour extends StatefulWidget {
  const CloudTour({
    super.key,
    required this.anchors,
    required this.onFinish,
    this.steps = kHomeTour,
    this.gestures,
    this.onScene,
  });

  /// Keys of the real widgets each [TourAnchor] designates. Anchors absent from
  /// the map simply get no spotlight.
  final Map<TourAnchor, GlobalKey> anchors;

  /// Called once, when the tour is finished or skipped.
  final VoidCallback onFinish;

  final List<TourStep> steps;

  /// The last gesture the user performed on the home screen. The tour consumes
  /// it (sets it back to null) once acted upon, so the same gesture can satisfy
  /// a later step too.
  final ValueNotifier<TourGesture?>? gestures;

  /// The scene each step wants on screen, fired on entering it (including the
  /// first). The home puts its drawers in that state, so a step explaining the
  /// full-screen drawer is read WITH the drawer full-screen — whether the user
  /// got there by swiping or by tapping "Suivant".
  final ValueChanged<TourScene>? onScene;

  @override
  State<CloudTour> createState() => _CloudTourState();
}

class _CloudTourState extends State<CloudTour> {
  static const _kGap = 14.0;
  static const _kEstimatedBubbleHeight = 190.0;

  /// How long a finished gesture stays on screen before the tour moves on.
  /// Longer than it looks on paper: the drawer's own slide takes ~340 ms, and
  /// cutting in right after it lands reads as being rushed. The next bubble
  /// comments on what just opened, so the hand-off is a continuation, not a
  /// jump-cut.
  static const _kGestureBeat = Duration(milliseconds: 1600);

  int _index = 0;
  Rect? _target;
  bool _visible = false;
  double _bubbleHeight = _kEstimatedBubbleHeight;
  Timer? _advanceTimer;
  final _bubbleKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    widget.gestures?.addListener(_onGesture);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.onScene?.call(widget.steps[_index].scene);
      setState(() {
        _visible = true;
        _target = _resolve(widget.steps[_index].anchor);
      });
    });
  }

  @override
  void didUpdateWidget(CloudTour old) {
    super.didUpdateWidget(old);
    if (old.gestures != widget.gestures) {
      old.gestures?.removeListener(_onGesture);
      widget.gestures?.addListener(_onGesture);
    }
  }

  @override
  void dispose() {
    _advanceTimer?.cancel();
    widget.gestures?.removeListener(_onGesture);
    super.dispose();
  }

  /// The user did something on the home screen. If it's what this step asked
  /// for, let them watch the result, then move on.
  void _onGesture() {
    final done = widget.gestures?.value;
    if (done == null || _advanceTimer != null) return;
    if (done != widget.steps[_index].gesture) return;
    widget.gestures?.value = null; // consumed
    _advanceTimer = Timer(_kGestureBeat, () {
      _advanceTimer = null;
      if (mounted) _next();
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
    _advanceTimer?.cancel();
    _advanceTimer = null;
    if (_index >= widget.steps.length - 1) {
      widget.onFinish();
      return;
    }
    final next = _index + 1;
    final step = widget.steps[next];
    // Ask for the scene BEFORE resolving: the new anchor is often a widget the
    // scene change is about to mount (or unmount). Whatever isn't resolvable on
    // this frame is picked up by [_syncTarget] on the next ones.
    widget.onScene?.call(step.scene);
    setState(() {
      _index = next;
      // Keep the previous spotlight rather than snapping to centre while the
      // new target is still animating in — unless the step wants none.
      _target = step.anchor == TourAnchor.none
          ? null
          : (_resolve(step.anchor) ?? _target);
    });
  }

  /// Re-reads the current step's anchor every frame.
  ///
  /// This is what makes the bubble RIDE the drawer: as the panel slides up, its
  /// rectangle changes each frame, the spotlight follows, and the cloud drifts
  /// along instead of sitting on top of what just opened. It also fixes an
  /// anchor that wasn't mounted yet when the step began — the case that left
  /// the "glisse vers le bas" step with no spotlight at all, because the
  /// previous drawer was still open (and the handles unmounted) at that instant.
  ///
  /// A null result is IGNORED rather than applied: an anchor that momentarily
  /// disappears should freeze the spotlight, not fling the cloud to the centre.
  void _syncTarget() {
    final anchor = widget.steps[_index].anchor;
    if (anchor == TourAnchor.none) {
      if (_target != null) setState(() => _target = null);
      return;
    }
    final next = _resolve(anchor);
    if (next == null) return;
    final current = _target;
    if (current != null &&
        (current.center - next.center).distance < 1 &&
        (current.size.width - next.size.width).abs() < 1 &&
        (current.size.height - next.size.height).abs() < 1) {
      return; // settled — stop rebuilding
    }
    setState(() => _target = next);
  }

  /// Bubbles are sized by their text, so the height needed to place one above a
  /// target is only knowable after it has been laid out. Re-measured every
  /// frame; the guard keeps it from looping on itself.
  void _measureBubble() {
    final box = _bubbleKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    if ((box.size.height - _bubbleHeight).abs() < 0.5) return;
    setState(() => _bubbleHeight = box.size.height);
  }

  /// Where the bubble's top edge goes: below the target when it sits high on
  /// screen, above it otherwise, centred when the step has no target. Always a
  /// `top`, never a `bottom` — that is what makes the move interpolable.
  double _bubbleTop(Size screen, Rect? target, EdgeInsets safe) {
    final minTop = safe.top + 8;
    final maxTop = screen.height - safe.bottom - _bubbleHeight - 8;
    final double wanted;
    if (target == null) {
      wanted = (screen.height - _bubbleHeight) / 2;
    } else if (target.center.dy < screen.height * 0.45) {
      wanted = target.bottom + _kGap;
    } else {
      wanted = target.top - _kGap - _bubbleHeight;
    }
    // maxTop can fall below minTop on a very short screen; clamp needs order.
    return maxTop <= minTop ? minTop : wanted.clamp(minTop, maxTop);
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _measureBubble();
      _syncTarget();
    });

    final step = widget.steps[_index];
    final size = MediaQuery.sizeOf(context);
    final safe = MediaQuery.paddingOf(context);
    final target = _target;
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
            // Dim + spotlight, and the tap surface that advances the tour.
            // TRANSLUCENT, not opaque: taps are claimed here, drags fall
            // through to the home's own gesture detector so the user can
            // actually perform the swipe the step is describing.
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: _next,
                child: TweenAnimationBuilder<Rect?>(
                  tween: RectTween(end: hole),
                  duration: const Duration(milliseconds: 280),
                  curve: Curves.easeOutCubic,
                  builder: (_, animated, _) => CustomPaint(
                    painter: _SpotlightPainter(hole: animated),
                    size: Size.infinite,
                  ),
                ),
              ),
            ),

            // The cloud drifts to its new spot rather than reappearing there.
            AnimatedPositioned(
              left: (size.width - bubbleWidth) / 2,
              width: bubbleWidth,
              top: _bubbleTop(size, target, safe),
              // Close to the drawer's own 340 ms slide: long enough to read as
              // a drift between steps, short enough that the cloud rides the
              // panel up instead of lagging behind it.
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeOutCubic,
              child: CloudBubble(
                key: _bubbleKey,
                tail: target == null
                    ? CloudTail.none
                    : (below ? CloudTail.above : CloudTail.below),
                tailAlignX: target == null
                    ? 0
                    : ((target.center.dx - size.width / 2) / (bubbleWidth / 2))
                          .clamp(-0.75, 0.75),
                child: AnimatedSize(
                  duration: const Duration(milliseconds: 320),
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.topCenter,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: KeyedSubtree(
                      key: ValueKey(_index),
                      child: _bubbleContent(step, isLast),
                    ),
                  ),
                ),
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
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOutCubic,
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

  /// Opt OUT of hit testing. `RenderCustomPaint.hitTestSelf` is
  /// `painter.hitTest(position) ?? true` — a CustomPaint carrying a `painter`
  /// swallows pointers by default, which would make the dimming layer eat every
  /// swipe no matter how translucent its GestureDetector is. Returning false
  /// is what lets the user actually perform the gesture the step describes.
  @override
  bool? hitTest(Offset position) => false;

  @override
  bool shouldRepaint(_SpotlightPainter old) => old.hole != hole;
}
