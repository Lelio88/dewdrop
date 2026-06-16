import 'dart:io' show Platform;
import 'dart:ui' show PlatformDispatcher;

import 'package:dewdrop/src/app.dart';
import 'package:dewdrop/src/common/provider_error_logger.dart';
import 'package:dewdrop/src/features/ambient/application/ambient_providers.dart';
import 'package:dewdrop/src/features/notifications/application/notification_channels.dart';
import 'package:dewdrop/src/supabase/supabase_config.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Background isolate handler. FCM renders "notification" messages in the system
/// tray automatically; this exists so background delivery is wired (and as a
/// hook for future data-only messages).
@pragma('vm:entry-point')
Future<void> _firebaseBackgroundHandler(RemoteMessage message) async {}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Firebase/FCM is mobile-only here; desktop (decor dev) skips it so it never
  // fails to init without a native Firebase config.
  if (Platform.isAndroid || Platform.isIOS) {
    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(_firebaseBackgroundHandler);
    await ensureThoughtsChannel();
    // Crash reporting (mobile-only — Crashlytics has no desktop backend).
    // Route both uncaught Flutter framework errors and uncaught async errors
    // (zone errors outside the widget tree) to Crashlytics so a crash on the
    // user's phone surfaces in the console instead of vanishing silently.
    FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
    PlatformDispatcher.instance.onError = (error, stack) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      return true;
    };
  }
  await Supabase.initialize(
    url: SupabaseConfig.url,
    publishableKey: SupabaseConfig.anonKey,
  );
  final prefs = await SharedPreferences.getInstance();
  runApp(
    ProviderScope(
      observers: const [ProviderErrorLogger()],
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: const DewDropApp(),
    ),
  );
}
