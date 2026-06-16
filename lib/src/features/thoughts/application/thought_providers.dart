import 'package:dewdrop/src/features/auth/application/auth_providers.dart';
import 'package:dewdrop/src/features/thoughts/data/thought_repository.dart';
import 'package:dewdrop/src/features/thoughts/domain/thought.dart';
import 'package:dewdrop/src/features/thoughts/domain/thought_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final thoughtRepositoryProvider = Provider<ThoughtRepository>((ref) {
  return SupabaseThoughtRepository(Supabase.instance.client);
});

final receivedThoughtsProvider = FutureProvider<List<ReceivedThought>>((ref) {
  ref.watch(authStateChangesProvider); // refetch on sign in/out
  // Avoid hitting the repo (and its currentUser!) when signed out.
  if (ref.watch(authRepositoryProvider).currentSession == null) {
    return <ReceivedThought>[];
  }
  return ref.watch(thoughtRepositoryProvider).receivedThoughts();
});

/// Fires each time a pensée is received **live** (while the app is open), so the
/// active decor can play its reception burst. Empty stream when signed out.
final incomingThoughtPulseProvider = StreamProvider<void>((ref) {
  ref.watch(authStateChangesProvider);
  if (ref.watch(authRepositoryProvider).currentSession == null) {
    return const Stream<void>.empty();
  }
  return ref.watch(thoughtRepositoryProvider).watchIncoming();
});
