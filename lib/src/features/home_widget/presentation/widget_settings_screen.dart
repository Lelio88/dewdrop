import 'dart:async';

import 'package:dewdrop/src/common/glass.dart';
import 'package:dewdrop/src/features/friends/application/friend_providers.dart';
import 'package:dewdrop/src/features/friends/domain/friend.dart';
import 'package:dewdrop/src/features/home_widget/application/widget_providers.dart';
import 'package:dewdrop/src/features/home_widget/application/widget_sync_service.dart';
import 'package:dewdrop/src/features/profile/application/profile_providers.dart';
import 'package:dewdrop/src/features/profile/domain/profile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// "Widget d'écran d'accueil" — chooses WHICH friends the home-screen widget
/// shows and in what order. Two sources:
///   • 'auto'   → the friends most recently sent a pensée (no setup);
///   • 'custom' → a hand-picked, reorderable list of up to [kWidgetSlotCount].
///
/// Mirrors the thought-presets screen: local state seeded from the already
/// loaded profile, every change written through `profileRepositoryProvider`
/// then `ref.invalidate(myProfileProvider)` so `app.dart`'s listeners re-push
/// the widget. The pinned list is a plain `List<String>` of friend ids
/// (`profiles.widget_friends`); the source is `profiles.widget_source`.
///
/// Invariant: never persist more than [kWidgetSlotCount] pinned ids — the same
/// cap the widget renders. Stale ids (a since-removed friend) are tolerated:
/// they're filtered on display here and when the widget resolves its slots.
class WidgetSettingsScreen extends ConsumerStatefulWidget {
  const WidgetSettingsScreen({super.key});

  @override
  ConsumerState<WidgetSettingsScreen> createState() =>
      _WidgetSettingsScreenState();
}

class _WidgetSettingsScreenState extends ConsumerState<WidgetSettingsScreen> {
  late String _source; // 'auto' | 'custom'
  late List<String> _pinned; // friend ids, in display order (≤ kWidgetSlotCount)

  @override
  void initState() {
    super.initState();
    final p = ref.read(myProfileProvider).value;
    _source = p?.widgetSource == 'custom' ? 'custom' : 'auto';
    _pinned = List<String>.of(p?.widgetFriends ?? const []);
  }

  Future<void> _persistSource(String source) async {
    setState(() => _source = source);
    try {
      await ref.read(profileRepositoryProvider).updateWidgetSource(source);
    } on Exception catch (e) {
      debugPrint('widget_source save failed: $e');
      return;
    }
    if (!mounted) return;
    ref.invalidate(myProfileProvider);
  }

  /// Writes the pinned list (already pruned/ordered by the caller), capped at
  /// [kWidgetSlotCount], then refreshes the profile so the widget re-syncs.
  Future<void> _savePinned(List<String> ids) async {
    final capped = ids.take(kWidgetSlotCount).toList();
    setState(() => _pinned = capped);
    try {
      await ref.read(profileRepositoryProvider).updateWidgetFriends(capped);
    } on Exception catch (e) {
      debugPrint('widget_friends save failed: $e');
      return;
    }
    if (!mounted) return;
    ref.invalidate(myProfileProvider);
  }

  void _reorder(List<Friend> pinned, int oldIndex, int newIndex) {
    final ids = pinned.map((f) => f.profile.id).toList();
    if (newIndex > oldIndex) newIndex -= 1;
    ids.insert(newIndex, ids.removeAt(oldIndex));
    unawaited(_savePinned(ids));
  }

  void _remove(List<Friend> pinned, String id) => unawaited(
    _savePinned([for (final f in pinned) if (f.profile.id != id) f.profile.id]),
  );

  void _add(List<Friend> pinned, String id) =>
      unawaited(_savePinned([...pinned.map((f) => f.profile.id), id]));

