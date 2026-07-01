import 'package:dewdrop/decor/april_decor.dart';
import 'package:dewdrop/decor/aurora_decor.dart';
import 'package:dewdrop/decor/beach_decor.dart';
import 'package:dewdrop/decor/christmas_decor.dart';
import 'package:dewdrop/decor/desert_decor.dart';
import 'package:dewdrop/decor/environment.dart';
import 'package:dewdrop/decor/fields_decor.dart';
import 'package:dewdrop/decor/forest_decor.dart';
import 'package:dewdrop/decor/halloween_decor.dart';
import 'package:dewdrop/decor/library_decor.dart';
import 'package:dewdrop/decor/mountain_decor.dart';
import 'package:dewdrop/decor/space_decor.dart';
import 'package:dewdrop/decor/underwater_decor.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('there are 12 environments (9 standard + 3 seasonal), each with named '
      'non-empty variants', () {
    expect(Environment.values.length, 12);
    expect(Environment.values.where((e) => e.seasonal).length, 3);
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
    //
    // buildDecor wraps each decor in a ClipRect (so the backdrop's ~6% edge
    // overspill can't bleed into a neighbouring world during a carousel/PageView
    // swipe); the bespoke renderer is the clip's child.
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
      Environment.christmas: isA<ChristmasDecor>(),
      Environment.halloween: isA<HalloweenDecor>(),
      Environment.april: isA<AprilDecor>(),
    };
    for (final mode in RenderMode.values) {
      expected.forEach((env, matcher) {
        final built = buildDecor(env, 0, mode);
        expect(built, isA<ClipRect>(), reason: '${env.name}/$mode');
        expect((built as ClipRect).child, matcher, reason: '${env.name}/$mode');
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
