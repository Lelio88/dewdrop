import 'dart:async';
import 'dart:math' as math;

import 'package:dewdrop/decor/decor_image_cache.dart';
import 'package:dewdrop/decor/environment.dart';
import 'package:dewdrop/decor/reception_signal.dart';
import 'package:dewdrop/src/common/decor_choice.dart';
import 'package:dewdrop/src/common/system_ui.dart';
import 'package:dewdrop/src/features/ambient/application/ambient_providers.dart';
import 'package:dewdrop/src/features/profile/application/profile_providers.dart';
import 'package:dewdrop/src/features/profile/domain/profile.dart';
import 'package:dewdrop/src/features/profile/presentation/onboarding_view.dart';
import 'package:dewdrop/src/features/home/domain/home_sheet.dart';
import 'package:dewdrop/src/features/home/presentation/dewdrop_loader.dart';
import 'package:dewdrop/src/features/home/presentation/home_chrome.dart';
import 'package:dewdrop/src/features/home/presentation/home_menu.dart';
import 'package:dewdrop/src/features/home/presentation/received_peek.dart';
import 'package:dewdrop/src/features/home/presentation/sheet_panel.dart';
import 'package:dewdrop/src/features/home/presentation/send_dock.dart';
import 'package:dewdrop/src/features/settings/presentation/decor_stories.dart';
import 'package:dewdrop/src/features/settings/application/decor_favorites_provider.dart';
import 'package:dewdrop/src/features/settings/application/display_providers.dart';
import 'package:dewdrop/src/features/settings/application/seasonal_providers.dart';
import 'package:dewdrop/src/features/thoughts/application/thought_providers.dart';
import 'package:dewdrop/src/features/tour/application/tour_providers.dart';
import 'package:dewdrop/src/features/tour/domain/tour_step.dart';
import 'package:dewdrop/src/features/tour/presentation/cloud_tour.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  // Which gesture sheet is open + how far (peek vs full). Swipe ↑ = envoyer,
  // swipe ↓ = pensées reçues; a second swipe the same way escalates the sheet to
  // full screen (see [nextSheetState]). Both paths also live in the ☰ menu,
  // since a gesture isn't discoverable.
  SheetState _sheetState = SheetState.closed;

  // Anchors the cloud tour points at. They live on the real chrome, so the
  // tour's spotlight follows it if the layout ever moves.
  final _sendHandleKey = GlobalKey();
  final _recusHandleKey = GlobalKey();
  final _menuKey = GlobalKey();
  final _sendSheetKey = GlobalKey();
  final _recusSheetKey = GlobalKey();
  final _sendHintKey = GlobalKey();
  final _recusHintKey = GlobalKey();

  /// Carries out a gesture the tour recognised and approved.
  ///
  /// While the tour is up it owns the screen, so the home never sees the raw
  /// drag: the tour matches it against the current step and calls this only for
  /// the one it teaches. Same effects as the real handlers — this IS the real
  /// gesture, just routed through the one place that knows what step we're on.
  void _performTourGesture(TourGesture g) {
    switch (g) {
      case TourGesture.swipeUp:
        setState(() => _sheetState = nextSheetState(_sheetState, up: true));
      case TourGesture.swipeDown:
        setState(() => _sheetState = nextSheetState(_sheetState, up: false));
      case TourGesture.swipeSide:
        _cycleWorldsForTour();
    }
  }

  /// The sideways swipe as the tour needs it: always a visible world change,
  /// favourites or not (that step exists to show the gesture works).
  void _cycleWorldsForTour() {
    if (ref.read(seasonalOverrideProvider) != null) return; // world is locked
    final favorites = ref.read(decorFavoritesProvider);
    _slideDir = 1;
    if (favorites.isEmpty) {
      _cycleAllWorlds(forward: true);
      return;
    }
    final idx = favorites.indexOf(_currentFavoriteKey());
    _applyFavorite(favorites[idx < 0 ? 0 : (idx + 1) % favorites.length]);
  }

  // Direction the next favourite slides in from: +1 = from the right (swiped
  // left → next world), -1 = from the left (swiped right → previous world).
  // Read by the home décor's AnimatedSwitcher so the world glides in the same
  // direction as the finger instead of popping in place.
  double _slideDir = 1;

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
      _prewarmNeighbours(); // warm the first swipe's neighbours
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
      // A day boundary may have crossed while backgrounded — re-sample the
      // marronnier window (into/out of Halloween, Noël…). The build's
      // ref.listen re-syncs the ambience if the lock flipped.
      ref.invalidate(seasonalOverrideProvider);
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

  /// Drive the soundscape (ambiance + music + one-shots) for the current decor —
  /// the marronnier's forced world if one is active, else the user's own — so
  /// the ambience always matches what's actually on screen.
  void _syncAmbient() {
    final s = ref.read(seasonalOverrideProvider);
    final (env, _) = parseDecor(s?.decor ?? _decor);
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
  // The ☰ menu + top/bottom handles open a sheet at its peek stage.
  void _openSend() => setState(
    () => _sheetState = const SheetState(HomeSheet.send, SheetStage.peek),
  );

  void _openRecus() => setState(
    () => _sheetState = const SheetState(HomeSheet.recus, SheetStage.peek),
  );

  void _closeSheets() {
    if (_sheetState.isOpen) setState(() => _sheetState = SheetState.closed);
  }

  /// Put the drawers in the state the tour's current step wants to talk about,
  /// so a bubble never describes something that isn't on screen (the user may
  /// have tapped "Suivant" instead of performing the gesture).
  void _applyTourScene(TourScene scene) {
    final next = switch (scene) {
      TourScene.closed => SheetState.closed,
      TourScene.sendPeek => const SheetState(HomeSheet.send, SheetStage.peek),
      TourScene.sendFull => const SheetState(HomeSheet.send, SheetStage.full),
      TourScene.receivedPeek => const SheetState(
        HomeSheet.recus,
        SheetStage.peek,
      ),
      TourScene.receivedFull => const SheetState(
        HomeSheet.recus,
        SheetStage.full,
      ),
    };
    if (next != _sheetState) setState(() => _sheetState = next);
  }

  // A vertical fling drives the sheet state machine: from closed it opens the
  // matching sheet (↑ envoyer / ↓ reçus) at peek; a second fling the same way
  // escalates to full, the opposite way retreats one level (peek → closed, full
  // → peek). See [nextSheetState]. A plain tap on the decor still triggers its
  // preview burst — a different gesture the arena resolves.
  void _onDragEnd(DragEndDetails d) {
    final v = d.primaryVelocity ?? 0;
    if (v.abs() < 250) return;
    setState(() => _sheetState = nextSheetState(_sheetState, up: v < 0));
  }

  // The favourite snapshot ("<env>:<variant>:<mode>") currently on screen.
  String _currentFavoriteKey() {
    final (env, variant) = parseDecor(_decor);
    return encodeFavorite(env, variant, _mode);
  }

  // Decode the favourites on either side of the current one into the shared
  // image cache, so the next swipe paints the new world on its first frame
  // instead of briefly flashing its flat base colour while the photo decodes.
  // No-op when fewer than two favourites, or when not currently on a favourite.
  void _prewarmNeighbours() {
    // No neighbours to warm while a marronnier locks the world.
    if (ref.read(seasonalOverrideProvider) != null) return;
    final favorites = ref.read(decorFavoritesProvider);
    if (favorites.length < 2) return;
    final idx = favorites.indexOf(_currentFavoriteKey());
    if (idx < 0) return;
    final n = favorites.length;
    final prev = favorites[(idx - 1 + n) % n];
    final next = favorites[(idx + 1) % n];
    for (final fav in {prev, next}) {
      final (env, variant, mode) = parseFavorite(fav);
      final assetRoot = mode == RenderMode.photo ? 'photo' : 'illustrated';
      DecorImageCache.instance.prewarm(assetRoot, env.name, variant);
    }
  }

  // A horizontal fling cycles through the user's starred decors — right =
  // previous, left = next — wrapping around. Ignored while a sheet is open
  // (those own the gesture) and below the same 250 px/s threshold as the
  // vertical sheets, so a lazy drag doesn't switch worlds by accident. The
  // chosen favourite becomes the live + persisted selection.
  void _onHorizontalDragEnd(DragEndDetails d) {
    if (_sheetState.isOpen) return;
    final v = d.primaryVelocity ?? 0;
    if (v.abs() < 250) return;
    // Locked to a single world during a marronnier — no favourite cycling.
    if (ref.read(seasonalOverrideProvider) != null) return;
    // With no ⭐ yet, the gesture walks EVERY world rather than doing nothing.
    // A brand-new account has no favourites, so the old early-return made the
    // swipe silently dead exactly when it was being discovered — and made the
    // tour a liar. Starring then becomes a shortlist, not a prerequisite.
    final favorites = ref.read(decorFavoritesProvider);
    if (favorites.isEmpty) {
      _cycleAllWorlds(forward: v < 0);
      return;
    }
    // Swipe right (v > 0) reveals the previous world from the left; swipe left
    // (v < 0) brings the next world in from the right.
    _slideDir = v > 0 ? -1 : 1;
    final idx = favorites.indexOf(_currentFavoriteKey());
    if (idx < 0) {
      // Not currently on a favourite → jump into the list from the matching end.
      _applyFavorite(v > 0 ? favorites.last : favorites.first);
      return;
    }
    if (favorites.length < 2) return; // a single favourite, already on it
    final next = v > 0
        ? (idx - 1 + favorites.length) % favorites.length
        : (idx + 1) % favorites.length;
    _applyFavorite(favorites[next]);
  }

  // Fallback cycling for an account with no ⭐ yet: step through the ordinary
  // worlds (seasonal ones excluded — they're date-locked and never chosen by
  // hand), keeping the current render mode and landing on each world's first
  // scene. As soon as the user stars anything, [_onHorizontalDragEnd] goes back
  // to walking the favourites instead.
  void _cycleAllWorlds({required bool forward}) {
    final worlds = [
      for (final e in Environment.values)
        if (!e.seasonal) e,
    ];
    if (worlds.isEmpty) return;
    final (currentEnv, _) = parseDecor(_decor);
    final idx = worlds.indexOf(currentEnv);
    final next = idx < 0
        ? (forward ? worlds.first : worlds.last)
        : worlds[(idx + (forward ? 1 : -1) + worlds.length) % worlds.length];
    _slideDir = forward ? 1 : -1;
    _applyFavorite(encodeFavorite(next, 0, _mode));
  }

  // Switches the live decor to a starred snapshot (world + variant + mode),
  // re-syncs ambient sound, and persists it as the current decor.
  void _applyFavorite(String favorite) {
    final (env, variant, mode) = parseFavorite(favorite);
    final decor = encodeDecor(env, variant);
    if (decor == _decor && mode == _mode) return;
    HapticFeedback.selectionClick();
    setState(() {
      _decor = decor;
      _mode = mode;
    });
    _syncAmbient();
    unawaited(_persist(decor, mode));
    _prewarmNeighbours(); // look ahead to the new neighbours
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

  void _openMenu() {
    showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.18),
      isScrollControlled: true, // tall menu must never clip its bottom items
      builder: (_) => HomeMenu(profile: widget.profile),
    ).then((result) {
      if (!mounted || result == null) return;
      if (result == 'decor') {
        _openDecorPicker();
        return;
      }
      final route = switch (result) {
        'friends' => '/friends',
        'thoughts' => '/thoughts',
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
    final seasonal = ref.watch(seasonalOverrideProvider);
    // The world actually shown: the marronnier's forced decor when one is active
    // (display-only — never persisted, so the user's own decor returns when the
    // window closes), otherwise the user's live choice.
    final decorStr = seasonal?.decor ?? _decor;
    final mode = seasonal?.mode ?? _mode;
    final (env, variant) = parseDecor(decorStr);
    final parallax = ref.watch(parallaxEnabledProvider);

    // When the marronnier window flips (e.g. resume across midnight), follow the
    // new world's ambience.
    ref.listen(seasonalOverrideProvider, (_, _) => _syncAmbient());

    // Live: a pensée arrives while the app is open -> burst now.
    ref.listen(incomingThoughtPulseProvider, (_, next) {
      if (next is AsyncData) {
        _reception.pulse();
        _markSeenNow();
      }
    });

    final open = _sheetState.isOpen;
    final showTour = ref.watch(showTourProvider(TourId.home));
    final media = MediaQuery.of(context);
    final fullH = media.size.height * 0.9;
    final sendFull =
        _sheetState.sheet == HomeSheet.send &&
        _sheetState.stage == SheetStage.full;
    final recusFull =
        _sheetState.sheet == HomeSheet.recus &&
        _sheetState.stage == SheetStage.full;

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Decor + swipes: vertical opens a sheet (↑ envoyer / ↓ reçus),
          // horizontal cycles through favourite decors. A plain tap still
          // reaches the decor (its preview burst); the gesture arena picks the
          // dominant axis, so the two drag directions never fight.
          GestureDetector(
            behavior: HitTestBehavior.translucent,
            onVerticalDragEnd: _onDragEnd,
            onHorizontalDragEnd: _onHorizontalDragEnd,
            // Switching favourites glides the new world in from the swipe side
            // (and the old one out the other way) instead of popping. The key is
            // the decor snapshot, so only an actual world/variant/mode change
            // triggers a transition — a sheet toggle or a reception burst keeps
            // the same live decor (and its state) in place.
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 340),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) {
                final incoming =
                    child.key == ValueKey('$decorStr:${mode.name}');
                final begin = Offset(incoming ? _slideDir : -_slideDir, 0);
                return ClipRect(
                  child: SlideTransition(
                    position: Tween(
                      begin: begin,
                      end: Offset.zero,
                    ).animate(animation),
                    child: child,
                  ),
                );
              },
              child: KeyedSubtree(
                key: ValueKey('$decorStr:${mode.name}'),
                // Freeze the world while a tour is up. Its bespoke FX animate
                // continuously and its parallax rebuilds a depth mesh on every
                // gyroscope sample — all of it behind a 62%-black scrim, for a
                // few seconds, at the exact moment the app makes its first
                // impression.
                //
                // TickerMode sits INSIDE the AnimatedSwitcher on purpose: the
                // switcher's own ticker must keep running, or the sideways
                // swipe the tour asks for would leave the incoming world parked
                // off-screen with its slide animation stuck at zero.
                child: TickerMode(
                  enabled: !showTour,
                  child: buildDecor(
                    env,
                    variant,
                    mode,
                    reception: _reception,
                    parallax: parallax && !showTour,
                  ),
                ),
              ),
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
                    child: HomeHandle(key: _recusHandleKey, onTap: _openRecus),
                  ),
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: HomeHandle(key: _sendHandleKey, onTap: _openSend),
                  ),
                ],
                Positioned(
                  right: 20,
                  bottom: 20,
                  child: Opacity(
                    opacity: 0.5,
                    child: GlassCircleButton(
                      key: _menuKey,
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

          // Send dock (swipe ↑; a second ↑ expands it to full screen).
          Align(
            alignment: Alignment.bottomCenter,
            child: AnimatedSlide(
              offset: _sheetState.sheet == HomeSheet.send
                  ? Offset.zero
                  : const Offset(0, 1.1),
              duration: const Duration(milliseconds: 340),
              curve: Curves.easeOutCubic,
              child: SheetPanel(
                // Tour anchor: AnimatedSlide's transform is part of the paint
                // transform, so localToGlobal tracks the panel WHILE it slides
                // — that's how the cloud rides it up instead of covering it.
                key: _sendSheetKey,
                hintKey: _sendHintKey,
                height: sendFull ? fullH : null,
                onGrabDrag: _onDragEnd,
                child: SendDock(
                  expanded: sendFull,
                  onAddFriend: () => _pushImmersive('/friends'),
                  // Stays mounted when closed (it just slides off) — the dock
                  // needs this to defer its re-ordering until it's hidden.
                  visible: _sheetState.sheet == HomeSheet.send,
                  onSeeAll: () => _pushImmersive('/send'),
                ),
              ),
            ),
          ),

          // Received peek (swipe ↓; a second ↓ expands it to full screen).
          Align(
            alignment: Alignment.topCenter,
            child: AnimatedSlide(
              offset: _sheetState.sheet == HomeSheet.recus
                  ? Offset.zero
                  : const Offset(0, -1.1),
              duration: const Duration(milliseconds: 340),
              curve: Curves.easeOutCubic,
              child: SheetPanel(
                key: _recusSheetKey,
                hintKey: _recusHintKey,
                top: true,
                height: recusFull ? fullH : null,
                onGrabDrag: _onDragEnd,
                child: ReceivedPeek(
                  expanded: recusFull,
                  // Samples stand in while the tour runs on an empty account —
                  // see ReceivedPeek.demo.
                  demo: showTour,
                  onSeeAll: () => _pushImmersive('/thoughts'),
                ),
              ),
            ),
          ),

          // Marronnier lock badge — explains why the world can't be changed.
          if (seasonal != null && !open)
            SafeArea(
              child: Align(
                alignment: Alignment.topCenter,
                child: Padding(
                  padding: const EdgeInsets.only(top: 40),
                  child: SeasonalBadge(event: seasonal),
                ),
              ),
            ),

          // First-run tour. It supersedes the one-line "glisse ↑ / ↓" hint that
          // used to flash here: the same gestures, but shown where they happen
          // and at a pace that can actually be read. Replayed from Réglages via
          // homeTourProvider.
          //
          // It deliberately stays up while a sheet is open — the swipe steps
          // WANT the user to open one, and yanking the tour away mid-gesture
          // would punish the very thing it just asked for. Instead, each step
          // change closes whatever the swipe opened, so the next bubble never
          // talks over a sheet.
          if (showTour)
            CloudTour(
              anchors: {
                TourAnchor.sendHandle: _sendHandleKey,
                TourAnchor.receivedHandle: _recusHandleKey,
                TourAnchor.sendSheet: _sendSheetKey,
                TourAnchor.receivedSheet: _recusSheetKey,
                TourAnchor.sendSheetHint: _sendHintKey,
                TourAnchor.receivedSheetHint: _recusHintKey,
                TourAnchor.menuButton: _menuKey,
              },
              onPerform: _performTourGesture,
              onScene: _applyTourScene,
              onFinish: () =>
                  ref.read(toursSeenProvider.notifier).complete(TourId.home),
            ),
        ],
      ),
    );
  }
}
