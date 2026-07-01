import 'package:dewdrop/src/common/seasonal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The marronnier universe active *right now*, or null on an ordinary day.
///
/// A plain [Provider] that samples `DateTime.now()` once and caches the result.
/// Wall-clock day boundaries are rare, so the home invalidates this provider on
/// app resume ([ref.invalidate]) to re-sample after the app was backgrounded
/// across midnight (e.g. into or out of the 24–25/12 window).
///
/// Overridable in tests / for on-device date simulation by replacing the whole
/// provider, or by feeding a fixed `now` to [activeSeasonalEvent] directly.
final seasonalOverrideProvider = Provider<SeasonalEvent?>(
  (ref) => activeSeasonalEvent(DateTime.now()),
);
