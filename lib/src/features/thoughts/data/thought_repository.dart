import 'dart:async';

import 'package:dewdrop/src/features/profile/domain/profile.dart';
import 'package:dewdrop/src/features/thoughts/domain/thought.dart';
import 'package:dewdrop/src/features/thoughts/domain/thought_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Pure row→domain mapping for received thoughts. Extracted so the
/// **privacy-critical** anonymity rule (an anonymous thought never exposes its
/// sender) is unit-testable without a Supabase fake. [profilesBySenderId] holds
/// only the non-anonymous senders. A malformed/absent `created_at` falls back
/// to epoch 0 rather than throwing (keeps the whole list from crashing).
List<ReceivedThought> mapReceivedThoughts(
  List<Map<String, dynamic>> rows,
  Map<String, Profile> profilesBySenderId,
) {
  return [
    for (final r in rows)
      ReceivedThought(
        id: r['id'] as String,
        createdAt: DateTime.tryParse(r['created_at']?.toString() ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        isAnonymous: r['is_anonymous'] == true,
        sender: r['is_anonymous'] == true ? null : profilesBySenderId[r['sender_id']],
      ),
  ];
}

class SupabaseThoughtRepository implements ThoughtRepository {
  SupabaseThoughtRepository(this._client);

  final SupabaseClient _client;

  String get _uid => _client.auth.currentUser!.id;

  /// Sends a "pensée" to [recipientId] (must be an accepted friend — enforced
  /// by RLS). When [anonymous], the recipient won't see who it's from.
  @override
  Future<void> sendThought(String recipientId, {bool anonymous = false}) =>
      _client.from('thoughts').insert({
        'recipient_id': recipientId,
        'sender_id': _uid,
        'is_anonymous': anonymous,
      });

  @override
  Future<List<ReceivedThought>> receivedThoughts() async {
    final rows = await _client
        .from('thoughts')
        .select('id, sender_id, is_anonymous, created_at')
        .eq('recipient_id', _uid)
        .order('created_at', ascending: false)
        .limit(100);

    final senderIds = <String>{
      for (final r in rows)
        if (r['is_anonymous'] != true) r['sender_id'] as String,
    }.toList();
    final profiles = await _profilesByIds(senderIds);

    return mapReceivedThoughts(rows, profiles);
  }

  @override
  Stream<int> watchIncoming() {
    // RLS still applies to Realtime, but we also filter server-side so the
    // socket only carries this user's incoming pensées. Emit a monotonic tick
    // (not null) so every event is a distinct value that re-notifies listeners.
    final controller = StreamController<int>();
    var tick = 0;
    final channel = _client.channel('thoughts:incoming:$_uid').onPostgresChanges(
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

  Future<Map<String, Profile>> _profilesByIds(List<String> ids) async {
    if (ids.isEmpty) return {};
    final rows = await _client.from('profiles').select().inFilter('id', ids);
    return {for (final m in rows) m['id'] as String: Profile.fromMap(m)};
  }
}
