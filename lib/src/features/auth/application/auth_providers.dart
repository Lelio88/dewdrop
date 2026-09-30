import 'package:dewdrop/src/features/auth/data/auth_repository.dart';
import 'package:dewdrop/src/features/auth/data/google_id_token_source.dart';
import 'package:dewdrop/src/features/auth/domain/auth_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return SupabaseAuthRepository(
    Supabase.instance.client,
    google: NativeGoogleIdTokenSource(serverClientId: kGoogleWebClientId),
  );
});

/// Emits whenever the user signs in or out.
final authStateChangesProvider = StreamProvider<AuthState>((ref) {
  return ref.watch(authRepositoryProvider).authStateChanges();
});

/// True only for the failure gotrue pushes into [authStateChangesProvider] on
/// every background token-refresh tick (~10 s) while the phone has no network.
/// `ProviderErrorLogger` skips its Crashlytics report for it — otherwise one
/// offline phone files a non-fatal every tick.
///
/// Deliberately as narrow as possible — ALL three must hold:
/// - the provider is [authStateChangesProvider] (a sign-in or any other call
///   failing the same way is still reported);
/// - no `statusCode`: gotrue also throws `AuthRetryableFetchException` for an
///   auth server 5xx — an outage must stay visible;
/// - the message starts with package:http's socket-failure wrapper
///   (`ClientException with SocketException`, io_client.dart). gotrue's
///   catch-all turns ANY fetch failure (TLS, unexpected bug) into the same
///   type and keeps only `toString()`, so the prefix is the only signal left.
bool isOfflineAuthRefreshNoise(Object provider, Object error) =>
    identical(provider, authStateChangesProvider) &&
    error is AuthRetryableFetchException &&
    error.statusCode == null &&
    error.message.startsWith(_kSocketFailurePrefix);

const _kSocketFailurePrefix = 'ClientException with SocketException';
