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

  static const String anonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH',
  );
}
