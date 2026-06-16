/// The sender's notification style — applied to every "pensée" they send.
///
/// Three parts: an optional leading emoji, a phrase template (where `%s` is the
/// sender's name, or « Quelqu'un » when sent anonymously) and an optional
/// trailing emoji. Persisted to `profiles.thought_style` (jsonb) and re-applied
/// server-side by the `send-thought-push` Edge Function, so the recipient sees
/// the sender's styled notification.
///
/// Both emoji slots draw from the same shared list [kThoughtEmojis] (with `''`
/// meaning « none »); phrases come from [kThoughtBodies].
class ThoughtStyle {
  const ThoughtStyle({
    this.lead = '',
    this.body = '%s a pensé à toi',
    this.tail = '✨',
  });

  /// Leading emoji (`''` = none), from [kThoughtEmojis].
  final String lead;

  /// Phrase template containing `%s` (the name placeholder), from [kThoughtBodies].
  final String body;

  /// Trailing emoji (`''` = none), from [kThoughtEmojis].
  final String tail;

  ThoughtStyle copyWith({String? lead, String? body, String? tail}) =>
      ThoughtStyle(
        lead: lead ?? this.lead,
        body: body ?? this.body,
        tail: tail ?? this.tail,
      );

  /// The assembled notification text with [name] substituted for `%s` — used
  /// both for the live preview and (mirrored) by the Edge Function.
  String preview(String name) {
    final phrase = body.replaceFirst('%s', name);
    return [lead, phrase, tail].where((s) => s.isNotEmpty).join(' ');
  }

  factory ThoughtStyle.fromJson(Map<String, dynamic> m) => ThoughtStyle(
    lead: (m['lead'] as String?) ?? '',
    body: (m['body'] as String?) ?? '%s a pensé à toi',
    tail: (m['tail'] as String?) ?? '✨',
  );

  Map<String, dynamic> toJson() => {'lead': lead, 'body': body, 'tail': tail};
}

/// Shared emoji pool for both the leading and trailing slots. `''` = « none ».
const List<String> kThoughtEmojis = [
  '',
  '💭',
  '💗',
  '🌸',
  '✨',
  '☀️',
  '🌙',
  '🍀',
  '💫',
  '💖',
  '🌟',
  '🤍',
  '🫶',
];

/// Phrase templates. `%s` is replaced by the sender's name (or « Quelqu'un »).
const List<String> kThoughtBodies = [
  '%s a pensé à toi',
  '%s pense fort à toi',
  "%s t'envoie une pensée",
  '%s a une pensée pour toi',
  'Une pensée de %s',
];
