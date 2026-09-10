# Changelog

Évolutions notables de DewDrop. Format inspiré de
[Keep a Changelog](https://keepachangelog.com/fr/).

## [Non publié]

### Note interne

- CI : `actions/checkout` passe de v4 à v7 — la v4 déclarait Node 20, que les
  runners forçaient déjà sur Node 24 en l'annonçant à chaque exécution.
- 🔑 **Le repli sur la clé de débogage s'annonce** : sans `android/key.properties`,
  une build release retombait en silence sur la clé de debug. Gradle l'accepte
  sans un mot ; c'est Play qui refuse l'AAB une demi-heure plus tard, sans dire
  pourquoi. Le repli reste (il sert à `flutter run --release`), mais il se dit.
- Les notes des versions `0.8.0+11` à `0.9.0+13`, qui ne vivaient que sur la page
  Releases de GitHub, sont rapatriées ici ; cette page est supprimée. Le Play
  Store est le seul canal de distribution, et ce journal le seul journal.

## [0.9.23+37] — 2026-09-08

### Corrigé

- ✋ **Le retour tactile des tuiles est de nouveau visible** : dans le menu ☰ (6
  tuiles) et les Réglages (10), l'onde d'appui était peinte *sous* le fond de la
  carte en verre, donc invisible — on ne savait pas si le doigt avait porté. Le
  rendu au repos, lui, n'a pas bougé d'un pixel.

### Note interne

- Crashlytics ne collecte plus en debug. Un rapport annonçait un « crash fatal »
  sur Android 13 alors que rien n'avait planté : un diagnostic du framework
  (`ListTile._debugCheckBackgroundIsHidden`, qui ne lève pas) était promu en
  incident fatal, et l'émulateur se déclarant constructeur « Google », l'indice
  « uniquement sur appareils Google » désignait la machine de dev.

## [0.9.22+36] — 2026-09-08

### Amélioré

- 👆 **Tiroir d'envoi lisible** : amis et cercles ne partagent plus jamais une
  rangée. Au premier cran, les deux familles défilent chacune de leur côté (amis
  ronds, puis cercles carrés) ; au second, chacune a sa section libellée. Une
  famille sans membre ne laisse pas de trou. Le lien vers la liste complète
  remonte dans l'en-tête, à droite — il n'est plus sous le pouce avant les
  visages.
- 🔵 **Les cercles se trient par derniers échanges**, comme les amis.

### Corrigé

- 🔔 **La notification redonne son nom au cercle** : le titre disait « un groupe »
  quel que soit le cercle, donc un membre de plusieurs cercles ne pouvait pas
  savoir auquel on avait pensé. La fonction serveur n'avait pas le droit de lire
  la table des cercles — un refus qui se lisait comme une liste vide, sans
  erreur.
- ↕️ **Réordonner les amis du widget** écrit le bon ordre à l'écran comme en base,
  et n'écrit plus rien quand le glissement ne change rien.
- ✋ L'encre d'appui des deux entrées d'« À propos », invisible pour la même
  raison que les tuiles ci-dessus.

### Note interne

- Machine de dev alignée sur Flutter 3.47 (la CI prenait déjà `stable`), ce qui
  a fait remonter les deux défauts ci-dessus. Réveil quotidien du projet
  Supabase : le plan gratuit met en pause après sept jours sans activité, et la
  pause est muette côté app. Goldens sortis de l'étape de CI qui bloque le build.

## [0.9.21+35] — 2026-09-04

### Corrigé

- 🔵 **Une pensée envoyée à un cercle dit enfin qu'elle en est une.** Elle
  n'était pas perdue, elle était déguisée : la liste l'affichait « X a pensé à
  toi », rigoureusement identique à une pensée perso. Trois formes désormais
  (« à toi », « au groupe *Y* », « à un groupe »), écrites par une seule
  fonction partagée entre l'app et la notification — c'est la duplication de
  cette phrase qui avait laissé le cas passer. Le nom est résolu à l'affichage,
  donc un cercle renommé se lit avec son nouveau nom. Une icône de cercle double
  la phrase : dans une liste, la forme se lit avant les mots.

## [0.9.20+34] — 2026-08-18

### Amélioré

- ⚡ **Le décor est gelé pendant un tuto** : ses effets tournaient en continu et
  sa parallaxe reconstruisait un maillage à chaque échantillon du gyroscope,
  le tout derrière un voile opaque — au moment précis de la première impression.

### Note interne

- Filet de sécurité posé après six publications pour des défauts qu'aucun test
  ne pouvait voir : cinq tests visuels sur le tuto, `verify_prod.py` (qui
  interroge le serveur au lieu du dépôt — la panne des courriels avait duré deux
  mois parce que tout était juste côté dépôt), `ship.py` (les sept étapes d'une
  publication en une commande) et une CI qui rejoue analyse + tests à chaque
  push. `home_screen.dart` retombe de 1188 à 713 lignes, sans changement de
  comportement.

## [0.9.19+33] — 2026-08-18

### Amélioré

- ⚡ **Tuto plus fluide et plus posé** : chaque frame où la cible bougeait
  repeignait tout le nuage et ses trois passes floutées ; la silhouette est
  désormais mémoïsée et le voile ne se redessine plus quand la bulle se déplace.
  Le nuage ne se téléporte plus entre deux étapes qui partagent une ancre, et le
  rythme ralentit (battue après un geste : 1,6 → 2,1 s).

## [0.9.18+32] — 2026-08-18

### Corrigé

- 🗨️ **Chaque bulle dit comment en sortir** — « Glisse vers le haut pour
  continuer », « Appuie n'importe où pour continuer », avec l'icône du geste.
  Une étape qui n'attendait aucun geste ignorait les glissements *en silence* :
  rien ne bougeait, rien ne disait pourquoi, et il fallait deviner que le bouton
  était la seule issue.

## [0.9.17+31] — 2026-08-18

### Corrigé

- 💨 **Plus de petites bouffées quand elles ne relient rien.** Elles servent à
  porter le regard de la bulle vers ce dont elle parle ; quand la cible était à
  un demi-écran, elles partaient dans la bonne direction puis s'arrêtaient
  trente pixels plus loin, et se lisaient comme des miettes collées au nuage.

## [0.9.16+30] — 2026-08-18

### Corrigé

- 🗨️ **La bulle du tiroir plein écran ne couvre plus les visages.** Elle visait
  le panneau entier — 90 % de l'écran — donc le placement automatique ne
  trouvait aucune place à côté et retombait en haut, pile sur les avatars que
  l'étape précédente venait d'apprendre à toucher. Elle vise maintenant la bande
  du chevron, et une étape peut imposer le bord où va sa bulle.

## [0.9.15+29] — 2026-08-18

### Modifié

- 🎓 **Pendant un tuto, le tuto possède l'écran.** Une bulle décrit l'écran ;
  laisser le modifier en pleine phrase fait diverger les mots et les pixels. Le
  voile redevient opaque et n'offre que trois issues : faire le geste demandé,
  taper pour avancer, « Passer le tuto ». Un geste non demandé est refusé
  *visiblement* — le nuage frissonne, avec un retour haptique — parce qu'un
  refus silencieux se lit comme une app figée.

## [0.9.14+28] — 2026-08-17

### Corrigé

- ☁️ **Le nuage accompagne le tiroir** au lieu de rester figé pendant qu'il monte
  (ou de rester en haut pendant qu'il descend dessous). Il emprunte l'ancre de
  l'étape suivante dès que le geste atterrit, et suit le panneau sur tout son
  trajet.

## [0.9.13+27] — 2026-08-17

### Ajouté

- 🎓 **Un tuto par écran, quand l'explication va servir.** Tout expliquer au
  premier lancement demandait quatorze bulles — lues par personne, et oubliées
  avant d'être utiles. L'accueil garde les gestes (huit étapes) ; Amis, Univers
  et Réglages portent chacun deux bulles, à leur première ouverture. Les
  Réglages les réarment tous.
- 🎬 **Le tuto met la scène** : l'étape qui explique le tiroir en plein écran
  l'ouvre vraiment, que tu y sois arrivé par le geste ou par « Suivant ». Sans
  ça, la moitié du script décrivait ce qui n'était pas affiché.
- Pendant le tuto, les tiroirs vides montrent deux pensées d'exemple (étiquetées
  comme telles, jamais écrites en base) et un raccourci « Ajoute ton premier
  ami » là où le dock ouvrait sur un cul-de-sac.

### Corrigé

- 👆 **Le geste latéral ne ment plus** : sans aucun favori — donc sur un compte
  neuf, exactement celui qui découvre le geste — le glissement était mort
  pendant que le tuto le vantait. Il parcourt maintenant tous les univers ;
  l'étoile est un raccourci, plus un prérequis.

## [0.9.12+26] — 2026-08-17

### Amélioré

- 👆 **Les gestes du tuto se font pour de vrai** : le voile ne capte plus que le
  tap et laisse passer les glissements, donc une étape qui dit « glisse vers le
  haut » se valide quand le doigt le fait — pas quand on tape « Suivant ». Le
  tuto reste affiché tiroir ouvert le temps de voir le résultat.
- ☁️ **Nuage plus cotonneux** (le duvet vient de haloes flous dessinés sous le
  remplissage, et le trait de contour disparaît — le moindre liseré ramenait
  l'aspect autocollant), et **bulle qui dérive** d'une étape à l'autre au lieu
  de se téléporter.

## [0.9.11+25] — 2026-08-17

### Ajouté

- ☁️ **Tuto d'accueil en bulles-nuage.** L'accueil est presque entièrement
  gestuel, et un geste ne laisse aucune trace à l'écran ; le message qui passait
  en 3,5 s disait tout à la fois et disparaissait avant d'être lu. Cinq bulles
  ancrées sur les vrais éléments le remplacent. Les Réglages le rejouent.
- 🔤 **Repêchage de faute de frappe** : un pseudo mal tapé menait à un
  cul-de-sac. Jusqu'à trois pseudos proches sont proposés **après** un échec
  exact — jamais pendant la frappe, et jamais assez large pour devenir un
  annuaire parcourable.
- 🤝 **Ajouter en ami depuis un cercle**, sans passer par la recherche.
- Renvoi vers « Amis » en pied de l'écran d'envoi — donc en tête quand la liste
  est vide.

### Corrigé

- ✉️ **Les courriels d'authentification sont en français pour tous les flux.**
  Confirmation et réinitialisation l'étaient depuis juin, mais le serveur
  retombe *silencieusement* sur son gabarit anglais pour tout flux non
  surchargé : changement d'adresse, lien magique, ré-authentification et
  invitation partaient donc en anglais. Un test échoue désormais si un flux perd
  son gabarit, son fichier, son français ou sa substitution.

## [0.9.10+24] — 2026-08-11

### Corrigé

- 🔊 **La musique des autres apps se met en pause** : DewDrop réclame désormais
  le son de l'appareil comme n'importe quelle app à ambiance — une vidéo YouTube
  ou une playlist Spotify en cours se met en pause à l'ouverture, au lieu de
  jouer par-dessus l'ambiance. Le son est **rendu** dès que DewDrop se tait
  (bouton muet, retour à l'accueil du téléphone) : la musique reprend toute
  seule. Un appel entrant met l'ambiance en pause, puis elle repart après.

### Amélioré

- 👆 **Tiroir d'envoi trié par derniers échanges** : les personnes à qui tu as
  envoyé une pensée le plus récemment apparaissent en premier ; les autres
  suivent par ordre alphabétique. L'ordre ne bouge jamais pendant que le tiroir
  est ouvert (pas d'avatar qui saute sous le doigt) — il se met à jour à la
  fermeture. La mention « anonyme : réglages » a été retirée.

## [0.9.9+23] — 2026-07-05

### Amélioré

- 👆 **Aperçus plein écran : le contenu occupe toute la page** : quand un aperçu
  (reçus ou envoi) est agrandi au maximum, la liste remplit désormais **tout
  l'écran** (avant : seulement la moitié). La moitié côté bord d'où vient
  l'aperçu reste une **zone de repli** — y glisser dans le sens inverse ramène au
  petit aperçu d'un simple geste (un chevron discret l'indique) — tandis que
  l'autre moitié fait défiler la liste. Plus besoin de viser la mini-poignée.

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

## [0.9.0+13] — 2026-06-22

### Modifié

- 👆 **Accueil par gestes** : glisse vers le **haut** pour envoyer une pensée en
  un seul geste (touche un ami, c'est parti — fini la confirmation), vers le
  **bas** pour voir les pensées reçues. Le menu garde les deux accès.
- ⚡ **Envoi direct** : un tap envoie ; la tuile passe « Envoyé » quelques
  secondes (anti-double-envoi). Un message dédié apparaît si tu envoies trop
  vite.
- 🎛️ **Réglages** : notifications et heures calmes regroupés en une seule section
  « Notifications ».

### Note interne

- Correction de la doc du pipeline d'assets décors (depth-warp).

## [0.8.1+12] — 2026-06-21

### Amélioré

- 🎉 **Les célébrations s'intensifient** : quand l'app rattrape plusieurs pensées
  d'un coup, l'animation du décor devient plus dense **et** plus longue (courbe
  √n, plafonnée à ×2,5). Avant, toutes les célébrations étaient identiques quel
  que soit le nombre de pensées.

### Corrigé

- 💧 **Écran de chargement** : la goutte ne réapparaît plus quelques frames à la
  fin — l'animation joue une seule fois puis se fige sur le mot « DewDrop ».
- 🏔️ **Décor Montagne · Aube** : suppression des points multicolores parasites en
  bas de l'écran.
- 🌌 **Décor Aurores boréales** : plus d'averse de neige à l'arrivée d'une pensée
  — seul le ciel s'illumine (la neige d'ambiance de fond est conservée).
- 🔗 **Partage par QR code** : le lien « Copier mon lien » n'est plus masqué par
  la barre de navigation Android à 3 boutons.

## [0.8.0+11] — 2026-06-21

### Ajouté

- 💧 **Écran de chargement animé « goutte de rosée »** : au lancement (et pendant
  le chargement du profil), une goutte tombe sur une feuille, y glisse en
  douceur, se détache et tombe dans l'eau pendant que le nom **DewDrop**
  apparaît, avec un « ploc » d'eau pile au contact et un jingle 8-bit. Tap sur
  l'écran pour la passer. *(Inspiré de la scène « paix intérieure » de Kung Fu
  Panda 2.)* Son libre de droits (CC0) ; l'animation est 100 % Flutter, donc
  identique sur Android et iOS.
- 🌑 **Splash natif sombre** (Android + iOS) : fini le flash blanc au lancement à
  froid — l'écran natif raccorde sans couture à l'animation.
- 🍏 **Icône iOS** : la goutte DewDrop remplace le logo Flutter par défaut.

### Corrigé

- 🎨 Plus de **flash d'ancien décor** (style « généré ») pendant une fraction de
  seconde au changement d'univers.
