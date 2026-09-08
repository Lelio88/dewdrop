import 'dart:async';

import 'package:dewdrop/src/common/app_exceptions.dart';
import 'package:dewdrop/src/features/friends/application/friend_providers.dart';
import 'package:dewdrop/src/features/friends/domain/friend.dart';
import 'package:dewdrop/src/features/groups/application/group_providers.dart';
import 'package:dewdrop/src/features/groups/domain/group.dart';
import 'package:dewdrop/src/features/profile/application/profile_providers.dart';
import 'package:dewdrop/src/features/profile/domain/profile.dart';
import 'package:dewdrop/src/features/thoughts/application/thought_providers.dart';
import 'package:dewdrop/src/features/thoughts/domain/send_order.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const _ok = Color(0xFF9BE8B0); // "envoyé" green

/// Height of one peek rank: a 54 avatar + its label, with slack for a
/// scaled-up font. Shared by both ranks so they read as one block.
const _kRankHeight = 94.0;

/// Compact "envoyer" dock revealed by swiping UP on the home: two ranks of
/// avatars — friends (round) first, groups (square) under them — **most
/// recently written-to first**. A single tap sends a pensée **directly**
/// (anonymity from the global default); the avatar then shows "✓" and is
/// disabled for a short cooldown — the accidental-double-send guard.
/// [onSeeAll] sits in the header's right-hand corner and opens the full send
/// screen for the complete list.
///
/// The two families never share a rank: at peek each is its own scrolling row,
/// expanded each is its own labelled section. Shape alone ("round or square?")
/// used to carry the whole distinction, on a single mixed row.
///
/// Invariant: the order never changes while the dock is on screen. A send makes
/// the recipient jump to the front, so re-ordering live would move avatars under
/// the user's finger mid-burst; instead the refresh is deferred until [visible]
/// goes false (see [didUpdateWidget]).
///
/// NB: the direct-send + cooldown behaviour mirrors `SendThoughtsScreen`. Kept
/// duplicated on purpose (two call sites, ~20 lines) — extract a shared
/// SendController only if a third caller appears (YAGNI).
class SendDock extends ConsumerStatefulWidget {
  const SendDock({
    super.key,
    required this.onSeeAll,
    this.onAddFriend,
    this.expanded = false,
    this.visible = true,
  });

  final VoidCallback onSeeAll;

  /// Opens the friends screen. An account with nobody to send to opens this
  /// drawer on a dead end otherwise — the way out belongs where the wall is.
  final VoidCallback? onAddFriend;

  /// When false, two horizontal ranks (the peek). When true — a second swipe
  /// up — the same two families as scrollable labelled grids, filling the
  /// sheet. The expanded branch uses an [Expanded], so its parent must bound
  /// its height.
  final bool expanded;

  /// Whether the sheet holding this dock is open. The widget stays mounted when
  /// closed (it slides off-screen), so this is the only way it can tell — and
  /// it is what gates the deferred re-ordering.
  final bool visible;

  @override
  ConsumerState<SendDock> createState() => _SendDockState();
}

class _SendDockState extends ConsumerState<SendDock> {
  // Recipients in their post-send cooldown ("u:<id>" friend / "g:<id>" group).
  final Set<String> _sent = {};
  final Map<String, Timer> _timers = {};
  static const _kCooldown = Duration(seconds: 4);

  // A send landed since the dock was opened → the recency order is stale.
  bool _orderStale = false;

  @override
  void didUpdateWidget(SendDock oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Refresh "derniers contacts" only once hidden, so the reshuffle happens
    // off-screen and the next opening already shows the new order.
    if (oldWidget.visible && !widget.visible && _orderStale) {
      _orderStale = false;
      ref.invalidate(recentContactsProvider);
      ref.invalidate(recentGroupsProvider);
    }
  }

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
      _orderStale = true; // applied on close — never under the user's finger
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

