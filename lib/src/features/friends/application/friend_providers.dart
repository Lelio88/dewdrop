import 'package:dewdrop/src/features/friends/data/friend_repository.dart';
import 'package:dewdrop/src/features/friends/domain/friend.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final friendRepositoryProvider = Provider<FriendRepository>((ref) {
  return FriendRepository(Supabase.instance.client);
});

final friendsProvider = FutureProvider<List<Friend>>((ref) {
  return ref.watch(friendRepositoryProvider).friends();
});

final incomingRequestsProvider = FutureProvider<List<IncomingRequest>>((ref) {
  return ref.watch(friendRepositoryProvider).incomingRequests();
});
