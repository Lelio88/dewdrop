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
| `profile` | Profil 1:1 : handle unique, pseudo, décor/mode, heures calmes (IANA tz), anonymat, **`sound_prefs`**. Onboarding. |
| `friends` | Demandes d'ami par **@handle / QR (`qr_invite.dart`) / lien (`dewdrop://invite`)**, accepter/refuser, **bloquer / signaler**. Listes **temps réel** (Realtime). |
| `thoughts` | Envoyer une pensée (option anonyme), liste reçue **live** + **éclat du décor** ; throttle des notifs. |
| `settings` | Picker de décor + **Son par décor** (volumes/on-off/fréquences, persisté au profil), heures calmes, **suppression de compte**, À-propos / **Crédits** / **Légal**. |
| `home` | Garde (onboarding vs accueil) + accueil = décor en fond + menu (identité centrée, sans avatar). |
| `ambient` | **Moteur de son** : ambiance + musique en boucle + planificateur de one-shots ; lit `SoundPrefs`. |
| `notifications` | Push **FCM** : token (`devices`), canal Android `thoughts_v3` (son goutte d'eau). |

## Infrastructure partagée

| Module | Rôle |
|---|---|
| `lib/src/common/glass.dart` | Matériau UI signature (glassmorphism) : `GlassCard`, `GlassTextField`, `GlassButton`. |
| `lib/src/common/decor_choice.dart` | (dé)sérialise `"env:variant"` ↔ `(Environment, int)` + `RenderMode`. |
| `lib/src/common/deep_links.dart` | Source unique des deep links `dewdrop://` (login-callback, reset-password, invite) + parseur d'invitation. |
| `lib/src/common/invite_links.dart` | Écoute (`app_links`) les liens `dewdrop://invite?handle=…` (cold start + à chaud) → demande d'ami. |
| `lib/src/supabase/supabase_config.dart` | URL + clé Supabase (locale par défaut, **auto `10.0.2.2` sur Android émulateur** ; override `--dart-define`). |
| `lib/src/routing/app_router.dart` | GoRouter + redirect auth ; routes publiques `/sign-in`, `/forgot-password` ; `/reset-password`. |
| `lib/decor/environment.dart` | Registre des **8 ambiances** + fabrique `buildDecor()`. |
| `lib/decor/tilt.dart` | Parallax gyroscope à **neutre adaptatif** (cf. moteur de décors). |

## Le moteur de décors

- **Rendu Canvas uniquement.** Les *fragment shaders runtime* **ne s'affichent pas** sur desktop → tout en `CustomPainter`. **Perf** : séparer un **fond statique** d'une **couche animée** (`repaint: model`).
- **Variantes** : une variante = une **vraie scène différente** (éléments, composition), pas une teinte ; cohérente entre Dessin et Photo.
- **Parallax (tilt)** : `tilt.dart` lit l'accéléromètre (~50 Hz). Le **neutre est adaptatif** — un lissage rapide suit l'orientation, un lissage lent (le neutre) la chase → le repos = ta position courante, un tilt tenu revient au centre, **jamais bloqué à un bord**. Deux réglages : `sensitivity` (force), `recenter` (vitesse de retour).
- **Mode photo** (`photo_decor.dart`) : parallax **multi-couches** (`assets/photo/<env>/<variant>/0.webp` = fond … `N.webp` = avant). Chaque couche a son fond **reconstruit par inpainting LaMa** (ce qui est plus proche est effacé puis comblé), pour éviter la **« trace »** du sujet quand un plan glisse. Nb de plans + feather **par scène** (`SCENE_SETTINGS`), `depthStrength` par décor atténue le parallaxe là où la profondeur est peu fiable (espace ≈ plat). Pipeline : `split_all.py` (Depth Anything V2 + LaMa, GPU si torch CUDA) → couches PNG dans `tools/depth_split/_src/` → `export_webp.py` → `assets/photo/*.webp`.
- **Burst de réception** : `buildDecor(..., {reception})` accepte un `ReceptionSignal` (`ChangeNotifier` découplé — pas de Riverpod dans le moteur). À la réception d'une pensée, le décor joue un **burst propre à la variante**. Le home alimente le signal depuis **Realtime** (live) **et** une détection **à l'ouverture/reprise**.

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
- **Réconciliation sérialisée** : `_apply()` est **sérialisé + coalescé** (un seul passage à la fois). Sinon, un vieux `play()` peut finir après un `pause()` récent → son bloqué « à fond » (bug corrigé). Le volume est passé **directement à `play()`** (jamais de blast à 1.0). Mute = `pause()`/`resume()` ; changer de décor = `play()` d'une nouvelle source.

## Deep links & emails d'auth

- **Scheme custom `dewdrop://`** (`lib/src/common/deep_links.dart`), déclaré côté Android (intent-filter) **et** iOS (`CFBundleURLTypes`). Trois usages : `login-callback` (confirmation d'inscription), `reset-password`, `invite`. Les deux premiers sont consommés par **supabase_flutter** (PKCE) ; `invite` par `InviteLinkListener`. Tout deep link d'auth **doit** figurer dans `additional_redirect_urls` (`config.toml`) sinon Supabase refuse la redirection.
- **Reset** : `sendPasswordReset(redirectTo: reset-password)` → email → l'app rouvre en mode recovery → `ResetPasswordScreen` → `updateUser(password)`. Formulation **anti-énumération** (ne révèle pas si l'email a un compte).
- **Emails via Brevo (SMTP)** : `[auth.email.smtp]` dans `config.toml` (`pass = env(BREVO_SMTP_KEY)`, jamais commitée). Templates FR brandés `supabase/templates/{confirmation,recovery}.html` (sujet « …DewDrop » → filtrables). Poussés par `supabase config push`.

## Temps réel (Realtime)

- Tables publiées dans `supabase_realtime` : `thoughts` (pensées reçues) et `friendships` (demandes/accepts). La RLS s'applique au Realtime → un client ne reçoit que ses lignes.
- Les repos exposent un **flux qui émet un compteur `int`** (`watchIncoming`, `watchChanges`) — **jamais `void`** : deux `AsyncValue<void>` identiques sont avalés par `==` et ne re-notifient pas Riverpod. Les `FutureProvider` de liste **`ref.watch`** ce flux → refetch live. Filet de sécurité : `app.dart` rafraîchit les listes **au retour d'app** (Realtime peut rater des events en arrière-plan) ; pull-to-refresh sur l'écran Amis.

## Données & sécurité (Supabase)

Tables : `profiles` (1:1 `auth.users`, trigger `handle_new_user`, `sound_prefs` jsonb, `last_thought_push_at`), `friendships` (`pending`/`accepted`, `are_friends()`), `thoughts`, `devices` (tokens FCM), `blocks` + `reports` (`is_blocked()`).

**Double barrière obligatoire** sur chaque table accédée par l'app :
1. **RLS** (`enable row level security` + policies `to authenticated`) — quelles **lignes**.
2. **GRANT** (`grant … to authenticated`) — privilèges **table**. Sans GRANT → `42501 permission denied` même si la RLS autorise.

### Patterns imposés

- **Migrations immuables** — une migration `supabase/migrations/<ts>_*.sql` déjà jouée n'est **jamais** éditée ; corriger = nouvelle migration.
- **Fonction SQL `language sql`** : valide son corps à la création → la définir **après** les tables référencées.
- **Repository** : une classe pure par feature dans `data/`, prend `SupabaseClient`, traduit `Map` → modèle `domain/`. Jointures inter-tables **en Dart** (`inFilter`), pas en embed PostgREST.
- **Riverpod sans codegen** : providers à la main ; `ref.watch` d'un flux Realtime pour l'auto-refresh, `ref.invalidate(...)` sinon.

### Flux typique — « envoyer une pensée → notification »

1. `FriendsScreen` : tap sur un ami → `SendThoughtSheet` (anonyme seedé par `profile.default_anonymous`).
2. `ThoughtRepository.sendThought(recipientId, anonymous)` → POST `/rest/v1/thoughts` (JWT → rôle `authenticated`).
3. Postgres : policy `insert` vérifie `auth.uid() = sender_id AND are_friends(...) AND not is_blocked(...)`.
4. **Webhook DB** → **Edge Function** `send-thought-push` : lit les `devices` du destinataire (hors quiet hours, fuseau IANA), **throttle** (`last_thought_push_at`, cooldown 60 s), envoie un push **FCM** (canal `thoughts_v3`).
5. Destinataire : notification ; Realtime → `incomingThoughtPulseProvider` (tick) → **burst du décor** + refetch de `receivedThoughtsProvider`.

## Distribution & déploiement

- **Signature release** : `android/app/build.gradle.kts` lit `android/key.properties` (gitignoré) ; fallback clés debug si absent.
- **Diffusion testeurs** : **Firebase App Distribution** (`firebase appdistribution:distribute … --app <id> --testers …`).
- **Page légale** : `docs/index.html` servie par **GitHub Pages** (`https://lelio88.github.io/dewdrop/`) ; à garder synchro avec `legal_screen.dart`.
- **Cloud Supabase** : `supabase db push` (migrations) + `supabase config push` (auth). Build app : `--dart-define` URL/clé.

## Anti-patterns à éviter

- ❌ Réintroduire `riverpod_generator` / `riverpod_lint` (conflit freezed 3 / Dart 3.11) ; `AsyncValue.valueOrNull` → `.value`.
- ❌ Un flux Realtime qui émet `void` (les ticks identiques sont avalés) → émettre un **compteur**.
- ❌ `_apply()` audio non sérialisé (course → son bloqué) ; `play()` sans passer le volume (blast à 1.0).
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
