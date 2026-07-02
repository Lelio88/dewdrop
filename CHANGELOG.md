# Changelog

Évolutions notables de DewDrop. Format inspiré de
[Keep a Changelog](https://keepachangelog.com/fr/).

## [0.9.9+22] — 2026-07-02

### Amélioré

- 👆 **Repli plus facile des aperçus plein écran** : quand un aperçu (reçus ou
  envoi) est agrandi au maximum, il est désormais coupé en deux — une moitié
  fait défiler la liste, l'autre moitié (côté du bord d'où vient l'aperçu) est
  une zone *« glisse pour réduire »* qui ramène au petit aperçu d'un simple
  geste. Plus besoin de viser la mini-poignée.

## [0.9.8+21] — 2026-07-01

### Ajouté

- 👆 **Gestes à deux crans sur l'accueil** : les aperçus tirés au doigt
  (glisser ↓ = pensées reçues, glisser ↑ = envoi rapide) s'ouvrent d'abord en
  petit ; **refaire le même geste** les agrandit en **plein écran** — tout
  l'historique côté reçus, tous les amis & cercles côté envoi, le tout sur
  place. Le geste inverse (ou la petite poignée) referme un cran à la fois.
- 🎃 **Univers marronniers verrouillés** : à certaines dates, un univers de
  saison dédié prend l'écran et ne peut pas être changé — **Noël** (24–25/12,
  intérieur cosy : sapin, cadeaux, cookies + lait, cheminée, baie vitrée
  enneigée), **Halloween** (31/10, forêt de citrouilles brumeuse) et **1er
  avril** (01/04, chantier « monde en travaux »). Chacun a ses effets animés
  (neige + lueur de cheminée / brume + orbes flottants / gyrophares ambrés qui
  clignotent). Le swipe entre favoris et le sélecteur d'univers sont désactivés
  le temps de la fenêtre ; ton univers habituel revient tout seul après. Un
  petit badge explique pourquoi (« 🎃 Halloween »).

### Note interne

- Le verrou marronnier est **display-only** : le décor de saison n'est jamais
  enregistré sur le profil, donc le choix perso est intact au retour. Les trois
  mondes sont de vrais `Environment` (fond dessin **et** photo générés par le
  pipeline `depth_split`), **masqués du sélecteur** normal (`Environment.seasonal`)
  — ils n'apparaissent que via le verrou. Chaque monde a aussi son **audio
  sur-mesure** (2 couches, `tools/sounds/build_seasonal.sh`) : sources CC0
  (OpenGameArt/Freesound) sauf **deux** pistes **CC BY** créditées **in-app**
  (« À propos & crédits ») — la boîte à musique de Noël (Brahms, Gregor Quendel)
  et le marteau-piqueur du 1er avril (Tomlija). Cœurs
  purs testés : `nextSheetState` (machine à états du geste) et
  `activeSeasonalEvent` (fenêtres de dates). Aucune migration, aucune donnée
  supplémentaire.

## [0.9.7+20] — 2026-06-25

### Ajouté

- 💬 **Envoyer une pensée par lien** : nouveau deep link
  `dewdrop://send?to=<pseudo>` qui ouvre une **confirmation en un tap** pour
  envoyer une pensée à cet ami. C'est le point d'accroche pour brancher une
  routine vocale (« Ok Google, envoie une pensée à … ») dès aujourd'hui, et la
  base que réutilisera la future intégration **Gemini AppFunctions**. La
  résolution du nom tolère accents, casse, pseudo **ou** nom affiché.

### Corrigé

- 🎞️ **Slide des décors favoris** : sur l'écran principal, changer de favori
  d'un geste **glisse** maintenant le nouveau monde depuis le côté du doigt (au
  lieu d'apparaître d'un coup).
- 🩹 **Colonne fantôme** dans le panneau Univers : en changeant d'ambiance, une
  fine bande verticale du monde précédent restait parfois affichée. Chaque décor
  est désormais clippé à ses bords (le fond déborde volontairement de ~6 % pour
  la parallaxe ; ce débord bavait sur le monde voisin).
