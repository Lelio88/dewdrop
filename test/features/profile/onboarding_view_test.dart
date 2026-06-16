import 'package:dewdrop/src/features/auth/application/auth_providers.dart';
import 'package:dewdrop/src/features/profile/application/profile_providers.dart';
import 'package:dewdrop/src/features/profile/presentation/onboarding_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fakes.dart';

// The decor background runs a continuous Ticker → drive frames explicitly.
// authRepositoryProvider is faked too so a myProfileProvider invalidation on
// success never reaches the (uninitialised) Supabase client.
Future<void> _pump(WidgetTester tester, FakeProfileRepository repo) {
  return tester.pumpWidget(
    ProviderScope(
      overrides: [
        profileRepositoryProvider.overrideWithValue(repo),
        authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
      ],
      child: const MaterialApp(home: OnboardingView()),
    ),
  );
}

Future<void> _submit(
  WidgetTester tester, {
  required String pseudo,
  required String handle,
}) async {
  final fields = find.byType(EditableText);
  await tester.enterText(fields.at(0), pseudo); // pseudo
  await tester.enterText(fields.at(1), handle); // handle
  await tester.tap(find.text("C'est parti"));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 20));
}

void main() {
  testWidgets('rejects a too-short handle without touching the repo', (
    tester,
  ) async {
    final repo = FakeProfileRepository();
    await _pump(tester, repo);
    await _submit(tester, pseudo: 'Lélio', handle: 'ab');

    expect(find.textContaining('3 à 20 caractères'), findsOneWidget);
    expect(repo.lastSetHandle, isNull); // never reached setHandle
  });

  testWidgets('shows "déjà pris" when the handle is taken', (tester) async {
    final repo = FakeProfileRepository()..handleAvailable = false;
    await _pump(tester, repo);
    await _submit(tester, pseudo: 'Lélio', handle: 'lelio');

    expect(find.text('Ce handle est déjà pris.'), findsOneWidget);
    expect(repo.lastSetHandle, isNull); // stopped before claiming it
  });

  testWidgets('claims the handle when available', (tester) async {
    final repo = FakeProfileRepository(); // handleAvailable = true
    await _pump(tester, repo);
    await _submit(tester, pseudo: 'Lélio', handle: 'lelio');

    expect(repo.lastSetHandle, 'lelio');
    expect(find.textContaining('déjà pris'), findsNothing);
  });
}
