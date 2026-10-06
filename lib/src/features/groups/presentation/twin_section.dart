/// Le jumelage vu depuis l'écran d'un cercle : le bandeau « Ce cercle existe
/// aussi dans … » pour tous les membres ([TwinBanner]), et la section où le
/// créateur lance, relance ou défait un jumelage ([TwinManager]).
///
/// Choix non évidents :
/// - le bandeau n'affiche qu'un jumeau complet (un jumeau en attente n'a pas
///   encore de code à rejoindre) et se tait si la lecture échoue : un
///   bandeau en panne ne doit pas masquer les membres ;
/// - l'adresse de l'autre app est reconstruite depuis sa base fixe et le
///   code validé (`TwinApp.joinUri`), jamais lue d'un lien reçu ;
/// - défaire tue le code donné à l'autre app ; la confirmation dit que
///   l'autre app garde son bouton jusqu'à ce qu'on l'y retire.
library;

import 'package:dewdrop/src/common/legal_links.dart';
import 'package:dewdrop/src/features/groups/application/twin_providers.dart';
import 'package:dewdrop/src/features/groups/domain/group.dart';
import 'package:dewdrop/src/features/groups/domain/twin.dart';
import 'package:dewdrop/src/features/groups/domain/twin_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const _accent = Color(0xFF8FE3A8);

/// « Ce cercle existe aussi dans … — Rejoindre », un par jumeau complet.
class TwinBanner extends ConsumerWidget {
  const TwinBanner({super.key, required this.groupId});

  final String groupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final twins = ref.watch(groupTwinsProvider(groupId)).value ?? const [];
    final complete = [
      for (final twin in twins)
        if (twin.remoteCode != null) twin,
    ];
    if (complete.isEmpty) return const SizedBox.shrink();
    return Material(
      type: MaterialType.transparency,
      child: Column(
        children: [
          for (final twin in complete)
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 6),
              leading: Icon(
                Icons.link_rounded,
                color: Colors.white.withValues(alpha: 0.85),
              ),
              title: Text(
                'Ce cercle existe aussi dans ${twin.app.displayName}',
              ),
              trailing: TextButton(
                onPressed: () => _open(
                  context,
                  ref,
                  twin.app,
                  twin.app.joinUri(twin.remoteCode!),
                ),
                child: const Text(
                  'Rejoindre',
                  style: TextStyle(color: _accent),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

Future<void> _open(
  BuildContext context,
  WidgetRef ref,
  TwinApp app,
  Uri uri,
) async {
  final messenger = ScaffoldMessenger.of(context);
  if (!await ref.read(externalLinkOpenerProvider)(uri)) {
    messenger.showSnackBar(
      SnackBar(content: Text('${app.displayName} n\'a pas pu s\'ouvrir.')),
    );
  }
}

/// La section « Jumelage » du créateur : une ligne par app jumelle.
class TwinManager extends ConsumerStatefulWidget {
  const TwinManager({super.key, required this.group});

  final Group group;

  @override
  ConsumerState<TwinManager> createState() => _TwinManagerState();
}

class _TwinManagerState extends ConsumerState<TwinManager> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final w = Colors.white;
    final twins = ref.watch(groupTwinsProvider(widget.group.id));
    return Material(
      type: MaterialType.transparency,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 4),
            child: Text(
              'Relie ce cercle à un groupe Agora (agendas partagés) ou Arpente '
              '(visites) : chacun rejoint l\'autre s\'il le veut, et c\'est toi '
              'qui acceptes qui entre ici.',
              style: TextStyle(color: w.withValues(alpha: 0.5), fontSize: 12),
            ),
          ),
          twins.when(
            loading: () => const SizedBox(height: 48),
            error: (_, _) => Padding(
              padding: const EdgeInsets.all(6),
              child: Text(
                'Impossible de charger le jumelage.',
                style: TextStyle(color: w.withValues(alpha: 0.5)),
              ),
            ),
            data: (list) => Column(
              children: [
                for (final app in TwinApp.values)
                  _row(w, app, list.where((t) => t.app == app).firstOrNull),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(Color w, TwinApp app, GroupTwin? twin) {
    final name = app.displayName;
    final unlink = IconButton(
      tooltip: 'Défaire',
      icon: Icon(Icons.link_off_rounded, color: w.withValues(alpha: 0.5)),
      onPressed: _busy ? null : () => _unlink(app),
    );
    return switch (twin) {
      null => ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 6),
        leading: Icon(Icons.add_link_rounded, color: w.withValues(alpha: 0.85)),
        title: Text('Jumeler avec $name'),
        onTap: _busy ? null : () => _start(app),
      ),
      GroupTwin(isPending: true) => ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 6),
        leading: Icon(
          Icons.hourglass_bottom_rounded,
          color: w.withValues(alpha: 0.6),
        ),
        title: Text('En attente de $name'),
        subtitle: Text(
          'Touche pour relancer',
          style: TextStyle(color: w.withValues(alpha: 0.5)),
        ),
        onTap: _busy ? null : () => _start(app),
        trailing: unlink,
      ),
      GroupTwin() => ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 6),
        leading: const Icon(Icons.link_rounded, color: _accent),
        title: Text('Jumelé avec $name'),
        trailing: unlink,
      ),
    };
  }

  /// Lance (ou relance) le jumelage : ouvre la demande dans l'autre app.
  Future<void> _start(TwinApp app) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final request = await ref
          .read(twinServiceProvider)
          .start(widget.group, app);
      ref.invalidate(groupTwinsProvider(widget.group.id));
      if (!await ref.read(externalLinkOpenerProvider)(request)) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              '${app.displayName} n\'a pas pu s\'ouvrir. Le jumelage reste en '
              'attente : relance-le d\'ici.',
            ),
          ),
        );
      }
    } on TwinException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } on Exception catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Jumelage impossible pour le moment.')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _unlink(TwinApp app) async {
    final messenger = ScaffoldMessenger.of(context);
    final name = app.displayName;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Défaire le jumelage avec $name ?'),
        content: Text(
          'Le code donné à $name n\'ouvrira plus rien. Les demandes déjà '
          'reçues restent à trancher, et le groupe $name garde son bouton '
          'jusqu\'à ce qu\'on l\'y retire.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Défaire',
              style: TextStyle(color: Color(0xFFFF6B5A)),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(twinServiceProvider).unlink(widget.group.id, app);
      ref.invalidate(groupTwinsProvider(widget.group.id));
      messenger.showSnackBar(
        SnackBar(content: Text('Jumelage avec $name défait.')),
      );
    } on TwinException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } on Exception catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Action impossible pour le moment.')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
