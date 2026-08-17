# DewDrop — Contexte d'Opération et Garde-Fous Agentiques

Résolvez les problèmes sans introduire de régression ni de dette technique architecturale.

## I. Finalité

**Application** : DewDrop — app mobile cosy pour **envoyer une pensée** à un ami (signal pur « X a pensé à toi », sans contenu). Anti-spam = culture, pas de feed.
**Objectif métier** : de douces *good vibes*, sur des **décors immersifs** choisis (espace, sous l'eau, forêt, plage, bibliothèque, montagne, désert, aurores boréales, champs), en style **dessiné** ou **photo**, chacun avec son **ambiance sonore + musique** réglables.

## II. Architecture

**Modèle** : Flutter **feature-first** (Clean Architecture) sous `lib/src/features/` + un **moteur de décors** autonome sous `lib/decor/`. État via **Riverpod (sans codegen)**, navigation **GoRouter**, backend **Supabase** (Postgres + Auth + RLS + Realtime), push/crash **Firebase** (FCM + Crashlytics), emails **Brevo**.

**Détails complets** (couches, moteur de décors, son, RLS/GRANT, mode photo, deep links, realtime, emails) : voir [`docs/architecture.md`](./docs/architecture.md).

Topologie rapide :
- `lib/decor/` — moteur de décors (Canvas) : `environment.dart` (registre 9 ambiances + 3 mondes **saisonniers** masqués + `buildDecor`), `*_decor.dart` (FX bespoke par-dessus la photo), `decor_backdrop.dart` (warp de profondeur + aplat `baseColor`), `decor_image_cache.dart` (LRU partagé), `tilt.dart` (parallax gyroscope à neutre adaptatif).
- `lib/src/features/<f>/{domain,data,application,presentation}/` — auth · profile · friends · **groups** (cercles) · thoughts · settings · home · **home_widget** · **ambient** (son) · **notifications** (push groupé) · **tour** (tuto nuages).
- `lib/src/{app,routing,common,supabase}/` — composition root, GoRouter, `common/{deep_links,deep_link_listener,seasonal,decor_choice}.dart`, widgets glass, config Supabase.
- `supabase/{migrations,functions,templates,config.toml}` · `tools/{depth_split,sounds,mockups}/` · `docs/` (pages légales + invite hébergées) · `assets/{photo,illustrated,audio}/`.

## III. Pile Technologique

*Versions contraintes par `pubspec.yaml`. N'introduisez aucune dépendance alternative sans approbation.*

- **Langage** : Dart (SDK ^3.11) / Flutter (stable).
- **État / nav** : `flutter_riverpod ^3.3` (**sans codegen**), `go_router`.
- **Modèles** : `freezed ^3` ou classes immuables manuelles.
- **Backend** : `supabase_flutter ^2.14` (cloud en prod/testeurs ; local Docker en dev).
- **Push / crash** : `firebase_core` / `firebase_messaging` / `firebase_crashlytics`, `flutter_local_notifications`, `flutter_timezone`.
- **Deep links** : scheme `dewdrop://` via `app_links` (+ handling auth natif de supabase_flutter).
- **Amis** : `qr_flutter` (afficher un QR), `mobile_scanner` (scanner un QR).
- **Widget d'accueil** : `home_widget` (Android AppWidget + isolate).
- **Son / capteurs** : `audioplayers`, `sensors_plus` (gyroscope), `shared_preferences`.
- **Emails** : SMTP **Brevo** (configuré dans `supabase/config.toml` ; clé via env).
- **CI iOS** : **Codemagic** (`codemagic.yaml`, runners macOS — build/signe iOS sans Mac).

## IV. Garde-Fous non négociables

1. **Migrations immuables** : une migration `supabase/migrations/` déjà jouée n'est **jamais** modifiée. Corriger = nouvelle migration.
2. **Sécurité Supabase** : toute table lue/écrite exige **RLS** **et** **GRANT** au rôle `authenticated` (oublier le GRANT → `42501`). `profiles` est **owner-only** (lire les autres = vue **`public_profiles`**) ; les helpers RLS (`are_friends`, `is_blocked`, `is_group_member`…) vivent dans le schéma **`private`** (`search_path=''`, non exposé en RPC).
3. **Riverpod sans codegen** : providers à la main. **NE PAS** réintroduire `riverpod_generator`/`riverpod_lint` (conflit freezed 3 / Dart 3.11). `AsyncValue.value`, pas `valueOrNull`.
4. **Décors en Canvas** : pas de fragment shader runtime (ne rend pas sur desktop) → `CustomPainter`. Fond statique vs couche animée (perf). Une **variante = une vraie scène** (même scène en Dessin **et** Photo), pas une teinte. `buildDecor` **clippe chaque décor à ses bords** (`ClipRect`) ; le backdrop sur-dessine ~6 % au-delà pour ne jamais révéler de gap au tilt. Images warp (`full.webp`+`depth.webp`) via cache LRU partagé `DecorImageCache` (jamais disposer le handle du cache — emprunter un `clone()`).
5. **Aucun secret commité** (repo **public**) : clé SMTP via `env(BREVO_SMTP_KEY)` ; keystore + `android/key.properties` gitignorés ; service account FCM dans `supabase/functions/.env` gitignoré.
6. **Couplage** : `presentation` n'importe jamais `data` ; le cross-feature passe par `application` ; seule la composition root connecte les implémentations.
7. **Temps réel & son** : les flux Realtime émettent un **compteur** (jamais `void` — sinon `==` avale les ticks) ; un **`AudioContext` global** mixe les lecteurs (`AndroidAudioFocus.none`) et la réconciliation audio est **sérialisée**. Interrompre les **autres** apps est un concern distinct : `AudioFocus` prend le focus **une fois pour l'app** (jamais par lecteur). Voir docs.

## V. Flux de Travail (Explore → Plan → Code → Verify)

1. **Exploration** — lire les fichiers adjacents pour calquer les patterns.
2. **Planification** — soumettre l'approche pour les changements non triviaux.
3. **TDD** — test d'abord, vérifier l'échec, **ne plus l'altérer**.
4. **Implémentation** — code minimal pour passer le test.
5. **Vérification** — `flutter analyze` (zéro issue) + `flutter test` + build/run.

**Auto-documentation des packages** — tout nouveau fichier/feature publie en tête un doc comment : (1) ce qu'il fait, (2) les choix non-évidents + motivation, (3) les invariants à préserver, (4) un exemple d'usage si l'API n'est pas évidente.

## VI. Commandes de Développement

```bash
supabase start                         # backend local (Docker ; Studio :54323, Mailpit :54324)
flutter run -d windows                 # desktop (itération rapide ; mobile = gyroscope + FCM réels)
flutter analyze && flutter test        # doivent être verts
flutter build apk --release \          # build testeurs — signé via android/key.properties
  --dart-define=SUPABASE_URL=https://<ref>.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=<clé publishable>
supabase migration new <slug>          # nouvelle migration (prod : supabase db push)
supabase config push                   # config auth (SMTP, gabarits, redirects). CLI >= 2.114 OBLIGATOIRE :
                                       # avant, seuls les SUJETS partent, les corps restent en anglais sans alerte.
                                       # Env : BREVO_SMTP_KEY + SUPABASE_ACCESS_TOKEN (coffres hors dépôt).
                                       # Vérifier le résultat côté serveur, pas la sortie du CLI (docs/architecture.md).
flutter build appbundle --release \     # AAB pour le Play Store (mêmes --dart-define que l'APK)
  --dart-define=SUPABASE_URL=… --dart-define=SUPABASE_ANON_KEY=…
python tools/release/publish_play.py --list-tracks          # tracks Play + versionCodes en place
python tools/release/publish_play.py --track alpha --dry-run  # valide sans rien publier
python tools/release/publish_play.py --track alpha --notes-file <notes.txt>  # publie (test fermé)
# décors photo : Base.png → tools/depth_split/_src/<décor>/<v>/ → warp_batch.py
#   → assets/photo/<décor>/<v>/{full.webp,depth.webp} ; dessin = illustrate_all.py → assets/illustrated/
```

## VII. Maintenance documentaire

**Règle d'or** : le diff du code et celui de la doc associée sont dans **le même commit**.

| Modification | Fichier(s) à mettre à jour |
|---|---|
| Table / colonne / RLS / Realtime | nouvelle migration `supabase/migrations/` (**+ GRANT**) + `docs/architecture.md` |
| Nouveau décor / variante | `lib/decor/environment.dart` (enum + `buildDecor`) + `lib/decor/<décor>_decor.dart` + source `tools/depth_split/_src/…/Base.png` → `warp_batch.py`/`illustrate_all.py` + **chaque** variante dans `pubspec.yaml` (pas de wildcard) + `docs/architecture.md` |
| Réglage parallaxe d'une scène | `_warpShift`/`_strengthByEnv` dans `lib/decor/decor_backdrop.dart` ; régénérer via `warp_batch.py` |
| Nouveau deep link | `lib/src/common/deep_links.dart` + `additional_redirect_urls` (`config.toml`) + manifeste Android / `Info.plist` |
| Nouveau flux d'auth par email (magic link, changement d'adresse…) | **un gabarit FR de plus** dans `supabase/templates/` + sa section `[auth.email.template.<flux>]` (`config.toml`) + la liste `_mustBeOverridden` (`test/supabase/email_templates_test.dart`) — un gabarit manquant = mail **anglais** silencieux. Puis `supabase config push`. |
| Étape / texte du tuto d'accueil | `features/tour/domain/tour_step.dart` (`kHomeTour`, script pur) ; une nouvelle **cible** = valeur `TourAnchor` + `GlobalKey` posée sur le widget réel + entrée dans la map `anchors` (`home_screen.dart`) |
| Règles de découvrabilité (recherche de handle) | migration modifiant `search_profiles` **et** le paragraphe « Découvrabilité » de `docs/architecture.md` — les 5 garde-fous (≥3 car., ≥0.45, ≤3 résultats, handle seul, exclusions) se décident ensemble |
| Envoi « pensée » par lien / voix | deep link `dewdrop://send?to=<handle>` (`DeepLinks.sendTo`), `DeepLinkListener` (`common/deep_link_listener.dart` : invite **et** send), résolveur pur `matchFriend` (`features/friends/domain/friend_match.dart`), capability headless `QuickSendService` (`features/thoughts/application/`), confirmation 1-tap dans `app.dart` `_onSend`. *Service natif Kotlin AppFunctions = déféré (API en preview).* |
| Décors favoris / swipe accueil | snapshot `"<env>:<variant>:<mode>"` = `encodeFavorite`/`parseFavorite` (`lib/src/common/decor_choice.dart`) + `decorFavoritesProvider` (`features/settings/application/`) + ⭐ dans `decor_stories.dart` + swipe dans `home/presentation/home_screen.dart` + colonne `profiles.decor_favorites` (migration) |
| Gestes à deux crans (aperçus accueil) | machine à états pure `nextSheetState`/`SheetState` (`features/home/domain/home_sheet.dart`, testée) + `home_screen.dart` `_onDragEnd` + `received_peek.dart`/`send_dock.dart` (`expanded:`) |
| Univers marronnier (verrou par date) | `SeasonalEvent`/`activeSeasonalEvent`/`kSeasonalEvents` (`lib/src/common/seasonal.dart`, testé) + `seasonalOverrideProvider` (`features/settings/application/`) + `home_screen.dart` (override display-only) + `Environment` `christmas`/`halloween`/`april` (flag `seasonal`) + `{env}_decor.dart` + assets `depth_split` + audio `build_seasonal.sh` + `kDecorAudio` + `CREDITS.md` (+ `about_screen.dart` si CC-BY) |
| Widget écran d'accueil | `features/home_widget/` (`widget_sync_service.dart`, `widget_providers.dart`, `widget_settings_screen.dart`, `widget_background.dart` isolate) + `android/.../DewDropWidgetProvider.kt` + `res/{layout,xml,drawable}` + 2 receivers manifest. **Contrat de clés** (`signed_in`/`slot{i}_*`/`sent_id`/`sent_at`…) partagé Dart ↔ Kotlin ↔ isolate — changer un côté = changer les trois. Source = `profiles.widget_source`+`widget_friends`. |
| Style/texte des notifs envoyées | listes émojis/phrases dans `thought_style.dart` + assemblage `send-thought-push` (les deux côtés) |
| Affichage/groupement des notifs reçues | `notifications/application/thought_notifications.dart` + payload `data` de `send-thought-push` |
| Logique de groupe (RLS, fan-out) | nouvelle migration (helpers `private`) + `features/groups/` + RPC `send_to_group` |
| Nouveau son / piste audio | `tools/sounds/build_audio.sh` (ou `build_seasonal.sh`) + attribution `CREDITS.md` |
| Focus audio (interruption des autres apps) | `features/ambient/application/audio_focus.dart` **et** `MainActivity.kt` (canal `app.dewdrop/audio_focus`) + prise/rendu dans `SoundscapeNotifier` (`_applyInner`, `pauseAll`, `_teardown`) |
| Ordre du dock d'envoi | `sortByRecency` (`features/thoughts/domain/send_order.dart`, testé) + `recentContactsProvider` ; le tri est **gelé tant que le dock est visible** (`SendDock.visible` → invalidation différée) |
| Texte légal | `lib/.../legal_screen.dart` **et** `docs/index.html` (garder synchro) |
| Procédure de publication Play | `tools/release/publish_play.py` (API Android Publisher v3) + `../play-store-publication-guide.md`. Service account JSON dans `../.dewdrop-secrets/play-sa.json` — **hors dépôt** (repo public) |
| Nouvel anti-pattern découvert | section « Anti-patterns à éviter » de `docs/architecture.md` |
| Changement de dépendance critique | Section III « Pile » + `pubspec.yaml` |

