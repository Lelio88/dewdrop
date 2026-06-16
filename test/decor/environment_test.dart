import 'package:dewdrop/decor/aurora_decor.dart';
import 'package:dewdrop/decor/beach_decor.dart';
import 'package:dewdrop/decor/desert_decor.dart';
import 'package:dewdrop/decor/environment.dart';
import 'package:dewdrop/decor/forest_decor.dart';
import 'package:dewdrop/decor/library_decor.dart';
import 'package:dewdrop/decor/mountain_decor.dart';
import 'package:dewdrop/decor/photo_decor.dart';
import 'package:dewdrop/decor/space_decor.dart';
import 'package:dewdrop/decor/underwater_decor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('there are 8 environments, each with named non-empty variants', () {
    expect(Environment.values.length, 8);
    for (final e in Environment.values) {
      expect(e.label, isNotEmpty);
      expect(e.variants, isNotEmpty);
      expect(e.variantCount, e.variants.length);
    }
  });

  test('photo mode always builds a PhotoDecor', () {
    for (final e in Environment.values) {
      expect(
        buildDecor(e, 0, RenderMode.photo),
        isA<PhotoDecor>(),
        reason: 'photo decor for ${e.name}',
      );
    }
  });

  test('drawn mode builds the bespoke renderer for every environment', () {
    expect(
      buildDecor(Environment.space, 0, RenderMode.drawn),
      isA<SpaceDecor>(),
    );
    expect(
      buildDecor(Environment.underwater, 0, RenderMode.drawn),
      isA<UnderwaterDecor>(),
    );
    expect(
      buildDecor(Environment.forest, 0, RenderMode.drawn),
      isA<ForestDecor>(),
    );
    expect(
      buildDecor(Environment.beach, 0, RenderMode.drawn),
      isA<BeachDecor>(),
    );
    expect(
      buildDecor(Environment.library, 0, RenderMode.drawn),
      isA<LibraryDecor>(),
    );
    expect(
      buildDecor(Environment.mountain, 0, RenderMode.drawn),
      isA<MountainDecor>(),
    );
    expect(
      buildDecor(Environment.desert, 0, RenderMode.drawn),
      isA<DesertDecor>(),
    );
    expect(
      buildDecor(Environment.aurora, 0, RenderMode.drawn),
      isA<AuroraDecor>(),
    );
  });

  test('out-of-range variants are clamped (never throw) in both modes', () {
    for (final e in Environment.values) {
      for (final mode in RenderMode.values) {
        expect(
          () => buildDecor(e, 99, mode),
          returnsNormally,
          reason: 'high variant for ${e.name}/$mode',
        );
        expect(
          () => buildDecor(e, -5, mode),
          returnsNormally,
          reason: 'negative variant for ${e.name}/$mode',
        );
      }
    }
  });
}
