-- friendships_realtime — let the app subscribe to friendship changes in real
-- time so an incoming friend request (and accepts/removals) shows up live,
-- without relaunching the app. RLS on public.friendships still applies to
-- Realtime, so a client only ever receives rows where it is the requester or
-- the addressee.
--
-- Idempotent: re-running (dev reset) must not fail if the table is already in
-- the publication.

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'friendships'
  ) then
    alter publication supabase_realtime add table public.friendships;
  end if;
end $$;
