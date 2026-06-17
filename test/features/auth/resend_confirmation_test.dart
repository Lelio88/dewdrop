import 'package:dewdrop/src/features/auth/application/auth_providers.dart';
import 'package:dewdrop/src/features/auth/presentation/sign_in_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fakes.dart';

// The decor runs a continuous Ticker — drive frames explicitly (no pumpAndSettle).
void main() {
  testWidgets('the "vérifie tes emails" screen can re-send the confirmation', (
    tester,
  ) async {
    final auth = FakeAuthRepository()..signUpNeedsConfirm = true;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [authRepositoryProvider.overrideWithValue(auth)],
        child: const MaterialApp(home: SignInScreen()),
      ),
    );

    // Switch to sign-up, fill, submit → reaches the "check your inbox" screen.
    await tester.tap(find.text("Pas de compte ? S'inscrire"));
    await tester.pump();
    final fields = find.byType(EditableText);
    await tester.enterText(fields.at(0), 'new@example.com');
    await tester.enterText(fields.at(1), 'hunter2pw');
    await tester.enterText(fields.at(2), 'hunter2pw');
    await tester.tap(find.text('Créer mon compte'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    expect(find.text('Vérifie tes emails'), findsOneWidget);

    // Re-send.
    await tester.tap(find.text('Renvoyer le lien'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    expect(auth.lastResendEmail, 'new@example.com');
    expect(find.text('Lien renvoyé ✓'), findsOneWidget);
  });
}
