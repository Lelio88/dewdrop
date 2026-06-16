import 'package:dewdrop/src/features/settings/presentation/about_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pump(WidgetTester tester) =>
      tester.pumpWidget(const MaterialApp(home: AboutScreen()));

  group('AboutScreen — legal notices', () {
    testWidgets('surfaces the required CC BY 4.0 tumbleweed attribution', (
      tester,
    ) async {
      // CC BY requires the credit to be visible to the user, not only in a repo
      // file. This is the legally load-bearing assertion — do not weaken it.
      await pump(tester);

      expect(find.textContaining('duckduckpony'), findsOneWidget);
      expect(find.textContaining('CC BY 4.0'), findsOneWidget);
      // Source + license references must be present.
      expect(find.textContaining('204028'), findsOneWidget);
      expect(find.textContaining('204031'), findsOneWidget);
      expect(
        find.textContaining('creativecommons.org/licenses/by/4.0'),
        findsOneWidget,
      );
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
      // The licenses tile is the only ListTile on the screen.
      await tester.tap(find.byType(ListTile));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });
}
