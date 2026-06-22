import 'dart:async';
import 'dart:math';

import 'package:audioplayers/audioplayers.dart';
import 'package:dewdrop/src/features/profile/application/profile_providers.dart';
import 'package:dewdrop/src/features/profile/domain/sound_prefs.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The app's [SharedPreferences]. Overridden at the composition root (main.dart)
/// with the resolved instance so the rest of the app reads it synchronously.
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (_) =>
      throw UnimplementedError('sharedPreferencesProvider must be overridden'),
);

/// A secondary (one-shot) category for a decor — fired at random intervals over
/// the ambiance. [clips] is the random pool (one is picked per firing). The
/// [volume]/[minGap]/[maxGap] are the engine defaults; the user can override
/// volume, on/off and frequency per category (see [SoundPrefs]).
class SecondaryCat {
  const SecondaryCat({
    required this.label,
    required this.clips,
    this.volume = 0.5,
    this.minGap = const Duration(seconds: 30),
    this.maxGap = const Duration(seconds: 80),
  });

  final String label;
  final List<String> clips;
  final double volume;
  final Duration minGap;
  final Duration maxGap;
}

/// Per-decor audio recipe: a looping ambiance bed, a looping music track (one or
/// more variants, picked at random) and named secondary categories. Loops are
/// pre-equalized (music ≈ -18 LUFS, ambiance ≈ -28 LUFS). Asset convention:
/// `assets/audio/<name>.ogg` (loops), `assets/audio/oneshot/<name>.ogg` (shots).
class DecorAudio {
  const DecorAudio({
    required this.ambiance,
    required this.music,
    this.secondaries = const {},
  });

  final String ambiance;
  final List<String> music;
  final Map<String, SecondaryCat> secondaries;
}

const List<String> _whales = [
  'underwater_whale_01',
  'underwater_whale_02',
  'underwater_whale_03',
  'underwater_whale_04',
  'underwater_whale_05',
  'underwater_whale_06',
  'underwater_whale_07',
  'underwater_whale_08',
  'underwater_whale_09',
  'underwater_whale_10',
  'underwater_whale_11',
  'underwater_whale_12',
  'underwater_whale_13',
];

