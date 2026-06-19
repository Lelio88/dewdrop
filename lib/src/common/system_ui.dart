import 'dart:io' show Platform;

import 'package:flutter/services.dart';

/// Centralised control of the Android/iOS system bars (status + navigation).
///
/// DewDrop is decor-first — the chosen scene fills the whole screen. Two modes:
///  - [edgeToEdge]: bars stay visible but fully transparent, so the decor shows
///    *through* them while every control still respects the safe-area insets.
///    Used on every screen except the live decor.
///  - [immersive]: bars are hidden and only swiped back transiently
///    (`immersiveSticky`) — the most immersive full-screen decor view.
///
/// Why one place: the mode is flipped on screen transitions (immersive on the
/// decor, edge-to-edge on the menus/settings) and re-asserted when the app
/// returns to the foreground. Scattering raw `SystemChrome` calls drifts that
/// state and reintroduces the "control hidden behind the nav bar" bug.
///
/// No-op off mobile — desktop (decor dev on Windows) has no system bars to drive.
///
/// Usage:
/// ```dart
/// SystemUi.edgeToEdge();           // at boot (main.dart)
/// SystemUi.immersive();            // entering the live decor (HomeView)
/// ```
class SystemUi {
  const SystemUi._();

  // Transparent bars + no OS contrast scrim (Android 10+). Light icons because
  // the decors are predominantly dark; the app theme is `ThemeData.dark`.
  static const _bars = SystemUiOverlayStyle(
    statusBarColor: Color(0x00000000),
    systemNavigationBarColor: Color(0x00000000),
    systemNavigationBarContrastEnforced: false,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarIconBrightness: Brightness.light,
  );

  static bool get _mobile => Platform.isAndroid || Platform.isIOS;

  /// Bars visible but transparent; content draws edge-to-edge underneath.
  static void edgeToEdge() {
    if (!_mobile) return;
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(_bars);
  }

  /// Bars hidden; reappear transiently on a swipe from the screen edge.
  static void immersive() {
    if (!_mobile) return;
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setSystemUIOverlayStyle(_bars);
  }
}
