# Edge Functions — DewDrop

## `send-thought-push`

Déclenchée par un **webhook DB** à l'insertion d'une ligne dans `public.thoughts`.
Envoie un **message *data* FCM** à chaque appareil du destinataire ; **l'app**
construit ensuite la notification **groupée** (1 groupe « DewDrop » + 1 enfant par
expéditeur/groupe, alerte une fois — voir `lib/src/features/notifications/application/thought_notifications.dart`).

Logique :
- **Auth** : n'accepte que le rôle `service_role` (le webhook) — rejette le reste.
- **Coupe-circuit** : saute si `profiles.notifications_enabled = false`.
- **Heures calmes** (fuseau IANA par utilisateur) : ne *sautent* plus la notif —
  elle est livrée **silencieuse** (`silent: "1"` → canal `thoughts_silent`), donc
  elle s'empile sans bruit et l'utilisateur la voit au réveil (pas de cron).
- **Style / groupe** : corps assemblé depuis `profiles.thought_style` de
  l'expéditeur ; pour une pensée de groupe (`thoughts.group_id`) → « X a pensé au
  groupe Y ». Anonyme → « Quelqu'un ».
- **Hygiène** : un token FCM rejeté en 404 (UNREGISTERED) est supprimé de `devices`.

Secret requis : `FIREBASE_SERVICE_ACCOUNT` (JSON du compte de service Firebase,
posé via `supabase secrets set`). `SUPABASE_URL` / `SUPABASE_SERVICE_ROLE_KEY`
sont injectés automatiquement.

## `delete-account`

Supprime le compte de l'appelant (**POST** uniquement). Résout l'utilisateur
depuis son **propre JWT** (jamais depuis le body), puis supprime le `auth.users`
via l'API admin (`service_role`) → cascade sur profil, amitiés, pensées, groupes
et appareils.

## Déployer

```bash
supabase functions deploy send-thought-push
supabase functions deploy delete-account
```
