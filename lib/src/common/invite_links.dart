import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:dewdrop/src/common/deep_links.dart';

/// Listens for invite deep links (`dewdrop://invite?handle=...`), both the one
/// that cold-started the app and any received while it's running, and hands the
/// extracted handle to [_onHandle].
///
/// Auth deep links (login-callback, reset-password) are deliberately left to
/// supabase_flutter's own listener — this only fires on invite links, so the
/// two coexist on the same scheme without stepping on each other.
class InviteLinkListener {
  InviteLinkListener(this._onHandle);

  final void Function(String handle) _onHandle;
  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri>? _sub;

  Future<void> start() async {
    final initial = await _appLinks.getInitialLink();
    if (initial != null) _dispatch(initial);
    _sub = _appLinks.uriLinkStream.listen(_dispatch);
  }

  void _dispatch(Uri uri) {
    final handle = DeepLinks.inviteHandle(uri);
    if (handle != null) _onHandle(handle);
  }

  void dispose() => _sub?.cancel();
}
