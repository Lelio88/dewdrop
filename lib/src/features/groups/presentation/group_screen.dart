import 'package:dewdrop/src/features/auth/application/auth_providers.dart';
import 'package:dewdrop/src/features/friends/application/friend_providers.dart';
import 'package:dewdrop/src/features/groups/application/group_providers.dart';
import 'package:dewdrop/src/features/groups/domain/group.dart';
import 'package:dewdrop/src/features/profile/domain/profile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Manage a group: see members, and — for the creator — add (from friends) or
/// remove members and delete the group; for a plain member, leave or block it.
class GroupScreen extends ConsumerWidget {
  const GroupScreen({super.key, required this.group});

  final Group group;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final w = Colors.white;
    final uid = ref.watch(authRepositoryProvider).currentUser?.id ?? '';
    final isCreator = group.isCreator(uid);
    final members = ref.watch(groupMembersProvider(group.id));

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
                style: TextStyle(color: w.withValues(alpha: 0.55), fontSize: 13),
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
                      _memberTile(context, ref, w, p, uid, isCreator),
                  ],
                ),
              ),
              if (isCreator) ...[
                const SizedBox(height: 8),
                _actionTile(
                  w,
                  icon: Icons.person_add_alt_1,
                  label: 'Ajouter un ami',
                  onTap: () => _addMembers(context, ref, members.value ?? []),
                ),
              ],
              const SizedBox(height: 28),
              if (isCreator)
                _danger(
                  w,
                  icon: Icons.delete_outline,
                  label: 'Supprimer le groupe',
                  onTap: () => _deleteGroup(context, ref),
                )
              else ...[
                _danger(
                  w,
                  icon: Icons.logout_rounded,
                  label: 'Quitter le groupe',
                  onTap: () => _leave(context, ref, block: false),
                ),
                _danger(
                  w,
                  icon: Icons.block,
                  label: 'Bloquer le groupe',
                  onTap: () => _leave(context, ref, block: true),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _memberTile(
    BuildContext context,
    WidgetRef ref,
    Color w,
    Profile p,
    String uid,
    bool isCreator,
  ) {
    final name = p.displayName?.isNotEmpty == true ? p.displayName! : '@${p.handle}';
    final isSelf = p.id == uid;
    final isOwner = group.isCreator(p.id);
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
      // The creator can remove anyone but themselves.
      trailing: (isCreator && !isSelf)
          ? IconButton(
              icon: Icon(Icons.remove_circle_outline, color: w.withValues(alpha: 0.5)),
              onPressed: () async {
                await ref.read(groupRepositoryProvider).removeMember(group.id, p.id);
                ref.invalidate(groupMembersProvider(group.id));
              },
            )
          : null,
    );
  }

  /// Sheet listing friends not already in the group; tap to add.
  Future<void> _addMembers(
    BuildContext context,
    WidgetRef ref,
    List<Profile> current,
  ) async {
    final memberIds = {for (final p in current) p.id};
    final friends = ref.read(friendsProvider).value ?? [];
    final addable = [
      for (final f in friends)
        if (!memberIds.contains(f.profile.id)) f.profile,
    ];
    if (addable.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tous tes amis sont déjà dans le groupe.')),
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
              child: Text('Ajouter au groupe', style: TextStyle(color: Colors.white70)),
            ),
            for (final p in addable)
              ListTile(
                leading: const Icon(Icons.person_add_alt_1, color: Colors.white70),
                title: Text(
                  p.displayName?.isNotEmpty == true ? p.displayName! : '@${p.handle}',
                  style: const TextStyle(color: Colors.white),
                ),
                onTap: () async {
                  Navigator.pop(ctx);
                  await ref.read(groupRepositoryProvider).addMember(group.id, p.id);
                  ref.invalidate(groupMembersProvider(group.id));
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteGroup(BuildContext context, WidgetRef ref) async {
    final ok = await _confirm(
      context,
      'Supprimer le groupe ?',
      'Le groupe « ${group.name} » sera supprimé pour tous ses membres.',
    );
    if (ok != true) return;
    await ref.read(groupRepositoryProvider).deleteGroup(group.id);
    if (context.mounted) context.pop();
  }

  Future<void> _leave(BuildContext context, WidgetRef ref, {required bool block}) async {
    final ok = await _confirm(
      context,
      block ? 'Bloquer le groupe ?' : 'Quitter le groupe ?',
      block
          ? 'Tu quittes « ${group.name} », tu ne recevras plus ses pensées et ne pourras plus y être rajouté.'
          : 'Tu quittes « ${group.name} ».',
    );
    if (ok != true) return;
    final repo = ref.read(groupRepositoryProvider);
    await (block ? repo.blockGroup(group.id) : repo.leaveGroup(group.id));
    if (context.mounted) context.pop();
  }

  Future<bool?> _confirm(BuildContext context, String title, String body) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirmer', style: TextStyle(color: Color(0xFFFF6B5A))),
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
