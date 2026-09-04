import 'dart:async';

import 'package:dewdrop/src/common/app_exceptions.dart';
import 'package:dewdrop/src/features/profile/domain/profile.dart';
import 'package:dewdrop/src/features/thoughts/domain/thought.dart';
import 'package:dewdrop/src/features/thoughts/domain/thought_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Pure row→domain mapping for received thoughts. Extracted so the
/// **privacy-critical** anonymity rule (an anonymous thought never exposes its
/// sender) is unit-testable without a Supabase fake. [profilesBySenderId] holds
/// only the non-anonymous senders. A malformed/absent `created_at` falls back
/// to epoch 0 rather than throwing (keeps the whole list from crashing).
///
/// [groupNamesById] carries the names of the groups these pensées came from; an
/// id missing from it (we left the group since) yields a null `groupName`, and
/// the line falls back to "à un groupe" instead of a stale name.
List<ReceivedThought> mapReceivedThoughts(
  List<Map<String, dynamic>> rows,
  Map<String, Profile> profilesBySenderId, {
  Map<String, String> groupNamesById = const {},
}) {
  return [
    for (final r in rows)
      ReceivedThought(
        id: r['id'] as String,
        createdAt:
            DateTime.tryParse(r['created_at']?.toString() ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        isAnonymous: r['is_anonymous'] == true,
        sender: r['is_anonymous'] == true
            ? null
            : profilesBySenderId[r['sender_id']],
        groupId: r['group_id'] as String?,
        groupName: groupNamesById[r['group_id']],
      ),
  ];
}

class SupabaseThoughtRepository implements ThoughtRepository {
  SupabaseThoughtRepository(this._client);

  final SupabaseClient _client;

  String get _uid => _client.auth.currentUser!.id;

  /// Sends a "pensée" to [recipientId] (must be an accepted friend — enforced
  /// by RLS). When [anonymous], the recipient won't see who it's from. The
  /// server's 25/min flood cap surfaces as a [RateLimitedException], translated
  /// here so the UI never sees a raw PostgrestException.
  @override
  Future<void> sendThought(String recipientId, {bool anonymous = false}) async {
    try {
      await _client.from('thoughts').insert({
        'recipient_id': recipientId,
        'sender_id': _uid,
        'is_anonymous': anonymous,
      });
    } on PostgrestException catch (e) {
      if (e.message.contains('rate_limited')) {
        throw const RateLimitedException();
      }
      rethrow;
    }
  }

  @override
  Future<List<ReceivedThought>> receivedThoughts() async {
    final rows = await _client
        .from('thoughts')
        .select('id, sender_id, is_anonymous, created_at, group_id')
        .eq('recipient_id', _uid)
        .order('created_at', ascending: false)
        .limit(100);

    final senderIds = <String>{
      for (final r in rows)
        if (r['is_anonymous'] != true) r['sender_id'] as String,
    }.toList();
    final groupIds = <String>{
      for (final r in rows)
        if (r['group_id'] != null) r['group_id'] as String,
    }.toList();
    // Two independent lookups — resolve them together rather than pay two
    // round-trips in a row on a list the user is waiting for.
    final (profiles, groupNames) = await (
      _profilesByIds(senderIds),
      _groupNamesByIds(groupIds),
    ).wait;

    return mapReceivedThoughts(rows, profiles, groupNamesById: groupNames);
  }

  @override
  Future<List<String>> recentlyContactedRecipientIds({int limit = 24}) async {
    // Own sent rows only (RLS: auth.uid() = sender_id). The composite index
    // idx_thoughts_sender (sender_id, created_at desc) covers this. PostgREST
    // has no clean DISTINCT ON, so dedupe in Dart preserving recency order.
    final rows = await _client
        .from('thoughts')
        .select('recipient_id, created_at')
        .eq('sender_id', _uid)
        .order('created_at', ascending: false)
        .limit(limit);

    final seen = <String>{};
    final ids = <String>[];
    for (final r in rows) {
      final id = r['recipient_id'] as String?;
      if (id != null && seen.add(id)) ids.add(id);
    }
    return ids;
  }

  @override
  Stream<int> watchIncoming() {
    // RLS still applies to Realtime, but we also filter server-side so the
    // socket only carries this user's incoming pensées. Emit a monotonic tick
    // (not null) so every event is a distinct value that re-notifies listeners.
    final controller = StreamController<int>();
    var tick = 0;
    final channel = _client
        .channel('thoughts:incoming:$_uid')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'thoughts',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'recipient_id',
            value: _uid,
          ),
          callback: (_) => controller.add(++tick),
        );
    channel.subscribe();
    controller.onCancel = () => _client.removeChannel(channel);
    return controller.stream;
  }

  /// Names of the groups a batch of received pensées came from. RLS
  /// ("see my groups") only returns groups the user still belongs to, so a
  /// group they left is simply absent from the result — the UI then says
  /// "à un groupe" rather than showing a name it can no longer verify.
  Future<Map<String, String>> _groupNamesByIds(List<String> ids) async {
    if (ids.isEmpty) return {};
    final rows = await _client
        .from('groups')
        .select('id, name')
        .inFilter('id', ids);
    return {for (final m in rows) m['id'] as String: m['name'] as String};
  }

  Future<Map<String, Profile>> _profilesByIds(List<String> ids) async {
    if (ids.isEmpty) return {};
    // public_profiles: directory view (handle/name/avatar) — the base profiles
    // table is owner-only, so other users' names are read through it.
    final rows = await _client
        .from('public_profiles')
        .select()
        .inFilter('id', ids);
    return {for (final m in rows) m['id'] as String: Profile.fromMap(m)};
  }
}
