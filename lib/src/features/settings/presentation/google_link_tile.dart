import 'package:dewdrop/src/features/auth/application/auth_error.dart';
import 'package:dewdrop/src/features/auth/application/auth_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// « Compte Google » row of Réglages → Compte.
///
/// Links a Google account whatever its address (manual linking: the same
/// address is already joined automatically at sign-in), shows which one is
/// linked, and unlinks it — but only while another way to sign in remains:
/// unlinking the last one would lock the user out, so the row never offers it.
///
/// Renders nothing where the account picker doesn't exist. Lives inside a
/// settings card, which provides the transparent `Material` a `ListTile` needs.
class GoogleLinkTile extends ConsumerStatefulWidget {
  const GoogleLinkTile({super.key});

  @override
  ConsumerState<GoogleLinkTile> createState() => _GoogleLinkTileState();
}

class _GoogleLinkTileState extends ConsumerState<GoogleLinkTile> {
  bool _busy = false;

  /// Runs [action], then rebuilds from the repository (the source of truth).
  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } on Exception catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(authErrorMessage(e))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmUnlink() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Délier ton compte Google ?'),
        content: const Text(
          'Tu ne pourras plus te connecter avec Google. Ton compte DewDrop, '
          'tes amis et tes pensées ne changent pas.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Délier'),
          ),
        ],
      ),
    );
    if (ok ?? false) {
      await _run(() => ref.read(authRepositoryProvider).unlinkGoogle());
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authRepositoryProvider);
    if (!auth.supportsGoogle) return const SizedBox.shrink();
    final w = Colors.white;
    final link = auth.linkedGoogle;
    final muted = TextStyle(color: w.withValues(alpha: 0.5));
    final logo = Image.asset(
      'assets/brand/google_g.png',
      width: 22,
      height: 22,
      excludeFromSemantics: true,
    );
    final spinner = const SizedBox(
      width: 18,
      height: 18,
      child: CircularProgressIndicator(strokeWidth: 2),
    );

    if (link == null) {
      return ListTile(
        contentPadding: EdgeInsets.zero,
        leading: logo,
        title: const Text('Lier mon compte Google'),
        subtitle: Text('Pour te connecter aussi avec Google', style: muted),
        trailing: _busy
            ? spinner
            : Icon(Icons.chevron_right, color: w.withValues(alpha: 0.5)),
        onTap: _busy
            ? null
            : () => _run(() => ref.read(authRepositoryProvider).linkGoogle()),
      );
    }
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: logo,
      title: const Text('Compte Google lié'),
      subtitle: Text(link.email ?? 'Adresse non communiquée', style: muted),
      trailing: _busy
          ? spinner
          : link.canUnlink
          ? Text('Délier', style: TextStyle(color: w.withValues(alpha: 0.7)))
          : null,
      onTap: link.canUnlink && !_busy ? _confirmUnlink : null,
    );
  }
}
