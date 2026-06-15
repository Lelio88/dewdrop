import 'dart:async';

import 'package:dewdrop/src/features/notifications/data/push_repository.dart';
import 'package:dewdrop/src/features/notifications/domain/push_repository.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final pushRepositoryProvider = Provider<PushRepository>((ref) {
  return FirebasePushRepository(
      FirebaseMessaging.instance, Supabase.instance.client);
});

final pushServiceProvider = Provider<PushService>((ref) {
  final service = PushService(ref.watch(pushRepositoryProvider));
  ref.onDispose(service.dispose);
  return service;
});

/// Keeps this device's FCM token in sync with the signed-in user.
///
/// Wiring: the app (`DewDropApp`) listens to auth changes and calls [register]
/// on sign-in; the home menu calls [unregister] right before sign-out.
/// [register] is idempotent (upsert), so re-emitted auth events are harmless.
class PushService {
  PushService(this._repo);

  final PushRepository _repo;
  StreamSubscription<String>? _refreshSub;
  String? _userId;

  Future<void> register(String userId) async {
    _userId = userId;
    if (!await _repo.requestPermission()) return;
    final token = await _repo.currentToken();
    if (token != null) await _repo.saveToken(userId, token);
    // Keep the row fresh when FCM rotates the token (set up once).
    _refreshSub ??= _repo.tokenRefreshes().listen((t) {
      final uid = _userId;
      if (uid != null) unawaited(_repo.saveToken(uid, t));
    });
  }

  /// Best-effort: drop this device's token before sign-out so a logged-out
  /// account stops receiving "X a pensé à toi".
  Future<void> unregister() async {
    final uid = _userId;
    _userId = null;
    if (uid == null) return;
    final token = await _repo.currentToken();
    if (token == null) return;
    try {
      await _repo.deleteToken(token);
    } on Exception catch (_) {
      // Network/RLS hiccup on logout — not worth blocking sign-out.
    }
  }

  void dispose() {
    unawaited(_refreshSub?.cancel());
  }
}
