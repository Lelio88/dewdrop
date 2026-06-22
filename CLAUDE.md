# DewDrop — Contexte d'Opération et Garde-Fous Agentiques

Résolvez les problèmes sans introduire de régression ni de dette technique architecturale.

## I. Finalité

**Application** : DewDrop — app mobile cosy pour **envoyer une pensée** à un ami (signal pur « X a pensé à toi », sans contenu). Anti-spam = culture, pas de feed.
**Objectif métier** : de douces *good vibes*, sur des **décors immersifs** choisis (espace, sous l'eau, forêt, plage, bibliothèque, montagne, désert, aurores boréales, champs), en style **dessiné** ou **photo**, chacun avec son **ambiance sonore + musique** réglables.

## II. Architecture

**Modèle** : Flutter **feature-first** (Clean Architecture) sous `lib/src/features/` + un **moteur de décors** autonome sous `lib/decor/`. État via **Riverpod (sans codegen)**, navigation **GoRouter**, backend **Supabase** (Postgres + Auth + RLS + Realtime), push/crash **Firebase** (FCM + Crashlytics), emails **Brevo**.

**Détails complets** (couches, moteur de décors, son, RLS/GRANT, mode photo, deep links, realtime, emails) : voir [`docs/architecture.md`](./docs/architecture.md).

Topologie rapide :
- `lib/decor/` — moteur de décors (Canvas) : `environment.dart` (registre 8 ambiances + `buildDecor`), `*_decor.dart` (FX bespoke par décor, par-dessus la photo), `decor_backdrop.dart` (warp de profondeur photo/aquarelle + aplat `baseColor` au chargement), `tilt.dart` (parallax gyroscope à neutre adaptatif).
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
4. **Décors en Canvas** : pas de fragment shader runtime (ne rend pas sur desktop) → `CustomPainter`. Fond statique vs couche animée (perf). Une **variante = une vraie scène** (même scène en Dessin **et** Photo), pas une teinte.
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
| Réglage parallaxe d'une scène | force par décor : `_strengthByEnv` dans `lib/decor/decor_backdrop.dart` (Dart) ; régénérer les assets = `tools/depth_split/warp_batch.py` |
| Texte légal | `lib/.../legal_screen.dart` **et** `docs/index.html` (garder synchro) |
| Style/texte des notifs envoyées | listes émojis/phrases dans `thought_style.dart` ; assemblage par `send-thought-push` (les deux côtés) |
| Logique de groupe (RLS, fan-out) | nouvelle migration (helpers `private`) + `features/groups/` + RPC `send_to_group` |
| Affichage/groupement des notifs reçues | `thought_notifications.dart` (app) **et** le payload `data` de `send-thought-push` |
| Nouveau son / piste audio | recette `tools/sounds/build_audio.sh` + attribution `CREDITS.md` |
| Changement de dépendance critique | Section « Pile » + `pubspec.yaml` |

## VIII. Contexte de Session

- **Dernier focus** : **durcissement sécurité** (helpers RLS → schéma `private`, `profiles` owner-only + vue `public_profiles`, anti-flood 25/min, rotation clé service account + clé API Firebase restreinte) ; **notifications v2** (messages *data* → notifs **groupées** « DewDrop », alerte une fois, silencieuses en heures calmes) ; **groupes** (cercles partagés + `send_to_group`). Diffusion testeurs **v0.5.0**.
- **Focus immédiat** : **test end-to-end à deux** (notifs groupées + groupes). Puis **iOS** (prep faite, **bloqué compte Apple Developer 99 $/an**) et **Play Store** (compte 25 $, captures, test fermé 14 j — voir `docs/play-store-listing.md`).
