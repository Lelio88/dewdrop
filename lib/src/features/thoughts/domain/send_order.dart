/// Ordering rule for the "envoyer une pensée" surfaces: the people you sent a
/// pensée to most recently come first.
///
/// Pure + type-agnostic on purpose — it keys on ids and a display label, so it
/// works for friends, groups or anything else without this file importing a
/// sibling feature's domain types.
///
/// Non-obvious choices:
/// - Never-contacted entries land **after** every contacted one, sorted by label
///   (case-insensitive), so a brand-new friend list still reads alphabetically
///   instead of in Postgres' arbitrary row order.
/// - Ties are broken by label then id: `List.sort` is **not** stable in Dart, so
///   without a total order the dock could reshuffle between two identical builds.
///
/// Example:
/// ```dart
/// final ordered = sortByRecency(
///   friends,
///   idOf: (f) => f.profile.id,
///   labelOf: (f) => f.profile.handle,
///   recentIdsNewestFirst: ref.watch(recentContactsProvider).value ?? const [],
/// );
/// ```
List<T> sortByRecency<T>(
  Iterable<T> items, {
  required String Function(T) idOf,
  required String Function(T) labelOf,
  required List<String> recentIdsNewestFirst,
}) {
  final rank = <String, int>{};
  for (var i = 0; i < recentIdsNewestFirst.length; i++) {
    // First occurrence wins — the list is newest-first and may hold duplicates.
    rank.putIfAbsent(recentIdsNewestFirst[i], () => i);
  }
  final never = recentIdsNewestFirst.length; // sorts after every contacted one

  final sorted = [...items];
  sorted.sort((a, b) {
    final byRank = (rank[idOf(a)] ?? never).compareTo(rank[idOf(b)] ?? never);
    if (byRank != 0) return byRank;
    final byLabel = labelOf(
      a,
    ).toLowerCase().compareTo(labelOf(b).toLowerCase());
    return byLabel != 0 ? byLabel : idOf(a).compareTo(idOf(b));
  });
  return sorted;
}

/// Collapses a newest-first column of ids — as read from the `thoughts` rows —
/// into the distinct ids in the order they were last written to. Nulls are
/// dropped: a personal pensée carries no `group_id`.
///
/// Non-obvious: one group send writes one row **per member**, all bearing the
/// same `group_id`, so a raw column is mostly repetition. Deduping is what
/// turns it back into "the circles you wrote to, latest first".
///
/// Lives here rather than in the repository because it is the other half of
/// [sortByRecency]'s rule, and because a loop buried in `data/` cannot be
/// reached from a unit test.
List<String> dedupeNewestFirst(Iterable<String?> ids) {
  final seen = <String>{};
  final out = <String>[];
  for (final id in ids) {
    if (id != null && seen.add(id)) out.add(id);
  }
  return out;
}
