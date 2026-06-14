import 'dart:ui';

import 'package:dewdrop/decor/environment.dart';
import 'package:dewdrop/src/common/decor_choice.dart';
import 'package:flutter/material.dart';

/// Glass bottom sheet to pick the ambiance (environment + variant) and the
/// render mode (drawn / photo). Calls [onChanged] live as the user selects,
/// so the home behind it updates instantly.
class DecorPicker extends StatefulWidget {
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
  State<DecorPicker> createState() => _DecorPickerState();
}

class _DecorPickerState extends State<DecorPicker> {
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
                  Text('Ambiance',
                      style: TextStyle(
                          fontSize: 20, fontWeight: FontWeight.w500, color: w)),
                  _modeToggle(w),
                ],
              ),
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: media.size.height * 0.48),
                child: SingleChildScrollView(
                  child: Column(
                    children: [for (final env in Environment.values) _envRow(env, w)],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

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
        child: Text(label,
            style: TextStyle(
                fontSize: 12.5,
                color: w.withValues(alpha: sel ? 0.95 : 0.55),
                fontWeight: sel ? FontWeight.w600 : FontWeight.w400)),
      ),
    );
  }

  Widget _envRow(Environment env, Color w) {
    final isDraft = env.status == DecorStatus.draft;
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
                  child: Text(env.label,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 15, color: w.withValues(alpha: 0.92))),
                ),
                if (isDraft) ...[const SizedBox(width: 8), _tag(w)],
              ],
            ),
          ),
          for (var i = 0; i < env.variantCount; i++)
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: _chip(w, 'Var ${i + 1}',
                  _sel.$1 == env && _sel.$2 == i, () => _selectVariant(env, i)),
            ),
        ],
      ),
    );
  }

  Widget _tag(Color w) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: w.withValues(alpha: 0.08),
          border: Border.all(color: w.withValues(alpha: 0.18)),
        ),
        child: Text('ébauche',
            style: TextStyle(
                fontSize: 10,
                fontStyle: FontStyle.italic,
                color: w.withValues(alpha: 0.55))),
      );

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
          child: Text(label,
              style: TextStyle(
                  fontSize: 11.5,
                  color: w.withValues(alpha: sel ? 0.95 : 0.55),
                  fontWeight: sel ? FontWeight.w600 : FontWeight.w400)),
        ),
      );
}
