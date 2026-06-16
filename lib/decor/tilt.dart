import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:sensors_plus/sensors_plus.dart';

/// Device-tilt → a gentle "look" offset that drives decor parallax.
///
/// Drift-free: it uses the **absolute gravity vector** (low-passed), measured
/// relative to a neutral baseline captured on the first reading — so `look` is
/// zero at whatever angle you're holding the phone, and offsets as you tilt it.
/// No integration, so it never drifts (unlike a raw gyroscope). This replaces
/// the old finger/pointer control: the scene now follows the phone's motion.
///
/// Usage: create one per decor `State` (in `initState`), read [look] each frame,
/// and [dispose] it. Only the *active* decor is mounted, so there is at most one
/// live sensor subscription at a time.
class TiltController {
  TiltController({this.sensitivity = 0.13}) {
    _sub = accelerometerEventStream().listen(_onAccel);
  }

  /// How far a given tilt moves the look (higher = stronger parallax).
  final double sensitivity;

  StreamSubscription<AccelerometerEvent>? _sub;

  /// Current look offset, components in [-1, 1]. Read it each frame.
  Offset look = Offset.zero;

  double _gx = 0, _gz = 0, _baseGx = 0, _baseGz = 0;
  bool _init = false;

  void _onAccel(AccelerometerEvent e) {
    const a = 0.18; // low-pass toward the gravity vector
    _gx = _init ? _gx + a * (e.x - _gx) : e.x;
    _gz = _init ? _gz + a * (e.z - _gz) : e.z;
    if (!_init) {
      _init = true;
      _baseGx = _gx;
      _baseGz = _gz;
    }
    final lx = ((_gx - _baseGx) * sensitivity).clamp(-1.0, 1.0);
    final ly = ((_gz - _baseGz) * sensitivity).clamp(-1.0, 1.0);
    look = Offset(-lx, ly);
  }

  void dispose() => _sub?.cancel();
}
