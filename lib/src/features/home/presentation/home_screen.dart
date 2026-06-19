import 'dart:async';
import 'dart:ui';

import 'package:dewdrop/decor/environment.dart';
import 'package:dewdrop/decor/reception_signal.dart';
import 'package:dewdrop/src/common/decor_choice.dart';
import 'package:dewdrop/src/common/system_ui.dart';
import 'package:dewdrop/src/features/ambient/application/ambient_providers.dart';
import 'package:dewdrop/src/features/auth/application/auth_providers.dart';
import 'package:dewdrop/src/features/notifications/application/push_providers.dart';
import 'package:dewdrop/src/features/profile/application/profile_providers.dart';
import 'package:dewdrop/src/features/profile/domain/profile.dart';
import 'package:dewdrop/src/features/profile/presentation/onboarding_view.dart';
import 'package:dewdrop/src/features/settings/presentation/decor_stories.dart';
import 'package:dewdrop/src/features/settings/application/display_providers.dart';
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
          child: Text(
            'Une erreur est survenue.',
            style: TextStyle(color: Colors.white70),
          ),
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
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: Colors.white70,
          ),
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
    // The live decor goes fully immersive — system bars hidden, swiped back.
    SystemUi.immersive();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncAmbient();
      unawaited(_checkUnseenOnOpen());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Leaving the decor (e.g. sign-out): bring the system bars back.
    SystemUi.edgeToEdge();
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
      // Re-assert immersive, but only if the decor is on top: a pushed screen
      // (Settings, Friends…) needs the system bars back.
      if (mounted && (ModalRoute.of(context)?.isCurrent ?? false)) {
        SystemUi.immersive();
      }
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
      final lastSeen = DateTime.fromMillisecondsSinceEpoch(
        markerMs,
        isUtc: true,
      );
      final unseen = list.where((t) => t.createdAt.isAfter(lastSeen)).length;
      if (unseen > 0) _replayBursts(unseen);
    } on Exception catch (_) {
      // Offline / transient — no burst, marker left untouched.
    }
  }

  // Cap the catch-up so returning after many pensées doesn't burst forever.
  static const _kMaxReplayBursts = 5;

  /// Replay one burst per unseen pensée (capped + staggered) so coming back to
  /// the app "catches up" what arrived while it was closed. Guards on [mounted]
  /// since the timers may outlive the screen.
  void _replayBursts(int count) {
    final n = count.clamp(1, _kMaxReplayBursts);
    for (var i = 0; i < n; i++) {
      Timer(Duration(milliseconds: i * 600), () {
        if (mounted) _reception.pulse();
      });
    }
  }

  void _markSeenNow() {
    unawaited(
      ref
          .read(sharedPreferencesProvider)
          .setInt(
            'reception_seen_at',
            DateTime.now().toUtc().millisecondsSinceEpoch,
          ),
    );
  }

  void _openMenu() {
    showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.18),
      isScrollControlled: true, // tall menu must never clip its bottom items
      builder: (_) => _HomeMenu(profile: widget.profile),
    ).then((result) {
      if (!mounted || result == null) return;
      if (result == 'decor') {
        _openDecorPicker();
        return;
      }
      final route = switch (result) {
        'friends' => '/friends',
        'thoughts' => '/thoughts',
        'thought-settings' => '/thought-settings',
        'send' => '/send',
        'settings' => '/settings',
        _ => null,
      };
      if (route == null) return;
      // Sub-screens want the system bars back; restore immersive on return.
      SystemUi.edgeToEdge();
      context.push(route).then((_) {
        if (mounted) SystemUi.immersive();
      });
    });
  }

  void _openDecorPicker() {
    // Full-screen "stories" world picker (fades in over the live home). Pushed
    // on the same Navigator so HomeView stays mounted underneath and its
    // immersive system-UI mode is preserved.
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 260),
        reverseTransitionDuration: const Duration(milliseconds: 200),
        pageBuilder: (_, _, _) => DecorStories(
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
        transitionsBuilder: (_, anim, _, child) =>
            FadeTransition(opacity: anim, child: child),
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
    final parallax = ref.watch(parallaxEnabledProvider);

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
        parallax: parallax,
        child: SafeArea(
          child: Stack(
            children: [
              Positioned(
                right: 20,
                bottom: 20,
                child: Opacity(
                  opacity: 0.5,
                  child: _GlassCircleButton(
                    icon: Icons.menu_rounded,
                    onTap: _openMenu,
                  ),
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
    final media = MediaQuery.of(context);
    // viewPadding (not padding): the inset survives even when the nav bar is
    // hidden by immersive mode, so the bottom items stay above where it sits.
    final bottom = media.viewPadding.bottom;
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: Container(
          width: double.infinity,
          // Cap the height + scroll, so a small screen never pushes the last
          // items ("Réglages" / "Se déconnecter") off the bottom.
          constraints: BoxConstraints(maxHeight: media.size.height * 0.85),
          padding: EdgeInsets.fromLTRB(22, 14, 22, 18 + bottom),
          decoration: BoxDecoration(
            color: white.withValues(alpha: 0.10),
            border: Border.all(color: white.withValues(alpha: 0.18)),
          ),
          child: SingleChildScrollView(
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
                // Centered identity header — app name, then name + handle, no avatar.
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'DewDrop',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w300,
                          letterSpacing: 2,
                          color: white,
                        ),
                      ),
                      const SizedBox(height: 10),
                      if (profile.displayName?.isNotEmpty == true) ...[
                        Text(
                          profile.displayName!,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            color: white,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '@${profile.handle}',
                          style: TextStyle(
                            color: white.withValues(alpha: 0.55),
                          ),
                        ),
                      ] else
                        Text(
                          '@${profile.handle}',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            color: white,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Divider(color: white.withValues(alpha: 0.15), height: 1),
                const SizedBox(height: 6),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    Icons.auto_awesome_outlined,
                    color: white.withValues(alpha: 0.85),
                  ),
                  title: const Text('Pensées reçues'),
                  trailing: Icon(
                    Icons.chevron_right,
                    color: white.withValues(alpha: 0.5),
                  ),
                  onTap: () => Navigator.of(context).pop('thoughts'),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    Icons.edit_note_rounded,
                    color: white.withValues(alpha: 0.85),
                  ),
                  title: const Text('Pensées'),
                  subtitle: Text(
                    'Anonymat + style de tes notifications',
                    style: TextStyle(
                      color: white.withValues(alpha: 0.5),
                      fontSize: 12,
                    ),
                  ),
                  trailing: Icon(
                    Icons.chevron_right,
                    color: white.withValues(alpha: 0.5),
                  ),
                  onTap: () => Navigator.of(context).pop('thought-settings'),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    Icons.send_rounded,
                    color: white.withValues(alpha: 0.85),
                  ),
                  title: const Text('Envoyer une pensée'),
                  trailing: Icon(
                    Icons.chevron_right,
                    color: white.withValues(alpha: 0.5),
                  ),
                  onTap: () => Navigator.of(context).pop('send'),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    Icons.group_outlined,
                    color: white.withValues(alpha: 0.85),
                  ),
                  title: const Text('Amis'),
                  trailing: Icon(
                    Icons.chevron_right,
                    color: white.withValues(alpha: 0.5),
                  ),
                  onTap: () => Navigator.of(context).pop('friends'),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    Icons.palette_outlined,
                    color: white.withValues(alpha: 0.85),
                  ),
                  title: const Text('Univers'),
                  trailing: Icon(
                    Icons.chevron_right,
                    color: white.withValues(alpha: 0.5),
                  ),
                  onTap: () => Navigator.of(context).pop('decor'),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    Icons.tune_rounded,
                    color: white.withValues(alpha: 0.85),
                  ),
                  title: const Text('Réglages'),
                  trailing: Icon(
                    Icons.chevron_right,
                    color: white.withValues(alpha: 0.5),
                  ),
                  onTap: () => Navigator.of(context).pop('settings'),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    Icons.logout_rounded,
                    color: white.withValues(alpha: 0.85),
                  ),
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
