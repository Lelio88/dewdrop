/// A shared "circle": a named group the [creatorId] owns and whose members can
/// each send a pensée to everyone in it. Mirrors `public.groups`.
class Group {
  const Group({
    required this.id,
    required this.name,
    required this.creatorId,
  });

  final String id;
  final String name;
  final String creatorId;

  /// True when [uid] owns this group (can add/remove members, rename, delete).
  bool isCreator(String uid) => creatorId == uid;

  factory Group.fromMap(Map<String, dynamic> m) => Group(
    id: m['id'] as String,
    name: m['name'] as String,
    creatorId: m['creator_id'] as String,
  );
}
