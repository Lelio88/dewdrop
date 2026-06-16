/// Single source of truth for DewDrop's custom-scheme deep links.
///
/// We use a custom URL scheme (`dewdrop://`) rather than HTTPS App/Universal
/// Links: the app isn't on a domain we own, and a custom scheme needs zero
/// hosting (no `.well-known/assetlinks.json`) to route a link into the app.
/// The trade-off — a custom-scheme link only resolves when the app is already
/// installed — is acceptable here (in-person invites use the QR flow instead).
///
/// Two of these hosts are consumed by `supabase_flutter`'s built-in deep-link
/// handler (it carries the PKCE `code` for us): [loginCallback] is the redirect
/// for sign-up confirmation emails, [resetPassword] for password-reset emails.
/// They MUST be allow-listed in Supabase auth config (`site_url` /
/// `additional_redirect_urls`) or Supabase refuses the redirect. [invite] is
/// ours alone — Supabase ignores it (no auth params) and our own `app_links`
/// listener turns it into a friend request.
class DeepLinks {
  const DeepLinks._();

  static const String scheme = 'dewdrop';

  /// Redirect for sign-up confirmation emails → opens the app signed-in.
  static const String loginCallback = '$scheme://login-callback';

  /// Redirect for password-reset emails → opens the app in recovery mode.
  static const String resetPassword = '$scheme://reset-password';

  /// Host of an invite link. Full link: `dewdrop://invite?handle=<handle>`.
  static const String inviteHost = 'invite';

  /// Builds a shareable invite link for [handle].
  static String invite(String handle) => '$scheme://$inviteHost?handle=$handle';

  /// Extracts the handle from an invite deep link, or null if [uri] is not one
  /// (e.g. an auth callback, which is supabase_flutter's job, not ours).
  static String? inviteHandle(Uri uri) {
    if (uri.scheme != scheme || uri.host != inviteHost) return null;
    final h = uri.queryParameters['handle']?.trim().replaceAll('@', '');
    return (h == null || h.isEmpty) ? null : h;
  }
}
