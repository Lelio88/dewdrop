-- drop_push_throttle — the grouped-notifications v2 alerts once on the CLIENT
-- (onlyAlertOnce + re-arm on app open / tray clear), so the server no longer
-- throttles pushes. Remove the now-dead push-slot machinery: the claim_push_slot
-- RPC and the profiles.last_thought_push_at column it stamped.

begin;

drop function if exists public.claim_push_slot(uuid, int);
alter table public.profiles drop column if exists last_thought_push_at;

commit;
