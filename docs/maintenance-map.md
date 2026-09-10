# DewDrop — Carte de maintenance documentaire

**Règle d'or** : le diff du code et celui de la doc associée vont dans **le même
commit**. Jamais séparément, jamais « plus tard ».

Ce fichier est la version complète de la section VII du
[`CLAUDE.md`](../CLAUDE.md), qui n'en garde que les entrées les plus fréquentes.
Chaque ligne répond à une seule question : *je touche à ceci — qu'est-ce qui doit
bouger avec ?* Les entrées ne décrivent pas seulement **quoi** mettre à jour,
mais **pourquoi les fichiers listés forment un tout** : c'est cette raison qui
permet de décider quand un cas nouveau relève de la même règle.

## Backend & sécurité

| Modification | Fichier(s) à mettre à jour |
|---|---|
| Table / colonne / RLS / Realtime | nouvelle migration `supabase/migrations/` (**+ GRANT**) + `architecture.md` |
| Logique de groupe (RLS, fan-out) | nouvelle migration (helpers `private`) + `features/groups/` + RPC `send_to_group` |
| Règles de découvrabilité (recherche de handle) | migration modifiant `search_profiles` **et** le paragraphe « Découvrabilité » d'`architecture.md` — les 5 garde-fous (≥ 3 car., ≥ 0.45, ≤ 3 résultats, handle seul, exclusions) se décident ensemble, jamais isolément |
| Nouveau flux d'auth par email (magic link, changement d'adresse…) | **un gabarit FR de plus** dans `supabase/templates/` + sa section `[auth.email.template.<flux>]` (`config.toml`) + la liste `_mustBeOverridden` (`test/supabase/email_templates_test.dart`) — un gabarit manquant = mail **anglais** silencieux. Puis `supabase config push`. |
| Nouveau deep link | `lib/src/common/deep_links.dart` + `additional_redirect_urls` (`config.toml`) + manifeste Android / `Info.plist` |

## Décors, son et parallaxe

| Modification | Fichier(s) à mettre à jour |
|---|---|
| Nouveau décor / variante | `lib/decor/environment.dart` (enum + `buildDecor`) + `lib/decor/<décor>_decor.dart` + source `tools/depth_split/_src/…/Base.png` → `warp_batch.py` / `illustrate_all.py` + **chaque** variante dans `pubspec.yaml` (pas de wildcard) + `architecture.md` |
| Réglage parallaxe d'une scène | `_warpShift` / `_strengthByEnv` dans `lib/decor/decor_backdrop.dart` ; régénérer via `warp_batch.py` |
| Univers marronnier (verrou par date) | `SeasonalEvent` / `activeSeasonalEvent` / `kSeasonalEvents` (`lib/src/common/seasonal.dart`, testé) + `seasonalOverrideProvider` (`features/settings/application/`) + `home_screen.dart` (override display-only) + `Environment` `christmas` / `halloween` / `april` (flag `seasonal`) + `{env}_decor.dart` + assets `depth_split` + audio `build_seasonal.sh` + `kDecorAudio` + `CREDITS.md` (+ `about_screen.dart` si CC-BY) |
| Décors favoris / swipe accueil | snapshot `"<env>:<variant>:<mode>"` = `encodeFavorite` / `parseFavorite` (`lib/src/common/decor_choice.dart`) + `decorFavoritesProvider` (`features/settings/application/`) + ⭐ dans `decor_stories.dart` + swipe dans `home/presentation/home_screen.dart` + colonne `profiles.decor_favorites` (migration) |
| Nouveau son / piste audio | `tools/sounds/build_audio.sh` (ou `build_seasonal.sh`) + attribution `CREDITS.md` |
| Focus audio (interruption des autres apps) | `features/ambient/application/audio_focus.dart` **et** `MainActivity.kt` (canal `app.dewdrop/audio_focus`) + prise/rendu dans `SoundscapeNotifier` (`_applyInner`, `pauseAll`, `_teardown`) |

## Pensées, notifications et envoi

