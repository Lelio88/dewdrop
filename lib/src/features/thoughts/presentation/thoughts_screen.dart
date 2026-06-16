import 'package:dewdrop/src/features/thoughts/application/thought_providers.dart';
import 'package:dewdrop/src/features/thoughts/domain/thought.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// History of thoughts received ("X a pensé à toi").
class ThoughtsScreen extends ConsumerWidget {
  const ThoughtsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final w = Colors.white;
    final received = ref.watch(receivedThoughtsProvider);

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('Pensées reçues'),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF161228), Color(0xFF07060E)],
          ),
        ),
        child: SafeArea(
          child: RefreshIndicator(
            onRefresh: () async => ref.invalidate(receivedThoughtsProvider),
            child: received.when(
              loading: () => const Center(
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white54,
                ),
              ),
              error: (_, _) => ListView(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'Impossible de charger tes pensées.',
                      style: TextStyle(color: w.withValues(alpha: 0.6)),
                    ),
                  ),
                ],
              ),
              data: (list) => list.isEmpty
                  ? _emptyState(w)
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                      itemCount: list.length,
                      separatorBuilder: (_, _) =>
                          Divider(color: w.withValues(alpha: 0.06), height: 1),
                      itemBuilder: (_, i) => _tile(w, list[i]),
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _emptyState(Color w) => ListView(
    children: [
      Padding(
        padding: const EdgeInsets.only(top: 120),
        child: Column(
          children: [
            Icon(
              Icons.auto_awesome_outlined,
              size: 48,
              color: w.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 16),
            Text(
              'Aucune pensée pour le moment.',
              style: TextStyle(color: w.withValues(alpha: 0.5)),
            ),
            const SizedBox(height: 6),
            Text(
              'Elles apparaîtront ici quand un ami pensera à toi.',
              textAlign: TextAlign.center,
              style: TextStyle(color: w.withValues(alpha: 0.35), fontSize: 13),
            ),
          ],
        ),
      ),
    ],
  );

  Widget _tile(Color w, ReceivedThought t) {
    final who = t.isAnonymous
        ? "Quelqu'un"
        : (t.sender?.displayName?.isNotEmpty == true
              ? t.sender!.displayName!
              : '@${t.sender?.handle ?? '?'}');
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      leading: CircleAvatar(
        backgroundColor: w.withValues(alpha: 0.12),
        child: Icon(
          t.isAnonymous ? Icons.help_outline : Icons.favorite,
          color: w.withValues(alpha: 0.8),
          size: 20,
        ),
      ),
      title: Text('$who a pensé à toi'),
      subtitle: Text(
        _ago(t.createdAt),
        style: TextStyle(color: w.withValues(alpha: 0.5)),
      ),
    );
  }

  String _ago(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return "à l'instant";
    if (d.inMinutes < 60) return 'il y a ${d.inMinutes} min';
    if (d.inHours < 24) return 'il y a ${d.inHours} h';
    if (d.inDays < 7) return 'il y a ${d.inDays} j';
    return '${t.day}/${t.month}/${t.year}';
  }
}
