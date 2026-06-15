-- profiles_sound_prefs — per-decor soundscape customization, synced across the
-- user's devices.
--
-- One JSON object keyed by environment name (e.g. "desert"), each holding the
-- ambiance/music layer prefs and per-secondary-category prefs:
--   {
--     "desert": {
--       "amb": {"on": true, "vol": 1.0},
--       "mus": {"on": true, "vol": 1.0},
--       "sec": {
--         "thunder":    {"on": true, "vol": 0.6,  "freq": 0.5},
--         "tumbleweed": {"on": true, "vol": 0.6,  "freq": 0.5}
--       }
--     }
--   }
-- An absent env / field falls back to the engine defaults. `vol` and `freq` are
-- 0..1. The existing owner RLS + table GRANT on public.profiles already cover
-- reads/writes of this column.

alter table public.profiles
  add column if not exists sound_prefs jsonb not null default '{}'::jsonb;

comment on column public.profiles.sound_prefs is
  'Per-decor soundscape customization (keyed by environment name): ambiance/music/secondary on-off + volume + frequency. Absent = engine defaults.';
