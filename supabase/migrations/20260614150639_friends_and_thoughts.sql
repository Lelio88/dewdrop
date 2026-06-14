-- friends_and_thoughts — friend requests (pending/accepted) + thoughts ("pensées").

create table if not exists public.friendships (
  id           uuid primary key default gen_random_uuid(),
  requester_id uuid not null references public.profiles (id) on delete cascade,
  addressee_id uuid not null references public.profiles (id) on delete cascade,
  status       text not null default 'pending' check (status in ('pending', 'accepted')),
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  unique (requester_id, addressee_id),
  check (requester_id <> addressee_id)
);
create index if not exists idx_friendships_addressee on public.friendships (addressee_id);
create index if not exists idx_friendships_requester on public.friendships (requester_id);

create trigger friendships_set_updated_at
  before update on public.friendships
  for each row execute function public.set_updated_at();

create table if not exists public.thoughts (
  id           uuid primary key default gen_random_uuid(),
  sender_id    uuid not null references public.profiles (id) on delete cascade,
  recipient_id uuid not null references public.profiles (id) on delete cascade,
  is_anonymous boolean not null default false,
  created_at   timestamptz not null default now()
);
create index if not exists idx_thoughts_recipient on public.thoughts (recipient_id, created_at desc);
create index if not exists idx_thoughts_sender on public.thoughts (sender_id, created_at desc);

-- Are two users accepted friends? security definer so it can be used inside the
-- thoughts insert policy without tripping over friendships' own RLS. Defined
-- after the table so its (validated) body can reference it.
create or replace function public.are_friends(a uuid, b uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.friendships f
    where f.status = 'accepted'
      and ((f.requester_id = a and f.addressee_id = b)
        or (f.requester_id = b and f.addressee_id = a))
  );
$$;

-- Row Level Security ---------------------------------------------------------
alter table public.friendships enable row level security;
alter table public.thoughts enable row level security;

create policy "see own friendships" on public.friendships
  for select to authenticated
  using (auth.uid() = requester_id or auth.uid() = addressee_id);

create policy "send friend request" on public.friendships
  for insert to authenticated
  with check (auth.uid() = requester_id);

create policy "respond to friendship" on public.friendships
  for update to authenticated
  using (auth.uid() = addressee_id or auth.uid() = requester_id)
  with check (auth.uid() = addressee_id or auth.uid() = requester_id);

create policy "delete own friendship" on public.friendships
  for delete to authenticated
  using (auth.uid() = requester_id or auth.uid() = addressee_id);

create policy "see own thoughts" on public.thoughts
  for select to authenticated
  using (auth.uid() = sender_id or auth.uid() = recipient_id);

-- A thought can only be sent by yourself, to an accepted friend.
create policy "send thought to friend" on public.thoughts
  for insert to authenticated
  with check (auth.uid() = sender_id and public.are_friends(sender_id, recipient_id));

-- Table privileges (RLS above still gates rows).
grant select, insert, update, delete on public.friendships to authenticated;
grant select, insert on public.thoughts to authenticated;
