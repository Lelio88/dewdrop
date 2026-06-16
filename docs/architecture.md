# DewDrop — Architecture

## Vue d'ensemble

DewDrop est une app Flutter dont l'expérience repose sur deux piliers :
1. un **moteur de décors immersifs** (`lib/decor/`) rendu au Canvas — avec, pour chaque décor, une **ambiance sonore + musique** (`lib/src/features/ambient/`), et
2. une **app sociale minimale** (`lib/src/`) sur **Supabase** (Postgres + Auth + RLS) avec **notifications push** (FCM).

L'app est un **client** : elle n'expose pas d'API HTTP ; elle parle à Supabase via `supabase_flutter` (PostgREST + GoTrue). En dev, Supabase tourne **en local** (Docker, via la CLI). Le décor choisi par l'utilisateur devient le **fond vivant** de toute l'app.

## Couches

```
┌───────────────────────────────────────────────────────────┐
│ presentation/   écrans, sheets, widgets (ConsumerWidget)   │
│      │  watch / read                                       │
│ application/    providers Riverpod (Provider/Future/Stream)│  ← état
│      │                                                     │
│ domain/         modèles immuables (Profile, Friend, …)     │
│      ▲  implémente                                         │
│ data/           repositories  ──►  supabase_flutter        │
└──────┼────────────────────────────────────────────────────┘
       ▼
   Supabase local (PostgREST + GoTrue)  ──►  Postgres + RLS
```

Règle : `presentation → application → domain ← data`. La **composition root** (`lib/main.dart`, `lib/src/app.dart`, les `*_providers.dart`) est le seul endroit qui instancie les repositories (via `Supabase.instance.client`). Le **moteur de décors** (`lib/decor/`) est transverse (pas une feature) : `buildDecor(env, variant, mode, {child, reception})` rend le décor plein écran avec l'UI qui flotte par-dessus (`child`) et un `ReceptionSignal` optionnel pour le burst de réception.

## Features

| Feature | Rôle |
|---|---|
| `auth` | Inscription/connexion email (Supabase Auth), état de session. Erreurs traduites en messages FR via `authErrorMessage`. |
| `profile` | Profil 1:1 avec le compte : handle unique, pseudo, décor/mode, heures calmes (IANA tz), anonymat, **`sound_prefs`** (perso son). Onboarding. |
| `friends` | Demandes d'ami (pending/accepted) par @handle, accepter/refuser, liste. |
| `thoughts` | Envoyer une pensée à un ami (option anonyme), historique des pensées reçues. |
| `settings` | Picker de décor (ambiance × variante + Dessin/Photo) **+ panneau Son par décor** (volumes, on/off, fréquences), persisté au profil. |
| `home` | Garde (onboarding vs accueil) + accueil = décor en fond + menu + bouton son maître. |
| `ambient` | **Moteur de son** : ambiance + musique en boucle + planificateur de one-shots ; lit la perso (`SoundPrefs`). |
| `notifications` | Push **FCM** : enregistrement du token (`devices`), canal Android `thoughts_v2` (son goutte d'eau). |

## Infrastructure partagée

| Module | Rôle |
|---|---|
| `lib/src/common/glass.dart` | Matériau UI signature : `GlassCard`, `GlassTextField`, `GlassButton` (glassmorphism). |
| `lib/src/common/decor_choice.dart` | (dé)sérialise le décor `"env:variant"` ↔ `(Environment, int)` + `RenderMode`. |
| `lib/src/supabase/supabase_config.dart` | URL + clé Supabase (locales par défaut ; **auto `10.0.2.2` sur Android** ; override `--dart-define`). |
| `lib/src/routing/app_router.dart` | GoRouter + redirect auth (`GoRouterRefreshStream` sur `onAuthStateChange`). |
| `lib/decor/environment.dart` | Registre des **8 ambiances** + fabrique `buildDecor()` (drawn/photo). |
| `lib/src/features/ambient/application/ambient_providers.dart` | Recette audio par décor (`kDecorAudio`) + moteur `SoundscapeNotifier` + perso `SoundPrefsNotifier`. |

## Le moteur de décors

- **Rendu Canvas uniquement.** Les *fragment shaders runtime* (`FragmentProgram`) **ne s'affichent pas** sur Flutter Windows desktop → tout est en `CustomPainter`.
- **Perf** : séparer un **fond statique** (`*BgPainter`, repeint au resize) d'une **couche animée** (`*FxPainter`, `repaint: model`) pour ne pas redessiner les éléments lourds à chaque frame (cf. `forest_decor.dart`).
- **Variantes** : une variante = une **vraie scène différente** (éléments, composition), pas une teinte. Les arbres procéduraux vivent dans `forest_tree.dart`.
- **Mode photo** (`photo_decor.dart`) : parallax **multi-couches** auto-découvertes (`assets/photo/<env>/<variant>/0.png` = fond … `N.png` = avant ; `base.png` = source, ignorée). Chaque couche est **inpaintée** (tout ce qui est plus proche est effacé → bord feutré qui se fond, pas de couture) ; le **nombre de plans** + le feather sont réglés **par scène** (`tools/depth_split/split_all.py` → `SCENE_SETTINGS`), et un **`depthStrength` par décor** atténue le parallaxe là où la profondeur est peu fiable (espace ≈ plat).
- **Cohérence Dessin↔Photo** : pour une variante donnée, le rendu dessiné doit représenter la **même scène** que la photo (autre style, pas autre lieu).
- **Burst de réception** : `buildDecor(..., {reception})` accepte un `ReceptionSignal` (`lib/decor/reception_signal.dart`, un `ChangeNotifier` découplé — pas de Riverpod dans le moteur). Quand l'utilisateur reçoit une pensée, le home le **pulse** et le décor actif joue un **burst amplifié, propre à la variante courante** (pluie d'étoiles filantes, rideau de feuilles, houle de bulles…). Le **tap** sur le décor reste un aperçu plus léger du même effet. Le home alimente le signal depuis **Supabase Realtime** (live) **et** une détection **à l'ouverture/reprise** (pensées reçues hors-ligne ; 1er lancement = historique considéré comme vu).

