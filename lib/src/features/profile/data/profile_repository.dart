import 'package:dewdrop/src/features/profile/domain/profile.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ProfileRepository {
  ProfileRepository(this._client);

  final SupabaseClient _client;

  Future<Profile?> getMyProfile() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return null;
    final data =
        await _client.from('profiles').select().eq('id', uid).maybeSingle();
    return data == null ? null : Profile.fromMap(data);
  }

  Future<bool> isHandleAvailable(String handle) async {
    final res = await _client
        .from('profiles')
        .select('id')
        .eq('handle', handle)
        .maybeSingle();
    return res == null;
  }

  Future<void> setHandle(String handle, {String? displayName}) async {
    final uid = _client.auth.currentUser!.id;
    await _client.from('profiles').update({
      'handle': handle,
      if (displayName != null && displayName.isNotEmpty)
        'display_name': displayName,
    }).eq('id', uid);
  }

  Future<void> updateDecor(String decor, String renderMode) async {
    final uid = _client.auth.currentUser!.id;
    await _client
        .from('profiles')
        .update({'decor': decor, 'render_mode': renderMode})
        .eq('id', uid);
  }

  /// Persists the per-decor soundscape customization (synced across devices).
  Future<void> updateSoundPrefs(Map<String, dynamic> soundPrefs) async {
    final uid = _client.auth.currentUser!.id;
    await _client
        .from('profiles')
        .update({'sound_prefs': soundPrefs})
        .eq('id', uid);
  }

  /// Quiet hours are hours 0-23 (null = disabled). [quietTz] is the user's IANA
  /// timezone, so the push function evaluates the window in local time.
  Future<void> updateSettings({
    required bool defaultAnonymous,
    int? quietStart,
    int? quietEnd,
    String? quietTz,
  }) async {
    final uid = _client.auth.currentUser!.id;
    await _client.from('profiles').update({
      'default_anonymous': defaultAnonymous,
      'quiet_start': quietStart,
      'quiet_end': quietEnd,
      'quiet_tz': quietTz,
    }).eq('id', uid);
  }
}
