import 'dart:async';

import 'package:dewdrop/src/common/glass.dart';
import 'package:dewdrop/src/features/profile/application/profile_providers.dart';
import 'package:dewdrop/src/features/thoughts/domain/thought_preset.dart';
import 'package:dewdrop/src/features/thoughts/domain/thought_style.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// "Personnalisation" — the style of the thoughts this user sends: a
/// **slot-machine** picker (3 reels: leading emoji · phrase · trailing emoji)
/// with a live preview of the notification the recipient will receive, plus a
/// list of **saved presets** (named trios, ≤5) re-applied in one tap. Persisted
/// to the profile (debounced for the reels). The anonymity default lives in
/// Réglages, not here.
class ThoughtSettingsScreen extends ConsumerStatefulWidget {
  const ThoughtSettingsScreen({super.key});

  @override
  ConsumerState<ThoughtSettingsScreen> createState() =>
      _ThoughtSettingsScreenState();
}

class _ThoughtSettingsScreenState extends ConsumerState<ThoughtSettingsScreen> {
  late int _lead; // index into kThoughtEmojis
  late int _body; // index into kThoughtBodies
  late int _tail; // index into kThoughtEmojis
  late String _name; // the recipient sees this (the sender's name)
  List<ThoughtPreset> _presets = const []; // saved trios (≤ kMaxThoughtPresets)

  late final FixedExtentScrollController _leadCtl;
  late final FixedExtentScrollController _bodyCtl;
  late final FixedExtentScrollController _tailCtl;
  Timer? _save;

  @override
  void initState() {
    super.initState();
    final p = ref.read(myProfileProvider).value;
    final style = p?.thoughtStyle ?? const ThoughtStyle();
    _lead = kThoughtEmojis
        .indexOf(style.lead)
        .clamp(0, kThoughtEmojis.length - 1);
    _body = kThoughtBodies
        .indexOf(style.body)
        .clamp(0, kThoughtBodies.length - 1);
    _tail = kThoughtEmojis
        .indexOf(style.tail)
        .clamp(0, kThoughtEmojis.length - 1);
    _name = (p?.displayName?.isNotEmpty == true)
        ? p!.displayName!
        : (p?.handle != null ? '@${p!.handle}' : 'Toi');
    _presets = List<ThoughtPreset>.of(p?.thoughtPresets ?? const []);
    _leadCtl = FixedExtentScrollController(initialItem: _lead);
    _bodyCtl = FixedExtentScrollController(initialItem: _body);
    _tailCtl = FixedExtentScrollController(initialItem: _tail);
  }

  @override
  void dispose() {
    _save?.cancel();
    _leadCtl.dispose();
    _bodyCtl.dispose();
    _tailCtl.dispose();
    super.dispose();
  }

  ThoughtStyle get _style => ThoughtStyle(
    lead: kThoughtEmojis[_lead],
    body: kThoughtBodies[_body],
    tail: kThoughtEmojis[_tail],
  );

  void _onReel(void Function() apply) {
    setState(apply);
    _save?.cancel();
    _save = Timer(const Duration(milliseconds: 500), _persistStyle);
  }

  /// Persists the current style. Logs (never swallows) a failed save, and skips
  /// the invalidate if the write failed or the screen is already gone.
  Future<void> _persistStyle() async {
    try {
      await ref
          .read(profileRepositoryProvider)
          .updateThoughtStyle(_style.toJson());
    } on Exception catch (e) {
      debugPrint('thought_style save failed: $e');
      return;
    }
    if (!mounted) return;
    ref.invalidate(myProfileProvider);
  }

  /// True when [p]'s trio is the one currently selected on the reels.
  bool _isActive(ThoughtPreset p) =>
      p.style.lead == _style.lead &&
      p.style.body == _style.body &&
      p.style.tail == _style.tail;

  /// Spins the reels to [p]'s trio and persists it as the active style. The
  /// reel animation re-fires `onSelectedItemChanged`, which keeps `_lead/_body/
  /// _tail` in sync and schedules the debounced save below.
  void _applyPreset(ThoughtPreset p) {
    final lead = kThoughtEmojis
        .indexOf(p.style.lead)
        .clamp(0, kThoughtEmojis.length - 1);
    final body = kThoughtBodies
        .indexOf(p.style.body)
        .clamp(0, kThoughtBodies.length - 1);
    final tail = kThoughtEmojis
        .indexOf(p.style.tail)
        .clamp(0, kThoughtEmojis.length - 1);
    setState(() {
      _lead = lead;
      _body = body;
      _tail = tail;
    });
    const dur = Duration(milliseconds: 350);
    const curve = Curves.easeOutCubic;
    _leadCtl.animateToItem(lead, duration: dur, curve: curve);
    _bodyCtl.animateToItem(body, duration: dur, curve: curve);
    _tailCtl.animateToItem(tail, duration: dur, curve: curve);
    _save?.cancel();
    _save = Timer(const Duration(milliseconds: 500), _persistStyle);
  }

