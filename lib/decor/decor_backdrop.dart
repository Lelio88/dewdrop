import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dewdrop/decor/tilt.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

/// Parallax backdrop shared by every decor.
///
/// Two render paths, chosen by which assets a scene ships:
///
///  - **Depth warp (preferred).** When a scene ships `full.webp` + `depth.webp`
///    we render the WHOLE image as a continuous `drawVertices` mesh, displacing
///    each vertex's texture coordinate by `depth * tilt`. Near pixels move more
///    than far → parallax. The mesh STRETCHES at depth steps (never tears), so
///    there is no disocclusion hole, no inpaint, and therefore none of the
///    halo / ghost / aura artefacts that discrete layer-cutting produced. Thin
///    structures (palm fronds) get a soft partial displacement — exactly where
///    matting failed. Pure Canvas (`drawVertices` + `ImageShader`), no runtime
///    fragment shader, so it renders on desktop too.
///
///  - **Layers (legacy fallback).** Older scenes that still ship numbered cut
///    layers (`0.webp` … `N.webp`) are composited with a per-depth parallax
///    shift, as before. Kept so un-migrated scenes keep working.
///
/// The animated FX of a decor render ON TOP of this (the parent stacks its FX
/// painter over the backdrop). While assets load — or if a scene ships neither —
/// a flat [baseColor] fill is shown so a decor never flashes empty (and never a
/// black gap during a carousel swipe). The world's preloaded photo replaces it
/// in one frame; there is no longer a procedural scene drawn underneath.
class DecorBackdrop extends StatefulWidget {
  const DecorBackdrop({
    super.key,
    required this.env,
    this.variant = 0,
    this.parallax = true,
    this.assetRoot = 'photo',
    this.baseColor = const Color(0xFF06070D),
    this.midFx,
    this.midFxBelow = 1,
  });

  /// The environment name (`Environment.name`), e.g. `'forest'`.
  final String env;
  final int variant;
  final bool parallax;

  /// Which bundled asset tree the layers come from: `'photo'` or `'illustrated'`.
  final String assetRoot;

  /// Flat colour shown until the image is decoded (or if none is bundled) — the
  /// world's dominant tone, so the brief pre-decode frame reads as the scene,
  /// not a black hole. Cheap `ColoredBox`, no animation.
  final Color baseColor;

  /// Optional FX rendered on top of the backdrop. (In the legacy layer path it
  /// was inserted BETWEEN layers at [midFxBelow]; in the depth-warp path it
  /// renders on top — depth-aware occlusion of FX is a later refinement.)
  final Widget? midFx;
  final int midFxBelow;

  @override
  State<DecorBackdrop> createState() => _DecorBackdropState();
}

