import 'package:dewdrop/src/features/thoughts/domain/thought.dart';

/// The "pensées" boundary (Supabase `thoughts` behind it).
abstract interface class ThoughtRepository {
  /// Sends a "pensée" to [recipientId] (must be an accepted friend — enforced
  /// by RLS). When [anonymous], the recipient won't see who it's from.
  Future<void> sendThought(String recipientId, {bool anonymous = false});

  Future<List<ReceivedThought>> receivedThoughts();

  /// Emits once for every pensée received **live** (a new row addressed to the
  /// current user). Used to trigger the decor's reception burst while the app
  /// is open. The payload is intentionally empty — the burst needs a signal,
  /// not the content. Cancel the subscription to tear down the channel.
  Stream<void> watchIncoming();
}
