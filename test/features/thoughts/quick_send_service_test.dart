import 'package:dewdrop/src/common/app_exceptions.dart';
import 'package:dewdrop/src/features/friends/application/friend_providers.dart';
import 'package:dewdrop/src/features/friends/domain/friend.dart';
import 'package:dewdrop/src/features/profile/application/profile_providers.dart';
import 'package:dewdrop/src/features/profile/domain/profile.dart';
import 'package:dewdrop/src/features/thoughts/application/quick_send_service.dart';
import 'package:dewdrop/src/features/thoughts/application/thought_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fakes.dart';

Friend _friend(String id, {String? handle, String? name}) => Friend(
  friendshipId: 'fs-$id',
  profile: Profile(id: id, handle: handle, displayName: name),
);

void main() {
  final lelio = _friend('u1', handle: 'lelio', name: 'Lélio');
  final alice = _friend('u2', handle: 'alice', name: 'Alice');

  ProviderContainer makeContainer({
    List<Friend> friends = const [],
    Object? friendsError,
    FakeThoughtRepository? thoughts,
    Profile? profile,
  }) {
    final container = ProviderContainer(
      overrides: [
        friendRepositoryProvider.overrideWithValue(
          FakeFriendRepository()
            ..friendsList = friends
            ..friendsError = friendsError,
        ),
        thoughtRepositoryProvider.overrideWithValue(
          thoughts ?? FakeThoughtRepository(),
        ),
        myProfileProvider.overrideWith((ref) async => profile),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  group('QuickSendService.sendToName', () {
    test('resolves a friend and sends', () async {
      final thoughts = FakeThoughtRepository();
      final container = makeContainer(
        friends: [lelio, alice],
        thoughts: thoughts,
      );

      final result = await container
          .read(quickSendServiceProvider)
          .sendToName('lélio');

      expect(result, isA<QuickSendSent>());
      expect((result as QuickSendSent).friend, same(lelio));
      expect(thoughts.sent, hasLength(1));
      expect(thoughts.sent.single.recipientId, 'u1');
    });

    test('returns no-match for an unknown name and sends nothing', () async {
      final thoughts = FakeThoughtRepository();
      final container = makeContainer(friends: [lelio], thoughts: thoughts);

      final result = await container
          .read(quickSendServiceProvider)
          .sendToName('zoltan');

      expect(result, isA<QuickSendNoMatch>());
      expect((result as QuickSendNoMatch).query, 'zoltan');
      expect(thoughts.sent, isEmpty);
    });

    test('returns ambiguous and sends nothing when several match', () async {
      final lea = _friend('u3', handle: 'lea', name: 'Léa');
      final leo = _friend('u4', handle: 'leo', name: 'Léo');
      final thoughts = FakeThoughtRepository();
      final container = makeContainer(friends: [lea, leo], thoughts: thoughts);

      final result = await container
          .read(quickSendServiceProvider)
          .sendToName('le');

      expect(result, isA<QuickSendAmbiguous>());
      expect(
        (result as QuickSendAmbiguous).candidates,
        containsAll([lea, leo]),
      );
      expect(thoughts.sent, isEmpty);
    });

    test('an explicit anonymous flag overrides the profile default', () async {
      final thoughts = FakeThoughtRepository();
      final container = makeContainer(friends: [lelio], thoughts: thoughts);

      await container
          .read(quickSendServiceProvider)
          .sendToName('lelio', anonymous: true);

      expect(thoughts.sent.single.anonymous, isTrue);
    });

    test('falls back to the profile default anonymity', () async {
      final thoughts = FakeThoughtRepository();
      final container = makeContainer(
        friends: [lelio],
        thoughts: thoughts,
        profile: const Profile(id: 'me', defaultAnonymous: true),
      );
      // Resolve the profile so its value is cached before the synchronous read.
      await container.read(myProfileProvider.future);

      await container.read(quickSendServiceProvider).sendToName('lelio');

      expect(thoughts.sent.single.anonymous, isTrue);
    });

    test('wraps a send failure in QuickSendFailed', () async {
      final thoughts = FakeThoughtRepository()
        ..sendError = RateLimitedException();
      final container = makeContainer(friends: [lelio], thoughts: thoughts);

      final result = await container
          .read(quickSendServiceProvider)
          .sendToName('lelio');

      expect(result, isA<QuickSendFailed>());
      expect((result as QuickSendFailed).error, isA<RateLimitedException>());
    });

    test('wraps a friends-load failure in QuickSendFailed', () async {
      final container = makeContainer(friendsError: Exception('offline'));

      final result = await container
          .read(quickSendServiceProvider)
          .sendToName('lelio');

      expect(result, isA<QuickSendFailed>());
    });
  });

  group('QuickSendService.send', () {
    test('sends directly to an already-resolved friend', () async {
      final thoughts = FakeThoughtRepository();
      final container = makeContainer(friends: [lelio], thoughts: thoughts);

      final result = await container
          .read(quickSendServiceProvider)
          .send(alice, anonymous: false);

      expect(result, isA<QuickSendSent>());
      expect(thoughts.sent.single.recipientId, 'u2');
      expect(thoughts.sent.single.anonymous, isFalse);
    });
  });
}
