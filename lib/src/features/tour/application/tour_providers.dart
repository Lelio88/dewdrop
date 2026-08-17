import 'dart:async';

import 'package:dewdrop/src/features/ambient/application/ambient_providers.dart';
import 'package:dewdrop/src/features/tour/domain/tour_step.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Which tours have already been seen on this device.
///
/// Device-local (SharedPreferences), not a `profiles` column: "I've seen it" is
/// knowledge about *this* install, and a fresh phone is exactly where showing it
/// again helps. It also keeps the tours out of the profile round-trip on first
/// launch, so the home one can paint before the network answers.
///
/// One key per tour, so seeing the home tour doesn't silence the friends one —
/// each screen explains itself the first time it is opened.
class ToursSeenNotifier extends Notifier<Set<TourId>> {
  static String _key(TourId id) => 'tour_seen_${id.name}';

  @override
  Set<TourId> build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    return {
      for (final id in TourId.values)
        if (prefs.getBool(_key(id)) ?? false) id,
    };
  }

  /// Finished or skipped — don't show [id] again on this device.
  void complete(TourId id) => _set(id, seen: true);

  /// Re-arm every tour (Réglages → « Revoir le tuto »): the home one plays at
  /// once, and each screen explains itself again on its next visit.
  void replayAll() {
    for (final id in TourId.values) {
      _set(id, seen: false);
    }
  }

  void _set(TourId id, {required bool seen}) {
    state = seen ? {...state, id} : (state.toSet()..remove(id));
    // Fire-and-forget: the in-memory state above is what the UI reads, and a
    // failed write only costs the user seeing the tour once more.
    unawaited(ref.read(sharedPreferencesProvider).setBool(_key(id), seen));
  }
}

final toursSeenProvider = NotifierProvider<ToursSeenNotifier, Set<TourId>>(
  ToursSeenNotifier.new,
);

/// Whether [id] should be playing right now. Watch this, not the raw set.
final showTourProvider = Provider.family<bool, TourId>(
  (ref, id) => !ref.watch(toursSeenProvider).contains(id),
);
