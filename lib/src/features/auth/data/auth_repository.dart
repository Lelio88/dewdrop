import 'package:dewdrop/src/common/deep_links.dart';
import 'package:dewdrop/src/features/auth/domain/auth_repository.dart';
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
  Future<bool> signUp(String email, String password) async {
    final res = await _client.auth.signUp(
      email: email,
      password: password,
      // When confirmation is on, the email's link redirects here; the custom
      // scheme reopens the app and supabase_flutter exchanges the PKCE code,
      // signing the user in. Must be allow-listed in Supabase auth config.
      emailRedirectTo: DeepLinks.loginCallback,
    );
    // No session means email confirmation is required before signing in.
    return res.session == null;
  }

  @override
  Future<void> signIn(String email, String password) =>
      _client.auth.signInWithPassword(email: email, password: password);

  @override
  Future<void> signOut() => _client.auth.signOut();

  @override
  Future<void> sendPasswordReset(String email) =>
      _client.auth.resetPasswordForEmail(
        email,
        redirectTo: DeepLinks.resetPassword,
      );

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
