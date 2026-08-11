import 'dart:io' show Platform;

import 'package:flutter/services.dart';

/// Dart half of DewDrop's **app-level audio focus** (Android only).
///
/// Rationale: the soundscape's six players run with `AndroidAudioFocus.none` so
/// they mix instead of stealing focus from one another (see `lib/main.dart`) —
/// which also means nothing tells Android that DewDrop is playing, and the user's
/// Spotify/YouTube keeps running on top. This asks for focus **once for the whole
/// app**, so other media apps pause like they do for any other sound app.
///
/// Invariants:
/// - Only [request] while sound is actually audible, and [abandon] as soon as it
///   isn't (master mute, background, teardown) — otherwise a muted DewDrop would
///   keep the user's music hostage.
/// - [onLost] must pause the players **without** calling [abandon]: dropping the
///   request unregisters the listener, and the [onGained] that ends a transient
///   loss (a phone call) would never arrive.
///
/// Off Android this is a no-op: iOS interrupts other apps through its
/// `AVAudioSessionCategory.playback` session, and desktop has no channel at all.
///
/// Native side: `android/app/src/main/kotlin/app/dewdrop/MainActivity.kt`.
class AudioFocus {
  AudioFocus({MethodChannel? channel, bool? supported})
    : _channel = channel ?? const MethodChannel(_kChannel),
      _supported = supported ?? Platform.isAndroid;

  static const _kChannel = 'app.dewdrop/audio_focus';

  final MethodChannel _channel;
  final bool _supported;
  bool _held = false;

  /// Wires the native focus callbacks. [onLost] fires when another app takes the
  /// focus (or a call comes in), [onGained] when a transient loss ends.
  void bind({required VoidCallback onLost, required VoidCallback onGained}) {
    if (!_supported) return;
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onFocusLost':
          _held = false;
          onLost();
        case 'onFocusGained':
          _held = true;
          onGained();
      }
      return null;
    });
  }

  /// Takes app-wide audio focus — other media apps pause. Idempotent.
  Future<void> request() async {
    if (!_supported || _held) return;
    _held = true; // optimistic: a denied request still lets our sound play
    await _invoke('request');
  }

  /// Gives the focus back so the user's music can resume. Idempotent.
  Future<void> abandon() async {
    if (!_supported || !_held) return;
    _held = false;
    await _invoke('abandon');
  }

  /// Drops the callback handler (call from the owner's dispose).
  void dispose() {
    if (!_supported) return;
    _channel.setMethodCallHandler(null);
  }

  Future<void> _invoke(String method) async {
    try {
      await _channel.invokeMethod<void>(method);
    } on PlatformException catch (_) {
      // Focus is a nicety, never a reason to break the ambiance.
    } on MissingPluginException catch (_) {
      // Engine not attached yet (or a host without the channel).
    }
  }
}
