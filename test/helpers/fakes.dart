import 'dart:async';

import 'package:dewdrop/src/features/auth/domain/auth_repository.dart';
import 'package:dewdrop/src/features/notifications/domain/push_repository.dart';
import 'package:dewdrop/src/features/profile/domain/profile.dart';
import 'package:dewdrop/src/features/profile/domain/profile_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Hand-written fakes (preferred over mocks) — made possible by the repos now
/// being domain interfaces injected at the provider boundary.

class FakeAuthRepository implements AuthRepository {
  Object? signInError;
  Object? signUpError;
  int signInCount = 0;
  bool signUpNeedsConfirm = false;
  String? lastResetEmail;
  String? lastUpdatedPassword;

  /// Set to simulate a signed-in user (gates the friends/thoughts providers).
  Session? session;

  @override
  Session? get currentSession => session;
  @override
  User? get currentUser => null;
  @override
  Stream<AuthState> authStateChanges() => const Stream.empty();

  @override
  Future<void> signIn(String email, String password) async {
    signInCount++;
    if (signInError != null) throw signInError!;
  }

  @override
  Future<bool> signUp(String email, String password) async {
    if (signUpError != null) throw signUpError!;
    return signUpNeedsConfirm;
  }

  @override
  Future<void> signOut() async {}

  @override
  Future<void> sendPasswordReset(String email) async {
    lastResetEmail = email;
  }

  @override
  Future<void> updatePassword(String newPassword) async {
    lastUpdatedPassword = newPassword;
  }

  @override
  Future<void> deleteAccount() async {}
}

class FakeProfileRepository implements ProfileRepository {
  Profile? profile;
  Map<String, dynamic>? savedSoundPrefs;
  bool handleAvailable = true;
  String? lastSetHandle;

  @override
  Future<Profile?> getMyProfile() async => profile;
  @override
  Future<bool> isHandleAvailable(String handle) async => handleAvailable;
  @override
  Future<void> setHandle(String handle, {String? displayName}) async {
    lastSetHandle = handle;
  }

  @override
  Future<void> updateDecor(String decor, String renderMode) async {}
  @override
  Future<void> updateSoundPrefs(Map<String, dynamic> soundPrefs) async {
    savedSoundPrefs = soundPrefs;
  }

  @override
  Future<void> updateSettings({
    required bool defaultAnonymous,
    int? quietStart,
    int? quietEnd,
    String? quietTz,
  }) async {}
}

class FakePushRepository implements PushRepository {
  bool permission = true;
  String? token = 'tok-1';
  final List<(String userId, String token)> saved = [];
  final List<String> deleted = [];
  final _refreshes = StreamController<String>.broadcast();

  @override
  Future<bool> requestPermission() async => permission;
  @override
  Future<String?> currentToken() async => token;
  @override
  Stream<String> tokenRefreshes() => _refreshes.stream;
  @override
  Future<void> saveToken(String userId, String token) async {
    saved.add((userId, token));
  }

  @override
  Future<void> deleteToken(String token) async {
    deleted.add(token);
  }

  void emitRefresh(String t) => _refreshes.add(t);
  Future<void> dispose() => _refreshes.close();
}
