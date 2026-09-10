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
2. **Sécurité Supabase** : toute table lue/écrite exige **RLS** **et** **GRANT** — au rôle `authenticated`, **et à `service_role` si une Edge Function la lit** (`service_role` outrepasse la RLS, jamais les privilèges de table ; oublier le GRANT → `42501`, que PostgREST rend comme une réponse **vide** — la fonction dégrade en silence). `verify_prod.py` contrôle cette liste contre le serveur, le dépôt ne pouvant pas la voir. `profiles` est **owner-only** (lire les autres = vue **`public_profiles`**) ; les helpers RLS (`are_friends`, `is_blocked`, `is_group_member`…) vivent dans le schéma **`private`** (`search_path=''`, non exposé en RPC).
3. **Riverpod sans codegen** : providers à la main. **NE PAS** réintroduire `riverpod_generator`/`riverpod_lint` (conflit freezed 3 / Dart 3.11). `AsyncValue.value`, pas `valueOrNull`.
4. **Décors en Canvas** : pas de fragment shader runtime (ne rend pas sur desktop) → `CustomPainter`. Fond statique vs couche animée (perf). Une **variante = une vraie scène** (même scène en Dessin **et** Photo), pas une teinte. `buildDecor` **clippe chaque décor à ses bords** (`ClipRect`) ; le backdrop sur-dessine ~6 % au-delà pour ne jamais révéler de gap au tilt. Images warp (`full.webp`+`depth.webp`) via cache LRU partagé `DecorImageCache` (jamais disposer le handle du cache — emprunter un `clone()`).
5. **Aucun secret commité** (repo **public**) : clé SMTP via `env(BREVO_SMTP_KEY)` ; keystore + `android/key.properties` gitignorés (convention du conteneur : [`../android-signing-guide.md`](../android-signing-guide.md)) ; service account FCM dans `supabase/functions/.env` gitignoré.
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
flutter build apk --release \          # APK testeurs (appbundle = AAB Play, mêmes options) — signé via
  --dart-define=SUPABASE_URL=https://<ref>.supabase.co \    # android/key.properties ; sans les --dart-define,
  --dart-define=SUPABASE_ANON_KEY=<clé publishable>         # l'app compile et ne joint QUE le Supabase local
supabase migration new <slug>          # nouvelle migration (prod : supabase db push)
supabase config push                   # config auth (SMTP, gabarits, redirects). CLI >= 2.114 OBLIGATOIRE — avant,
                                       # seuls les SUJETS partent, corps en anglais sans alerte. Env : BREVO_SMTP_KEY +
                                       # SUPABASE_ACCESS_TOKEN. Vérifier le SERVEUR, pas la sortie du CLI (voir docs).
python tools/release/ship.py --notes-file <notes.txt> --push   # RELEASE, 9 étapes : arbre propre → version non
                                       # déjà expédiée → analyze → test → build → contrôle du binaire → publication →
                                       # tag `v<version>` → vérif prod → push (main ET tag)
python tools/release/verify_prod.py    # ce que le SERVEUR sert vraiment (gabarits, RPC) — après un push Supabase
python tools/release/publish_play.py --list-tracks          # tracks Play + versionCodes en place
python tools/release/publish_play.py --track alpha --dry-run  # valide sans rien publier
flutter test --update-goldens test/features/tour/cloud_tour_golden_test.dart  # puis REGARDER les images
```

## VII. Maintenance documentaire

**Règle d'or** : le diff du code et celui de la doc associée sont dans **le même commit**.

**Carte complète des déclencheurs** (décors, son, tutos, widget, notifications, backend) : [`docs/maintenance-map.md`](./docs/maintenance-map.md). Les entrées les plus faciles à oublier :

| Modification | Fichier(s) à mettre à jour |
|---|---|
| **Changement visible par un testeur** | une puce sous « Non publié » de [`CHANGELOG.md`](./CHANGELOG.md), **dans le commit qui le produit** — sinon le journal décroche |
| Table / colonne / RLS / Realtime | nouvelle migration `supabase/migrations/` (**+ GRANT**) + `docs/architecture.md` |
| Nouveau flux d'auth par email | **un gabarit FR de plus** (`supabase/templates/`) + `[auth.email.template.<flux>]` + `_mustBeOverridden` — un gabarit manquant = mail **anglais** silencieux |
| Phrase d'une pensée reçue | `thoughtLine`/`senderLabel` (`thoughts/domain/thought.dart`) **et** la phrase jumelle de `send-thought-push` — l'app et la notif disent la même chose |
| Contrat de clés du widget | Dart ↔ Kotlin ↔ isolate : changer un côté = changer les trois |
| Nouveau décor / variante | `environment.dart` + `<décor>_decor.dart` + pipeline `depth_split` + **chaque** variante dans `pubspec.yaml` (pas de wildcard) |
| Nouvel anti-pattern découvert | section « Anti-patterns à éviter » de `docs/architecture.md` |
| Changement de dépendance critique | Section III « Pile » + `pubspec.yaml` |

## VIII. Contexte de Session

- **Dernier focus** : **journal et traçabilité des versions**. `CHANGELOG.md` couvre de nouveau tout l'historique et porte une section « Non publié » à tenir au fil de l'eau — c'est le seul journal, la page Releases de GitHub n'existe plus. `ship.py` marque d'un tag annoté `v<version>` le commit de chaque publication, et refuse en tête de course une version déjà expédiée.
- **Focus immédiat** : deux ajouts livrés attendent une preuve **sur appareil** — l'**ajout en ami depuis un cercle** et le branchement UI de la **suggestion de handle** (son versant serveur est couvert par `verify_prod.py`). En attente par ailleurs : tags absents pour les versions `+14` à `+37` ; appui long widget → « Reconfigurer » (dépend du launcher) ; durcissement `HomeWidgetBackgroundReceiver` ; **iOS** WidgetKit (bloqué compte Apple Developer 99 $/an).
