import 'package:dewdrop/src/features/profile/application/profile_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The user's starred decor snapshots (`"<env>:<variant>:<mode>"`, see
/// [encodeFavorite]), in display order.
///
/// Single reactive source of truth for both the univers picker (star toggle +
/// "is this variant starred?" check) and the home screen (the swipe cycles
/// through this list). Seeded from `myProfileProvider` and persisted back to
/// `profiles.decor_favorites`.
///
/// **Optimistic by design**: [DecorFavoritesNotifier.toggle] updates `state`
/// immediately (so the star flips with zero latency), then writes through to
/// Supabase in the background. It does NOT invalidate `myProfileProvider` after
/// the write — re-running `build()` would otherwise momentarily reset the list
/// to the pre-write server value mid-flight. The server reconciles naturally on
/// the next profile (re)load (sign-in, app resume).
class DecorFavoritesNotifier extends Notifier<List<String>> {
  @override
  List<String> build() {
    // Re-seeds whenever the profile (re)loads. AsyncValue.value (not
    // valueOrNull) per the project's Riverpod-without-codegen convention.
    return ref.watch(myProfileProvider).value?.decorFavorites ?? const [];
  }

  /// Adds [favorite] if absent, removes it if present. Order is preserved;
  /// a newly starred snapshot is appended to the end.
  Future<void> toggle(String favorite) async {
    final next = [...state];
    if (!next.remove(favorite)) next.add(favorite);
    state = next; // optimistic — the UI reflects the change at once
    try {
      await ref.read(profileRepositoryProvider).updateDecorFavorites(next);
    } on Exception catch (_) {
      // Background persistence; ignore transient failures (the in-memory state
      // stays correct, and the next profile load reconciles with the server).
    }
  }
}

final decorFavoritesProvider =
    NotifierProvider<DecorFavoritesNotifier, List<String>>(
      DecorFavoritesNotifier.new,
    );
