import 'package:dewdrop/src/common/legal_links.dart';
import 'package:dewdrop/src/features/settings/presentation/legal_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LegalLinks', () {
    test('every legal page lives on the hosted site, over HTTPS', () {
      for (final uri in [
        LegalLinks.privacy,
        LegalLinks.terms,
        LegalLinks.legalNotice,
        LegalLinks.accountDeletion,
      ]) {
        expect(uri.scheme, 'https');
        expect(uri.host, 'dewdrop.heianenterprise.com');
        expect(uri.path, startsWith('/'));
      }
    });

    test('the privacy policy has its own page, apart from the home page', () {
      // Google requires distinct home-page and policy URLs (brand check), and
      // this is the URL declared on the Play listing.
      expect(
        LegalLinks.privacy.toString(),
        'https://dewdrop.heianenterprise.com/confidentialite.html',
      );
    });
  });

  group('LegalScreen', () {
    late List<Uri> opened;

    Future<void> pump(WidgetTester tester, {bool opens = true}) async {
      opened = [];
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            externalLinkOpenerProvider.overrideWithValue((uri) async {
              opened.add(uri);
              return opens;
            }),
          ],
          child: const MaterialApp(home: LegalScreen()),
        ),
      );
    }

    testWidgets('opens each legal page in the browser', (tester) async {
      await pump(tester);

      await tester.tap(find.text('Politique de confidentialité'));
      await tester.tap(find.text("Conditions d'utilisation"));
      await tester.tap(find.text('Mentions légales'));
      await tester.pump();

      expect(opened, [
        LegalLinks.privacy,
        LegalLinks.terms,
        LegalLinks.legalNotice,
      ]);
    });

    testWidgets('says so when the browser cannot open', (tester) async {
      await pump(tester, opens: false);

      await tester.tap(find.text('Mentions légales'));
      await tester.pump();

      expect(find.text("Impossible d'ouvrir le lien."), findsOneWidget);
    });
  });
}
