import 'dart:async';
import 'dart:ui';

import 'package:dewdrop/decor/environment.dart';
import 'package:dewdrop/decor/reception_signal.dart';
import 'package:dewdrop/src/common/decor_choice.dart';
import 'package:dewdrop/src/features/ambient/application/ambient_providers.dart';
import 'package:dewdrop/src/features/auth/application/auth_providers.dart';
import 'package:dewdrop/src/features/notifications/application/push_providers.dart';
import 'package:dewdrop/src/features/profile/application/profile_providers.dart';
import 'package:dewdrop/src/features/profile/domain/profile.dart';
import 'package:dewdrop/src/features/profile/presentation/onboarding_view.dart';
import 'package:dewdrop/src/features/settings/presentation/decor_picker.dart';
import 'package:dewdrop/src/features/thoughts/application/thought_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Decides between onboarding (no handle yet) and the home, once the profile
/// has loaded.
class HomeGate extends ConsumerWidget {
  const HomeGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(myProfileProvider);
    return profile.when(
      loading: () => const _DecorLoading(),
      error: (_, _) => const Scaffold(
        body: Center(
          child: Text('Une erreur est survenue.',
              style: TextStyle(color: Colors.white70)),
        ),
      ),
      data: (p) {
        if (p == null || !p.hasHandle) return const OnboardingView();
        return HomeView(profile: p);
      },
    );
  }
}

class _DecorLoading extends StatelessWidget {
  const _DecorLoading();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: buildDecor(
        Environment.space,
        0,
        RenderMode.drawn,
        child: const Center(
          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70),
        ),
      ),
    );
  }
}

/// The live home: the user's chosen decor as a full-screen background, with a
/// minimal floating UI over it. The decor is kept in local state so changes
/// from the picker apply instantly (and persist to the profile in background).
class HomeView extends ConsumerStatefulWidget {
  const HomeView({super.key, required this.profile});

  final Profile profile;

