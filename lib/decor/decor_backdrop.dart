import 'dart:math' as math;

import 'package:dewdrop/decor/tilt.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

/// Parallax backdrop shared by every decor.
///
/// Auto-discovers the layered images under `assets/<assetRoot>/<env>/<variant>/`
/// (`0` = farthest … `N` = nearest) and shifts each layer by phone tilt + a
/// gentle drift-free auto-pan to fake 2.5-D depth. The animated FX of a decor
/// (god-rays, particles, birds, shimmer…) render ON TOP of this — so a decor =
/// `DecorBackdrop` + its FX painter. The SAME backdrop serves both the
/// photographic (`assetRoot: 'photo'`) and the hand-painted
/// (`assetRoot: 'illustrated'`) trees, since the illustration is the same scene
/// as the photo.
///
/// While the asset manifest loads (one async frame) — or if a decor has no
/// layers bundled yet — [fallback] is shown, so a decor can pass its old
/// procedural background there and never flash empty.
class DecorBackdrop extends StatefulWidget {
  const DecorBackdrop({
    super.key,
    required this.env,
    this.variant = 0,
    this.parallax = true,
    this.assetRoot = 'photo',
    this.fallback,
    this.midFx,
    this.midFxBelow = 1,
  });

  /// The environment name (`Environment.name`), e.g. `'forest'`.
  final String env;
  final int variant;
  final bool parallax;

  /// Which bundled asset tree the layers come from: `'photo'` or `'illustrated'`.
  final String assetRoot;

  /// Shown until the layers are discovered (or if none are bundled).
  final Widget? fallback;

  /// Optional FX inserted INTO the parallax stack (not on top of it): rendered
  /// just before layer [midFxBelow], so the layers at index >= [midFxBelow]
  /// occlude it — e.g. birds flying between the trees, shooting stars passing
  /// behind a peak. Shifted by the parallax of depth `midFxBelow - 1`. Full-size.
  final Widget? midFx;
  final int midFxBelow;

  @override
  State<DecorBackdrop> createState() => _DecorBackdropState();
}

class _DecorBackdropState extends State<DecorBackdrop>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final TiltController _tilt = TiltController();
  // Repaint only the parallax via a ValueNotifier — the layer images are const.
  final ValueNotifier<Offset> _look = ValueNotifier(Offset.zero);

  List<String> _layers = const [];
  double _lastTick = 0;

  // Only numerically-named files are layers (0.webp, 1.webp, …); base.png and
  // friends are ignored.
  static final _layerRe = RegExp(r'^\d+\.(png|jpe?g|webp)$');

  // Per-decor parallax strength. Scenes with unreliable monocular depth
  // (space: stars/void) stay nearly flat so bad cuts don't swim; landscapes get
  // the full effect.
  static const Map<String, double> _depthStrengthByEnv = {
    'space': 0.25,
    'library': 0.7,
    'aurora': 0.9,
  };
  static const double _maxShift = 34;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
    _loadLayers();
  }

  @override
  void didUpdateWidget(DecorBackdrop old) {
    super.didUpdateWidget(old);
    if (old.env != widget.env ||
        old.variant != widget.variant ||
        old.assetRoot != widget.assetRoot) {
      _layers = const [];
      _loadLayers();
    }
  }

  Future<void> _loadLayers() async {
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final prefix =
        'assets/${widget.assetRoot}/${widget.env}/${widget.variant}/';
    final layers =
        manifest
            .listAssets()
            .where(
              (a) =>
                  a.startsWith(prefix) &&
                  _layerRe.hasMatch(a.split('/').last.toLowerCase()),
            )
            .toList()
          ..sort();
    if (!mounted) return;
    setState(() => _layers = layers);
  }

  void _onTick(Duration elapsed) {
    final now = elapsed.inMicroseconds / 1e6;
    final dt = (now - _lastTick).clamp(0.0, 0.05);
    _lastTick = now;
    final auto = Offset(
      math.sin(now * 0.06) * 0.05,
      math.cos(now * 0.05) * 0.03,
    );
    final target = auto + (widget.parallax ? _tilt.look : Offset.zero);
    final k = 1 - math.exp(-dt * 3);
    _look.value = Offset.lerp(_look.value, target, k)!;
  }

  @override
  void dispose() {
    _tilt.dispose();
    _ticker.dispose();
    _look.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_layers.isEmpty) {
      return widget.fallback ?? const SizedBox.expand();
    }
    final strength = _depthStrengthByEnv[widget.env] ?? 1.0;
    final n = _layers.length;
    return ValueListenableBuilder<Offset>(
      valueListenable: _look,
      builder: (context, look, _) {
        Offset depthOffset(double depth) =>
            look * (n == 1 ? 0.4 : depth / (n - 1)) * _maxShift * strength;
        final children = <Widget>[];
        for (var i = 0; i < n; i++) {
          // Mid-depth FX is inserted just before the layer it hides behind, so
          // the nearer layers occlude it (real depth, not pasted on top).
          if (widget.midFx != null && i == widget.midFxBelow) {
            children.add(
              Transform.translate(
                offset: depthOffset((widget.midFxBelow - 1).toDouble()),
                child: SizedBox.expand(child: widget.midFx),
              ),
            );
          }
          // Back layer (0) stays anchored; front layers move the most. Layers
          // are slightly over-scaled so the shifted edges never show.
          children.add(
            Transform.translate(
              offset: depthOffset(i.toDouble()),
              child: Transform.scale(
                scale: 1.12,
                child: Image.asset(_layers[i], fit: BoxFit.cover),
              ),
            ),
          );
        }
        // midFxBelow past the last layer → in front of everything.
        if (widget.midFx != null && widget.midFxBelow >= n) {
          children.add(
            Transform.translate(
              offset: depthOffset((n - 1).toDouble()),
              child: SizedBox.expand(child: widget.midFx),
            ),
          );
        }
        return Stack(fit: StackFit.expand, children: children);
      },
    );
  }
}
