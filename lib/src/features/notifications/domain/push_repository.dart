/// Bridges FCM device tokens to the `devices` table. The concrete
/// implementation wraps FirebaseMessaging + Supabase.
///
/// Invariants:
///  - `token` is globally unique in `devices`; [saveToken] upserts on it so a
///    device that changes hands re-points to the current user.
///  - RLS allows writes only where `auth.uid() = user_id`, so [saveToken] and
///    [deleteToken] must run while authenticated. Call [deleteToken] *before*
///    sign-out, never after.
abstract interface class PushRepository {
  /// Asks the OS for notification permission. True when notifications may show.
  Future<bool> requestPermission();
  Future<String?> currentToken();
  Stream<String> tokenRefreshes();
  Future<void> saveToken(String userId, String token);
  Future<void> deleteToken(String token);
}
