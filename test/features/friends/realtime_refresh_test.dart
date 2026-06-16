import 'dart:async';

import 'package:dewdrop/src/features/auth/application/auth_providers.dart';
import 'package:dewdrop/src/features/friends/application/friend_providers.dart';
import 'package:dewdrop/src/features/friends/domain/friend.dart';
import 'package:dewdrop/src/features/friends/domain/friend_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../helpers/fakes.dart';

/// Guards the live-refresh wiring: a friendship change arriving over Realtime
/// must make the friends/requests lists refetch, without a relaunch. These
/// tests would have caught the original bug (FutureProviders that fetched once)
/// and the follow-up `void`-collapse bug (identical stream payloads dropped by
/// `AsyncValue ==`, so repeat events never re-notified).

/// A signed-in session so the friends providers don't short-circuit to empty.
final _session = Session(
  accessToken: 'test',
  tokenType: 'bearer',
  user: User(
    id: 'test-uid',
    appMetadata: const {},
    userMetadata: const {},
    aud: 'authenticated',
    createdAt: '2026-01-01T00:00:00.000Z',
  ),
);

/// Counts repo calls and lets the test push realtime ticks on demand.
class FakeFriendRepository implements FriendRepository {
  final _changes = StreamController<int>.broadcast();
  int _tick = 0;
  int incomingRequestsCalls = 0;
  int friendsCalls = 0;

  void emitChange() => _changes.add(++_tick);

  @override
  Stream<int> watchChanges() => _changes.stream;

  @override
  Future<List<IncomingRequest>> incomingRequests() async {
    incomingRequestsCalls++;
    return [];
  }

  @override
  Future<List<Friend>> friends() async {
    friendsCalls++;
    return [];
  }

  @override
  Future<void> sendRequest(String handle) async {}
  @override
  Future<void> acceptRequest(String friendshipId) async {}
  @override
  Future<void> removeFriendship(String friendshipId) async {}
  @override
  Future<void> block(String userId) async {}
  @override
  Future<void> unblock(String userId) async {}
  @override
  Future<void> report(String userId, {String? reason}) async {}
}

void main() {
  group('friends live-refresh on a realtime tick', () {
    late FakeFriendRepository repo;
    late ProviderContainer container;

    setUp(() {
      repo = FakeFriendRepository();
      container = ProviderContainer(
        overrides: [
          authRepositoryProvider.overrideWithValue(
            FakeAuthRepository()..session = _session,
          ),
          friendRepositoryProvider.overrideWithValue(repo),
        ],
      );
      addTearDown(container.dispose);
    });

    test(
      'incomingRequestsProvider refetches when a friendship change ticks',
      () async {
        final sub = container.listen(incomingRequestsProvider, (_, _) {});
        addTearDown(sub.close);

        await container.read(incomingRequestsProvider.future);
        expect(repo.incomingRequestsCalls, 1);

        repo.emitChange();
        await pumpEventQueue();

        expect(
          repo.incomingRequestsCalls,
          2,
          reason: 'a realtime friendship tick must trigger a refetch',
        );
      },
    );

    test('friendsProvider refetches when a friendship change ticks', () async {
      final sub = container.listen(friendsProvider, (_, _) {});
      addTearDown(sub.close);

      await container.read(friendsProvider.future);
      expect(repo.friendsCalls, 1);

      repo.emitChange();
      await pumpEventQueue();

      expect(repo.friendsCalls, 2);
    });

    test(
      'each repeat tick refetches (distinct ints are not collapsed)',
      () async {
        final sub = container.listen(incomingRequestsProvider, (_, _) {});
        addTearDown(sub.close);
        await container.read(incomingRequestsProvider.future);

        repo.emitChange();
        await pumpEventQueue();
        repo.emitChange();
        await pumpEventQueue();

        expect(
          repo.incomingRequestsCalls,
          3,
          reason:
              'two distinct ticks after the initial fetch → 3 fetches total',
        );
      },
    );
  });
}
