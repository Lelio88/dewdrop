import 'package:dewdrop/src/features/auth/application/auth_providers.dart';
import 'package:dewdrop/src/features/auth/domain/auth_repository.dart';
import 'package:dewdrop/src/features/settings/presentation/google_link_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../helpers/fakes.dart';

Future<void> _pump(WidgetTester tester, FakeAuthRepository auth) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [authRepositoryProvider.overrideWithValue(auth)],
      child: const MaterialApp(
        home: Scaffold(body: Material(child: GoogleLinkTile())),
      ),
    ),
  );
}

void main() {
  group('GoogleLinkTile', () {
    testWidgets('offers to link when no Google account is linked', (
      tester,
    ) async {
      final auth = FakeAuthRepository();
      await _pump(tester, auth);

      await tester.tap(find.text('Lier mon compte Google'));
      await tester.pumpAndSettle();

      expect(auth.googleLinkCount, 1);
      expect(find.text('Compte Google lié'), findsOneWidget);
      expect(find.text('moi@gmail.com'), findsOneWidget);
    });

    testWidgets('a dismissed picker links nothing and says nothing', (
      tester,
    ) async {
      final auth = FakeAuthRepository()..googlePicked = false;
      await _pump(tester, auth);

      await tester.tap(find.text('Lier mon compte Google'));
      await tester.pumpAndSettle();

      expect(find.text('Lier mon compte Google'), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('a Google account used elsewhere is explained', (tester) async {
      final auth = FakeAuthRepository()
        ..googleError = const AuthException(
          'Identity is already linked to another user',
          code: 'identity_already_exists',
        );
      await _pump(tester, auth);

      await tester.tap(find.text('Lier mon compte Google'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('déjà lié à un autre compte DewDrop'),
        findsOneWidget,
      );
    });

    testWidgets('unlinks after confirmation when another sign-in remains', (
      tester,
    ) async {
      final auth = FakeAuthRepository()
        ..linkedGoogle = const GoogleLink(
          email: 'moi@gmail.com',
          canUnlink: true,
        );
      await _pump(tester, auth);

      await tester.tap(find.text('Délier'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Délier'));
      await tester.pumpAndSettle();

      expect(auth.googleUnlinkCount, 1);
      expect(find.text('Lier mon compte Google'), findsOneWidget);
    });

    testWidgets('never offers to unlink the only way to sign in', (
      tester,
    ) async {
      final auth = FakeAuthRepository()
        ..linkedGoogle = const GoogleLink(
          email: 'moi@gmail.com',
          canUnlink: false,
        );
      await _pump(tester, auth);

      expect(find.text('Compte Google lié'), findsOneWidget);
      expect(find.text('Délier'), findsNothing);
    });

    testWidgets('is absent where the account picker does not exist', (
      tester,
    ) async {
      await _pump(tester, FakeAuthRepository()..supportsGoogle = false);
      expect(find.byType(ListTile), findsNothing);
    });
  });
}