/// Audio recipe per [Environment.name]. Exposed so the decor picker can list a
/// decor's adjustable tracks.
const Map<String, DecorAudio> kDecorAudio = {
  'space': DecorAudio(ambiance: 'space_amb', music: ['space_mus']),
  'underwater': DecorAudio(
    ambiance: 'underwater_amb',
    music: ['underwater_mus'],
    secondaries: {
      'whales': SecondaryCat(
        label: 'Baleines',
        clips: _whales,
        volume: 0.7,
        minGap: Duration(seconds: 18),
        maxGap: Duration(seconds: 45),
      ),
    },
  ),
  'forest': DecorAudio(ambiance: 'forest_amb', music: ['forest_mus']),
  'beach': DecorAudio(ambiance: 'beach_amb', music: ['beach_mus']),
  'library': DecorAudio(
    ambiance: 'library_amb',
    music: ['library_mus'],
    secondaries: {
      'pages': SecondaryCat(
        label: 'Pages',
        clips: ['library_page_1'],
        volume: 0.5,
        minGap: Duration(seconds: 18),
        maxGap: Duration(seconds: 42),
      ),
      'purrs': SecondaryCat(
        label: 'Ronron du chat',
        clips: ['library_purr_1', 'library_purr_2', 'library_purr_3'],
        volume: 0.5,
        minGap: Duration(seconds: 25),
        maxGap: Duration(seconds: 60),
      ),
    },
  ),
  'mountain': DecorAudio(
    ambiance: 'mountain_amb',
    music: ['mountain_mus'],
    secondaries: {
      'pigeon': SecondaryCat(
        label: 'Pigeon ramier',
        clips: ['mountain_pigeon_1'],
        volume: 0.4,
        minGap: Duration(seconds: 22),
        maxGap: Duration(seconds: 55),
      ),
    },
  ),
  'desert': DecorAudio(
    ambiance: 'desert_amb',
    music: ['desert_mus'],
    secondaries: {
      'thunder': SecondaryCat(
        label: 'Tonnerre',
        clips: ['desert_thunder_1', 'desert_thunder_2', 'desert_thunder_3'],
        volume: 0.6,
        minGap: Duration(seconds: 22),
        maxGap: Duration(seconds: 55),
      ),
      'tumbleweed': SecondaryCat(
        label: 'Virevoltants',
        clips: ['desert_tumble_1', 'desert_tumble_2', 'desert_tumble_3'],
        volume: 0.6,
        minGap: Duration(seconds: 16),
        maxGap: Duration(seconds: 40),
      ),
    },
  ),
  'aurora': DecorAudio(
    ambiance: 'aurora_amb',
    music: ['aurora_mus_a', 'aurora_mus_b'],
    secondaries: {
      'cracks': SecondaryCat(
        label: 'Glace qui craque',
        clips: ['aurora_crack_1', 'aurora_crack_2', 'aurora_crack_3'],
        volume: 0.55,
        minGap: Duration(seconds: 25),
        maxGap: Duration(seconds: 70),
      ),
      'shimmer': SecondaryCat(
        label: 'Scintillement',
        clips: ['aurora_shimmer_1'],
        volume: 0.35,
        minGap: Duration(seconds: 40),
        maxGap: Duration(seconds: 90),
      ),
    },
  ),
  'fields': DecorAudio(
    ambiance: 'fields_amb',
    music: ['fields_mus'],
    secondaries: {
      'bees': SecondaryCat(
        label: 'Abeille',
        clips: ['fields_bee_1', 'fields_bee_2'],
        volume: 0.2, // very low by default — a bee passing far off
        minGap: Duration(seconds: 22),
        maxGap: Duration(seconds: 55),
      ),
    },
  ),
};

const _kMaster = 'snd_master';

/// Maps a 0..1 frequency knob to a multiplier on a category's default gap range.
/// 0.5 = default, 1 = ~2.3× more frequent, 0 = ~2.3× rarer.
double _freqFactor(double freq) => pow(2, (0.5 - freq) * 2.4).toDouble();

/// Drives the per-decor soundscape: an ambiance loop, a music loop and one timer
/// per secondary category, reconciled against the home **master** mute
/// (`state`) and the per-decor [SoundPrefs] (on/off, volume, frequency). Reacts
/// live to pref edits. Mute uses pause/resume; switching decor issues a fresh
/// `play` with a new source (reliable with audioplayers).
class SoundscapeNotifier extends Notifier<bool> {
  final Random _rng = Random();
  AudioPlayer? _amb;
  AudioPlayer? _mus;
  final List<AudioPlayer> _shots = [];
  int _shotIdx = 0;

  String? _env;
  String? _ambLoaded;
  String? _musAsset;
  String? _musLoaded;
  final Map<String, Timer> _catTimers = {};
  bool _disposed = false;

