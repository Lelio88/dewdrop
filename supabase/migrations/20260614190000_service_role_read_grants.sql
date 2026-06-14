-- service_role_read_grants — the push Edge Function (send-thought-push) runs as
-- service_role and reads profiles (quiet hours + sender name) and devices
-- (recipient tokens) through PostgREST. service_role bypasses RLS, but
-- PostgREST still needs table-level privileges, which the original migrations
-- granted only to `authenticated`. Without these grants the function's reads
-- come back 42501 (permission denied) and no push is ever sent.

grant select on public.profiles to service_role;
grant select on public.devices  to service_role;
