import 'package:dewdrop/decor/environment.dart';
import 'package:dewdrop/src/common/glass.dart';
import 'package:dewdrop/src/features/profile/application/profile_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final _handleRe = RegExp(r'^[a-z0-9_]{3,20}$');

/// Shown right after sign-up: pick a unique public handle.
class OnboardingView extends ConsumerStatefulWidget {
  const OnboardingView({super.key});

  @override
  ConsumerState<OnboardingView> createState() => _OnboardingViewState();
}

class _OnboardingViewState extends ConsumerState<OnboardingView> {
  final _handle = TextEditingController();
  final _name = TextEditingController();
  final _pseudoFocus = FocusNode();
  final _handleFocus = FocusNode();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _handle.dispose();
    _name.dispose();
    _pseudoFocus.dispose();
    _handleFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final pseudo = _name.text.trim();
    final handle = _handle.text.trim().toLowerCase();
    if (pseudo.isEmpty) {
      setState(() => _error = 'Choisis un pseudo.');
      return;
    }
    if (!_handleRe.hasMatch(handle)) {
      setState(() => _error = '3 à 20 caractères : lettres, chiffres ou _');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    final repo = ref.read(profileRepositoryProvider);
    try {
      if (!await repo.isHandleAvailable(handle)) {
        if (mounted) setState(() => _error = 'Ce handle est déjà pris.');
        return;
      }
      await repo.setHandle(handle, displayName: pseudo);
      if (mounted) ref.invalidate(myProfileProvider); // HomeGate shows the home
    } on Exception catch (e) {
      if (!mounted) return;
      // TOCTOU: someone grabbed the handle between the check and the insert →
      // the unique-constraint violation (Postgres 23505) means "taken".
      final taken = e.toString().contains('23505') ||
          e.toString().toLowerCase().contains('duplicate');
      setState(() =>
          _error = taken ? 'Ce handle est déjà pris.' : 'Une erreur est survenue.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final white = Colors.white;
    return Scaffold(
      body: buildDecor(
        Environment.forest,
        0,
        RenderMode.drawn,
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(28),
              child: GlassCard(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Crée ton profil',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 24, fontWeight: FontWeight.w500, color: white),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Ton pseudo est affiché ; ton @handle sert à te trouver.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: white.withValues(alpha: 0.7), fontSize: 13),
                    ),
                    const SizedBox(height: 22),
                    GlassTextField(
                      controller: _name,
                      hint: 'Pseudo (ex. Lélio)',
                      icon: Icons.face_outlined,
                      focusNode: _pseudoFocus,
                      textInputAction: TextInputAction.next,
                      onSubmitted: (_) => _handleFocus.requestFocus(),
                    ),
                    const SizedBox(height: 12),
                    GlassTextField(
                      controller: _handle,
                      hint: '@handle (ex. lelio)',
                      icon: Icons.alternate_email,
                      focusNode: _handleFocus,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _submit(),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(_error!,
                          style: const TextStyle(
                              color: Color(0xFFFFB4A8), fontSize: 13)),
                    ],
                    const SizedBox(height: 20),
                    GlassButton(
                      label: "C'est parti",
                      loading: _loading,
                      onTap: _submit,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
