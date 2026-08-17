import 'package:dewdrop/src/features/tour/domain/tour_step.dart';
import 'package:flutter_test/flutter_test.dart';

/// The scripts are data, so their invariants can be asserted without a widget.
/// These guard the promises the tours make to the user — a step that asks for a
/// gesture the home doesn't report, or points at an anchor nobody wires up,
/// silently becomes a dead end.
void main() {
  test('every tour has a script', () {
    for (final id in TourId.values) {
      expect(stepsFor(id), isNotEmpty, reason: '${id.name} has no steps');
    }
  });

  test('the home tour stays short enough to be read', () {
    // Past ~8 bubbles at first launch, it stops being a tour and becomes a
    // manual. Anything extra belongs to a screen's own two bubbles.
    expect(kHomeTour.length, lessThanOrEqualTo(8));
  });

  test('per-screen tours are two bubbles, shown where they apply', () {
    for (final id in [TourId.friends, TourId.decors, TourId.settings]) {
      expect(stepsFor(id).length, lessThanOrEqualTo(2), reason: id.name);
    }
  });

  test('no step is left without a title or a body', () {
    for (final id in TourId.values) {
      for (final s in stepsFor(id)) {
        expect(s.title.trim(), isNotEmpty);
        expect(s.body.trim(), isNotEmpty);
      }
    }
  });

  test('every gesture the home can report is taught at least once', () {
    // "At least", not "exactly": swipeUp and swipeDown each appear twice on
    // purpose — once to open a drawer, once again for its second notch. That
    // repetition IS the lesson.
    final asked = {
      for (final s in kHomeTour)
        if (s.gesture != null) s.gesture!,
    };
    expect(asked, TourGesture.values.toSet());
  });

  test('a step that stages a drawer points at that drawer', () {
    // Otherwise the spotlight lands on a handle the scene just unmounted, and
    // the bubble covers what it is describing.
    const sheetAnchors = {TourAnchor.sendSheet, TourAnchor.receivedSheet};
    for (final s in kHomeTour) {
      if (s.scene == TourScene.closed) continue;
      expect(
        sheetAnchors,
        contains(s.anchor),
        reason: '"${s.title}" stages ${s.scene.name} but points at ${s.anchor.name}',
      );
    }
  });

  test('the second notch and the split scroll are actually explained', () {
    // The two things users could not guess on their own, per direct feedback.
    final home = kHomeTour.map((s) => '${s.title} ${s.body}').join(' ');
    expect(home, contains('Re-glisse'), reason: 'le deuxième cran');
    expect(home, contains('défiler'), reason: 'la zone qui fait défiler');
    expect(home, contains('referme'), reason: 'la zone qui referme');
  });

  test('per-screen tours cover what the home tour deliberately drops', () {
    final elsewhere = [
      for (final id in [TourId.friends, TourId.decors, TourId.settings])
        for (final s in stepsFor(id)) '${s.title} ${s.body}',
    ].join(' ');
    // Matched on word stems, not on exact wording: the copy is meant to be
    // rewritten freely, and a test that pins phrasing would just get deleted.
    for (final promise in [
      '@handle',
      'cercle',
      'étoil',
      'son',
      'phrase',
      'silencieuses',
    ]) {
      expect(elsewhere, contains(promise), reason: 'jamais expliqué : $promise');
    }
  });
}
