import 'package:dewdrop/src/features/profile/domain/profile.dart';
import 'package:dewdrop/src/features/thoughts/domain/thought.dart';
import 'package:dewdrop/src/features/thoughts/domain/thought_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

    return [
      for (final r in rows)
        ReceivedThought(
          id: r['id'] as String,
          createdAt: DateTime.parse(r['created_at'] as String),
          isAnonymous: r['is_anonymous'] == true,
          sender: r['is_anonymous'] == true ? null : profiles[r['sender_id']],
        ),
    ];
  }

  Future<Map<String, Profile>> _profilesByIds(List<String> ids) async {
    if (ids.isEmpty) return {};
    final rows = await _client.from('profiles').select().inFilter('id', ids);
    return {for (final m in rows) m['id'] as String: Profile.fromMap(m)};
  }
}
