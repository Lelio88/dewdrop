-- thoughts_realtime — let the app subscribe to incoming "pensées" in real time
-- so the active decor can play its reception burst the instant a friend thinks
-- of you. RLS on public.thoughts still applies to Realtime, so a client only
-- ever receives rows where it is the recipient.
--
-- Idempotent: re-running (dev reset) must not fail if the table is already in
-- the publication.

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'thoughts'
  ) then
    alter publication supabase_realtime add table public.thoughts;
  end if;
end $$;
