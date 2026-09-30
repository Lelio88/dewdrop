import 'dart:io' show Platform;

import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthException;

/// OAuth client id of DewDrop's **Web** client (Google Cloud project
/// `dewdrop-60229`, « DewDrop – Web »). Public by nature — it ships inside the
/// APK — it is the audience Supabase checks on every Google ID token, so it
/// must match `[auth.external.google].client_id` in `supabase/config.toml` and
/// `GOOGLE_CLIENT_ID` in `docs/suppression-compte.js`. Its secret, unused (no
/// redirect flow), is kept in `../.dewdrop-secrets/google-oauth.env`.
/// A compile-time constant rather than a `--dart-define`: a build that forgot
/// the define would compile fine and silently lose Google sign-in.
/// Empty = Google sign-in hidden everywhere.
const String kGoogleWebClientId =
    '515627278707-lppcora09kmh4c9hljbbhku309o4utfe.apps.googleusercontent.com';

/// Where Google ID tokens come from — the native account picker in the app,
/// a fake in tests.
abstract interface class GoogleIdTokenSource {
  /// Whether the picker can be shown on this device.
  bool get isAvailable;

  /// Shows the account picker; resolves the ID token of the picked account,
  /// or `null` when the user dismisses it. Any other failure throws an
  /// [AuthException] with code `google_sign_in_failed`.
  Future<String?> pickAccount();

  /// Forgets the picked account on this device, so the next sign-in shows the
  /// picker again instead of silently reusing it. [revoke] also withdraws the
  /// app's Google grant (account deletion).
  Future<void> forget({bool revoke = false});
}

/// The native picker (`google_sign_in` 7: Credential Manager on Android).
///
/// Choices:
/// - Android only for now: iOS needs its own client id, and the iOS build is
///   blocked on the Apple Developer account anyway (App Store rule 4.8 would
///   then also require « Se connecter avec Apple »).
/// - No nonce: without one on either side Supabase has nothing to compare, and
///   the token stays bound to our client id and short-lived.
/// - `initialize` runs once per process (the plugin requires it), lazily, so an
///   app that never touches Google never loads it.
class NativeGoogleIdTokenSource implements GoogleIdTokenSource {
  NativeGoogleIdTokenSource({required this.serverClientId});

  final String serverClientId;
  Future<void>? _ready;

  @override
  bool get isAvailable => serverClientId.isNotEmpty && Platform.isAndroid;

  Future<void> _init() => _ready ??= GoogleSignIn.instance
      .initialize(serverClientId: serverClientId)
      .catchError((Object e) {
        _ready = null; // let a later attempt retry the initialisation
        throw e;
      });

  @override
  Future<String?> pickAccount() async {
    try {
      await _init();
      final account = await GoogleSignIn.instance.authenticate();
      final token = account.authentication.idToken;
      if (token == null) {
        throw const GoogleSignInException(
          code: GoogleSignInExceptionCode.unknownError,
          description: 'no ID token',
        );
      }
      return token;
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) return null;
      throw AuthException(
        'Google sign-in failed: ${e.code.name}',
        code: 'google_sign_in_failed',
      );
    }
  }

  @override
  Future<void> forget({bool revoke = false}) async {
    if (!isAvailable) return;
    try {
      await _init();
      if (revoke) {
        await GoogleSignIn.instance.disconnect();
      } else {
        await GoogleSignIn.instance.signOut();
      }
    } on Exception {
      // Nothing picked on this device, or no network: nothing to forget.
    }
  }
}
