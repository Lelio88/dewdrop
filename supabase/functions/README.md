# Edge Functions — push DewDrop

## `send-thought-push`

Envoie une notification FCM **« X a pensé à toi ✨ »** quand une ligne est
insérée dans `public.thoughts`. Respecte les **heures calmes** du destinataire
(`profiles.quiet_start/quiet_end`) et l'**anonymat** (`thoughts.is_anonymous`).

### Câblage (à faire quand le projet Firebase existe)

**1. Projet Firebase + clé de service**
- Console Firebase → ton projet → ⚙️ *Paramètres du projet* → *Comptes de service*
  → **Générer une nouvelle clé privée** → télécharge le JSON.

**2. Donner la clé à la fonction (secret)**
```bash
# Local : crée supabase/functions/.env  (ne pas committer)
echo "FIREBASE_SERVICE_ACCOUNT=$(cat ~/Downloads/service-account.json | tr -d '\n')" >> supabase/functions/.env
# Hébergé :
supabase secrets set FIREBASE_SERVICE_ACCOUNT="$(cat service-account.json)"
```
`SUPABASE_URL` et `SUPABASE_SERVICE_ROLE_KEY` sont injectés automatiquement.

**3. Déclencher la fonction à l'insertion d'une pensée**
- Hébergé : Dashboard → *Database* → *Webhooks* → nouveau webhook sur
  `public.thoughts`, événement **INSERT**, type **HTTP**, URL de la fonction
  (`.../functions/v1/send-thought-push`), header `Authorization: Bearer <anon>`.
- Local : `supabase functions serve send-thought-push` puis un trigger `pg_net`
  pointant sur `http://host.docker.internal:54321/functions/v1/send-thought-push`.

**4. Côté app : enregistrer le token FCM**
- Ajouter `firebase_core` + `firebase_messaging`, demander la permission,
  récupérer le token, et l'**upsert** dans `public.devices`
  (`user_id`, `token`, `platform`). À faire sur une cible **Android/iOS/web**
  (pas Windows desktop — FCM n'y est pas supporté).

**5. Déployer (hébergé)**
```bash
supabase functions deploy send-thought-push
```

### Limite connue
Les heures calmes sont comparées en **UTC** (pas de fuseau par utilisateur). À
améliorer : stocker un fuseau dans `profiles`, ou décaler côté client.
