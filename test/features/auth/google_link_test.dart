import 'package:dewdrop/src/features/auth/data/auth_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

UserIdentity _identity(String provider, {String? email}) => UserIdentity(
  id: provider,
  userId: 'u1',
  identityData: {'email': ?email},
  identityId: 'id-$provider',
  provider: provider,
  createdAt: null,
  lastSignInAt: null,
);

User _user(List<UserIdentity> identities) => User(
  id: 'u1',
  appMetadata: const {},
  userMetadata: const {},
  aud: 'authenticated',
  createdAt: '2026-09-30T00:00:00Z',
  identities: identities,
);

void main() {
  group('googleLinkOf', () {
    test('no user, or no Google identity: nothing linked', () {
      expect(googleLinkOf(null), isNull);
      expect(
        googleLinkOf(_user([_identity('email', email: 'a@b.fr')])),
        isNull,
      );
    });

    test('shows the Google address, which may differ from the account one', () {
      final link = googleLinkOf(
        _user([
          _identity('email', email: 'moi@exemple.fr'),
          _identity('google', email: 'moi@gmail.com'),
        ]),
      );
      expect(link?.email, 'moi@gmail.com');
      expect(link?.canUnlink, isTrue);
    });

    test('Google as the only way in can never be unlinked', () {
      final link = googleLinkOf(
        _user([_identity('google', email: 'moi@gmail.com')]),
      );
      expect(link?.canUnlink, isFalse);
    });
  });

  group('linkThenRefresh', () {
    const ownIdentity = AuthException(
      'Identity is already linked',
      statusCode: '422',
      code: 'identity_already_exists',
    );
    const someoneElses = AuthException(
      'Identity is already linked to another user',
      statusCode: '422',
      code: 'identity_already_exists',
    );

    test('refreshes the session once the link is made', () async {
      final calls = <String>[];
      await linkThenRefresh(
        link: () async => calls.add('link'),
        refresh: () async => calls.add('refresh'),
      );
      // GoTrue answers the link with the user as it was before: only the
      // refresh brings the new identity into the session.
      expect(calls, ['link', 'refresh']);
    });

    test(
      'a Google account already linked to this user is not an error',
      () async {
        var refreshed = false;
        await linkThenRefresh(
          link: () async => throw ownIdentity,
          refresh: () async => refreshed = true,
        );
        expect(refreshed, isTrue);
      },
    );

    test('a Google account linked to someone else still fails', () async {
      var refreshed = false;
      await expectLater(
        linkThenRefresh(
          link: () async => throw someoneElses,
          refresh: () async => refreshed = true,
        ),
        throwsA(same(someoneElses)),
      );
      expect(refreshed, isFalse);
    });
  });
}
