import 'dart:io' show Platform;

import 'package:dewdrop/src/common/invite_links.dart';
import 'package:dewdrop/src/features/auth/application/auth_providers.dart';
import 'package:dewdrop/src/features/friends/application/friend_providers.dart';
import 'package:dewdrop/src/features/friends/domain/friend.dart';
import 'package:dewdrop/src/features/notifications/application/push_providers.dart';
import 'package:dewdrop/src/routing/app_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class DewDropApp extends ConsumerStatefulWidget {
  const DewDropApp({super.key});

  @override
  ConsumerState<DewDropApp> createState() => _DewDropAppState();
}

class _DewDropAppState extends ConsumerState<DewDropApp> {
  // App-level messenger so deep-link handlers (which fire outside any screen's
  // context) can still surface a snackbar.
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();
  late final InviteLinkListener _inviteLinks;

  // An invite tapped while logged out is parked here and replayed once a
  // session exists — otherwise the friend request would fail silently.
  String? _pendingInvite;

  @override
  void initState() {
    super.initState();
    _inviteLinks = InviteLinkListener(_onInvite)..start();
  }

  @override
  void dispose() {
    _inviteLinks.dispose();
    super.dispose();
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

  void _snack(String msg) {
    _messengerKey.currentState
      ?..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);

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
          _onInvite(pending);
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
