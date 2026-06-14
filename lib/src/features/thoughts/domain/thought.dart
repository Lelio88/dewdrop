import 'package:dewdrop/src/features/profile/domain/profile.dart';

/// A thought received by the current user. [sender] is null when anonymous.
class ReceivedThought {
  const ReceivedThought({
    required this.id,
    required this.createdAt,
    required this.isAnonymous,
    this.sender,
  });

  final String id;
  final DateTime createdAt;
  final bool isAnonymous;
  final Profile? sender;
}
