import 'package:flutter/foundation.dart';

/// Supabase connection config.
///
/// For non-local environments, override with
/// `--dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...`.
///
/// When no override is given we point at the **local** Supabase stack (Docker).
/// The Android emulator reaches the host machine via `10.0.2.2` (its own
/// `127.0.0.1` is the emulator itself), so we swap the host automatically — the
/// emulator then connects to local Supabase with no extra flags.
class SupabaseConfig {
  const SupabaseConfig._();

  static const String _urlOverride = String.fromEnvironment('SUPABASE_URL');

  static String get url {
    if (_urlOverride.isNotEmpty) return _urlOverride;
    final host = !kIsWeb && defaultTargetPlatform == TargetPlatform.android
        ? '10.0.2.2'
        : '127.0.0.1';
    return 'http://$host:54321';
  }

  /// The anon/publishable key of the **local** Supabase stack — the default when
  /// no override is passed. It is NOT the cloud key: building with a remote URL
  /// but this default makes every request 401 (see [assertConsistent]).
  static const String _localDefaultAnonKey =
      'sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH';

  static const String anonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: _localDefaultAnonKey,
  );

  /// Fail fast on the classic build mistake: a **remote** (https) URL paired
  /// with the **local** default anon key — which makes every Supabase call
  /// return `401 Invalid API key`, visible only as a generic runtime error.
  /// Call once at startup, before [Supabase.initialize].
  ///
  /// No secret is referenced: the anon key is public (security comes from RLS,
  /// not from hiding this key), and the thrown message never prints a key value.
  static void assertConsistent() {
    final isRemote = url.startsWith('https://');
    if (isRemote && anonKey == _localDefaultAnonKey) {
      throw StateError(
        'Supabase config error: the remote URL ($url) is paired with the LOCAL '
        'default anon key. Build with '
        '--dart-define=SUPABASE_ANON_KEY=<your cloud publishable key>.',
      );
    }
  }
}
