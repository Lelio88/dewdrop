import 'package:dewdrop/src/features/friends/application/friend_providers.dart';
import 'package:dewdrop/src/features/friends/domain/friend.dart';
import 'package:dewdrop/src/features/groups/application/group_providers.dart';
import 'package:dewdrop/src/features/groups/domain/group.dart';
import 'package:dewdrop/src/features/profile/domain/profile.dart';
import 'package:dewdrop/src/features/thoughts/presentation/send_thought_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// "Envoyer une pensée" — pick a friend or a group to send to. Sending lives
/// here now (the "Amis" page is for managing friends + groups, not sending).
class SendThoughtsScreen extends ConsumerWidget {
  const SendThoughtsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final w = Colors.white;
    final friends = ref.watch(friendsProvider);
    final groups = ref.watch(myGroupsProvider);

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('Envoyer une pensée'),
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
          child: RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(friendsProvider);
              ref.invalidate(myGroupsProvider);
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
              children: [
                _section(w, 'Mes groupes'),
                groups.when(
                  loading: () => const _Loading(),
                  error: (_, _) => _error(w),
                  data: (list) => list.isEmpty
                      ? _empty(w, 'Aucun groupe. Crée-en un depuis « Amis ».')
                      : Column(
                          children: [
                            for (final g in list) _groupTile(context, ref, w, g),
                          ],
                        ),
                ),
                const SizedBox(height: 24),
                _section(w, 'Mes amis'),
                friends.when(
                  loading: () => const _Loading(),
                  error: (_, _) => _error(w),
                  data: (list) => list.isEmpty
                      ? _empty(w, 'Pas encore d\'amis.')
                      : Column(
                          children: [
                            for (final f in list) _friendTile(context, ref, w, f),
                          ],
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _friendTile(BuildContext context, WidgetRef ref, Color w, Friend f) {
    final p = f.profile;
    final name = p.displayName?.isNotEmpty == true ? p.displayName! : '@${p.handle}';
    return _tile(
      w,
      leading: CircleAvatar(
        backgroundColor: w.withValues(alpha: 0.14),
        child: Text(_initial(name), style: TextStyle(color: w)),
      ),
      title: name,
      subtitle: '@${p.handle}',
      onTap: () => _send(context, ref, to: p),
    );
  }

  Widget _groupTile(BuildContext context, WidgetRef ref, Color w, Group g) {
    return _tile(
      w,
      leading: CircleAvatar(
        backgroundColor: const Color(0xFF8FB7FF).withValues(alpha: 0.18),
        child: Icon(Icons.group_rounded, color: w.withValues(alpha: 0.9), size: 20),
      ),
      title: g.name,
      subtitle: 'Groupe',
      onTap: () => _send(context, ref, group: g),
    );
  }

  Future<void> _send(
    BuildContext context,
    WidgetRef ref, {
    Profile? to,
    Group? group,
  }) async {
    final sent = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.2),
      isScrollControlled: true,
      builder: (_) => SendThoughtSheet(to: to, group: group),
    );
    if (sent == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pensée envoyée 💭')),
      );
    }
  }

  Widget _tile(
    Color w, {
    required Widget leading,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 6),
      leading: leading,
      title: Text(title),
      subtitle: Text(subtitle, style: TextStyle(color: w.withValues(alpha: 0.5))),
      trailing: Icon(Icons.send_rounded, color: w.withValues(alpha: 0.5)),
    ),
  );

  String _initial(String s) => s.isEmpty ? '?' : s[0].toUpperCase();

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

  Widget _empty(Color w, String msg) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
    child: Text(msg, style: TextStyle(color: w.withValues(alpha: 0.45))),
  );

  Widget _error(Color w) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
    child: Text(
      'Impossible de charger pour le moment.',
      style: TextStyle(color: w.withValues(alpha: 0.6)),
    ),
  );
}

class _Loading extends StatelessWidget {
  const _Loading();
  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.all(16),
    child: Center(
      child: SizedBox(
        width: 22,
        height: 22,
        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white54),
      ),
    ),
  );
}