  @override
  bool build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    // If build() ever re-runs (a watched dep changes), tear down the previous
    // players/timers first so they don't leak.
    _teardown();
    _disposed = false;
    _amb = AudioPlayer();
    unawaited(_amb!.setReleaseMode(ReleaseMode.loop));
    _mus = AudioPlayer();
    unawaited(_mus!.setReleaseMode(ReleaseMode.loop));
    for (var i = 0; i < 4; i++) {
      final shot = AudioPlayer();
      unawaited(shot.setReleaseMode(ReleaseMode.stop));
      _shots.add(shot);
    }
    // Live-react to per-decor customization edits.
    ref.listen(soundPrefsProvider, (_, _) => unawaited(_apply()));
    ref.onDispose(_teardown);
    return prefs.getBool(_kMaster) ?? true;
  }

  /// Cancels timers and disposes players. Sets [_disposed] first so any in-flight
  /// `_apply()` / one-shot reschedule bails out instead of touching dead players.
  void _teardown() {
    _disposed = true;
    for (final t in _catTimers.values) {
      t.cancel();
    }
    _catTimers.clear();
    unawaited(_amb?.dispose());
    unawaited(_mus?.dispose());
    for (final p in _shots) {
      unawaited(p.dispose());
    }
    _amb = _mus = null;
    _shots.clear();
    _shotIdx = 0;
  }

  DecorAudio? get _cfg => _env == null ? null : kDecorAudio[_env];

  EnvSoundPref get _pref => _env == null
      ? const EnvSoundPref()
      : ref.read(soundPrefsProvider).forEnv(_env!);

  /// Switches the soundscape to [environment] (e.g. 'forest'). Picks a fresh
  /// random music variant and restarts the secondary schedulers.
  Future<void> setEnvironment(String environment) async {
    _env = environment;
    final cfg = kDecorAudio[environment];
    _musAsset = (cfg != null && cfg.music.isNotEmpty)
        ? cfg.music[_rng.nextInt(cfg.music.length)]
        : null;
    await _apply(freshMusic: true);
  }

  /// Home-screen master mute: silences (or restores) everything.
  Future<void> toggleMaster() async {
    state = !state;
    await ref.read(sharedPreferencesProvider).setBool(_kMaster, state);
    await _apply();
  }

  /// Lifecycle: app backgrounded — pause everything (keep state).
  Future<void> pauseAll() async {
    for (final t in _catTimers.values) {
      t.cancel();
    }
    _catTimers.clear();
    await _amb?.pause();
    await _mus?.pause();
  }

  /// Lifecycle: app resumed — restore the layers that should play.
  Future<void> resumeAll() async => _apply();

  // Serialize + coalesce all reconciliations. `setEnvironment`, `toggleMaster`,
  // the prefs `ref.listen` and lifecycle resumes all call _apply, often in rapid
  // bursts (slider drags). Running their bodies concurrently let an old `play()`
  // finish *after* a newer `pause()`, leaving a loop stuck on — and worse, at
  // full volume (the "couldn't stop the sound, had to force-quit" bug). So only
  // one reconciliation runs at a time, start to finish; any requests that arrive
  // while one is running collapse into a single trailing run with the latest
  // prefs.
  bool _applyRunning = false;
  bool _applyPending = false;
  bool _pendingFreshMusic = false;

  /// Requests a reconciliation of the players + per-category timers against
  /// [state], [_env] and the current [SoundPrefs]. Coalesced; safe to spam.
  Future<void> _apply({bool freshMusic = false}) async {
    _applyPending = true;
    if (freshMusic) _pendingFreshMusic = true;
    if (_applyRunning) return; // the in-flight run will pick up this request
    _applyRunning = true;
    try {
      while (_applyPending && !_disposed) {
        _applyPending = false;
        final fm = _pendingFreshMusic;
        _pendingFreshMusic = false;
        await _applyInner(freshMusic: fm);
      }
    } finally {
      _applyRunning = false;
    }
  }

  Future<void> _applyInner({required bool freshMusic}) async {
    final cfg = _cfg;
    final pref = _pref;
    final wantAmb = state && cfg != null && pref.amb.on;
    final wantMus = state && _musAsset != null && pref.mus.on;
    final ambVol = pref.amb.vol.clamp(0.0, 1.0);
    final musVol = pref.mus.vol.clamp(0.0, 1.0);

    if (wantAmb) {
      if (_ambLoaded != _env) {
        // Start the loop AT the target volume so it never blares at the default
        // 1.0 before a follow-up setVolume.
        await _amb?.play(
          AssetSource('audio/${cfg.ambiance}.ogg'),
          volume: ambVol,
        );
        _ambLoaded = _env;
      } else {
        await _amb?.resume();
        await _amb?.setVolume(ambVol);
      }
    } else {
      await _amb?.pause();
    }
    if (_disposed) return;

    if (wantMus) {
      if (freshMusic || _musLoaded != _musAsset) {
        await _mus?.play(AssetSource('audio/$_musAsset.ogg'), volume: musVol);
        _musLoaded = _musAsset;
      } else {
        await _mus?.resume();
        await _mus?.setVolume(musVol);
      }
    } else {
      await _mus?.pause();
    }
    if (_disposed) return;

    _rescheduleSecondaries();
  }

  void _rescheduleSecondaries() {
    for (final t in _catTimers.values) {
      t.cancel();
    }
    _catTimers.clear();
    final cfg = _cfg;
    if (cfg == null || !state || _disposed) return;
    final pref = _pref;
    for (final entry in cfg.secondaries.entries) {
      final sp = pref.sec[entry.key];
      if (!(sp?.on ?? true)) continue; // category muted by the user
      _scheduleCat(entry.key, entry.value);
    }
  }

  void _scheduleCat(String key, SecondaryCat cat) {
    final sp = _pref.sec[key];
    final factor = _freqFactor(sp?.freq ?? 0.5);
    final minMs = (cat.minGap.inMilliseconds * factor).round();
    final maxMs = (cat.maxGap.inMilliseconds * factor).round();
    final gap = minMs + (maxMs > minMs ? _rng.nextInt(maxMs - minMs) : 0);
    _catTimers[key] = Timer(Duration(milliseconds: gap), () async {
      if (_disposed) return;
      final cfg = _cfg;
      final cat2 = cfg?.secondaries[key];
      if (cat2 != null && state) {
        final p = _pref.sec[key];
        if ((p?.on ?? true) && cat2.clips.isNotEmpty && _shots.isNotEmpty) {
          final clip = cat2.clips[_rng.nextInt(cat2.clips.length)];
          final vol = (p?.vol ?? cat2.volume).clamp(0.0, 1.0);
          final player = _shots[_shotIdx];
          _shotIdx = (_shotIdx + 1) % _shots.length;
          try {
            await player.play(
              AssetSource('audio/oneshot/$clip.ogg'),
              volume: vol,
            );
          } on Exception catch (_) {
            // A failed one-shot must never break the schedule.
          }
        }
        // Reschedule only if a dispose didn't land during the await above —
        // otherwise we'd add an orphaned Timer after onDispose cancelled them.
        if (!_disposed) _scheduleCat(key, cat2);
      }
    });
  }
}

