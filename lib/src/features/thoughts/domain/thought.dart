import 'package:dewdrop/src/features/profile/domain/profile.dart';

/// A thought received by the current user. [sender] is null when anonymous.
///
/// A pensée sent to a group is fanned out by `send_to_group` into one row per
/// member, so each recipient still sees exactly one [ReceivedThought] — it just
/// carries [groupId] as well. [groupName] is resolved **at display time** from
/// `groups` (never stored on the row): a renamed group reads with its new name,
/// and a group we have left since resolves to null instead of a stale name.
class ReceivedThought {
  const ReceivedThought({
    required this.id,
    required this.createdAt,
    required this.isAnonymous,
    this.sender,
    this.groupId,
    this.groupName,
  });

  final String id;
  final DateTime createdAt;
  final bool isAnonymous;
  final Profile? sender;

  /// Non-null when this pensée was addressed to a whole group.
  final String? groupId;

  /// The group's current name, or null when it can no longer be read (we left
  /// the group since — RLS "see my groups" only returns groups we belong to).
  final String? groupName;

  bool get isGroup => groupId != null;
}

/// Who sent [t], as shown to the recipient: "Quelqu'un" when anonymous, else
/// the display name, else the @handle. Never leaks an anonymous sender — the
/// mapping already dropped the profile, this only formats what is left.
String senderLabel(ReceivedThought t) {
  if (t.isAnonymous) return "Quelqu'un";
  final name = t.sender?.displayName;
  if (name != null && name.isNotEmpty) return name;
  return '@${t.sender?.handle ?? '?'}';
}

/// The single line shown for a received pensée. Kept here (pure, tested) rather
/// than in each screen because the received list and the home peek MUST word it
/// identically — a group pensée that reads like a personal one is exactly the
/// bug this sentence exists to prevent.
///
/// ```dart
/// thoughtLine(t); // "Lazare a pensé au groupe « Famille »"
/// ```
String thoughtLine(ReceivedThought t) {
  final who = senderLabel(t);
  if (!t.isGroup) return '$who a pensé à toi';
  final group = t.groupName;
  // No name resolved → we are no longer a member. Say so plainly rather than
  // pass the pensée off as a personal one.
  if (group == null || group.isEmpty) return '$who a pensé à un groupe';
  return '$who a pensé au groupe « $group »';
}
