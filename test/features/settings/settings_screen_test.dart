import 'package:dewdrop/src/features/ambient/application/ambient_providers.dart';
import 'package:dewdrop/src/features/auth/application/auth_providers.dart';
import 'package:dewdrop/src/features/profile/application/profile_providers.dart';
import 'package:dewdrop/src/features/profile/domain/profile.dart';
import 'package:dewdrop/src/features/settings/presentation/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fakes.dart';

void main() {
  // Same rule as the home menu: a ListTile paints its background and ink on the
  // nearest Material, and every tile here lives inside a glass card whose colour
  // would cover them. ListTile reports it itself, the binding turns the report
  // into a failure — so pumping the screen is the assertion.
  testWidgets('every settings tile keeps its ink above its card background', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        profileRepositoryProvider.overrideWithValue(
          FakeProfileRepository()
            ..profile = const Profile(id: 'u1', handle: 'claude'),
        ),
        authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
      ],
    );
    addTearDown(container.dispose);
    // Tall surface: the body is a lazy ListView, and a tile that never builds
    // never reports. Tall also keeps the rows clear of any overflow, which
    // would be reported the same way and fail for the wrong reason.
    await tester.binding.setSurfaceSize(const Size(1000, 5000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await container.read(myProfileProvider.future);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ListTile), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
