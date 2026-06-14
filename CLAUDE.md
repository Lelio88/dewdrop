# DewDrop — Contexte d'Opération et Garde-Fous Agentiques

Résolvez les problèmes sans introduire de régression ni de dette technique architecturale.

## I. Finalité

**Application** : DewDrop — app mobile cosy pour **envoyer une pensée** à un ami (signal pur « X a pensé à toi », sans contenu, unidirectionnel). Anti-spam = culture, pas de feed.
**Objectif métier** : de douces *good vibes*, sur des **décors immersifs** choisis (espace, forêt, sous l'eau, plage, montagne, désert, bibliothèque), en style **dessiné** ou **photo**.

## II. Architecture

**Modèle** : Flutter **feature-first** (Clean Architecture) sous `lib/src/features/` + un **moteur de décors** autonome sous `lib/decor/`. État via **Riverpod (sans codegen)**, navigation **GoRouter**, backend **Supabase** (Postgres + Auth + RLS, en local via Docker).

**Détails complets** (couches, moteur de décors, RLS/GRANT, mode photo, outil de profondeur) : voir [`docs/architecture.md`](./docs/architecture.md).

Topologie rapide :
- `lib/decor/` — moteur de décors (Canvas) : `environment.dart` (registre + `buildDecor`), `*_decor.dart` (espace/forêt/sous-l'eau…), `photo_decor.dart` (parallax photo).
- `lib/src/features/<f>/{domain,data,application,presentation}/` — auth · profile · friends · thoughts · settings · home.
- `lib/src/{app,routing,common,supabase}/` — composition root, GoRouter, widgets glass, config Supabase.
- `supabase/migrations/` — schéma + RLS · `tools/depth_split/` — script Python (couches photo) · `assets/photo/` — images.

## III. Pile Technologique

*Versions contraintes par `pubspec.yaml`. N'introduisez aucune dépendance alternative sans approbation.*

- **Langage** : Dart 3.11 / Flutter 3.41 (stable).
- **État / nav** : `flutter_riverpod ^3.3` (**sans codegen**), `go_router`.
- **Modèles** : `freezed` (annotations) ou classes immuables manuelles.
- **Backend** : `supabase_flutter ^2.14` (Supabase local via Docker + CLI).
- **Capteurs** : `sensors_plus` (gyroscope/parallax).

## IV. Garde-Fous non négociables

1. **Migrations immuables** : une migration de `supabase/migrations/` déjà jouée n'est **jamais** modifiée. Pour corriger → nouvelle migration (sinon divergence silencieuse local/prod).
2. **Sécurité Supabase** : toute table lue/écrite par l'app exige **à la fois** une **politique RLS** **et** un **GRANT** au rôle `authenticated` (RLS = lignes, GRANT = privilèges table). Oublier le GRANT → `42501 permission denied`.
3. **Riverpod sans codegen** : providers écrits à la main. **NE PAS** réintroduire `riverpod_generator`/`riverpod_lint` (conflit freezed 3 / Dart 3.11). Utiliser `AsyncValue.value` (pas `valueOrNull`).
4. **Décors en Canvas** : les fragment shaders runtime **ne rendent pas** sur desktop → tout en `CustomPainter`. Séparer **fond statique** et **couche animée** (perf). Une **variante = une vraie scène** (contenu différent), pas un simple changement de palette.
5. **Cohérence Dessin↔Photo** : une variante représente la **même scène** dans les deux styles.
6. **Couplage** : `presentation` n'importe jamais `data` ; le cross-feature passe par `application`. Seule la composition root connecte les implémentations.

## V. Flux de Travail (Explore → Plan → Code → Verify)

1. **Exploration** — lire les fichiers adjacents pour calquer les patterns.
2. **Planification** — soumettre l'approche pour les changements non triviaux.
3. **TDD** — test d'abord, vérifier l'échec, **ne plus l'altérer**.
4. **Implémentation** — code minimal pour passer le test.
5. **Vérification** — `flutter analyze` (zéro issue) + build/run.

**Auto-documentation des packages** — tout nouveau fichier/feature publie en tête un doc comment : (1) ce qu'il fait, (2) les choix non-évidents + leur motivation, (3) les invariants à préserver, (4) un exemple d'usage si l'API n'est pas évidente. C'est ce qui permet de reconstruire la rationale sans docs externes périssables.

## VI. Commandes de Développement

```bash
supabase start                         # backend local (Docker)
flutter run -d windows                 # app en dev (desktop)
flutter analyze                        # lint (doit être vert)
flutter build windows --debug          # build de vérification
supabase migration new <slug>          # nouvelle migration
supabase migration up                  # appliquer en local
python tools/depth_split/split_all.py  # (dans le venv) couches photo
```

## VII. Maintenance documentaire

**Règle d'or** : le diff du code et celui de la doc associée sont dans **le même commit**.

| Modification | Fichier à mettre à jour |
|---|---|
| Nouvelle table / colonne / RLS | nouvelle migration `supabase/migrations/` (+ GRANT) |
| Nouveau décor / variante | `lib/decor/environment.dart` + assets, + `docs/architecture.md` |
| Nouvelle règle de couplage / anti-pattern | section dédiée de `docs/architecture.md` |
| Changement de dépendance critique | Section « Pile » + `pubspec.yaml` |

## VIII. Contexte de Session

- **Dernier focus** : cible Android opérationnelle (bundle id `app.dewdrop`, émulateur) + notifications push FCM de bout en bout (enregistrement du token dans `devices`, webhook `thoughts`→Edge Function, son de notification goutte d'eau sur le canal `thoughts_v2`).
- **Focus immédiat** : réglages in-app finalisés (heures calmes/anonymat) ; assets photo réels pour les décors restants ; cible iOS.
