import 'package:dewdrop/src/features/auth/application/auth_error.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('authErrorMessage', () {
    test('maps network / server-unreachable failures', () {
      const networkErrors = [
        'ClientException with SocketException: Connection refused',
        'Connection refused',
        'Failed host lookup: "127.0.0.1"',
        'TimeoutException after 0:00:10.000000',
        'HandshakeException: handshake error',
        'Network is unreachable',
      ];
      for (final e in networkErrors) {
        expect(
          authErrorMessage(Exception(e)),
          contains('Connexion au serveur'),
          reason: 'should be a network message for: $e',
        );
      }
    });

    test('maps wrong credentials', () {
      expect(
        authErrorMessage(Exception('Invalid login credentials')),
        'Email ou mot de passe incorrect.',
      );
    });

    test('maps an unconfirmed email', () {
      expect(
        authErrorMessage(Exception('Email not confirmed')),
        contains('Confirme'),
      );
    });

    // Guide C2: sign-up must never confirm that an email is taken. The
    // repository answers a duplicate like a new account; should the raw error
    // ever reach the screen anyway, it gets the generic sign-up message.
    test('never reveals an already-registered account (sign up)', () {
      for (final e in ['User already registered', 'user_already_exists']) {
        final message = authErrorMessage(Exception(e), isSignUp: true);
        expect(message, 'Impossible de créer le compte. Réessaie.');
        expect(message, isNot(contains('existe')));
      }
    });

    test('maps the Google sign-in failures', () {
      expect(
        authErrorMessage(Exception('google_sign_in_failed')),
        "La connexion avec Google n'a pas abouti. Réessaie.",
      );
      expect(
        authErrorMessage(Exception('identity_already_exists')),
        contains('déjà lié à un autre compte DewDrop'),
      );
      expect(
        authErrorMessage(Exception('single_identity_not_deletable')),
        contains('seul moyen de connexion'),
      );
    });

    test(
      'states the server password rule (8 characters, letters + digits)',
      () {
        expect(
          authErrorMessage(
            Exception('Password should be at least 8 characters'),
          ),
          allOf(
            contains('8 caractères'),
            contains('lettres'),
            contains('chiffres'),
          ),
        );
      },
    );

    test('maps a malformed email', () {
      expect(
        authErrorMessage(
          Exception('Unable to validate email address: invalid format'),
        ),
        contains('email invalide'),
      );
    });

    test('maps a rate limit', () {
      expect(
        authErrorMessage(Exception('over_request_rate_limit')),
        contains('Trop de tentatives'),
      );
    });

    test('a network failure is never mistaken for a credentials error', () {
      // A wrong-password attempt while offline surfaces the network string —
      // it must read as "serveur injoignable", not "mot de passe incorrect".
      expect(
        authErrorMessage(Exception('SocketException: Connection refused')),
        isNot('Email ou mot de passe incorrect.'),
      );
    });

    test('falls back differently for sign-in vs sign-up', () {
      expect(
        authErrorMessage(Exception('some unexpected thing')),
        contains('Une erreur est survenue'),
      );
      expect(
        authErrorMessage(Exception('some unexpected thing'), isSignUp: true),
        contains('créer le compte'),
      );
    });

    test('is case-insensitive', () {
      expect(
        authErrorMessage(Exception('INVALID LOGIN CREDENTIALS')),
        'Email ou mot de passe incorrect.',
      );
      expect(
        authErrorMessage(Exception('SOCKETEXCEPTION')),
        contains('Connexion au serveur'),
      );
    });

    test('handles the supabase error-code forms', () {
      expect(
        authErrorMessage(Exception('weak_password')),
        contains('8 caractères'),
      );
      expect(
        authErrorMessage(Exception('email_not_confirmed')),
        contains('Confirme'),
      );
    });

    test('covers the remaining network + code branches', () {
      expect(
        authErrorMessage(Exception('invalid_credentials')),
        'Email ou mot de passe incorrect.',
      );
      expect(
        authErrorMessage(
          Exception('Connection closed before full header was received'),
        ),
        contains('Connexion au serveur'),
      );
      expect(
        authErrorMessage(Exception('XMLHttpRequest error')),
        contains('Connexion au serveur'),
      );
      expect(
        authErrorMessage(Exception('validation_failed')),
        contains('email invalide'),
      );
    });
  });
}
