-- profiles_decor_favorites — starred decor variants cycled by the home swipe.
--
--   decor_favorites : ordered snapshots "<environment>:<variant>:<render_mode>"
--                     (e.g. 'forest:1:photo') the user starred from the univers
--                     picker. The home screen switches between them on a
--                     horizontal swipe.
--
-- Pure client-side convenience, like profiles.widget_* (20260624120000):
-- nothing server-side (the push Edge Function, RLS) ever reads it, so it needs
-- no validation, policy or grant — the existing owner-only profiles RLS + GRANT
-- already cover the owner updating their own row.

alter table public.profiles
  add column if not exists decor_favorites text[] not null default '{}';

comment on column public.profiles.decor_favorites is
  'Ordered starred decor snapshots "<environment>:<variant>:<render_mode>" the home screen cycles through on a horizontal swipe. Client-side only.';
