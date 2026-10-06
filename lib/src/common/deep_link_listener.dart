import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:dewdrop/src/common/deep_links.dart';

/// Listens for DewDrop's in-app deep links — invite links
/// (`dewdrop://invite?handle=…`), "send a pensée" links
/// (`dewdrop://send?to=…`) and the App Links of the other apps of the
/// container (`https://dewdrop.heianenterprise.com/jumeler.html#…`,
/// `…/rejoindre.html#code=…`) — both the one that cold-started the app and any
/// received while it runs, dispatching each to the matching handler.
///
/// It is the ONLY listener for those: Flutter's own deep linking is turned off
/// in the Android manifest (`flutter_deeplinking_enabled`), otherwise it would
/// also push `/jumeler.html` into GoRouter, which has no such route.
///
/// Auth deep links (login-callback, reset-password) are deliberately left to
/// supabase_flutter's own listener: this fires only on invite/send/twin/join
/// links, so the listeners coexist on the same `dewdrop://` scheme without
/// stepping on each other. A single URI resolves to at most one handler (tried
/// in that order), so two never both fire.
class DeepLinkListener {
  DeepLinkListener({
    required void Function(String handle) onInvite,
    required void Function(String handle) onSend,
    required void Function(Map<String, String> params) onTwin,
    required void Function(String code) onJoin,
  }) : _onInvite = onInvite,
       _onSend = onSend,
       _onTwin = onTwin,
       _onJoin = onJoin;

  final void Function(String handle) _onInvite;
  final void Function(String handle) _onSend;
  final void Function(Map<String, String> params) _onTwin;
  final void Function(String code) _onJoin;
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
    if (send != null) {
      _onSend(send);
      return;
    }
    final twin = DeepLinks.twinParams(uri);
    if (twin != null) {
      _onTwin(twin);
      return;
    }
    final join = DeepLinks.joinCode(uri);
    if (join != null) _onJoin(join);
  }

  void dispose() => _sub?.cancel();
}
