-- thoughts_rate_limit — stop mass-insertion abuse + make the push throttle atomic.
--
-- The 60s push cooldown lived only in the Edge Function: it throttled the PUSH,
-- not the INSERT. A client hitting the REST API directly could insert thousands
-- of thoughts and fan out the webhook. We now (a) cap inserts per sender in the
-- DB, and (b) claim the push slot with one atomic UPDATE.

begin;

-- (a) Flood cap: at most 10 thoughts per sender per rolling minute. Generous for
--     a human "thinking of you" app, harsh for a script. The existing index
--     idx_thoughts_sender (sender_id, created_at desc) serves the count.
create or replace function public.enforce_thought_rate_limit()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  if (
    select count(*) from public.thoughts
    where sender_id = new.sender_id
      and created_at > now() - interval '1 minute'
  ) >= 10 then
    raise exception 'rate_limited'
      using errcode = 'check_violation',
            hint = 'too many thoughts sent in the last minute';
  end if;
  return new;
end;
$$;

create trigger thoughts_rate_limit
  before insert on public.thoughts
  for each row execute function public.enforce_thought_rate_limit();

-- (b) Atomic push-slot claim: one conditional UPDATE checks the cooldown AND
--     stamps it, so two concurrent webhook runs can't both notify. Returns true
--     only when THIS call won the slot. service_role-only (the Edge Function).
create or replace function public.claim_push_slot(p_user uuid, p_cooldown_ms int)
returns boolean language plpgsql security definer set search_path = ''
as $$
declare updated int;
begin
  update public.profiles
    set last_thought_push_at = now()
  where id = p_user
    and (last_thought_push_at is null
         or last_thought_push_at < now() - make_interval(secs => p_cooldown_ms / 1000.0));
  get diagnostics updated = row_count;
  return updated > 0;
end;
$$;

revoke execute on function public.claim_push_slot(uuid, int) from public;
grant execute on function public.claim_push_slot(uuid, int) to service_role;

commit;
