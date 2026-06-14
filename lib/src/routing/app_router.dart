import 'dart:async';

import 'package:dewdrop/src/features/auth/application/auth_providers.dart';
import 'package:dewdrop/src/features/auth/presentation/sign_in_screen.dart';
import 'package:dewdrop/src/features/friends/presentation/friends_screen.dart';
import 'package:dewdrop/src/features/home/presentation/home_screen.dart';
import 'package:dewdrop/src/features/thoughts/presentation/thoughts_screen.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final auth = ref.watch(authRepositoryProvider);
  return GoRouter(
    initialLocation: '/home',
    refreshListenable: GoRouterRefreshStream(auth.authStateChanges()),
    redirect: (context, state) {
      final loggedIn = auth.currentSession != null;
      final loggingIn = state.matchedLocation == '/sign-in';
      if (!loggedIn) return loggingIn ? null : '/sign-in';
      if (loggingIn) return '/home';
      return null;
    },
    routes: [
      GoRoute(path: '/sign-in', builder: (_, _) => const SignInScreen()),
      GoRoute(path: '/home', builder: (_, _) => const HomeGate()),
      GoRoute(path: '/friends', builder: (_, _) => const FriendsScreen()),
      GoRoute(path: '/thoughts', builder: (_, _) => const ThoughtsScreen()),
    ],
  );
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
