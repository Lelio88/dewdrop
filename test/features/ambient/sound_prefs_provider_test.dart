import 'package:dewdrop/src/features/ambient/application/ambient_providers.dart';
import 'package:dewdrop/src/features/profile/application/profile_providers.dart';
import 'package:dewdrop/src/features/profile/domain/profile.dart';
import 'package:dewdrop/src/features/profile/domain/sound_prefs.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fakes.dart';

// soundPrefsProvider holds the live, editable per-decor sound customization.
// It seeds once from the signed-in profile and is mutated by the decor picker.
// (The debounced Supabase save fires on a 700 ms timer that the container's
// dispose cancels, so these synchronous tests never touch the repository.)
void main() {
  test('seeds its state from the profile sound_prefs', () async {
    final profile = Profile.fromMap({
      'id': 'u',
      'sound_prefs': {
        'desert': {
          'mus': {'on': false, 'vol': 0.3},
        },
      },
    });
    final container = ProviderContainer(overrides: [
      myProfileProvider.overrideWith((ref) async => profile),
    ]);
    addTearDown(container.dispose);

    await container.read(myProfileProvider.future); // resolve before seeding
    final prefs = container.read(soundPrefsProvider);

    expect(prefs.forEnv('desert').mus.on, false);
    expect(prefs.forEnv('desert').mus.vol, 0.3);
  });

  test('defaults to empty prefs when there is no profile', () async {
    final container = ProviderContainer(overrides: [
      myProfileProvider.overrideWith((ref) async => null),
    ]);
    addTearDown(container.dispose);
    await container.read(myProfileProvider.future);

    expect(container.read(soundPrefsProvider).byEnv, isEmpty);
  });

  test('setEnv updates the live state', () async {
    final container = ProviderContainer(overrides: [
      myProfileProvider.overrideWith((ref) async => null),
    ]);
    addTearDown(container.dispose);
    await container.read(myProfileProvider.future);
    container.read(soundPrefsProvider); // build

    container.read(soundPrefsProvider.notifier).setEnv(
          'space',
          const EnvSoundPref(amb: LayerPref(vol: 0.2)),
        );

    expect(container.read(soundPrefsProvider).forEnv('space').amb.vol, 0.2);
  });

  test('setEnv persists to the repository, debounced', () async {
    final repo = FakeProfileRepository();
    final container = ProviderContainer(overrides: [
      myProfileProvider.overrideWith((ref) async => null),
      profileRepositoryProvider.overrideWithValue(repo),
    ]);
    addTearDown(container.dispose);
    await container.read(myProfileProvider.future);
    container.read(soundPrefsProvider);

    container.read(soundPrefsProvider.notifier).setEnv(
          'desert',
          const EnvSoundPref(mus: LayerPref(on: false)),
        );

    expect(repo.savedSoundPrefs, isNull, reason: 'debounced — not saved yet');
    await Future.delayed(const Duration(milliseconds: 800));
    expect(repo.savedSoundPrefs, isNotNull, reason: 'saved after the debounce');
    final desert = repo.savedSoundPrefs!['desert'] as Map<String, dynamic>;
    expect((desert['mus'] as Map)['on'], false);
  });
}
