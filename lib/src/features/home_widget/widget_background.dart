import 'package:dewdrop/src/common/app_exceptions.dart';
import 'package:dewdrop/src/features/home_widget/data/home_widget_gateway.dart';
import 'package:dewdrop/src/features/thoughts/data/thought_repository.dart';
import 'package:dewdrop/src/supabase/supabase_config.dart';
import 'package:home_widget/home_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Background isolate entry point for a widget tap.
///
/// What it does: when a friend circle on the home-screen widget is tapped, the
/// `home_widget` plugin runs THIS function in a fresh isolate (the app may be
/// closed). It re-inits Supabase (so the persisted session is reloaded), checks
/// an anti-double-send cooldown, and inserts a `thoughts` row — the same single
/// insert the in-app dock does; the push chain then fires server-side by trigger.
///
/// Why it imports `data/`: like `main.dart`, this is a composition-root-style
/// entry point that runs outside the `ProviderScope`, so it wires the concrete
/// repository directly rather than through a provider.
///
/// Invariants:
/// - Must be top-level + `@pragma('vm:entry-point')` or release tree-shaking
///   drops it and taps do nothing.
/// - Never throws out of here (no UI to surface an error to) — swallow & return.
/// - The `recipientId` query param + the `anonymous` widget-data key are the
///   contract written by [WidgetSyncService]; keep them in sync.

const Duration _kCooldown = Duration(seconds: 4);

bool _supabaseReady = false;

@pragma('vm:entry-point')
Future<void> dewDropWidgetBackgroundCallback(Uri? data) async {
  final recipientId = data?.queryParameters['recipientId'];
  if (data?.host != 'widget' || recipientId == null || !_isUuid(recipientId)) {
    return;
  }

  // Anti-double-send: claim the cooldown up-front so a rapid second broadcast
  // for the same friend is ignored before it can reach the insert.
  final prefs = await SharedPreferences.getInstance();
  final cdKey = 'widget_cd_$recipientId';
  final now = DateTime.now().millisecondsSinceEpoch;
  final last = prefs.getInt(cdKey) ?? 0;
  if (now - last < _kCooldown.inMilliseconds) return;
  await prefs.setInt(cdKey, now);

  final client = await _ensureSupabase();
  final session = client.auth.currentSession;
  if (session == null) {
    await prefs.remove(cdKey); // not signed in — don't burn the cooldown
    return;
  }
  // `Supabase.initialize` restores the session locally (so currentUser is set)
  // but refreshes the access token OFF the await path (supabase.dart fire-and-
  // forgets `recoverSession`). A tap after the token expired (~1h idle) would
  // otherwise insert with a stale JWT → 401 → silently swallowed below. Refresh
  // up-front so the tap actually sends; a dead refresh token = treat as logged
  // out (release the cooldown, no send).
  if (session.isExpired) {
    try {
      await client.auth.refreshSession();
    } on Object {
      await prefs.remove(cdKey);
      return;
    }
  }

  final anonymous =
      await HomeWidget.getWidgetData<bool>('anonymous', defaultValue: false) ??
      false;

  try {
    await SupabaseThoughtRepository(
      client,
    ).sendThought(recipientId, anonymous: anonymous);
    // Flash a ✓ on the tapped slot: the native widget reads sent_id/sent_at and
    // shows a brief confirmation, then schedules its own revert to the normal
    // circle. Best-effort — if these writes fail the send already succeeded.
    await HomeWidget.saveWidgetData<String>('sent_id', recipientId);
    // Stored as a String: epoch millis overflow a 32-bit int, and the plugin
    // routes small ints through putInt — getString/toLong is unambiguous.
    await HomeWidget.saveWidgetData<String>(
      'sent_at',
      DateTime.now().millisecondsSinceEpoch.toString(),
    );
    await HomeWidget.updateWidget(androidName: kAndroidWidgetProvider);
  } on RateLimitedException {
    // Best-effort from a headless isolate — nothing to surface, leave the
    // cooldown in place so the user naturally backs off.
  } on Object {
    // Headless isolate: no UI to surface an error, and an `Error` (not only an
    // `Exception` — e.g. an unexpected null) must NOT escape and crash the
    // background isolate. The cooldown still guards against a tap storm.
  }
}

/// Cheap UUID-shape check — rejects a forged/garbage `recipientId` before any
/// network round-trip (RLS remains the real authorization gate server-side).
bool _isUuid(String s) => _uuidRe.hasMatch(s);

final RegExp _uuidRe = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
  r'[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

/// Re-initialise Supabase inside the isolate (idempotent across reused isolates).
Future<SupabaseClient> _ensureSupabase() async {
  if (!_supabaseReady) {
    try {
      await Supabase.initialize(
        url: SupabaseConfig.url,
        publishableKey: SupabaseConfig.anonKey,
      );
    } on Object {
      // Already initialised in a reused background isolate — fine.
    }
    _supabaseReady = true;
  }
  return Supabase.instance.client;
}
