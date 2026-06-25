import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';

/// A decoded depth-warp scene: the full-resolution photo plus its per-vertex
/// depth grid, ready for [DecorBackdrop]'s warp painter.
///
/// [full] is the cache's OWNING handle — borrowers must `clone()` it for their
/// own use and must NEVER dispose this one (the cache disposes it on eviction).
/// [depth] is immutable read-only data, shared freely between borrowers.
class DecorScene {
  const DecorScene(this.full, this.depth, this.cols, this.rows);
  final ui.Image full;
  final Float32List depth;
  final int cols;
  final int rows;
}

/// Process-wide LRU cache of decoded depth-warp scenes, keyed by
/// `<assetRoot>/<env>/<variant>`.
///
/// Decoding a `full.webp` to a `ui.Image` costs ~11 MB of RAM and a few ms.
/// Keeping the neighbours of the current world resident lets a home/carousel
/// swipe paint the new scene on its FIRST frame instead of briefly flashing the
/// flat base colour while the photo decodes.
///
/// **Lifetime.** The cache holds one owning [ui.Image] handle per entry and
/// disposes it on LRU eviction. Each backdrop borrows via [peek] / [scene] and
/// immediately `clone()`s the result — an independent handle onto the same
/// pixels — so evicting (and disposing) the cache's handle can never pull the
/// image out from under a live painter; the pixels are freed only once every
/// clone is disposed too. The eviction `dispose` is registered after any
/// awaiting borrower's continuation, so the borrower always clones first.
///
/// **Sizing.** [_cap] bounds resident scenes. The home needs current + the two
/// swipe neighbours (3); the world picker keeps current ± 1 (3, overlapping).
/// Six gives headroom — ceiling ~`_cap` × 11 MB ≈ 66 MB worst case, ~33 MB in
/// steady use.
class DecorImageCache {
  DecorImageCache._(this._decoder);

  /// The app-wide cache, decoding from the bundled assets.
  static final DecorImageCache instance = DecorImageCache._(_decodeFromBundle);

  /// A throwaway cache with an injected [decoder] — for unit-testing the LRU /
  /// dedup / eviction behaviour without touching the asset bundle.
  DecorImageCache.forTest(
    Future<DecorScene?> Function(String assetRoot, String env, int variant)
    decoder,
  ) : _decoder = decoder;

  final Future<DecorScene?> Function(String assetRoot, String env, int variant)
  _decoder;

  static const int _cap = 6;

  // Insertion order doubles as the LRU order: the first key is the least
  // recently used, the last is the most recent (re-inserted on every touch).
  final Map<String, _Entry> _entries = {};

  static String _key(String assetRoot, String env, int variant) =>
      '$assetRoot/$env/$variant';

  /// The already-decoded scene for a world, or null if it isn't resident yet
  /// (or ships no depth-warp assets). Synchronous so a backdrop can adopt a
  /// pre-warmed neighbour on its very first frame, with no base-colour flash.
  /// Touches the LRU. Borrowers must `clone()` `scene.full`, never dispose it.
  DecorScene? peek(String assetRoot, String env, int variant) {
    final key = _key(assetRoot, env, variant);
    final entry = _entries.remove(key);
    if (entry == null) return null;
    _entries[key] = entry; // touch → most-recently-used
    return entry.scene;
  }

  /// The decoded scene for a world, decoding (or joining an in-flight decode)
  /// on first request. Resolves to null when the world ships no depth-warp
  /// assets (legacy layer scenes / none). Borrowers must `clone()` `scene.full`
  /// and never dispose it.
  Future<DecorScene?> scene(String assetRoot, String env, int variant) {
    final key = _key(assetRoot, env, variant);
    final entry =
        _entries.remove(key) ?? _Entry(_decoder(assetRoot, env, variant));
    _entries[key] = entry; // (re)insert at the most-recently-used end
    _evict();
    return entry.future;
  }

  /// Decode + cache a world ahead of time, holding no live reference, so a
  /// later [peek] / [scene] for it is instant. Fire-and-forget and deduped.
  void prewarm(String assetRoot, String env, int variant) {
    unawaited(scene(assetRoot, env, variant).catchError((_) => null));
  }

  // Trim back to [_cap] from the least-recently-used end, disposing each
  // evicted entry's owning handle once its decode has settled (clones survive).
  void _evict() {
    while (_entries.length > _cap) {
      final oldest = _entries.keys.first;
      final evicted = _entries.remove(oldest)!;
      unawaited(
        evicted.future
            .then((s) {
              s?.full.dispose();
            })
            .catchError((_) {}),
      );
    }
  }

  // The bundled asset list, loaded once and reused — `prewarm` would otherwise
  // re-parse the manifest on every look-ahead.
  static Future<Set<String>>? _assetsFuture;
  static Future<Set<String>> _assets() =>
      _assetsFuture ??= AssetManifest.loadFromAssetBundle(
        rootBundle,
      ).then((m) => m.listAssets().toSet());

  static Future<DecorScene?> _decodeFromBundle(
    String assetRoot,
    String env,
    int variant,
  ) async {
    final dir = 'assets/$assetRoot/$env/$variant/';
    final assets = await _assets();
    if (!assets.contains('${dir}full.webp') ||
        !assets.contains('${dir}depth.webp')) {
      return null; // not a depth-warp scene
    }
    final full = await _loadImage('${dir}full.webp');
    final (depth, cols, rows) = await _loadDepth('${dir}depth.webp');
    return DecorScene(full, depth, cols, rows);
  }

  static Future<ui.Image> _loadImage(String key) async {
    final data = await rootBundle.load(key);
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
    return (await codec.getNextFrame()).image;
  }

  // Decode the small grayscale depth map straight into a per-vertex grid
  // (near = 1.0). The depth map's resolution IS the warp mesh resolution.
  static Future<(Float32List, int, int)> _loadDepth(String key) async {
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
}

class _Entry {
  _Entry(Future<DecorScene?> decode) : future = decode {
    // Mirror the resolved value so [DecorImageCache.peek] can read it
    // synchronously. Ignored if the decode failed.
    unawaited(future.then((s) => scene = s).catchError((_) => null));
  }

  final Future<DecorScene?> future;
  DecorScene? scene;
}
