import 'dart:async';
import 'dart:math';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The app's [SharedPreferences]. Overridden at the composition root (main.dart)
/// with the resolved instance so the rest of the app reads it synchronously.
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (_) => throw UnimplementedError('sharedPreferencesProvider must be overridden'),
);

/// Per-decor audio recipe. Each decor has **two independent layers** — a looping
/// [ambiance] bed and a looping [music] track — plus an optional pool of
/// [oneShots] (environmental events fired at random intervals over the ambiance,
/// e.g. whale calls, page turns, thunder). [music] may hold several variants;
/// one is picked at random each time the decor starts. Asset convention:
/// `assets/audio/<name>.ogg` for loops, `assets/audio/oneshot/<name>.ogg` for
/// one-shots. Loops are pre-equalized (music ≈ -18 LUFS, ambiance ≈ -28 LUFS) so
/// the ambiance always sits well below the music.
class DecorAudio {
  const DecorAudio({
    required this.ambiance,
    required this.music,
    this.oneShots = const [],
    this.minGap = const Duration(seconds: 30),
    this.maxGap = const Duration(seconds: 80),
    this.oneShotVolume = 0.5,
  });

  final String ambiance;
  final List<String> music;
  final List<String> oneShots;
  final Duration minGap;
  final Duration maxGap;
  final double oneShotVolume;
}

const List<String> _whales = [
  'underwater_whale_01', 'underwater_whale_02', 'underwater_whale_03',
  'underwater_whale_04', 'underwater_whale_05', 'underwater_whale_06',
  'underwater_whale_07', 'underwater_whale_08', 'underwater_whale_09',
  'underwater_whale_10', 'underwater_whale_11', 'underwater_whale_12',
  'underwater_whale_13',
];

/// Audio recipe per [Environment.name].
const Map<String, DecorAudio> _audio = {
  'space': DecorAudio(ambiance: 'space_amb', music: ['space_mus']),
  'underwater': DecorAudio(
    ambiance: 'underwater_amb',
    music: ['underwater_mus'],
    oneShots: _whales,
    minGap: Duration(seconds: 18),
    maxGap: Duration(seconds: 45),
    oneShotVolume: 0.7,
  ),
  'forest': DecorAudio(ambiance: 'forest_amb', music: ['forest_mus']),
  'beach': DecorAudio(ambiance: 'beach_amb', music: ['beach_mus']),
  'library': DecorAudio(
    ambiance: 'library_amb',
    music: ['library_mus'],
    oneShots: ['library_page_1', 'library_purr_1', 'library_purr_2', 'library_purr_3'],
    minGap: Duration(seconds: 12),
    maxGap: Duration(seconds: 30),
    oneShotVolume: 0.5,
  ),
  'mountain': DecorAudio(
    ambiance: 'mountain_amb',
    music: ['mountain_mus'],
    oneShots: ['mountain_pigeon_1'],
    minGap: Duration(seconds: 22),
    maxGap: Duration(seconds: 55),
    oneShotVolume: 0.4,
  ),
  'desert': DecorAudio(
    ambiance: 'desert_amb',
    music: ['desert_mus'],
    oneShots: [
      'desert_thunder_1', 'desert_thunder_2', 'desert_thunder_3',
      'desert_tumble_1', 'desert_tumble_2', 'desert_tumble_3',
    ],
    minGap: Duration(seconds: 14),
    maxGap: Duration(seconds: 40),
    oneShotVolume: 0.6,
  ),
  'aurora': DecorAudio(
    ambiance: 'aurora_amb',
    music: ['aurora_mus_a', 'aurora_mus_b'],
    oneShots: ['aurora_crack_1', 'aurora_crack_2', 'aurora_crack_3', 'aurora_shimmer_1'],
    minGap: Duration(seconds: 25),
    maxGap: Duration(seconds: 70),
    oneShotVolume: 0.5,
  ),
};

/// Immutable on/off state of the soundscape. [master] is the home-screen mute
/// (silences everything); [ambiance] and [music] are the two independent toggles
/// from Settings. A layer plays only when [master] **and** its own flag are on.
class SoundscapeState {
  const SoundscapeState({
    required this.master,
    required this.ambiance,
    required this.music,
  });

  final bool master;
  final bool ambiance;
  final bool music;

  SoundscapeState copyWith({bool? master, bool? ambiance, bool? music}) =>
      SoundscapeState(
        master: master ?? this.master,
        ambiance: ambiance ?? this.ambiance,
        music: music ?? this.music,
      );
}

const _kMaster = 'snd_master';
const _kAmbiance = 'snd_ambiance';
const _kMusic = 'snd_music';

/// Drives the per-decor soundscape: an ambiance loop, a music loop and a random
/// one-shot scheduler, reconciled against [SoundscapeState] and the current
/// decor. Mute uses pause/resume (audioplayers does not reliably restart a
/// *stopped* same-source player); switching decor issues a fresh `play` with a
/// new source, which is reliable.
class SoundscapeNotifier extends Notifier<SoundscapeState> {
  final Random _rng = Random();
  AudioPlayer? _amb;
  AudioPlayer? _mus;
  AudioPlayer? _shot;

