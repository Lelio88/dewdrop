import 'dart:async';
import 'dart:math' as math;

import 'package:dewdrop/src/features/tour/domain/tour_step.dart';
import 'package:dewdrop/src/features/tour/presentation/cloud_bubble.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The home tour: a dimmed screen with a hole punched over the element being
/// explained, and a cloud bubble ([CloudBubble]) that DRIFTS from one step's
/// position to the next. Steps come from [kHomeTour]; a tap anywhere advances,
/// "Passer" ends it.
///
/// Three things drive the design:
///
/// **The tour owns the screen while it runs.** The overlay is `opaque`, so
/// nothing reaches the screen underneath, and it offers exactly three moves:
/// perform the gesture the step asks for, tap to move on, or "Passer".
///
/// This is the whole reason the tour can describe anything at all. A bubble
/// talks *about* the screen; letting the user change that screen mid-sentence
/// means the words and the pixels drift apart, and every trick to re-sync them
/// afterwards (following a drawer that opened one step too early, guessing
/// which anchor is current) is a patch over a hole that should not exist.
///
/// A drag is recognised HERE, not below: matching the step's [TourStep.gesture]
/// forwards it to [onPerform], which is what actually moves the drawer — so the
/// user really performs the gesture, and the tour still knows exactly what the
/// screen is doing. A different gesture is refused with a nudge, never in
/// silence: nothing-happens reads as a frozen app.
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
    this.onPerform,
    this.onScene,
  });

  /// Keys of the real widgets each [TourAnchor] designates. Anchors absent from
  /// the map simply get no spotlight.
  final Map<TourAnchor, GlobalKey> anchors;

  /// Called once, when the tour is finished or skipped.
  final VoidCallback onFinish;

  final List<TourStep> steps;

  /// Carries out the gesture the user just performed, when it is the one this
  /// step asked for. The tour recognises it, the host applies it — the drawer
  /// opens for real, and the tour knows precisely when.
  final ValueChanged<TourGesture>? onPerform;

  /// The scene each step wants on screen, fired on entering it (including the
  /// first). The home puts its drawers in that state, so a step explaining the
  /// full-screen drawer is read WITH the drawer full-screen — whether the user
  /// got there by swiping or by tapping "Suivant".
  final ValueChanged<TourScene>? onScene;

  @override
  State<CloudTour> createState() => _CloudTourState();
}

