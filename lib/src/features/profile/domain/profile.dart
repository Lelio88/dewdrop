import 'package:dewdrop/src/features/profile/domain/sound_prefs.dart';
import 'package:dewdrop/src/features/thoughts/domain/thought_style.dart';

/// A user's public profile + app settings (mirrors `public.profiles`).
class Profile {
  const Profile({
    required this.id,
    this.handle,
    this.displayName,
    this.decor = 'space:0',
    this.renderMode = 'photo',
    this.quietStart,
    this.quietEnd,
    this.quietTz,
    this.defaultAnonymous = false,
    this.notificationsEnabled = true,
    this.soundPrefsRaw = const {},
    this.thoughtStyleRaw = const {},
  });

  final String id;
  final String? handle;
  final String? displayName;
  final String decor; // "<environment>:<variant>"
  final String renderMode; // 'drawn' | 'photo'
  final int? quietStart;
  final int? quietEnd;
  final String? quietTz; // IANA timezone for evaluating quiet hours locally
  final bool defaultAnonymous;
  final bool notificationsEnabled; // master push switch
  final Map<String, dynamic>
  soundPrefsRaw; // per-decor soundscape customization
  final Map<String, dynamic> thoughtStyleRaw; // sent-notification style

  bool get hasHandle => handle != null && handle!.trim().isNotEmpty;

  /// Parsed per-decor soundscape customization.
  SoundPrefs get soundPrefs => SoundPrefs.fromJson(soundPrefsRaw);

  /// Parsed style applied to the notifications this user sends.
  ThoughtStyle get thoughtStyle => ThoughtStyle.fromJson(thoughtStyleRaw);

  factory Profile.fromMap(Map<String, dynamic> m) => Profile(
    id: m['id'] as String,
    handle: m['handle'] as String?,
    displayName: m['display_name'] as String?,
    decor: (m['decor'] as String?) ?? 'space:0',
    renderMode: (m['render_mode'] as String?) ?? 'photo',
    quietStart: m['quiet_start'] as int?,
    quietEnd: m['quiet_end'] as int?,
    quietTz: m['quiet_tz'] as String?,
    defaultAnonymous: (m['default_anonymous'] as bool?) ?? false,
    notificationsEnabled: (m['notifications_enabled'] as bool?) ?? true,
    soundPrefsRaw:
        (m['sound_prefs'] as Map?)?.cast<String, dynamic>() ?? const {},
    thoughtStyleRaw:
        (m['thought_style'] as Map?)?.cast<String, dynamic>() ?? const {},
  );
}
