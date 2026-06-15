# DewDrop — Contexte d'Opération et Garde-Fous Agentiques

Résolvez les problèmes sans introduire de régression ni de dette technique architecturale.

## I. Finalité

**Application** : DewDrop — app mobile cosy pour **envoyer une pensée** à un ami (signal pur « X a pensé à toi », sans contenu, unidirectionnel). Anti-spam = culture, pas de feed.
**Objectif métier** : de douces *good vibes*, sur des **décors immersifs** choisis (espace, sous l'eau, forêt, plage, bibliothèque, montagne, désert, aurores boréales), en style **dessiné** ou **photo**, chacun avec son **ambiance sonore + musique** réglables.

## II. Architecture

**Modèle** : Flutter **feature-first** (Clean Architecture) sous `lib/src/features/` + un **moteur de décors** autonome sous `lib/decor/`. État via **Riverpod (sans codegen)**, navigation **GoRouter**, backend **Supabase** (Postgres + Auth + RLS, en local via Docker), push **FCM**.

**Détails complets** (couches, moteur de décors, son, RLS/GRANT, mode photo, profondeur) : voir [`docs/architecture.md`](./docs/architecture.md).

Topologie rapide :
- `lib/decor/` — moteur de décors (Canvas) : `environment.dart` (registre 8 ambiances + `buildDecor`), `*_decor.dart` (un par ambiance), `photo_decor.dart` (parallax photo).
- `lib/src/features/<f>/{domain,data,application,presentation}/` — auth · profile · friends · thoughts · settings · home · **ambient** (moteur son) · **notifications** (push FCM).
- `lib/src/{app,routing,common,supabase}/` — composition root, GoRouter, widgets glass, config Supabase.
- `supabase/migrations/` — schéma + RLS · `tools/depth_split/` — script Python (couches photo) · `assets/photo/` — images · `assets/audio/` — sons par décor.

## III. Pile Technologique

*Versions contraintes par `pubspec.yaml`. N'introduisez aucune dépendance alternative sans approbation.*

- **Langage** : Dart 3.11 / Flutter 3.41 (stable).
- **État / nav** : `flutter_riverpod ^3.3` (**sans codegen**), `go_router`.
- **Modèles** : `freezed` (annotations) ou classes immuables manuelles.
- **Backend** : `supabase_flutter ^2.14` (Supabase local via Docker + CLI).
- **Son** : `audioplayers`, prefs device-local via `shared_preferences`.
- **Push** : `firebase_core`/`firebase_messaging`, `flutter_local_notifications`, `flutter_timezone`.
- **Capteurs** : `sensors_plus` (gyroscope/parallax).

## IV. Garde-Fous non négociables

1. **Migrations immuables** : une migration de `supabase/migrations/` déjà jouée n'est **jamais** modifiée. Pour corriger → nouvelle migration (sinon divergence silencieuse local/prod).
2. **Sécurité Supabase** : toute table lue/écrite par l'app exige **à la fois** une **politique RLS** **et** un **GRANT** au rôle `authenticated` (RLS = lignes, GRANT = privilèges table). Oublier le GRANT → `42501 permission denied`.
3. **Riverpod sans codegen** : providers écrits à la main. **NE PAS** réintroduire `riverpod_generator`/`riverpod_lint` (conflit freezed 3 / Dart 3.11). Utiliser `AsyncValue.value` (pas `valueOrNull`).
4. **Décors en Canvas** : les fragment shaders runtime **ne rendent pas** sur desktop → tout en `CustomPainter`. Séparer **fond statique** et **couche animée** (perf). Une **variante = une vraie scène** (contenu différent), pas un simple changement de palette.
5. **Cohérence Dessin↔Photo** : une variante représente la **même scène** dans les deux styles.
6. **Couplage** : `presentation` n'importe jamais `data` ; le cross-feature passe par `application`. Seule la composition root connecte les implémentations.
7. **Son par décor** : 2 couches (ambiance + musique en boucle) + sons ponctuels aléatoires ; niveaux **égalisés par groupe** (musique nettement au-dessus de l'ambiance) ; assets pré-rendus, perso synchronisée au profil. Voir docs.

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
flutter run -d emulator-5554           # app sur émulateur Android (auto 10.0.2.2)
flutter run -d windows                 # app desktop (itération rapide)
flutter analyze                        # lint (doit être vert)
supabase migration new <slug>          # nouvelle migration
supabase migration up                  # appliquer en local  (prod : supabase db push)
python tools/depth_split/split_all.py  # (dans le venv) couches photo (réglages par scène)
```

## VII. Maintenance documentaire

**Règle d'or** : le diff du code et celui de la doc associée sont dans **le même commit**.

| Modification | Fichier à mettre à jour |
|---|---|
| Nouvelle table / colonne / RLS | nouvelle migration `supabase/migrations/` (+ GRANT) |
| Nouveau décor / variante | `lib/decor/environment.dart` + assets, + `docs/architecture.md` |
| Nouveau son / piste audio | recette `tools/sounds/build_audio.sh` (régénère `assets/audio/`) + attribution dans `CREDITS.md` |
| Réglage parallaxe d'une scène | table `SCENE_SETTINGS` de `tools/depth_split/split_all.py` |
| Nouvelle règle de couplage / anti-pattern | section dédiée de `docs/architecture.md` |
| Changement de dépendance critique | Section « Pile » + `pubspec.yaml` |

## VIII. Contexte de Session

- **Dernier focus** : système **audio** complet — 2 couches/décor (ambiance + musique + one-shots aléatoires), égalisé par groupe, **personnalisation du son** par décor synchronisée au profil (`profiles.sound_prefs`). Décors **dessinés pour les 8 ambiances**. **Parallaxe photo** lissé (inpainting par plan + nb de plans par scène). Auth : messages d'erreur UI-friendly + `10.0.2.2` auto sur Android.
- **Focus immédiat** : test du flux « pensée → notif » de bout en bout sur émulateur ; cible iOS ; déploiement prod (`supabase db push` + `--dart-define` URL/clé).