## Le son (soundscape)

Deux couches **indépendantes** par décor, en boucle, plus des sons ponctuels :

```
master (bouton home)
 ├─ ambiance  (assets/audio/<env>_amb.ogg, ~-28 LUFS)   ┐ on/off + volume par décor
 ├─ musique   (assets/audio/<env>_mus.ogg, ~-18 LUFS)   ┘ (musique nettement > ambiance)
 └─ one-shots (assets/audio/oneshot/*.ogg) — 1 timer par catégorie, intervalle aléatoire
       baleines · pages · ronron · pigeon · tonnerre · virevoltants · craquements · scintillement
```

- **Catégories** : les one-shots sont groupés par catégorie (`kDecorAudio[env].secondaries`), chacune avec son **volume + fréquence** réglables. L'aurore a 2 musiques alternées au hasard.
- **Égalisation par groupe** (pré-rendue dans les assets) : toutes les musiques à ~-18 LUFS, toutes les ambiances à ~-28 LUFS → changer de décor ne fait pas sauter le niveau, et l'ambiance reste sous la musique. Pipeline reproductible : `tools/sounds/build_audio.sh` (dossier de travail **non committé**).
- **Personnalisation** (`SoundPrefs`) : on/off + volume (ambiance, musique) et on/off + volume + fréquence (par catégorie), édités **en live** dans le picker de décor, **synchronisés au profil** (`profiles.sound_prefs` jsonb, débounce). Le moteur réagit via `ref.listen(soundPrefsProvider)`.
- **audioplayers** : `play()` ne redémarre pas fiablement après `stop()` → mute = `pause()`/`resume()` ; changer de décor = `play()` d'une nouvelle source.

## Données & sécurité (Supabase)

Tables : `profiles` (1:1 `auth.users`, trigger `handle_new_user`, colonne `sound_prefs` jsonb), `friendships` (`pending`/`accepted`, `are_friends()` *security definer*), `thoughts`, `devices` (tokens push FCM).

