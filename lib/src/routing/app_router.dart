import 'dart:async';

import 'package:dewdrop/src/features/auth/application/auth_providers.dart';
import 'package:dewdrop/src/features/auth/presentation/forgot_password_screen.dart';
import 'package:dewdrop/src/features/auth/presentation/reset_password_screen.dart';
import 'package:dewdrop/src/features/auth/presentation/sign_in_screen.dart';
import 'package:dewdrop/src/features/friends/presentation/friends_screen.dart';
import 'package:dewdrop/src/features/groups/domain/group.dart';
import 'package:dewdrop/src/features/groups/presentation/group_screen.dart';
import 'package:dewdrop/src/features/home/presentation/home_screen.dart';
import 'package:dewdrop/src/features/settings/presentation/about_screen.dart';
import 'package:dewdrop/src/features/settings/presentation/legal_screen.dart';
import 'package:dewdrop/src/features/settings/presentation/settings_screen.dart';
import 'package:dewdrop/src/features/thoughts/presentation/send_thoughts_screen.dart';
import 'package:dewdrop/src/features/thoughts/presentation/thought_settings_screen.dart';
import 'package:dewdrop/src/features/thoughts/presentation/thoughts_screen.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final auth = ref.watch(authRepositoryProvider);
  // Owned here so they can be torn down when the provider is disposed/rebuilt
  // (e.g. authRepositoryProvider is invalidated). Without this, every rebuild
  // would leak the previous refresh-stream subscription and GoRouter instance.
  final refresh = GoRouterRefreshStream(auth.authStateChanges());
  final router = GoRouter(
    initialLocation: '/home',
    refreshListenable: refresh,
    redirect: (context, state) {
      final loggedIn = auth.currentSession != null;
      final loc = state.matchedLocation;
      // Auth routes reachable while logged out (the reset link itself reopens
      // the app *with* a recovery session, so it doesn't need to be here).
      const publicAuth = {'/sign-in', '/forgot-password'};
      if (!loggedIn) return publicAuth.contains(loc) ? null : '/sign-in';
      if (loc == '/sign-in') return '/home';
      return null;
    },
    routes: [
      GoRoute(path: '/sign-in', builder: (_, _) => const SignInScreen()),
      GoRoute(
        path: '/forgot-password',
        builder: (_, _) => const ForgotPasswordScreen(),
      ),
      GoRoute(
        path: '/reset-password',
        builder: (_, _) => const ResetPasswordScreen(),
      ),
      GoRoute(path: '/home', builder: (_, _) => const HomeGate()),
      GoRoute(path: '/send', builder: (_, _) => const SendThoughtsScreen()),
      GoRoute(path: '/friends', builder: (_, _) => const FriendsScreen()),
      GoRoute(
        path: '/group',
        builder: (_, state) => GroupScreen(group: state.extra as Group),
      ),
      GoRoute(path: '/thoughts', builder: (_, _) => const ThoughtsScreen()),
      GoRoute(
        path: '/thought-settings',
        builder: (_, _) => const ThoughtSettingsScreen(),
      ),
      GoRoute(path: '/settings', builder: (_, _) => const SettingsScreen()),
      GoRoute(path: '/about', builder: (_, _) => const AboutScreen()),
      GoRoute(path: '/legal', builder: (_, _) => const LegalScreen()),
    ],
  );
  ref.onDispose(() {
    router.dispose();
    refresh.dispose();
  });
  return router;
});

/// Bridges a [Stream] to a [Listenable] so GoRouter re-evaluates redirects when
/// the auth state changes.
class GoRouterRefreshStream extends ChangeNotifier {
  GoRouterRefreshStream(Stream<dynamic> stream) {
    notifyListeners();
    _sub = stream.asBroadcastStream().listen((_) => notifyListeners());
  }

  late final StreamSubscription<dynamic> _sub;

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}
