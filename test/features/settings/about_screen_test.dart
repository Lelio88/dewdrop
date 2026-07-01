import 'package:dewdrop/src/features/settings/presentation/about_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // The body is a lazy ListView; a tall surface makes every row build so the
  // credits + licenses entries are all found without scrolling gymnastics.
  Future<void> pump(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1080, 4000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(home: AboutScreen()));
  }

  group('AboutScreen — legal notices', () {
    testWidgets('surfaces the required CC BY 4.0 tumbleweed attribution', (
      tester,
    ) async {
      // CC BY requires the credit to be visible to the user, not only in a repo
      // file. This is the legally load-bearing assertion — do not weaken it.
      await pump(tester);

      expect(find.textContaining('duckduckpony'), findsOneWidget);
      // Source + license references must be present.
      expect(find.textContaining('204028'), findsOneWidget);
      expect(find.textContaining('204031'), findsOneWidget);
      // At least one CC BY 4.0 credit + license link is visible (there are now
      // two CC BY assets — the tumbleweed and the Noël music box).
      expect(find.textContaining('CC BY 4.0'), findsWidgets);
      expect(
        find.textContaining('creativecommons.org/licenses/by/4.0'),
        findsWidgets,
      );
    });

    testWidgets('surfaces the required CC BY 4.0 music-box attribution', (
      tester,
    ) async {
      // The Noël music (Brahms arr. music box) is CC BY 4.0 — its author credit
      // must be visible to the user, same load-bearing rule as the tumbleweed.
      await pump(tester);
      expect(find.textContaining('Gregor Quendel'), findsOneWidget);
      expect(find.textContaining('CC BY 4.0'), findsWidgets);
    });

    testWidgets('surfaces the required CC BY jackhammer attribution', (
      tester,
    ) async {
      // The 1er avril jackhammer (Tomlija, Freesound #98859) is CC BY 3.0 — its
      // author credit + source must be visible to the user.
      await pump(tester);
      expect(find.textContaining('Tomlija'), findsOneWidget);
      expect(find.textContaining('98859'), findsOneWidget);
    });

    testWidgets('states the rest of the audio is CC0 / public domain', (
      tester,
    ) async {
      await pump(tester);
      expect(find.textContaining('CC0'), findsWidgets);
    });

    testWidgets('exposes an open-source licenses entry', (tester) async {
      await pump(tester);
      expect(find.text('Licences open source'), findsOneWidget);
    });

    testWidgets('tapping the licenses entry does not throw', (tester) async {
      await pump(tester);
      // Target the licenses tile by its label (the screen has a second
      // ListTile, « Confidentialité & CGU »).
      final tile = find.widgetWithText(ListTile, 'Licences open source');
      await tester.ensureVisible(tile);
      await tester.tap(tile);
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });
}
