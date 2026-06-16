import 'dart:io' show Platform;

import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Logs every provider failure once, so async errors that flow through the app
/// (a failed profile / friends / received-thoughts fetch, a mutation that
/// throws) are never *silently* swallowed. Wired into `ProviderScope.observers`
/// at the composition root.
///
/// Two sinks: `debugPrint` (stripped in release, useful for desktop decor dev)
/// and Crashlytics as a *non-fatal* report on mobile. The platform guard is
/// load-bearing — Crashlytics has no desktop backend and `Firebase` is only
/// initialised on Android/iOS (see `main.dart`), so calling it elsewhere would
/// itself throw. `ProviderObserver` is an `abstract base class`, hence `final`.
final class ProviderErrorLogger extends ProviderObserver {
  const ProviderErrorLogger();

  @override
  void providerDidFail(
    ProviderObserverContext context,
    Object error,
    StackTrace stackTrace,
  ) {
    debugPrint('[provider error] ${context.provider}: $error');
    if (Platform.isAndroid || Platform.isIOS) {
      FirebaseCrashlytics.instance.recordError(
        error,
        stackTrace,
        reason: 'provider ${context.provider}',
        fatal: false,
      );
    }
  }
}
