import 'dart:async';

import 'package:dewdrop/src/features/ambient/application/ambient_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether the home tour should be showing right now.
///
/// Device-local (SharedPreferences), not a `profiles` column: "I've seen the
/// tour" is knowledge about *this* install, and a fresh phone is exactly where
/// re-showing it is useful. It also keeps the tour out of the profile round-trip
/// on first launch, so it can paint before the network answers.
///
/// [complete] is called when the user finishes or skips; [replay] re-arms it
/// from Réglages. Since `HomeView` watches this provider and stays mounted
/// under any pushed screen, replaying from Réglages means the tour is already
/// waiting when that screen is popped.
class HomeTourNotifier extends Notifier<bool> {
  static const _key = 'home_tour_seen';

  @override
  bool build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    return !(prefs.getBool(_key) ?? false);
  }

  /// Finished or skipped — don't show it again on this device.
  void complete() => _set(seen: true);

  /// Re-arm the tour (from Réglages → « Revoir le tuto »).
  void replay() => _set(seen: false);

  void _set({required bool seen}) {
    state = !seen;
    // Fire-and-forget: the in-memory state above is what the UI reads, and a
    // failed write only costs the user seeing the tour once more.
    unawaited(ref.read(sharedPreferencesProvider).setBool(_key, seen));
  }
}

final homeTourProvider = NotifierProvider<HomeTourNotifier, bool>(
  HomeTourNotifier.new,
);
