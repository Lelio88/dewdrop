-- security_hardening — pre-public-release hardening of the auth/RLS surface.
--
-- 1. A friend request can only be ACCEPTED by its addressee. Previously the
--    requester could self-accept and become a "friend" without consent.
-- 2. The RLS helper functions move to a non-exposed `private` schema so they
--    can't be called as PostgREST RPCs to probe arbitrary users' relationships,
--    and every SECURITY DEFINER / trigger function pins `search_path = ''`.
-- 3. thought_style (sender-controlled, shown in the recipient's push) is
--    constrained; reports are deduped + bounded; handle format is enforced.
--
-- Migrations are immutable: this re-creates policies/functions in a new file
-- rather than editing the originals.

begin;

-- 1. Only the addressee accepts/rejects. The requester withdrawing a pending
--    request uses the existing "delete own friendship" policy.
drop policy if exists "respond to friendship" on public.friendships;
create policy "respond to friendship" on public.friendships
  for update to authenticated
  using (auth.uid() = addressee_id)
  with check (auth.uid() = addressee_id);

-- 2. RLS helpers → `private` schema. PostgREST never exposes `private`, so these
--    stop being callable as RPCs; RLS still works because `authenticated` keeps
--    USAGE + EXECUTE. search_path is pinned to '' (all refs schema-qualified).
create schema if not exists private;
grant usage on schema private to authenticated;

create or replace function private.are_friends(a uuid, b uuid)
returns boolean language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.friendships f
    where f.status = 'accepted'
      and ((f.requester_id = a and f.addressee_id = b)
        or (f.requester_id = b and f.addressee_id = a))
  );
$$;

create or replace function private.is_blocked(blocker uuid, blocked uuid)
returns boolean language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.blocks b
    where b.blocker_id = blocker and b.blocked_id = blocked
  );
$$;

grant execute on function private.are_friends(uuid, uuid) to authenticated;
grant execute on function private.is_blocked(uuid, uuid) to authenticated;

-- Repoint the policies onto the private helpers, then drop the public ones.
drop policy if exists "send thought to friend" on public.thoughts;
create policy "send thought to friend" on public.thoughts
  for insert to authenticated
  with check (
    auth.uid() = sender_id
    and private.are_friends(sender_id, recipient_id)
    and not private.is_blocked(recipient_id, sender_id)
  );

drop policy if exists "send friend request" on public.friendships;
create policy "send friend request" on public.friendships
  for insert to authenticated
  with check (
    auth.uid() = requester_id
    and not private.is_blocked(addressee_id, requester_id)
  );

drop function if exists public.are_friends(uuid, uuid);
drop function if exists public.is_blocked(uuid, uuid);

-- Harden the remaining definer/trigger functions' search_path.
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  insert into public.profiles (id) values (new.id)
  on conflict (id) do nothing;
  return new;
end;
$$;

create or replace function public.set_updated_at()
returns trigger language plpgsql set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

-- 3a. thought_style is sender-controlled and ends up in the recipient's push:
--     constrain shape, lengths, and require the %s placeholder in body.
alter table public.profiles
  add constraint thought_style_valid check (
    jsonb_typeof(thought_style) = 'object'
    and char_length(coalesce(thought_style->>'lead', '')) <= 8
    and char_length(coalesce(thought_style->>'body', '%s')) <= 80
    and char_length(coalesce(thought_style->>'tail', '')) <= 8
    and coalesce(thought_style->>'body', '%s') like '%\%s%'
  );

-- 3b. handle format mirrors the app's onboarding rule (^[a-z0-9_]{3,20}$).
alter table public.profiles
  add constraint handle_format check (
    handle is null or handle ~ '^[a-z0-9_]{3,20}$'
  );

-- 3c. One report per (reporter, reported) pair + a bounded reason. Dedupe any
--     existing duplicates first so the unique constraint can be added.
delete from public.reports a using public.reports b
  where a.ctid < b.ctid
    and a.reporter_id = b.reporter_id
    and a.reported_id = b.reported_id;
alter table public.reports
  add constraint reports_unique_pair unique (reporter_id, reported_id);
alter table public.reports
  add constraint reports_reason_len check (reason is null or char_length(reason) <= 1000);

commit;
