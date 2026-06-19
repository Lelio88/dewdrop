import 'dart:async';
import 'dart:ui';

import 'package:dewdrop/decor/environment.dart';
import 'package:dewdrop/src/features/ambient/application/ambient_providers.dart';
import 'package:dewdrop/src/features/ambient/application/sound_preview.dart';
import 'package:dewdrop/src/features/profile/domain/sound_prefs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Opens the glass « Ambiance & musique » sheet for [env] — per-track on/off,
/// volume, and per-secondary frequency, all applied live via [soundPrefsProvider].
///
/// Extracted from the former decor picker so the full-screen decor stories
/// ([DecorStories]) can reuse it behind a 🔊 button instead of cramming the sound
/// controls into the world-selection flow.
void showSoundSheet(BuildContext context, Environment env) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.3),
    isScrollControlled: true,
    builder: (_) => SoundControls(env: env),
  );
}

/// The sound-customization panel for one environment. State lives entirely in
/// the shared [soundPrefsProvider], so this widget is safe to embed in a sheet
/// or a settings page without owning any local state.
class SoundControls extends ConsumerStatefulWidget {
  const SoundControls({super.key, required this.env});

  final Environment env;

  @override
  ConsumerState<SoundControls> createState() => _SoundControlsState();
}

class _SoundControlsState extends ConsumerState<SoundControls> {
  void _update(String env, EnvSoundPref pref) =>
      ref.read(soundPrefsProvider.notifier).setEnv(env, pref);

  /// Play a short preview of [asset] (separate player — never touches the live
  /// soundscape) so the user can hear a track before toggling it.
  void _preview(String asset) =>
      unawaited(ref.read(soundPreviewProvider).play(asset));

  @override
  Widget build(BuildContext context) {
    final w = Colors.white;
    final media = MediaQuery.of(context);
    final env = widget.env;
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: Container(
          width: double.infinity,
          constraints: BoxConstraints(maxHeight: media.size.height * 0.82),
          padding: EdgeInsets.fromLTRB(
            22,
            14,
            22,
            18 + media.viewPadding.bottom,
          ),
          decoration: BoxDecoration(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
            color: w.withValues(alpha: 0.10),
            border: Border.all(color: w.withValues(alpha: 0.18)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: w.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Icon(
                    Icons.graphic_eq_rounded,
                    size: 18,
                    color: w.withValues(alpha: 0.8),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Ambiance & musique · ${env.label}',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w500,
                      color: w,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Flexible(child: SingleChildScrollView(child: _panel(env, w))),
            ],
          ),
        ),
      ),
    );
  }

  Widget _panel(Environment env, Color w) {
    final cfg = kDecorAudio[env.name];
    if (cfg == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Text(
          'Pas de son pour cet univers.',
          style: TextStyle(color: w.withValues(alpha: 0.5)),
        ),
      );
    }
    final pref = ref.watch(soundPrefsProvider).forEnv(env.name);
    final divider = Divider(color: w.withValues(alpha: 0.12), height: 22);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _track(
          w,
          label: 'Ambiance',
          on: pref.amb.on,
          vol: pref.amb.vol,
          onOn: (v) =>
              _update(env.name, pref.copyWith(amb: pref.amb.copyWith(on: v))),
          onVol: (v) =>
              _update(env.name, pref.copyWith(amb: pref.amb.copyWith(vol: v))),
          onPreview: () => _preview('audio/${cfg.ambiance}.ogg'),
        ),
        _track(
          w,
          label: 'Musique',
          on: pref.mus.on,
          vol: pref.mus.vol,
          onOn: (v) =>
              _update(env.name, pref.copyWith(mus: pref.mus.copyWith(on: v))),
          onVol: (v) =>
              _update(env.name, pref.copyWith(mus: pref.mus.copyWith(vol: v))),
          onPreview: cfg.music.isNotEmpty
              ? () => _preview('audio/${cfg.music.first}.ogg')
              : null,
        ),
        if (cfg.secondaries.isNotEmpty) divider,
        for (final entry in cfg.secondaries.entries)
          _secondaryTrack(env.name, entry.key, entry.value, pref, w),
      ],
    );
  }

  Widget _secondaryTrack(
    String env,
    String key,
    SecondaryCat cat,
    EnvSoundPref pref,
    Color w,
  ) {
    final sp = pref.sec[key] ?? SecondaryPref(vol: cat.volume);
    return _track(
      w,
      label: cat.label,
      on: sp.on,
      vol: sp.vol,
      freq: sp.freq,
      onOn: (v) => _update(env, pref.withSecondary(key, sp.copyWith(on: v))),
      onVol: (v) => _update(env, pref.withSecondary(key, sp.copyWith(vol: v))),
      onFreq: (v) =>
          _update(env, pref.withSecondary(key, sp.copyWith(freq: v))),
      onPreview: cat.clips.isNotEmpty
          ? () => _preview('audio/oneshot/${cat.clips.first}.ogg')
          : null,
    );
  }

  Widget _track(
    Color w, {
    required String label,
    required bool on,
    required double vol,
    required ValueChanged<bool> onOn,
    required ValueChanged<double> onVol,
    VoidCallback? onPreview,
    double? freq,
    ValueChanged<double>? onFreq,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 13.5,
                    color: w.withValues(alpha: on ? 0.92 : 0.45),
                  ),
                ),
              ),
              SizedBox(
                height: 26,
                child: Transform.scale(
                  scale: 0.8,
                  child: Switch(
                    value: on,
                    onChanged: onOn,
                    activeThumbColor: w,
                    activeTrackColor: w.withValues(alpha: 0.4),
                  ),
                ),
              ),
              if (onPreview != null)
                GestureDetector(
                  onTap: onPreview,
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Icon(
                      Icons.play_circle_outline_rounded,
                      size: 24,
                      color: w.withValues(alpha: 0.6),
                    ),
                  ),
                ),
            ],
          ),
          _slider(w, Icons.volume_up_rounded, vol, on ? onVol : null),
          if (freq != null)
            _slider(w, Icons.timer_outlined, freq, on ? onFreq : null),
        ],
      ),
    );
  }

  Widget _slider(
    Color w,
    IconData icon,
    double value,
    ValueChanged<double>? onChanged,
  ) {
    return Row(
      children: [
        Icon(
          icon,
          size: 15,
          color: w.withValues(alpha: onChanged == null ? 0.25 : 0.5),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderThemeData(
              trackHeight: 2.5,
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              activeTrackColor: w.withValues(alpha: 0.8),
              inactiveTrackColor: w.withValues(alpha: 0.16),
              thumbColor: w,
            ),
            child: Slider(value: value.clamp(0.0, 1.0), onChanged: onChanged),
          ),
        ),
      ],
    );
  }
}
