-- profiles_notifications_enabled — master push switch (a Settings toggle, just
-- below Quiet Hours). When false, the send-thought-push function skips this user
-- entirely (the thought is still recorded and visible in-app).

begin;

alter table public.profiles
  add column if not exists notifications_enabled boolean not null default true;

comment on column public.profiles.notifications_enabled is
  'Master push switch; when false, send-thought-push skips this recipient.';

commit;
