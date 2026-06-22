import 'package:dewdrop/src/common/glass.dart';
import 'package:dewdrop/src/features/profile/domain/profile.dart';
import 'package:dewdrop/src/features/thoughts/application/thought_providers.dart';
import 'package:dewdrop/src/features/thoughts/domain/thought.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Compact "pensées reçues" panel revealed by swiping DOWN on the home: a peek
/// at the most recent pensées + a button to the full list. [onSeeAll] opens the
/// received screen. Anonymous senders are shown as "Quelqu'un".
class ReceivedPeek extends ConsumerWidget {
  const ReceivedPeek({super.key, required this.onSeeAll});

  final VoidCallback onSeeAll;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final w = Colors.white;
    final received =
        ref.watch(receivedThoughtsProvider).value ?? const <ReceivedThought>[];
    final recent = received.take(3).toList();

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Text('✨', style: TextStyle(fontSize: 16)),
            const SizedBox(width: 8),
            Text(
              'Pensées reçues',
              style: TextStyle(color: w, fontWeight: FontWeight.w600),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (recent.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text(
              "Personne ne t'a encore envoyé de pensée.",
              style: TextStyle(color: w.withValues(alpha: 0.5)),
            ),
          )
        else
          for (final t in recent) _item(w, t),
        const SizedBox(height: 14),
        GlassButton(label: 'Voir toutes mes pensées', onTap: onSeeAll),
      ],
    );
  }

  Widget _item(Color w, ReceivedThought t) {
    final who = t.isAnonymous ? "Quelqu'un" : _name(t.sender);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: w.withValues(alpha: 0.14),
            child: Text(
              _initial(who),
              style: TextStyle(color: w, fontSize: 13),
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Text(
              '$who a pensé à toi',
              style: TextStyle(color: w.withValues(alpha: 0.9)),
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

  String _name(Profile? p) {
    if (p == null) return "Quelqu'un";
    return p.displayName?.isNotEmpty == true ? p.displayName! : '@${p.handle}';
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
