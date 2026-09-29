import 'package:dewdrop/src/common/deep_links.dart';
import 'package:dewdrop/src/features/auth/domain/auth_repository.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:supabase_flutter/supabase_flutter.dart';

/// Thin wrapper over Supabase auth.
class SupabaseAuthRepository implements AuthRepository {
  SupabaseAuthRepository(this._client);

  final SupabaseClient _client;

  @override
  Session? get currentSession => _client.auth.currentSession;

  @override
  User? get currentUser => _client.auth.currentUser;

  @override
  Stream<AuthState> authStateChanges() => _client.auth.onAuthStateChange;

  @override
  Future<bool> signUp(String email, String password) => blindSignUp(
    () => _client.auth.signUp(
      email: email,
      password: password,
      // When confirmation is on, the email's link redirects here; the custom
      // scheme reopens the app and supabase_flutter exchanges the PKCE code,
      // signing the user in. Must be allow-listed in Supabase auth config.
      emailRedirectTo: DeepLinks.loginCallback,
    ),
  );

  @override
  Future<void> signIn(String email, String password) =>
      _client.auth.signInWithPassword(email: email, password: password);

  @override
  Future<void> signOut() => _client.auth.signOut();

  @override
  Future<void> resendConfirmation(String email) => _client.auth.resend(
    type: OtpType.signup,
    email: email,
    emailRedirectTo: DeepLinks.loginCallback,
  );

  @override
  Future<void> sendPasswordReset(String email) => _client.auth
      .resetPasswordForEmail(email, redirectTo: DeepLinks.resetPassword);

  @override
  Future<void> updatePassword(String newPassword) =>
      _client.auth.updateUser(UserAttributes(password: newPassword));

  @override
  Future<void> deleteAccount() async {
    // The Edge Function deletes the auth user (cascades to all their data);
    // invoke() forwards the current session's JWT so it deletes only the caller.
    await _client.functions.invoke('delete-account');
    await _client.auth.signOut();
  }
}

/// Runs a sign-up and answers whether it now awaits the confirmation email,
/// **without ever revealing that the address was already registered**
/// (conformity guide C2 — otherwise the form tells anyone which emails have an
/// account).
///
/// With confirmation on, GoTrue answers a confirmed duplicate with an
/// obfuscated user (no identity, no session) and sends no email; an
/// unconfirmed one gets its confirmation email again. Both read here as a new
/// account: no session, so « Vérifie tes emails ». That screen also points an
/// existing holder to sign-in and « Mot de passe oublié », so nobody is stuck.
/// A server that reports the duplicate outright (`user_already_exists`, only
/// when confirmation is off) is answered the same way. Never re-add an
/// `identities.isEmpty` check that turns the duplicate into an error.
@visibleForTesting
Future<bool> blindSignUp(Future<AuthResponse> Function() signUp) async {
  try {
    // No session means email confirmation is required before signing in.
    return (await signUp()).session == null;
  } on AuthException catch (e) {
    if (e.code == 'user_already_exists') return true;
    rethrow;
  }
}
