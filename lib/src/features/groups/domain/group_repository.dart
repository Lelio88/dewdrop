import 'package:dewdrop/src/features/groups/domain/group.dart';
import 'package:dewdrop/src/features/profile/domain/profile.dart';

/// Groups boundary (Supabase `groups` / `group_members` / `group_blocks` + the
/// `send_to_group` RPC behind it).
///
/// Invariants enforced server-side (RLS + the RPC), mirrored by the UI:
///  - only the creator adds/removes members (and only their own friends),
///  - any member can [sendToGroup] (fan-out to the others),
///  - [leaveGroup] removes yourself; [blockGroup] also stops the group's pensées
///    and prevents re-add.
abstract interface class GroupRepository {
  /// Groups the signed-in user is a member of (or created).
  Future<List<Group>> myGroups();

  /// Creates a group with [name] and adds the creator as its first member.
  Future<Group> createGroup(String name);

  /// The members' public profiles (handle / name).
  Future<List<Profile>> members(String groupId);

  /// Creator-only: add one of your friends.
  Future<void> addMember(String groupId, String userId);

  /// Creator-only: remove a member.
  Future<void> removeMember(String groupId, String userId);

  /// Remove yourself from the group.
  Future<void> leaveGroup(String groupId);

  /// Leave the group AND stop its pensées (and prevent being re-added).
  Future<void> blockGroup(String groupId);

  /// Creator-only: delete the whole group.
  Future<void> deleteGroup(String groupId);

  /// Fan-out a pensée to every other member. Returns how many were sent.
  Future<int> sendToGroup(String groupId, {bool anonymous});

  /// Emits a tick when the user's groups or their membership change (live).
  Stream<int> watchChanges();
}
