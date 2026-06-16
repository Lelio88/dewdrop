-- thoughts_push_throttle — cap how often a recipient is *notified*, not how
-- often they receive thoughts. Every pensée is still recorded and visible
-- in-app; we just avoid a flood of push notifications by enforcing a
-- per-recipient cooldown (see send-thought-push). This is the
-- "rate-limit the notifications, not the thoughts" policy.

alter table public.profiles
  add column if not exists last_thought_push_at timestamptz;

comment on column public.profiles.last_thought_push_at is
  'When the last "X a pensé à toi" push was sent to this user; the push function '
  'skips sending again within the cooldown window.';

-- The send-thought-push Edge Function (service_role) stamps this one column
-- after it sends a push. Column-level grant: it can touch nothing else.
grant update (last_thought_push_at) on public.profiles to service_role;
