import 'package:dewdrop/src/features/tour/domain/tour_step.dart';
import 'package:dewdrop/src/features/tour/presentation/cloud_tour.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _steps = [
  TourStep(title: 'Un', body: 'Premier nuage'),
  TourStep(title: 'Deux', body: 'Deuxième nuage', anchor: TourAnchor.menuButton),
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
