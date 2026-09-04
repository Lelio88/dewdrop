import 'package:dewdrop/src/common/glass.dart';
import 'package:dewdrop/src/features/thoughts/application/thought_providers.dart';
import 'package:dewdrop/src/features/thoughts/domain/thought.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// "Pensées reçues" panel revealed by swiping DOWN on the home. Two stages: at
/// [expanded] false it's a peek (the 3 most recent + a button to the full
/// screen); at [expanded] true — a second swipe down — it fills the sheet with
/// the whole history in a scrollable list, in place. [onSeeAll] opens the full
/// received screen. Anonymous senders are shown as "Quelqu'un".
///
/// The expanded branch returns an [Expanded]-based column, so its parent
/// ([_SheetPanel] at full height) MUST give it a bounded height.
class ReceivedPeek extends ConsumerWidget {
  const ReceivedPeek({
    super.key,
    required this.onSeeAll,
    this.expanded = false,
    this.demo = false,
  });

  final VoidCallback onSeeAll;
  final bool expanded;

  /// While the tour is running, a brand-new account would open this drawer on
  /// nothing at all — and "voilà tes pensées" over an empty panel teaches
  /// nothing. With [demo] on, and ONLY when there is genuinely nothing to show,
  /// two sample lines stand in, each labelled « exemple ». Nothing is written
  /// anywhere: they exist for the length of the tour and vanish with it.
  final bool demo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final w = Colors.white;
    final real =
        ref.watch(receivedThoughtsProvider).value ?? const <ReceivedThought>[];
    final received = (demo && real.isEmpty) ? _samples() : real;
    final isDemo = demo && real.isEmpty;

    if (expanded) return _expanded(w, received, isDemo);

    final recent = received.take(3).toList();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(w),
        const SizedBox(height: 12),
        if (recent.isEmpty)
          _empty(w)
        else
          for (final t in recent) _item(w, t, isDemo),
        const SizedBox(height: 14),
        GlassButton(label: 'Voir toutes mes pensées', onTap: onSeeAll),
      ],
    );
  }

  Widget _expanded(Color w, List<ReceivedThought> received, bool isDemo) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(w),
        const SizedBox(height: 12),
        Expanded(
          child: received.isEmpty
              ? Align(alignment: Alignment.topLeft, child: _empty(w))
              : ListView.builder(
                  padding: EdgeInsets.zero,
                  itemCount: received.length,
                  itemBuilder: (_, i) => _item(w, received[i], isDemo),
                ),
        ),
        const SizedBox(height: 10),
        GlassButton(label: 'Ouvrir en plein écran', onTap: onSeeAll),
      ],
    );
  }

  /// Stand-in lines for the tour. Deliberately unremarkable — one named sender,
  /// one anonymous — so the drawer shows both shapes it can take.
  List<ReceivedThought> _samples() {
    final now = DateTime.now();
    return [
      ReceivedThought(
        id: '_demo_1',
        createdAt: now.subtract(const Duration(minutes: 12)),
        isAnonymous: true,
      ),
      ReceivedThought(
        id: '_demo_2',
        createdAt: now.subtract(const Duration(hours: 5)),
        isAnonymous: true,
      ),
    ];
  }

  Widget _header(Color w) => Row(
    children: [
      const Text('✨', style: TextStyle(fontSize: 16)),
      const SizedBox(width: 8),
      Text(
        'Pensées reçues',
        style: TextStyle(color: w, fontWeight: FontWeight.w600),
      ),
    ],
  );

  Widget _empty(Color w) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Text(
      "Personne ne t'a encore envoyé de pensée.",
      style: TextStyle(color: w.withValues(alpha: 0.5)),
    ),
  );

  Widget _item(Color w, ReceivedThought t, [bool isDemo = false]) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: w.withValues(alpha: 0.14),
            // A group pensée is marked by an icon as well as by its sentence —
            // in a 3-line peek, the shape is read before the words.
            child: t.isGroup
                ? Icon(Icons.group_outlined, color: w, size: 16)
                : Text(
                    _initial(senderLabel(t)),
                    style: TextStyle(color: w, fontSize: 13),
                  ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    thoughtLine(t),
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: w.withValues(alpha: 0.9)),
                  ),
                ),
                // Never let a tour sample pass for a real pensée.
                if (isDemo) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(99),
                      color: w.withValues(alpha: 0.14),
                    ),
                    child: Text(
                      'exemple',
                      style: TextStyle(
                        color: w.withValues(alpha: 0.65),
                        fontSize: 10,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Text(
            _ago(t.createdAt),
            style: TextStyle(color: w.withValues(alpha: 0.45), fontSize: 12),
          ),
        ],
      ),
    );
  }

  String _initial(String s) =>
      s.isEmpty ? '?' : s.replaceAll('@', '')[0].toUpperCase();

  String _ago(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return "à l'instant";
    if (d.inMinutes < 60) return 'il y a ${d.inMinutes} min';
    if (d.inHours < 24) return 'il y a ${d.inHours} h';
    return 'il y a ${d.inDays} j';
  }
}
