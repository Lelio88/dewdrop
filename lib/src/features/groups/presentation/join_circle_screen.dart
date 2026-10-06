/// « Demander à rejoindre un cercle » (route `/join-circle`) : ouvert par un
/// lien `rejoindre.html#code=…` venu d'Agora ou d'Arpente, ou depuis l'écran
/// Amis pour saisir le code à la main (repli quand le lien a ouvert le
/// navigateur au lieu de l'app).
///
/// Choix non évidents :
/// - un code ne fait jamais entrer : l'écran montre le cercle et son
///   créateur, puis envoie une **demande** que celui-ci accepte ou refuse ;
/// - un code inconnu, défait ou refusé (blocage) dit la même chose : « aucun
///   cercle ne correspond ». Rien ne doit trahir qu'un cercle existe derrière
///   un code qu'on n'a pas le droit d'utiliser ;
/// - le code se saisit en majuscules, sans les caractères ambigus : une
///   faute de frappe est refusée avant d'interroger le serveur, qui compte
///   les essais ratés.
library;

import 'package:dewdrop/src/features/groups/application/group_providers.dart';
import 'package:dewdrop/src/features/groups/application/twin_providers.dart';
import 'package:dewdrop/src/features/groups/domain/twin.dart';
import 'package:dewdrop/src/features/groups/domain/twin_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class JoinCircleScreen extends ConsumerStatefulWidget {
  const JoinCircleScreen({super.key, this.initialCode});

  /// Le code lu dans le lien, s'il y en a un.
  final String? initialCode;

  @override
  ConsumerState<JoinCircleScreen> createState() => _JoinCircleScreenState();
}

/// Où en est la recherche du code saisi.
sealed class _Lookup {
  const _Lookup();
}

final class _Idle extends _Lookup {
  const _Idle();
}

final class _NotFound extends _Lookup {
  const _NotFound();
}

final class _Found extends _Lookup {
  const _Found(this.preview, this.code);

  final JoinCodePreview preview;
  final String code;
}

final class _Sent extends _Lookup {
  const _Sent(this.preview);

  final JoinCodePreview preview;
}

class _JoinCircleScreenState extends ConsumerState<JoinCircleScreen> {
  late final _code = TextEditingController(
    text: widget.initialCode?.toUpperCase() ?? '',
  );
  _Lookup _lookup = const _Idle();
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    if (dewdropCodePattern.hasMatch(_code.text)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _find());
    }
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _find() async {
    final code = _code.text.trim().toUpperCase();
    if (!dewdropCodePattern.hasMatch(code)) {
      setState(
        () => _error = 'Un code DewDrop a 8 caractères (lettres et chiffres).',
      );
      return;
    }
    setState(() {
      _error = null;
      _busy = true;
    });
    try {
      final preview = await ref.read(twinRepositoryProvider).preview(code);
      if (!mounted) return;
      setState(
        () => _lookup = preview == null
            ? const _NotFound()
            : _Found(preview, code),
      );
    } on TwinException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on Exception catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Impossible de vérifier ce code pour le moment.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _request(_Found found) async {
    setState(() => _busy = true);
    try {
      final outcome = await ref
          .read(twinRepositoryProvider)
          .requestToJoin(found.code);
      if (!mounted) return;
      setState(
        () => _lookup = switch (outcome) {
          JoinRequestOutcome.requested ||
          JoinRequestOutcome.alreadyRequested => _Sent(found.preview),
          JoinRequestOutcome.alreadyMember => _Found(
            JoinCodePreview(
              groupId: found.preview.groupId,
              name: found.preview.name,
              creatorHandle: found.preview.creatorHandle,
              isMember: true,
              alreadyRequested: false,
            ),
            found.code,
          ),
          JoinRequestOutcome.invalid => const _NotFound(),
        },
      );
    } on TwinException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on Exception catch (_) {
      if (mounted) {
        setState(() => _error = 'Demande impossible pour le moment.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openCircle(String groupId) async {
    final groups = await ref.read(myGroupsProvider.future);
    final group = groups.where((g) => g.id == groupId).firstOrNull;
    if (!mounted || group == null) return;
    context.pushReplacement('/group', extra: group);
  }

  @override
  Widget build(BuildContext context) {
    final w = Colors.white;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('Rejoindre un cercle'),
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
              Text(
                'Saisis le code reçu depuis Agora ou Arpente. Ta demande part à '
                'la personne qui a créé le cercle : tu y entres quand elle '
                'l\'accepte.',
                style: TextStyle(color: w.withValues(alpha: 0.6), fontSize: 14),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _code,
                maxLength: 8,
                textCapitalization: TextCapitalization.characters,
                autocorrect: false,
                enableSuggestions: false,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp('[A-Za-z0-9]')),
                  _UpperCase(),
                ],
                decoration: InputDecoration(
                  labelText: 'Code du cercle',
                  errorText: _error,
                ),
                onChanged: (_) {
                  if (_lookup is! _Idle) {
                    setState(() => _lookup = const _Idle());
                  }
                },
                onSubmitted: (_) => _find(),
              ),
              const SizedBox(height: 8),
              if (_lookup is _Idle || _lookup is _NotFound)
                FilledButton(
                  onPressed: _busy ? null : _find,
                  child: Text(_busy ? 'Un instant…' : 'Voir le cercle'),
                ),
              const SizedBox(height: 20),
              ..._result(w),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _result(Color w) {
    TextStyle title() =>
        const TextStyle(fontSize: 18, fontWeight: FontWeight.w600);
    String byCreator(JoinCodePreview p) =>
        p.creatorHandle == null ? '' : ', le cercle de @${p.creatorHandle}';
    return switch (_lookup) {
      _Idle() => const [],
      _NotFound() => [
        Text(
          'Aucun cercle ne correspond à ce code. Vérifie-le, ou demande un '
          'nouveau lien.',
          style: TextStyle(color: w.withValues(alpha: 0.6)),
        ),
      ],
      _Found(:final preview) when preview.isMember => [
        Text('Tu fais déjà partie de « ${preview.name} ».', style: title()),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: () => _openCircle(preview.groupId),
          child: const Text('Ouvrir le cercle'),
        ),
      ],
      _Found(:final preview) when preview.alreadyRequested => [
        Text(
          'Ta demande pour « ${preview.name} » attend une réponse.',
          style: title(),
        ),
      ],
      final _Found found => [
        Text(
          '« ${found.preview.name} »${byCreator(found.preview)}',
          style: title(),
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: _busy ? null : () => _request(found),
          child: Text(_busy ? 'Un instant…' : 'Demander à rejoindre'),
        ),
      ],
      _Sent(:final preview) => [
        Text('Demande envoyée ✨', style: title()),
        const SizedBox(height: 8),
        Text(
          preview.creatorHandle == null
              ? 'Tu entreras dans « ${preview.name} » dès que ta demande sera acceptée.'
              : 'Tu entreras dans « ${preview.name} » dès que @${preview.creatorHandle} '
                    'aura accepté ta demande.',
          style: TextStyle(color: w.withValues(alpha: 0.7)),
        ),
      ],
    };
  }
}

class _UpperCase extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) => newValue.copyWith(text: newValue.text.toUpperCase());
}
