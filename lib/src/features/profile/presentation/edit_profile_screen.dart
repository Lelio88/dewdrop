import 'package:dewdrop/src/common/glass.dart';
import 'package:dewdrop/src/features/profile/application/profile_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final _handleRe = RegExp(r'^[a-z0-9_]{3,20}$');

/// Edit the display name and/or @handle after onboarding. The handle's
/// availability is only re-checked when it actually **changed** (your own handle
/// reads as "taken").
class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key});

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  late final TextEditingController _name;
  late final TextEditingController _handle;
  late final String _initialHandle;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final p = ref.read(myProfileProvider).value;
    _name = TextEditingController(text: p?.displayName ?? '');
    _initialHandle = p?.handle ?? '';
    _handle = TextEditingController(text: _initialHandle);
  }

  @override
  void dispose() {
    _name.dispose();
    _handle.dispose();
    super.dispose();
  }

  Future<void> _save() async {
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
      final handleChanged = handle != _initialHandle;
      if (handleChanged && !await repo.isHandleAvailable(handle)) {
        if (mounted) setState(() => _error = 'Ce handle est déjà pris.');
        return;
      }
      await repo.updateProfile(
        displayName: pseudo,
        handle: handleChanged ? handle : null,
      );
      if (!mounted) return;
      ref.invalidate(myProfileProvider);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Profil mis à jour ✓')));
      Navigator.of(context).pop();
    } on Exception catch (e) {
      if (!mounted) return;
      // TOCTOU: the handle got taken between the check and the update (PG 23505).
      final taken =
          e.toString().contains('23505') ||
          e.toString().toLowerCase().contains('duplicate');
      setState(
        () => _error = taken
            ? 'Ce handle est déjà pris.'
            : 'Une erreur est survenue.',
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final w = Colors.white;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('Modifier mon profil'),
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
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: GlassCard(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Ton pseudo est affiché ; ton @handle sert à te trouver.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: w.withValues(alpha: 0.7), fontSize: 13),
                  ),
                  const SizedBox(height: 20),
                  GlassTextField(
                    controller: _name,
                    hint: 'Pseudo',
                    icon: Icons.face_outlined,
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 12),
                  GlassTextField(
                    controller: _handle,
                    hint: '@handle',
                    icon: Icons.alternate_email,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _save(),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      style: const TextStyle(color: Color(0xFFFFB4A8), fontSize: 13),
                    ),
                  ],
                  const SizedBox(height: 20),
                  GlassButton(label: 'Enregistrer', loading: _loading, onTap: _save),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
