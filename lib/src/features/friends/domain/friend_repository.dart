import 'package:dewdrop/src/features/friends/domain/friend.dart';
import 'package:dewdrop/src/features/profile/domain/profile.dart';

/// The friendships boundary (Supabase `friendships` + `profiles` behind it).
/// [sendRequest] and [sendRequestTo] throw a [FriendException] for user-facing
/// failures (unknown handle, already friends, self-add…).
abstract interface class FriendRepository {
  Future<void> sendRequest(String handle);

  /// Same as [sendRequest] for a target whose profile id is already known — a
  /// fellow group member, a "tu voulais dire…" suggestion. Skips the handle
  /// lookup; every other guard (self-add, existing friendship or pending
  /// request) is identical.
  Future<void> sendRequestTo(String userId);

  /// Handles that *look like* [query], best match first — the "tu voulais
  /// dire… ?" fallback after an exact lookup missed.
  ///
  /// Deliberately NOT a browsable directory: the server side (`search_profiles`)
  /// caps this at a handful of close matches, requires at least 3 characters,
  /// and matches on the **handle only** — never the display name. Returns an
  /// empty list rather than throwing, so a failing suggestion never blocks the
  /// exact-handle path that the user actually asked for.
  Future<List<Profile>> suggestHandles(String query);

  Future<List<IncomingRequest>> incomingRequests();
  Future<List<Friend>> friends();
  Future<void> acceptRequest(String friendshipId);

  /// Reject a request or remove a friend (deletes the friendship row).
  Future<void> removeFriendship(String friendshipId);

  /// Block a user ([userId] is their profile id): removes any friendship both
  /// ways and prevents them from sending you thoughts or friend requests.
  Future<void> block(String userId);

  /// Lift a block.
  Future<void> unblock(String userId);

  /// Record a report against a user for later moderation.
  Future<void> report(String userId, {String? reason});

  /// Emits an incrementing tick whenever a friendship the current user is part
  /// of changes (a request arrives, is accepted, or is removed), so the friends
  /// and requests lists can refresh **live** without a relaunch. Monotonic
  /// counter so distinct values re-notify Riverpod reliably.
  Stream<int> watchChanges();
}
