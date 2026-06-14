import 'dart:io' show Platform;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Bridges FCM device tokens to the `devices` table.
///
/// The push Edge Function (`send-thought-push`) reads a recipient's rows from
/// `devices` to deliver "X a pensé à toi". This repo is the only client-side
/// writer of that table.
///
/// Invariants:
///  - `token` is globally unique in `devices`; [saveToken] upserts on it so a
///    device that changes hands re-points to the current user.
///  - RLS allows writes only where `auth.uid() = user_id`, so [saveToken] and
///    [deleteToken] must run while the user is authenticated. Call [deleteToken]
///    *before* sign-out, never after.
class PushRepository {
  PushRepository(this._messaging, this._client);

  final FirebaseMessaging _messaging;
  final SupabaseClient _client;

  static String get _platform =>
      Platform.isAndroid ? 'android' : (Platform.isIOS ? 'ios' : 'web');

  /// Asks the OS for notification permission (Android 13+ system dialog / iOS
  /// prompt). Returns true when notifications may be shown.
  Future<bool> requestPermission() async {
    final settings = await _messaging.requestPermission();
    final status = settings.authorizationStatus;
    return status == AuthorizationStatus.authorized ||
        status == AuthorizationStatus.provisional;
  }

  Future<String?> currentToken() => _messaging.getToken();

  Stream<String> tokenRefreshes() => _messaging.onTokenRefresh;

  /// Upserts the FCM [token] for [userId]. Conflict target is the unique
  /// `token` column so re-registration is idempotent.
  Future<void> saveToken(String userId, String token) =>
      _client.from('devices').upsert(
        {'user_id': userId, 'token': token, 'platform': _platform},
        onConflict: 'token',
      );

  /// Removes this device's [token] so a signed-out account stops receiving
  /// pushes. Must be called while still authenticated (RLS).
  Future<void> deleteToken(String token) =>
      _client.from('devices').delete().eq('token', token);
}