class _CloudTourState extends State<CloudTour>
    with SingleTickerProviderStateMixin {
  static const _kGap = 14.0;

  /// How far the puffs can meaningfully bridge, in logical pixels.
  static const _kTailReach = 90.0;
  static const _kEstimatedBubbleHeight = 190.0;

  /// Below this, a drag is a slip of the thumb rather than a swipe. Same
  /// threshold the home uses, so what counts as a gesture doesn't change
  /// depending on whether the tour is up.
  static const _kFlingVelocity = 250.0;

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

  /// Anchor adopted early, the moment the step's gesture lands — before the
  /// step itself changes.
  ///
  /// Without it, the cloud freezes while the drawer travels: the step still
  /// points at a handle, and the handle is unmounted for as long as a drawer is
  /// open, so there is nothing to follow. Borrowing the NEXT step's anchor (the
  /// drawer) makes the cloud ride the panel — up from the bottom, or down from
  /// the top — instead of sitting still while it passes underneath.
  TourAnchor? _previewAnchor;

  /// True once the bubble should stick to its target frame-for-frame.
  ///
  /// A moving target and an implicit animation don't compose: the panel slides
  /// (~340 ms) AND the bubble eases toward it (~400 ms), which reads as lag.
  /// So each jump to a NEW anchor is animated, then the bubble snaps to the
  /// target for the rest of that anchor's life.
  bool _follow = false;
  Timer? _followTimer;

  /// The anchor actually being tracked right now.
  TourAnchor get _activeAnchor => _previewAnchor ?? widget.steps[_index].anchor;

  /// Ease into the new anchor, then track it exactly. The `setState` matters:
  /// flipping the flag after the caller's own rebuild would let that frame
  /// paint in follow mode and snap the very move meant to be animated.
  void _animateThenFollow() {
    _followTimer?.cancel();
    if (mounted) {
      setState(() => _follow = false);
    } else {
      _follow = false;
    }
    _followTimer = Timer(const Duration(milliseconds: 420), () {
      if (mounted) setState(() => _follow = true);
    });
  }

  /// Drives the refusal nudge (see [_refuse]).
  late final AnimationController _nudge = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.onScene?.call(widget.steps[_index].scene);
      setState(() {
        _visible = true;
        _target = _resolve(widget.steps[_index].anchor);
      });
      _animateThenFollow();
    });
  }

  @override
  void dispose() {
    _advanceTimer?.cancel();
    _followTimer?.cancel();
    _nudge.dispose();
    super.dispose();
  }

  void _onVerticalDrag(DragEndDetails d) {
    final v = d.primaryVelocity ?? 0;
    if (v.abs() < _kFlingVelocity) return;
    _handle(v < 0 ? TourGesture.swipeUp : TourGesture.swipeDown);
  }

  void _onHorizontalDrag(DragEndDetails d) {
    final v = d.primaryVelocity ?? 0;
    if (v.abs() < _kFlingVelocity) return;
    _handle(TourGesture.swipeSide);
  }

  /// A swipe happened. Either it is the one this step teaches — carry it out
  /// for real, then move on after a beat — or it isn't, and the cloud says no.
  void _handle(TourGesture done) {
    if (_advanceTimer != null) return; // already on the way out
    final wanted = widget.steps[_index].gesture;
    if (wanted == null) return; // this step teaches no gesture: ignore quietly
    if (done != wanted) {
      _refuse();
      return;
    }

    // Hand the cloud over to whatever the gesture is opening, NOW — the step's
    // own anchor (a handle) is about to be unmounted by that very drawer.
    final next = _index + 1;
    if (next < widget.steps.length) {
      final ahead = widget.steps[next].anchor;
      if (ahead != TourAnchor.none && ahead != widget.steps[_index].anchor) {
        setState(() => _previewAnchor = ahead);
        _animateThenFollow();
      }
    }

    widget.onPerform?.call(done);
    _advanceTimer = Timer(_kGestureBeat, () {
      _advanceTimer = null;
      if (mounted) _next();
    });
  }

  /// Refuse a gesture the step didn't ask for, visibly. A swipe that changes
  /// nothing and says nothing reads as a frozen screen, so the cloud shivers:
  /// "not that one, the one I'm pointing at".
  void _refuse() {
    HapticFeedback.selectionClick();
    _nudge.forward(from: 0);
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
    final borrowed = _previewAnchor;
    setState(() {
      _index = next;
      _previewAnchor = null;
      // Keep the previous spotlight rather than snapping to centre while the
      // new target is still animating in — unless the step wants none.
      _target = step.anchor == TourAnchor.none
          ? null
          : (_resolve(step.anchor) ?? _target);
    });
    // Only re-animate when the anchor actually changes. Arriving on a step
    // whose anchor the cloud already borrowed (it rode the drawer here) must
    // not re-trigger an ease — it is already exactly where it belongs.
    if (borrowed != step.anchor) _animateThenFollow();
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
    final anchor = _activeAnchor;
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
    switch (widget.steps[_index].placement) {
      case TourPlacement.screenTop:
        wanted = minTop;
      case TourPlacement.screenBottom:
        wanted = maxTop;
      case TourPlacement.auto:
        if (target == null) {
          wanted = (screen.height - _bubbleHeight) / 2;
        } else if (target.center.dy < screen.height * 0.45) {
          wanted = target.bottom + _kGap;
        } else {
          wanted = target.top - _kGap - _bubbleHeight;
        }
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
    final bubbleTop = _bubbleTop(size, target, safe);
    // Which way the puffs point: derived from where the bubble ENDED UP, not
    // from the rule that would have placed it — a step may override that.
    final bubbleAboveTarget =
        target != null && bubbleTop + _bubbleHeight <= target.center.dy;
    // The puffs are a LINK between the bubble and what it talks about: three
    // shrinking dots that carry the eye across a short gap. Past that, they
    // carry it nowhere — they stop a few pixels out and read as crumbs floating
    // beside the cloud, which is exactly how a forced placement leaves things
    // (bubble pinned to one edge, target at the other). Beyond the reach, drop
    // them: the spotlight already says where to look.
    final tailGap = target == null
        ? double.infinity
        : (bubbleAboveTarget
              ? target.top - (bubbleTop + _bubbleHeight)
              : bubbleTop - target.bottom);
    final tail = target == null || tailGap > _kTailReach || tailGap < 0
        ? CloudTail.none
        : (bubbleAboveTarget ? CloudTail.below : CloudTail.above);
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
                // OPAQUE: while the tour is up, it owns the screen. The three
                // ways forward are the step's gesture, a tap, and "Passer".
                behavior: HitTestBehavior.opaque,
                onTap: _next,
                onVerticalDragEnd: _onVerticalDrag,
                onHorizontalDragEnd: _onHorizontalDrag,
                child: TweenAnimationBuilder<Rect?>(
                  tween: RectTween(end: hole),
                  // Same reasoning as the bubble: the spotlight must sit ON the
                  // moving panel, not trail it.
                  duration: _follow
                      ? Duration.zero
                      : const Duration(milliseconds: 280),
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
              top: bubbleTop,
              // Zero once locked on: a drawer in motion moves its rectangle
              // every frame, and easing toward a target that is itself easing
              // reads as the cloud dragging behind. Ease only when switching to
              // a NEW anchor; after that, follow exactly.
              duration: _follow
                  ? Duration.zero
                  : const Duration(milliseconds: 400),
              curve: Curves.easeOutCubic,
              child: _Shiver(
                animation: _nudge,
                child: CloudBubble(
                  key: _bubbleKey,
                  tail: tail,
                  tailAlignX: target == null
                      ? 0
                      : ((target.center.dx - size.width / 2) /
                                (bubbleWidth / 2))
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
            ),

            if (!isLast)
              Positioned(
                top: 0,
                right: 0,
                child: SafeArea(
                  // The tour now holds every other gesture, so this is the only
                  // way out — it has to look like one, not like fine print.
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: GestureDetector(
                      onTap: widget.onFinish,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(99),
                          color: Colors.black.withValues(alpha: 0.35),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.28),
                          ),
                        ),
                        child: Text(
                          'Passer le tuto',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.9),
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
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

/// Sways its child from side to side, once, whenever [animation] runs.
///
/// A damped sine rather than a two-step jerk: this is a cloud saying "not that
/// gesture", not an error dialog. The amplitude decays over the run, so it
/// settles rather than stopping dead.
class _Shiver extends StatelessWidget {
  const _Shiver({required this.animation, required this.child});

  final Animation<double> animation;
  final Widget child;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: animation,
    builder: (_, inner) {
      final t = animation.value;
      if (t == 0 || t == 1) return inner!;
      final dx = math.sin(t * math.pi * 3) * 12 * (1 - t);
      return Transform.translate(offset: Offset(dx, 0), child: inner);
    },
    child: child,
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
