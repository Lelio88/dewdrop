import 'package:dewdrop/src/features/thoughts/domain/thought.dart';

/// The "pensées" boundary (Supabase `thoughts` behind it).
abstract interface class ThoughtRepository {
  /// Sends a "pensée" to [recipientId] (must be an accepted friend — enforced
  /// by RLS). When [anonymous], the recipient won't see who it's from.
  Future<void> sendThought(String recipientId, {bool anonymous = false});

  Future<List<ReceivedThought>> receivedThoughts();

  /// The recipient ids this user has most recently sent a pensée to (newest
  /// first, deduped). Orders the home-screen widget's "auto" friend slots.
  Future<List<String>> recentlyContactedRecipientIds({int limit = 24});

  /// Emits an incrementing tick for every pensée received **live** (a new row
  /// addressed to the current user). Drives the decor's reception burst and a
  /// refresh of the received-thoughts list while the app is open. The value is
  /// a monotonic counter (not the content) on purpose: distinct values are what
  /// make Riverpod re-notify reliably — a `void`/identical payload gets
  /// collapsed by `==` and dropped. Cancel the subscription to tear down the
  /// channel.
  Stream<int> watchIncoming();
}
