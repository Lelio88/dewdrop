/// [TwinRepository] sur Supabase : RPC du jumelage et des demandes
/// (`twin_group`, `untwin_group`, `join_code_preview`, `request_to_join`,
/// `answer_join_request`), lectures de `group_twins` et
/// `group_join_requests`.
///
/// Choix non évidents :
/// - `group_twins` se lit colonne par colonne : `code` n'est accordé à
///   personne (un `select *` échouerait en 42501) ;
/// - les demandes visibles sont les miennes et celles de mes cercles (RLS) :
///   les miennes sont écartées ici, la liste ne sert qu'au créateur ;
/// - les erreurs Postgres connues deviennent des [TwinException] déjà
///   rédigées ; l'interface n'apprend jamais ce qu'est un PostgrestException.
library;

import 'dart:async';

import 'package:dewdrop/src/features/groups/domain/twin.dart';
import 'package:dewdrop/src/features/groups/domain/twin_repository.dart';
import 'package:dewdrop/src/features/profile/domain/profile.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseTwinRepository implements TwinRepository {
  SupabaseTwinRepository(this._client);

  final SupabaseClient _client;

  String get _uid => _client.auth.currentUser!.id;

  static const _messages = {
    'not_group_creator':
        'Seule la personne qui a créé le cercle peut faire ça.',
    'twin_exists':
        'Ce cercle est déjà jumelé avec un autre groupe. Défais d\'abord ce jumelage.',
    'invalid_twin_code': 'Ce lien de jumelage n\'est pas valide.',
    'invalid_twin_app': 'Ce lien de jumelage n\'est pas valide.',
    'rate_limited': 'Trop d\'essais d\'affilée : réessaie dans une heure.',
    'request_not_found': 'Cette demande n\'est plus en attente.',
  };

  Future<T> _guard<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on PostgrestException catch (e) {
      for (final MapEntry(:key, :value) in _messages.entries) {
        if (e.message.contains(key)) throw TwinException(value);
      }
      rethrow;
    }
  }

  @override
  Future<List<GroupTwin>> twins(String groupId) async {
    final rows = await _client
        .from('group_twins')
        .select('app, remote_code')
        .eq('group_id', groupId);
    return [
      for (final row in rows)
        if (TwinApp.fromCode(row['app'] as String?) case final app?)
          GroupTwin(app: app, remoteCode: row['remote_code'] as String?),
    ];
  }

  @override
  Future<String> twinGroup(String groupId, TwinApp app, {String? remoteCode}) =>
      _guard(() async {
        final code = await _client.rpc(
          'twin_group',
          params: {
            'p_group': groupId,
            'p_app': app.code,
            'p_remote_code': ?remoteCode,
          },
        );
        return code as String;
      });

  @override
  Future<void> untwinGroup(String groupId, TwinApp app) => _guard(
    () => _client.rpc(
      'untwin_group',
      params: {'p_group': groupId, 'p_app': app.code},
    ),
  );

  @override
  Future<JoinCodePreview?> preview(String code) => _guard(() async {
    final rows = await _client.rpc(
      'join_code_preview',
      params: {'p_code': code},
    );
    final list = rows as List<dynamic>;
    if (list.isEmpty) return null;
    final row = list.first as Map<String, dynamic>;
    return JoinCodePreview(
      groupId: row['group_id'] as String,
      name: row['name'] as String,
      creatorHandle: row['creator_handle'] as String?,
      isMember: row['is_member'] as bool,
      alreadyRequested: row['already_requested'] as bool,
    );
  });

  @override
  Future<JoinRequestOutcome> requestToJoin(String code) => _guard(() async {
    final outcome = await _client.rpc(
      'request_to_join',
      params: {'p_code': code},
    );
    return switch (outcome as String?) {
      'requested' => JoinRequestOutcome.requested,
      'already_requested' => JoinRequestOutcome.alreadyRequested,
      'already_member' => JoinRequestOutcome.alreadyMember,
      _ => JoinRequestOutcome.invalid,
    };
  });

  @override
  Future<List<JoinRequest>> pendingRequests() async {
    final rows = await _client
        .from('group_join_requests')
        .select('group_id, user_id, created_at')
        .neq('user_id', _uid)
        .order('created_at');
    if (rows.isEmpty) return const [];
    final ids = {for (final r in rows) r['user_id'] as String};
    // Noms par la vue publique (profiles n'est lisible que par son titulaire).
    final profiles = await _client
        .from('public_profiles')
        .select()
        .inFilter('id', ids.toList());
    final byId = {
      for (final m in profiles) m['id'] as String: Profile.fromMap(m),
    };
    return [
      for (final r in rows)
        if (byId[r['user_id']] case final requester?)
          JoinRequest(
            groupId: r['group_id'] as String,
            requester: requester,
            createdAt: DateTime.parse(r['created_at'] as String),
          ),
    ];
  }

  @override
  Future<void> answer(String groupId, String userId, {required bool accept}) =>
      _guard(
        () => _client.rpc(
          'answer_join_request',
          params: {'p_group': groupId, 'p_user': userId, 'p_accept': accept},
        ),
      );

  @override
  Stream<int> watchRequests() {
    // La RLS ne livre que mes demandes et celles de mes cercles. Un compteur
    // monotone, pour que chaque événement re-notifie Riverpod.
    final controller = StreamController<int>();
    var tick = 0;
    final channel = _client
        .channel('join_requests:$_uid')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'group_join_requests',
          callback: (_) => controller.add(++tick),
        );
    channel.subscribe();
    controller.onCancel = () => _client.removeChannel(channel);
    return controller.stream;
  }
}
