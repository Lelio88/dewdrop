import 'package:supabase_flutter/supabase_flutter.dart';

/// Authentication boundary. The concrete implementation wraps Supabase Auth.
///
/// Note: the session/user/auth-state types are Supabase's — auth is
/// intentionally coupled to its session model, so the interface re-exposes them
/// rather than re-mapping to bespoke domain types.
abstract interface class AuthRepository {
  Session? get currentSession;
  User? get currentUser;
  Stream<AuthState> authStateChanges();

  /// Signs up. Returns `true` when the account still needs to confirm its email
  /// before it can sign in (no active session yet); `false` when it's signed in
  /// immediately (email confirmation disabled).
  Future<bool> signUp(String email, String password);
  Future<void> signIn(String email, String password);
  Future<void> signOut();

  /// Re-sends the sign-up confirmation email to [email] (for someone who didn't
  /// receive it). Rate-limited by Supabase.
  Future<void> resendConfirmation(String email);

  /// Sends a password-reset email. The link opens the app in recovery mode
  /// (a temporary session), where [updatePassword] can be called.
  Future<void> sendPasswordReset(String email);

  /// Sets a new password for the current (recovery or signed-in) session.
  Future<void> updatePassword(String newPassword);

  /// Deletes the current user's account and all their data (profile,
  /// friendships, thoughts, devices via FK cascade), then signs out. Backed by
  /// the `delete-account` Edge Function (only the service role can do this).
  Future<void> deleteAccount();
}