## VIII. Contexte de Session

- **Dernier focus** : lot **accueil & découvrabilité** — (1) **tuto d'accueil** en bulles-nuage (feature `tour`, 5 étapes ancrées, rejouable depuis Réglages) qui remplace le hint texte éclair ; (2) **tous** les gabarits d'email auth désormais surchargés en FR (`email_change`, `magic_link`, `reauthentication`, `invite` s'ajoutent aux deux existants) + test de non-régression ; (3) **demande d'ami entre co-membres d'un groupe** ; (4) renvoi vers « Amis » en pied de l'écran d'envoi ; (5) repêchage **« Tu voulais dire… »** après un handle introuvable (migration `20260817120000_profiles_fuzzy_handle_search`, RPC `search_profiles`).
- **Focus immédiat** : (a) `supabase db push` (nouvelle migration) **et** `supabase config push` avec `BREVO_SMTP_KEY` — **les mails restent en anglais tant que le config push n'est pas rejoué** ; (b) vérifier par un vrai envoi (inscription + mot de passe oublié) que le corps reçu est bien le gabarit FR ; (c) on-device : le tuto au premier lancement + son rejeu depuis Réglages (spotlights bien alignés sur les poignées et le ☰), la suggestion de handle après une faute de frappe, le bouton « ajouter en ami » dans un groupe.
- **Restes hors lot** : appui long widget → « Reconfigurer » (dépend du launcher) ; durcissement sécu `HomeWidgetBackgroundReceiver` ; **iOS** WidgetKit (bloqué compte Apple Developer 99 $/an).
