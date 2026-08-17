import 'package:dewdrop/src/features/tour/domain/tour_step.dart';
import 'package:dewdrop/src/features/tour/presentation/cloud_bubble.dart';
import 'package:dewdrop/src/features/tour/presentation/cloud_tour.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _steps = [
  TourStep(title: 'Un', body: 'Premier nuage'),
  TourStep(title: 'Deux', body: 'Deuxième nuage', anchor: TourAnchor.menuButton),
  TourStep(title: 'Trois', body: 'Dernier nuage'),
];

/// Steps whose middle one is satisfied by a real swipe.
const _gestureSteps = [
  TourStep(title: 'Un', body: 'Premier nuage'),
  TourStep(
    title: 'Glisse',
    body: 'Fais le geste',
    anchor: TourAnchor.menuButton,
    gesture: TourGesture.swipeUp,
  ),
  TourStep(title: 'Trois', body: 'Dernier nuage'),
];

/// Pumps the tour over a stand-in home screen. [withAnchor] mounts a widget
/// under the key step 2 points at; leaving it out is the "target is gone" case.
Future<int> _pump(WidgetTester tester, {bool withAnchor = true}) async {
  var finished = 0;
  final menuKey = GlobalKey();
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Stack(
          children: [
            const Positioned.fill(child: ColoredBox(color: Colors.indigo)),
            if (withAnchor)
              Positioned(
                right: 20,
                bottom: 20,
                child: SizedBox(key: menuKey, width: 54, height: 54),
              ),
            CloudTour(
              steps: _steps,
              anchors: {if (withAnchor) TourAnchor.menuButton: menuKey},
              onFinish: () => finished++,
            ),
          ],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return finished;
}

void main() {
  testWidgets('opens on the first step', (tester) async {
    await _pump(tester);
    expect(find.text('Un'), findsOneWidget);
    expect(find.text('Premier nuage'), findsOneWidget);
    expect(find.text('Deux'), findsNothing);
  });

  testWidgets('a tap anywhere advances one step', (tester) async {
    await _pump(tester);
    await tester.tapAt(const Offset(30, 300)); // bare decor, away from the bubble
    await tester.pumpAndSettle();
    expect(find.text('Deux'), findsOneWidget);
    expect(find.text('Un'), findsNothing);
  });

  testWidgets('the last step swaps "Suivant" for "C’est parti"', (tester) async {
    await _pump(tester);
    await tester.tap(find.text('Suivant'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Suivant'));
    await tester.pumpAndSettle();
    expect(find.text('Trois'), findsOneWidget);
    expect(find.text('Suivant'), findsNothing);
    expect(find.text('C’est parti'), findsOneWidget);
  });

  testWidgets('finishing calls onFinish exactly once', (tester) async {
    var finished = 0;
    final menuKey = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              SizedBox(key: menuKey, width: 54, height: 54),
              CloudTour(
                steps: _steps,
                anchors: {TourAnchor.menuButton: menuKey},
                onFinish: () => finished++,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    for (var i = 0; i < 2; i++) {
      await tester.tap(find.text('Suivant'));
      await tester.pumpAndSettle();
    }
    expect(finished, 0);
    await tester.tap(find.text('C’est parti'));
    await tester.pumpAndSettle();
    expect(finished, 1);
  });

  testWidgets('"Passer" ends the tour and is hidden on the last step', (
    tester,
  ) async {
    await _pump(tester);
    expect(find.text('Passer'), findsOneWidget);
    await tester.tap(find.text('Suivant'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Suivant'));
    await tester.pumpAndSettle();
    expect(find.text('Passer'), findsNothing);
  });

  group('gestes réels', () {
    /// Pumps the tour over a home that reports gestures, plus a drag detector
    /// standing in for the real decor, so we can assert the swipe reached it.
    Future<(ValueNotifier<TourGesture?>, List<int>, List<String>)> pump(
      WidgetTester tester,
    ) async {
      final gestures = ValueNotifier<TourGesture?>(null);
      addTearDown(gestures.dispose);
      final steps = <int>[];
      final dragsReachingHome = <String>[];
      final menuKey = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                // Stand-in for the home's own gesture detector.
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onVerticalDragEnd: (_) => dragsReachingHome.add('vertical'),
                    child: const ColoredBox(color: Colors.indigo),
                  ),
                ),
                SizedBox(key: menuKey, width: 54, height: 54),
                CloudTour(
                  steps: _gestureSteps,
                  anchors: {TourAnchor.menuButton: menuKey},
                  gestures: gestures,
                  onStepChanged: steps.add,
                  onFinish: () {},
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return (gestures, steps, dragsReachingHome);
    }

    testWidgets('a drag passes through the overlay to the home', (tester) async {
      final (_, _, drags) = await pump(tester);
      // From a bare corner of the decor, clear of the bubble and its buttons.
      await tester.flingFrom(const Offset(40, 520), const Offset(0, -300), 1000);
      await tester.pumpAndSettle();
      // The whole point: the tour dims the screen without confiscating swipes.
      expect(drags, contains('vertical'));
    });

    testWidgets('performing the asked gesture advances the step', (
      tester,
    ) async {
      final (gestures, steps, _) = await pump(tester);
      await tester.tap(find.text('Suivant'));
      await tester.pumpAndSettle();
      expect(find.text('Glisse'), findsOneWidget);

      gestures.value = TourGesture.swipeUp; // the home reports the swipe
      await tester.pump();
      // Still on the step: the user gets a beat to see what the gesture did.
      expect(find.text('Glisse'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 1200));
      await tester.pumpAndSettle();
      expect(find.text('Trois'), findsOneWidget);
      expect(steps, [1, 2]); // the home was told to close its sheet
      expect(gestures.value, isNull); // consumed, so it can satisfy a later step
    });

    testWidgets('an unrelated gesture does not advance the step', (
      tester,
    ) async {
      final (gestures, _, _) = await pump(tester);
      await tester.tap(find.text('Suivant'));
      await tester.pumpAndSettle();

      gestures.value = TourGesture.swipeSide; // not what this step asked for
      await tester.pump(const Duration(milliseconds: 1500));
      await tester.pumpAndSettle();
      expect(find.text('Glisse'), findsOneWidget);
    });

    testWidgets('a gesture on a step that asks for none is ignored', (
      tester,
    ) async {
      final (gestures, _, _) = await pump(tester);
      gestures.value = TourGesture.swipeUp; // step 1 has no gesture
      await tester.pump(const Duration(milliseconds: 1500));
      await tester.pumpAndSettle();
      expect(find.text('Un'), findsOneWidget);
    });
  });

  testWidgets('the bubble slides between positions instead of jumping', (
    tester,
  ) async {
    // Step 2 is anchored near the bottom, so the bubble must travel. It should
    // still be in flight one frame after the switch — a teleport would already
    // be at its destination.
    final menuKey = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              const Positioned.fill(child: ColoredBox(color: Colors.indigo)),
              Positioned(
                bottom: 20,
                right: 20,
                child: SizedBox(key: menuKey, width: 54, height: 54),
              ),
              CloudTour(
                steps: _steps,
                anchors: {TourAnchor.menuButton: menuKey},
                onFinish: () {},
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    double bubbleTop() =>
        tester.getTopLeft(find.byType(CloudBubble).first).dy;
    final start = bubbleTop();

    await tester.tap(find.text('Suivant'));
    await tester.pump(const Duration(milliseconds: 60)); // mid-flight
    final midway = bubbleTop();
    await tester.pumpAndSettle();
    final settled = bubbleTop();

    expect(settled, isNot(closeTo(start, 1)), reason: 'la bulle doit se déplacer');
    expect(
      midway,
      isNot(closeTo(settled, 1)),
      reason: 'elle doit encore glisser 60 ms après le changement, pas y être déjà',
    );
  });

  testWidgets('an anchor with no mounted widget still renders its step', (
    tester,
  ) async {
    // Regression guard: a target that got hidden must degrade to a centred
    // bubble, never throw.
    await _pump(tester, withAnchor: false);
    await tester.tap(find.text('Suivant'));
    await tester.pumpAndSettle();
    expect(find.text('Deux'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
