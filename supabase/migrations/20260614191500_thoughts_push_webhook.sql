-- thoughts_push_webhook — fire the send-thought-push Edge Function on every new
-- thought, so "X a pensé à toi" is delivered without any app polling.
--
-- Environment-agnostic by design: the function base URL and the service-role
-- key are read from database settings (GUCs), so this one immutable migration
-- works locally, in staging and in prod. Configure each environment with:
--
--   alter database postgres
--     set app.settings.functions_url = 'https://<ref>.functions.supabase.co';
--   alter database postgres
--     set app.settings.service_role_key = '<service-role-key>';
--
-- (Local dev uses 'http://host.docker.internal:54321/functions/v1'.)
--
-- If the settings are absent the trigger is a no-op — it never blocks a thought
-- insert in an environment where push isn't wired yet.

create extension if not exists pg_net with schema extensions;

create or replace function public.notify_thought_push()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  base_url    text := current_setting('app.settings.functions_url', true);
  service_key text := current_setting('app.settings.service_role_key', true);
begin
  if base_url is null or base_url = '' then
    return new; -- push not configured in this environment
  end if;

  perform net.http_post(
    url := base_url || '/send-thought-push',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'apikey', coalesce(service_key, ''),
      'Authorization', 'Bearer ' || coalesce(service_key, '')
    ),
    body := jsonb_build_object(
      'type', 'INSERT',
      'table', 'thoughts',
      'record', to_jsonb(new)
    )
  );
  return new;
end;
$$;

create trigger on_thought_created
  after insert on public.thoughts
  for each row execute function public.notify_thought_push();
