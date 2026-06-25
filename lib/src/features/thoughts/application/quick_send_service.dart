import 'package:dewdrop/src/features/friends/application/friend_providers.dart';
import 'package:dewdrop/src/features/friends/domain/friend.dart';
import 'package:dewdrop/src/features/friends/domain/friend_match.dart';
import 'package:dewdrop/src/features/profile/application/profile_providers.dart';
import 'package:dewdrop/src/features/thoughts/application/thought_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Reads the friend list straight from the repository (not `friendsProvider`):
// this capability runs headless, off any widget, where the UI provider may be
// unlistened — and an unlistened FutureProvider in error state leaves its
// `.future` pending. A direct repo call rejects cleanly instead, and gives the
// freshest list for a one-off voice/deep-link send. The caller guarantees a
// session (the repo needs `currentUser`).

/// Headless "send a pensée to a named friend" capability — resolve a free-form
/// name/handle, then send, with **no `BuildContext` and no widget**.
///
/// This is the AppFunctions-ready contract: the deep-link confirm calls it
/// today (`dewdrop://send?to=…`), and the future on-device Gemini AppFunction
/// (native Kotlin → headless Dart, the same isolate plumbing the home-screen
/// widget already uses) will call this exact method. Building it now pins the
/// capability so the eventual native shim is a thin adapter, not new logic.
///
/// Invariants:
///  - Never sends silently to the wrong person: resolution is delegated to
///    [matchFriend], and an ambiguous/absent name returns a typed result rather
///    than picking a friend at random.
///  - The recipient must be an accepted friend — the resolver only sees the
///    user's own friend list, and the server (RLS) rejects a send to anyone
///    else, so a forged deep link cannot reach a stranger.
///  - Anonymity defaults to the profile's global "Pensées" default unless the
///    caller overrides it.
///
/// ```dart
/// final result = await ref.read(quickSendServiceProvider).sendToName('lélio');
/// // → QuickSendSent / QuickSendNoMatch / QuickSendAmbiguous / QuickSendFailed
/// ```
sealed class QuickSendResult {
  const QuickSendResult();
}

/// The pensée was sent to [friend].
final class QuickSendSent extends QuickSendResult {
  const QuickSendSent(this.friend);
  final Friend friend;
}

/// No friend matched [query] (an empty or unknown name).
final class QuickSendNoMatch extends QuickSendResult {
  const QuickSendNoMatch(this.query);
  final String query;
}

/// Several friends matched — the caller must ask which one. [candidates] is
/// non-empty.
final class QuickSendAmbiguous extends QuickSendResult {
  const QuickSendAmbiguous(this.candidates);
  final List<Friend> candidates;
}

/// The friend resolved but loading the list or the send itself failed
/// (network, rate limit, signed out). [error] is the underlying exception.
final class QuickSendFailed extends QuickSendResult {
  const QuickSendFailed(this.error);
  final Object error;
}

class QuickSendService {
  const QuickSendService(this._ref);

  final Ref _ref;

  /// Resolves [name] against the signed-in user's friends. Throws if the list
  /// can't be loaded (offline, signed out); the caller decides how to surface
  /// it. Used by the deep-link confirm (which needs the friend before sending)
  /// and by [sendToName].
  Future<FriendMatch> resolve(String name) async {
    final friends = await _ref.read(friendRepositoryProvider).friends();
    return matchFriend(friends, name);
  }

  /// Resolves [name] against the signed-in user's friends and sends a pensée.
  /// [anonymous] overrides the profile default when provided.
  Future<QuickSendResult> sendToName(String name, {bool? anonymous}) async {
    final FriendMatch match;
    try {
      match = await resolve(name);
    } on Exception catch (e) {
      return QuickSendFailed(e);
    }

    return switch (match) {
      FriendMatched(:final friend) => _send(friend, anonymous: anonymous),
      FriendAmbiguous(:final candidates) => QuickSendAmbiguous(candidates),
      FriendNotFound() => QuickSendNoMatch(name),
    };
  }

  /// Sends directly to an already-resolved [friend] (used by the confirm step,
  /// which has the friend in hand).
  Future<QuickSendResult> send(Friend friend, {bool? anonymous}) =>
      _send(friend, anonymous: anonymous);

  Future<QuickSendResult> _send(Friend friend, {bool? anonymous}) async {
    final anon =
        anonymous ??
        _ref.read(myProfileProvider).value?.defaultAnonymous ??
        false;
    try {
      await _ref
          .read(thoughtRepositoryProvider)
          .sendThought(friend.profile.id, anonymous: anon);
      return QuickSendSent(friend);
    } on Exception catch (e) {
      return QuickSendFailed(e);
    }
  }
}

final quickSendServiceProvider = Provider<QuickSendService>(
  QuickSendService.new,
);
