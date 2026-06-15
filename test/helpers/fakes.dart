import 'package:dewdrop/src/features/auth/domain/auth_repository.dart';
import 'package:dewdrop/src/features/profile/domain/profile.dart';
import 'package:dewdrop/src/features/profile/domain/profile_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Hand-written fakes (preferred over mocks) — made possible by the repos now
/// being domain interfaces injected at the provider boundary.

class FakeAuthRepository implements AuthRepository {
  Object? signInError;
  Object? signUpError;
  int signInCount = 0;

  @override
  Session? get currentSession => null;
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
  Future<void> signUp(String email, String password) async {
    if (signUpError != null) throw signUpError!;
  }

  @override
  Future<void> signOut() async {}
}

class FakeProfileRepository implements ProfileRepository {
  Profile? profile;
  Map<String, dynamic>? savedSoundPrefs;

  @override
  Future<Profile?> getMyProfile() async => profile;
  @override
  Future<bool> isHandleAvailable(String handle) async => true;
  @override
  Future<void> setHandle(String handle, {String? displayName}) async {}
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
