/// Écran d'un lien de jumelage venu d'Agora ou d'Arpente (`jumeler.html#…`,
/// route `/twin`) : une **demande** (choisir le cercle à jumeler) ou une
/// **réponse** (relier le cercle dont le jumelage a été lancé d'ici).
///
/// Choix non évidents :
/// - les paramètres sont validés par `parseTwinLink` avant tout affichage :
///   un lien mal formé n'ouvre qu'un message, jamais un bouton ;
/// - seuls les cercles que l'on a créés sont proposés (le serveur ne laisse
///   jumeler que le créateur) ; un nouveau cercle, nommé comme le jumeau, est
///   présélectionné ;
/// - une réponse n'est montrée que si elle répond à un jumelage lancé depuis
///   cet appareil, et le cercle concerné est figé à l'ouverture :
///   l'enregistrement oublie la demande, l'écran ne doit pas basculer sur
///   « inconnue » pendant qu'il navigue ;
/// - si l'autre app ne s'ouvre pas, le jumeau reste enregistré ici et
///   l'écran le dit.
library;

import 'package:dewdrop/src/common/legal_links.dart';
import 'package:dewdrop/src/features/auth/application/auth_providers.dart';
import 'package:dewdrop/src/features/groups/application/group_providers.dart';
import 'package:dewdrop/src/features/groups/application/twin_providers.dart';
import 'package:dewdrop/src/features/groups/domain/group.dart';
import 'package:dewdrop/src/features/groups/domain/twin.dart';
import 'package:dewdrop/src/features/groups/domain/twin_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Choix « un nouveau cercle » (un id de cercle n'est jamais vide).
const _newCircle = '';

/// Longueur maximale d'un nom de cercle (contrainte de la table `groups`).
const _maxNameLength = 60;

class TwinScreen extends ConsumerStatefulWidget {
  const TwinScreen({super.key, required this.params});

  /// Paramètres du lien, tels que reçus.
  final Map<String, String> params;

  @override
  ConsumerState<TwinScreen> createState() => _TwinScreenState();
}

class _TwinScreenState extends ConsumerState<TwinScreen> {
  late final TwinLink? _link = parseTwinLink(widget.params);
  late final _name = TextEditingController(
    text: switch (_link) {
      TwinRequest(:final name) => name ?? '',
      _ => '',
    },
  );

