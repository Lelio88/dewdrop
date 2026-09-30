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

  // ── Google ──────────────────────────────────────────────────────────────

  /// Whether this device can show Google's native account picker (Android and
  /// iOS builds carrying the Google client id). The UI hides every Google
  /// action when it can't.
  bool get supportsGoogle;

  /// Signs in with the Google account the user picks. The first time, this
  /// creates the DewDrop account (then onboarding asks for a @handle, as for
  /// an email sign-up); if an account already uses the same **verified**
  /// email, Supabase joins them instead (automatic identity linking).
  /// Resolves `false` when the user dismisses the picker — not an error.
  Future<bool> signInWithGoogle();

  /// The Google account linked to the signed-in user, or `null`.
  GoogleLink? get linkedGoogle;

  /// Links the Google account the user picks to the signed-in user, whatever
  /// its email (manual linking). Resolves `false` when dismissed. Fails with
  /// `identity_already_exists` if that Google account belongs to another user.
  Future<bool> linkGoogle();

  /// Unlinks Google. Refused (`single_identity_not_deletable`) when it is the
  /// account's only way to sign in — the UI never offers it then.
  Future<void> unlinkGoogle();
}

/// A Google account linked to the signed-in user.
class GoogleLink {
  const GoogleLink({required this.email, required this.canUnlink});

  /// The Google account's address (may differ from the DewDrop email).
  final String? email;

  /// Whether another way to sign in remains once Google is unlinked.
  final bool canUnlink;
}
