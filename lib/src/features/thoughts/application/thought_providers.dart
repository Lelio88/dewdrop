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
