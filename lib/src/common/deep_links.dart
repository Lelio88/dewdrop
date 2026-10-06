/// Single source of truth for DewDrop's invite & auth deep links.
///
/// Invite links are **HTTPS** (`https://dewdrop.heianenterprise.com/invite.html?handle=…`)
/// so they are CLICKABLE in any messenger (SMS, WhatsApp, Instagram…) — a
/// custom-scheme `dewdrop://` link is rendered there as plain, un-tappable text,
/// and resolves only if the app is already installed. The HTTPS link opens a tiny
/// landing page (GitHub Pages under our own domain, `docs/invite.html`) offering
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
///
/// Les liens entre apps du conteneur ([twinPage], [joinPage]) sont, eux, de
/// vrais App Links vérifiés : HTTPS seulement, paramètres dans le fragment.
/// Leur forme suit `docs/liens-inter-apps.md` du dépôt méta et les pages
/// `docs/jumeler.html` / `docs/rejoindre.html`.
class DeepLinks {
  const DeepLinks._();

  static const String scheme = 'dewdrop';

  /// Host serving our web pages: GitHub Pages under our own domain
  /// (`docs/CNAME`, DNS in Cloudflare). The invite landing page and the legal
  /// pages live there.
  static const String webHost = 'dewdrop.heianenterprise.com';

  /// Where the pages lived before the move (`lelio88.github.io/dewdrop/`).
  /// GitHub redirects it, and invite links and QR codes shared back then still
  /// carry it — [inviteHandle] keeps accepting them.
  static const String legacyWebHost = 'lelio88.github.io';

  /// Base URL of the hosted site (GitHub Pages serves `docs/` at its root).
  static const String webBase = 'https://$webHost';

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

  /// Page de jumelage avec un groupe d'une autre app du conteneur (Agora,
  /// Arpente) : `jumeler.html#de=…&code=…&etat=…` (protocole commun,
  /// `docs/liens-inter-apps.md` du dépôt méta). Ouverte par un App Link
  /// vérifié (`docs/.well-known/assetlinks.json`) ; sans l'app, la page de
  /// `docs/` explique quoi faire.
  static final Uri twinPage = Uri.parse('$webBase/jumeler.html');

  /// Page qui fait demander à entrer dans un cercle par le code d'un jumeau :
  /// `rejoindre.html#code=CODE`. Mêmes règles que [twinPage].
  static final Uri joinPage = Uri.parse('$webBase/rejoindre.html');

  /// Même format que `dewdropCodePattern` (feature groups) : 8 caractères,
  /// alphabet sans 0/O ni 1/I.
  static final _joinCode = RegExp(r'^[A-HJ-NP-Z2-9]{8}$');

  static bool _isOurPage(Uri uri, Uri page) =>
      uri.scheme == 'https' && uri.host == webHost && uri.path == page.path;

  /// Les paramètres d'un lien [twinPage], lus dans le **fragment** seulement
  /// (un code n'y voyage jamais en requête : elle finirait dans les journaux
  /// de l'hébergeur) ; `null` si [uri] n'est pas cette page. Leur validation
  /// est l'affaire de `parseTwinLink`.
  static Map<String, String>? twinParams(Uri uri) {
    if (!_isOurPage(uri, twinPage)) return null;
    return uri.fragment.isEmpty ? const {} : Uri.splitQueryString(uri.fragment);
  }

  /// Le code (en majuscules, format vérifié) d'un lien [joinPage], ou `null`.
  static String? joinCode(Uri uri) {
    if (!_isOurPage(uri, joinPage) || uri.fragment.isEmpty) return null;
    final code = Uri.splitQueryString(
      uri.fragment,
    )['code']?.trim().toUpperCase();
    return (code != null && _joinCode.hasMatch(code)) ? code : null;
  }

  /// Extracts the handle from an invite deep link — accepting BOTH the HTTPS web
  /// link and the `dewdrop://invite` custom scheme — or null if [uri] is neither
  /// (e.g. an auth callback, which is supabase_flutter's job, not ours).
  static String? inviteHandle(Uri uri) {
    final isScheme = uri.scheme == scheme && uri.host == inviteHost;
    final onOurSite =
        uri.host == webHost ||
        (uri.host == legacyWebHost && uri.path.startsWith('/dewdrop/'));
    final isWeb =
        uri.scheme == 'https' && onOurSite && uri.path.endsWith('/invite.html');
    if (!isScheme && !isWeb) return null;
    final h = uri.queryParameters['handle']?.trim().replaceAll('@', '');
    return (h == null || h.isEmpty) ? null : h;
  }
}
