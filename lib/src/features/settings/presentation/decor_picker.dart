import 'dart:ui';

import 'package:dewdrop/decor/environment.dart';
import 'package:dewdrop/src/common/decor_choice.dart';
import 'package:dewdrop/src/features/ambient/application/ambient_providers.dart';
import 'package:dewdrop/src/features/profile/domain/sound_prefs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Glass bottom sheet to pick the ambiance (environment + variant), the render
/// mode (drawn / photo), and to fine-tune the selected decor's soundscape
/// (per-track on/off, volume, and per-secondary frequency). Calls [onChanged]
/// live as the user selects; sound edits apply live via [soundPrefsProvider].
class DecorPicker extends ConsumerStatefulWidget {
  const DecorPicker({
    super.key,
    required this.decor,
    required this.mode,
    required this.onChanged,
  });

  final String decor;
  final RenderMode mode;
  final void Function(String decor, RenderMode mode) onChanged;

  @override
  ConsumerState<DecorPicker> createState() => _DecorPickerState();
}

class _DecorPickerState extends ConsumerState<DecorPicker> {
  late (Environment, int) _sel = parseDecor(widget.decor);
  late RenderMode _mode = widget.mode;

  void _selectVariant(Environment env, int variant) {
    setState(() => _sel = (env, variant));
    widget.onChanged(encodeDecor(env, variant), _mode);
  }

  void _setMode(RenderMode m) {
    setState(() => _mode = m);
    widget.onChanged(encodeDecor(_sel.$1, _sel.$2), m);
  }

  void _update(String env, EnvSoundPref pref) =>
      ref.read(soundPrefsProvider.notifier).setEnv(env, pref);

  @override
  Widget build(BuildContext context) {
    final w = Colors.white;
    final media = MediaQuery.of(context);
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: Container(
          width: double.infinity,
          padding: EdgeInsets.fromLTRB(22, 14, 22, 16 + media.padding.bottom),
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
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Univers',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w500,
                      color: w,
                    ),
                  ),
                  _modeToggle(w),
                ],
              ),
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: media.size.height * 0.62,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final env in Environment.values) _envRow(env, w),
                      const SizedBox(height: 10),
                      _soundPanel(_sel.$1, w),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Sound customization panel for the selected decor ─────────────────────────

  Widget _soundPanel(Environment env, Color w) {
    final cfg = kDecorAudio[env.name];
    if (cfg == null) return const SizedBox.shrink();
    final pref = ref.watch(soundPrefsProvider).forEnv(env.name);
    final divider = Divider(color: w.withValues(alpha: 0.12), height: 22);

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: w.withValues(alpha: 0.05),
        border: Border.all(color: w.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.graphic_eq_rounded,
                size: 16,
                color: w.withValues(alpha: 0.7),
              ),
              const SizedBox(width: 8),
              Text(
                'Son · ${env.label}',
                style: TextStyle(
                  fontSize: 13,
                  letterSpacing: 0.4,
                  fontWeight: FontWeight.w600,
                  color: w.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          _track(
            w,
            label: 'Ambiance',
            on: pref.amb.on,
            vol: pref.amb.vol,
            onOn: (v) =>
                _update(env.name, pref.copyWith(amb: pref.amb.copyWith(on: v))),
            onVol: (v) => _update(
              env.name,
              pref.copyWith(amb: pref.amb.copyWith(vol: v)),
            ),
          ),
          _track(
            w,
            label: 'Musique',
            on: pref.mus.on,
            vol: pref.mus.vol,
            onOn: (v) =>
                _update(env.name, pref.copyWith(mus: pref.mus.copyWith(on: v))),
            onVol: (v) => _update(
              env.name,
              pref.copyWith(mus: pref.mus.copyWith(vol: v)),
            ),
          ),
          if (cfg.secondaries.isNotEmpty) divider,
          for (final entry in cfg.secondaries.entries)
            _secondaryTrack(env.name, entry.key, entry.value, pref, w),
        ],
      ),
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
    );
  }

  Widget _track(
    Color w, {
    required String label,
    required bool on,
    required double vol,
    required ValueChanged<bool> onOn,
    required ValueChanged<double> onVol,
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

  // ── Decor + variant + mode selection ─────────────────────────────────────────

  Widget _modeToggle(Color w) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: w.withValues(alpha: 0.08),
        border: Border.all(color: w.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _modeSeg(w, 'Dessin', RenderMode.drawn),
          _modeSeg(w, 'Photo', RenderMode.photo),
        ],
      ),
    );
  }

  Widget _modeSeg(Color w, String label, RenderMode m) {
    final sel = _mode == m;
    return GestureDetector(
      onTap: () => _setMode(m),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: sel ? w.withValues(alpha: 0.22) : Colors.transparent,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            color: w.withValues(alpha: sel ? 0.95 : 0.55),
            fontWeight: sel ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }

  Widget _envRow(Environment env, Color w) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(env.icon, size: 20, color: w.withValues(alpha: 0.85)),
          const SizedBox(width: 12),
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    env.label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      color: w.withValues(alpha: 0.92),
                    ),
                  ),
                ),
              ],
            ),
          ),
          for (var i = 0; i < env.variantCount; i++)
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: _chip(
                w,
                'V${i + 1}',
                _sel.$1 == env && _sel.$2 == i,
                () => _selectVariant(env, i),
              ),
            ),
        ],
      ),
    );
  }

  Widget _chip(Color w, String label, bool sel, VoidCallback onTap) =>
      GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(13),
            color: sel ? w.withValues(alpha: 0.24) : w.withValues(alpha: 0.06),
            border: Border.all(color: w.withValues(alpha: sel ? 0.5 : 0.16)),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              color: w.withValues(alpha: sel ? 0.95 : 0.55),
              fontWeight: sel ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      );
}
