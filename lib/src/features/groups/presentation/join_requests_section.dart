/// Les demandes pour entrer dans un cercle, vues par son créateur : une ligne
/// par personne, Accepter ou Refuser. Elles arrivent par le code d'un jumeau
/// (Agora, Arpente) et se mettent à jour en temps réel.
///
/// Choix non évidents :
/// - la section disparaît quand il n'y a rien à trancher (ni titre vide) ;
/// - accepter fait entrer quelqu'un qui n'est pas forcément ami du créateur :
///   c'est le créateur qui le choisit ici, comme il choisit ses amis ailleurs.
///   Le serveur retire la demande sans faire entrer si un blocage est apparu
///   entre-temps.
library;

import 'package:dewdrop/src/features/groups/application/group_providers.dart';
import 'package:dewdrop/src/features/groups/application/twin_providers.dart';
import 'package:dewdrop/src/features/groups/domain/twin_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class JoinRequestsSection extends ConsumerStatefulWidget {
  const JoinRequestsSection({super.key, required this.groupId});

  final String groupId;

  @override
  ConsumerState<JoinRequestsSection> createState() =>
      _JoinRequestsSectionState();
}

class _JoinRequestsSectionState extends ConsumerState<JoinRequestsSection> {
  /// Demandes en cours de traitement (boutons désactivés).
  final Set<String> _answering = {};

  @override
  Widget build(BuildContext context) {
    final w = Colors.white;
    final requests =
        ref.watch(joinRequestsForGroupProvider(widget.groupId)).value ??
        const <JoinRequest>[];
    if (requests.isEmpty) return const SizedBox.shrink();
    return Material(
      type: MaterialType.transparency,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8, left: 4, top: 8),
            child: Text(
              'Demandes pour entrer',
              style: TextStyle(
                fontSize: 13,
                letterSpacing: 0.6,
                fontWeight: FontWeight.w600,
                color: w.withValues(alpha: 0.6),
              ),
            ),
          ),
          for (final r in requests) _tile(w, r),
        ],
      ),
    );
  }

  Widget _tile(Color w, JoinRequest r) {
    final p = r.requester;
    final name = p.displayName?.isNotEmpty == true
        ? p.displayName!
        : '@${p.handle ?? '?'}';
    final busy = _answering.contains(p.id);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 6),
      leading: CircleAvatar(
        backgroundColor: w.withValues(alpha: 0.14),
        child: Text(name.isEmpty ? '?' : name[0].toUpperCase()),
      ),
      title: Text(name),
      subtitle: p.handle == null
          ? null
          : Text(
              '@${p.handle}',
              style: TextStyle(color: w.withValues(alpha: 0.5)),
            ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Refuser',
            icon: Icon(Icons.close_rounded, color: w.withValues(alpha: 0.6)),
            onPressed: busy ? null : () => _answer(r, accept: false),
          ),
          IconButton(
            tooltip: 'Accepter',
            icon: const Icon(Icons.check_rounded, color: Color(0xFF8FE3A8)),
            onPressed: busy ? null : () => _answer(r, accept: true),
          ),
        ],
      ),
    );
  }

  Future<void> _answer(JoinRequest r, {required bool accept}) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _answering.add(r.requester.id));
    try {
      await ref
          .read(twinRepositoryProvider)
          .answer(r.groupId, r.requester.id, accept: accept);
      ref
        ..invalidate(pendingJoinRequestsProvider)
        ..invalidate(groupMembersProvider(r.groupId));
    } on TwinException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } on Exception catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Action impossible pour le moment.')),
      );
    } finally {
      if (mounted) setState(() => _answering.remove(r.requester.id));
    }
  }
}
