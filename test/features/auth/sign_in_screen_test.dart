import 'package:dewdrop/src/features/auth/application/auth_providers.dart';
import 'package:dewdrop/src/features/auth/presentation/sign_in_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fakes.dart';

// The decor background runs a continuous Ticker, so we drive frames explicitly
// (never pumpAndSettle, which would hang).
Future<void> _pumpSignIn(WidgetTester tester, FakeAuthRepository auth) {
  return tester.pumpWidget(
    ProviderScope(
      overrides: [authRepositoryProvider.overrideWithValue(auth)],
      child: const MaterialApp(home: SignInScreen()),
    ),
  );
}

Future<void> _fillAndSubmit(WidgetTester tester) async {
  final fields = find.byType(EditableText);
  await tester.enterText(fields.at(0), 'someone@example.com'); // email
  await tester.enterText(fields.at(1), 'hunter2'); // password
  await tester.tap(find.text('Se connecter'));
  await tester.pump(); // run _submit's future
  await tester.pump(const Duration(milliseconds: 20)); // settle the setState
}

void main() {
  testWidgets('shows a friendly message when the credentials are wrong', (
    tester,
  ) async {
    final auth = FakeAuthRepository()
      ..signInError = Exception('Invalid login credentials');
    await _pumpSignIn(tester, auth);
    await _fillAndSubmit(tester);

    expect(auth.signInCount, 1);
    expect(find.text('Email ou mot de passe incorrect.'), findsOneWidget);
    // Never the raw exception.
    expect(find.textContaining('Exception'), findsNothing);
  });

  testWidgets('shows a server-unreachable message on a network failure', (
    tester,
  ) async {
    final auth = FakeAuthRepository()
      ..signInError = Exception(
        'ClientException with SocketException: Connection refused',
      );
    await _pumpSignIn(tester, auth);
    await _fillAndSubmit(tester);

    expect(
      find.textContaining('Connexion au serveur impossible'),
      findsOneWidget,
    );
  });

  testWidgets('no error shown on a successful sign-in', (tester) async {
    final auth = FakeAuthRepository(); // no error
    await _pumpSignIn(tester, auth);
    await _fillAndSubmit(tester);

    expect(auth.signInCount, 1);
    expect(find.text('Email ou mot de passe incorrect.'), findsNothing);
    expect(find.textContaining('Connexion au serveur'), findsNothing);
  });

  testWidgets('validates that both fields are filled before calling auth', (
    tester,
  ) async {
    final auth = FakeAuthRepository();
    await _pumpSignIn(tester, auth);
    await tester.tap(find.text('Se connecter')); // empty fields
    await tester.pump();

    expect(auth.signInCount, 0); // never reached the repository
    expect(find.textContaining('Renseigne ton email'), findsOneWidget);
  });
}
