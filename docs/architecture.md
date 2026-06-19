# DewDrop — Architecture

## Vue d'ensemble

DewDrop est une app Flutter dont l'expérience repose sur deux piliers :
1. un **moteur de décors immersifs** (`lib/decor/`) rendu au Canvas — avec, pour chaque décor, une **ambiance sonore + musique** (`lib/src/features/ambient/`), et
2. une **app sociale minimale** (`lib/src/`) sur **Supabase** (Postgres + Auth + RLS + Realtime) avec **notifications push** (FCM), **rapports de crash** (Crashlytics) et **emails transactionnels** (SMTP Brevo).

L'app est un **client** : elle n'expose pas d'API HTTP ; elle parle à Supabase via `supabase_flutter` (PostgREST + GoTrue + Realtime). Le backend tourne **en cloud** pour les builds de prod/testeurs (sélectionné via `--dart-define`) et **en local** (Docker, via la CLI) en dev. Le décor choisi devient le **fond vivant** de toute l'app.

## Couches

```
┌───────────────────────────────────────────────────────────┐
│ presentation/   écrans, sheets, widgets (ConsumerWidget)   │
│      │  watch / read / listen                              │
│ application/    providers Riverpod (Provider/Future/Stream)│  ← état
│      │                                                     │
│ domain/         modèles immuables + interfaces repo        │
│      ▲  implémente                                         │
│ data/           repositories  ──►  supabase_flutter        │
└──────┼────────────────────────────────────────────────────┘
       ▼
   Supabase (cloud OU local Docker) : PostgREST + GoTrue + Realtime  ──►  Postgres + RLS
   Firebase : FCM (push) · Crashlytics (crash)        Brevo : SMTP (emails auth)
```

Règle : `presentation → application → domain ← data`. La **composition root** (`lib/main.dart`, `lib/src/app.dart`, les `*_providers.dart`) est le seul endroit qui instancie les repositories (via `Supabase.instance.client`). `app.dart` (un `ConsumerStatefulWidget`) câble aussi les listeners transverses : enregistrement push, **deep link de récupération de mot de passe**, **lien d'invitation** (`InviteLinkListener`), et un **refresh des listes au retour d'app**. Le **moteur de décors** (`lib/decor/`) est transverse (pas une feature) : `buildDecor(env, variant, mode, {child, reception})` rend le décor plein écran avec l'UI qui flotte par-dessus.

## Features

