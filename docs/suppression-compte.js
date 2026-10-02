/**
 * suppression-compte.js — Supprime un compte DewDrop depuis le web, sans l'app
 * (Google Play exige une URL de suppression pour toute app à comptes).
 *
 * Deux appels REST, sans bibliothèque : connexion (mot de passe, ou jeton
 * d'identité Google), puis la fonction `delete-account`, la même que l'app
 * appelle. La fonction ne supprime que le titulaire du jeton ; la
 * base efface le reste en cascade.
 *
 * Choix non évidents :
 * - L'adresse du serveur et la clé publishable sont FIGÉES ici, jamais lues
 *   depuis l'URL de la page : un lien piégé enverrait sinon le mot de passe à
 *   un autre serveur. La clé publishable est publique par nature (elle est déjà
 *   dans l'APK) ; la sécurité repose sur la RLS et la fonction.
 * - Jetons en mémoire seulement (ni localStorage ni cookie) ; « Annuler » et la
 *   fermeture de la page révoquent la session côté serveur — **celle de la page
 *   seule** (`/logout?scope=local`). Sans paramètre, GoTrue révoque toutes les
 *   sessions du compte : se connecter ici puis renoncer déconnectait aussi le
 *   téléphone.
 * - Google : le script officiel (Google Identity Services) n'est chargé qu'au
 *   clic sur « Continuer avec Google », jamais pour un simple visiteur. Il
 *   remplace notre bouton par le sien, qui rend un jeton d'identité échangé
 *   auprès de Supabase (grant `id_token`) : ni redirection ni secret Google
 *   côté Supabase, et aucun domaine supabase.co à déclarer chez Google.
 * - Un compte Google sans compte DewDrop en crée un à la connexion (Supabase n'a
 *   pas d'interrupteur d'inscription par fournisseur) : la page le détecte (créé
 *   par cette connexion même) et le supprime aussitôt, sans rien garder.
 * - GitHub Pages ne permet pas l'en-tête `frame-ancestors` : le script refuse
 *   de tourner dans un cadre (anti-clickjacking).
 * - Messages neutres (guide C2) : mauvais identifiants et adresse non
 *   confirmée donnent le même message, pour ne pas révéler quels e-mails ont
 *   un compte.
 *
 * Invariants :
 * - L'hôte de SUPABASE_URL figure dans le `connect-src` de la CSP de
 *   suppression-compte.html.
 * - La fonction `delete-account` autorise l'origine
 *   https://dewdrop.heianenterprise.com (CORS), qui est aussi l'« origine
 *   JavaScript autorisée » du client Web Google ; changer d'hébergement =
 *   changer les deux, plus la CSP.
 * - GOOGLE_CLIENT_ID = `kGoogleWebClientId` de l'app = `client_id` de
 *   `[auth.external.google]` (config.toml).
 * - Nouvelle clé publishable (rotation) = mettre à jour SUPABASE_KEY ici.
 */
