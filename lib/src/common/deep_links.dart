/// Single source of truth for DewDrop's invite & auth deep links.
///
/// Invite links are **HTTPS** (`https://lelio88.github.io/dewdrop/invite.html?handle=…`)
/// so they are CLICKABLE in any messenger (SMS, WhatsApp, Instagram…) — a
/// custom-scheme `dewdrop://` link is rendered there as plain, un-tappable text,
/// and resolves only if the app is already installed. The HTTPS link opens a tiny
/// landing page (hosted on our GitHub Pages, `docs/invite.html`) offering
/// « Ouvrir dans DewDrop » (→ the [inviteScheme] custom link, which the app's
/// `app_links` listener turns into a friend request) and « Installer » (Play
/// Store) — so it works whether or not the app is already installed.
///
/// Auth callbacks ([loginCallback], [resetPassword]) stay on the custom scheme:
/// they are consumed by `supabase_flutter`'s built-in deep-link handler (it
/// carries the PKCE `code`) and MUST be allow-listed in Supabase auth config
/// (`site_url` / `additional_redirect_urls`).
///
/// [inviteHandle] accepts BOTH the HTTPS link and the custom scheme, so a handle
/// resolves whether it arrives via the landing-page hand-off or (future) an
/// Android App Link. Mirror any change to the link shape in `docs/invite.html`.
class DeepLinks {
  const DeepLinks._();

  static const String scheme = 'dewdrop';

  /// Host serving our GitHub Pages site (the invite landing page lives there).
  static const String webHost = 'lelio88.github.io';

  /// Base URL of the hosted site (GitHub Pages serves `docs/` at this path).
  static const String webBase = 'https://$webHost/dewdrop';

  /// Redirect for sign-up confirmation emails → opens the app signed-in.
  static const String loginCallback = '$scheme://login-callback';

  /// Redirect for password-reset emails → opens the app in recovery mode.
  static const String resetPassword = '$scheme://reset-password';

  /// Host of the custom-scheme invite link (`dewdrop://invite?handle=…`), used by
  /// the landing page's « Ouvrir dans DewDrop » button.
  static const String inviteHost = 'invite';

  /// The shareable invite link for [handle] — an HTTPS link that is clickable
  /// everywhere and falls back to the Play Store when the app isn't installed.
  static String invite(String handle) => '$webBase/invite.html?handle=$handle';

  /// The custom-scheme hand-off link the landing page opens to enter the app.
  static String inviteScheme(String handle) =>
      '$scheme://$inviteHost?handle=$handle';

  /// Host of the custom-scheme "send a pensée" link
  /// (`dewdrop://send?to=<handle>`). It is the on-device hook a user wires to a
  /// voice routine ("Ok Google, envoie une pensée à Lélio") today, and the seam
  /// the future Gemini AppFunction reuses — opening a one-tap confirm to send a
  /// pensée to that friend. Custom-scheme only (the app must be installed); no
  /// HTTPS variant, unlike invites, since there is nothing to land on.
  static const String sendHost = 'send';

  /// The custom-scheme link asking the app to send a pensée to [handle].
  static String sendTo(String handle) => '$scheme://$sendHost?to=$handle';

  /// Extracts the recipient handle from a `dewdrop://send?to=<handle>` link, or
  /// null if [uri] is not one (an invite or an auth callback).
  static String? sendTarget(Uri uri) {
    if (uri.scheme != scheme || uri.host != sendHost) return null;
    final h = uri.queryParameters['to']?.trim().replaceAll('@', '');
    return (h == null || h.isEmpty) ? null : h;
  }

  /// Extracts the handle from an invite deep link — accepting BOTH the HTTPS web
  /// link and the `dewdrop://invite` custom scheme — or null if [uri] is neither
  /// (e.g. an auth callback, which is supabase_flutter's job, not ours).
  static String? inviteHandle(Uri uri) {
    final isScheme = uri.scheme == scheme && uri.host == inviteHost;
    final isWeb =
        uri.scheme == 'https' &&
        uri.host == webHost &&
        uri.path.endsWith('/invite.html');
    if (!isScheme && !isWeb) return null;
    final h = uri.queryParameters['handle']?.trim().replaceAll('@', '');
    return (h == null || h.isEmpty) ? null : h;
  }
}
