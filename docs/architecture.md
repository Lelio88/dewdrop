# DewDrop — Architecture

## Vue d'ensemble

DewDrop est une app Flutter dont l'expérience repose sur deux piliers :
1. un **moteur de décors immersifs** (`lib/decor/`) rendu au Canvas, et
2. une **app sociale minimale** (`lib/src/`) sur **Supabase** (Postgres + Auth + RLS).

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

Règle : `presentation → application → domain ← data`. La **composition root** (`lib/main.dart`, `lib/src/app.dart`, les `*_providers.dart`) est le seul endroit qui instancie les repositories (via `Supabase.instance.client`). Le **moteur de décors** (`lib/decor/`) est transverse (pas une feature) : `buildDecor(env, variant, mode, {child})` rend le décor plein écran avec l'UI qui flotte par-dessus (`child`).

## Features

| Feature | Rôle |
|---|---|
| `auth` | Inscription/connexion email (Supabase Auth), état de session. |
| `profile` | Profil 1:1 avec le compte : handle unique, pseudo, décor/mode, heures calmes, anonymat. Onboarding (choix handle/pseudo). |
| `friends` | Demandes d'ami (pending/accepted) par @handle, accepter/refuser, liste. |
| `thoughts` | Envoyer une pensée à un ami (option anonyme), historique des pensées reçues. |
| `settings` | Picker de décor (ambiance × variante + Dessin/Photo), persisté au profil. |
| `home` | Garde (onboarding vs accueil) + accueil = décor en fond + menu. |

## Infrastructure partagée

| Module | Rôle |
|---|---|
| `lib/src/common/glass.dart` | Matériau UI signature : `GlassCard`, `GlassTextField`, `GlassButton` (glassmorphism). |
| `lib/src/common/decor_choice.dart` | (dé)sérialise le décor `"env:variant"` ↔ `(Environment, int)` + `RenderMode`. |
| `lib/src/supabase/supabase_config.dart` | URL + clé Supabase (locales par défaut, override `--dart-define`). |
| `lib/src/routing/app_router.dart` | GoRouter + redirect auth (`GoRouterRefreshStream` sur `onAuthStateChange`). |
| `lib/decor/environment.dart` | Registre des 7 ambiances + fabrique `buildDecor()` (drawn/photo). |

## Le moteur de décors

- **Rendu Canvas uniquement.** Les *fragment shaders runtime* (`FragmentProgram`) **ne s'affichent pas** sur Flutter Windows desktop → tout est en `CustomPainter`. Le `.frag` reste pour un futur path mobile (Impeller).
- **Perf** : séparer un **fond statique** (`*BgPainter`, repeint au resize) d'une **couche animée** (`*FxPainter`, `repaint: model`) pour ne pas redessiner les éléments lourds à chaque frame (cf. `forest_decor.dart`).
- **Variantes** : une variante = une **vraie scène différente** (éléments, composition), pas une teinte. Les arbres procéduraux vivent dans `forest_tree.dart`.
- **Mode photo** (`photo_decor.dart`) : parallax **multi-couches** d'images (`assets/photo/<env>/<variant>/0.png` = fond … `N.png` = avant), couches avant transparentes, + overlay animé selon l'ambiance. Seuls les fichiers **numérotés** sont des couches (`base.png` = source, ignorée par le moteur et par git).
- **Cohérence Dessin↔Photo** : pour une variante donnée, le rendu dessiné doit représenter la **même scène** que la photo (autre style, pas autre lieu).

## Données & sécurité (Supabase)

Tables : `profiles` (1:1 `auth.users`, trigger `handle_new_user` à l'inscription), `friendships` (`pending`/`accepted`, fonction `are_friends()` *security definer*), `thoughts`.

**Double barrière obligatoire** sur chaque table accédée par l'app :
1. **RLS** (`enable row level security` + policies `to authenticated`) — qui voit/écrit quelles **lignes**.
2. **GRANT** (`grant select, insert, … to authenticated`) — privilèges **table**. Sans GRANT, l'app reçoit `42501 permission denied` même si la RLS autorise.

### Patterns imposés

- **Migrations immuables** — une migration `supabase/migrations/<ts>_*.sql` déjà jouée n'est **jamais** éditée ; corriger = nouvelle migration. (La CLI marque les fichiers joués et ne les rejoue pas → divergence silencieuse entre environnements local/prod.)
- **Fonction SQL `language sql`** : valide son corps à la création → la définir **après** les tables qu'elle référence (sinon `relation does not exist`).
- **Repository** : une classe pure par feature dans `data/`, prend `SupabaseClient`, traduit les lignes (`Map`) en modèles `domain/`. Jointures inter-tables faites **en Dart** (`inFilter`) plutôt qu'en embed PostgREST.
- **Riverpod sans codegen** : `Provider`/`FutureProvider`/`StreamProvider` écrits à la main ; `ref.invalidate(...)` pour rafraîchir.

### Flux typique — « envoyer une pensée »

1. `FriendsScreen` : tap sur un ami → ouvre `SendThoughtSheet`.
2. Toggle anonyme (seedé par `profile.default_anonymous`) → `ThoughtRepository.sendThought(recipientId, anonymous)`.
3. `supabase_flutter` POST `/rest/v1/thoughts` (JWT du user → rôle `authenticated`).
4. Postgres : la policy `insert` vérifie `auth.uid() = sender_id AND are_friends(sender, recipient)` → insert ou rejet.
5. Côté destinataire : `ThoughtsScreen` → `receivedThoughtsProvider` → `receivedThoughts()` (`select` filtré par RLS, jointure du sender en Dart, masqué si anonyme).

Le *push* temps réel n'existe pas encore (FCM à venir) ; l'historique in-app fait foi.

## Anti-patterns à éviter

- ❌ Réintroduire `riverpod_generator` / `riverpod_lint` (conflit freezed 3 / Dart 3.11).
- ❌ Utiliser un fragment shader runtime comme rendu principal d'un décor sur desktop (ne rend pas).
- ❌ Créer une table sans **GRANT** au rôle `authenticated` (en plus de la RLS).
- ❌ Éditer une migration déjà appliquée.
- ❌ `AsyncValue.valueOrNull` (n'existe plus en Riverpod 3.x) → `.value`.
- ❌ Une variante de décor qui n'est qu'un changement de couleur d'une autre.
- ❌ `127.0.0.1` pour Supabase depuis un émulateur Android → utiliser `http://10.0.2.2:54321`.

## Stratégie de test

État actuel : **peu de tests** (prototype rapide, dette assumée). Cible : TDD pour la logique métier (repositories, providers), tests widget sur les écrans interactifs (robot pattern), goldens sur le design-system glass. Vérification minimale **obligatoire** avant commit : `flutter analyze` vert + build qui passe.

## Dépendances externes critiques

| Dépendance | Rôle | Note |
|---|---|---|
| Supabase (local, Docker) | Auth + Postgres + RLS | `supabase start`/`stop` ; Studio `:54323`, Mailpit `:54324`. |
| Depth Anything V2 (PyTorch) | `tools/depth_split` : profondeur → couches photo | venv local lourd, **non committé** (régénérable). |
| FCM (à venir) | Notifications push | nécessitera un projet Firebase. |
