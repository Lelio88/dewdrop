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

  // Sign-up: account already exists.
  if (has('already registered') ||
      has('already been registered') ||
      has('user_already_exists') ||
      has('user already registered')) {
    return 'Un compte existe déjà avec cet email.';
  }

  // Sign-up: weak / too-short password.
  if (has('password should be at least') ||
      has('weak_password') ||
      has('weak password')) {
    return 'Mot de passe trop court (6 caractères minimum).';
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
