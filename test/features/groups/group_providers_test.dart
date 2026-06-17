import 'package:dewdrop/src/features/auth/application/auth_providers.dart';
import 'package:dewdrop/src/features/groups/application/group_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../helpers/fakes.dart';

/// Same live-refresh contract as friends: a group/membership change over Realtime
/// must make `myGroupsProvider` refetch, and when signed out it never hits the repo.

final _session = Session(
  accessToken: 'test',
  tokenType: 'bearer',
  user: User(
    id: 'me',
    appMetadata: const {},
    userMetadata: const {},
    aud: 'authenticated',
    createdAt: '2026-01-01T00:00:00.000Z',
  ),
);

void main() {
  test('myGroupsProvider is empty (no repo hit) when signed out', () async {
    final repo = FakeGroupRepository();
    final c = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
        groupRepositoryProvider.overrideWithValue(repo),
      ],
    );
    addTearDown(c.dispose);

    expect(await c.read(myGroupsProvider.future), isEmpty);
    expect(repo.myGroupsCalls, 0);
  });

  test('myGroupsProvider refetches when a group change ticks', () async {
    final repo = FakeGroupRepository();
    final c = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(
          FakeAuthRepository()..session = _session,
        ),
        groupRepositoryProvider.overrideWithValue(repo),
      ],
    );
    addTearDown(c.dispose);

    final sub = c.listen(myGroupsProvider, (_, _) {});
    addTearDown(sub.close);

    await pumpEventQueue();
    expect(repo.myGroupsCalls, 1);

    repo.emitChange();
    await pumpEventQueue();

    expect(
      repo.myGroupsCalls,
      2,
      reason: 'a realtime group/membership tick must trigger a refetch',
    );
  });
}