  /// Saves the current trio as a new preset. Refuses (and alerts) when the user
  /// already has [kMaxThoughtPresets]; otherwise prompts for a name first.
  Future<void> _onSavePreset() async {
    if (_presets.length >= kMaxThoughtPresets) {
      await _showFullAlert();
      return;
    }
    final name = await _promptName();
    if (name == null || !mounted) return;
    setState(
      () => _presets = [..._presets, ThoughtPreset(name: name, style: _style)],
    );
    await _persistPresets();
  }

  Future<void> _deletePreset(ThoughtPreset p) async {
    setState(() => _presets = _presets.where((e) => !identical(e, p)).toList());
    await _persistPresets();
  }

  Future<void> _showFullAlert() => showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Maximum atteint'),
      content: const Text(
        'Tu as déjà 5 presets. Supprime-en un pour en enregistrer un nouveau.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('OK'),
        ),
      ],
    ),
  );

  /// Prompts for a preset name; returns the trimmed name, a fallback when left
  /// blank, or null if cancelled. The dialog owns its own controller (see
  /// [_NamePresetDialog]) so it is disposed only once the route is fully gone —
  /// disposing it here, right after `await`, crashes during the close animation.
  Future<String?> _promptName() async {
    final fallback = 'Preset ${_presets.length + 1}';
    final raw = await showDialog<String>(
      context: context,
      builder: (_) => _NamePresetDialog(initialName: fallback),
    );
    if (raw == null) return null; // cancelled
    final trimmed = raw.trim();
    return trimmed.isEmpty ? fallback : trimmed;
  }

  /// Persists the preset list. Logs (never swallows) a failed save, and skips
  /// the invalidate if the write failed or the screen is already gone.
  Future<void> _persistPresets() async {
    try {
      await ref
          .read(profileRepositoryProvider)
          .updateThoughtPresets(_presets.map((e) => e.toJson()).toList());
    } on Exception catch (e) {
      debugPrint('thought_presets save failed: $e');
      return;
    }
    if (!mounted) return;
    ref.invalidate(myProfileProvider);
  }

  @override
  Widget build(BuildContext context) {
    final w = Colors.white;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('Personnalisation'),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF12162A), Color(0xFF06070E)],
          ),
        ),
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: [
              _section(w, 'Ta notification'),
              Text(
                'Voici comment ta pensée s\'affichera chez tes amis.',
                style: TextStyle(
                  color: w.withValues(alpha: 0.55),
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 14),
              _preview(w),
              const SizedBox(height: 18),
              _reels(w),
              const SizedBox(height: 28),
              _section(w, 'Mes presets'),
              _presetsCard(w),
            ],
          ),
        ),
      ),
    );
  }

  /// Live preview of the assembled notification.
  Widget _preview(Color w) => GlassCard(
    child: Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: const Color(0xFF8FB7FF).withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Center(
            child: Text('💧', style: TextStyle(fontSize: 20)),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'DewDrop',
                style: TextStyle(
                  color: w.withValues(alpha: 0.6),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _style.preview(_name),
                style: TextStyle(color: w, fontSize: 15),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  /// The three slot-machine reels.
  Widget _reels(Color w) => GlassCard(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          flex: 3,
          child: _reel(
            w,
            'avant',
            _leadCtl,
            kThoughtEmojis.length,
            (i) => _onReel(() => _lead = i),
            (i) => _emojiLabel(kThoughtEmojis[i]),
          ),
        ),
        Expanded(
          flex: 7,
          child: _reel(
            w,
            'phrase',
            _bodyCtl,
            kThoughtBodies.length,
            (i) => _onReel(() => _body = i),
            (i) => kThoughtBodies[i].replaceFirst('%s', _name),
            small: true,
          ),
        ),
        Expanded(
          flex: 3,
          child: _reel(
            w,
            'après',
            _tailCtl,
            kThoughtEmojis.length,
            (i) => _onReel(() => _tail = i),
            (i) => _emojiLabel(kThoughtEmojis[i]),
          ),
        ),
      ],
    ),
  );

  String _emojiLabel(String e) => e.isEmpty ? '—' : e;

  Widget _reel(
    Color w,
    String label,
    FixedExtentScrollController ctl,
    int count,
    ValueChanged<int> onChanged,
    String Function(int) text, {
    bool small = false,
  }) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            color: w.withValues(alpha: 0.4),
            fontSize: 11,
            letterSpacing: 0.4,
          ),
        ),
        SizedBox(
          height: 132,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Selection band.
              Container(
                height: 36,
                decoration: BoxDecoration(
                  color: w.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              ListWheelScrollView.useDelegate(
                controller: ctl,
                itemExtent: 36,
                perspective: 0.006,
                diameterRatio: 1.5,
                physics: const FixedExtentScrollPhysics(),
                onSelectedItemChanged: onChanged,
                childDelegate: ListWheelChildBuilderDelegate(
                  childCount: count,
                  builder: (_, i) => Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Text(
                        text(i),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: w.withValues(alpha: 0.85),
                          fontSize: small ? 13 : 22,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// The saved presets: tap a row to apply it, the trash icon to remove it, and
  /// the bottom button to store the current trio (capped at [kMaxThoughtPresets]).
  Widget _presetsCard(Color w) => GlassCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_presets.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text(
              'Aucun preset. Enregistre ton style actuel pour le retrouver en un tap.',
              style: TextStyle(color: w.withValues(alpha: 0.5), fontSize: 13),
            ),
          )
        else
          for (var i = 0; i < _presets.length; i++) ...[
            if (i > 0) Divider(color: w.withValues(alpha: 0.08), height: 1),
            _presetRow(w, _presets[i]),
          ],
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _onSavePreset,
            icon: const Icon(Icons.add_rounded, size: 20),
            label: const Text('Enregistrer ce style'),
            style: TextButton.styleFrom(foregroundColor: w),
          ),
        ),
      ],
    ),
  );

  Widget _presetRow(Color w, ThoughtPreset p) {
    final active = _isActive(p);
    return Row(
      children: [
        Expanded(
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => _applyPreset(p),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          p.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: w,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      if (active) ...[
                        const SizedBox(width: 6),
                        Icon(
                          Icons.check_circle,
                          size: 15,
                          color: const Color(0xFF8FB7FF).withValues(alpha: 0.9),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    p.style.preview(_name),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: w.withValues(alpha: 0.55),
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        IconButton(
          tooltip: 'Supprimer',
          icon: Icon(Icons.delete_outline, color: w.withValues(alpha: 0.5)),
          onPressed: () => _deletePreset(p),
        ),
      ],
    );
  }

  Widget _section(Color w, String t) => Padding(
    padding: const EdgeInsets.only(bottom: 8, left: 4),
    child: Text(
      t,
      style: TextStyle(
        fontSize: 13,
        letterSpacing: 0.6,
        fontWeight: FontWeight.w600,
        color: w.withValues(alpha: 0.6),
      ),
    ),
  );
}

/// Name-entry dialog for saving a preset. Owns its [TextEditingController] so it
/// is disposed only when the route is fully removed — disposing the controller
/// right after `await showDialog` instead crashes during the close animation
/// (the still-mounted [TextField] re-attaches to a disposed controller). Pops
/// the entered text on submit/confirm, or null on cancel.
class _NamePresetDialog extends StatefulWidget {
  const _NamePresetDialog({required this.initialName});

  final String initialName;

  @override
  State<_NamePresetDialog> createState() => _NamePresetDialogState();
}

class _NamePresetDialogState extends State<_NamePresetDialog> {
  late final TextEditingController _ctl;

  @override
  void initState() {
    super.initState();
    _ctl = TextEditingController(text: widget.initialName);
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Nom du preset'),
    content: TextField(
      controller: _ctl,
      autofocus: true,
      maxLength: 24,
      decoration: const InputDecoration(hintText: 'Ex. Bonjour, Bonne nuit…'),
      onSubmitted: (v) => Navigator.pop(context, v),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Annuler'),
      ),
      TextButton(
        onPressed: () => Navigator.pop(context, _ctl.text),
        child: const Text('Enregistrer'),
      ),
    ],
  );
}