  String? _env; // current decor environment name
  String? _ambLoaded; // env whose ambiance is loaded in [_amb]
  String? _musAsset; // music variant chosen for [_env]
  String? _musLoaded; // music asset loaded in [_mus]
  Timer? _shotTimer;

  @override
  SoundscapeState build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    _amb = AudioPlayer()..setReleaseMode(ReleaseMode.loop);
    _mus = AudioPlayer()..setReleaseMode(ReleaseMode.loop);
    _shot = AudioPlayer()..setReleaseMode(ReleaseMode.stop);
    ref.onDispose(() {
      _shotTimer?.cancel();
      unawaited(_amb?.dispose());
      unawaited(_mus?.dispose());
      unawaited(_shot?.dispose());
      _amb = _mus = _shot = null;
    });
    return SoundscapeState(
      master: prefs.getBool(_kMaster) ?? true,
      ambiance: prefs.getBool(_kAmbiance) ?? true,
      music: prefs.getBool(_kMusic) ?? true,
    );
  }

  DecorAudio? get _cfg => _env == null ? null : _audio[_env];

  /// Switches the soundscape to [environment] (e.g. 'forest'). Picks a fresh
  /// random music variant and restarts the one-shot scheduler.
  Future<void> setEnvironment(String environment) async {
    _env = environment;
    final cfg = _audio[environment];
    _musAsset = (cfg != null && cfg.music.isNotEmpty)
        ? cfg.music[_rng.nextInt(cfg.music.length)]
        : null;
    await _apply(freshMusic: true, restartShots: true);
  }

  /// Home-screen master mute: silences (or restores) every layer.
  Future<void> toggleMaster() async {
    state = state.copyWith(master: !state.master);
    await ref.read(sharedPreferencesProvider).setBool(_kMaster, state.master);
    await _apply(restartShots: true);
  }

  /// Settings toggle for the ambiance layer (bed + one-shots).
  Future<void> setAmbiance(bool value) async {
    state = state.copyWith(ambiance: value);
    await ref.read(sharedPreferencesProvider).setBool(_kAmbiance, value);
    await _apply(restartShots: true);
  }

  /// Settings toggle for the music layer.
  Future<void> setMusic(bool value) async {
    state = state.copyWith(music: value);
    await ref.read(sharedPreferencesProvider).setBool(_kMusic, value);
    await _apply();
  }

  /// Lifecycle: app backgrounded — pause everything (keep state).
  Future<void> pauseAll() async {
    _shotTimer?.cancel();
    await _amb?.pause();
    await _mus?.pause();
  }

  /// Lifecycle: app resumed — restore the layers that should be playing.
  Future<void> resumeAll() async => _apply(restartShots: true);

  /// Reconciles the players + scheduler against [state] and [_env].
  Future<void> _apply({bool freshMusic = false, bool restartShots = false}) async {
    final cfg = _cfg;
    final wantAmb = state.master && state.ambiance && cfg != null;
    final wantMus = state.master && state.music && _musAsset != null;

    if (wantAmb) {
      if (_ambLoaded != _env) {
        await _amb?.setVolume(1.0);
        await _amb?.play(AssetSource('audio/${cfg.ambiance}.ogg'));
        _ambLoaded = _env;
      } else {
        await _amb?.resume();
      }
    } else {
      await _amb?.pause();
    }

    if (wantMus) {
      if (freshMusic || _musLoaded != _musAsset) {
        await _mus?.setVolume(1.0);
        await _mus?.play(AssetSource('audio/$_musAsset.ogg'));
        _musLoaded = _musAsset;
      } else {
        await _mus?.resume();
      }
    } else {
      await _mus?.pause();
    }

    if (state.master && state.ambiance && restartShots) {
      _scheduleNextShot();
    } else if (!(state.master && state.ambiance)) {
      _shotTimer?.cancel();
    }
  }

  /// Schedules the next one-shot at a random gap; reschedules itself after firing.
  void _scheduleNextShot() {
    _shotTimer?.cancel();
    final cfg = _cfg;
    if (cfg == null || cfg.oneShots.isEmpty) return;
    if (!(state.master && state.ambiance)) return;
    final span = cfg.maxGap.inMilliseconds - cfg.minGap.inMilliseconds;
    final gap = cfg.minGap.inMilliseconds + (span <= 0 ? 0 : _rng.nextInt(span));
    _shotTimer = Timer(Duration(milliseconds: gap), () async {
      final c = _cfg;
      if (c != null && c.oneShots.isNotEmpty && state.master && state.ambiance) {
        final clip = c.oneShots[_rng.nextInt(c.oneShots.length)];
        try {
          await _shot?.play(
            AssetSource('audio/oneshot/$clip.ogg'),
            volume: c.oneShotVolume,
          );
        } on Exception catch (_) {
          // A failed one-shot must never break the loop.
        }
      }
      _scheduleNextShot();
    });
  }
}

final soundscapeProvider =
    NotifierProvider<SoundscapeNotifier, SoundscapeState>(SoundscapeNotifier.new);