class _DecorBackdropState extends State<DecorBackdrop>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final TiltController _tilt = TiltController();
  // Repaint the warp/parallax via a ValueNotifier — the image is const.
  final ValueNotifier<Offset> _look = ValueNotifier(Offset.zero);

  // Depth-warp assets.
  ui.Image? _full;
  Float32List? _depth; // rows*cols, near = 1.0
  int _dCols = 0, _dRows = 0;

  // Legacy layer assets.
  List<String> _layers = const [];

  double _lastTick = 0;

  static final _layerRe = RegExp(r'^\d+\.(png|jpe?g|webp)$');

  // Per-decor parallax strength. Scenes with unreliable monocular depth
  // (space: stars/void) stay gentle so the warp never rubber-bands; landscapes
  // get the full, lively effect.
  static const Map<String, double> _strengthByEnv = {
    'space': 0.30,
    'aurora': 0.65,
    'desert': 0.8,
    'library': 0.85,
  };
  // Max texture-coordinate displacement (image px) at full tilt for depth=1.
  static const double _warpShift = 120;
  static const double _maxShift = 34; // legacy layer shift

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
    _load();
  }

  @override
  void didUpdateWidget(DecorBackdrop old) {
    super.didUpdateWidget(old);
    if (old.env != widget.env ||
        old.variant != widget.variant ||
        old.assetRoot != widget.assetRoot) {
      _full = null;
      _depth = null;
      _layers = const [];
      _load();
    }
  }

  Future<void> _load() async {
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final dir = 'assets/${widget.assetRoot}/${widget.env}/${widget.variant}/';
    final assets = manifest.listAssets().toSet();
    if (assets.contains('${dir}full.webp') &&
        assets.contains('${dir}depth.webp')) {
      final full = await _loadImage('${dir}full.webp');
      final depth = await _loadDepth('${dir}depth.webp');
      if (!mounted) return;
      setState(() {
        _full = full;
        _depth = depth.$1;
        _dCols = depth.$2;
        _dRows = depth.$3;
      });
      return;
    }
    final layers =
        assets
            .where(
              (a) =>
                  a.startsWith(dir) &&
                  _layerRe.hasMatch(a.split('/').last.toLowerCase()),
            )
            .toList()
          ..sort();
    if (!mounted) return;
    setState(() => _layers = layers);
  }

  Future<ui.Image> _loadImage(String key) async {
    final data = await rootBundle.load(key);
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
    return (await codec.getNextFrame()).image;
  }

  // Decode the small grayscale depth map straight into a per-vertex grid
  // (near = 1.0). The depth map's resolution IS the warp mesh resolution.
  Future<(Float32List, int, int)> _loadDepth(String key) async {
    final data = await rootBundle.load(key);
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
    final img = (await codec.getNextFrame()).image;
    final cols = img.width, rows = img.height;
    final bytes = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
    img.dispose();
    final grid = Float32List(cols * rows);
    for (var i = 0; i < grid.length; i++) {
      grid[i] = bytes!.getUint8(i * 4) / 255.0; // R channel
    }
    return (grid, cols, rows);
  }

  void _onTick(Duration elapsed) {
    final now = elapsed.inMicroseconds / 1e6;
    final dt = (now - _lastTick).clamp(0.0, 0.05);
    _lastTick = now;
    // A gentle always-on auto-pan makes the depth read even at rest (near
    // content drifts vs far); the tilt adds the responsive parallax on top.
    final auto = Offset(
      math.sin(now * 0.16) * 0.09,
      math.cos(now * 0.13) * 0.055,
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
    _full?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final full = _full;
    final depth = _depth;
    if (full != null && depth != null) {
      final strength = _strengthByEnv[widget.env] ?? 1.0;
      return Stack(
        fit: StackFit.expand,
        children: [
          RepaintBoundary(
            child: ValueListenableBuilder<Offset>(
              valueListenable: _look,
              builder: (context, look, _) => CustomPaint(
                painter: _WarpPainter(
                  image: full,
                  depth: depth,
                  cols: _dCols,
                  rows: _dRows,
                  look: look,
                  shift: _warpShift * strength,
                ),
                child: const SizedBox.expand(),
              ),
            ),
          ),
          if (widget.midFx != null) widget.midFx!,
        ],
      );
    }
    if (_layers.isEmpty) {
      return ColoredBox(color: widget.baseColor);
    }
    return _buildLayers();
  }

  Widget _buildLayers() {
    final strength = _strengthByEnv[widget.env] ?? 1.0;
    final n = _layers.length;
    return ValueListenableBuilder<Offset>(
      valueListenable: _look,
      builder: (context, look, _) {
        Offset depthOffset(double d) =>
            look * (n == 1 ? 0.4 : d / (n - 1)) * _maxShift * strength;
        final children = <Widget>[];
        for (var i = 0; i < n; i++) {
          if (widget.midFx != null && i == widget.midFxBelow) {
            children.add(
              Transform.translate(
                offset: depthOffset((widget.midFxBelow - 1).toDouble()),
                child: SizedBox.expand(child: widget.midFx),
              ),
            );
          }
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
        if (widget.midFx != null && widget.midFxBelow >= n) {
          children.add(SizedBox.expand(child: widget.midFx));
        }
        return Stack(fit: StackFit.expand, children: children);
      },
    );
  }
}

/// Renders [image] as a depth-displaced triangle mesh: vertices sit on a fixed
/// cover grid; each vertex's TEXTURE coordinate is pushed by `depth * look *
/// shift`, so nearer image regions slide more than far ones. The mesh stretches
/// (never tears) at depth steps → no hole, no inpaint, no halo. Reuses flat
/// `Float32List` buffers so a tilt costs no per-frame allocation.
class _WarpPainter extends CustomPainter {
  _WarpPainter({
    required this.image,
    required this.depth,
    required this.cols,
    required this.rows,
    required this.look,
    required this.shift,
  }) : _pos = Float32List(cols * rows * 2),
       _tex = Float32List(cols * rows * 2),
       _texBase = Float32List(cols * rows * 2),
       _indices = _buildIndices(cols, rows) {
    final iw = image.width.toDouble(), ih = image.height.toDouble();
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        final i = r * cols + c;
        _texBase[2 * i] = (c / (cols - 1)) * iw;
        _texBase[2 * i + 1] = (r / (rows - 1)) * ih;
      }
    }
  }

  final ui.Image image;
  final Float32List depth; // near = 1.0
  final int cols, rows;
  final Offset look;
  final double shift;

  final Float32List _pos;
  final Float32List _tex;
  final Float32List _texBase;
  final Uint16List _indices;

  static const double _overscale = 1.12;

  static Uint16List _buildIndices(int cols, int rows) {
    final idx = Uint16List((cols - 1) * (rows - 1) * 6);
    var k = 0;
    for (var r = 0; r < rows - 1; r++) {
      for (var c = 0; c < cols - 1; c++) {
        final i = r * cols + c;
        idx[k++] = i;
        idx[k++] = i + 1;
        idx[k++] = i + cols;
        idx[k++] = i + 1;
        idx[k++] = i + cols + 1;
        idx[k++] = i + cols;
      }
    }
    return idx;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final iw = image.width.toDouble(), ih = image.height.toDouble();
    // BoxFit.cover (+ overscale so the warped edges never reveal a gap).
    final scale =
        (size.width / iw > size.height / ih
            ? size.width / iw
            : size.height / ih) *
        _overscale;
    final dispW = iw * scale, dispH = ih * scale;
    final ox = (size.width - dispW) / 2, oy = (size.height - dispH) / 2;

    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        final i = r * cols + c;
        // Fixed cover position on screen.
        _pos[2 * i] = ox + (c / (cols - 1)) * dispW;
        _pos[2 * i + 1] = oy + (r / (rows - 1)) * dispH;
        // Texture coordinate pushed by depth * tilt (parallax).
        final d = depth[i];
        _tex[2 * i] = _texBase[2 * i] - look.dx * d * shift;
        _tex[2 * i + 1] = _texBase[2 * i + 1] - look.dy * d * shift;
      }
    }

    final verts = ui.Vertices.raw(
      VertexMode.triangles,
      _pos,
      textureCoordinates: _tex,
      indices: _indices,
    );
    final paint = Paint()
      ..shader = ui.ImageShader(
        image,
        TileMode.clamp,
        TileMode.clamp,
        Matrix4.identity().storage,
      );
    canvas.drawVertices(verts, BlendMode.srcOver, paint);
    verts.dispose();
  }

  @override
  bool shouldRepaint(_WarpPainter old) =>
      old.look != look || old.image != image || old.shift != shift;
}
