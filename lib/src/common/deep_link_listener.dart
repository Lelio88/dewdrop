import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:dewdrop/src/common/deep_links.dart';

/// Listens for DewDrop's in-app deep links — invite links
/// (`dewdrop://invite?handle=…`) and "send a pensée" links
/// (`dewdrop://send?to=…`) — both the one that cold-started the app and any
/// received while it runs, dispatching each to the matching handler.
///
/// Auth deep links (login-callback, reset-password) are deliberately left to
/// supabase_flutter's own listener: this fires only on invite/send links, so
/// the listeners coexist on the same `dewdrop://` scheme without stepping on
/// each other. A single URI resolves to at most one handler (invite is tried
/// first, then send), so the two never both fire.
class DeepLinkListener {
  DeepLinkListener({
    required void Function(String handle) onInvite,
    required void Function(String handle) onSend,
  }) : _onInvite = onInvite,
       _onSend = onSend;

  final void Function(String handle) _onInvite;
  final void Function(String handle) _onSend;
  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri>? _sub;

  Future<void> start() async {
    try {
      final initial = await _appLinks.getInitialLink();
      if (initial != null) _dispatch(initial);
    } on Exception catch (_) {
      // No initial link (or the platform channel isn't ready yet) — ignore and
      // still wire the live stream below so running-app links keep working.
    }
    _sub = _appLinks.uriLinkStream.listen(_dispatch);
  }

  void _dispatch(Uri uri) {
    final invite = DeepLinks.inviteHandle(uri);
    if (invite != null) {
      _onInvite(invite);
      return;
    }
    final send = DeepLinks.sendTarget(uri);
    if (send != null) _onSend(send);
  }

  void dispose() => _sub?.cancel();
}
