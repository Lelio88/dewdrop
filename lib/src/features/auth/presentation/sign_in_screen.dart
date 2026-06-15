import 'package:dewdrop/decor/environment.dart';
import 'package:dewdrop/src/common/glass.dart';
import 'package:dewdrop/src/features/auth/application/auth_error.dart';
import 'package:dewdrop/src/features/auth/application/auth_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Email + password sign in / sign up, over a calm decor background.
class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _passwordFocus = FocusNode();
  bool _isSignUp = false;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _email.text.trim();
    final password = _password.text;
    if (email.isEmpty || password.isEmpty) {
      setState(() => _error = 'Renseigne ton email et ton mot de passe.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    final auth = ref.read(authRepositoryProvider);
    try {
      if (_isSignUp) {
        await auth.signUp(email, password);
      } else {
        await auth.signIn(email, password);
      }
      // Navigation is handled by the router redirect on auth-state change.
    } on Exception catch (e) {
      if (mounted) {
        setState(() => _error = authErrorMessage(e, isSignUp: _isSignUp));
      }
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
                    Text(
                      'DewDrop',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 38,
                        fontWeight: FontWeight.w300,
                        letterSpacing: 2,
                        color: white,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _isSignUp ? 'Crée ton compte' : 'Content de te revoir',
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
                      textInputAction: TextInputAction.next,
                      onSubmitted: (_) => _passwordFocus.requestFocus(),
                    ),
                    const SizedBox(height: 12),
                    GlassTextField(
                      controller: _password,
                      hint: 'Mot de passe',
                      icon: Icons.lock_outline,
                      obscure: true,
                      focusNode: _passwordFocus,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _submit(),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF6B5A).withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: const Color(0xFFFF6B5A).withValues(alpha: 0.4)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.error_outline_rounded,
                                color: Color(0xFFFFB4A8), size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _error!,
                                style: const TextStyle(
                                    color: Color(0xFFFFD6CE), fontSize: 13, height: 1.3),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    GlassButton(
                      label: _isSignUp ? 'Créer mon compte' : 'Se connecter',
                      loading: _loading,
                      onTap: _submit,
                    ),
                    const SizedBox(height: 14),
                    GestureDetector(
                      onTap: _loading
                          ? null
                          : () => setState(() {
                                _isSignUp = !_isSignUp;
                                _error = null;
                              }),
                      child: Text(
                        _isSignUp
                            ? 'Déjà un compte ? Se connecter'
                            : "Pas de compte ? S'inscrire",
                        textAlign: TextAlign.center,
                        style: TextStyle(color: white.withValues(alpha: 0.65), fontSize: 13),
                      ),
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
