-- =====================================================================
--  Tcipher Workspace small upgrade (run after upgrade-2026-11.sql)
--  • Meetings can repeat on selected days (tick boxes Mon–Sun)
--  • Saturday becomes a working day
--  Run once in Supabase > SQL Editor > New query > Run. Safe to run again.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 19. Meetings on chosen days (e.g. Mon–Sat), and Saturday as a working day
-- ---------------------------------------------------------------------
alter table public.meetings add column if not exists repeat_days int[] not null default '{}';

-- Tcipher works Monday to Saturday (change any time in Admin panel › Company settings)
update public.settings
set data = jsonb_set(data, '{working_days}', '[1,2,3,4,5,6]'::jsonb, true), updated_at = now()
where id = 1 and coalesce(data->'working_days', '[]'::jsonb) <> '[1,2,3,4,5,6]'::jsonb;
