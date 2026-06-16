import 'package:dewdrop/decor/environment.dart';
import 'package:dewdrop/src/common/glass.dart';
import 'package:dewdrop/src/features/auth/application/auth_error.dart';
import 'package:dewdrop/src/features/auth/application/auth_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// "Forgot password" — enter an email, Supabase sends a reset link that
/// reopens the app (custom scheme) in recovery mode. On success we show a
/// neutral confirmation that does NOT reveal whether the email has an account
/// (anti-enumeration): the wording is identical whether or not a user exists.
class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _email = TextEditingController();
  bool _loading = false;
  bool _sent = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _email.text.trim();
    if (email.isEmpty) {
      setState(() => _error = 'Renseigne ton email.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref.read(authRepositoryProvider).sendPasswordReset(email);
      if (mounted) setState(() => _sent = true);
    } on Exception catch (e) {
      if (mounted) setState(() => _error = authErrorMessage(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final white = Colors.white;
    return Scaffold(
      body: buildDecor(
        Environment.space,
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
                    if (_sent) ...[
                      Icon(
                        Icons.mark_email_read_outlined,
                        color: white.withValues(alpha: 0.9),
                        size: 46,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Lien envoyé',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: white,
                          fontSize: 18,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Si un compte existe pour cet email, tu vas recevoir '
                        'un lien pour choisir un nouveau mot de passe.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: white.withValues(alpha: 0.7),
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 22),
                      GlassButton(
                        label: 'Retour',
                        onTap: () => Navigator.of(context).pop(),
                      ),
                    ] else ...[
                      Text(
                        'Mot de passe oublié',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: white,
                          fontSize: 22,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Entre ton email, on t\'envoie un lien.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: white.withValues(alpha: 0.7)),
                      ),
                      const SizedBox(height: 22),
                      GlassTextField(
                        controller: _email,
                        hint: 'Email',
                        icon: Icons.alternate_email,
                        keyboardType: TextInputType.emailAddress,
                        autofillHints: const [AutofillHints.email],
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _submit(),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 14),
                        _ErrorBanner(message: _error!),
                      ],
                      const SizedBox(height: 20),
                      GlassButton(
                        label: 'Envoyer le lien',
                        loading: _loading,
                        onTap: _submit,
                      ),
                      const SizedBox(height: 14),
                      GestureDetector(
                        onTap: _loading ? null : () => Navigator.of(context).pop(),
                        child: Text(
                          'Retour à la connexion',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: white.withValues(alpha: 0.65),
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
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

/// Shared red error banner, matching the sign-in screen's treatment.
class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFF6B5A).withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFF6B5A).withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: Color(0xFFFFB4A8),
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Color(0xFFFFD6CE),
                fontSize: 13,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
