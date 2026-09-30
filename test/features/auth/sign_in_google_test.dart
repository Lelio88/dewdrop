import 'package:dewdrop/src/features/auth/application/auth_providers.dart';
import 'package:dewdrop/src/features/auth/presentation/sign_in_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../helpers/fakes.dart';

// The decor background runs a continuous Ticker: drive frames explicitly.
Future<void> _pump(WidgetTester tester, FakeAuthRepository auth) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [authRepositoryProvider.overrideWithValue(auth)],
      child: const MaterialApp(home: SignInScreen()),
    ),
  );
}

Future<void> _tapGoogle(WidgetTester tester) async {
  await tester.tap(find.text('Continuer avec Google'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 20));
}

void main() {
  group('Continuer avec Google', () {
    testWidgets('is offered on sign-in and on sign-up', (tester) async {
      await _pump(tester, FakeAuthRepository());
      expect(find.text('Continuer avec Google'), findsOneWidget);

      await tester.tap(find.text("Pas de compte ? S'inscrire"));
      await tester.pump();
      expect(find.text('Continuer avec Google'), findsOneWidget);
    });

    testWidgets('is hidden where the account picker does not exist', (
      tester,
    ) async {
      await _pump(tester, FakeAuthRepository()..supportsGoogle = false);
      expect(find.text('Continuer avec Google'), findsNothing);
    });

    testWidgets('signs in with the picked account, no email needed', (
      tester,
    ) async {
      final auth = FakeAuthRepository();
      await _pump(tester, auth);
      await _tapGoogle(tester);

      expect(auth.googleSignInCount, 1);
      expect(auth.signInCount, 0);
      expect(find.textContaining('Renseigne'), findsNothing);
    });

    testWidgets('a dismissed picker is not an error', (tester) async {
      final auth = FakeAuthRepository()..googlePicked = false;
      await _pump(tester, auth);
      await _tapGoogle(tester);

      expect(auth.googleSignInCount, 1);
      expect(find.textContaining('Google'), findsOneWidget); // the button only
      expect(find.textContaining("n'a pas abouti"), findsNothing);
    });

    testWidgets('a failure says so, without the raw exception', (tester) async {
      final auth = FakeAuthRepository()
        ..googleError = const AuthException(
          'Google sign-in failed',
          code: 'google_sign_in_failed',
        );
      await _pump(tester, auth);
      await _tapGoogle(tester);

      expect(
        find.textContaining("La connexion avec Google n'a pas abouti"),
        findsOneWidget,
      );
      expect(find.textContaining('Exception'), findsNothing);
    });
  });
}
