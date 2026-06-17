-- profiles_privacy — stop every authenticated user from reading every other
-- user's FULL profile (quiet hours, sound prefs, thought style, last-push…).
--
-- profiles SELECT is restricted to the owner. A `public_profiles` view exposes
-- ONLY the directory columns (handle / display_name / avatar) needed to find &
-- display a friend; the app reads other users through it. The view runs with
-- owner rights (bypasses RLS) but, exposing only those safe columns, it is
-- exactly the public directory we want — it can never leak the private columns.

begin;

drop policy if exists "profiles readable by authenticated" on public.profiles;
create policy "read own profile" on public.profiles
  for select to authenticated
  using (auth.uid() = id);

create or replace view public.public_profiles
  with (security_invoker = false) as
  select id, handle, display_name, avatar_url
  from public.profiles;

grant select on public.public_profiles to authenticated;

comment on view public.public_profiles is
  'Public directory: only handle/display_name/avatar, readable by any '
  'authenticated user. The base profiles table is owner-only (RLS).';

commit;
