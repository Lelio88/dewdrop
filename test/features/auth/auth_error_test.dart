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
        expect(authErrorMessage(Exception(e)), contains('Connexion au serveur'),
            reason: 'should be a network message for: $e');
      }
    });

    test('maps wrong credentials', () {
      expect(authErrorMessage(Exception('Invalid login credentials')),
          'Email ou mot de passe incorrect.');
    });

    test('maps an unconfirmed email', () {
      expect(authErrorMessage(Exception('Email not confirmed')),
          contains('Confirme'));
    });

    test('maps an already-registered account (sign up)', () {
      expect(authErrorMessage(Exception('User already registered'), isSignUp: true),
          contains('existe déjà'));
    });

    test('maps a too-short password', () {
      expect(
          authErrorMessage(Exception('Password should be at least 6 characters')),
          contains('trop court'));
    });

    test('maps a malformed email', () {
      expect(
          authErrorMessage(Exception('Unable to validate email address: invalid format')),
          contains('email invalide'));
    });

    test('maps a rate limit', () {
      expect(authErrorMessage(Exception('over_request_rate_limit')),
          contains('Trop de tentatives'));
    });

    test('a network failure is never mistaken for a credentials error', () {
      // A wrong-password attempt while offline surfaces the network string —
      // it must read as "serveur injoignable", not "mot de passe incorrect".
      expect(authErrorMessage(Exception('SocketException: Connection refused')),
          isNot('Email ou mot de passe incorrect.'));
    });

    test('falls back differently for sign-in vs sign-up', () {
      expect(authErrorMessage(Exception('some unexpected thing')),
          contains('Une erreur est survenue'));
      expect(authErrorMessage(Exception('some unexpected thing'), isSignUp: true),
          contains('créer le compte'));
    });

    test('is case-insensitive', () {
      expect(authErrorMessage(Exception('INVALID LOGIN CREDENTIALS')),
          'Email ou mot de passe incorrect.');
      expect(authErrorMessage(Exception('SOCKETEXCEPTION')),
          contains('Connexion au serveur'));
    });

    test('handles the supabase error-code forms', () {
      expect(authErrorMessage(Exception('user_already_exists'), isSignUp: true),
          contains('existe déjà'));
      expect(authErrorMessage(Exception('weak_password')), contains('trop court'));
      expect(authErrorMessage(Exception('email_not_confirmed')), contains('Confirme'));
    });
  });
}
