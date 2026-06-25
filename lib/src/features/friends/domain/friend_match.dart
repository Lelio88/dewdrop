import 'package:dewdrop/src/features/friends/domain/friend.dart';

/// Resolves a free-form name or handle (as spoken to a voice assistant, typed
/// in a routine, or carried by a `dewdrop://send?to=…` deep link) to one of the
/// user's accepted friends.
///
/// This is the headless, UI-free brain shared by every "send a thought by name"
/// entry point — the deep-link confirm today, and the future on-device
/// AppFunction (Gemini) tomorrow. Keeping it a pure function over a plain
/// `List<Friend>` makes it trivially testable and reusable from any layer.
///
/// Non-obvious choices:
///  - **Accent/case-insensitive** matching (`_normalize`) so "lelio", "Lélio"
///    and "LÉLIO" all resolve — French names carry diacritics a voice layer
///    drops. The de-accent table is hand-rolled (no extra dependency, repo is
///    public) and covers the Latin-1/French set; widen it if a name needs it.
///  - **Tiered** matching (exact handle → exact display name → prefix →
///    substring): a deep link always passes an exact handle (handles are
///    unique) so it lands on tier 1 unambiguously, while a spoken first name
///    still resolves via the looser tiers.
///  - Returns a sealed [FriendMatch] rather than `Friend?` so callers can tell
///    "no such friend" from "several match" — the AppFunction needs that to ask
///    the user to disambiguate by voice instead of guessing.
///
/// ```dart
/// switch (matchFriend(friends, 'lélio')) {
///   case FriendMatched(:final friend): send(friend);
///   case FriendAmbiguous(:final candidates): askWhichOne(candidates);
///   case FriendNotFound(): say("Je ne connais pas cet ami.");
/// }
/// ```
sealed class FriendMatch {
  const FriendMatch();
}

/// Exactly one friend matched [query].
final class FriendMatched extends FriendMatch {
  const FriendMatched(this.friend);
  final Friend friend;
}

/// No friend matched [query].
final class FriendNotFound extends FriendMatch {
  const FriendNotFound();
}

/// Several friends matched [query] at the same (non-exact) tier — the caller
/// must disambiguate. [candidates] is non-empty and unmodifiable.
final class FriendAmbiguous extends FriendMatch {
  const FriendAmbiguous(this.candidates);
  final List<Friend> candidates;
}

/// Best-effort resolution of [query] against [friends]. See [FriendMatch].
FriendMatch matchFriend(List<Friend> friends, String query) {
  final q = _normalize(query);
  if (q.isEmpty) return const FriendNotFound();

  final exactHandle = <Friend>[];
  final exactName = <Friend>[];
  final prefix = <Friend>[];
  final substring = <Friend>[];

  for (final f in friends) {
    final handle = _normalize(f.profile.handle ?? '');
    final name = _normalize(f.profile.displayName ?? '');
    if (handle.isNotEmpty && handle == q) {
      exactHandle.add(f);
    } else if (name.isNotEmpty && name == q) {
      exactName.add(f);
    } else if (handle.startsWith(q) ||
        (name.isNotEmpty && name.startsWith(q))) {
      prefix.add(f);
    } else if (handle.contains(q) || (name.isNotEmpty && name.contains(q))) {
      substring.add(f);
    }
  }

  // Return at the first non-empty tier: a single hit wins, ties are ambiguous.
  for (final tier in [exactHandle, exactName, prefix, substring]) {
    if (tier.length == 1) return FriendMatched(tier.first);
    if (tier.length > 1) return FriendAmbiguous(List.unmodifiable(tier));
  }
  return const FriendNotFound();
}

/// Lowercased, trimmed, de-accented, `@`-stripped, whitespace-collapsed form
/// used for comparison on both sides.
String _normalize(String s) {
  final lower = s.trim().toLowerCase();
  final sb = StringBuffer();
  for (var i = 0; i < lower.length; i++) {
    final ch = lower[i];
    sb.write(_deaccent[ch] ?? ch);
  }
  return sb
      .toString()
      .replaceAll('@', '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

/// French/Latin-1 accent folding. Hand-rolled to avoid a dependency.
const Map<String, String> _deaccent = {
  'á': 'a',
  'à': 'a',
  'â': 'a',
  'ä': 'a',
  'ã': 'a',
  'å': 'a',
  'é': 'e',
  'è': 'e',
  'ê': 'e',
  'ë': 'e',
  'í': 'i',
  'ì': 'i',
  'î': 'i',
  'ï': 'i',
  'ó': 'o',
  'ò': 'o',
  'ô': 'o',
  'ö': 'o',
  'õ': 'o',
  'ú': 'u',
  'ù': 'u',
  'û': 'u',
  'ü': 'u',
  'ç': 'c',
  'ñ': 'n',
  'ÿ': 'y',
  'œ': 'oe',
  'æ': 'ae',
};
