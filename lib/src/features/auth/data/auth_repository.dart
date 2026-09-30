import 'package:dewdrop/src/common/deep_links.dart';
import 'package:dewdrop/src/features/auth/data/google_id_token_source.dart';
import 'package:dewdrop/src/features/auth/domain/auth_repository.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:supabase_flutter/supabase_flutter.dart';

/// Thin wrapper over Supabase auth, plus Google sign-in through [_google]
/// (native account picker → ID token → `signInWithIdToken`).
class SupabaseAuthRepository implements AuthRepository {
  SupabaseAuthRepository(this._client, {GoogleIdTokenSource? google})
    : _google = google;

  final SupabaseClient _client;
  final GoogleIdTokenSource? _google;

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
  Future<void> signOut() async {
    // Forget the Google account first, so the next person on this phone gets
    // the picker instead of being signed straight back into this account.
    await _google?.forget();
    await _client.auth.signOut();
  }

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
    await _google?.forget(revoke: true); // withdraw the app's Google grant too
    await _client.auth.signOut();
  }

  @override
  bool get supportsGoogle => _google?.isAvailable ?? false;

  @override
  Future<bool> signInWithGoogle() async {
    final idToken = await _pickGoogleAccount();
    if (idToken == null) return false;
    await _client.auth.signInWithIdToken(
      provider: OAuthProvider.google,
      idToken: idToken,
    );
    return true;
  }

  @override
  GoogleLink? get linkedGoogle => googleLinkOf(_client.auth.currentUser);

  @override
  Future<bool> linkGoogle() async {
    final idToken = await _pickGoogleAccount();
    if (idToken == null) return false;
    await linkThenRefresh(
      link: () => _client.auth.linkIdentityWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
      ),
      refresh: _client.auth.refreshSession,
    );
    return true;
  }

  @override
  Future<void> unlinkGoogle() async {
    final identities = await _client.auth.getUserIdentities();
    final google = identities.where((i) => i.provider == 'google').firstOrNull;
    if (google == null) return;
    if (identities.length < 2) {
      // GoTrue refuses it too; failing here spares a round trip.
      throw const AuthException(
        'Google is the only identity',
        code: 'single_identity_not_deletable',
      );
    }
    await _client.auth.unlinkIdentity(google);
    // unlinkIdentity leaves the cached user stale: refresh so [linkedGoogle]
    // reads the new identities.
    await _client.auth.refreshSession();
    await _google?.forget();
  }

  Future<String?> _pickGoogleAccount() {
    final google = _google;
    if (google == null || !google.isAvailable) {
      throw const AuthException(
        'Google sign-in is not available here',
        code: 'google_sign_in_failed',
      );
    }
    return google.pickAccount();
  }
}

/// The Google account linked to [user], or `null` — read from the identities
/// Supabase returns with the session (no network).
@visibleForTesting
GoogleLink? googleLinkOf(User? user) {
  final identities = user?.identities ?? const <UserIdentity>[];
  final google = identities.where((i) => i.provider == 'google').firstOrNull;
  if (google == null) return null;
  return GoogleLink(
    email: google.identityData?['email'] as String?,
    canUnlink: identities.length > 1,
  );
}

/// Links an identity, then refreshes the session so the new identity shows.
///
/// GoTrue answers a link with the user as it was loaded **before** the link
/// (the identity is inserted, never added to the returned user), and that
/// stale user is what the client saves: without the refresh, [googleLinkOf]
/// still sees no Google and the row keeps offering to link. The refresh
/// reloads the user from the database.
///
/// An identity already linked to the caller (`identity_already_exists` with
/// « Identity is already linked », not « … to another user ») means a stale
/// session hid it: nothing to link, the refresh brings it to light. Any other
/// failure is rethrown, without a refresh.
@visibleForTesting
Future<void> linkThenRefresh({
  required Future<void> Function() link,
  required Future<void> Function() refresh,
}) async {
  try {
    await link();
  } on AuthException catch (e) {
    if (!_isAlreadyLinkedToCaller(e)) rethrow;
  }
  await refresh();
}

bool _isAlreadyLinkedToCaller(AuthException e) =>
    e.code == 'identity_already_exists' &&
    !e.message.toLowerCase().contains('another user');

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