| Feature | Rôle |
|---|---|
| `auth` | Inscription/connexion email (**confirmation obligatoire**), **reset de mot de passe** + **confirmation d'inscription** par deep link, suppression de compte (Edge Function). Erreurs traduites FR (`authErrorMessage`) ; signup détecte « email déjà pris » (identities vide). |
| `profile` | Profil 1:1 : handle unique, pseudo, décor/mode, heures calmes (IANA tz), anonymat, **`sound_prefs`**, **`thought_style`** (style de notif envoyée). Onboarding. |
| `friends` | **Gestion** (l'envoi a migré vers « Envoyer une pensée ») : demandes d'ami par **@handle / QR / lien HTTPS cliquable**, accepter/refuser, **bloquer / signaler**, + **création/gestion de groupes**. Listes **temps réel**. |
| `groups` | **Cercles partagés** (`groups` / `group_members` / `group_blocks`). Le créateur gère les membres (parmi ses amis) ; **tout membre** envoie au groupe via le RPC **`send_to_group`** (fan-out). Quitter / **bloquer** / supprimer un groupe. |
| `thoughts` | **« Envoyer une pensée »** (`send_thoughts_screen.dart`) : choisir un **ami ou un groupe** (option anonyme). Réception **live** + **éclat du décor**. Page **« Pensées »** (`thought_settings_screen.dart`) : anonymat + **style de notif** (machine à sous 3 rouleaux, aperçu live → `thought_style`). |
| `settings` | Picker de décor + **Son par décor** (+ **aperçu ▶** par piste), **toggle parallaxe**, **heures calmes**, **toggle « notifications »** (`notifications_enabled`), liens → « Pensées », **suppression de compte**, À-propos / Crédits / Légal. |
| `home` | Garde (onboarding vs accueil) + accueil = décor en fond + menu (`Pensées reçues · Pensées · Envoyer une pensée · Amis · Univers · Réglages`). |
| `ambient` | **Moteur de son** : ambiance + musique + one-shots ; lit `SoundPrefs`. **Aperçu** (`sound_preview.dart`) : lecteur dédié pour écouter une piste sans toucher au son en cours. |
| `notifications` | Push **FCM en messages *data*** : l'app construit des notifs **groupées** (`thought_notifications.dart`) — 1 groupe « DewDrop » + 1 enfant par expéditeur/groupe, **alerte une fois** (`onlyAlertOnce` + `GroupAlertBehavior.summary`), **silencieuses** pendant les heures calmes (canal `thoughts_silent`). Tokens dans `devices`. |

## Infrastructure partagée

| Module | Rôle |
|---|---|
| `lib/src/common/glass.dart` | Matériau UI signature (glassmorphism) : `GlassCard`, `GlassTextField`, `GlassButton`. |
| `lib/src/common/decor_choice.dart` | (dé)sérialise `"env:variant"` ↔ `(Environment, int)` + `RenderMode`. |
| `lib/src/common/deep_links.dart` | Source unique des liens : auth `dewdrop://` (login-callback, reset-password) + **lien d'invitation HTTPS** (→ page `docs/invite.html`) + parseur (accepte HTTPS **et** `dewdrop://invite`). |
| `lib/src/common/invite_links.dart` | Écoute (`app_links`) les liens `dewdrop://invite?handle=…` (cold start + à chaud) → demande d'ami. |
| `lib/src/supabase/supabase_config.dart` | URL + clé Supabase (locale par défaut, **auto `10.0.2.2` sur Android émulateur** ; override `--dart-define`). |
| `lib/src/routing/app_router.dart` | GoRouter + redirect auth ; routes publiques `/sign-in`, `/forgot-password` ; `/reset-password`. |
| `lib/decor/environment.dart` | Registre des **8 ambiances** + fabrique `buildDecor()`. |
| `lib/decor/tilt.dart` | Parallax gyroscope à **neutre adaptatif** (cf. moteur de décors). |
| `lib/decor/decor_backdrop.dart` | **Fond parallaxe partagé** : déforme l'image entière en **maillage de profondeur** (`drawVertices` + `ImageShader`, Canvas pur, pas de shader runtime) — chaque sommet déplacé de `profondeur × tilt`. Repli **couches** (legacy) si une scène ne ship pas `full.webp`+`depth.webp`. |

## Le moteur de décors

- **Rendu Canvas uniquement.** Les *fragment shaders runtime* **ne s'affichent pas** sur desktop → tout en `CustomPainter`. **Perf** : séparer un **fond statique** d'une **couche animée** (`repaint: model`).
- **Variantes** : une variante = une **vraie scène différente** (éléments, composition), pas une teinte ; cohérente entre Dessin et Photo.
- **Parallax (tilt)** : `tilt.dart` lit l'accéléromètre (~50 Hz). Le **neutre est adaptatif** — un lissage rapide suit l'orientation, un lissage lent (le neutre) la chase → le repos = ta position courante, un tilt tenu revient au centre, **jamais bloqué à un bord**. Deux réglages : `sensitivity` (force), `recenter` (vitesse de retour). **Désactivable** via `buildDecor(..., parallax:)` (depuis `parallaxEnabledProvider`, device-local) : à off, les décors ignorent le tilt.
- **Pipeline unifié (photo & dessin)** : depuis `environment.dart`, **chaque décor** = un `DecorBackdrop` **+ son painter FX bespoke par-dessus**, sur les **deux** modes. Le `RenderMode` choisit juste l'arbre d'assets — `assets/photo/` (photoréaliste) ou `assets/illustrated/` (aquarelle) : **même scène, mêmes FX**.
- **Warp de profondeur (rendu actuel).** Chaque scène embarque **`full.webp`** (l'image entière) + **`depth.webp`** (carte de profondeur grayscale **lossless**, à la résolution du maillage). `DecorBackdrop` rend l'image en **maillage `drawVertices`** : la coordonnée de texture de chaque sommet est déplacée de `profondeur × tilt` → le proche bouge plus que le lointain (parallaxe). Le maillage **s'étire** aux ruptures de profondeur (il ne se **déchire** jamais) → **aucun trou, aucun inpaint, donc aucun halo / fantôme / aura**. C'est ce qui a remplacé le **découpage en couches** (qui forçait un inpaint du fond dévoilé en parallaxe — source intarissable d'artefacts). Profondeur via **Depth-Anything V2 Large + guided filter**. Pipeline : `warp_assets.py` / `warp_batch.py` — **juste la profondeur**, ~2 s/scène (fini SAM / matting / inpaint). Réglages : `_warpShift` (force globale) + `_strengthByEnv` (force par décor — espace plus doux, paysages plus francs). *Legacy abandonné : le découpage `split_*` / `sam_*`, `photo_decor.dart`, et le repli « couches » de `DecorBackdrop`.*
- **Mode dessin (aquarelle)** : `illustrate_all.py` stylise chaque source en **aquarelle storybook** (SDXL img2img), **sans humain** (negative prompt) ni **filigrane**. Le **même warp de profondeur** s'y applique — `assets/illustrated/<env>/<v>/{full,depth}.webp`.
- **Burst de réception** : `buildDecor(..., {reception})` accepte un `ReceptionSignal` (`ChangeNotifier` découplé — pas de Riverpod dans le moteur). À la réception d'une pensée, le décor joue un **effet propre à la variante** (tempête de sable, nappe de brume, jaillissement de bulles, surge de lucioles, cascade de feuilles…) — **dans les deux modes**, le FX étant le même au-dessus du `DecorBackdrop`. Un **tap** en rejoue un aperçu. Le home alimente le signal depuis **Realtime** (live) **et** une détection **à l'ouverture/reprise** (un burst par pensée non vue, plafonné).

## Le son (soundscape)

Deux couches **indépendantes** par décor (boucle) + sons ponctuels :

```
ambiance  (assets/audio/<env>_amb.ogg, ~-28 LUFS)   ┐ on/off + volume par décor
musique   (assets/audio/<env>_mus.ogg, ~-18 LUFS)   ┘ (musique nettement > ambiance)
one-shots (assets/audio/oneshot/*.ogg) — 1 timer par catégorie, intervalle aléatoire
     baleines · pages · ronron · pigeon · tonnerre · virevoltants · craquements · scintillement
```

- **Égalisation par groupe** pré-rendue (musiques ~-18 LUFS, ambiances ~-28 LUFS). Pipeline : `tools/sounds/build_audio.sh` (dossier de travail **non committé**).
- **Personnalisation** (`SoundPrefs`) : on/off + volume (couches) + on/off + volume + fréquence (catégories), éditée **en live** dans le picker, **synchronisée au profil** (`profiles.sound_prefs` jsonb, débounce).
- **Mixage des lecteurs** : un **`AudioContext` global** (`AndroidAudioFocus.none` + iOS `mixWithOthers`, posé dans `main.dart`). Sans lui, chaque lecteur prend le **focus audio exclusif** et coupe les autres (la musique noyait l'ambiance, les one-shots ne passaient jamais).
- **Réconciliation sérialisée** : `_apply()` est **sérialisé + coalescé** (un seul passage à la fois). Sinon, un vieux `play()` peut finir après un `pause()` récent → son bloqué « à fond » (bug corrigé). Le volume est passé **directement à `play()`** (jamais de blast à 1.0). Mute = `pause()`/`resume()` ; changer de décor = `play()` d'une nouvelle source.

## Deep links & emails d'auth

- **Scheme custom `dewdrop://`** (`lib/src/common/deep_links.dart`), déclaré côté Android (intent-filter) **et** iOS (`CFBundleURLTypes`). Usages auth : `login-callback` (confirmation d'inscription) + `reset-password`, consommés par **supabase_flutter** (PKCE) — ils **doivent** figurer dans `additional_redirect_urls` (`config.toml`) sinon Supabase refuse la redirection.
- **Invitation** : le lien partagé est **HTTPS** (`lelio88.github.io/dewdrop/invite.html?handle=…`, page `docs/invite.html`) — cliquable dans toute messagerie, avec repli Play Store. La page propose « Ouvrir dans DewDrop » → `dewdrop://invite?handle=…`, capté par `InviteLinkListener` → demande d'ami. Le QR encode le même lien HTTPS. (App Links auto-vérifiés = amélioration future : nécessite `assetlinks.json` au root du domaine + SHA-256 Play App Signing.)
- **Reset** : `sendPasswordReset(redirectTo: reset-password)` → email → l'app rouvre en mode recovery → `ResetPasswordScreen` → `updateUser(password)`. Formulation **anti-énumération** (ne révèle pas si l'email a un compte).
- **Emails via Brevo (SMTP)** : `[auth.email.smtp]` dans `config.toml` (`pass = env(BREVO_SMTP_KEY)`, jamais commitée). Templates FR brandés `supabase/templates/{confirmation,recovery}.html` (sujet « …DewDrop » → filtrables). Poussés par `supabase config push`.

## Temps réel (Realtime)

- Tables publiées dans `supabase_realtime` : `thoughts`, `friendships`, `groups` et `group_members`. La RLS s'applique au Realtime → un client ne reçoit que ses lignes.
- Les repos exposent un **flux qui émet un compteur `int`** (`watchIncoming`, `watchChanges`) — **jamais `void`** : deux `AsyncValue<void>` identiques sont avalés par `==` et ne re-notifient pas Riverpod. Les `FutureProvider` de liste **`ref.watch`** ce flux → refetch live. Filet de sécurité : `app.dart` rafraîchit les listes **au retour d'app** (Realtime peut rater des events en arrière-plan) ; pull-to-refresh sur l'écran Amis.

## Données & sécurité (Supabase)

Tables : `profiles` (1:1 `auth.users`, trigger `handle_new_user`, `sound_prefs` + `thought_style` jsonb, `notifications_enabled`), `friendships` (`pending`/`accepted`), `thoughts` (+ `group_id` nullable pour le fan-out), `devices` (tokens FCM), `blocks` + `reports`, `groups` / `group_members` / `group_blocks`.

**Double barrière obligatoire** sur chaque table accédée par l'app :
1. **RLS** (`enable row level security` + policies `to authenticated`) — quelles **lignes**.
2. **GRANT** (`grant … to authenticated`) — privilèges **table**. Sans GRANT → `42501 permission denied` même si la RLS autorise.

**Cloisonnement** : `profiles` n'est lisible **que par son propriétaire** ; les autres passent par la **vue `public_profiles`** (handle/nom/avatar only). Les helpers RLS (`are_friends`, `is_blocked`, `is_group_member`, `is_group_creator`) vivent dans le schéma **`private`** (non exposé par PostgREST, `search_path = ''`) → pas de récursion de policy ni d'énumération par RPC. Anti-flood : trigger **25 pensées/min** par expéditeur (les pensées de groupe en sont exemptées, plafonnées dans `send_to_group`).

### Patterns imposés

- **Migrations immuables** — une migration `supabase/migrations/<ts>_*.sql` déjà jouée n'est **jamais** éditée ; corriger = nouvelle migration.
- **Fonction SQL `language sql`** : valide son corps à la création → la définir **après** les tables référencées.
- **Repository** : une classe pure par feature dans `data/`, prend `SupabaseClient`, traduit `Map` → modèle `domain/`. Jointures inter-tables **en Dart** (`inFilter`), pas en embed PostgREST.
- **Riverpod sans codegen** : providers à la main ; `ref.watch` d'un flux Realtime pour l'auto-refresh, `ref.invalidate(...)` sinon.

### Flux typique — « envoyer une pensée → notification »

1. **« Envoyer une pensée »** (`send_thoughts_screen.dart`) : choisir un **ami** ou un **groupe** → `SendThoughtSheet` (anonyme seedé par `profile.default_anonymous`).
2. Ami → `ThoughtRepository.sendThought` (POST `/rest/v1/thoughts`). Groupe → RPC **`send_to_group(p_group, p_anonymous)`** (`SECURITY DEFINER`) qui **fan-out** : une `thought` par autre membre (membership + blocages vérifiés), `group_id` posé.
3. Pour un envoi direct, la policy `insert` vérifie `auth.uid() = sender_id AND private.are_friends(...) AND not private.is_blocked(...)`.
4. **Webhook DB** → Edge Function `send-thought-push` : vérifie l'appelant (rôle `service_role` via le claim JWT), saute si `notifications_enabled = false`, calcule **`silent`** selon les heures calmes (fuseau IANA — plus de skip, juste silencieux), assemble le corps (style ; pour un groupe : « X a pensé au groupe Y ») et envoie un **message *data* FCM** par device.
5. Côté app : le **background handler** (`thought_notifications.dart`) construit la notif **groupée** (1 « DewDrop » + 1 enfant par expéditeur/groupe, **alerte une fois**, silencieuse en heures calmes). En foreground, Realtime → `incomingThoughtPulseProvider` → **burst du décor** ; à l'ouverture, on **vide** le groupe + rejoue les bursts non vus.

## Distribution & déploiement

- **Signature release** : `android/app/build.gradle.kts` lit `android/key.properties` (gitignoré) ; fallback clés debug si absent.
- **Diffusion testeurs** : **Firebase App Distribution** (`firebase appdistribution:distribute … --app <id> --testers …`).
- **GitHub Pages** (`https://lelio88.github.io/dewdrop/`, dossier `docs/`) : `index.html` (page légale, synchro avec `legal_screen.dart`) + **`invite.html`** (page d'atterrissage d'invitation, synchro avec `DeepLinks.invite`).
- **Cloud Supabase** : `supabase db push` (migrations) + `supabase config push` (auth). Build app : `--dart-define` URL/clé.
- **iOS** : pas de Mac → CI **Codemagic** (`codemagic.yaml`, workflow iOS → TestFlight ; un script y injecte `GoogleService-Info.plist` dans la target Xcode « Runner »). **Prep faite** depuis Windows : app Firebase iOS + plist, scheme `dewdrop://`, `NSCameraUsageDescription`, bundle `app.dewdrop`, compte/repo/vars Codemagic. **Bloqué** sur le **compte Apple Developer (99 $/an)** — requis pour la signature, la clé **APNs** (push) et **TestFlight** ; aucun des trois n'a d'alternative gratuite.

## Anti-patterns à éviter

- ❌ Réintroduire `riverpod_generator` / `riverpod_lint` (conflit freezed 3 / Dart 3.11) ; `AsyncValue.valueOrNull` → `.value`.
- ❌ Un flux Realtime qui émet `void` (les ticks identiques sont avalés) → émettre un **compteur**.
- ❌ `_apply()` audio non sérialisé (course → son bloqué) ; `play()` sans passer le volume (blast à 1.0) ; **lecteurs audio sans `AudioContext` global** (focus exclusif → ils se coupent l'un l'autre).
- ❌ Commiter un secret (clé SMTP, keystore, service account) — repo public.
- ❌ Créer une table sans **GRANT** ; éditer une migration déjà appliquée.
- ❌ Un fragment shader runtime comme rendu principal sur desktop ; une variante = simple changement de couleur.
- ❌ `127.0.0.1` pour Supabase depuis un émulateur Android (géré par `SupabaseConfig`).

## Stratégie de test

État : tests ciblés sur la logique pure + le câblage critique (`SoundPrefs`, `authErrorMessage`, `parseDecor`, **deep links**, **refresh temps réel des listes**) ; fakes manuels au boundary repo (`test/helpers/fakes.dart`). Cible : élargir aux écrans interactifs (robot pattern) + goldens design-system. Vérification **obligatoire** avant commit : `flutter analyze` vert + `flutter test` vert + build qui passe.

## Dépendances externes critiques

| Dépendance | Rôle | Note |
|---|---|---|
| Supabase (cloud + local Docker) | Auth + Postgres + RLS + Realtime + Edge Functions | dev : `supabase start` (Studio `:54323`, Mailpit `:54324`) ; cloud : `db push` / `config push`. |
| Firebase | FCM (push) · Crashlytics (crash) · App Distribution (testeurs) | projet `dewdrop-60229` + `google-services.json` (clé client, non secrète). |
| Brevo (SMTP) | Emails de confirmation / reset | sender vérifié ; clé via `env(BREVO_SMTP_KEY)` au `config push`. |
| Depth Anything V2 + **LaMa** (PyTorch) | `tools/depth_split` : profondeur → couches photo + inpainting | venv **non committé** ; GPU si torch CUDA (`cu128`). `simple-lama-inpainting --no-deps`. |
| ffmpeg + sources CC0/PD | `tools/sounds/build_audio.sh` : assets audio | dossier de travail **non committé** ; voir `CREDITS.md`. |
