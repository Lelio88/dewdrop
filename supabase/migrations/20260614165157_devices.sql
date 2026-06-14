-- devices — one FCM push token per user device. The push Edge Function reads
-- a recipient's tokens (as service_role) to deliver "X a pensé à toi".

create table if not exists public.devices (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references public.profiles (id) on delete cascade,
  token      text not null unique,
  platform   text not null check (platform in ('android', 'ios', 'web')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists idx_devices_user on public.devices (user_id);

create trigger devices_set_updated_at
  before update on public.devices
  for each row execute function public.set_updated_at();

alter table public.devices enable row level security;

-- A user manages only their own device tokens.
create policy "manage own devices" on public.devices
  for all to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

grant select, insert, update, delete on public.devices to authenticated;
