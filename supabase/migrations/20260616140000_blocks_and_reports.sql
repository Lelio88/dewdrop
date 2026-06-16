-- blocks_and_reports — a user can block (and report) another. A blocked person
-- can no longer send a pensée or a friend request to the blocker, and blocking
-- removes any existing friendship. Reports are recorded for later moderation.

create table if not exists public.blocks (
  blocker_id uuid not null references public.profiles (id) on delete cascade,
  blocked_id uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  check (blocker_id <> blocked_id)
);
create index if not exists idx_blocks_blocked on public.blocks (blocked_id);

create table if not exists public.reports (
  id          uuid primary key default gen_random_uuid(),
  reporter_id uuid not null references public.profiles (id) on delete cascade,
  reported_id uuid not null references public.profiles (id) on delete cascade,
  reason      text,
  created_at  timestamptz not null default now()
);

-- Has `blocker` blocked `blocked`? security definer so it can be used inside
-- other tables' RLS without tripping over blocks' own row-level security.
create or replace function public.is_blocked(blocker uuid, blocked uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.blocks b
    where b.blocker_id = blocker and b.blocked_id = blocked
  );
$$;

alter table public.blocks enable row level security;
alter table public.reports enable row level security;

create policy "manage own blocks" on public.blocks
  for all to authenticated
  using (auth.uid() = blocker_id)
  with check (auth.uid() = blocker_id);

create policy "create own reports" on public.reports
  for insert to authenticated
  with check (auth.uid() = reporter_id);

grant select, insert, delete on public.blocks to authenticated;
grant insert on public.reports to authenticated;

-- Tighten the existing insert policies so a blocked sender can't reach the
-- blocker. Migrations never edit old files: re-create the policies here.
drop policy if exists "send thought to friend" on public.thoughts;
create policy "send thought to friend" on public.thoughts
  for insert to authenticated
  with check (
    auth.uid() = sender_id
    and public.are_friends(sender_id, recipient_id)
    and not public.is_blocked(recipient_id, sender_id)
  );

drop policy if exists "send friend request" on public.friendships;
create policy "send friend request" on public.friendships
  for insert to authenticated
  with check (
    auth.uid() = requester_id
    and not public.is_blocked(addressee_id, requester_id)
  );
