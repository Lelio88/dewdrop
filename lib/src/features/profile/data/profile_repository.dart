import 'package:dewdrop/src/features/profile/domain/profile.dart';
import 'package:dewdrop/src/features/profile/domain/profile_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseProfileRepository implements ProfileRepository {
  SupabaseProfileRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<Profile?> getMyProfile() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return null;
    final data = await _client
        .from('profiles')
        .select()
        .eq('id', uid)
        .maybeSingle();
    return data == null ? null : Profile.fromMap(data);
  }

  @override
  Future<bool> isHandleAvailable(String handle) async {
    // Checked against the directory view (profiles is owner-only); the unique
    // constraint on profiles.handle is the real guard against a TOCTOU race.
    final res = await _client
        .from('public_profiles')
        .select('id')
        .eq('handle', handle)
        .maybeSingle();
    return res == null;
  }

  @override
  Future<void> setHandle(String handle, {String? displayName}) async {
    final uid = _client.auth.currentUser!.id;
    await _client
        .from('profiles')
        .update({
          'handle': handle,
          if (displayName != null && displayName.isNotEmpty)
            'display_name': displayName,
        })
        .eq('id', uid);
  }

  @override
  Future<void> updateProfile({String? displayName, String? handle}) async {
    final uid = _client.auth.currentUser!.id;
    final patch = <String, dynamic>{
      'display_name': ?displayName,
      'handle': ?handle,
    };
    if (patch.isEmpty) return;
    await _client.from('profiles').update(patch).eq('id', uid);
  }

  @override
  Future<void> updateDecor(String decor, String renderMode) async {
    final uid = _client.auth.currentUser!.id;
    await _client
        .from('profiles')
        .update({'decor': decor, 'render_mode': renderMode})
        .eq('id', uid);
  }

  @override
  Future<void> updateSoundPrefs(Map<String, dynamic> soundPrefs) async {
    final uid = _client.auth.currentUser!.id;
    await _client
        .from('profiles')
        .update({'sound_prefs': soundPrefs})
        .eq('id', uid);
  }

  @override
  Future<void> updateThoughtStyle(Map<String, dynamic> thoughtStyle) async {
    final uid = _client.auth.currentUser!.id;
    await _client
        .from('profiles')
        .update({'thought_style': thoughtStyle})
        .eq('id', uid);
  }

  @override
  Future<void> updateThoughtPresets(List<Map<String, dynamic>> presets) async {
    final uid = _client.auth.currentUser!.id;
    await _client
        .from('profiles')
        .update({'thought_presets': presets})
        .eq('id', uid);
  }

  @override
  Future<void> updateWidgetSource(String source) async {
    final uid = _client.auth.currentUser!.id;
    await _client
        .from('profiles')
        .update({'widget_source': source})
        .eq('id', uid);
  }

  @override
  Future<void> updateWidgetFriends(List<String> friendIds) async {
    final uid = _client.auth.currentUser!.id;
    await _client
        .from('profiles')
        .update({'widget_friends': friendIds})
        .eq('id', uid);
  }

  @override
  Future<void> updateDecorFavorites(List<String> favorites) async {
    final uid = _client.auth.currentUser!.id;
    await _client
        .from('profiles')
        .update({'decor_favorites': favorites})
        .eq('id', uid);
  }

  @override
  Future<void> updateDefaultAnonymous(bool value) async {
    final uid = _client.auth.currentUser!.id;
    await _client
        .from('profiles')
        .update({'default_anonymous': value})
        .eq('id', uid);
  }

  @override
  Future<void> updateNotificationsEnabled(bool value) async {
    final uid = _client.auth.currentUser!.id;
    await _client
        .from('profiles')
        .update({'notifications_enabled': value})
        .eq('id', uid);
  }

  @override
  Future<void> updateQuietHours({
    int? quietStart,
    int? quietEnd,
    String? quietTz,
  }) async {
    final uid = _client.auth.currentUser!.id;
    await _client
        .from('profiles')
        .update({
          'quiet_start': quietStart,
          'quiet_end': quietEnd,
          'quiet_tz': quietTz,
        })
        .eq('id', uid);
  }
}