  @override
  Widget build(BuildContext context) {
    final w = Colors.white;
    final friends = ref.watch(friendsProvider).value;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text("Widget d'écran d'accueil"),
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
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: [
              _section(w, 'Qui afficher'),
              GlassCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: double.infinity,
                      child: SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(
                            value: 'auto',
                            label: Text('Derniers contacts'),
                          ),
                          ButtonSegment(
                            value: 'custom',
                            label: Text('Ma sélection'),
                          ),
                        ],
                        selected: {_source},
                        showSelectedIcon: false,
                        onSelectionChanged: (s) =>
                            unawaited(_persistSource(s.first)),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      _source == 'auto'
                          ? 'Les amis à qui tu as envoyé une pensée le plus '
                                'récemment apparaissent automatiquement (jusqu’à '
                                '$kWidgetSlotCount).'
                          : 'Choisis jusqu’à $kWidgetSlotCount amis et leur '
                                'ordre. Ils s’affichent toujours, peu importe '
                                'tes envois.',
                      style: _hint(w),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              if (friends == null)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: CircularProgressIndicator(),
                  ),
                )
              else if (friends.isEmpty)
                GlassCard(
                  child: Text(
                    'Ajoute d’abord des amis pour les poser sur ton widget.',
                    style: _hint(w),
                  ),
                )
              else if (_source == 'auto')
                ..._autoSection(w, friends)
              else
                ..._customSection(w, friends),
            ],
          ),
        ),
      ),
    );
  }

  /// Read-only preview of what the 'auto' source resolves to right now.
  List<Widget> _autoSection(Color w, List<Friend> friends) {
    final slots = ref
        .watch(widgetSlotFriendsProvider)
        .take(kWidgetSlotCount)
        .toList();
    return [
      _section(w, 'Aperçu'),
      GlassCard(
        child: slots.isEmpty
            ? Text(
                'Envoie une pensée à un ami et il apparaîtra ici.',
                style: _hint(w),
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final f in slots)
                    Expanded(child: _slotPreview(w, f.profile)),
                ],
              ),
      ),
    ];
  }

  List<Widget> _customSection(Color w, List<Friend> friends) {
    final byId = {for (final f in friends) f.profile.id: f};
    final pinned = [
      for (final id in _pinned)
        if (byId.containsKey(id)) byId[id]!,
    ];
    final pinnedIds = {for (final f in pinned) f.profile.id};
    final addable = [
      for (final f in friends)
        if (!pinnedIds.contains(f.profile.id)) f,
    ];
    final full = pinned.length >= kWidgetSlotCount;

    return [
      _section(w, 'Ma sélection ($kWidgetSlotCount max)'),
      GlassCard(
        child: pinned.isEmpty
            ? Text(
                'Aucun ami sélectionné. Ajoute-en depuis la liste ci-dessous.',
                style: _hint(w),
              )
            : ReorderableListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                buildDefaultDragHandles: false,
                itemCount: pinned.length,
                onReorder: (o, n) => _reorder(pinned, o, n),
                itemBuilder: (ctx, i) => _pinnedRow(w, pinned, i),
              ),
      ),
      const SizedBox(height: 22),
      _section(w, 'Tes amis'),
      GlassCard(
        child: addable.isEmpty
            ? Text(
                full
                    ? 'Maximum atteint — retire un ami pour en ajouter un autre.'
                    : 'Tous tes amis sont déjà sur le widget.',
                style: _hint(w),
              )
            : Column(
                children: [
                  for (var i = 0; i < addable.length; i++) ...[
                    if (i > 0)
                      Divider(color: w.withValues(alpha: 0.08), height: 1),
                    _addableRow(w, pinned, addable[i], full),
                  ],
                ],
              ),
      ),
    ];
  }

  Widget _pinnedRow(Color w, List<Friend> pinned, int i) {
    final p = pinned[i].profile;
    return Padding(
      key: ValueKey(p.id),
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          _avatar(w, p),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _name(p),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: w, fontSize: 15),
            ),
          ),
          IconButton(
            tooltip: 'Retirer',
            icon: Icon(Icons.close_rounded, color: w.withValues(alpha: 0.5)),
            onPressed: () => _remove(pinned, p.id),
          ),
          ReorderableDragStartListener(
            index: i,
            child: Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Icon(
                Icons.drag_handle_rounded,
                color: w.withValues(alpha: 0.4),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _addableRow(Color w, List<Friend> pinned, Friend f, bool full) {
    final p = f.profile;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          _avatar(w, p),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _name(p),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: w, fontSize: 15),
            ),
          ),
          IconButton(
            tooltip: full ? 'Maximum atteint' : 'Ajouter',
            icon: Icon(
              Icons.add_circle_outline_rounded,
              color: w.withValues(alpha: full ? 0.25 : 0.85),
            ),
            onPressed: full ? null : () => _add(pinned, p.id),
          ),
        ],
      ),
    );
  }

  Widget _slotPreview(Color w, Profile p) => Column(
    children: [
      _avatar(w, p),
      const SizedBox(height: 6),
      Text(
        _name(p),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: TextStyle(color: w.withValues(alpha: 0.7), fontSize: 12),
      ),
    ],
  );

  /// Friend avatar circle — mirrors `SendDock._avatar` / the widget slot.
  Widget _avatar(Color w, Profile p, {double size = 44}) => Container(
    width: size,
    height: size,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: w.withValues(alpha: 0.14),
      border: Border.all(color: w.withValues(alpha: 0.25), width: 1.5),
    ),
    child: Text(
      _initial(_name(p)),
      style: TextStyle(
        color: w,
        fontWeight: FontWeight.w700,
        fontSize: size * 0.4,
      ),
    ),
  );

  /// Mirrors `SendDock._name`: display name when set, else the @handle.
  String _name(Profile p) =>
      p.displayName?.isNotEmpty == true ? p.displayName! : '@${p.handle}';

  /// Mirrors `SendDock._initial`: first letter of the label, '@' stripped.
  String _initial(String s) =>
      s.isEmpty ? '?' : s.replaceAll('@', '')[0].toUpperCase();

  TextStyle _hint(Color w) =>
      TextStyle(color: w.withValues(alpha: 0.55), fontSize: 13, height: 1.4);

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
}
