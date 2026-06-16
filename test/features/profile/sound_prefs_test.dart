import 'package:dewdrop/src/features/profile/domain/sound_prefs.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LayerPref', () {
    test('defaults: on, full volume', () {
      const p = LayerPref();
      expect(p.on, true);
      expect(p.vol, 1.0);
    });

    test('fromJson(null) → defaults', () {
      final p = LayerPref.fromJson(null);
      expect(p.on, true);
      expect(p.vol, 1.0);
    });

    test('fromJson reads on + vol', () {
      final p = LayerPref.fromJson({'on': false, 'vol': 0.4});
      expect(p.on, false);
      expect(p.vol, 0.4);
    });

    test('toJson/fromJson round-trip', () {
      const p = LayerPref(on: false, vol: 0.3);
      final r = LayerPref.fromJson(p.toJson());
      expect(r.on, false);
      expect(r.vol, 0.3);
    });

    test('copyWith changes only the given field', () {
      const p = LayerPref();
      expect(p.copyWith(vol: 0.5).vol, 0.5);
      expect(p.copyWith(vol: 0.5).on, true);
      expect(p.copyWith(on: false).vol, 1.0);
    });
  });

  group('SecondaryPref', () {
    test('defaults', () {
      const p = SecondaryPref();
      expect(p.on, true);
      expect(p.vol, 0.5);
      expect(p.freq, 0.5);
    });

    test('fromJson(null) uses the supplied category default volume', () {
      expect(SecondaryPref.fromJson(null, defVol: 0.7).vol, 0.7);
    });

    test('toJson/fromJson round-trip', () {
      const p = SecondaryPref(on: false, vol: 0.8, freq: 0.2);
      final r = SecondaryPref.fromJson(p.toJson());
      expect(r.on, false);
      expect(r.vol, 0.8);
      expect(r.freq, 0.2);
    });
  });

  group('EnvSoundPref', () {
    test('defaults: ambiance + music on, no secondaries', () {
      const p = EnvSoundPref();
      expect(p.amb.on, true);
      expect(p.mus.on, true);
      expect(p.sec, isEmpty);
    });

    test('toJson omits an empty "sec"', () {
      expect(const EnvSoundPref().toJson().containsKey('sec'), false);
    });

    test('withSecondary adds a category and does not mutate the original', () {
      const p = EnvSoundPref();
      final p2 = p.withSecondary('thunder', const SecondaryPref(vol: 0.6));
      expect(p2.sec['thunder']!.vol, 0.6);
      expect(p.sec, isEmpty); // original untouched (immutable)
    });

    test('round-trips ambiance + secondaries through JSON', () {
      final p = const EnvSoundPref(
        amb: LayerPref(vol: 0.5),
      ).withSecondary('t', const SecondaryPref(vol: 0.6, freq: 0.3));
      final r = EnvSoundPref.fromJson(p.toJson());
      expect(r.amb.vol, 0.5);
      expect(r.sec['t']!.vol, 0.6);
      expect(r.sec['t']!.freq, 0.3);
    });
  });

  group('SoundPrefs', () {
    test('empty → engine defaults for any env', () {
      final p = SoundPrefs.empty.forEnv('desert');
      expect(p.amb.on, true);
      expect(p.mus.vol, 1.0);
      expect(p.sec, isEmpty);
    });

    test('withEnv stores per-env prefs without mutating the original', () {
      final p = SoundPrefs.empty.withEnv(
        'space',
        const EnvSoundPref(mus: LayerPref(on: false)),
      );
      expect(p.forEnv('space').mus.on, false);
      expect(SoundPrefs.empty.byEnv, isEmpty);
    });

    test('fromJson(null) → empty', () {
      expect(SoundPrefs.fromJson(null).byEnv, isEmpty);
    });

    test('full round-trip preserves a customized secondary', () {
      final p = SoundPrefs.empty.withEnv(
        'desert',
        const EnvSoundPref().withSecondary(
          'thunder',
          const SecondaryPref(on: false, vol: 0.4, freq: 0.7),
        ),
      );
      final t = SoundPrefs.fromJson(
        p.toJson(),
      ).forEnv('desert').sec['thunder']!;
      expect(t.on, false);
      expect(t.vol, 0.4);
      expect(t.freq, 0.7);
    });
  });
}
