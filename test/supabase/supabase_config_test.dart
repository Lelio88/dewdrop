import 'package:dewdrop/src/supabase/supabase_config.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Note: these assume no --dart-define=SUPABASE_URL (the dev default), which is
  // the case under `flutter test`.
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test('Android uses 10.0.2.2 (the emulator reaches the host there)', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(SupabaseConfig.url, 'http://10.0.2.2:54321');
  });

  test('non-Android keeps 127.0.0.1', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    expect(SupabaseConfig.url, 'http://127.0.0.1:54321');
  });

  test('the anon key is configured (non-empty)', () {
    expect(SupabaseConfig.anonKey, isNotEmpty);
  });
}
