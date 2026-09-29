/**
 * suppression-compte.js — Supprime un compte DewDrop depuis le web, sans l'app
 * (Google Play exige une URL de suppression pour toute app à comptes).
 *
 * Deux appels REST, sans bibliothèque : connexion par mot de passe (GoTrue),
 * puis la fonction `delete-account`, la même que l'app appelle. La fonction ne
 * supprime que le titulaire du jeton ; la base efface le reste en cascade.
 *
 * Choix non évidents :
 * - L'adresse du serveur et la clé publishable sont FIGÉES ici, jamais lues
 *   depuis l'URL de la page : un lien piégé enverrait sinon le mot de passe à
 *   un autre serveur. La clé publishable est publique par nature (elle est déjà
 *   dans l'APK) ; la sécurité repose sur la RLS et la fonction.
 * - Jetons en mémoire seulement (ni localStorage ni cookie) ; « Annuler » et la
 *   fermeture de la page révoquent la session côté serveur.
 * - GitHub Pages ne permet pas l'en-tête `frame-ancestors` : le script refuse
 *   de tourner dans un cadre (anti-clickjacking).
 * - Messages neutres (guide C2) : mauvais identifiants et adresse non
 *   confirmée donnent le même message, pour ne pas révéler quels e-mails ont
 *   un compte.
 *
 * Invariants :
 * - L'hôte de SUPABASE_URL figure dans le `connect-src` de la CSP de
 *   suppression-compte.html.
 * - La fonction `delete-account` autorise l'origine https://lelio88.github.io
 *   (CORS) ; changer d'hébergement = changer les deux.
 * - Nouvelle clé publishable (rotation) = mettre à jour SUPABASE_KEY ici.
 */
(function () {
  'use strict';

  const SUPABASE_URL = 'https://jjbmtheuhiijwqdgcvgr.supabase.co';
  const SUPABASE_KEY = 'sb_publishable_xvPsybMRRrfj8BF-uAfjsA_ZIQWll7F';
  const MOT_DE_CONFIRMATION = 'SUPPRIMER';

  const MESSAGES = {
    identifiants: "Connexion impossible : vérifie ton e-mail et ton mot de passe. " +
      "Un compte jamais confirmé ne peut pas se connecter : écris-nous pour le supprimer.",
    tropDEssais: 'Trop de tentatives. Réessaie dans quelques minutes.',
    reseau: 'Le serveur ne répond pas. Vérifie ta connexion, puis réessaie.',
    echec: "La suppression n'a pas abouti. Réessaie, ou écris-nous : on la fera à la main.",
    mot: 'Écris SUPPRIMER (en majuscules) pour confirmer.',
    vide: 'Renseigne ton e-mail et ton mot de passe.',
  };

  let session = null; // { accessToken, email } — en mémoire, jamais stockée

  const $ = (id) => document.getElementById(id);

  function statut(texte, erreur) {
    const el = $('statut');
    el.textContent = texte || '';
    el.classList.toggle('error', Boolean(erreur));
  }

  function afficher(etape) {
    for (const id of ['connexion', 'confirmation', 'termine']) {
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

  async function seConnecter(email, motDePasse) {
    const reponse = await appeler('/auth/v1/token?grant_type=password', {
      body: JSON.stringify({ email: email, password: motDePasse }),
      headers: {},
    });
    if (reponse.status === 429) throw new Error('tropDEssais');
    if (!reponse.ok) throw new Error('identifiants');
    const corps = await reponse.json();
    if (!corps.access_token) throw new Error('identifiants');
    return { accessToken: corps.access_token, email: (corps.user && corps.user.email) || email };
  }

  async function seDeconnecter() {
    if (!session) return;
    const jeton = session.accessToken;
    session = null;
    try {
      await appeler('/auth/v1/logout', { headers: { Authorization: 'Bearer ' + jeton }, keepalive: true });
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
      $('compte').textContent = session.email;
      afficher('confirmation');
      statut('');
      $('mot').focus();
    } catch (erreur) {
      statut(MESSAGES[erreur.message] || MESSAGES.reseau, true);
    } finally {
      occupe(form, false);
    }
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
    window.addEventListener('pagehide', seDeconnecter);
    afficher('connexion');
  }

  demarrer();
})();
