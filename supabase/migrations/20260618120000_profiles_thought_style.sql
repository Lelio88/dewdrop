-- profiles_thought_style — per-sender notification style: a leading emoji, a
-- phrase template (where %s = the sender's name, or « Quelqu'un » when sent
-- anonymously) and a trailing emoji. The send-thought-push Edge Function reads
-- it to build each pensée's notification text, so the recipient sees the
-- sender's styled message.
--
-- The default reproduces the previous fixed message ("<name> a pensé à toi ✨").
-- Owner-only writes are already covered by the existing profiles RLS + GRANT
-- (the owner can update their own row), so no new policy/grant is needed.

alter table public.profiles
  add column if not exists thought_style jsonb not null
  default '{"lead":"","body":"%s a pensé à toi","tail":"✨"}'::jsonb;

comment on column public.profiles.thought_style is
  'Sender notification style {lead, body (contains %s), tail}; applied by send-thought-push.';
