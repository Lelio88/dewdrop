# DewDrop 🌿

Envoyer une **pensée** à quelqu'un. Pas de spam, pas de feed — juste de douces *good vibes* :
« Lelio a pensé à toi ✨ ». Une app mobile cosy, avec des **décors immersifs** qu'on choisit
(espace, forêt, sous l'eau, plage, montagne, désert, bibliothèque, aurores boréales), en style
**dessiné** ou **photo**, chacun avec son **ambiance sonore + musique** réglables par décor.

> Confidentialité & CGU : <https://lelio88.github.io/dewdrop/>

## Stack

- **App** : Flutter (Riverpod **sans codegen**, GoRouter, freezed). **Android** (live, testeurs via
  Firebase App Distribution) ; **iOS** via **Codemagic** (CI macOS — pas besoin d'un Mac).
- **Décors** : moteur Canvas maison (parallax gyroscope à **neutre adaptatif**, particules par
  variante, éclat à la réception) + un mode **photo** en parallax multi-couches (profondeur
  **Depth Anything V2** + inpainting **LaMa**).
- **Son** : 2 couches par décor (ambiance + musique en boucle) + sons ponctuels aléatoires
  (baleines, tonnerre, virevoltants…) via `audioplayers` ; volumes/fréquences réglables par décor,
  synchronisés au profil.
- **Backend** : **Supabase** (Postgres + Auth + RLS + Realtime) — cloud en prod, **local via
  Docker** pour le dev.
- **Push & crash** : **Firebase** — Cloud Messaging (notifs **groupées**, construites par l'app
  depuis des messages *data*), Crashlytics (rapports), App Distribution (diffusion aux testeurs).
- **Emails** : **Brevo** (SMTP) pour les mails de confirmation / reset — templates FR brandés.

## Fonctionnalités

- **Comptes** email + **confirmation obligatoire** (anti-abus) + reset de mot de passe.
- **Deep links** `dewdrop://` : confirmation d'inscription, reset, **invitation par lien**.
- **Amis & groupes** : ajout par @handle / **QR** / **lien** ; **cercles partagés** (le créateur
  gère les membres, tout membre envoie au groupe) ; demandes en **temps réel**, **bloquer / signaler**.
- **Pensées** : envoi à un **ami ou un groupe** (option **anonyme**), réception **live** (liste +
  éclat du décor), **heures calmes**, **notification personnalisable** (émojis + phrase, page « Pensées »).
- **Notifications groupées** : une seule alerte + un groupe « DewDrop » avec une sous-notif par
  expéditeur ; **silencieuses** pendant les heures calmes ; **désactivables**.
- **Suppression de compte** (cascade) · **page légale** hébergée (GitHub Pages).

## Structure

```
lib/
├── decor/            # moteur de décors (Canvas) + tilt.dart (parallax) + mode photo
└── src/
    ├── app.dart · routing/ · common/ (deep_links, glass) · supabase/
    └── features/     # auth · profile · friends · thoughts · settings · home · ambient · notifications
supabase/
├── migrations/       # schéma (profiles, friendships, thoughts, blocks…) + RLS + Realtime
├── functions/        # Edge Functions (send-thought-push, delete-account)
└── config.toml       # auth : SMTP Brevo, templates FR, redirections deep-link
tools/depth_split/    # Python : photo → plans de profondeur (Depth Anything V2 + inpainting LaMa)
docs/index.html       # page Confidentialité & CGU (servie par GitHub Pages)
assets/photo/         # décors photo (0..N.webp = couches parallax) — sources hors-bundle dans tools/depth_split/_src/
assets/audio/         # sons par décor (*_amb / *_mus en boucle ; oneshot/ = sons ponctuels)
```

## Démarrer

Prérequis : [Flutter](https://flutter.dev), [Docker](https://www.docker.com/),
[Supabase CLI](https://supabase.com/docs/guides/cli).

```bash
cd dewdrop

# 1. Backend local (Postgres / Auth / Realtime via Docker)
supabase start

# 2. App — desktop pour itérer vite (le mobile a le gyroscope + FCM réels)
flutter run -d windows
```

- Supabase Studio : <http://127.0.0.1:54323> · Mails de test (Mailpit) : <http://127.0.0.1:54324>

### Build contre le cloud (pour les testeurs)

```bash
flutter build apk --release \
  --dart-define=SUPABASE_URL=https://<ref>.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=<clé publishable>
```

La **signature de release** lit `android/key.properties` (gitignoré). Sans ce fichier, le build
retombe sur les clés debug. Diffusion aux testeurs via **Firebase App Distribution**.

### Décors photo (parallax)

Source `Base.png` dans `tools/depth_split/_src/<env>/<variante>/`, puis :

```bash
cd tools/depth_split
python -m venv .venv
# CPU : .venv/Scripts/pip install torch --index-url https://download.pytorch.org/whl/cpu
# GPU NVIDIA (bien plus rapide) :
#       .venv/Scripts/pip install torch --index-url https://download.pytorch.org/whl/cu128
.venv/Scripts/pip install -r requirements.txt
.venv/Scripts/pip install simple-lama-inpainting --no-deps
.venv/Scripts/python split_all.py _src   # profondeur + inpainting LaMa → couches PNG
.venv/Scripts/python export_webp.py      # PNG → assets/photo/*.webp
```

## État

✅ Comptes + confirmation email · ✅ Profil/handle · ✅ Décors (dessin + photo, parallaxe
désactivable, éclat de réception **aussi en photo**) · ✅ **Amis + groupes** (cercles partagés) ·
✅ Pensées (anonyme, live, heures calmes, **notif personnalisable**) · ✅ **Notifications v2**
(groupées, alerte unique, silencieuses en heures calmes, **désactivables**) · ✅ Son par décor
(lecteurs **mixés** + **aperçu ▶**) · ✅ **Sécurité durcie** (RLS schéma `private`, vue `public_profiles`,
anti-flood, secrets rotés) · ✅ Deep links · ✅ SMTP Brevo · ✅ Crashlytics · ✅ Signature release ·
✅ Page légale hébergée · ✅ Diffusion testeurs (Firebase App Distribution, **v0.5.0**).

🔜 **iOS** : prep faite (app Firebase iOS, `codemagic.yaml`, scheme, permission caméra) — **bloqué
sur le compte Apple Developer (99 $/an)** requis pour la signature + APNs + TestFlight.
🔜 **Play Store** : déploiement prod.
