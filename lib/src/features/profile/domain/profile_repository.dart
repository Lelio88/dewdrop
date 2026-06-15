import 'package:dewdrop/src/features/profile/domain/profile.dart';

/// The signed-in user's profile boundary (Supabase `profiles` behind it).
abstract interface class ProfileRepository {
  Future<Profile?> getMyProfile();
  Future<bool> isHandleAvailable(String handle);
  Future<void> setHandle(String handle, {String? displayName});
  Future<void> updateDecor(String decor, String renderMode);

  /// Persists the per-decor soundscape customization (synced across devices).
  Future<void> updateSoundPrefs(Map<String, dynamic> soundPrefs);

  Future<void> updateSettings({
    required bool defaultAnonymous,
    int? quietStart,
    int? quietEnd,
    String? quietTz,
  });
}
