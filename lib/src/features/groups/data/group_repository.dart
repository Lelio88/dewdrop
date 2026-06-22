import 'dart:async';

import 'package:dewdrop/src/common/app_exceptions.dart';
import 'package:dewdrop/src/features/groups/domain/group.dart';
import 'package:dewdrop/src/features/groups/domain/group_repository.dart';
import 'package:dewdrop/src/features/profile/domain/profile.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseGroupRepository implements GroupRepository {
  SupabaseGroupRepository(this._client);

  final SupabaseClient _client;

  String get _uid => _client.auth.currentUser!.id;

  @override
  Future<List<Group>> myGroups() async {
    final rows = await _client
        .from('groups')
        .select('id, name, creator_id')
        .order('created_at');
    return [for (final m in rows) Group.fromMap(m)];
  }

  @override
  Future<Group> createGroup(String name) async {
    final row = await _client
        .from('groups')
        .insert({'name': name.trim(), 'creator_id': _uid})
        .select('id, name, creator_id')
        .single();
    // Add the creator as the first member (so they appear + can send).
    await _client.from('group_members').insert({
      'group_id': row['id'],
      'user_id': _uid,
    });
    return Group.fromMap(row);
  }

  @override
  Future<List<Profile>> members(String groupId) async {
    final rows = await _client
        .from('group_members')
        .select('user_id')
        .eq('group_id', groupId);
    final ids = [for (final r in rows) r['user_id'] as String];
    if (ids.isEmpty) return [];
    // Names via the public directory view (profiles is owner-only).
    final profiles = await _client
        .from('public_profiles')
        .select()
        .inFilter('id', ids);
    return [for (final m in profiles) Profile.fromMap(m)];
  }

  @override
  Future<void> addMember(String groupId, String userId) => _client
      .from('group_members')
      .insert({'group_id': groupId, 'user_id': userId});

  @override
  Future<void> removeMember(String groupId, String userId) => _client
      .from('group_members')
      .delete()
      .eq('group_id', groupId)
      .eq('user_id', userId);

  @override
  Future<void> leaveGroup(String groupId) => _client
      .from('group_members')
      .delete()
      .eq('group_id', groupId)
      .eq('user_id', _uid);

  @override
  Future<void> blockGroup(String groupId) async {
    await _client
        .from('group_members')
        .delete()
        .eq('group_id', groupId)
        .eq('user_id', _uid);
    await _client.from('group_blocks').insert({
      'user_id': _uid,
      'group_id': groupId,
    });
  }

  @override
  Future<void> deleteGroup(String groupId) =>
      _client.from('groups').delete().eq('id', groupId);

  @override
  Future<int> sendToGroup(String groupId, {bool anonymous = false}) async {
    try {
      final res = await _client.rpc(
        'send_to_group',
        params: {'p_group': groupId, 'p_anonymous': anonymous},
      );
      return (res as int?) ?? 0;
    } on PostgrestException catch (e) {
      // The group-send cap (150/min) raises the same `rate_limited`.
      if (e.message.contains('rate_limited')) {
        throw const RateLimitedException();
      }
      rethrow;
    }
  }

  @override
  Stream<int> watchChanges() {
    // RLS restricts events to the subscriber's groups/membership. Fires on add,
    // remove, create and delete. Emits a monotonic tick so each event re-notifies.
    final controller = StreamController<int>();
    var tick = 0;
    final channel = _client
        .channel('groups:$_uid')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'groups',
          callback: (_) => controller.add(++tick),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'group_members',
          callback: (_) => controller.add(++tick),
        );
    channel.subscribe();
    controller.onCancel = () => _client.removeChannel(channel);
    return controller.stream;
  }
}
