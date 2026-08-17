import 'package:dewdrop/src/features/auth/application/auth_providers.dart';
import 'package:dewdrop/src/features/friends/application/friend_providers.dart';
import 'package:dewdrop/src/features/friends/domain/friend.dart';
import 'package:dewdrop/src/features/groups/application/group_providers.dart';
import 'package:dewdrop/src/features/groups/domain/group.dart';
import 'package:dewdrop/src/features/profile/domain/profile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Manage a group: see members, and — for the creator — add (from friends) or
/// remove members and delete the group; for a plain member, leave or block it.
///
/// A group is also where you meet friends-of-friends: any member you aren't
/// already friends with can be sent a friend request from here. That needs no
/// new privilege — the `send friend request` policy already allows a request
/// toward anyone who hasn't blocked you, and members are readable to each
/// other — so this is a UI affordance over rules that were always there.
class GroupScreen extends ConsumerStatefulWidget {
  const GroupScreen({super.key, required this.group});

  final Group group;

  @override
  ConsumerState<GroupScreen> createState() => _GroupScreenState();
}

class _GroupScreenState extends ConsumerState<GroupScreen> {
  /// Members this session has sent a request to — turns the button into a spent
  /// "envoyée" state. Session-local on purpose: requests already pending from a
  /// previous visit aren't fetched, so tapping one simply surfaces the
  /// repository's "Une demande est déjà en cours." message.
  final Set<String> _requested = {};

