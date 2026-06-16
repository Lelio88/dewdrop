import 'dart:io' show Platform;

import 'package:dewdrop/src/features/notifications/domain/push_repository.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Bridges FCM device tokens to the `devices` table (FirebaseMessaging +
/// Supabase). The push Edge Function (`send-thought-push`) reads a recipient's
/// rows from `devices` to deliver "X a pensé à toi"; this is the only
/// client-side writer of that table. See [PushRepository] for the invariants.
class FirebasePushRepository implements PushRepository {
  FirebasePushRepository(this._messaging, this._client);

  final FirebaseMessaging _messaging;
  final SupabaseClient _client;

  static String get _platform =>
      Platform.isAndroid ? 'android' : (Platform.isIOS ? 'ios' : 'web');

  @override
  Future<bool> requestPermission() async {
    final settings = await _messaging.requestPermission();
    final status = settings.authorizationStatus;
    return status == AuthorizationStatus.authorized ||
        status == AuthorizationStatus.provisional;
  }

  @override
  Future<String?> currentToken() => _messaging.getToken();

  @override
  Stream<String> tokenRefreshes() => _messaging.onTokenRefresh;

  /// Upserts the FCM [token] for [userId]. Conflict target is the unique
  /// `token` column so re-registration is idempotent.
  @override
  Future<void> saveToken(String userId, String token) =>
      _client.from('devices').upsert({
        'user_id': userId,
        'token': token,
        'platform': _platform,
      }, onConflict: 'token');

  /// Removes this device's [token] so a signed-out account stops receiving
  /// pushes. Must be called while still authenticated (RLS).
  @override
  Future<void> deleteToken(String token) =>
      _client.from('devices').delete().eq('token', token);
}
