import 'dart:async';
import 'dart:math' as math;
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
import 'package:dewdrop/src/features/home/presentation/dewdrop_loader.dart';
import 'package:dewdrop/src/features/home/presentation/received_peek.dart';
import 'package:dewdrop/src/features/home/presentation/send_dock.dart';
import 'package:dewdrop/src/features/settings/presentation/decor_stories.dart';
import 'package:dewdrop/src/features/settings/application/display_providers.dart';
import 'package:dewdrop/src/features/thoughts/application/thought_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Decides between onboarding (no handle yet) and the home, once the profile
/// has loaded. While loading, plays the DewDrop loader animation — kept on
/// screen for at least one full cycle so it's always seen (tap to skip).
class HomeGate extends ConsumerStatefulWidget {
  const HomeGate({super.key});

  @override
  ConsumerState<HomeGate> createState() => _HomeGateState();
}

class _HomeGateState extends ConsumerState<HomeGate> {
  // Laisse l'animation de chargement se jouer en entier au moins une fois (même
  // si le profil arrive plus vite), pour qu'on la voie toujours.
  bool _minDone = false;
  Timer? _minTimer;

  @override
  void initState() {
    super.initState();
    _minTimer = Timer(const Duration(milliseconds: 2300), () {
      if (mounted) setState(() => _minDone = true);
    });
  }

  @override
  void dispose() {
    _minTimer?.cancel();
    super.dispose();
  }

  // Un tap sur l'écran saute l'attente (effectif dès que le profil est prêt).
  void _skip() {
    _minTimer?.cancel();
    if (mounted && !_minDone) setState(() => _minDone = true);
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(myProfileProvider);
    if (profile.hasError) {
      return const Scaffold(
        body: Center(
          child: Text(
            'Une erreur est survenue.',
            style: TextStyle(color: Colors.white70),
          ),
        ),
      );
    }
    if (!(profile.hasValue && _minDone)) {
      return DewDropLoader(onTap: _skip);
    }
    final p = profile.value;
    if (p == null || !p.hasHandle) return const OnboardingView();
    return HomeView(profile: p);
  }
}

