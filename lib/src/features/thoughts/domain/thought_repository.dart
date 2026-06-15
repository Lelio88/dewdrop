import 'package:dewdrop/src/features/thoughts/domain/thought.dart';

/// The "pensées" boundary (Supabase `thoughts` behind it).
abstract interface class ThoughtRepository {
  /// Sends a "pensée" to [recipientId] (must be an accepted friend — enforced
  /// by RLS). When [anonymous], the recipient won't see who it's from.
  Future<void> sendThought(String recipientId, {bool anonymous = false});

  Future<List<ReceivedThought>> receivedThoughts();
}
