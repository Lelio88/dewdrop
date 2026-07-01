import 'package:dewdrop/decor/environment.dart';

/// Seasonal "marronnier" universes: on a few fixed calendar days, a special
/// decor takes over the home and the user cannot change it (favourite swipe +
/// world picker are locked). Their own universe returns on its own once the
/// window closes — the override is display-only and is never persisted to the
/// profile.
///
/// This file is the pure, framework-free source of truth: the event list + the
/// [activeSeasonalEvent] resolver, both driven by an explicit `now` so they can
/// be unit-tested at the window boundaries. The Riverpod provider that feeds
/// `DateTime.now()` in and the home wiring live elsewhere.
///
/// Non-obvious choices:
/// - The forced [decor] points at a dedicated seasonal [Environment]
///   (christmas / halloween / april) that is hidden from the normal univers
///   picker (`Environment.seasonal`) — it only ever appears through this lock.
/// - Windows are (month, day) ranges compared on a `month*100 + day` key, so
///   they are year-agnostic and recur every year with no date arithmetic. The
///   range may wrap across the new year (start > end) for robustness, even
///   though none of the current events need it.
class SeasonalEvent {
  const SeasonalEvent({
    required this.id,
    required this.label,
    required this.emoji,
    required this.startMonth,
    required this.startDay,
    required this.endMonth,
    required this.endDay,
    required this.decor,
    required this.mode,
  });

  /// Convenience for a single-day event (start == end).
  const SeasonalEvent.day({
    required String id,
    required String label,
    required String emoji,
    required int month,
    required int day,
    required String decor,
    required RenderMode mode,
  }) : this(
         id: id,
         label: label,
         emoji: emoji,
         startMonth: month,
         startDay: day,
         endMonth: month,
         endDay: day,
         decor: decor,
         mode: mode,
       );

  /// Stable identifier (also the analytics / debug key).
  final String id;

  /// Human label, e.g. "Halloween".
  final String label;

  /// A single emoji shown on the lock banner.
  final String emoji;

  final int startMonth;
  final int startDay;
  final int endMonth;
  final int endDay;

  /// The forced decor string `"<environment>:<variant>"` (same shape as
  /// `profiles.decor`), parsed with [parseDecor].
  final String decor;

  /// The forced render mode for the window.
  final RenderMode mode;

  /// Whether [now]'s calendar day falls inside this event's window (inclusive),
  /// ignoring the year.
  bool isActiveOn(DateTime now) {
    final md = now.month * 100 + now.day;
    final start = startMonth * 100 + startDay;
    final end = endMonth * 100 + endDay;
    if (start <= end) return md >= start && md <= end;
    // Wraps across the new year (e.g. Dec 28 → Jan 2).
    return md >= start || md <= end;
  }
}

/// The calendar of marronniers. Dates are "le jour pile": Halloween 31/10, 1er
/// avril 01/04, Noël 24–25/12. Decors are visual stubs on existing worlds until
/// the bespoke seasonal worlds are drawn.
const List<SeasonalEvent> kSeasonalEvents = [
  SeasonalEvent.day(
    id: 'halloween',
    label: 'Halloween',
    emoji: '🎃',
    month: 10,
    day: 31,
    decor: 'halloween:0', // misty pumpkin forest
    mode: RenderMode.photo,
  ),
  SeasonalEvent.day(
    id: 'aprilfool',
    label: '1er avril',
    emoji: '🚧',
    month: 4,
    day: 1,
    decor: 'april:0', // "world under construction" roadworks
    mode: RenderMode.photo,
  ),
  SeasonalEvent(
    id: 'christmas',
    label: 'Noël',
    emoji: '🎄',
    startMonth: 12,
    startDay: 24,
    endMonth: 12,
    endDay: 25,
    decor: 'christmas:0', // cozy living-room interior
    mode: RenderMode.photo,
  ),
];

/// The marronnier active on [now], or null on any ordinary day. The first
/// matching event wins (windows do not overlap in [kSeasonalEvents]).
SeasonalEvent? activeSeasonalEvent(
  DateTime now, {
  List<SeasonalEvent> events = kSeasonalEvents,
}) {
  for (final e in events) {
    if (e.isActiveOn(now)) return e;
  }
  return null;
}
