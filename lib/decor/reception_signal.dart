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
  double _intensity = 1.0;

  /// Strength of the most recent [pulse]: 1.0 for a single pensée, scaling up
  /// when several are caught up at once (e.g. on app open after an absence). A
  /// decor reads this synchronously inside its listener to size its burst — more
  /// particles, a longer-lived swell. Only meaningful during the notification
  /// triggered by [pulse].
  double get intensity => _intensity;

  /// Trigger the active decor's reception burst. [intensity] (>= 1.0) makes the
  /// burst bigger + longer when several pensées arrived at once; the default
  /// 1.0 is a single pensée.
  void pulse([double intensity = 1.0]) {
    _intensity = intensity < 1.0 ? 1.0 : intensity;
    notifyListeners();
  }
}