  /// Le cercle auquel répond une réponse, figé à l'ouverture.
  String? _answeredGroup;
  String _target = _newCircle;
  String? _nameError;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    if (_link case final TwinResponse response) {
      _answeredGroup = ref.read(twinServiceProvider).groupFor(response);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('Jumelage'),
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
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
            children: [
              switch (_link) {
                null => const _Hint('Ce lien de jumelage n\'est pas valide.'),
                final TwinRequest request => _request(request),
                final TwinResponse response => _response(response),
              },
            ],
          ),
        ),
      ),
    );
  }

  Widget _request(TwinRequest request) {
    final app = request.app.displayName;
    final uid = ref.watch(authRepositoryProvider).currentUser?.id ?? '';
    final groups = ref.watch(myGroupsProvider);
    final name = request.name;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          name == null
              ? 'Un groupe $app propose de se jumeler avec un de tes cercles.'
              : 'Le groupe « $name » d\'$app propose de se jumeler avec un de tes cercles.',
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 10),
        _Hint(
          'Tes membres verront « Rejoindre aussi dans $app », et ceux du groupe '
          '$app pourront demander à entrer dans ton cercle : tu acceptes chaque '
          'demande. Personne n\'est ajouté d\'office.',
        ),
        const SizedBox(height: 18),
        groups.when(
          loading: () => const Center(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
          error: (_, _) =>
              const _Hint('Impossible de charger tes cercles pour le moment.'),
          data: (list) => _targets([
            for (final g in list)
              if (g.isCreator(uid)) g,
          ]),
        ),
        if (_target == _newCircle)
          TextField(
            controller: _name,
            maxLength: _maxNameLength,
            decoration: InputDecoration(
              labelText: 'Nom du cercle',
              errorText: _nameError,
            ),
          ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _busy ? null : () => _accept(request),
          child: Text(_busy ? 'Un instant…' : 'Jumeler'),
        ),
      ],
    );
  }

  Widget _targets(List<Group> mine) => RadioGroup<String>(
    groupValue: _target,
    onChanged: (target) {
      if (target != null) setState(() => _target = target);
    },
    child: Column(
      children: [
        const RadioListTile<String>(
          value: _newCircle,
          title: Text('Un nouveau cercle'),
          contentPadding: EdgeInsets.zero,
        ),
        for (final g in mine)
          RadioListTile<String>(
            value: g.id,
            title: Text(g.name),
            contentPadding: EdgeInsets.zero,
          ),
      ],
    ),
  );

  Future<void> _accept(TwinRequest request) async {
    final newName = _name.text.trim();
    final isNew = _target == _newCircle;
    // En caractères, comme char_length côté serveur (pas en unités UTF-16).
    final length = newName.runes.length;
    if (isNew && (length == 0 || length > _maxNameLength)) {
      setState(
        () => _nameError = 'Donne un nom au cercle (60 caractères au plus).',
      );
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    void say(String message) =>
        messenger.showSnackBar(SnackBar(content: Text(message)));
    setState(() {
      _nameError = null;
      _busy = true;
    });
    final app = request.app.displayName;
    try {
      final answer = await ref
          .read(twinServiceProvider)
          .accept(
            request,
            groupId: isNew ? null : _target,
            newGroupName: newName,
          );
      ref.invalidate(myGroupsProvider);
      ref.invalidate(groupTwinsProvider(answer.groupId));
      final opened = await ref.read(externalLinkOpenerProvider)(
        answer.response,
      );
      say(
        opened
            ? 'Cercle jumelé avec $app ✨'
            : 'Cercle jumelé ici, mais $app n\'a pas pu s\'ouvrir pour finir.',
      );
      if (mounted) await _openGroup(answer.groupId);
    } on TwinException catch (e) {
      say(e.message);
    } on Exception catch (_) {
      say('Jumelage impossible pour le moment.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _response(TwinResponse response) {
    final groupId = _answeredGroup;
    const unknown = _Hint(
      'Ce lien ne répond à aucun jumelage lancé depuis ce téléphone. Relance '
      'le jumelage depuis ton cercle.',
    );
    if (groupId == null) return unknown;
    return ref
        .watch(myGroupsProvider)
        .when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) =>
              const _Hint('Impossible de charger tes cercles pour le moment.'),
          data: (list) {
            final group = list.where((g) => g.id == groupId).firstOrNull;
            if (group == null) return unknown;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Relier « ${group.name} » au groupe ${response.app.displayName} ?',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _busy ? null : () => _complete(response),
                  child: Text(_busy ? 'Un instant…' : 'Relier'),
                ),
              ],
            );
          },
        );
  }

  Future<void> _complete(TwinResponse response) async {
    final messenger = ScaffoldMessenger.of(context);
    void say(String message) =>
        messenger.showSnackBar(SnackBar(content: Text(message)));
    setState(() => _busy = true);
    try {
      final groupId = await ref.read(twinServiceProvider).complete(response);
      ref.invalidate(groupTwinsProvider(groupId));
      say('Cercle jumelé avec ${response.app.displayName} ✨');
      if (mounted) await _openGroup(groupId);
    } on TwinException catch (e) {
      say(e.message);
    } on Exception catch (_) {
      say('Jumelage impossible pour le moment.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Remplace cet écran par celui du cercle.
  Future<void> _openGroup(String groupId) async {
    final groups = await ref.read(myGroupsProvider.future);
    final group = groups.where((g) => g.id == groupId).firstOrNull;
    if (!mounted) return;
    if (group == null) {
      context.pop();
      return;
    }
    context.pushReplacement('/group', extra: group);
  }
}

class _Hint extends StatelessWidget {
  const _Hint(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 14),
  );
}
