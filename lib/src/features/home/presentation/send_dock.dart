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

const _ok = Color(0xFF9BE8B0); // "envoyé" green

/// Compact "envoyer" dock revealed by swiping UP on the home: a horizontal row
/// of friend + group avatars. A single tap sends a pensée **directly** (anonymity
/// from the global default); the avatar then shows "✓" and is disabled for a
/// short cooldown — the accidental-double-send guard. [onSeeAll] opens the full
/// send screen for the complete list.
///
/// NB: the direct-send + cooldown behaviour mirrors `SendThoughtsScreen`. Kept
/// duplicated on purpose (two call sites, ~20 lines) — extract a shared
/// SendController only if a third caller appears (YAGNI).
class SendDock extends ConsumerStatefulWidget {
  const SendDock({super.key, required this.onSeeAll, this.expanded = false});

  final VoidCallback onSeeAll;

  /// When false, a single horizontal row (the peek). When true — a second swipe
  /// up — a scrollable wrapped grid of every friend + group, filling the sheet.
  /// The expanded branch uses an [Expanded], so its parent must bound its height.
  final bool expanded;

  @override
  ConsumerState<SendDock> createState() => _SendDockState();
}

class _SendDockState extends ConsumerState<SendDock> {
  // Recipients in their post-send cooldown ("u:<id>" friend / "g:<id>" group).
  final Set<String> _sent = {};
  final Map<String, Timer> _timers = {};
  static const _kCooldown = Duration(seconds: 4);

  @override
  void dispose() {
    for (final t in _timers.values) {
      t.cancel();
    }
    super.dispose();
  }

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
    final friends = ref.watch(friendsProvider).value ?? const <Friend>[];
    final groups = ref.watch(myGroupsProvider).value ?? const <Group>[];
    final empty = friends.isEmpty && groups.isEmpty;

    // Groups first, then friends — same order in both stages.
    final avatars = <Widget>[
      for (final g in groups)
        _avatar(
          w,
          key: 'g:${g.id}',
          label: g.name,
          group: true,
          onTap: () => _send(group: g),
        ),
      for (final f in friends)
        _avatar(
          w,
          key: 'u:${f.profile.id}',
          label: _name(f.profile),
          onTap: () => _send(to: f.profile),
        ),
    ];

    return Column(
      mainAxisSize: widget.expanded ? MainAxisSize.max : MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _header(w),
        const SizedBox(height: 12),
        if (empty)
          _emptyText(w)
        else if (widget.expanded)
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: 8),
              child: Wrap(spacing: 14, runSpacing: 16, children: avatars),
            ),
          )
        else
          SizedBox(
            height: 94,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final a in avatars)
                  Padding(padding: const EdgeInsets.only(right: 14), child: a),
              ],
            ),
          ),
        const SizedBox(height: 4),
        Center(
          child: TextButton(
            onPressed: widget.onSeeAll,
            child: Text(
              'voir tous mes amis & cercles',
              style: TextStyle(color: w.withValues(alpha: 0.7)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _header(Color w) => Row(
    children: [
      Text(
        'Envoyer une pensée',
        style: TextStyle(color: w, fontWeight: FontWeight.w600),
      ),
      const Spacer(),
      Text(
        'anonyme : réglages',
        style: TextStyle(color: w.withValues(alpha: 0.4), fontSize: 12),
      ),
    ],
  );

  Widget _emptyText(Color w) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Text(
      'Ajoute un ami pour envoyer une pensée.',
      style: TextStyle(color: w.withValues(alpha: 0.5)),
    ),
  );

  Widget _avatar(
    Color w, {
    required String key,
    required String label,
    required VoidCallback onTap,
    bool group = false,
  }) {
    final sent = _sent.contains(key);
    final shape = group ? BoxShape.rectangle : BoxShape.circle;
    final radius = group ? BorderRadius.circular(16) : null;
    return SizedBox(
      width: 60,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: sent ? null : onTap,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 54,
                  height: 54,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: shape,
                    borderRadius: radius,
                    color: w.withValues(alpha: 0.14),
                    border: Border.all(
                      color: (sent ? _ok : w).withValues(
                        alpha: sent ? 0.9 : 0.4,
                      ),
                      width: 2,
                    ),
                  ),
                  child: group
                      ? Icon(
                          Icons.group_rounded,
                          color: w.withValues(alpha: 0.9),
                        )
                      : Text(
                          _initial(label),
                          style: TextStyle(
                            color: w,
                            fontWeight: FontWeight.w700,
                            fontSize: 20,
                          ),
                        ),
                ),
                if (sent)
                  Container(
                    width: 54,
                    height: 54,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: shape,
                      borderRadius: radius,
                      color: const Color(0xFF07221D).withValues(alpha: 0.55),
                    ),
                    child: const Icon(
                      Icons.check_rounded,
                      color: _ok,
                      size: 26,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            sent ? 'Envoyé' : label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: sent ? _ok : w.withValues(alpha: 0.65),
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  String _name(Profile p) =>
      p.displayName?.isNotEmpty == true ? p.displayName! : '@${p.handle}';

  String _initial(String s) =>
      s.isEmpty ? '?' : s.replaceAll('@', '')[0].toUpperCase();
}
