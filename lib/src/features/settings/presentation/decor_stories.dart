import 'dart:ui';

import 'package:dewdrop/decor/environment.dart';
import 'package:dewdrop/src/common/decor_choice.dart';
import 'package:dewdrop/src/common/system_ui.dart';
import 'package:dewdrop/src/features/settings/presentation/sound_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Full-screen "stories" world picker: each environment fills the screen as a
/// LIVE decor; swipe horizontally to travel between worlds, tap a named variant,
/// flip Dessin/Photo, open the 🔊 sound sheet, then « Choisir ce monde ».
///
/// Selection applies LIVE through [onChanged] (same contract as the former
/// bottom-sheet picker): the preview you see/hear *is* what gets kept, so closing
/// — via the CTA or the back arrow — simply confirms the world you're on. There
/// is no separate commit/cancel step, which keeps the flow immersive and the
/// state model trivial.
class DecorStories extends StatefulWidget {
  const DecorStories({
    super.key,
    required this.decor,
    required this.mode,
    required this.onChanged,
  });

  final String decor;
  final RenderMode mode;
  final void Function(String decor, RenderMode mode) onChanged;

  @override
  State<DecorStories> createState() => _DecorStoriesState();
}

class _DecorStoriesState extends State<DecorStories> {
  static final List<Environment> _envs = Environment.values;

  late final PageController _pages;
  late RenderMode _mode = widget.mode;
  late int _index;
  // Remembers the variant chosen per world while browsing.
  final Map<Environment, int> _variant = {};

  @override
  void initState() {
    super.initState();
    final (env, variant) = parseDecor(widget.decor);
    _index = _envs.indexOf(env);
    if (_index < 0) _index = 0;
    _variant[env] = variant;
    _pages = PageController(initialPage: _index);
    // This screen sits over the immersive home — keep the system bars hidden.
    SystemUi.immersive();
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  Environment get _env => _envs[_index];

  int _variantOf(Environment e) =>
      (_variant[e] ?? 0).clamp(0, e.variantCount - 1);

  void _apply() => widget.onChanged(encodeDecor(_env, _variantOf(_env)), _mode);

  void _onPage(int i) {
    HapticFeedback.selectionClick();
    setState(() => _index = i);
    _apply();
  }

  void _setVariant(int v) {
    setState(() => _variant[_env] = v);
    _apply();
  }

  void _setMode(RenderMode m) {
    if (m == _mode) return;
    setState(() => _mode = m);
    _apply();
  }

  @override
  Widget build(BuildContext context) {
    final w = Colors.white;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1) The live worlds.
          PageView.builder(
            controller: _pages,
            itemCount: _envs.length,
            onPageChanged: _onPage,
            itemBuilder: (_, i) => buildDecor(
              _envs[i],
              _variantOf(_envs[i]),
              _mode,
              parallax: false,
            ),
          ),
          // 2) Scrims so controls stay legible over bright worlds (beach, desert).
          _scrim(top: true),
          _scrim(top: false),
          // 3) Controls.
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Column(
                children: [
                  const SizedBox(height: 4),
                  _topBar(w),
                  const SizedBox(height: 12),
                  _dots(w),
                  const Spacer(),
                  _envTitle(w),
                  const SizedBox(height: 14),
                  _variantChips(w),
                  const SizedBox(height: 20),
                  _chooseButton(w),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _scrim({required bool top}) => Align(
    alignment: top ? Alignment.topCenter : Alignment.bottomCenter,
    child: IgnorePointer(
      child: Container(
        height: top ? 160 : 300,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: top ? Alignment.topCenter : Alignment.bottomCenter,
            end: top ? Alignment.bottomCenter : Alignment.topCenter,
            colors: [
              Colors.black.withValues(alpha: top ? 0.45 : 0.6),
              Colors.transparent,
            ],
          ),
        ),
      ),
    ),
  );

  Widget _topBar(Color w) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      _glassIcon(Icons.close_rounded, () => Navigator.of(context).pop()),
      Row(
        children: [
          _glassIcon(
            Icons.graphic_eq_rounded,
            () => showSoundSheet(context, _env),
          ),
          const SizedBox(width: 10),
          _modeToggle(w),
        ],
      ),
    ],
  );

  Widget _dots(Color w) => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      for (var i = 0; i < _envs.length; i++)
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.symmetric(horizontal: 3),
          width: i == _index ? 18 : 6,
          height: 6,
          decoration: BoxDecoration(
            color: w.withValues(alpha: i == _index ? 0.95 : 0.35),
            borderRadius: BorderRadius.circular(3),
          ),
        ),
    ],
  );

  Widget _envTitle(Color w) => Text(
    _env.label,
    textAlign: TextAlign.center,
    style: TextStyle(
      fontSize: 30,
      fontWeight: FontWeight.w300,
      letterSpacing: 1.5,
      color: w,
      shadows: const [Shadow(color: Colors.black54, blurRadius: 12)],
    ),
  );

  Widget _variantChips(Color w) {
    final sel = _variantOf(_env);
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 8,
      runSpacing: 8,
      children: [
        for (var i = 0; i < _env.variantCount; i++)
          GestureDetector(
            onTap: () => _setVariant(i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(99),
                color: i == sel
                    ? w.withValues(alpha: 0.9)
                    : w.withValues(alpha: 0.12),
                border: Border.all(
                  color: w.withValues(alpha: i == sel ? 0.9 : 0.3),
                ),
              ),
              child: Text(
                _env.variants[i],
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: i == sel ? FontWeight.w600 : FontWeight.w400,
                  color: i == sel ? Colors.black87 : w.withValues(alpha: 0.85),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _chooseButton(Color w) => SizedBox(
    width: double.infinity,
    child: GestureDetector(
      onTap: () => Navigator.of(context).pop(),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 15),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(99),
          color: w,
        ),
        child: const Text(
          'Choisir ce monde',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: Color(0xFF0A0E1C),
          ),
        ),
      ),
    ),
  );

  Widget _modeToggle(Color w) => Container(
    padding: const EdgeInsets.all(3),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(20),
      color: Colors.black.withValues(alpha: 0.25),
      border: Border.all(color: w.withValues(alpha: 0.2)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _modeSeg(w, 'Dessin', RenderMode.drawn),
        _modeSeg(w, 'Photo', RenderMode.photo),
      ],
    ),
  );

  Widget _modeSeg(Color w, String label, RenderMode m) {
    final selected = _mode == m;
    return GestureDetector(
      onTap: () => _setMode(m),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: selected ? w.withValues(alpha: 0.9) : Colors.transparent,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            color: selected ? Colors.black87 : w.withValues(alpha: 0.8),
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }

  Widget _glassIcon(IconData icon, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: ClipOval(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.black.withValues(alpha: 0.25),
            border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
          ),
          child: Icon(icon, color: Colors.white, size: 22),
        ),
      ),
    ),
  );
}
