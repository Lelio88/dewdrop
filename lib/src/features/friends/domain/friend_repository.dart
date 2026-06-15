import 'package:dewdrop/src/features/friends/domain/friend.dart';

/// The friendships boundary (Supabase `friendships` + `profiles` behind it).
/// [sendRequest] throws a [FriendException] for user-facing failures.
abstract interface class FriendRepository {
  Future<void> sendRequest(String handle);
  Future<List<IncomingRequest>> incomingRequests();
  Future<List<Friend>> friends();
  Future<void> acceptRequest(String friendshipId);

  /// Reject a request or remove a friend (deletes the friendship row).
  Future<void> removeFriendship(String friendshipId);
}
