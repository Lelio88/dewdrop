# DewDrop 🌿

Envoyer une **pensée** à quelqu'un. Pas de spam, pas de feed — juste de douces *good vibes* :
« Lelio a pensé à toi ✨ ». Une app mobile cosy, avec des **décors immersifs** qu'on choisit
(espace, forêt, sous l'eau, plage, montagne, désert, bibliothèque, aurores boréales), en style
**dessiné** ou **photo**, chacun avec son **ambiance sonore + musique** réglables par décor.

## Stack

- **App** : Flutter (Riverpod, GoRouter, freezed) — Android d'abord, iOS ensuite.
- **Décors** : moteur Canvas maison (parallax gyroscope, particules) + un mode **photo** en
  parallax multi-couches (inpainting + nb de plans par décor).
- **Son** : 2 couches par décor (ambiance + musique en boucle) + sons ponctuels aléatoires
  (baleines, tonnerre, virevoltants…) via `audioplayers` ; volumes/fréquences réglables par décor.
- **Backend** : Supabase (Postgres + Auth + RLS), en **local via Docker** pour le développement.

## Structure

```
lib/
├── decor/            # moteur de décors (espace, forêt, sous-l'eau… + mode photo)
└── src/
    ├── app.dart · routing/ · common/ · supabase/
    └── features/     # auth · profile · friends · thoughts · settings · home
supabase/migrations/  # schéma (profiles, friendships, thoughts) + RLS
tools/depth_split/    # script Python : découpe une photo en plans de profondeur (Depth Anything V2)
assets/photo/         # décors photo (base.png = source ; 0..N.png = couches parallax générées)
assets/audio/         # sons par décor (*_amb / *_mus en boucle ; oneshot/ = sons ponctuels)
```

## Démarrer

Prérequis : [Flutter](https://flutter.dev), [Docker](https://www.docker.com/),
[Supabase CLI](https://supabase.com/docs/guides/cli).

```bash
cd dewdrop

# 1. Backend local (Postgres/Auth/… via Docker)
supabase start

# 2. App (desktop pour itérer vite ; gyroscope réel sur mobile)
flutter run -d windows
```

- Supabase Studio : http://127.0.0.1:54323
- Mails de test (Mailpit) : http://127.0.0.1:54324

### Décors photo (parallax)

Génère une image `base.png` (IA), dépose-la dans `assets/photo/<env>/<variante>/`, puis :

```bash
cd tools/depth_split
python -m venv .venv
.venv/Scripts/pip install torch --index-url https://download.pytorch.org/whl/cpu
.venv/Scripts/pip install -r requirements.txt
.venv/Scripts/python split_all.py     # couches parallax (nb de plans + feather par décor)
```

## État

✅ Comptes (email) · ✅ Profil + pseudo/handle · ✅ Décors (dessin + photo, persistés) ·
✅ Amis (demandes accepter/refuser) · ✅ Envoyer une pensée (+ option anonyme) · ✅ Historique ·
✅ Notifications push (FCM + heures calmes) · ✅ Son par décor (ambiance + musique, personnalisable).

🔜 Lien d'invitation, groupes/channels, cible iOS, déploiement prod.
