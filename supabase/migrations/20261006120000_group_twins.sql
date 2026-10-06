-- group_twins — un cercle jumelé avec un groupe d'une autre app du conteneur
-- (Agora, Arpente), et les demandes pour y entrer par le code d'un jumeau.
--
-- Les apps ne se parlent pas : elles s'ouvrent l'une l'autre par des liens
-- préremplis (protocole : docs/liens-inter-apps.md du dépôt méta Projets). Un
-- jumeau garde le code qui fait rejoindre le groupe de l'autre app, que les
-- membres du cercle voient (« Rejoindre aussi dans Agora »), et le code que le
-- cercle a donné à l'autre app pour qu'on demande à y entrer.
--
-- Choix non évidents :
--   - un code ne fait PAS entrer : il envoie une demande que le créateur du
--     cercle accepte ou refuse (answer_join_request). Un cercle reste un groupe
--     de gens que son créateur a choisis ; le code n'ouvre aucun annuaire (la
--     « ligne de découvrabilité » d'architecture.md tient) ;
--   - un code PAR JUMEAU (group_twins.code), comme l'invitation d'un jumeau
--     Agora : défaire un jumelage tue son code sans toucher à l'autre jumeau ;
--   - `code` n'est lisible que par le créateur, via twin_group (grant par
--     colonne : les membres lisent app et remote_code, pas code) ;
--   - pas d'UPDATE : un jumeau complet ne se remplace pas (twin_exists). Un
--     lien forgé ne doit pas rediriger les membres vers un autre groupe ; pour
--     changer de jumeau, on défait d'abord ;
--   - accepter une demande insère dans group_members en SECURITY DEFINER : la
--     politique « creator adds members » (parmi ses amis) ne s'applique pas,
--     le créateur ayant choisi cette personne en acceptant ;
--   - un code inconnu ne lève pas d'exception : preview rend zéro ligne et
--     request_to_join rend 'invalid', ce qui laisse l'échec s'inscrire dans
--     private.join_code_failures (une exception l'annulerait). Vingt échecs en
--     une heure → rate_limited (bonnes pratiques C1 : jamais de verrouillage
--     définitif, la fenêtre glisse). Les blocages répondent comme un code
--     inconnu, sans compter d'échec ;
--   - la base accorde par défaut TRUNCATE & co. à anon/authenticated sur toute
--     table neuve : tout est révoqué avant d'accorder le strict nécessaire.
--
-- Invariants (supabase/tests/group_twins_test.sql) : seul le créateur jumelle
-- et tranche les demandes ; un jumeau par cercle et par app ; seuls les
-- membres lisent le jumeau ; le code reste au créateur ; tout part en cascade
-- avec le cercle ou le compte.

begin;

-- ── Codes ────────────────────────────────────────────────────────────────────
-- 8 caractères sur un alphabet de 32 sans ambiguïté (ni 0/O, ni 1/I) : 32^8 ≈
-- 10^12 codes ; 256 étant multiple de 32, le tirage est uniforme.
create or replace function private.random_join_code()
returns text language sql volatile set search_path = ''
as $$
  select string_agg(
    substr('ABCDEFGHJKLMNPQRSTUVWXYZ23456789', 1 + get_byte(b.bytes, i) % 32, 1),
    ''
  )
  from (select extensions.gen_random_bytes(8) as bytes) b,
       generate_series(0, 7) as i;
$$;
revoke execute on function private.random_join_code() from public, anon, authenticated;

-- ── Jumeaux ──────────────────────────────────────────────────────────────────
create table public.group_twins (
  group_id    uuid not null references public.groups (id) on delete cascade,
  app         text not null check (app in ('agora', 'arpente')),
  code        text not null unique check (code ~ '^[A-HJ-NP-Z2-9]{8}$'),
  remote_code text,
  created_at  timestamptz not null default now(),
  primary key (group_id, app),
  constraint group_twins_remote_code_format check (
    remote_code is null
    or (app = 'agora' and remote_code ~ '^[A-HJ-NP-Z2-9]{8}$')
    or (app = 'arpente' and remote_code ~ '^[A-HJ-NP-Z2-9]{6}$')
  )
);

alter table public.group_twins enable row level security;
revoke all on public.group_twins from anon, authenticated;
grant select (group_id, app, remote_code, created_at) on public.group_twins to authenticated;

create policy "members see twins" on public.group_twins
  for select to authenticated
  using (
    private.is_group_member(group_id, auth.uid())
    or private.is_group_creator(group_id, auth.uid())
  );

-- ── Demandes d'adhésion ──────────────────────────────────────────────────────
create table public.group_join_requests (
  group_id   uuid not null references public.groups (id) on delete cascade,
  user_id    uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (group_id, user_id)
);
create index idx_group_join_requests_user on public.group_join_requests (user_id);

alter table public.group_join_requests enable row level security;
revoke all on public.group_join_requests from anon, authenticated;
grant select, delete on public.group_join_requests to authenticated;

create policy "requester or creator sees request" on public.group_join_requests
  for select to authenticated
  using (user_id = auth.uid() or private.is_group_creator(group_id, auth.uid()));
-- Le demandeur annule la sienne ; le créateur la refuse (answer_join_request
-- passe aussi par là, en definer).
create policy "requester or creator removes request" on public.group_join_requests
  for delete to authenticated
  using (user_id = auth.uid() or private.is_group_creator(group_id, auth.uid()));

-- Le créateur voit les demandes arriver sans recharger.
alter publication supabase_realtime add table public.group_join_requests;

-- Échecs de code par personne, sur une heure glissante (jamais lus hors des RPC).
create table private.join_code_failures (
  user_id uuid not null references public.profiles (id) on delete cascade,
  at      timestamptz not null default now()
);
create index idx_join_code_failures_user on private.join_code_failures (user_id, at);
revoke all on private.join_code_failures from public, anon, authenticated;

create or replace function private.join_code_rate_limited(p_user uuid)
returns boolean language sql stable security definer set search_path = ''
as $$
  select count(*) >= 20 from private.join_code_failures f
  where f.user_id = p_user and f.at > now() - interval '1 hour';
$$;

create or replace function private.note_join_code_failure(p_user uuid)
returns void language sql volatile security definer set search_path = ''
as $$
  delete from private.join_code_failures f
  where f.user_id = p_user and f.at <= now() - interval '1 hour';
  insert into private.join_code_failures (user_id) values (p_user);
$$;
revoke execute on function private.join_code_rate_limited(uuid) from public, anon, authenticated;
revoke execute on function private.note_join_code_failure(uuid) from public, anon, authenticated;

-- Le jumeau dont [p_code] est le code, s'il peut recevoir une demande de
-- [p_user] : ni blocage dans un sens ou dans l'autre avec le créateur, ni
-- cercle bloqué par le demandeur. Sinon NULL (même réponse qu'un code inconnu).
create or replace function private.joinable_group(p_code text, p_user uuid)
returns uuid language sql stable security definer set search_path = ''
as $$
  select g.id
  from public.group_twins t
  join public.groups g on g.id = t.group_id
  where t.code = upper(btrim(p_code))
    and not private.is_blocked(g.creator_id, p_user)
    and not private.is_blocked(p_user, g.creator_id)
    and not exists (
      select 1 from public.group_blocks b
      where b.group_id = g.id and b.user_id = p_user
    );
$$;
revoke execute on function private.joinable_group(text, uuid) from public, anon, authenticated;

-- ── RPC ──────────────────────────────────────────────────────────────────────

-- Crée le jumeau (et son code), ou le complète du code distant. Rend le code à
-- donner à l'autre app. Créateur seul ; la ligne du cercle est verrouillée,
-- deux appareils qui jumellent en même temps se sérialisent.
create or replace function public.twin_group(
  p_group uuid,
  p_app text,
  p_remote_code text default null
)
returns text language plpgsql volatile security definer set search_path = ''
as $$
declare
  v_remote text := nullif(upper(btrim(p_remote_code)), '');
  v_code text;
  v_current text;
begin
  if auth.uid() is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;
  if not private.is_group_creator(p_group, auth.uid()) then
    raise exception 'not_group_creator' using errcode = '42501';
  end if;
  perform 1 from public.groups g where g.id = p_group for update;
  if p_app is null or p_app not in ('agora', 'arpente') then
    raise exception 'invalid_twin_app' using errcode = '22023';
  end if;
  if v_remote is not null and not (
    (p_app = 'agora' and v_remote ~ '^[A-HJ-NP-Z2-9]{8}$')
    or (p_app = 'arpente' and v_remote ~ '^[A-HJ-NP-Z2-9]{6}$')
  ) then
    raise exception 'invalid_twin_code' using errcode = '22023';
  end if;

  select t.code, t.remote_code into v_code, v_current
  from public.group_twins t
  where t.group_id = p_group and t.app = p_app;

  if not found then
    loop
      v_code := private.random_join_code();
      exit when not exists (select 1 from public.group_twins t where t.code = v_code);
    end loop;
    insert into public.group_twins (group_id, app, code, remote_code)
    values (p_group, p_app, v_code, v_remote);
  elsif v_remote is not null and v_current is not null and v_current <> v_remote then
    raise exception 'twin_exists' using errcode = '23505';
  elsif v_remote is not null and v_current is null then
    update public.group_twins t set remote_code = v_remote
    where t.group_id = p_group and t.app = p_app;
  end if;
  return v_code;
end;
$$;

-- Défait un jumelage : son code n'ouvre plus rien. Les demandes déjà reçues
-- restent à trancher.
create or replace function public.untwin_group(p_group uuid, p_app text)
returns void language plpgsql volatile security definer set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;
  if not private.is_group_creator(p_group, auth.uid()) then
    raise exception 'not_group_creator' using errcode = '42501';
  end if;
  delete from public.group_twins t where t.group_id = p_group and t.app = p_app;
end;
$$;

-- Ce qu'un code fait rejoindre, avant de demander : nom du cercle, @handle du
-- créateur, et où en est la personne. Zéro ligne pour un code inconnu ou
-- refusé ; rate_limited après vingt codes inconnus en une heure.
create or replace function public.join_code_preview(p_code text)
returns table (
  group_id uuid,
  name text,
  creator_handle text,
  is_member boolean,
  already_requested boolean
)
language plpgsql volatile security definer set search_path = ''
as $$
declare
  v_me uuid := auth.uid();
  v_group uuid;
begin
  if v_me is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;
  if private.join_code_rate_limited(v_me) then
    raise exception 'rate_limited' using errcode = 'check_violation';
  end if;
  if not exists (select 1 from public.group_twins t where t.code = upper(btrim(p_code))) then
    perform private.note_join_code_failure(v_me);
    return;
  end if;
  v_group := private.joinable_group(p_code, v_me);
  if v_group is null then
    return;
  end if;
  return query
    select g.id, g.name, p.handle,
           private.is_group_member(g.id, v_me),
           exists (
             select 1 from public.group_join_requests r
             where r.group_id = g.id and r.user_id = v_me
           )
    from public.groups g
    join public.profiles p on p.id = g.creator_id
    where g.id = v_group;
end;
$$;

-- Demande à entrer dans le cercle de [p_code]. Rend 'requested',
-- 'already_requested', 'already_member' ou 'invalid' (code inconnu ou refusé,
-- sans distinction). Dix demandes en une heure au plus.
create or replace function public.request_to_join(p_code text)
returns text language plpgsql volatile security definer set search_path = ''
as $$
declare
  v_me uuid := auth.uid();
  v_group uuid;
begin
  if v_me is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;
  if private.join_code_rate_limited(v_me) then
    raise exception 'rate_limited' using errcode = 'check_violation';
  end if;
  if not exists (select 1 from public.group_twins t where t.code = upper(btrim(p_code))) then
    perform private.note_join_code_failure(v_me);
    return 'invalid';
  end if;
  v_group := private.joinable_group(p_code, v_me);
  if v_group is null then
    return 'invalid';
  end if;
  if private.is_group_member(v_group, v_me) then
    return 'already_member';
  end if;
  if exists (
    select 1 from public.group_join_requests r
    where r.group_id = v_group and r.user_id = v_me
  ) then
    return 'already_requested';
  end if;
  if (
    select count(*) from public.group_join_requests r
    where r.user_id = v_me and r.created_at > now() - interval '1 hour'
  ) >= 10 then
    raise exception 'rate_limited' using errcode = 'check_violation';
  end if;
  insert into public.group_join_requests (group_id, user_id) values (v_group, v_me);
  return 'requested';
end;
$$;

-- Le créateur accepte ou refuse une demande. Accepter fait entrer la personne
-- (sauf si un blocage est apparu entre-temps : la demande est alors seulement
-- retirée) ; dans les deux cas la demande disparaît.
create or replace function public.answer_join_request(
  p_group uuid,
  p_user uuid,
  p_accept boolean
)
returns void language plpgsql volatile security definer set search_path = ''
as $$
declare
  v_creator uuid;
begin
  if auth.uid() is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;
  if not private.is_group_creator(p_group, auth.uid()) then
    raise exception 'not_group_creator' using errcode = '42501';
  end if;
  delete from public.group_join_requests r
  where r.group_id = p_group and r.user_id = p_user;
  if not found then
    raise exception 'request_not_found' using errcode = 'P0002';
  end if;
  select g.creator_id into v_creator from public.groups g where g.id = p_group;
  if p_accept
     and not private.is_blocked(v_creator, p_user)
     and not private.is_blocked(p_user, v_creator)
     and not exists (
       select 1 from public.group_blocks b
       where b.group_id = p_group and b.user_id = p_user
     ) then
    insert into public.group_members (group_id, user_id)
    values (p_group, p_user)
    on conflict do nothing;
  end if;
end;
$$;

revoke execute on function public.twin_group(uuid, text, text) from public, anon;
revoke execute on function public.untwin_group(uuid, text) from public, anon;
revoke execute on function public.join_code_preview(text) from public, anon;
revoke execute on function public.request_to_join(text) from public, anon;
revoke execute on function public.answer_join_request(uuid, uuid, boolean) from public, anon;
grant execute on function public.twin_group(uuid, text, text) to authenticated;
grant execute on function public.untwin_group(uuid, text) to authenticated;
grant execute on function public.join_code_preview(text) to authenticated;
grant execute on function public.request_to_join(text) to authenticated;
grant execute on function public.answer_join_request(uuid, uuid, boolean) to authenticated;

commit;
