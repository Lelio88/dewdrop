-- profiles_thought_presets — named, saved notification-style trios the user can
-- re-apply in one tap. Each entry is {"name": <label>, "style": {lead, body, tail}}.
--
-- Presets are a pure client-side convenience: only the *active* style is read
-- server-side (profiles.thought_style, applied by send-thought-push). This list
-- is never consulted by the Edge Function, so it needs no server validation and
-- no new policy/grant — the existing owner-only profiles RLS + GRANT already
-- cover the owner updating their own row. The app caps the list at 5 entries.

alter table public.profiles
  add column if not exists thought_presets jsonb not null default '[]'::jsonb;

comment on column public.profiles.thought_presets is
  'Saved notification-style presets [{name, style:{lead,body,tail}}], client-side only, capped at 5 by the app.';
