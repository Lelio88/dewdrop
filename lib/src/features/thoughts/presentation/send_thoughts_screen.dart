import 'dart:async';

import 'package:dewdrop/src/common/app_exceptions.dart';
import 'package:dewdrop/src/features/friends/application/friend_providers.dart';
import 'package:dewdrop/src/features/friends/domain/friend.dart';
import 'package:dewdrop/src/features/groups/application/group_providers.dart';
import 'package:dewdrop/src/features/groups/domain/group.dart';
import 'package:dewdrop/src/features/profile/application/profile_providers.dart';
import 'package:dewdrop/src/features/profile/domain/profile.dart';
import 'package:dewdrop/src/features/thoughts/application/thought_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// "Envoyer une pensée" — pick a friend or a group; a single tap sends directly
/// (no confirmation sheet). Anonymity follows the profile's global default (the
/// "Pensées" settings). After a send, the tile shows "Envoyé ✨" and is disabled
/// for a short cooldown so an accidental double-tap can't fire twice. The
/// server's flood cap surfaces as a [RateLimitedException] → a friendly message.
class SendThoughtsScreen extends ConsumerStatefulWidget {
  const SendThoughtsScreen({super.key});

  @override
  ConsumerState<SendThoughtsScreen> createState() => _SendThoughtsScreenState();
}

class _SendThoughtsScreenState extends ConsumerState<SendThoughtsScreen> {
  // Recipients in their post-send cooldown, keyed "u:<id>" (friend) / "g:<id>"
  // (group); each cleared by a timer. The tile shows "Envoyé ✨" + is disabled
  // meanwhile — the accidental-double-send guard.
  final Set<String> _sent = {};
  final Map<String, Timer> _timers = {};

  // How long a tile stays "Envoyé ✨" + disabled after a send.
  static const _kCooldown = Duration(seconds: 4);

  @override
  void dispose() {
    for (final t in _timers.values) {
      t.cancel();
    }
    super.dispose();
  }

  /// Direct send (no confirmation). Anonymity comes from the global default.
  Future<void> _send({Profile? to, Group? group}) async {
    final key = to != null ? 'u:${to.id}' : 'g:${group!.id}';
    if (_sent.contains(key)) return; // already sent / in cooldown
    setState(() => _sent.add(key));
    final anonymous =
        ref.read(myProfileProvider).value?.defaultAnonymous ?? false;
    try {
      if (group != null) {
        await ref
            .read(groupRepositoryProvider)
            .sendToGroup(group.id, anonymous: anonymous);
      } else {
        await ref
            .read(thoughtRepositoryProvider)
            .sendThought(to!.id, anonymous: anonymous);
      }
      if (!mounted) return;
      // Success: keep "Envoyé ✨" for the cooldown window, then clear it.
      _timers[key]?.cancel();
      _timers[key] = Timer(_kCooldown, () {
        _timers.remove(key);
        if (mounted) setState(() => _sent.remove(key));
      });
    } on RateLimitedException {
      _revert(key);
      _snack('Tu envoies un peu vite 🌬️ — réessaie dans une minute.');
    } on Exception {
      _revert(key);
      _snack("Échec de l'envoi.");
    }
  }

  void _revert(String key) {
    _timers.remove(key)?.cancel();
    if (mounted) setState(() => _sent.remove(key));
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
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
                          children: [for (final g in list) _groupTile(w, g)],
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
                          children: [for (final f in list) _friendTile(w, f)],
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _friendTile(Color w, Friend f) {
    final p = f.profile;
    final name = p.displayName?.isNotEmpty == true
        ? p.displayName!
        : '@${p.handle}';
    final sent = _sent.contains('u:${p.id}');
    return _tile(
      w,
      leading: CircleAvatar(
        backgroundColor: w.withValues(alpha: 0.14),
        child: Text(_initial(name), style: TextStyle(color: w)),
      ),
      title: name,
      subtitle: '@${p.handle}',
      sent: sent,
      onTap: sent ? null : () => _send(to: p),
    );
  }

  Widget _groupTile(Color w, Group g) {
    final sent = _sent.contains('g:${g.id}');
    return _tile(
      w,
      leading: CircleAvatar(
        backgroundColor: const Color(0xFF8FB7FF).withValues(alpha: 0.18),
        child: Icon(
          Icons.group_rounded,
          color: w.withValues(alpha: 0.9),
          size: 20,
        ),
      ),
      title: g.name,
      subtitle: 'Groupe',
      sent: sent,
      onTap: sent ? null : () => _send(group: g),
    );
  }

  Widget _tile(
    Color w, {
    required Widget leading,
    required String title,
    required String subtitle,
    required bool sent,
    required VoidCallback? onTap,
  }) {
    const ok = Color(0xFF9BE8B0);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Opacity(
        opacity: sent ? 0.6 : 1,
        child: ListTile(
          onTap: onTap,
          contentPadding: const EdgeInsets.symmetric(horizontal: 6),
          leading: leading,
          title: Text(title),
          subtitle: Text(
            sent ? 'Envoyé ✨' : subtitle,
            style: TextStyle(color: sent ? ok : w.withValues(alpha: 0.5)),
          ),
          trailing: Icon(
            sent ? Icons.check_circle_rounded : Icons.send_rounded,
            color: sent ? ok : w.withValues(alpha: 0.5),
          ),
        ),
      ),
    );
  }

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
