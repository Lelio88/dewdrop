import 'dart:io' show Platform;

import 'package:dewdrop/src/features/ambient/application/ambient_providers.dart'
    show sharedPreferencesProvider;
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Device-local opt-out of crash reports (Firebase Crashlytics).
///
/// Crash reports leave the phone for Google with an installation identifier.
/// They rest on legitimate interest (fixing what breaks for testers), which
/// keeps them **on by default** but gives the user a real way to refuse:
/// « Réglages → Rapports de plantage ». The privacy policy and the Play « Data
/// safety » form both describe them as optional — this switch is what makes
/// that true.
///
/// Invariants:
/// - `main()` reads [crashReportsEnabled] **before** enabling Crashlytics, so a
///   refusal holds from the very next launch, before anything can crash.
/// - Turning reports off also deletes the ones still waiting on the device.
/// - Debug builds never collect, whatever the switch says (see `main.dart`).
/// - Stored in SharedPreferences, like the parallax toggle: a per-device
///   choice, not profile data.
const kCrashReportsPref = 'crash_reports_enabled';

/// The stored choice; reports are on until the user turns them off.
bool crashReportsEnabled(SharedPreferences prefs) =>
    prefs.getBool(kCrashReportsPref) ?? true;

/// Applies the choice to Crashlytics. Mobile release builds only: desktop has
/// no Crashlytics backend, and debug never collects. Overridden in tests.
Future<void> applyCrashReporting(bool enabled) async {
  if (kDebugMode || !(Platform.isAndroid || Platform.isIOS)) return;
  final crashlytics = FirebaseCrashlytics.instance;
  await crashlytics.setCrashlyticsCollectionEnabled(enabled);
  if (!enabled) await crashlytics.deleteUnsentReports();
}

final crashReportingSinkProvider = Provider<Future<void> Function(bool)>(
  (ref) => applyCrashReporting,
);

class CrashReportsNotifier extends Notifier<bool> {
  @override
  bool build() => crashReportsEnabled(ref.watch(sharedPreferencesProvider));

  Future<void> set(bool enabled) async {
    state = enabled;
    await ref
        .read(sharedPreferencesProvider)
        .setBool(kCrashReportsPref, enabled);
    await ref.read(crashReportingSinkProvider)(enabled);
  }
}

final crashReportsProvider = NotifierProvider<CrashReportsNotifier, bool>(
  CrashReportsNotifier.new,
);
