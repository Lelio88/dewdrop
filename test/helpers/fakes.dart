import 'dart:async';

import 'package:dewdrop/src/features/auth/domain/auth_repository.dart';
import 'package:dewdrop/src/features/groups/domain/group.dart';
import 'package:dewdrop/src/features/groups/domain/group_repository.dart';
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

  String? lastResendEmail;
  Object? resendError;

  @override
  Future<void> resendConfirmation(String email) async {
    if (resendError != null) throw resendError!;
    lastResendEmail = email;
  }
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

  Map<String, dynamic>? savedThoughtStyle;
  bool? savedDefaultAnonymous;
  bool? savedNotificationsEnabled;

  @override
  Future<void> updateThoughtStyle(Map<String, dynamic> thoughtStyle) async {
    savedThoughtStyle = thoughtStyle;
  }

  @override
  Future<void> updateDefaultAnonymous(bool value) async {
    savedDefaultAnonymous = value;
  }

  @override
  Future<void> updateNotificationsEnabled(bool value) async {
    savedNotificationsEnabled = value;
  }

  Map<String, dynamic>? savedProfileUpdate;

  @override
  Future<void> updateProfile({String? displayName, String? handle}) async {
    savedProfileUpdate = {
      'display_name': ?displayName,
      'handle': ?handle,
    };
  }

  @override
  Future<void> updateQuietHours({
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

class FakeGroupRepository implements GroupRepository {
  final _changes = StreamController<int>.broadcast();
  int _tick = 0;
  int myGroupsCalls = 0;
  List<Group> groups = [];
  final List<(String groupId, String userId)> added = [];
  final List<(String groupId, bool anonymous)> sent = [];

  void emitChange() => _changes.add(++_tick);

  @override
  Stream<int> watchChanges() => _changes.stream;

  @override
  Future<List<Group>> myGroups() async {
    myGroupsCalls++;
    return groups;
  }

  @override
  Future<Group> createGroup(String name) async {
    final g = Group(id: 'g-${groups.length}', name: name, creatorId: 'me');
    groups = [...groups, g];
    return g;
  }

  @override
  Future<List<Profile>> members(String groupId) async => const [];

  @override
  Future<void> addMember(String groupId, String userId) async {
    added.add((groupId, userId));
  }

  @override
  Future<void> removeMember(String groupId, String userId) async {}

  @override
  Future<void> leaveGroup(String groupId) async {}

  @override
  Future<void> blockGroup(String groupId) async {}

  @override
  Future<void> deleteGroup(String groupId) async {}

  @override
  Future<int> sendToGroup(String groupId, {bool anonymous = false}) async {
    sent.add((groupId, anonymous));
    return 0;
  }
}
