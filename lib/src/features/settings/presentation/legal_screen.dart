import 'package:flutter/material.dart';

/// "Confidentialité & CGU" — the privacy policy and terms, surfaced in-app and
/// reachable from « À propos & crédits ». The text describes DewDrop's actual
/// data practices (email + handle, friends, thoughts as a contentless signal,
/// FCM token; Supabase + Firebase as processors; no ads/tracking/resale).
///
/// IMPORTANT (not user-facing): this is a sound starting draft, not legal
/// advice — have it reviewed before a public store release. A public copy is
/// hosted via GitHub Pages (`docs/index.html`) for the store listing; keep the
/// two in sync (same `_updated`, same `_contact`, same text).
class LegalScreen extends StatelessWidget {
  const LegalScreen({super.key});

  /// Update when the text changes. Keep in sync with the hosted copy.
  static const String _updated = 'juin 2026';

  static const String _contact = 'heianenterpriseyt@gmail.com';

  @override
  Widget build(BuildContext context) {
    final w = Colors.white;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('Confidentialité & CGU'),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF12162A), Color(0xFF06070E)],
          ),
        ),
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: [
              Text('Dernière mise à jour : $_updated',
                  style: TextStyle(color: w.withValues(alpha: 0.45), fontSize: 12)),
              const SizedBox(height: 20),

              _h(w, 'Politique de confidentialité'),
              _p(w,
                  'DewDrop te permet d\'envoyer un signal « j\'ai pensé à toi » à '
                  'tes amis. On collecte le minimum pour faire fonctionner ce '
                  'service, rien de plus.'),
              _sub(w, 'Données que l\'on traite'),
              _p(w,
                  '• Compte : ton adresse email et ton mot de passe (chiffré).\n'
                  '• Profil : ton @handle, ton pseudo, et tes préférences '
                  '(décor, sons, heures calmes + fuseau horaire).\n'
                  '• Social : tes amitiés (demandes, amis), tes blocages.\n'
                  '• Pensées : qui a pensé à qui et quand, et si c\'était '
                  'anonyme. Une pensée ne contient AUCUN texte — c\'est un '
                  'simple signal.\n'
                  '• Notifications : un identifiant d\'appareil (jeton FCM) pour '
                  't\'envoyer les notifications push.'),
              _sub(w, 'Pourquoi'),
              _p(w,
                  'Uniquement pour faire marcher l\'app : créer ton compte, '
                  'gérer tes amis, transmettre les pensées et t\'avertir quand '
                  'on pense à toi. Pas de publicité, pas de revente de données, '
                  'pas de pistage publicitaire tiers.'),
              _sub(w, 'Sous-traitants'),
              _p(w,
                  '• Supabase — hébergement de la base de données et '
                  'authentification (serveurs en Union européenne).\n'
                  '• Google Firebase Cloud Messaging — livraison des '
                  'notifications push.\n'
                  'Ils traitent ces données pour notre compte, selon leurs '
                  'propres engagements de sécurité.'),
              _sub(w, 'Anonymat'),
              _p(w,
                  'Si tu envoies une pensée en mode anonyme, le destinataire '
                  'voit « Quelqu\'un a pensé à toi » sans ton nom. Ton identité '
                  'reste néanmoins enregistrée côté serveur (pour la sécurité et '
                  'la modération) et n\'est jamais montrée au destinataire.'),
              _sub(w, 'Conservation & suppression'),
              _p(w,
                  'On garde tes données tant que ton compte existe. Tu peux '
                  'supprimer ton compte à tout moment (Réglages → Supprimer mon '
                  'compte) : ton compte, tes amis et toutes tes pensées sont '
                  'alors effacés définitivement.'),
              _sub(w, 'Tes droits (RGPD)'),
              _p(w,
                  'Tu peux demander l\'accès, la rectification, l\'effacement ou '
                  'la portabilité de tes données en écrivant à $_contact.'),
              _sub(w, 'Âge'),
              _p(w,
                  'DewDrop n\'est pas destiné aux enfants de moins de 13 ans (ou '
                  'l\'âge minimum légal dans ton pays).'),

              const SizedBox(height: 28),
              _h(w, 'Conditions d\'utilisation'),
              _sub(w, 'Le service'),
              _p(w,
                  'DewDrop sert à envoyer de douces « pensées » à des amis qui '
                  't\'ont accepté. C\'est un signal bienveillant, sans contenu.'),
              _sub(w, 'Ton compte'),
              _p(w,
                  'Tu es responsable de la confidentialité de ton mot de passe '
                  'et de l\'activité sur ton compte. Donne des informations '
                  'exactes à l\'inscription.'),
              _sub(w, 'Bon usage'),
              _p(w,
                  'Pas de harcèlement ni d\'usage abusif — y compris via le mode '
                  'anonyme. Tu peux bloquer ou signaler quelqu\'un à tout moment '
                  '(appui long sur un ami). On peut suspendre un compte qui '
                  'enfreint ces règles.'),
              _sub(w, 'Disponibilité'),
              _p(w,
                  'Le service est fourni « tel quel », sans garantie de '
                  'disponibilité continue. On fait de notre mieux pour qu\'il '
                  'marche bien.'),
              _sub(w, 'Résiliation'),
              _p(w,
                  'Tu peux arrêter et supprimer ton compte quand tu veux. On '
                  'peut faire évoluer ces conditions ; les changements importants '
                  'seront signalés dans l\'app.'),
              _sub(w, 'Contact'),
              _p(w, 'Une question ? Écris-nous à $_contact.'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _h(Color w, String t) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(t,
            style: TextStyle(
                color: w, fontSize: 22, fontWeight: FontWeight.w500)),
      );

  Widget _sub(Color w, String t) => Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 6),
        child: Text(t,
            style: TextStyle(
                color: w, fontSize: 15, fontWeight: FontWeight.w600)),
      );

  Widget _p(Color w, String t) => Text(t,
      style: TextStyle(color: w.withValues(alpha: 0.72), height: 1.5));
}
