import 'package:dewdrop/decor/aurora_decor.dart';
import 'package:dewdrop/decor/beach_decor.dart';
import 'package:dewdrop/decor/desert_decor.dart';
import 'package:dewdrop/decor/environment.dart';
import 'package:dewdrop/decor/fields_decor.dart';
import 'package:dewdrop/decor/forest_decor.dart';
import 'package:dewdrop/decor/library_decor.dart';
import 'package:dewdrop/decor/mountain_decor.dart';
import 'package:dewdrop/decor/space_decor.dart';
import 'package:dewdrop/decor/underwater_decor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('there are 9 environments, each with named non-empty variants', () {
    expect(Environment.values.length, 9);
    for (final e in Environment.values) {
      expect(e.label, isNotEmpty);
      expect(e.variants, isNotEmpty);
      expect(e.variantCount, e.variants.length);
    }
  });

  test('every environment builds its bespoke renderer in both modes', () {
    // Since the depth-warp rewrite, photo and drawn modes share one unified
    // pipeline: buildDecor always returns the env's bespoke decor, differing
    // only by the asset tree it pulls (photo vs illustrated). Both modes thus
    // produce the same widget type per environment.
    final expected = <Environment, Matcher>{
      Environment.space: isA<SpaceDecor>(),
      Environment.underwater: isA<UnderwaterDecor>(),
      Environment.forest: isA<ForestDecor>(),
      Environment.beach: isA<BeachDecor>(),
      Environment.library: isA<LibraryDecor>(),
      Environment.mountain: isA<MountainDecor>(),
      Environment.desert: isA<DesertDecor>(),
      Environment.aurora: isA<AuroraDecor>(),
      Environment.fields: isA<FieldsDecor>(),
    };
    for (final mode in RenderMode.values) {
      expected.forEach((env, matcher) {
        expect(buildDecor(env, 0, mode), matcher, reason: '${env.name}/$mode');
      });
    }
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
