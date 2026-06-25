import 'package:dewdrop/src/features/friends/domain/friend.dart';
import 'package:dewdrop/src/features/friends/domain/friend_match.dart';
import 'package:dewdrop/src/features/profile/domain/profile.dart';
import 'package:flutter_test/flutter_test.dart';

Friend _friend(String id, {String? handle, String? name}) => Friend(
  friendshipId: 'fs-$id',
  profile: Profile(id: id, handle: handle, displayName: name),
);

void main() {
  group('matchFriend', () {
    final lelio = _friend('1', handle: 'lelio', name: 'Lélio');
    final alice = _friend('2', handle: 'alice', name: 'Alice');
    final bob = _friend('3', handle: 'bob_dylan', name: 'Bob');

    test('resolves an exact handle', () {
      final m = matchFriend([lelio, alice, bob], 'lelio');
      expect(m, isA<FriendMatched>());
      expect((m as FriendMatched).friend, lelio);
    });

    test('is accent- and case-insensitive', () {
      expect(
        (matchFriend([lelio, alice], 'LÉLIO') as FriendMatched).friend,
        lelio,
      );
      expect(
        (matchFriend([lelio, alice], 'lélio') as FriendMatched).friend,
        lelio,
      );
    });

    test('strips a leading @', () {
      expect(
        (matchFriend([lelio, alice], '@alice') as FriendMatched).friend,
        alice,
      );
    });

    test('resolves by display name when the handle differs', () {
      // "Bob" is the display name; the handle is "bob_dylan".
      expect((matchFriend([bob], 'bob') as FriendMatched).friend, bob);
    });

    test('falls back to a prefix match', () {
      expect((matchFriend([bob], 'bob_d') as FriendMatched).friend, bob);
    });

    test('falls back to a substring match', () {
      expect((matchFriend([bob], 'dylan') as FriendMatched).friend, bob);
    });

    test('returns ambiguous when several friends tie at the same tier', () {
      final lea = _friend('4', handle: 'lea', name: 'Léa');
      final leo = _friend('5', handle: 'leo', name: 'Léo');
      final m = matchFriend([lea, leo], 'le'); // both prefix-match "le"
      expect(m, isA<FriendAmbiguous>());
      expect((m as FriendAmbiguous).candidates, containsAll([lea, leo]));
    });

    test('prefers an exact handle over a looser name match', () {
      final exact = _friend('6', handle: 'sam', name: 'Samuel');
      final loose = _friend('7', handle: 'samira', name: 'Sam Lee');
      // "sam" is an exact handle for #6 and a prefix/substring for #7 → #6 wins.
      expect(
        (matchFriend([exact, loose], 'sam') as FriendMatched).friend,
        exact,
      );
    });

    test('returns not-found for an unknown name', () {
      expect(matchFriend([lelio, alice], 'zoltan'), isA<FriendNotFound>());
    });

    test('returns not-found for an empty query or empty list', () {
      expect(matchFriend([lelio], '   '), isA<FriendNotFound>());
      expect(matchFriend(const [], 'lelio'), isA<FriendNotFound>());
    });

    test('tolerates a friend with no display name', () {
      final handleOnly = _friend('8', handle: 'kai');
      expect(
        (matchFriend([handleOnly], 'kai') as FriendMatched).friend,
        handleOnly,
      );
    });
  });
}
