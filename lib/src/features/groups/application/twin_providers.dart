/// Jumelage d'un cercle avec un groupe d'une autre app (Agora, Arpente) et
/// demandes d'adhésion : providers et [TwinService] (lancer, accepter une
/// demande, compléter, défaire). Le protocole et ses liens sont dans
/// `domain/twin.dart`.
///
/// Choix non évidents :
/// - les jumelages lancés d'ici vivent dans les préférences de l'appareil
///   ([TwinRequestStore], 24 h) et non en mémoire : ouvrir Agora ou Arpente
///   peut faire fermer DewDrop par Android, et la réponse rouvre alors une
///   app neuve. Une réponse n'est acceptée que si elle répond à une demande
///   partie d'ici (même jeton, même app, même code) — sans quoi un membre qui
///   connaît le code d'un jumeau pourrait forger une réponse et faire
///   rattacher un groupe à lui ;
/// - l'horloge et la fabrique de jetons sont des providers pour que les tests
///   les fixent ;
/// - [TwinService] n'invalide rien : les écrans invalident ce qu'ils
///   affichent, comme le reste de la feature.
///
/// Invariant : une demande consommée par [TwinService.complete] est oubliée —
/// rejouer la même réponse ne relie plus rien.
library;

import 'dart:convert';

import 'package:dewdrop/src/features/ambient/application/ambient_providers.dart';
import 'package:dewdrop/src/features/auth/application/auth_providers.dart';
import 'package:dewdrop/src/features/groups/application/group_providers.dart';
import 'package:dewdrop/src/features/groups/data/twin_repository.dart';
import 'package:dewdrop/src/features/groups/domain/group.dart';
import 'package:dewdrop/src/features/groups/domain/group_repository.dart';
import 'package:dewdrop/src/features/groups/domain/twin.dart';
import 'package:dewdrop/src/features/groups/domain/twin_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final twinRepositoryProvider = Provider<TwinRepository>((ref) {
  return SupabaseTwinRepository(Supabase.instance.client);
});

/// L'heure courante ; remplacée dans les tests.
final twinClockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// Fabrique des jetons de jumelage ; remplacée dans les tests.
final twinStateGeneratorProvider = Provider<String Function()>(
  (ref) => newTwinState,
);

bool _signedIn(Ref ref) {
  ref.watch(authStateChangesProvider);
  return ref.watch(authRepositoryProvider).currentSession != null;
}

/// Les jumeaux d'un cercle.
final groupTwinsProvider = FutureProvider.family<List<GroupTwin>, String>((
  ref,
  groupId,
) {
  if (!_signedIn(ref)) return const <GroupTwin>[];
  return ref.watch(twinRepositoryProvider).twins(groupId);
});

/// Un tick à chaque demande reçue, tranchée ou annulée.
final joinRequestChangesProvider = StreamProvider<int>((ref) {
  if (!_signedIn(ref)) return const Stream<int>.empty();
  return ref.watch(twinRepositoryProvider).watchRequests();
});

/// Les demandes en attente dans les cercles que je crée (temps réel).
final pendingJoinRequestsProvider = FutureProvider<List<JoinRequest>>((ref) {
  if (!_signedIn(ref)) return const <JoinRequest>[];
  ref.watch(joinRequestChangesProvider);
  return ref.watch(twinRepositoryProvider).pendingRequests();
});

/// Les demandes en attente pour un cercle.
final joinRequestsForGroupProvider =
    Provider.family<AsyncValue<List<JoinRequest>>, String>(
      (ref, groupId) => ref
          .watch(pendingJoinRequestsProvider)
          .whenData(
            (all) => [
              for (final r in all)
                if (r.groupId == groupId) r,
            ],
          ),
    );

/// Les jumelages lancés depuis cet appareil, par jeton, dans les
/// préférences ; une entrée périmée ou illisible est ignorée puis effacée.
final class TwinRequestStore {
  TwinRequestStore(this._prefs, this._now);

  static const _key = 'twin_requests_v1';

