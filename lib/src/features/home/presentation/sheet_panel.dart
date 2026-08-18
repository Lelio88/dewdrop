import 'dart:ui';

import 'package:flutter/material.dart';

/// Glass panel hosting a gesture sheet's content. [top] flips the rounded
/// corners + safe-area inset so the same panel works sliding from the top
/// (pensées reçues) or the bottom (envoyer).
///
/// Two stages: at peek [height] is null and the panel hugs its content (with a
/// thin grabber at the free edge). At full [height] is set and the panel grows
/// to it and the child fills the WHOLE panel (bounded height, so its own
/// scrollable list stretches full-page). The half against the free edge (top for
/// the bottom "envoyer" sheet, bottom for the top "reçus" sheet) is overlaid by a
/// TRANSLUCENT, drag-only collapse zone: a swipe there falls back to peek (via
/// [onGrabDrag]) while taps fall THROUGH it (so the send dock's avatars stay
/// tappable across that half) and the opposite half scrolls the list. A slim
/// chevron sits in a thin band at the very free edge to hint the gesture; the
/// child is inset by that band so the hint never covers the content. The
/// peek↔full height change is animated by [AnimatedSize] (which clips
/// mid-transition, so no overflow).
class SheetPanel extends StatelessWidget {
  const SheetPanel({
    super.key,
    required this.child,
    this.top = false,
    this.height,
    this.onGrabDrag,
    this.hintKey,
  });

  /// Tour anchor for the chevron band. The step about the full-screen drawer
  /// points HERE rather than at the whole panel: a panel filling 90% of the
  /// screen leaves the bubble nowhere to stand that isn't on top of the faces.
  final GlobalKey? hintKey;

  final Widget child;
  final bool top;
  final double? height;
  final GestureDragEndCallback? onGrabDrag;

  @override
  Widget build(BuildContext context) {
    final w = Colors.white;
    final media = MediaQuery.of(context);
    final inset = top ? media.viewPadding.top : media.viewPadding.bottom;
    final expanded = height != null;

    // The drag affordance (reused at peek and in the full-stage collapse zone).
    final grabberBar = Container(
      width: 44,
      height: 5,
      decoration: BoxDecoration(
        color: w.withValues(alpha: 0.30),
        borderRadius: BorderRadius.circular(3),
      ),
    );

    // Peek: a thin grabber at the free edge.
    final peekGrabber = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragEnd: onGrabDrag,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: grabberBar,
      ),
    );

    // Full: the child fills the WHOLE panel; the half against the FREE edge (top
    // for the bottom "envoyer" sheet, bottom for the top "reçus" sheet) is a
    // TRANSLUCENT, drag-only collapse zone — a swipe there falls back to peek
    // (via onGrabDrag) while taps fall through (the send dock's avatars stay
    // tappable there) and the opposite half scrolls the list. A slim chevron sits
    // in a thin band at the very free edge; the child is inset by that band so the
    // hint never covers the content.
    const hintBand = 34.0;

    // Points toward the free edge (up for the top "reçus" sheet, down for the
    // bottom "envoyer" sheet) — the direction of the collapsing swipe.
    final collapseHint = IgnorePointer(
      key: hintKey,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (top) ...[
              grabberBar,
              const SizedBox(height: 4),
              Icon(
                Icons.keyboard_arrow_up_rounded,
                size: 20,
                color: w.withValues(alpha: 0.5),
              ),
            ] else ...[
              Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 20,
                color: w.withValues(alpha: 0.5),
              ),
              const SizedBox(height: 4),
              grabberBar,
            ],
          ],
        ),
      ),
    );

    // Invisible gesture layer over the free-edge half; taps pass through it.
    final collapseZone = Align(
      alignment: top ? Alignment.bottomCenter : Alignment.topCenter,
      child: FractionallySizedBox(
        heightFactor: 0.5,
        widthFactor: 1,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onVerticalDragEnd: onGrabDrag,
          child: Align(
            alignment: top ? Alignment.bottomCenter : Alignment.topCenter,
            child: collapseHint,
          ),
        ),
      ),
    );

    final inner = expanded
        ? Stack(
            children: [
              // The list fills the whole panel, inset by the hint band at the
              // free edge so the chevron never overlaps it or its trailing button.
              Positioned.fill(
                child: Padding(
                  padding: EdgeInsets.only(
                    top: top ? 0 : hintBand,
                    bottom: top ? hintBand : 0,
                  ),
                  child: child,
                ),
              ),
              collapseZone,
            ],
          )
        : Column(
            mainAxisSize: MainAxisSize.min,
            children: [if (!top) peekGrabber, child, if (top) peekGrabber],
          );

    return ClipRRect(
      borderRadius: BorderRadius.vertical(
        top: top ? Radius.zero : const Radius.circular(26),
        bottom: top ? const Radius.circular(26) : Radius.zero,
      ),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: AnimatedSize(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
          alignment: top ? Alignment.topCenter : Alignment.bottomCenter,
          child: Container(
            width: double.infinity,
            padding: EdgeInsets.fromLTRB(
              20,
              top ? 8 + inset : 10,
              20,
              top ? 10 : 8 + inset,
            ),
            decoration: BoxDecoration(
              color: w.withValues(alpha: 0.10),
              border: Border.all(color: w.withValues(alpha: 0.16)),
            ),
            child: expanded ? SizedBox(height: height, child: inner) : inner,
          ),
        ),
      ),
    );
  }
}
