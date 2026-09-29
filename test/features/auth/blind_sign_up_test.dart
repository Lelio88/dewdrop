import 'package:dewdrop/src/features/auth/data/auth_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

User _user({List<UserIdentity>? identities}) => User(
  id: 'u1',
  appMetadata: const {},
  userMetadata: const {},
  aud: 'authenticated',
  createdAt: '2026-09-30T00:00:00Z',
  identities: identities,
);

void main() {
  group('blindSignUp — never reveals that an email is already registered', () {
    test('a new account waiting for its confirmation email', () async {
      final needsConfirm = await blindSignUp(
        () async => AuthResponse(
          user: _user(
            identities: [
              UserIdentity(
                id: 'i1',
                userId: 'u1',
                identityData: const {},
                identityId: 'i1',
                provider: 'email',
                createdAt: null,
                lastSignInAt: null,
                updatedAt: null,
              ),
            ],
          ),
        ),
      );
      expect(needsConfirm, isTrue);
    });

    test(
      'an already-registered email answers exactly like a new account',
      () async {
        // GoTrue hides a confirmed duplicate behind a user with no identity
        // and no session; the app must not tell the two apart.
        final needsConfirm = await blindSignUp(
          () async => AuthResponse(user: _user(identities: const [])),
        );
        expect(needsConfirm, isTrue);
      },
    );

    test(
      'a server that reports the duplicate outright is answered the same',
      () async {
        final needsConfirm = await blindSignUp(
          () async => throw const AuthException(
            'User already registered',
            statusCode: '422',
            code: 'user_already_exists',
          ),
        );
        expect(needsConfirm, isTrue);
      },
    );

    test('a sign-up that opens a session needs no confirmation', () async {
      final needsConfirm = await blindSignUp(
        () async => AuthResponse(
          session: Session(
            accessToken: 'a',
            tokenType: 'bearer',
            user: _user(),
          ),
        ),
      );
      expect(needsConfirm, isFalse);
    });

    test('any other failure still reaches the screen', () async {
      expect(
        () => blindSignUp(
          () async => throw const AuthException(
            'Password should be at least 8 characters.',
            statusCode: '422',
            code: 'weak_password',
          ),
        ),
        throwsA(isA<AuthException>()),
      );
    });
  });
}
