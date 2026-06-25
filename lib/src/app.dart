import 'dart:async';
import 'dart:io' show Platform;

import 'package:dewdrop/src/common/app_exceptions.dart';
import 'package:dewdrop/src/common/deep_link_listener.dart';
import 'package:dewdrop/src/features/auth/application/auth_providers.dart';
import 'package:dewdrop/src/features/friends/application/friend_providers.dart';
import 'package:dewdrop/src/features/friends/domain/friend.dart';
import 'package:dewdrop/src/features/friends/domain/friend_match.dart';
import 'package:dewdrop/src/features/home_widget/application/widget_providers.dart';
import 'package:dewdrop/src/features/notifications/application/push_providers.dart';
import 'package:dewdrop/src/features/notifications/application/thought_notifications.dart';
import 'package:dewdrop/src/features/profile/application/profile_providers.dart';
import 'package:dewdrop/src/features/thoughts/application/quick_send_service.dart';
import 'package:dewdrop/src/features/thoughts/application/thought_providers.dart';
import 'package:dewdrop/src/routing/app_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:home_widget/home_widget.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class DewDropApp extends ConsumerStatefulWidget {
  const DewDropApp({super.key});

  @override
  ConsumerState<DewDropApp> createState() => _DewDropAppState();
}

class _DewDropAppState extends ConsumerState<DewDropApp>
    with WidgetsBindingObserver {
  // App-level messenger so deep-link handlers (which fire outside any screen's
  // context) can still surface a snackbar.
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();
  late final DeepLinkListener _deepLinks;

  // An invite tapped while logged out is parked here and replayed once a
  // session exists — otherwise the friend request would fail silently.
  String? _pendingInvite;

  // Live "widget reconfigure" launches (long-press the widget → Reconfigure).
  StreamSubscription<Uri?>? _widgetClicks;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _deepLinks = DeepLinkListener(onInvite: _onInvite, onSend: _onSend)
      ..start();
    // Launching the app = the pensées are seen → clear the grouped tray + reset
    // the counters (also re-arms the "alert once" for the next batch).
    if (Platform.isAndroid || Platform.isIOS) {
      unawaited(clearThoughtNotifications());
      // Seed the home-screen widget early (writes the signed-out state before
      // any friend data lands; the listeners in build() refresh it afterwards).
      WidgetsBinding.instance.addPostFrameCallback((_) => _syncHomeWidget());
      // Reconfigure entry point: long-press the widget → "Reconfigure" bounces
      // into the app with the configure URI (cold launch + live taps) — open
      // the widget settings screen.
      unawaited(
        HomeWidget.initiallyLaunchedFromHomeWidget().then(_onWidgetLaunch),
      );
      _widgetClicks = HomeWidget.widgetClicked.listen(_onWidgetLaunch);
    }
  }

  /// Pushes the current friends + anonymity default + session state to the
  /// home-screen widget. Cheap and idempotent — safe to call on every change.
  void _syncHomeWidget() {
    if (!mounted || !(Platform.isAndroid || Platform.isIOS)) return;
    final signedIn = ref.read(authRepositoryProvider).currentSession != null;
    final friends = ref.read(widgetSlotFriendsProvider);
    final anonymous =
        ref.read(myProfileProvider).value?.defaultAnonymous ?? false;
    unawaited(
      ref
          .read(widgetSyncServiceProvider)
          .push(friends: friends, anonymous: anonymous, signedIn: signedIn),
    );
  }

  /// A widget launch URI (from the reconfigure trampoline) — open the widget
  /// settings screen. The hint's null URI and the background send are ignored.
  void _onWidgetLaunch(Uri? uri) {
    if (uri?.host != 'widget' || uri?.path != '/configure') return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(routerProvider).go('/widget-settings');
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _deepLinks.dispose();
    _widgetClicks?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Safety net: Realtime can miss events while backgrounded (socket dropped),
    // so on every foreground, refetch the live lists to catch up.
    if (state == AppLifecycleState.resumed) {
      ref.invalidate(friendsProvider);
      ref.invalidate(incomingRequestsProvider);
      ref.invalidate(receivedThoughtsProvider);
      ref.invalidate(recentContactsProvider);
      if (Platform.isAndroid || Platform.isIOS) {
        unawaited(clearThoughtNotifications());
        _syncHomeWidget();
      }
    }
  }

  Future<void> _onInvite(String handle) async {
    final auth = ref.read(authRepositoryProvider);
    if (auth.currentSession == null) {
      _pendingInvite = handle;
      return;
    }
    try {
      await ref.read(friendRepositoryProvider).sendRequest(handle);
      _snack('Demande envoyée à @${handle.toLowerCase()} ✨');
    } on FriendException catch (e) {
      _snack(e.message);
    } on Exception catch (_) {
      _snack("Lien d'invitation invalide.");
    }
  }

  /// A `dewdrop://send?to=<handle>` deep link (a voice routine / future Gemini
  /// AppFunction asking to send a pensée). Resolves the friend, then asks for a
  /// one-tap confirmation before sending — never a silent send, so an accidental
  /// voice trigger can't spam a friend.
  Future<void> _onSend(String handle) async {
    if (ref.read(authRepositoryProvider).currentSession == null) {
      _snack('Connecte-toi pour envoyer une pensée 🌙');
      return;
    }
    final FriendMatch match;
    try {
      match = await ref.read(quickSendServiceProvider).resolve(handle);
    } on Exception catch (_) {
      _snack('Impossible de charger tes amis pour le moment.');
      return;
    }
    switch (match) {
      case FriendMatched(:final friend):
        await _confirmAndSend(friend);
      case FriendAmbiguous():
        _snack('Plusieurs amis correspondent à « $handle ».');
      case FriendNotFound():
        _snack('Aucun ami nommé « $handle ».');
    }
  }

  /// Confirm dialog → send via the headless [quickSendServiceProvider] (the same
  /// capability the future AppFunction will call). Shown through the router's
  /// navigator since this fires outside any screen's context.
  Future<void> _confirmAndSend(Friend friend) async {
    final name = _friendName(friend);
    final navContext = ref
        .read(routerProvider)
        .routerDelegate
        .navigatorKey
        .currentContext;
    if (navContext == null || !mounted) return;
    final confirmed = await showDialog<bool>(
      context: navContext,
      builder: (ctx) => AlertDialog(
        title: Text('Envoyer une pensée à $name ?'),
        content: const Text('Un doux signal, sans message.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Envoyer ✨'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    switch (await ref.read(quickSendServiceProvider).send(friend)) {
      case QuickSendSent():
        _snack('Pensée envoyée à $name ✨');
      case QuickSendFailed(:final error):
        _snack(
          error is RateLimitedException
              ? 'Tu envoies un peu vite 🌬️ — réessaie dans une minute.'
              : "Échec de l'envoi.",
        );
      case QuickSendNoMatch():
      case QuickSendAmbiguous():
        _snack("Échec de l'envoi.");
    }
  }

  String _friendName(Friend friend) {
    final p = friend.profile;
    return p.displayName?.isNotEmpty == true ? p.displayName! : '@${p.handle}';
  }

  void _snack(String msg) {
    _messengerKey.currentState
      ?..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);

    // Keep the home-screen widget in step with the friend list + anonymity
    // default as they resolve and change (sign-in, add/remove friend, toggle).
    ref.listen(widgetSlotFriendsProvider, (_, _) => _syncHomeWidget());
    ref.listen(myProfileProvider, (_, _) => _syncHomeWidget());

    ref.listen(authStateChangesProvider, (_, next) {
      final state = next.value;
      if (state == null) return;
      // A password-reset link reopened the app: supabase_flutter has already
      // built the temporary session, so jump to the new-password screen.
      if (state.event == AuthChangeEvent.passwordRecovery) {
        router.go('/reset-password');
      }
      final session = state.session;
      if (session != null) {
        // Register this device for push (mobile only — desktop has no FCM).
        if (Platform.isAndroid || Platform.isIOS) {
          ref.read(pushServiceProvider).register(session.user.id);
        }
        // Replay an invite that arrived before the user was signed in.
        final pending = _pendingInvite;
        if (pending != null) {
          _pendingInvite = null;
          unawaited(_onInvite(pending));
        }
      }
    });

    return MaterialApp.router(
      title: 'DewDrop',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      scaffoldMessengerKey: _messengerKey,
      routerConfig: router,
    );
  }
}
