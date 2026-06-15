-- profiles_quiet_tz — store the user's IANA timezone so "heures calmes" (quiet
-- hours / do-not-disturb) are evaluated in their LOCAL time, not UTC.
--
-- The push Edge Function (send-thought-push) reads this and computes the
-- recipient's current local hour (DST-correct via the IANA database). NULL means
-- fall back to UTC (legacy profiles / timezone unavailable on the device).

alter table public.profiles add column if not exists quiet_tz text;

comment on column public.profiles.quiet_tz is
  'IANA timezone (e.g. "Europe/Paris") used to evaluate quiet hours in local time; NULL = evaluate in UTC';
