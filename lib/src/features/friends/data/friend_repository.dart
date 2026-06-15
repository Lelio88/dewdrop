import 'package:dewdrop/src/features/friends/domain/friend.dart';
import 'package:dewdrop/src/features/friends/domain/friend_repository.dart';
import 'package:dewdrop/src/features/profile/domain/profile.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseFriendRepository implements FriendRepository {
  SupabaseFriendRepository(this._client);

  final SupabaseClient _client;

  String get _uid => _client.auth.currentUser!.id;

  /// Sends a friend request to the user with [handle].
  ///
  /// A missing handle surfaces "Aucun utilisateur @x" — handle existence is
  /// **intentionally not hidden**: handles are meant to be publicly searchable
  /// so people can add each other, and the threat model is low. This is a
  /// deliberate decision, not an enumeration bug — don't "fix" it.
  @override
  Future<void> sendRequest(String handle) async {
    final h = handle.trim().toLowerCase();
    final target =
        await _client.from('profiles').select('id').eq('handle', h).maybeSingle();
    if (target == null) throw FriendException('Aucun utilisateur @$h.');

    final targetId = target['id'] as String;
    if (targetId == _uid) {
      throw FriendException("Tu ne peux pas t'ajouter toi-même.");
    }

    final existing = await _client
        .from('friendships')
        .select('status')
        .or('and(requester_id.eq.$_uid,addressee_id.eq.$targetId),'
            'and(requester_id.eq.$targetId,addressee_id.eq.$_uid)')
        .maybeSingle();
    if (existing != null) {
      throw FriendException(existing['status'] == 'accepted'
          ? 'Vous êtes déjà amis.'
          : 'Une demande est déjà en cours.');
    }

    await _client
        .from('friendships')
        .insert({'requester_id': _uid, 'addressee_id': targetId});
  }

  @override
  Future<List<IncomingRequest>> incomingRequests() async {
    final rows = await _client
        .from('friendships')
        .select('id, requester_id')
        .eq('addressee_id', _uid)
        .eq('status', 'pending');
    if (rows.isEmpty) return [];
    final profiles =
        await _profilesByIds([for (final r in rows) r['requester_id'] as String]);
    return [
      for (final r in rows)
        if (profiles[r['requester_id']] case final p?)
          IncomingRequest(friendshipId: r['id'] as String, requester: p),
    ];
  }

  @override
  Future<List<Friend>> friends() async {
    final rows = await _client
        .from('friendships')
        .select('id, requester_id, addressee_id')
        .eq('status', 'accepted')
        .or('requester_id.eq.$_uid,addressee_id.eq.$_uid');
    if (rows.isEmpty) return [];

    String other(Map<String, dynamic> r) =>
        (r['requester_id'] == _uid ? r['addressee_id'] : r['requester_id']) as String;

    final profiles = await _profilesByIds([for (final r in rows) other(r)]);
    return [
      for (final r in rows)
        if (profiles[other(r)] case final p?)
          Friend(friendshipId: r['id'] as String, profile: p),
    ];
  }

  @override
  Future<void> acceptRequest(String friendshipId) => _client
      .from('friendships')
      .update({'status': 'accepted'}).eq('id', friendshipId);

  /// Reject a request or remove a friend (deletes the friendship row).
  @override
  Future<void> removeFriendship(String friendshipId) =>
      _client.from('friendships').delete().eq('id', friendshipId);

  Future<Map<String, Profile>> _profilesByIds(List<String> ids) async {
    if (ids.isEmpty) return {};
    final rows = await _client.from('profiles').select().inFilter('id', ids);
    return {for (final m in rows) m['id'] as String: Profile.fromMap(m)};
  }
}
