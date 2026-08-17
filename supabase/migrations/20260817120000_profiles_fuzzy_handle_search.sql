-- profiles_fuzzy_handle_search — "tu voulais dire… ?" after a missed handle.
--
-- Adding a friend requires typing their @handle EXACTLY; one wrong character
-- dead-ends on "Aucun utilisateur @x". This adds a lookalike lookup used ONLY
-- as a fallback once the exact lookup found nothing.
--
-- It is deliberately NOT a searchable directory — that would turn a private
-- circle app into a browsable list of strangers. The guards, all enforced here
-- (server-side) rather than in the client, are:
--   • at least 3 characters — no listing the base one letter at a time;
--   • similarity >= 0.45 — only genuine typos, not "everything starting with a";
--   • at most 3 rows — a suggestion, never a feed;
--   • handle ONLY — display_name (often a real first name) is never matched on;
--   • the caller and anyone who blocked them are excluded.
-- Loosening any of those changes what the app *is*. Don't, without saying so.
--
-- Runs SECURITY DEFINER because `profiles` is owner-only under RLS (see
-- profiles_privacy) — it returns exactly the four public-directory columns the
-- `public_profiles` view already exposes, and nothing else.

begin;

-- `%` (trigram similarity operator) + similarity(); Supabase keeps extensions
-- in their own schema, like pg_net in thoughts_push_webhook.
create extension if not exists pg_trgm with schema extensions;

-- Lets `%` below answer from an index instead of scanning every profile.
create index if not exists idx_profiles_handle_trgm
  on public.profiles using gin (handle extensions.gin_trgm_ops);

create or replace function public.search_profiles(q text)
returns table (id uuid, handle text, display_name text, avatar_url text)
language sql stable security definer set search_path = ''
as $$
  select p.id, p.handle, p.display_name, p.avatar_url
  from public.profiles p
  where auth.uid() is not null
    and length(btrim(q)) >= 3
    and p.handle is not null
    and p.id <> auth.uid()
    -- `%` uses the trigram index at its default 0.3 threshold (a cheap
    -- pre-filter); the stricter 0.45 below is what actually decides.
    and p.handle operator(extensions.%) lower(btrim(q))
    and extensions.similarity(p.handle, lower(btrim(q))) >= 0.45
    and not private.is_blocked(p.id, auth.uid())
  order by extensions.similarity(p.handle, lower(btrim(q))) desc, p.handle
  limit 3;
$$;

comment on function public.search_profiles(text) is
  'Typo fallback for friend-adding: up to 3 handles similar to q (>= 0.45), '
  'handle only, min 3 chars, excluding self and blockers. NOT a directory.';

revoke execute on function public.search_profiles(text) from public;
grant execute on function public.search_profiles(text) to authenticated;

commit;
