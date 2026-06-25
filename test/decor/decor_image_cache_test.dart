import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dewdrop/decor/decor_image_cache.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Real (tiny) images so eviction's dispose is observable via debugDisposed.
  final created = <ui.Image>[];
  Future<ui.Image> img() async {
    final rec = ui.PictureRecorder();
    ui.Canvas(rec).drawRect(const ui.Rect.fromLTWH(0, 0, 1, 1), ui.Paint());
    final image = await rec.endRecording().toImage(1, 1);
    created.add(image);
    return image;
  }

  DecorScene mkScene(ui.Image i) => DecorScene(i, Float32List(1), 1, 1);

  tearDown(() {
    for (final i in created) {
      if (!i.debugDisposed) i.dispose();
    }
    created.clear();
  });

  test('peek is null until decoded, then returns the scene', () async {
    final s = mkScene(await img());
    final cache = DecorImageCache.forTest((r, e, v) async => s);

    expect(cache.peek('photo', 'space', 0), isNull);
    expect(await cache.scene('photo', 'space', 0), same(s));
    expect(cache.peek('photo', 'space', 0), same(s));
  });

  test('dedups concurrent + repeat requests — one decode per key', () async {
    var calls = 0;
    final s = mkScene(await img());
    final cache = DecorImageCache.forTest((r, e, v) async {
      calls++;
      return s;
    });

    await Future.wait([
      cache.scene('photo', 'space', 0),
      cache.scene('photo', 'space', 0),
    ]);
    await cache.scene('photo', 'space', 0);

    expect(calls, 1);
  });

  test('resolves null for a world with no depth-warp assets', () async {
    final cache = DecorImageCache.forTest((r, e, v) async => null);

    expect(await cache.scene('illustrated', 'space', 0), isNull);
    expect(cache.peek('illustrated', 'space', 0), isNull);
  });

  test('evicts + disposes the least-recently-used past the cap of 6', () async {
    final scenes = <int, DecorScene>{};
    for (var i = 0; i < 8; i++) {
      scenes[i] = mkScene(await img());
    }
    final cache = DecorImageCache.forTest((r, e, v) async => scenes[v]!);

    for (var i = 0; i < 7; i++) {
      await cache.scene('photo', 'space', i);
    }
    await Future<void>.delayed(Duration.zero); // let eviction disposes run

    // 7 decoded, cap 6 → variant 0 (oldest) evicted and disposed.
    expect(cache.peek('photo', 'space', 0), isNull);
    expect(scenes[0]!.full.debugDisposed, isTrue);
    // The most recent stays resident and alive.
    expect(cache.peek('photo', 'space', 6), same(scenes[6]));
    expect(scenes[6]!.full.debugDisposed, isFalse);
  });

  test('peek refreshes the LRU so a peeked scene survives eviction', () async {
    final scenes = <int, DecorScene>{};
    for (var i = 0; i < 8; i++) {
      scenes[i] = mkScene(await img());
    }
    final cache = DecorImageCache.forTest((r, e, v) async => scenes[v]!);

    for (var i = 0; i < 6; i++) {
      await cache.scene('photo', 'space', i); // 0..5 resident (full)
    }
    // Touch variant 0 → now most-recently-used (variant 1 becomes the LRU).
    expect(cache.peek('photo', 'space', 0), same(scenes[0]));

    await cache.scene('photo', 'space', 6); // pushes one out
    await Future<void>.delayed(Duration.zero);

    expect(cache.peek('photo', 'space', 0), same(scenes[0])); // survived
    expect(cache.peek('photo', 'space', 1), isNull); // evicted instead
  });
}