| Modification | Fichier(s) à mettre à jour |
|---|---|
| Phrase d'une pensée reçue (perso / groupe) | `thoughtLine` / `senderLabel` (`thoughts/domain/thought.dart`, purs et testés) — **et** la phrase jumelle dans `send-thought-push/index.ts`. L'app et la notif disent la même chose ; un groupe non résolu (quitté depuis) dit « à un groupe », **jamais** « à toi ». Le nom est lu à l'affichage (`groups`), jamais figé sur la ligne |
| Style / texte des notifs envoyées | listes émojis / phrases dans `thought_style.dart` + assemblage `send-thought-push` (les deux côtés) |
| Affichage / groupement des notifs reçues | `notifications/application/thought_notifications.dart` + payload `data` de `send-thought-push` |
| Envoi « pensée » par lien / voix | deep link `dewdrop://send?to=<handle>` (`DeepLinks.sendTo`), `DeepLinkListener` (`common/deep_link_listener.dart` : invite **et** send), résolveur pur `matchFriend` (`features/friends/domain/friend_match.dart`), capability headless `QuickSendService` (`features/thoughts/application/`), confirmation 1-tap dans `app.dart` `_onSend` |
| Dock d'envoi (ordre + disposition) | `send_dock.dart` : les deux familles ne partagent jamais une rangée — au 1er cran deux rangées défilant à part (amis ronds, puis cercles carrés), au 2e des sections libellées, une famille vide ne rendant rien ; le lien vers l'écran complet vit dans le **header à droite**. Tri par `sortByRecency` + `dedupeNewestFirst` (`thoughts/domain/send_order.dart`, testés) sur **deux** lectures de récence — `recentContactsProvider` (amis) et `recentGroupsProvider` (cercles) : un envoi de groupe écrit **une ligne par membre**, une fenêtre commune serait remplie par un seul fan-out. Tri **gelé tant que le dock est visible** (`SendDock.visible` → invalidation différée des deux) |
| Gestes à deux crans (aperçus accueil) | machine à états pure `nextSheetState` / `SheetState` (`features/home/domain/home_sheet.dart`, testée) + `home_screen.dart` `_onDragEnd` + `received_peek.dart` / `send_dock.dart` (`expanded:`) |

## Tutoriels (bulles-nuage)

| Modification | Fichier(s) à mettre à jour |
|---|---|
| Étape / texte d'un tuto | `features/tour/domain/tour_step.dart` (scripts purs `kHomeTour` / `kFriendsTour` / `kDecorsTour` / `kSettingsTour` + `stepsFor`) ; nouvelle **cible** = valeur `TourAnchor` + `GlobalKey` sur le widget réel + entrée dans `anchors` ; nouveau **geste** = valeur `TourGesture` + cas dans `_performTourGesture` (le tuto reconnaît, l'accueil exécute) ; nouvelle **scène** = valeur `TourScene` + cas dans `_applyTourScene` (`home_screen.dart`) ; une étape dont la scène remplit l'écran doit fixer son `TourPlacement` |
| Nouvel écran à documenter par des bulles | valeur dans `TourId` + script dans `tour_step.dart` (+ `stepsFor`) + `Stack` autour du body de l'écran avec `CloudTour` gardé par `showTourProvider(TourId.x)` et `complete(...)` en `onFinish` |
| Apparence du tuto (nuage, placement, halo) | régénérer `test/features/tour/goldens/` puis **regarder** les images avant de committer — un golden mis à jour sans être vu enregistre le bug comme vérité |

## Widget d'écran d'accueil

| Modification | Fichier(s) à mettre à jour |
|---|---|
| Widget écran d'accueil | `features/home_widget/` (`widget_sync_service.dart`, `widget_providers.dart`, `widget_settings_screen.dart`, `domain/pin_order.dart` réordonnancement pur testé, `widget_background.dart` isolate) + `android/.../DewDropWidgetProvider.kt` + `res/{layout,xml,drawable}` + 2 receivers manifest. **Contrat de clés** (`signed_in` / `slot{i}_*` / `sent_id` / `sent_at`…) partagé Dart ↔ Kotlin ↔ isolate — changer un côté = changer les trois. Source = `profiles.widget_source` + `widget_friends`. |

## Publication et journal

| Modification | Fichier(s) à mettre à jour |
|---|---|
| **Changement visible par un testeur** | une puce sous « Non publié » de [`../CHANGELOG.md`](../CHANGELOG.md), **dans le commit qui le produit**. Écrire au fil de l'eau est ce qui empêche le journal de décrocher : tenu seulement au moment d'un `ship.py`, il ne recueille que les releases et perd tout le reste. |
| Version expédiée | renommer « Non publié » en `## [<version>] — <date>` et rouvrir une section « Non publié » vide. Le tag `v<version>` est posé par `ship.py`, pas à la main. |
| Procédure de publication Play | `tools/release/publish_play.py` (API Android Publisher v3) + [`../../play-store-publication-guide.md`](../../play-store-publication-guide.md). Service account JSON dans `../.dewdrop-secrets/play-sa.json` — **hors dépôt** (repo public) |
| Étape ajoutée / retirée de la release | `tools/release/ship.py` (le compteur `total` **et** la numérotation des étapes) + `architecture.md` § outils de release + `CLAUDE.md` § VI |

## Divers

| Modification | Fichier(s) à mettre à jour |
|---|---|
| Texte légal | `lib/.../legal_screen.dart` **et** `docs/index.html` (garder synchro) |
| Nouvel anti-pattern découvert | section « Anti-patterns à éviter » d'[`architecture.md`](./architecture.md) |
| Changement de dépendance critique | `CLAUDE.md` § III « Pile » + `pubspec.yaml` |
