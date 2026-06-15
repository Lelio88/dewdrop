import 'package:dewdrop/src/features/profile/domain/profile.dart';

/// A user-facing friend error (handle not found, already friends, self-add…).
/// Lives in the domain so both the repository (which throws it) and the UI
/// (which catches it) depend on it without crossing the data boundary.
class FriendException implements Exception {
  FriendException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// An accepted friend (the other person + the friendship row id).
class Friend {
  const Friend({required this.friendshipId, required this.profile});
  final String friendshipId;
  final Profile profile;
}

/// A pending friend request someone sent to me.
class IncomingRequest {
  const IncomingRequest({required this.friendshipId, required this.requester});
  final String friendshipId;
  final Profile requester;
}
