import 'dart:async';

import 'package:dewdrop/src/common/glass.dart';
import 'package:dewdrop/src/features/profile/application/profile_providers.dart';
import 'package:dewdrop/src/features/thoughts/domain/thought_style.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// "Pensées" — the per-sender preferences for the thoughts they send: the
/// anonymity default, and a **slot-machine** style picker (3 reels: leading
/// emoji · phrase · trailing emoji) with a live preview of the notification the
/// recipient will receive. Persisted to the profile (debounced for the reels).
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
  late bool _anonymous;
  late String _name; // the recipient sees this (the sender's name)

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
    _anonymous = p?.defaultAnonymous ?? false;
    _name = (p?.displayName?.isNotEmpty == true)
        ? p!.displayName!
        : (p?.handle != null ? '@${p!.handle}' : 'Toi');
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
    _save = Timer(const Duration(milliseconds: 500), () {
      unawaited(
        ref.read(profileRepositoryProvider).updateThoughtStyle(_style.toJson()),
      );
      ref.invalidate(myProfileProvider);
    });
  }

  Future<void> _setAnonymous(bool v) async {
    setState(() => _anonymous = v);
    await ref.read(profileRepositoryProvider).updateDefaultAnonymous(v);
    ref.invalidate(myProfileProvider);
  }

  @override
  Widget build(BuildContext context) {
    final w = Colors.white;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('Pensées'),
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
              _section(w, 'Confidentialité'),
              GlassCard(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _anonymous,
                  onChanged: _setAnonymous,
                  title: const Text('Envoyer anonymement par défaut'),
                  subtitle: Text(
                    "Ton nom sera remplacé par « Quelqu'un ».",
                    style: TextStyle(color: w.withValues(alpha: 0.5)),
                  ),
                ),
              ),
              const SizedBox(height: 24),
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
