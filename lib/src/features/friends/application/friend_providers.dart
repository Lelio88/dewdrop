import 'package:dewdrop/src/features/auth/application/auth_providers.dart';
import 'package:dewdrop/src/features/friends/data/friend_repository.dart';
import 'package:dewdrop/src/features/friends/domain/friend.dart';
import 'package:dewdrop/src/features/friends/domain/friend_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final friendRepositoryProvider = Provider<FriendRepository>((ref) {
  return SupabaseFriendRepository(Supabase.instance.client);
});

/// True only while a session exists — gates the list providers so they never
/// call the repo (and its `currentUser!`) signed out, and so they refetch on
/// sign in/out.
bool _signedIn(Ref ref) {
  ref.watch(authStateChangesProvider);
  return ref.watch(authRepositoryProvider).currentSession != null;
}

final friendsProvider = FutureProvider<List<Friend>>((ref) {
  if (!_signedIn(ref)) return <Friend>[];
  return ref.watch(friendRepositoryProvider).friends();
});

final incomingRequestsProvider = FutureProvider<List<IncomingRequest>>((ref) {
  if (!_signedIn(ref)) return <IncomingRequest>[];
  return ref.watch(friendRepositoryProvider).incomingRequests();
});

/// Ticks whenever a friendship involving the current user changes, so the
/// composition root can refresh the friends/requests lists live. Empty when
/// signed out.
final friendshipChangesProvider = StreamProvider<int>((ref) {
  if (!_signedIn(ref)) return const Stream<int>.empty();
  return ref.watch(friendRepositoryProvider).watchChanges();
});
