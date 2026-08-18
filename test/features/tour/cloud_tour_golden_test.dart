import 'package:dewdrop/src/features/tour/domain/tour_step.dart';
import 'package:dewdrop/src/features/tour/presentation/cloud_bubble.dart';
import 'package:dewdrop/src/features/tour/presentation/cloud_tour.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pixel tests for the tour's look.
///
/// Every visual defect this feature shipped — the bubble sitting on the faces,
/// puffs trailing off toward nothing, the cloud jumping between placements —
/// was found by a human looking at a phone, one published build at a time.
/// None of them could fail a behavioural test: the widgets were all *there*,
/// just in the wrong place. These goldens are the cheap version of that loop.
///
/// Regenerate deliberately, never reflexively:
///   flutter test --update-goldens test/features/tour/cloud_tour_golden_test.dart
/// then LOOK at the produced images before committing them. A golden updated
/// without being looked at is worse than no golden — it records the bug as the
/// new truth.
///
/// Text is rendered with the test font (boxes instead of glyphs), which is
/// fine: these check geometry — where the cloud sits, which way it points, what
/// it overlaps — not typography.

/// A drawer-shaped target, so a step can be staged the way the home stages it.
Widget _harness({
  required List<TourStep> steps,
  required Widget Function(GlobalKey bandKey, GlobalKey panelKey) scenery,
  Map<TourAnchor, GlobalKey>? anchors,
  required GlobalKey bandKey,
  required GlobalKey panelKey,
}) => MaterialApp(
  debugShowCheckedModeBanner: false,
  home: Scaffold(
    body: Stack(
      children: [
        // Stand-in for the live decor: a flat colour is enough, and keeps the
        // goldens independent of the decor engine's own rendering.
        const Positioned.fill(child: ColoredBox(color: Color(0xFF12162A))),
        scenery(bandKey, panelKey),
        CloudTour(
          steps: steps,
          anchors:
              anchors ??
              {
                TourAnchor.sendSheetHint: bandKey,
                TourAnchor.sendSheet: panelKey,
              },
          onFinish: () {},
        ),
      ],
    ),
  ),
);

void main() {
  testWidgets('bulle sans cible : centrée', (tester) async {
    final band = GlobalKey();
    final panel = GlobalKey();
    await tester.pumpWidget(
      _harness(
        steps: const [
          TourStep(title: 'Une pensée', body: 'Rien de plus à faire ici.'),
        ],
        scenery: (_, _) => const SizedBox.shrink(),
        anchors: const {},
        bandKey: band,
        panelKey: panel,
      ),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(CloudTour),
      matchesGoldenFile('goldens/bubble_centered.png'),
    );
  });

  testWidgets('cible en haut : bulle dessous, queue vers le haut', (
    tester,
  ) async {
    final band = GlobalKey();
    final panel = GlobalKey();
    await tester.pumpWidget(
      _harness(
        steps: const [
          TourStep(
            title: 'Glisse vers le bas',
            body: 'L’autre tiroir, en haut cette fois.',
            anchor: TourAnchor.sendSheetHint,
          ),
        ],
        scenery: (b, _) => Positioned(
          top: 24,
          left: 0,
          right: 0,
          child: Center(child: SizedBox(key: b, width: 44, height: 10)),
        ),
        bandKey: band,
        panelKey: panel,
      ),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(CloudTour),
      matchesGoldenFile('goldens/bubble_below_target.png'),
    );
  });

  testWidgets('cible en bas : bulle dessus, queue vers le bas', (tester) async {
    final band = GlobalKey();
    final panel = GlobalKey();
    await tester.pumpWidget(
      _harness(
        steps: const [
          TourStep(
            title: 'Glisse vers le haut',
            body: 'Le tiroir d’envoi arrive par le bas.',
            anchor: TourAnchor.sendSheetHint,
          ),
        ],
        scenery: (b, _) => Positioned(
          bottom: 20,
          left: 0,
          right: 0,
          child: Center(child: SizedBox(key: b, width: 44, height: 10)),
        ),
        bandKey: band,
        panelKey: panel,
      ),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(CloudTour),
      matchesGoldenFile('goldens/bubble_above_target.png'),
    );
  });

  testWidgets('tiroir plein écran : bulle au bord, hors du contenu', (
    tester,
  ) async {
    // THE regression that shipped: with the panel filling the screen there is
    // no room beside it, and the bubble landed on the faces.
    final band = GlobalKey();
    final panel = GlobalKey();
    await tester.pumpWidget(
      _harness(
        steps: const [
          TourStep(
            title: 'En grand, deux zones',
            body:
                'Le haut referme, le bas fait défiler la liste des visages.',
            anchor: TourAnchor.sendSheetHint,
            placement: TourPlacement.screenBottom,
          ),
        ],
        scenery: (b, p) => Positioned(
          key: p,
          top: 60,
          left: 0,
          right: 0,
          bottom: 0,
          child: Column(
            children: [
              // The chevron band…
              Center(child: SizedBox(key: b, width: 44, height: 12)),
              // …and the faces it must not cover.
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var i = 0; i < 4; i++)
                      Container(
                        width: 54,
                        height: 54,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Color(0x33FFFFFF),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        bandKey: band,
        panelKey: panel,
      ),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(CloudTour),
      matchesGoldenFile('goldens/bubble_fullscreen_drawer.png'),
    );
  });

  testWidgets('le nuage seul, sans queue', (tester) async {
    // The silhouette itself: lobes, haloes, gradient. Guards the look of the
    // cloud independently of where the tour puts it.
    await tester.pumpWidget(
      const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          backgroundColor: Color(0xFF12162A),
          body: Center(
            child: SizedBox(
              width: 320,
              child: CloudBubble(
                child: Text('Un nuage, deux lignes, pour voir la silhouette.'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(CloudBubble),
      matchesGoldenFile('goldens/cloud_bubble_plain.png'),
    );
  });
}
