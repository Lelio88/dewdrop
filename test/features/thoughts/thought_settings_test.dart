import 'package:dewdrop/src/features/auth/application/auth_providers.dart';
import 'package:dewdrop/src/features/profile/application/profile_providers.dart';
import 'package:dewdrop/src/features/profile/domain/profile.dart';
import 'package:dewdrop/src/features/thoughts/presentation/thought_settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fakes.dart';

/// Resolves [myProfileProvider] with [repo]'s seeded profile *before* pumping,
/// so the screen's initState reads the real profile (as in production, where it
/// is already cached) rather than the loading-state null.
Future<void> _pump(WidgetTester tester, FakeProfileRepository repo) async {
  final container = ProviderContainer(
    overrides: [
      profileRepositoryProvider.overrideWithValue(repo),
      authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
    ],
  );
  addTearDown(container.dispose);
  // Tall surface so the bottom "Mes presets" card (with up to 5 rows + button)
  // fits without scrolling — keeps the taps deterministic.
  await tester.binding.setSurfaceSize(const Size(1000, 2200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await container.read(myProfileProvider.future);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: ThoughtSettingsScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('saving a preset captures it and survives the dialog close', (
    tester,
  ) async {
    final repo = FakeProfileRepository()
      ..profile = const Profile(id: 'u1', handle: 'claude', displayName: 'Claude');
    await _pump(tester, repo);

    // Open the name dialog.
    await tester.ensureVisible(find.text('Enregistrer ce style'));
    await tester.tap(find.text('Enregistrer ce style'));
    await tester.pumpAndSettle();

    // Name it and confirm. The dialog's close animation is what used to crash
    // ("A TextEditingController was used after being disposed").
    await tester.enterText(find.byType(EditableText), 'Bonjour');
    await tester.tap(find.widgetWithText(TextButton, 'Enregistrer'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(repo.savedThoughtPresets, isNotNull);
    expect(repo.savedThoughtPresets!.length, 1);
    expect(repo.savedThoughtPresets!.first['name'], 'Bonjour');
  });

  testWidgets('the save button alerts (and saves nothing) when 5 already exist', (
    tester,
  ) async {
    final presets = [
      for (var i = 0; i < 5; i++)
        {
          'name': 'P$i',
          'style': {'lead': '', 'body': '%s a pensé à toi', 'tail': '✨'},
        },
    ];
    final repo = FakeProfileRepository()
      ..profile = Profile(
        id: 'u1',
        handle: 'claude',
        displayName: 'Claude',
        thoughtPresetsRaw: presets,
      );
    await _pump(tester, repo);

    await tester.ensureVisible(find.text('Enregistrer ce style'));
    await tester.tap(find.text('Enregistrer ce style'));
    await tester.pumpAndSettle();

    expect(find.text('Maximum atteint'), findsOneWidget);
    expect(repo.savedThoughtPresets, isNull); // nothing persisted
  });
}