**Double barrière obligatoire** sur chaque table accédée par l'app :
1. **RLS** (`enable row level security` + policies `to authenticated`) — qui voit/écrit quelles **lignes**.
2. **GRANT** (`grant select, insert, … to authenticated`) — privilèges **table**. Sans GRANT, l'app reçoit `42501 permission denied` même si la RLS autorise.

### Patterns imposés

- **Migrations immuables** — une migration `supabase/migrations/<ts>_*.sql` déjà jouée n'est **jamais** éditée ; corriger = nouvelle migration.
- **Fonction SQL `language sql`** : valide son corps à la création → la définir **après** les tables qu'elle référence.
- **Repository** : une classe pure par feature dans `data/`, prend `SupabaseClient`, traduit les lignes (`Map`) en modèles `domain/`. Jointures inter-tables **en Dart** (`inFilter`) plutôt qu'en embed PostgREST.
- **Riverpod sans codegen** : `Provider`/`FutureProvider`/`StreamProvider`/`Notifier` écrits à la main ; `ref.invalidate(...)` pour rafraîchir.

### Flux typique — « envoyer une pensée → notification »

1. `FriendsScreen` : tap sur un ami → `SendThoughtSheet` (toggle anonyme seedé par `profile.default_anonymous`).
2. `ThoughtRepository.sendThought(recipientId, anonymous)` → POST `/rest/v1/thoughts` (JWT → rôle `authenticated`).
3. Postgres : la policy `insert` vérifie `auth.uid() = sender_id AND are_friends(sender, recipient)` → insert ou rejet.
4. Le **webhook DB** (migration `thoughts_push_webhook`) appelle l'**Edge Function** `send-thought-push`, qui lit les `devices` du destinataire (hors `quiet hours`, dans son fuseau IANA) et envoie un push **FCM** (canal `thoughts_v2`).
5. Destinataire : notification (son goutte d'eau) ; à l'ouverture, `ThoughtsScreen` → `receivedThoughtsProvider` (RLS, jointure sender en Dart, masqué si anonyme).

## Anti-patterns à éviter

- ❌ Réintroduire `riverpod_generator` / `riverpod_lint` (conflit freezed 3 / Dart 3.11).
- ❌ Utiliser un fragment shader runtime comme rendu principal d'un décor sur desktop (ne rend pas).
- ❌ Créer une table sans **GRANT** au rôle `authenticated` (en plus de la RLS).
- ❌ Éditer une migration déjà appliquée.
- ❌ `AsyncValue.valueOrNull` (n'existe plus en Riverpod 3.x) → `.value`.
- ❌ Une variante de décor qui n'est qu'un changement de couleur d'une autre.
- ❌ Publier sur NATS/FCM ou écrire la BD hors du flux prévu ; afficher une exception brute à l'utilisateur (traduire via `authErrorMessage`).
- ❌ `127.0.0.1` pour Supabase depuis un émulateur Android (géré auto par `SupabaseConfig` ; ne pas le re-câbler en dur).

## Stratégie de test

État actuel : **peu de tests** (prototype rapide, dette assumée). Cible : TDD pour la logique métier (repositories, providers, fonctions pures comme `SoundPrefs`/`authErrorMessage`/`parseDecor`), tests widget sur les écrans interactifs (robot pattern), goldens sur le design-system glass. Vérification minimale **obligatoire** avant commit : `flutter analyze` vert + build qui passe.

## Dépendances externes critiques

| Dépendance | Rôle | Note |
|---|---|---|
| Supabase (local, Docker) | Auth + Postgres + RLS + Edge Functions | `supabase start`/`stop` ; Studio `:54323`, Mailpit `:54324`. Prod : `supabase db push`. |
| Firebase / FCM | Notifications push | projet Firebase + `google-services.json` ; Edge Function `send-thought-push`. |
| Depth Anything V2 (PyTorch) | `tools/depth_split` : profondeur → couches photo | venv local lourd, **non committé** (régénérable). |
| ffmpeg + sources CC0/PD | `tools/sounds/build_audio.sh` : assets audio | dossier de travail **non committé** ; voir `CREDITS.md`. |
