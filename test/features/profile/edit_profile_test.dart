import 'package:dewdrop/src/features/profile/application/profile_providers.dart';
import 'package:dewdrop/src/features/profile/presentation/edit_profile_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fakes.dart';

Future<void> _pump(WidgetTester tester, FakeProfileRepository repo) {
  // Pushed onto a navigator so the screen's success-pop has somewhere to go.
  final nav = GlobalKey<NavigatorState>();
  return tester
      .pumpWidget(
        ProviderScope(
          overrides: [profileRepositoryProvider.overrideWithValue(repo)],
          child: MaterialApp(
            navigatorKey: nav,
            home: Builder(
              builder: (ctx) => TextButton(
                onPressed: () => Navigator.of(ctx).push(
                  MaterialPageRoute(builder: (_) => const EditProfileScreen()),
                ),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      )
      .then((_) async {
        await tester.tap(find.text('go'));
        await tester.pumpAndSettle();
      });
}

void main() {
  testWidgets('saving updates the profile via the repository', (tester) async {
    final repo = FakeProfileRepository()..handleAvailable = true;
    await _pump(tester, repo);

    final fields = find.byType(EditableText);
    await tester.enterText(fields.at(0), 'Nouveau Pseudo');
    await tester.enterText(fields.at(1), 'nouveauhandle');
    await tester.tap(find.text('Enregistrer'));
    await tester.pumpAndSettle();

    expect(repo.savedProfileUpdate, isNotNull);
    expect(repo.savedProfileUpdate!['display_name'], 'Nouveau Pseudo');
    expect(repo.savedProfileUpdate!['handle'], 'nouveauhandle');
  });

  testWidgets('an invalid handle is rejected without hitting the repo', (
    tester,
  ) async {
    final repo = FakeProfileRepository()..handleAvailable = true;
    await _pump(tester, repo);

    final fields = find.byType(EditableText);
    await tester.enterText(fields.at(0), 'Pseudo');
    await tester.enterText(fields.at(1), 'x'); // too short
    await tester.tap(find.text('Enregistrer'));
    await tester.pump();

    expect(repo.savedProfileUpdate, isNull);
    expect(find.textContaining('3 à 20 caractères'), findsOneWidget);
  });
}
