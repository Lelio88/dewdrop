import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:sensors_plus/sensors_plus.dart';

/// Device-tilt → a gentle "look" offset that drives decor parallax.
///
/// Uses the **gravity vector** (low-passed) with an **adaptive neutral**: the
/// reference orientation isn't captured once — it slowly chases your current
/// orientation. So whatever angle you hold the phone at becomes "centre", a
/// held tilt eases back to centre over a few seconds, and you can never get
/// stuck at an edge (the old fixed-baseline "tête en bas" bug). No fragile
/// "capture the baseline at the right moment", and no gyro integration, so it
/// never drifts.
///
/// Two knobs:
/// - [sensitivity]: how far a tilt moves the look (higher = stronger parallax).
/// - [recenter]: how fast the neutral follows you, per reading (smaller = the
///   scene holds a tilt longer before easing back to centre).
///
/// Create one per decor `State` (in `initState`), read [look] each frame, and
/// [dispose] it. Only the active decor is mounted, so there is at most one live
/// sensor subscription at a time.
class TiltController {
  TiltController({this.sensitivity = 0.13, this.recenter = 0.008}) {
    // Game-rate sampling (~50 Hz) so the parallax is smooth, not steppy like the
    // default ~5 Hz; also makes the filter time-constants predictable.
    _sub = accelerometerEventStream(
      samplingPeriod: SensorInterval.gameInterval,
    ).listen(_onAccel);
  }

  /// How far a given tilt moves the look (higher = stronger parallax).
  final double sensitivity;

  /// How fast the neutral chases your orientation, per reading (0..1). Smaller
  /// holds a tilt longer before the scene eases back to centre.
  final double recenter;

  StreamSubscription<AccelerometerEvent>? _sub;

  /// Current look offset, components in [-1, 1]. Read it each frame.
  Offset look = Offset.zero;

  // Fast low-pass = current gravity (responsive). Slow low-pass = the adaptive
  // neutral the look is measured against.
  double _gx = 0, _gz = 0, _baseGx = 0, _baseGz = 0;
  bool _init = false;

  void _onAccel(AccelerometerEvent e) {
    const fast = 0.12; // low-pass toward the gravity vector
    if (!_init) {
      _init = true;
      _gx = _baseGx = e.x;
      _gz = _baseGz = e.z; // start centred (look = 0)
    } else {
      _gx += fast * (e.x - _gx);
      _gz += fast * (e.z - _gz);
      // The neutral slowly chases the current orientation.
      _baseGx += recenter * (_gx - _baseGx);
      _baseGz += recenter * (_gz - _baseGz);
    }
    final lx = ((_gx - _baseGx) * sensitivity).clamp(-1.0, 1.0);
    final ly = ((_gz - _baseGz) * sensitivity).clamp(-1.0, 1.0);
    look = Offset(-lx, ly);
  }

  void dispose() => _sub?.cancel();
}
