-- init_schema — Profiles: one row per auth user, holding the public handle
-- and the app settings (chosen decor, render mode, quiet hours, anonymity).

-- Generic updated_at trigger helper.
create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create table if not exists public.profiles (
  id                uuid primary key references auth.users (id) on delete cascade,
  handle            text unique,                       -- chosen at onboarding
  display_name      text,
  avatar_url        text,
  decor             text not null default 'space:0',   -- "<environment>:<variant>"
  render_mode       text not null default 'photo',     -- 'drawn' | 'photo'
  quiet_start       int,                               -- hour 0-23, null = disabled
  quiet_end         int,
  default_anonymous boolean not null default false,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);

comment on table public.profiles is 'Public profile + app settings, 1:1 with auth.users';
comment on column public.profiles.handle is 'Unique public handle, set during onboarding (nullable until then)';
comment on column public.profiles.decor is 'Selected ambiance as "<environment>:<variant>", e.g. forest:0';

create trigger profiles_set_updated_at
  before update on public.profiles
  for each row execute function public.set_updated_at();

-- Auto-create a (handle-less) profile row when a new auth user signs up.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id) values (new.id)
  on conflict (id) do nothing;
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- Row Level Security ---------------------------------------------------------
alter table public.profiles enable row level security;

-- Any authenticated user can read profiles (needed to find friends by handle).
create policy "profiles readable by authenticated"
  on public.profiles for select
  to authenticated
  using (true);

-- A user can only insert/update their own profile.
create policy "users insert own profile"
  on public.profiles for insert
  to authenticated
  with check (auth.uid() = id);

create policy "users update own profile"
  on public.profiles for update
  to authenticated
  using (auth.uid() = id)
  with check (auth.uid() = id);

-- Table privileges. RLS (above) still gates which rows each user can touch;
-- these GRANTs are the base table-level permissions PostgREST needs.
grant select, insert, update on public.profiles to authenticated;
