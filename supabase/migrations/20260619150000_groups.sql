-- groups — shared "circles". A creator owns a group and manages its members
-- (chosen among their friends). ANY member can send a pensée to the whole group
-- (fan-out via send_to_group). Members can leave; "blocking" a group leaves it,
-- stops its pensées, and prevents re-add.
--
-- Cross-table membership/creator checks go through SECURITY DEFINER helpers in
-- the `private` schema (like are_friends/is_blocked) so RLS policies never
-- recurse and the helpers aren't callable as PostgREST RPCs.

begin;

create table if not exists public.groups (
  id          uuid primary key default gen_random_uuid(),
  name        text not null check (char_length(name) between 1 and 60),
  creator_id  uuid not null references public.profiles (id) on delete cascade,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create index if not exists idx_groups_creator on public.groups (creator_id);

create trigger groups_set_updated_at
  before update on public.groups
  for each row execute function public.set_updated_at();

create table if not exists public.group_members (
  group_id   uuid not null references public.groups (id) on delete cascade,
  user_id    uuid not null references public.profiles (id) on delete cascade,
  joined_at  timestamptz not null default now(),
  primary key (group_id, user_id)
);
create index if not exists idx_group_members_user on public.group_members (user_id);

create table if not exists public.group_blocks (
  user_id    uuid not null references public.profiles (id) on delete cascade,
  group_id   uuid not null references public.groups (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, group_id)
);

-- A pensée can target a group (fan-out). Plain nullable uuid (no cross-table FK
-- needed; send_to_group always sets a validated group_id).
alter table public.thoughts
  add column if not exists group_id uuid;
create index if not exists idx_thoughts_group
  on public.thoughts (group_id) where group_id is not null;

-- ── Private helpers (definer, bypass RLS so policies can't recurse) ───────────
create or replace function private.is_group_member(p_group uuid, p_user uuid)
returns boolean language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.group_members
    where group_id = p_group and user_id = p_user
  );
$$;

create or replace function private.is_group_creator(p_group uuid, p_user uuid)
returns boolean language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.groups where id = p_group and creator_id = p_user
  );
$$;

grant execute on function private.is_group_member(uuid, uuid) to authenticated;
grant execute on function private.is_group_creator(uuid, uuid) to authenticated;

-- ── RLS ──────────────────────────────────────────────────────────────────────
alter table public.groups enable row level security;
alter table public.group_members enable row level security;
alter table public.group_blocks enable row level security;

create policy "see my groups" on public.groups
  for select to authenticated
  using (creator_id = auth.uid() or private.is_group_member(id, auth.uid()));
create policy "create groups" on public.groups
  for insert to authenticated
  with check (creator_id = auth.uid());
create policy "creator updates group" on public.groups
  for update to authenticated
  using (creator_id = auth.uid()) with check (creator_id = auth.uid());
create policy "creator deletes group" on public.groups
  for delete to authenticated
  using (creator_id = auth.uid());

create policy "see members of my groups" on public.group_members
  for select to authenticated
  using (
    private.is_group_member(group_id, auth.uid())
    or private.is_group_creator(group_id, auth.uid())
  );
-- The creator adds members, and only their own friends (or themselves on create).
create policy "creator adds members" on public.group_members
  for insert to authenticated
  with check (
    private.is_group_creator(group_id, auth.uid())
    and (user_id = auth.uid() or private.are_friends(auth.uid(), user_id))
  );
-- A member leaves (removes self); the creator removes anyone.
create policy "creator or self removes member" on public.group_members
  for delete to authenticated
  using (
    user_id = auth.uid()
    or private.is_group_creator(group_id, auth.uid())
  );

create policy "manage own group blocks" on public.group_blocks
  for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

grant select, insert, update, delete on public.groups to authenticated;
grant select, insert, delete on public.group_members to authenticated;
grant select, insert, delete on public.group_blocks to authenticated;

-- ── Rate-limit: exempt group fan-out from the 25/min INDIVIDUAL cap ───────────
-- Individual pensées stay capped at 25/min; group pensées are bounded by the
-- per-send cap inside send_to_group instead, so one fan-out can't trip this.
create or replace function public.enforce_thought_rate_limit()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  if new.group_id is null and (
    select count(*) from public.thoughts
    where sender_id = new.sender_id
      and group_id is null
      and created_at > now() - interval '1 minute'
  ) >= 25 then
    raise exception 'rate_limited'
      using errcode = 'check_violation',
            hint = 'too many thoughts sent in the last minute';
  end if;
  return new;
end;
$$;

-- ── send_to_group: fan-out one pensée per OTHER member ────────────────────────
-- SECURITY DEFINER so it can insert past the friend-only thoughts policy;
-- membership + both-way blocks + group-blocks are enforced here. Returns the
-- number of pensées actually sent.
create or replace function public.send_to_group(p_group uuid, p_anonymous boolean default false)
returns int language plpgsql security definer set search_path = ''
as $$
declare
  me uuid := auth.uid();
  recent int;
  inserted int := 0;
begin
  if me is null then
    raise exception 'unauthenticated' using errcode = '28000';
  end if;
  if not private.is_group_member(p_group, me) then
    raise exception 'not_a_member' using errcode = 'check_violation';
  end if;
  -- Group-send cap (separate from the individual 25/min): bound total fan-out.
  select count(*) into recent from public.thoughts
    where sender_id = me and group_id is not null
      and created_at > now() - interval '1 minute';
  if recent >= 150 then
    raise exception 'rate_limited' using errcode = 'check_violation';
  end if;
  insert into public.thoughts (sender_id, recipient_id, is_anonymous, group_id)
  select me, gm.user_id, p_anonymous, p_group
  from public.group_members gm
  where gm.group_id = p_group
    and gm.user_id <> me
    and not private.is_blocked(gm.user_id, me)
    and not private.is_blocked(me, gm.user_id)
    and not exists (
      select 1 from public.group_blocks gb
      where gb.group_id = p_group and gb.user_id = gm.user_id
    );
  get diagnostics inserted = row_count;
  return inserted;
end;
$$;
revoke execute on function public.send_to_group(uuid, boolean) from public;
grant execute on function public.send_to_group(uuid, boolean) to authenticated;

-- Realtime: so a member sees a group appear / membership change live (RLS still
-- restricts events to rows the subscriber can read).
alter publication supabase_realtime add table public.groups;
alter publication supabase_realtime add table public.group_members;

commit;
