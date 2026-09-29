# Dossier Play Store — DewDrop

Tout le contenu prêt à copier-coller dans la **Google Play Console**. À faire après avoir
réglé les bloquants de sécurité (voir l'audit). Build à uploader :
`build/app/outputs/bundle/release/app-release.aab`.

---

## 1. Identité

| Champ | Valeur |
|---|---|
| Nom de l'app | **DewDrop** |
| Package | `app.dewdrop` |
| Catégorie | Social *(ou « Style de vie »)* |
| Email de contact | heianenterpriseyt@gmail.com |
| Confidentialité (URL) | https://lelio88.github.io/dewdrop/ |
| Suppression de compte (URL) | https://lelio88.github.io/dewdrop/suppression-compte.html |
| Site web (optionnel) | https://lelio88.github.io/dewdrop/ |
| Tarif | Gratuit · sans achats intégrés · sans pub |

## 2. Description courte (≤ 80 caractères)

> Envoie une pensée à quelqu'un. Pas de feed, pas de spam — juste de douces good vibes.

*(76 caractères)*

## 3. Description longue (≤ 4000 caractères)

> **DewDrop, c'est dire « je pense à toi » — rien de plus, et c'est déjà beaucoup.**
>
> Pas de fil d'actualité. Pas de likes. Pas de messages à rédiger. Tu choisis un ami,
> tu envoies une pensée, et il reçoit un signal tout simple : *« Lelio a pensé à toi ✨ »*.
> C'est tout. Une attention pure, sans la charge mentale des réseaux sociaux.
>
> **🌿 Des décors immersifs rien que pour toi**
> Espace étoilé, forêt, fonds marins, plage, montagne, désert, bibliothèque cosy, aurores
> boréales… Chaque décor existe en version **dessinée** et en version **photo**, avec un
> léger effet de profondeur qui réagit aux mouvements de ton téléphone.
>
> **🎧 Une ambiance sonore vivante**
> Chaque décor a sa propre ambiance et sa musique douce, réglables comme tu veux. Vagues,
> pluie, feu de cheminée, chants d'oiseaux… avec quelques surprises sonores au fil du temps.
>
> **💌 Des pensées qui te ressemblent**
> Personnalise ta notification (émojis, petite phrase au choix). Envoie de façon visible
> ou **anonyme**. Active des **heures calmes** pour ne pas être dérangé la nuit.
>
> **👋 Des amis, simplement**
> Ajoute par pseudo (@handle), par **QR code** ou par **lien d'invitation**. Tu peux
> bloquer ou signaler à tout moment. Tes données restent les tiennes.
>
> DewDrop est pensée pour faire du bien, doucement. Une goutte de rosée, une pensée,
> un sourire à l'autre bout.

## 4. Assets graphiques à fournir

| Asset | Format / taille | Quantité | État |
|---|---|---|---|
| **Icône** | PNG 32 bits, **512 × 512** | 1 | ✅ déjà conçue (réexporter en 512) |
| **Feature graphic** | PNG/JPG, **1024 × 500** | 1 | ⬜ à créer (bannière) |
| **Captures téléphone** | PNG/JPG, ratio 16:9 ou 9:16, **≥ 1080 px** côté long | 2 à 8 | ⬜ à faire |
| Capture tablette 7" (optionnel) | idem | 0–8 | ⬜ optionnel |

**Captures recommandées** (cohérentes avec l'anti-template) :
1. Décor montagne (photo) avec l'éclat de réception d'une pensée.
2. Décor espace (dessin) au repos.
3. La page « Pensées » (machine à sous émojis) en train de composer une notif.
4. L'écran d'envoi vers un ami.
5. La liste d'amis / ajout par QR.

> Astuce : capturer sur un vrai téléphone (le parallaxe + les particules rendent mieux que
> sur émulateur). Garder une direction visuelle assumée — pas de cadre marketing générique.

## 5. Classification du contenu (questionnaire IARC)

Réponses attendues pour DewDrop :
- Violence / contenu sexuel / drogue / jeux d'argent : **Non** partout.
- L'app permet-elle d'**interagir avec d'autres utilisateurs** ? **Oui** (envoi de pensées,
  demandes d'amis) → l'app sera classée « interaction sociale ».
- Partage de localisation : **Non**.
- Résultat attendu : **PEGI 3 / Tout public**.

## 6. Data safety (Sécurité des données)

**Doit dire la même chose que la politique** (`docs/index.html`, tableau des traitements).
Envoyée par l'API (`applications.dataSafety`, CSV du modèle Google) — le formulaire de la
console affiche ensuite ces réponses.

| Donnée (catégorie Google) | Pourquoi | Facultative |
|---|---|---|
| Adresse e-mail | Fonctionnement, gestion du compte | Non |
| Nom (pseudo) | Fonctionnement | Non |
| ID utilisateur (@handle, id de compte) | Fonctionnement, gestion du compte | Non |
| Autres actions (pensées, amis, cercles, blocages) | Fonctionnement | Non |
| Autre contenu généré (nom de cercle, motif de signalement) | Fonctionnement, sécurité | Oui |
| ID d'appareil (jeton FCM, id d'installation Crashlytics) | Fonctionnement, analyse | Non |
| Journaux de plantage, diagnostics (Crashlytics) | Analyse | **Oui** (Réglages → Vie privée) |

- **Rien n'est « partagé »** au sens de Google : Supabase, Firebase et Brevo sont des
  prestataires qui traitent pour notre compte.
- Chiffré en transit ; création de compte par **e-mail + mot de passe**.
- **Suppression** : URL de suppression de compte **et** de données =
  `https://lelio88.github.io/dewdrop/suppression-compte.html`.

## 7. Parcours de publication

1. Créer le compte **Google Play Console** (25 $, une fois).
2. Créer l'app → remplir Identité + Descriptions + Assets + Classification + Data safety.
3. **Play App Signing** : uploader l'AAB ; Google gère la clé de signature finale
   (on signe avec la clé d'upload = `android/key.properties`).
4. **Test fermé** : ⚠️ pour un **nouveau compte perso**, Google impose **20 testeurs
   pendant 14 jours** avant de pouvoir demander l'accès production.
5. Demander l'accès production → soumettre pour examen → publication.

> **À ne pas oublier au moment du Play Store** : ajouter la restriction « Applications
> Android » sur la clé API Firebase (Google Cloud Console → Credentials → la clé `AIzaSy…VL8M`),
> avec le package `app.dewdrop` et **les deux** SHA-1 : la clé d'upload
> (`51:44:74:CB:FA:58:FB:E1:C3:8D:4B:BD:AE:CB:0E:D3:42:A5:AD:AB`) **et** celle de Play App
> Signing (Play Console → Intégrité de l'application). Sans le SHA-1 de Play, l'enregistrement
> FCM casse pour les installs venant du Store. *(Les restrictions API sont déjà en place.)*

> Chaque nouvelle release doit avoir un `versionCode` supérieur (actuellement 3 dans
> `pubspec.yaml` → passer à 4 pour la première soumission Play).
