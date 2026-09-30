/// Maps a raw auth failure (Supabase `AuthException`, network `SocketException`/
/// `ClientException`, etc.) to a short, friendly French message for the UI.
///
/// Why text-based: a network failure often surfaces as an `AuthException` whose
/// `.message` is the raw `ClientException with SocketException...` string, so we
/// can't just show `e.message`. Matching on the message text is robust across
/// supabase_flutter versions (codes/status fields move around).
String authErrorMessage(Object error, {bool isSignUp = false}) {
  final text = error.toString().toLowerCase();
  bool has(String s) => text.contains(s);

  // Server unreachable / offline — the most common case in local dev.
  if (has('socketexception') ||
      has('clientexception') ||
      has('connection refused') ||
      has('connection closed') ||
      has('failed host lookup') ||
      has('handshakeexception') ||
      has('timeoutexception') ||
      has('timed out') ||
      has('network is unreachable') ||
      has('xmlhttprequest')) {
    return 'Connexion au serveur impossible. Vérifie ta connexion internet.';
  }

  // Wrong email / password.
  if (has('invalid login credentials') ||
      has('invalid_credentials') ||
      has('invalid credentials')) {
    return 'Email ou mot de passe incorrect.';
  }

  // Email not yet confirmed.
  if (has('email not confirmed') || has('email_not_confirmed')) {
    return 'Confirme ton adresse email avant de te connecter.';
  }

  // Google: the account is someone else's, or it's the last way in. GoTrue
  // gives the same code when the account is already the caller's own — only
  // « to another user » tells them apart (the repository absorbs that case;
  // this is the safety net against claiming it belongs to someone else).
  if (has('identity is already linked to another user')) {
    return 'Ce compte Google est déjà lié à un autre compte DewDrop.';
  }
  if (has('identity is already linked')) {
    return 'Ce compte Google est déjà lié à ton compte.';
  }
  if (has('identity_already_exists')) {
    return 'Ce compte Google est déjà lié à un autre compte DewDrop.';
  }
  if (has('single_identity_not_deletable')) {
    return "Impossible : c'est ton seul moyen de connexion.";
  }
  if (has('google_sign_in_failed') || has('manual_linking_disabled')) {
    return "La connexion avec Google n'a pas abouti. Réessaie.";
  }

  // No "account already exists" branch, on purpose: sign-up must never confirm
  // that an email is taken (guide C2). The repository answers a duplicate like
  // a new account (`blindSignUp`); a stray one falls to the generic message.

  // Sign-up / reset: weak password. Mirrors the server rule
  // (`minimum_password_length` + `password_requirements` in config.toml).
  if (has('password should be at least') ||
      has('password should contain') ||
      has('weak_password') ||
      has('weak password')) {
    return 'Mot de passe trop faible : 8 caractères minimum, '
        'avec des lettres et des chiffres.';
  }

  // Malformed email.
  if (has('invalid email') ||
      has('unable to validate email') ||
      has('validation_failed')) {
    return 'Adresse email invalide.';
  }

  // Too many attempts.
  if (has('over_request_rate_limit') || has('rate limit') || has('too many')) {
    return 'Trop de tentatives. Réessaie dans un instant.';
  }

  return isSignUp
      ? 'Impossible de créer le compte. Réessaie.'
      : 'Une erreur est survenue. Réessaie.';
}