(function () {
  'use strict';

  const SUPABASE_URL = 'https://jjbmtheuhiijwqdgcvgr.supabase.co';
  const SUPABASE_KEY = 'sb_publishable_xvPsybMRRrfj8BF-uAfjsA_ZIQWll7F';
  const GOOGLE_CLIENT_ID = '515627278707-lppcora09kmh4c9hljbbhku309o4utfe.apps.googleusercontent.com';
  const SCRIPT_GOOGLE = 'https://accounts.google.com/gsi/client';
  const MOT_DE_CONFIRMATION = 'SUPPRIMER';
  // Écart maximal entre création et connexion pour un compte que la connexion
  // Google vient elle-même de créer.
  const COMPTE_NEUF_MS = 10 * 1000;

  const MESSAGES = {
    identifiants: "Connexion impossible : vérifie ton e-mail et ton mot de passe. " +
      "Un compte jamais confirmé ne peut pas se connecter : écris-nous pour le supprimer.",
    tropDEssais: 'Trop de tentatives. Réessaie dans quelques minutes.',
    reseau: 'Le serveur ne répond pas. Vérifie ta connexion, puis réessaie.',
    echec: "La suppression n'a pas abouti. Réessaie, ou écris-nous : on la fera à la main.",
    mot: 'Écris SUPPRIMER (en majuscules) pour confirmer.',
    vide: 'Renseigne ton e-mail et ton mot de passe.',
    google: "La connexion avec Google n'a pas abouti. Réessaie.",
  };

  let session = null; // { accessToken, email } — en mémoire, jamais stockée

  const $ = (id) => document.getElementById(id);

  function statut(texte, erreur) {
    const el = $('statut');
    el.textContent = texte || '';
    el.classList.toggle('error', Boolean(erreur));
  }

  function afficher(etape) {
    for (const id of ['connexion', 'confirmation', 'termine', 'rien']) {
      $(id).hidden = id !== etape;
    }
  }

  function occupe(form, oui) {
    for (const bouton of form.querySelectorAll('button')) bouton.disabled = oui;
  }

  async function appeler(chemin, options) {
    const reponse = await fetch(SUPABASE_URL + chemin, {
      method: 'POST',
      credentials: 'omit',
      cache: 'no-store',
      ...options,
      headers: { apikey: SUPABASE_KEY, 'Content-Type': 'application/json', ...options.headers },
    });
    return reponse;
  }

  async function ouvrirSession(chemin, corpsRequete, erreur) {
    const reponse = await appeler(chemin, { body: JSON.stringify(corpsRequete), headers: {} });
    if (reponse.status === 429) throw new Error('tropDEssais');
    if (!reponse.ok) throw new Error(erreur);
    const corps = await reponse.json();
    if (!corps.access_token) throw new Error(erreur);
    const user = corps.user || {};
    return {
      accessToken: corps.access_token,
      email: user.email || corpsRequete.email || '',
      neuf: Date.parse(user.last_sign_in_at) - Date.parse(user.created_at) < COMPTE_NEUF_MS,
    };
  }

  function seConnecter(email, motDePasse) {
    return ouvrirSession('/auth/v1/token?grant_type=password',
      { email: email, password: motDePasse }, 'identifiants');
  }

  async function seDeconnecter() {
    if (!session) return;
    const jeton = session.accessToken;
    session = null;
    try {
      await appeler('/auth/v1/logout?scope=local', { headers: { Authorization: 'Bearer ' + jeton }, keepalive: true });
    } catch (_) {
      // Le jeton d'accès expire seul au bout d'une heure ; rien d'autre à faire.
    }
  }

  async function supprimer() {
    const reponse = await appeler('/functions/v1/delete-account', {
      headers: { Authorization: 'Bearer ' + session.accessToken },
      body: '{}',
    });
    if (!reponse.ok) throw new Error('echec');
  }

  function chargerGoogle() {
    return new Promise((resoudre, rejeter) => {
      if (window.google && window.google.accounts) {
        resoudre();
        return;
      }
      const script = document.createElement('script');
      script.src = SCRIPT_GOOGLE;
      script.async = true;
      script.onload = () => resoudre();
      script.onerror = () => rejeter(new Error('google'));
      document.head.appendChild(script);
    });
  }

  /** Au clic : charge le bouton officiel de Google à la place du nôtre. */
  async function versGoogle() {
    const bouton = $('google');
    bouton.disabled = true;
    statut('Chargement du bouton Google…');
    try {
      await chargerGoogle();
    } catch (_) {
      bouton.disabled = false;
      statut(MESSAGES.google, true);
      return;
    }
    window.google.accounts.id.initialize({
      client_id: GOOGLE_CLIENT_ID,
      callback: surJetonGoogle,
      ux_mode: 'popup',
      auto_select: false,
      use_fedcm_for_prompt: true,
    });
    bouton.hidden = true;
    window.google.accounts.id.renderButton($('google-officiel'), {
      type: 'standard',
      theme: 'outline',
      size: 'large',
      text: 'continue_with',
      shape: 'rectangular',
      locale: 'fr',
    });
    // Le sélecteur de compte du navigateur (FedCM) s'ouvre aussitôt : il ne
    // reste qu'à choisir son compte, au lieu de recliquer sur un bouton
    // identique au nôtre. S'il ne s'ouvre pas (aucun compte Google connecté,
    // sélecteur refermé peu avant), le bouton officiel reste là.
    window.google.accounts.id.prompt();
    statut("Choisis ton compte Google dans la fenêtre qui s'ouvre, ou avec le bouton ci-dessus.");
  }

  /** Jeton d'identité rendu par Google : l'échange contre une session. */
  async function surJetonGoogle(reponse) {
    if (!reponse || !reponse.credential) {
      statut(MESSAGES.google, true);
      return;
    }
    statut('Connexion…');
    try {
      session = await ouvrirSession('/auth/v1/token?grant_type=id_token',
        { provider: 'google', id_token: reponse.credential }, 'google');
    } catch (erreur) {
      statut(MESSAGES[erreur.message] || MESSAGES.reseau, true);
      return;
    }
    if (session.neuf) {
      // Aucun compte DewDrop derrière ce compte Google : la connexion vient d'en
      // créer un, qu'on efface aussitôt pour ne rien garder.
      try {
        await supprimer();
        session = null;
        afficher('rien');
        statut('');
      } catch (_) {
        statut(MESSAGES.echec, true);
      }
      return;
    }
    montrerConfirmation();
  }

  async function surConnexion(evenement) {
    evenement.preventDefault();
    const form = evenement.currentTarget;
    const email = $('email').value.trim();
    const motDePasse = $('password').value;
    if (!email || !motDePasse) {
      statut(MESSAGES.vide, true);
      return;
    }
    occupe(form, true);
    statut('Connexion…');
    try {
      session = await seConnecter(email, motDePasse);
      $('password').value = '';
      montrerConfirmation();
    } catch (erreur) {
      statut(MESSAGES[erreur.message] || MESSAGES.reseau, true);
    } finally {
      occupe(form, false);
    }
  }

  function montrerConfirmation() {
    $('compte').textContent = session.email;
    afficher('confirmation');
    statut('');
    $('mot').focus();
  }

  async function surConfirmation(evenement) {
    evenement.preventDefault();
    const form = evenement.currentTarget;
    if ($('mot').value.trim() !== MOT_DE_CONFIRMATION) {
      statut(MESSAGES.mot, true);
      return;
    }
    occupe(form, true);
    statut('Suppression…');
    try {
      await supprimer();
      session = null; // le compte n'existe plus : sa session non plus
      afficher('termine');
      statut('');
    } catch (erreur) {
      statut(MESSAGES[erreur.message] || MESSAGES.reseau, true);
    } finally {
      occupe(form, false);
    }
  }

  async function surAnnulation() {
    await seDeconnecter();
    $('mot').value = '';
    afficher('connexion');
    statut('Déconnecté·e. Ton compte n\'a pas été supprimé.');
  }

  function demarrer() {
    if (window.top !== window.self) {
      statut("Cette page ne peut pas s'ouvrir dans un cadre. Ouvre-la directement.", true);
      return;
    }
    $('connexion').addEventListener('submit', surConnexion);
    $('confirmation').addEventListener('submit', surConfirmation);
    $('annuler').addEventListener('click', surAnnulation);
    $('google').addEventListener('click', versGoogle);
    window.addEventListener('pagehide', seDeconnecter);
    afficher('connexion');
  }

  demarrer();
})();