  @override
  ConsumerState<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends ConsumerState<HomeView>
    with WidgetsBindingObserver {
  late String _decor = widget.profile.decor;
  late RenderMode _mode = parseRenderMode(widget.profile.renderMode);
  // Cached at initState so dispose() never reads `ref` across teardown.
  late final SoundscapeNotifier _sound;
  // Owned here; pulsed by realtime + on-open detection so the active decor
  // bursts when a pensée is received. Disposed with the view.
  final ReceptionSignal _reception = ReceptionSignal();

  @override
  void initState() {
    super.initState();
    _sound = ref.read(soundscapeProvider.notifier);
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncAmbient();
      unawaited(_checkUnseenOnOpen());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_sound.pauseAll());
    _reception.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_sound.resumeAll());
      // Realtime may have missed events while backgrounded — catch up.
      unawaited(_checkUnseenOnOpen());
    } else if (state != AppLifecycleState.detached) {
      unawaited(_sound.pauseAll());
    }
  }

  /// Drive the soundscape (ambiance + music + one-shots) for the current decor.
  void _syncAmbient() {
    final (env, _) = parseDecor(_decor);
    unawaited(_sound.setEnvironment(env.name));
  }

  /// Burst once if a pensée arrived while the app was closed/backgrounded. The
  /// first ever run treats existing history as already seen (no burst for it).
  Future<void> _checkUnseenOnOpen() async {
    const key = 'reception_seen_at';
    final prefs = ref.read(sharedPreferencesProvider);
    final markerMs = prefs.getInt(key);
    final nowMs = DateTime.now().toUtc().millisecondsSinceEpoch;
    try {
      final list = await ref.read(receivedThoughtsProvider.future);
      if (!mounted) return;
      await prefs.setInt(key, nowMs);
      if (markerMs == null) return; // first run: nothing counts as new
      final lastSeen = DateTime.fromMillisecondsSinceEpoch(markerMs, isUtc: true);
      if (list.any((t) => t.createdAt.isAfter(lastSeen))) _reception.pulse();
    } on Exception catch (_) {
      // Offline / transient — no burst, marker left untouched.
    }
  }

  void _markSeenNow() {
    unawaited(ref.read(sharedPreferencesProvider).setInt(
        'reception_seen_at', DateTime.now().toUtc().millisecondsSinceEpoch));
  }

  void _openMenu() {
    showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.18),
      builder: (_) => _HomeMenu(profile: widget.profile),
    ).then((result) {
      if (!mounted) return;
      if (result == 'decor') _openDecorPicker();
      if (result == 'friends') context.push('/friends');
      if (result == 'thoughts') context.push('/thoughts');
      if (result == 'settings') context.push('/settings');
    });
  }

  void _openDecorPicker() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.18),
      isScrollControlled: true, // tall content (decor list + sound panel) scrolls
      builder: (_) => DecorPicker(
        decor: _decor,
        mode: _mode,
        onChanged: (decor, mode) {
          setState(() {
            _decor = decor;
            _mode = mode;
          });
          _syncAmbient();
          unawaited(_persist(decor, mode));
        },
      ),
    );
  }

  Future<void> _persist(String decor, RenderMode mode) async {
    try {
      await ref.read(profileRepositoryProvider).updateDecor(decor, mode.name);
    } on Exception catch (_) {
      // Background persistence; ignore transient failures.
    }
  }

  @override
  Widget build(BuildContext context) {
    final (env, variant) = parseDecor(_decor);

    // Live: a pensée arrives while the app is open -> burst now.
    ref.listen(incomingThoughtPulseProvider, (_, next) {
      if (next is AsyncData) {
        _reception.pulse();
        _markSeenNow();
      }
    });

    return Scaffold(
      body: buildDecor(
        env,
        variant,
        _mode,
        reception: _reception,
        child: SafeArea(
          child: Stack(
            children: [
              Positioned(
                right: 20,
                bottom: 20,
                child: _GlassCircleButton(
                  icon: Icons.menu_rounded,
                  onTap: _openMenu,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HomeMenu extends ConsumerWidget {
  const _HomeMenu({required this.profile});

  final Profile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final white = Colors.white;
    final bottom = MediaQuery.of(context).padding.bottom;
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: Container(
          width: double.infinity,
          padding: EdgeInsets.fromLTRB(22, 14, 22, 18 + bottom),
          decoration: BoxDecoration(
            color: white.withValues(alpha: 0.10),
            border: Border.all(color: white.withValues(alpha: 0.18)),
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
                    color: white.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 4),
                child: Text(
                  'DewDrop',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w300,
                    letterSpacing: 2,
                    color: white,
                  ),
                ),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.person_outline, color: white.withValues(alpha: 0.85)),
                title: Text(profile.displayName?.isNotEmpty == true
                    ? profile.displayName!
                    : '@${profile.handle}'),
                subtitle: Text('@${profile.handle}',
                    style: TextStyle(color: white.withValues(alpha: 0.55))),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.auto_awesome_outlined, color: white.withValues(alpha: 0.85)),
                title: const Text('Pensées reçues'),
                trailing: Icon(Icons.chevron_right, color: white.withValues(alpha: 0.5)),
                onTap: () => Navigator.of(context).pop('thoughts'),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.group_outlined, color: white.withValues(alpha: 0.85)),
                title: const Text('Amis'),
                trailing: Icon(Icons.chevron_right, color: white.withValues(alpha: 0.5)),
                onTap: () => Navigator.of(context).pop('friends'),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.palette_outlined, color: white.withValues(alpha: 0.85)),
                title: const Text('Univers'),
                trailing: Icon(Icons.chevron_right, color: white.withValues(alpha: 0.5)),
                onTap: () => Navigator.of(context).pop('decor'),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.tune_rounded, color: white.withValues(alpha: 0.85)),
                title: const Text('Réglages'),
                trailing: Icon(Icons.chevron_right, color: white.withValues(alpha: 0.5)),
                onTap: () => Navigator.of(context).pop('settings'),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.logout_rounded, color: white.withValues(alpha: 0.85)),
                title: const Text('Se déconnecter'),
                onTap: () async {
                  // Capture before popping — the sheet's `ref` is gone after pop.
                  final push = ref.read(pushServiceProvider);
                  final auth = ref.read(authRepositoryProvider);
                  Navigator.of(context).pop();
                  try {
                    // Drop the device token while still authenticated (RLS),
                    // then sign out. Best-effort: a failure must not strand the
                    // user in a half-signed-out state silently.
                    await push.unregister();
                    await auth.signOut();
                  } on Exception catch (_) {
                    // The router redirect handles navigation on success.
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GlassCircleButton extends StatelessWidget {
  const _GlassCircleButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final white = Colors.white;
    return GestureDetector(
      onTap: onTap,
      child: ClipOval(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: white.withValues(alpha: 0.14),
              border: Border.all(color: white.withValues(alpha: 0.28)),
            ),
            child: Icon(icon, color: white.withValues(alpha: 0.9), size: 24),
          ),
        ),
      ),
    );
  }
}
