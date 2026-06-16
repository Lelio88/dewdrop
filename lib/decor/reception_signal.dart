import 'package:flutter/foundation.dart';

/// A decoupled "a pensée just arrived" pulse that the host (the home screen)
/// feeds to the **active decor** so it can play an amplified celebratory burst
/// — a shooting-star shower, a curtain of falling leaves, a swell of bubbles…
///
/// It lives in the decor engine (no Riverpod, no Supabase) so every decor stays
/// framework-agnostic: a decor just `addListener`s to it and, on each [pulse],
/// spawns its big burst. The host owns the instance, decides *when* a reception
/// happened (live via Supabase Realtime, or on app open for thoughts received
/// while it was closed), and calls [pulse].
///
/// Invariant: the host owns the lifecycle (create once, [dispose] it). Decors
/// must `removeListener` on their own dispose — never dispose the signal.
class ReceptionSignal extends ChangeNotifier {
  /// Trigger the active decor's reception burst. One call = one burst,
  /// regardless of how many thoughts arrived (the burst is "many" by design).
  void pulse() => notifyListeners();
}
