import 'package:dewdrop/src/features/profile/domain/profile.dart';

/// The signed-in user's profile boundary (Supabase `profiles` behind it).
abstract interface class ProfileRepository {
  Future<Profile?> getMyProfile();
  Future<bool> isHandleAvailable(String handle);
  Future<void> setHandle(String handle, {String? displayName});
  Future<void> updateDecor(String decor, String renderMode);

  /// Persists the per-decor soundscape customization (synced across devices).
  Future<void> updateSoundPrefs(Map<String, dynamic> soundPrefs);

  /// Persists the style applied to the notifications this user sends.
  Future<void> updateThoughtStyle(Map<String, dynamic> thoughtStyle);

  /// Default for the per-send "anonymous" toggle.
  Future<void> updateDefaultAnonymous(bool value);

  /// Quiet hours are hours 0-23 (null = disabled); [quietTz] is the user's IANA
  /// timezone so the push function evaluates the window in local time.
  Future<void> updateQuietHours({
    int? quietStart,
    int? quietEnd,
    String? quietTz,
  });
}