  final SharedPreferences _prefs;
  final DateTime Function() _now;

  Map<String, TwinRequestSent> _read() {
    final raw = _prefs.getString(_key);
    if (raw == null) return {};
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return {};
    }
    if (decoded is! Map<String, dynamic>) return {};
    final now = _now();
    return {
      for (final MapEntry(:key, :value) in decoded.entries)
        if (value is Map<String, dynamic>)
          if (TwinRequestSent.fromJson(value) case final request?)
            if (now.difference(request.sentAt) <= twinRequestLifetime)
              key: request,
    };
  }

  Future<void> _write(Map<String, TwinRequestSent> requests) =>
      _prefs.setString(
        _key,
        jsonEncode({
          for (final MapEntry(:key, :value) in requests.entries)
            key: value.toJson(),
        }),
      );

  Future<void> remember(String state, TwinRequestSent request) =>
      _write({..._read(), state: request});

  TwinRequestSent? match(TwinResponse response) =>
      matchTwinRequest(_read(), response, _now());

  Future<void> forget(String state) => _write({..._read()}..remove(state));
}

final twinRequestStoreProvider = Provider<TwinRequestStore>(
  (ref) => TwinRequestStore(
    ref.watch(sharedPreferencesProvider),
    ref.watch(twinClockProvider),
  ),
);

final class TwinService {
  const TwinService(
    this._twins,
    this._groups,
    this._store,
    this._newState,
    this._now,
  );

  final TwinRepository _twins;
  final GroupRepository _groups;
  final TwinRequestStore _store;
  final String Function() _newState;
  final DateTime Function() _now;

  /// Lance le jumelage de [group] avec [app] : l'adresse de la demande à
  /// ouvrir. Relancer reprend le même code, avec un jeton neuf.
  Future<Uri> start(Group group, TwinApp app) async {
    final code = await _twins.twinGroup(group.id, app);
    final state = _newState();
    await _store.remember(
      state,
      TwinRequestSent(app: app, groupId: group.id, code: code, sentAt: _now()),
    );
    return twinRequestUri(app, code: code, name: group.name, state: state);
  }

  /// Accepte une demande venue d'une autre app : jumelle le cercle [groupId],
  /// ou un nouveau cercle nommé [newGroupName] si [groupId] est nul. Rend le
  /// cercle et l'adresse de la réponse à ouvrir.
  Future<({String groupId, Uri response})> accept(
    TwinRequest request, {
    required String? groupId,
    required String newGroupName,
  }) async {
    final id = groupId ?? (await _groups.createGroup(newGroupName)).id;
    final code = await _twins.twinGroup(
      id,
      request.app,
      remoteCode: request.remoteCode,
    );
    return (
      groupId: id,
      response: twinResponseUri(
        request.app,
        code: code,
        forCode: request.remoteCode,
        state: request.state,
      ),
    );
  }

  /// Le cercle auquel répond [response], s'il a été lancé d'ici.
  String? groupFor(TwinResponse response) => _store.match(response)?.groupId;

  /// Complète le jumelage que [response] achève ; l'id du cercle.
  Future<String> complete(TwinResponse response) async {
    final request = _store.match(response);
    if (request == null) {
      throw const TwinException(
        'Ce lien ne répond à aucun jumelage lancé depuis ce téléphone.',
      );
    }
    await _twins.twinGroup(
      request.groupId,
      response.app,
      remoteCode: response.remoteCode,
    );
    await _store.forget(response.state);
    return request.groupId;
  }

  /// Défait le jumelage avec [app] : le code donné n'ouvre plus rien.
  Future<void> unlink(String groupId, TwinApp app) =>
      _twins.untwinGroup(groupId, app);
}

final twinServiceProvider = Provider<TwinService>(
  (ref) => TwinService(
    ref.watch(twinRepositoryProvider),
    ref.watch(groupRepositoryProvider),
    ref.watch(twinRequestStoreProvider),
    ref.watch(twinStateGeneratorProvider),
    ref.watch(twinClockProvider),
  ),
);
