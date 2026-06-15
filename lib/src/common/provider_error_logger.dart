import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Logs every provider failure once, so async errors that flow through the app
/// (a failed profile / friends / received-thoughts fetch, a mutation that
/// throws) are never *silently* swallowed. Wired into `ProviderScope.observers`
/// at the composition root.
///
/// Console-only for now (`debugPrint`, stripped in release). Swap the body for
/// Sentry/Crashlytics when there's a backend for it. `ProviderObserver` is an
/// `abstract base class`, hence the `final` subclass.
final class ProviderErrorLogger extends ProviderObserver {
  const ProviderErrorLogger();

  @override
  void providerDidFail(
    ProviderObserverContext context,
    Object error,
    StackTrace stackTrace,
  ) {
    debugPrint('[provider error] ${context.provider}: $error');
  }
}
