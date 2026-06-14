/// Supabase connection config.
///
/// Defaults point at the **local** Supabase stack (Docker). Override for other
/// environments with `--dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...`.
///
/// Note: on an Android emulator, `127.0.0.1` refers to the emulator itself —
/// use `http://10.0.2.2:54321` to reach the host's local Supabase.
class SupabaseConfig {
  const SupabaseConfig._();

  static const String url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'http://127.0.0.1:54321',
  );

  static const String anonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH',
  );
}
