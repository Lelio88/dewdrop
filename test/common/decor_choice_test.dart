import 'package:dewdrop/decor/environment.dart';
import 'package:dewdrop/src/common/decor_choice.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseDecor', () {
    test('parses "<env>:<variant>"', () {
      final (env, v) = parseDecor('forest:1');
      expect(env, Environment.forest);
      expect(v, 1);
    });

    test('parses the aurora decor', () {
      final (env, v) = parseDecor('aurora:1');
      expect(env, Environment.aurora);
      expect(v, 1);
    });

    test('falls back to space on an unknown environment', () {
      final (env, v) = parseDecor('atlantis:2');
      expect(env, Environment.space);
      expect(v, 2); // the variant is still parsed
    });

    test('defaults the variant to 0 when missing', () {
      expect(parseDecor('mountain'), (Environment.mountain, 0));
    });

    test('defaults the variant to 0 when non-numeric', () {
      expect(parseDecor('desert:abc'), (Environment.desert, 0));
    });

    test('empty string → space/0', () {
      expect(parseDecor(''), (Environment.space, 0));
    });
  });

  group('encodeDecor', () {
    test('encodes env + variant', () {
      expect(encodeDecor(Environment.beach, 1), 'beach:1');
    });

    test('round-trips with parseDecor for every valid decor', () {
      for (final env in Environment.values) {
        for (var v = 0; v < env.variantCount; v++) {
          final (e2, v2) = parseDecor(encodeDecor(env, v));
          expect(e2, env, reason: 'env round-trip for ${env.name}:$v');
          expect(v2, v, reason: 'variant round-trip for ${env.name}:$v');
        }
      }
    });
  });

  group('parseRenderMode', () {
    test('drawn', () => expect(parseRenderMode('drawn'), RenderMode.drawn));
    test('photo', () => expect(parseRenderMode('photo'), RenderMode.photo));
    test(
      'unknown defaults to photo',
      () => expect(parseRenderMode('whatever'), RenderMode.photo),
    );
  });

  group('encodeFavorite / parseFavorite', () {
    test('encodes env + variant + mode', () {
      expect(
        encodeFavorite(Environment.forest, 1, RenderMode.photo),
        'forest:1:photo',
      );
      expect(
        encodeFavorite(Environment.space, 0, RenderMode.drawn),
        'space:0:drawn',
      );
    });

    test('parses "<env>:<variant>:<mode>"', () {
      final (env, v, mode) = parseFavorite('beach:2:drawn');
      expect(env, Environment.beach);
      expect(v, 2);
      expect(mode, RenderMode.drawn);
    });

    test('a plain "<env>:<variant>" (no mode) defaults to photo', () {
      final (env, v, mode) = parseFavorite('mountain:1');
      expect(env, Environment.mountain);
      expect(v, 1);
      expect(mode, RenderMode.photo);
    });

    test('falls back like parseDecor on garbage', () {
      final (env, v, mode) = parseFavorite('atlantis:abc:whatever');
      expect(env, Environment.space); // unknown env
      expect(v, 0); // non-numeric variant
      expect(mode, RenderMode.photo); // unknown mode
    });

    test('round-trips for every valid decor in both modes', () {
      for (final env in Environment.values) {
        for (var v = 0; v < env.variantCount; v++) {
          for (final m in RenderMode.values) {
            final (e2, v2, m2) = parseFavorite(encodeFavorite(env, v, m));
            expect(e2, env, reason: 'env ${env.name}:$v:${m.name}');
            expect(v2, v, reason: 'variant ${env.name}:$v:${m.name}');
            expect(m2, m, reason: 'mode ${env.name}:$v:${m.name}');
          }
        }
      }
    });
  });
}
