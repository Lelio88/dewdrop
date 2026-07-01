# DewDrop — Contexte d'Opération et Garde-Fous Agentiques

Résolvez les problèmes sans introduire de régression ni de dette technique architecturale.

## I. Finalité

**Application** : DewDrop — app mobile cosy pour **envoyer une pensée** à un ami (signal pur « X a pensé à toi », sans contenu). Anti-spam = culture, pas de feed.
**Objectif métier** : de douces *good vibes*, sur des **décors immersifs** choisis (espace, sous l'eau, forêt, plage, bibliothèque, montagne, désert, aurores boréales, champs), en style **dessiné** ou **photo**, chacun avec son **ambiance sonore + musique** réglables.

## II. Architecture

**Modèle** : Flutter **feature-first** (Clean Architecture) sous `lib/src/features/` + un **moteur de décors** autonome sous `lib/decor/`. État via **Riverpod (sans codegen)**, navigation **GoRouter**, backend **Supabase** (Postgres + Auth + RLS + Realtime), push/crash **Firebase** (FCM + Crashlytics), emails **Brevo**.

**Détails complets** (couches, moteur de décors, son, RLS/GRANT, mode photo, deep links, realtime, emails) : voir [`docs/architecture.md`](./docs/architecture.md).

Topologie rapide :
- `lib/decor/` — moteur de décors (Canvas) : `environment.dart` (registre 9 ambiances + 3 mondes **saisonniers** marronniers masqués du sélecteur + `buildDecor`), `*_decor.dart` (FX bespoke par décor, par-dessus la photo), `decor_backdrop.dart` (warp de profondeur photo/aquarelle + aplat `baseColor` au chargement), `tilt.dart` (parallax gyroscope à neutre adaptatif).
- `lib/src/features/<f>/{domain,data,application,presentation}/` — auth · profile · friends · **groups** (cercles) · thoughts · settings · home · **ambient** (son) · **notifications** (push **groupé**).
- `lib/src/{app,routing,common,supabase}/` — composition root, GoRouter, `common/deep_links.dart`, widgets glass, config Supabase.
- `supabase/{migrations,functions,config.toml}` · `tools/depth_split/` (couches photo) · `docs/index.html` (page légale hébergée) · `assets/{photo,audio}/`.

## III. Pile Technologique

*Versions contraintes par `pubspec.yaml`. N'introduisez aucune dépendance alternative sans approbation.*

- **Langage** : Dart (SDK ^3.11) / Flutter (stable).
- **État / nav** : `flutter_riverpod ^3.3` (**sans codegen**), `go_router`.
- **Modèles** : `freezed ^3` ou classes immuables manuelles.
- **Backend** : `supabase_flutter ^2.14` (cloud en prod/testeurs ; local Docker en dev).
- **Push / crash** : `firebase_core` / `firebase_messaging` / `firebase_crashlytics`, `flutter_local_notifications`, `flutter_timezone`.
- **Deep links** : scheme `dewdrop://` via `app_links` (+ handling auth natif de supabase_flutter).
- **Amis** : `qr_flutter` (afficher un QR), `mobile_scanner` (scanner un QR).
- **Son / capteurs** : `audioplayers`, `sensors_plus` (gyroscope), `shared_preferences`.
- **Emails** : SMTP **Brevo** (configuré dans `supabase/config.toml` ; clé via env).
- **CI iOS** : **Codemagic** (`codemagic.yaml`, runners macOS — build/signe iOS sans Mac).

## IV. Garde-Fous non négociables

1. **Migrations immuables** : une migration `supabase/migrations/` déjà jouée n'est **jamais** modifiée. Corriger = nouvelle migration.
2. **Sécurité Supabase** : toute table lue/écrite exige **RLS** **et** **GRANT** au rôle `authenticated` (oublier le GRANT → `42501`). `profiles` est **owner-only** (lire les autres = vue **`public_profiles`**) ; les helpers RLS (`are_friends`, `is_blocked`, `is_group_member`…) vivent dans le schéma **`private`** (`search_path=''`, non exposé en RPC).
3. **Riverpod sans codegen** : providers à la main. **NE PAS** réintroduire `riverpod_generator`/`riverpod_lint` (conflit freezed 3 / Dart 3.11). `AsyncValue.value`, pas `valueOrNull`.
4. **Décors en Canvas** : pas de fragment shader runtime (ne rend pas sur desktop) → `CustomPainter`. Fond statique vs couche animée (perf). Une **variante = une vraie scène** (même scène en Dessin **et** Photo), pas une teinte. **`buildDecor` clippe chaque décor à ses bords** (`ClipRect`) : le backdrop sur-dessine volontairement ~6 % au-delà (warp `_overscale`/scale 1.12) pour ne jamais révéler de gap au tilt ; sans clip ce débord bave sur le monde voisin (colonne fantôme en PageView / pendant le slide accueil). Les images warp (`full.webp`+`depth.webp`, ~11 Mo décodées) passent par un **cache LRU partagé** `DecorImageCache` (`lib/decor/decor_image_cache.dart`, cap 6) : le backdrop emprunte un `clone()` (jamais disposer le handle du cache ; les pixels ne sont libérés qu'au dispose de tous les clones), `peek()` synchrone en `initState` pour peindre dès la 1ʳᵉ frame, l'accueil pré-chauffe les voisins (`_prewarmNeighbours`).
5. **Aucun secret commité** (repo **public**) : clé SMTP via `env(BREVO_SMTP_KEY)` au `config push` ; keystore + `android/key.properties` gitignorés ; service account FCM dans `supabase/functions/.env` gitignoré.
6. **Couplage** : `presentation` n'importe jamais `data` ; le cross-feature passe par `application` ; seule la composition root connecte les implémentations.
7. **Temps réel & son** : les flux Realtime émettent un **compteur** (jamais `void` — sinon `==` avale les ticks) ; un **`AudioContext` global** mixe les lecteurs (`AndroidAudioFocus.none`/`mixWithOthers` — sinon le focus exclusif coupe ambiance/musique/one-shots l'un l'autre) et la réconciliation audio est **sérialisée** (sinon son bloqué). Voir docs.

## V. Flux de Travail (Explore → Plan → Code → Verify)

1. **Exploration** — lire les fichiers adjacents pour calquer les patterns.
2. **Planification** — soumettre l'approche pour les changements non triviaux.
3. **TDD** — test d'abord, vérifier l'échec, **ne plus l'altérer**.
4. **Implémentation** — code minimal pour passer le test.
5. **Vérification** — `flutter analyze` (zéro issue) + `flutter test` + build/run.

**Auto-documentation des packages** — tout nouveau fichier/feature publie en tête un doc comment : (1) ce qu'il fait, (2) les choix non-évidents + motivation, (3) les invariants à préserver, (4) un exemple d'usage si l'API n'est pas évidente.

## VI. Commandes de Développement

```bash
supabase start                         # backend local (Docker)
flutter run -d windows                 # desktop (itération rapide ; mobile = gyroscope + FCM réels)
flutter analyze && flutter test        # doivent être verts
flutter build apk --release \          # build cloud (testeurs) — signé via android/key.properties
  --dart-define=SUPABASE_URL=https://<ref>.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=<clé publishable>
supabase migration new <slug>          # nouvelle migration (prod : supabase db push)
supabase config push                   # pousser la config auth (SMTP, templates, redirects) ; BREVO_SMTP_KEY en env
# décors photo : Base.png → tools/depth_split/_src/<décor>/<variante>/ puis warp_batch.py
#   → assets/photo/<décor>/<variante>/{full.webp,depth.webp} (parallaxe = depth-warp, pas de SCENE_SETTINGS)
```

## VII. Maintenance documentaire

**Règle d'or** : le diff du code et celui de la doc associée sont dans **le même commit**.

| Modification | Fichier à mettre à jour |
|---|---|
| Nouvelle table / colonne / RLS / Realtime | nouvelle migration `supabase/migrations/` (+ GRANT) |
| Nouveau décor / variante | `lib/decor/environment.dart` (enum + `buildDecor`) + `lib/decor/<décor>_decor.dart` + source `tools/depth_split/_src/<décor>/<v>/Base.png` → `warp_batch.py` + déclarer **chaque** variante dans `pubspec.yaml` (pas de wildcard) + `docs/architecture.md` |
| Nouveau deep link | `lib/src/common/deep_links.dart` + `additional_redirect_urls` (`config.toml`) + manifeste Android / `Info.plist` |
| Envoi « pensée » par lien / voix (socle AppFunctions) | deep link `dewdrop://send?to=<handle>` = `DeepLinks.sendTo`/`sendTarget` (`common/deep_links.dart`), dispatché par `DeepLinkListener` (`common/deep_link_listener.dart`, ex-`invite_links.dart` : invite **et** send) ; résolveur **pur** `matchFriend` (`features/friends/domain/friend_match.dart`, accents/casse, sealed `FriendMatch`) ; capability **headless** `QuickSendService` (`features/thoughts/application/quick_send_service.dart`) qui lit le **repo amis en direct** (pas `friendsProvider` : un `FutureProvider` non écouté laisse son `.future` **pendant** en cas d'erreur) puis envoie sans widget ; confirmation **1-tap** hors écran via `app.dart` `_onSend` (navigator du router). Manifeste scheme-only = `send` déjà couvert. **Reste déféré** : service natif Kotlin AppFunctions (API en preview, Pixel 10 / S26 Ultra) — il réutilisera `QuickSendService` + le pattern isolate du widget |
| Réglage parallaxe d'une scène | force par décor : `_strengthByEnv` dans `lib/decor/decor_backdrop.dart` (Dart) ; régénérer les assets = `tools/depth_split/warp_batch.py` |
| Décors favoris / swipe accueil | snapshot favori `"<env>:<variant>:<mode>"` = `encodeFavorite`/`parseFavorite` (`lib/src/common/decor_choice.dart`) ; source unique `decorFavoritesProvider` (`features/settings/application/`, optimiste, persiste `profiles.decor_favorites`) ; ⭐ (toggle, remplace la croix) dans `decor_stories.dart` (`ConsumerStatefulWidget`) ; **swipe horizontal** bidirectionnel en boucle dans `home/presentation/home_screen.dart` (`_onHorizontalDragEnd`, droite = précédent) qui **glisse** le décor via un `AnimatedSwitcher` directionnel (`_slideDir`, clé = snapshot décor, transition slide+`ClipRect`) ; colonne via migration (owner-only, pas de RLS/GRANT en plus) |
| Texte légal | `lib/.../legal_screen.dart` **et** `docs/index.html` (garder synchro) |
| Style/texte des notifs envoyées | listes émojis/phrases dans `thought_style.dart` ; assemblage par `send-thought-push` (les deux côtés) |
| Logique de groupe (RLS, fan-out) | nouvelle migration (helpers `private`) + `features/groups/` + RPC `send_to_group` |
| Affichage/groupement des notifs reçues | `thought_notifications.dart` (app) **et** le payload `data` de `send-thought-push` |
| Nouveau son / piste audio | recette `tools/sounds/build_audio.sh` + attribution `CREDITS.md` |
| Logique du widget écran d'accueil | `features/home_widget/` (Dart : `widget_sync_service.dart`, `widgetSlotFriendsProvider` dans `widget_providers.dart`, `presentation/widget_settings_screen.dart`) + `android/.../DewDropWidgetProvider.kt` + `res/{layout,xml,drawable}` + 2 receivers manifest. **Contrat de clés** `signed_in`/`anonymous`/`slot_count`/`slot{i}_id\|initial\|label` **+ `sent_id`/`sent_at`** (✓ envoyé) partagé Dart ↔ Kotlin ↔ isolate (`widget_background.dart`) — changer un côté = changer les trois. Source des slots = `profiles.widget_source` (`auto`\|`custom`) + `profiles.widget_friends`, résolue par `widgetSlotFriendsProvider`. Réglage ouvert **depuis le widget** (appui long → Reconfigurer) via `WidgetConfigActivity` (`android:configure` + `widgetFeatures="reconfigurable\|configuration_optional"`) → URI `dewdrop://widget/configure` → `/widget-settings` (capté dans `app.dart` via `HomeWidget.widgetClicked`/`initiallyLaunchedFromHomeWidget`). **Pas d'entrée in-app** |
| Gestes à deux crans (aperçus accueil) | machine à états **pure** `nextSheetState` + `SheetState`/`HomeSheet`/`SheetStage` (`features/home/domain/home_sheet.dart`, testée) ; `home_screen.dart` `_onDragEnd` applique la transition (peek → full = re-glisser dans le même sens, sens inverse = redescendre d'un cran) ; `_SheetPanel` grandit via `AnimatedSize` + `Expanded` et expose une **poignée** (`onGrabDrag`) ; `ReceivedPeek(expanded:)` / `SendDock(expanded:)` rendent la liste complète scrollable au cran plein écran |
| Univers marronnier (verrou par date) | modèle **pur** `SeasonalEvent` + `activeSeasonalEvent(now)` + `kSeasonalEvents` (`lib/src/common/seasonal.dart`, testé, « jour pile ») ; provider `seasonalOverrideProvider` (ré-échantillonné au `resume`) ; `home_screen.dart` force le décor **à l'affichage seulement** (jamais persisté → l'univers perso revient), coupe `_onHorizontalDragEnd`/`_prewarmNeighbours`, verrouille l'entrée « Univers » du `_HomeMenu`, affiche `_SeasonalBadge`. **3 vrais `Environment`** (`christmas`/`halloween`/`april`, flag `seasonal` ⇒ **masqués** du sélecteur `decor_stories.dart`) avec FX bespoke (`{christmas,halloween,april}_decor.dart` : neige+cheminée / brume+orbes / gyrophares) + assets `depth_split` (`_src/<env>/0/Base.png` → pipeline) + **audio** (`kDecorAudio` ; sources `tools/sounds/<env>_src/` → `build_seasonal.sh`). Toucher une scène = décor + `warp_batch.py`/`illustrate_all.py` (liste envs) + `pubspec.yaml` + `build_seasonal.sh` + `kDecorAudio` + `CREDITS.md` (+ crédit **in-app** `about_screen.dart` si CC-BY) |
| Changement de dépendance critique | Section « Pile » + `pubspec.yaml` |

## VIII. Contexte de Session

- **Dernier focus** : **gestes à deux crans + univers marronniers** (release **0.9.8+21**). (1) Les aperçus tirés au doigt sur l'accueil (↓ reçus / ↑ envoi) ont un **2ᵉ cran plein écran** : re-glisser dans le même sens escalade `peek → full` (liste complète scrollable), le sens inverse redescend d'un cran. Cœur **pur** `nextSheetState` (`features/home/domain/home_sheet.dart`, testé) ; `_SheetPanel` grandit via `AnimatedSize`+`Expanded`+poignée `onGrabDrag` ; `ReceivedPeek(expanded:)`/`SendDock(expanded:)` rendent tout. (2) **Univers marronniers verrouillés** aux dates « jour pile » (Halloween 31/10, 1er avril 01/04, Noël 24–25/12) : `SeasonalEvent`/`activeSeasonalEvent` (`lib/src/common/seasonal.dart`, testé) + `seasonalOverrideProvider` ; la home force le décor **à l'affichage seulement** (jamais persisté → l'univers perso revient après la fenêtre), coupe le swipe favoris + `_prewarmNeighbours`, verrouille l'entrée « Univers » du menu et montre `_SeasonalBadge` ; ré-échantillonné au `resume` (`ref.invalidate`). **3 vrais mondes dédiés** peuplés en session : Noël (intérieur cosy sapin/cadeaux/cheminée+neige), Halloween (forêt de citrouilles brumeuse + orbes), 1er avril (chantier « en travaux » + gyrophares) — `Environment` `christmas/halloween/april` (flag `seasonal` ⇒ masqués du sélecteur) + FX bespoke (`{env}_decor.dart`) + assets `depth_split` (photo **et** dessin) + **audio bespoke** (`build_seasonal.sh`, sources CC0 OpenGameArt/Freesound sauf 2 pistes **CC-BY** créditées **in-app** `about_screen` : boîte à musique Brahms de Noël + marteau-piqueur du 1er avril). Noël = feu+boîte à musique · Halloween = vent+forêt éerie · 1er avril = **marteau-piqueur + trafic** (voitures/camions). Tests verts, analyze 0 issue. Pas encore validé on-device. **Aucune migration.**
- **Focus précédent** : **socle « envoyer une pensée par lien / voix »** (release **0.9.7+20**), préparation Gemini AppFunctions. Deep link `dewdrop://send?to=<handle>` → confirmation 1-tap → envoi ; briques `matchFriend` (pur), `QuickSendService` (headless, lit le repo amis en direct), `DeepLinkListener`. Service natif Kotlin **déféré**. Incluait aussi 3 polish décors (slide favoris `AnimatedSwitcher`, `ClipRect` anti-colonne-fantôme, cache `DecorImageCache` + `_prewarmNeighbours`). Précédé de **0.9.6+19** (décors favoris + swipe accueil).
- **Focus immédiat** : **builder + uploader l'AAB 0.9.8+21** au test fermé Play Store (notes = `CHANGELOG.md`) — **aucune** migration ajoutée. **À vérifier sur device** : (a) sur l'accueil, re-glisser ↓ puis ↓ agrandit les reçus en plein écran (idem ↑↑ pour l'envoi), et le geste inverse / la poignée referment cran par cran ; (b) simuler un marronnier pour voir le verrou + **les 3 nouveaux mondes** (le plus simple : changer la date du téléphone au 31/10 / 24-12 / 01-04, ou pointer temporairement un `SeasonalEvent` sur `DateTime.now()`) — décor + FX + **audio** (feu+boîte à musique / vent+forêt éerie / marteau-piqueur+trafic), swipe favoris + sélecteur « Univers » désactivés, badge affiché, univers perso de retour hors fenêtre ; (c) restes des lots précédents (send par lien `dewdrop://send?to=`, ⭐ favoris + swipe horizontal). **Restes hors lot** : ambiance sonore *sur-mesure enrichie* si besoin (les pistes actuelles sont posées) ; appui long widget → « Reconfigurer » (dépend du launcher) ; durcissement sécu (`HomeWidgetBackgroundReceiver`) ; **iOS** WidgetKit (toujours **bloqué compte Apple Developer 99 $/an**).