    // Both families ordered by who you wrote to last, each off its own read:
    // a group send fans out to per-member rows, so the two recency windows
    // cannot share one (see `recentlyContactedGroupIds`). Whoever was never
    // written to falls back to alphabetical order.
    final recent = ref.watch(recentContactsProvider).value ?? const <String>[];
    final recentGroups =
        ref.watch(recentGroupsProvider).value ?? const <String>[];
    final orderedFriends = sortByRecency(
      friends,
      idOf: (f) => f.profile.id,
      labelOf: (f) => _name(f.profile),
      recentIdsNewestFirst: recent,
    );
    final orderedGroups = sortByRecency(
      groups,
      idOf: (g) => g.id,
      labelOf: (g) => g.name,
      recentIdsNewestFirst: recentGroups,
    );

    // Friends first, groups under them — same families in the same order at
    // both stages. Each list is built on its own: a family with no member
    // renders nothing rather than an empty rank.
    final friendTiles = <Widget>[
      for (final f in orderedFriends)
        _avatar(
          w,
          key: 'u:${f.profile.id}',
          label: _name(f.profile),
          onTap: () => _send(to: f.profile),
        ),
    ];
    final groupTiles = <Widget>[
      for (final g in orderedGroups)
        _avatar(
          w,
          key: 'g:${g.id}',
          label: g.name,
          group: true,
          onTap: () => _send(group: g),
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (friendTiles.isNotEmpty) ...[
                    _sectionLabel(w, 'Amis'),
                    Wrap(spacing: 14, runSpacing: 16, children: friendTiles),
                  ],
                  if (groupTiles.isNotEmpty) ...[
                    if (friendTiles.isNotEmpty) const SizedBox(height: 22),
                    _sectionLabel(w, 'Cercles'),
                    Wrap(spacing: 14, runSpacing: 16, children: groupTiles),
                  ],
                ],
              ),
            ),
          )
        else ...[
          if (friendTiles.isNotEmpty) _rank(friendTiles),
          if (friendTiles.isNotEmpty && groupTiles.isNotEmpty)
            const SizedBox(height: 10),
          if (groupTiles.isNotEmpty) _rank(groupTiles),
        ],
      ],
    );
  }

  /// One horizontally scrolling rank of avatars, at peek.
  Widget _rank(List<Widget> tiles) => SizedBox(
    height: _kRankHeight,
    child: ListView(
      scrollDirection: Axis.horizontal,
      children: [
        for (final t in tiles)
          Padding(padding: const EdgeInsets.only(right: 14), child: t),
      ],
    ),
  );

  /// Title on the left, the way out facing it on the right. The link used to
  /// sit centred under the avatars, where it took a whole line of a drawer
  /// that now needs two — and where the thumb met it before the faces.
  Widget _header(Color w) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Flexible(
        child: Text(
          'Envoyer une pensée',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: w, fontWeight: FontWeight.w600),
        ),
      ),
      const SizedBox(width: 8),
      Flexible(
        child: TextButton(
          onPressed: widget.onSeeAll,
          style: TextButton.styleFrom(
            foregroundColor: w.withValues(alpha: 0.7),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            visualDensity: VisualDensity.compact,
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  'Mes amis & cercles',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Icon(Icons.chevron_right_rounded, size: 16),
            ],
          ),
        ),
      ),
    ],
  );

  /// Heading of one family in the expanded stage — the labels the peek gets
  /// away without, two ranks being self-evident where a scrolling grid is not.
  Widget _sectionLabel(Color w, String text) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(
      text,
      style: TextStyle(
        color: w.withValues(alpha: 0.55),
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.8,
      ),
    ),
  );

  Widget _emptyText(Color w) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: widget.onAddFriend == null
        ? Text(
            'Ajoute un ami pour envoyer une pensée.',
            style: TextStyle(color: w.withValues(alpha: 0.5)),
          )
        : GestureDetector(
            onTap: widget.onAddFriend,
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF8FE3A8).withValues(alpha: 0.18),
                    border: Border.all(
                      color: const Color(0xFF8FE3A8).withValues(alpha: 0.45),
                    ),
                  ),
                  child: const Icon(
                    Icons.person_add_alt_1,
                    color: Color(0xFF8FE3A8),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Ajoute ton premier ami pour commencer',
                    style: TextStyle(color: w.withValues(alpha: 0.75)),
                  ),
                ),
                Icon(Icons.chevron_right, color: w.withValues(alpha: 0.45)),
              ],
            ),
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
