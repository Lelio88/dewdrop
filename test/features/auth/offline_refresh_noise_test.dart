import 'package:dewdrop/src/features/auth/application/auth_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('isOfflineAuthRefreshNoise', () {
    // What gotrue wraps around package:http's socket failure (io_client.dart).
    const offline =
        "ClientException with SocketException: Failed host lookup: "
        "'x.supabase.co' (OS Error: No address associated with hostname, "
        'errno = 7), uri=https://x.supabase.co/auth/v1/token';

    test('matches an offline background refresh on the auth stream', () {
      expect(
        isOfflineAuthRefreshNoise(
          authStateChangesProvider,
          AuthRetryableFetchException(message: offline),
        ),
        isTrue,
      );
    });

    test('keeps the same failure on any other provider', () {
      final other = Provider<int>((_) => 0);
      expect(
        isOfflineAuthRefreshNoise(
          other,
          AuthRetryableFetchException(message: offline),
        ),
        isFalse,
      );
    });

    test('keeps an auth server error (5xx)', () {
      expect(
        isOfflineAuthRefreshNoise(
          authStateChangesProvider,
          AuthRetryableFetchException(message: offline, statusCode: '503'),
        ),
        isFalse,
      );
    });

    test('keeps non-socket failures wrapped as retryable', () {
      const others = [
        'HandshakeException: Handshake error in client',
        'ClientException: Connection closed before full header was received',
        'TimeoutException after 0:00:10.000000',
        'AuthRetryableFetchException',
      ];
      for (final message in others) {
        expect(
          isOfflineAuthRefreshNoise(
            authStateChangesProvider,
            AuthRetryableFetchException(message: message),
          ),
          isFalse,
          reason: message,
        );
      }
    });

    test('keeps any other error type', () {
      expect(
        isOfflineAuthRefreshNoise(
          authStateChangesProvider,
          const AuthException(offline),
        ),
        isFalse,
      );
      expect(
        isOfflineAuthRefreshNoise(authStateChangesProvider, Exception(offline)),
        isFalse,
      );
    });
  });
}
