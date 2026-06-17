import 'package:dewdrop/src/features/auth/application/auth_providers.dart';
import 'package:dewdrop/src/features/groups/data/group_repository.dart';
import 'package:dewdrop/src/features/groups/domain/group.dart';
import 'package:dewdrop/src/features/groups/domain/group_repository.dart';
import 'package:dewdrop/src/features/profile/domain/profile.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final groupRepositoryProvider = Provider<GroupRepository>((ref) {
  return SupabaseGroupRepository(Supabase.instance.client);
});

bool _signedIn(Ref ref) {
  ref.watch(authStateChangesProvider);
  return ref.watch(authRepositoryProvider).currentSession != null;
}

/// Live tick when the user's groups or their membership change.
final groupChangesProvider = StreamProvider<int>((ref) {
  if (!_signedIn(ref)) return const Stream<int>.empty();
  return ref.watch(groupRepositoryProvider).watchChanges();
});

/// The groups the signed-in user belongs to (self-refreshes on realtime change).
final myGroupsProvider = FutureProvider<List<Group>>((ref) {
  if (!_signedIn(ref)) return <Group>[];
  ref.watch(groupChangesProvider);
  return ref.watch(groupRepositoryProvider).myGroups();
});

/// Members (public profiles) of a given group.
final groupMembersProvider = FutureProvider.family<List<Profile>, String>((
  ref,
  groupId,
) {
  if (!_signedIn(ref)) return <Profile>[];
  ref.watch(groupChangesProvider);
  return ref.watch(groupRepositoryProvider).members(groupId);
});
