-- profiles_widget_config — home-screen widget friend source.
--
--   widget_source  : 'auto'  → the 4 friends most recently sent a pensée
--                    'custom' → the pinned widget_friends list, in order
--   widget_friends : ordered friend ids shown when source = 'custom' (≤4, app-capped)
--
-- Both are a pure client-side convenience: nothing server-side (the push Edge
-- Function, RLS) ever reads them, so they need no validation, policy or grant —
-- the existing owner-only profiles RLS + GRANT already cover the owner updating
-- their own row. Mirrors profiles.thought_presets (20260623120000).

alter table public.profiles
  add column if not exists widget_source text not null default 'auto';

alter table public.profiles
  add column if not exists widget_friends uuid[] not null default '{}';

comment on column public.profiles.widget_source is
  'Home-screen widget friend source: ''auto'' (most recently contacted) or ''custom'' (widget_friends). Client-side only.';

comment on column public.profiles.widget_friends is
  'Pinned friend ids shown by the home-screen widget when widget_source = ''custom'', in display order. Capped at 4 by the app.';