final soundscapeProvider = NotifierProvider<SoundscapeNotifier, bool>(
  SoundscapeNotifier.new,
);

/// The live, editable per-decor soundscape customization. Seeded once from the
/// user's profile, mutated instantly by the decor picker (so changes apply
/// live), and persisted to Supabase (debounced) so it syncs across devices.
class SoundPrefsNotifier extends Notifier<SoundPrefs> {
  Timer? _save;

  @override
  SoundPrefs build() {
    ref.onDispose(() => _save?.cancel());
    // Seeded once via `read` (not `watch`): this is read only after HomeGate has
    // resolved `myProfileProvider`, so `.value` is the loaded profile. After
    // that, edits flow through `setEnv` (live) and persist to the profile, so we
    // intentionally don't re-seed when the profile provider updates.
    return ref.read(myProfileProvider).value?.soundPrefs ?? SoundPrefs.empty;
  }

  /// Replaces the prefs for [env] and schedules a debounced sync.
  void setEnv(String env, EnvSoundPref pref) {
    state = state.withEnv(env, pref);
    _scheduleSave();
  }

  void _scheduleSave() {
    _save?.cancel();
    _save = Timer(const Duration(milliseconds: 700), () {
      unawaited(
        ref.read(profileRepositoryProvider).updateSoundPrefs(state.toJson()),
      );
    });
  }
}

final soundPrefsProvider = NotifierProvider<SoundPrefsNotifier, SoundPrefs>(
  SoundPrefsNotifier.new,
);
