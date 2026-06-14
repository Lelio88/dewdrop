import 'package:dewdrop/src/features/profile/domain/profile.dart';

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
