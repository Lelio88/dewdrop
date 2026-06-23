import 'package:dewdrop/src/features/thoughts/domain/thought_style.dart';

/// A named, saved [ThoughtStyle] trio (leading emoji · phrase · trailing emoji)
/// the user can re-apply to their sent notifications in a single tap.
///
/// Presets are a **pure client-side convenience**: only the *active* style is
/// read server-side (`profiles.thought_style`, applied by `send-thought-push`).
/// The list lives in `profiles.thought_presets` (jsonb array) and is capped at
/// [kMaxThoughtPresets] — the save flow refuses beyond that and alerts the user.
///
/// Example:
/// ```dart
/// final p = ThoughtPreset(name: 'Bonjour', style: ThoughtStyle(lead: '☀️', body: '%s a pensé à toi', tail: '🌸'));
/// final json = p.toJson(); // {name: 'Bonjour', style: {lead: '☀️', ...}}
/// ```
class ThoughtPreset {
  const ThoughtPreset({required this.name, required this.style});

  /// User-facing label (trimmed, never empty — falls back to « Sans nom »).
  final String name;

  /// The saved trio applied when this preset is tapped.
  final ThoughtStyle style;

  factory ThoughtPreset.fromJson(Map<String, dynamic> m) {
    final raw = (m['name'] as String?)?.trim() ?? '';
    return ThoughtPreset(
      name: raw.isEmpty ? 'Sans nom' : raw,
      style: ThoughtStyle.fromJson(
        (m['style'] as Map?)?.cast<String, dynamic>() ?? const {},
      ),
    );
  }

  Map<String, dynamic> toJson() => {'name': name, 'style': style.toJson()};
}

/// Max presets a user may keep. The save flow checks this before prompting for a
/// name and shows an alert when the list is already full.
const int kMaxThoughtPresets = 5;