/// Which gesture sheet is currently revealed on the home.
enum _HomeSheet { none, send, recus }

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

  // Which gesture sheet is open (swipe ↑ = envoyer, swipe ↓ = pensées reçues).
  // Both paths also live in the ☰ menu, since a gesture isn't discoverable.
  _HomeSheet _sheet = _HomeSheet.none;
  bool _showHint = false; // one-time "swipe" hint on the first home view

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
      _maybeShowHint();
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
      if (unseen > 0) _celebrateCatchUp(unseen);
    } on Exception catch (_) {
      // Offline / transient — no burst, marker left untouched.
    }
  }

  // Cap the catch-up intensity so coming back after a long absence stays a
  // tasteful celebration rather than an overwhelming one.
  static const double _kMaxCatchUpIntensity = 2.5;

  /// One amplified celebration whose strength + duration scale with how many
  /// pensées arrived while the app was closed (a gentle sqrt curve, capped at
  /// [_kMaxCatchUpIntensity]). The active decor reads that intensity off the
  /// [ReceptionSignal] and sizes its burst accordingly. Guards on [mounted]
  /// since this runs after an async gap.
  void _celebrateCatchUp(int count) {
    if (count <= 0 || !mounted) return;
    final intensity = math.sqrt(count).clamp(1.0, _kMaxCatchUpIntensity);
    _reception.pulse(intensity.toDouble());
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

  // ── Gesture sheets (swipe ↑ envoyer / ↓ pensées reçues) ────────────────────
  void _openSend() {
    if (_sheet != _HomeSheet.send) {
      setState(() => _sheet = _HomeSheet.send);
    }
  }

  void _openRecus() {
    if (_sheet != _HomeSheet.recus) {
      setState(() => _sheet = _HomeSheet.recus);
    }
  }

  void _closeSheets() {
    if (_sheet != _HomeSheet.none) {
      setState(() => _sheet = _HomeSheet.none);
    }
  }

  // A vertical fling opens the matching sheet (or closes an open one). A plain
  // tap on the decor still triggers its preview burst (different gesture).
  void _onDragEnd(DragEndDetails d) {
    final v = d.primaryVelocity ?? 0;
    if (_sheet != _HomeSheet.none) {
      _closeSheets();
      return;
    }
    if (v < -250) {
      _openSend();
    } else if (v > 250) {
      _openRecus();
    }
  }

  // The ☰ fallback paths (and the sheets' "voir tout" buttons): drop immersive,
  // push the full screen, restore immersive on return.
  void _pushImmersive(String route) {
    _closeSheets();
    SystemUi.edgeToEdge();
    context.push(route).then((_) {
      if (mounted) SystemUi.immersive();
    });
  }

  // One-time hint on the first home view so the invisible gestures are findable.
  void _maybeShowHint() {
    final prefs = ref.read(sharedPreferencesProvider);
    if (prefs.getBool('home_gesture_hint_seen') ?? false) return;
    setState(() => _showHint = true);
    unawaited(prefs.setBool('home_gesture_hint_seen', true));
    Timer(const Duration(milliseconds: 3500), () {
      if (mounted) setState(() => _showHint = false);
    });
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

    final w = Colors.white;
    final open = _sheet != _HomeSheet.none;

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Decor + vertical-swipe to open a sheet. A plain tap still reaches
          // the decor (its preview burst); only vertical drags open the sheets.
          GestureDetector(
            behavior: HitTestBehavior.translucent,
            onVerticalDragEnd: _onDragEnd,
            child: buildDecor(
              env,
              variant,
              _mode,
              reception: _reception,
              parallax: parallax,
            ),
          ),

          // Floating chrome (inside the safe area so the handles clear Android's
          // system-gesture edges): the ☰ + the two discreet pull handles.
          // Handles are hidden while a sheet is open.
          SafeArea(
            child: Stack(
              children: [
                if (!open) ...[
                  Align(
                    alignment: Alignment.topCenter,
                    child: _Handle(onTap: _openRecus),
                  ),
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: _Handle(onTap: _openSend),
                  ),
                ],
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

          // Scrim (tap or swipe-back to close).
          IgnorePointer(
            ignoring: !open,
            child: GestureDetector(
              onTap: _closeSheets,
              onVerticalDragEnd: _onDragEnd,
              child: AnimatedOpacity(
                opacity: open ? 1 : 0,
                duration: const Duration(milliseconds: 250),
                child: ColoredBox(
                  color: Colors.black.withValues(alpha: 0.45),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ),

          // Send dock (swipe ↑).
          Align(
            alignment: Alignment.bottomCenter,
            child: AnimatedSlide(
              offset: _sheet == _HomeSheet.send
                  ? Offset.zero
                  : const Offset(0, 1.1),
              duration: const Duration(milliseconds: 340),
              curve: Curves.easeOutCubic,
              child: _SheetPanel(
                child: SendDock(onSeeAll: () => _pushImmersive('/send')),
              ),
            ),
          ),

          // Received peek (swipe ↓).
          Align(
            alignment: Alignment.topCenter,
            child: AnimatedSlide(
              offset: _sheet == _HomeSheet.recus
                  ? Offset.zero
                  : const Offset(0, -1.1),
              duration: const Duration(milliseconds: 340),
              curve: Curves.easeOutCubic,
              child: _SheetPanel(
                top: true,
                child: ReceivedPeek(
                  onSeeAll: () => _pushImmersive('/thoughts'),
                ),
              ),
            ),
          ),

          // One-time "swipe" hint.
          IgnorePointer(
            child: AnimatedOpacity(
              opacity: _showHint && !open ? 1 : 0,
              duration: const Duration(milliseconds: 500),
              child: SafeArea(
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 64),
                    child: Text(
                      'glisse ↑ pour envoyer · ↓ pour tes pensées',
                      style: TextStyle(
                        color: w.withValues(alpha: 0.6),
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
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

/// A very discreet pull handle (a thin, faint bar) hinting the swipe gestures.
/// The 12 px padding gives a comfortable tap target without making it look big.
class _Handle extends StatelessWidget {
  const _Handle({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Container(
          width: 34,
          height: 4,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    );
  }
}

/// Glass panel hosting a gesture sheet's content. [top] flips the rounded
/// corners + the safe-area inset so the same panel works sliding from the top
/// (pensées reçues) or the bottom (envoyer).
class _SheetPanel extends StatelessWidget {
  const _SheetPanel({required this.child, this.top = false});

  final Widget child;
  final bool top;

  @override
  Widget build(BuildContext context) {
    final w = Colors.white;
    final media = MediaQuery.of(context);
    final inset = top ? media.viewPadding.top : media.viewPadding.bottom;
    return ClipRRect(
      borderRadius: BorderRadius.vertical(
        top: top ? Radius.zero : const Radius.circular(26),
        bottom: top ? const Radius.circular(26) : Radius.zero,
      ),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: Container(
          width: double.infinity,
          padding: EdgeInsets.fromLTRB(
            20,
            top ? 14 + inset : 16,
            20,
            top ? 18 : 18 + inset,
          ),
          decoration: BoxDecoration(
            color: w.withValues(alpha: 0.10),
            border: Border.all(color: w.withValues(alpha: 0.16)),
          ),
          child: child,
        ),
      ),
    );
  }
}
