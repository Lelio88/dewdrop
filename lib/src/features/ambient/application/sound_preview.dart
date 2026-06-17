import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// One-off audio previewer for the sound settings: tap a track's ▶ to hear it.
///
/// Uses its OWN player, separate from the live [SoundscapeNotifier], so a preview
/// never disturbs the running soundscape; long loop beds are cut off after a few
/// seconds. It mixes over the ambiance thanks to the global AudioContext.
///
/// Example: `ref.read(soundPreviewProvider).play('audio/forest_amb.ogg')`.
class SoundPreview {
  AudioPlayer? _player;
  Timer? _stop;

  /// Play [asset] (e.g. 'audio/forest_amb.ogg') as a short preview, replacing any
  /// preview already playing. Loop beds are cut off after [maxPreview].
  Future<void> play(
    String asset, {
    double volume = 0.85,
    Duration maxPreview = const Duration(seconds: 4),
  }) async {
    _stop?.cancel();
    if (_player == null) {
      _player = AudioPlayer();
      unawaited(_player!.setReleaseMode(ReleaseMode.stop));
    }
    final player = _player!;
    await player.stop();
    await player.play(AssetSource(asset), volume: volume.clamp(0.0, 1.0));
    _stop = Timer(maxPreview, () => unawaited(player.stop()));
  }

  void dispose() {
    _stop?.cancel();
    unawaited(_player?.dispose());
  }
}

/// Lives for the app session; disposed with the container.
final soundPreviewProvider = Provider<SoundPreview>((ref) {
  final preview = SoundPreview();
  ref.onDispose(preview.dispose);
  return preview;
});