  Group get group => widget.group;

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _addFriend(Profile p) async {
    setState(() => _requested.add(p.id));
    try {
      await ref.read(friendRepositoryProvider).sendRequestTo(p.id);
      _snack('Demande envoyée à @${p.handle} ✨');
    } on FriendException catch (e) {
      if (mounted) setState(() => _requested.remove(p.id));
      _snack(e.message);
    } on Exception catch (_) {
      if (mounted) setState(() => _requested.remove(p.id));
      _snack('Action impossible pour le moment.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final w = Colors.white;
    final uid = ref.watch(authRepositoryProvider).currentUser?.id ?? '';
    final isCreator = group.isCreator(uid);
    final members = ref.watch(groupMembersProvider(group.id));
    // Null until the friends list has loaded — the "ajouter en ami" button
    // stays hidden meanwhile rather than offering to add an existing friend.
    final friendIds = ref
        .watch(friendsProvider)
        .value
        ?.map((f) => f.profile.id)
        .toSet();

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(group.name),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF12162A), Color(0xFF06070E)],
          ),
        ),
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
            children: [
              Text(
                isCreator
                    ? 'Tu gères ce groupe : ajoute ou retire des membres parmi tes amis.'
                    : 'Tout membre peut envoyer une pensée au groupe.',
                style: TextStyle(
                  color: w.withValues(alpha: 0.55),
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 16),
              _section(w, 'Membres'),
              members.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white54,
                      ),
                    ),
                  ),
                ),
                error: (_, _) => _hint(w, 'Impossible de charger les membres.'),
                data: (list) => Column(
                  children: [
                    for (final p in list)
                      _memberTile(w, p, uid, isCreator, friendIds),
                  ],
                ),
              ),
              if (isCreator) ...[
                const SizedBox(height: 8),
                _actionTile(
                  w,
                  icon: Icons.person_add_alt_1,
                  label: 'Ajouter un ami',
                  onTap: () => _addMembers(members.value ?? []),
                ),
              ],
              const SizedBox(height: 28),
              if (isCreator)
                _danger(
                  w,
                  icon: Icons.delete_outline,
                  label: 'Supprimer le groupe',
                  onTap: _deleteGroup,
                )
              else ...[
                _danger(
                  w,
                  icon: Icons.logout_rounded,
                  label: 'Quitter le groupe',
                  onTap: () => _leave(block: false),
                ),
                _danger(
                  w,
                  icon: Icons.block,
                  label: 'Bloquer le groupe',
                  onTap: () => _leave(block: true),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _memberTile(
    Color w,
    Profile p,
    String uid,
    bool isCreator,
    Set<String>? friendIds,
  ) {
    final name = p.displayName?.isNotEmpty == true
        ? p.displayName!
        : '@${p.handle}';
    final isSelf = p.id == uid;
    final isOwner = group.isCreator(p.id);
    // Offer friendship to fellow members only once we KNOW they aren't already
    // friends (friendIds still null = list loading).
    final canBefriend =
        !isSelf && friendIds != null && !friendIds.contains(p.id);
    final requested = _requested.contains(p.id);

    final actions = <Widget>[
      if (canBefriend)
        IconButton(
          icon: Icon(
            requested ? Icons.hourglass_bottom_rounded : Icons.person_add_alt_1,
            color: requested
                ? w.withValues(alpha: 0.4)
                : const Color(0xFF8FE3A8),
          ),
          tooltip: requested ? 'Demande envoyée' : 'Ajouter en ami',
          onPressed: requested ? null : () => _addFriend(p),
        ),
      // The creator can remove anyone but themselves.
      if (isCreator && !isSelf)
        IconButton(
          icon: Icon(
            Icons.remove_circle_outline,
            color: w.withValues(alpha: 0.5),
          ),
          tooltip: 'Retirer du groupe',
          onPressed: () async {
            await ref
                .read(groupRepositoryProvider)
                .removeMember(group.id, p.id);
            ref.invalidate(groupMembersProvider(group.id));
          },
        ),
    ];

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 6),
      leading: CircleAvatar(
        backgroundColor: w.withValues(alpha: 0.14),
        child: Text(
          name.isEmpty ? '?' : name[0].toUpperCase(),
          style: TextStyle(color: w),
        ),
      ),
      title: Text(isSelf ? '$name (toi)' : name),
      subtitle: Text(
        isOwner ? 'Créateur' : '@${p.handle}',
        style: TextStyle(color: w.withValues(alpha: 0.5)),
      ),
      trailing: actions.isEmpty
          ? null
          : Row(mainAxisSize: MainAxisSize.min, children: actions),
    );
  }

  /// Sheet listing friends not already in the group; tap to add.
  Future<void> _addMembers(List<Profile> current) async {
    final memberIds = {for (final p in current) p.id};
    final friends = ref.read(friendsProvider).value ?? [];
    final addable = [
      for (final f in friends)
        if (!memberIds.contains(f.profile.id)) f.profile,
    ];
    if (addable.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tous tes amis sont déjà dans le groupe.'),
        ),
      );
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF12162A),
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Ajouter au groupe',
                style: TextStyle(color: Colors.white70),
              ),
            ),
            for (final p in addable)
              ListTile(
                leading: const Icon(
                  Icons.person_add_alt_1,
                  color: Colors.white70,
                ),
                title: Text(
                  p.displayName?.isNotEmpty == true
                      ? p.displayName!
                      : '@${p.handle}',
                  style: const TextStyle(color: Colors.white),
                ),
                onTap: () async {
                  Navigator.pop(ctx);
                  await ref
                      .read(groupRepositoryProvider)
                      .addMember(group.id, p.id);
                  ref.invalidate(groupMembersProvider(group.id));
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteGroup() async {
    final ok = await _confirm(
      'Supprimer le groupe ?',
      'Le groupe « ${group.name} » sera supprimé pour tous ses membres.',
    );
    if (ok != true) return;
    await ref.read(groupRepositoryProvider).deleteGroup(group.id);
    if (mounted) context.pop();
  }

  Future<void> _leave({required bool block}) async {
    final ok = await _confirm(
      block ? 'Bloquer le groupe ?' : 'Quitter le groupe ?',
      block
          ? 'Tu quittes « ${group.name} », tu ne recevras plus ses pensées et ne pourras plus y être rajouté.'
          : 'Tu quittes « ${group.name} ».',
    );
    if (ok != true) return;
    final repo = ref.read(groupRepositoryProvider);
    await (block ? repo.blockGroup(group.id) : repo.leaveGroup(group.id));
    if (mounted) context.pop();
  }

  Future<bool?> _confirm(String title, String body) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Confirmer',
              style: TextStyle(color: Color(0xFFFF6B5A)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _section(Color w, String t) => Padding(
    padding: const EdgeInsets.only(bottom: 8, left: 4),
    child: Text(
      t,
      style: TextStyle(
        fontSize: 13,
        letterSpacing: 0.6,
        fontWeight: FontWeight.w600,
        color: w.withValues(alpha: 0.6),
      ),
    ),
  );

  Widget _actionTile(
    Color w, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) => ListTile(
    onTap: onTap,
    contentPadding: const EdgeInsets.symmetric(horizontal: 6),
    leading: Icon(icon, color: w.withValues(alpha: 0.85)),
    title: Text(label),
  );

  Widget _danger(
    Color w, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) => ListTile(
    onTap: onTap,
    contentPadding: const EdgeInsets.symmetric(horizontal: 6),
    leading: const Icon(Icons.circle, color: Colors.transparent, size: 0),
    title: Row(
      children: [
        Icon(icon, color: const Color(0xFFFF6B5A), size: 20),
        const SizedBox(width: 12),
        Text(label, style: const TextStyle(color: Color(0xFFFF6B5A))),
      ],
    ),
  );

  Widget _hint(Color w, String msg) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
    child: Text(msg, style: TextStyle(color: w.withValues(alpha: 0.5))),
  );
}
