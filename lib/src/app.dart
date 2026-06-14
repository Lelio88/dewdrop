import 'dart:io' show Platform;

import 'package:dewdrop/src/features/auth/application/auth_providers.dart';
import 'package:dewdrop/src/features/notifications/application/push_providers.dart';
import 'package:dewdrop/src/routing/app_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class DewDropApp extends ConsumerWidget {
  const DewDropApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Register this device for push whenever a session becomes available
    // (mobile only — desktop has no FCM).
    if (Platform.isAndroid || Platform.isIOS) {
      ref.listen(authStateChangesProvider, (_, next) {
        final session = next.value?.session;
        if (session != null) {
          ref.read(pushServiceProvider).register(session.user.id);
        }
      });
    }

    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'DewDrop',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      routerConfig: router,
    );
  }
}