- ⚡ **Plus de flash au changement de décor favori** : les mondes voisins sont
  pré-décodés dans un cache d'images partagé, donc le nouveau décor s'affiche
  dès la première frame du slide au lieu de montrer brièvement sa couleur de
  fond (cache plafonné, ~33 Mo en usage courant, libéré à l'éviction).

### Note interne

- Socle « envoi sans interface » posé pour la suite : un résolveur d'ami pur
  (`matchFriend`, testé) et une capability headless (`QuickSendService`) qui
  lit le repo amis en direct et envoie sans aucun widget — exactement ce
  qu'appellera la fonction vocale native quand l'API AppFunctions sortira de
  preview. Le service natif Kotlin reste **déféré** (API en preview, 2 modèles
  de téléphone). Aucune donnée supplémentaire collectée ; un envoi par lien
  reste soumis au RLS (impossible d'écrire à un non-ami).

## [0.9.6+19] — 2026-06-25

### Ajouté

- ⭐ **Décors favoris** : dans le panneau Univers, l'icône en haut à gauche est
  maintenant une **étoile** — touche-la pour mettre la vue en cours (monde +
  variante + dessin/photo) en favori, retouche-la pour l'enlever. Tes favoris
  sont **synchronisés** sur ton compte.
- 👆 **Changer de décor d'un geste** : sur l'écran principal, **glisse
  horizontalement** pour passer d'un favori à l'autre (droite = précédent,
  gauche = suivant, en boucle), sans rouvrir le panneau.

### Modifié

- La **croix de fermeture** du panneau Univers laisse sa place à l'étoile : on
  ferme désormais avec le bouton « Choisir ce monde » ou le geste retour.

## [0.9.5+18] — 2026-06-24

### Modifié

- 🛠️ **Le réglage du widget se fait depuis le widget lui-même** : fais un **appui
  long sur le widget → « Reconfigurer »** pour choisir tes amis et leur ordre.
  L'entrée correspondante dans les Réglages de l'app a été retirée.
  *(Le « Reconfigurer » dépend de ton launcher Android ; s'il ne l'affiche pas, le
  mode « derniers contacts » automatique reste actif par défaut.)*

## [0.9.4+17] — 2026-06-24

### Ajouté

- 🎚️ **Réglage du widget** : choisis **qui** apparaît sur ton widget d'écran
  d'accueil — soit **automatiquement** tes derniers contacts (les amis à qui tu
  as envoyé une pensée le plus récemment), soit **ta propre sélection** de
  jusqu'à 4 amis, **réordonnables**. Depuis Réglages → « Widget d'écran
  d'accueil ».
- ✅ **Confirmation d'envoi sur le widget** : après un tap, le rond de l'ami
  affiche un **✓ « Envoyé »** pendant quelques secondes, puis revient à la
  normale — sans ouvrir l'app.

### Modifié

- 📐 Le widget ne peut plus être **étiré en hauteur** (il gardait des vides) :
  il se redimensionne désormais en largeur uniquement.

## [0.9.3+16] — 2026-06-24

### Ajouté

- 🏠 **Widget d'écran d'accueil (Android)** : pose une rangée de tes amis sur ton
  écran d'accueil et **envoie une pensée d'un seul tap, sans ouvrir l'app**. Un
  court délai anti-double-envoi évite les envois en rafale. L'anonymat suit ton
  réglage par défaut.

## [0.9.2+15] — 2026-06-23

### Ajouté

- ⭐ **Presets de style de notification** : enregistre jusqu'à **5 styles nommés**
  (emoji · phrase · emoji), ré-applique-en un d'un seul tap, et supprime-les. Une
  alerte t'avertit quand les 5 emplacements sont pris.

### Modifié

- 🎛️ **Menu et réglages réorganisés** : dans le menu, « Envoyer une pensée » passe
  en premier. Les préférences de tes pensées (anonymat + personnalisation) vivent
  désormais dans **Réglages**, sous une section **Personnalisation** (avec la
  parallaxe). Ordre des sections : Personnalisation → Notifications → Soutien →
  À propos → Compte.

## [0.9.1+14] — 2026-06-22

### Ajouté

- 🌾 **Nouvel univers « Champs »** : une prairie fleurie (matinée dorée) et un
  champ de blé (coucher flamboyant), au choix en **photo** ou en **aquarelle**.
- Quand quelqu'un pense à toi, un **envol de graines de pissenlit** traverse le
  champ, emporté par une brise — deux souffles successifs.
- **Ambiance sonore dédiée** au décor : le blé qui bruisse au vent et une
  abeille qui passe, sur une musique douce.
- ☕ Bouton **« Soutenir DewDrop »** (Ko-fi) dans les réglages.
