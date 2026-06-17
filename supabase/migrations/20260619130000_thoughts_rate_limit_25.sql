-- thoughts_rate_limit_25 — raise the per-sender flood cap from 10 to 25/min.
-- Migrations are immutable: re-create the trigger function rather than edit the
-- previous one. (Group fan-out will be exempted from this count in a later
-- migration, when the group_id column exists.)

begin;

create or replace function public.enforce_thought_rate_limit()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  if (
    select count(*) from public.thoughts
    where sender_id = new.sender_id
      and created_at > now() - interval '1 minute'
  ) >= 25 then
    raise exception 'rate_limited'
      using errcode = 'check_violation',
            hint = 'too many thoughts sent in the last minute';
  end if;
  return new;
end;
$$;

commit;
