-- =====================================================================
--  Tcipher Workspace upgrade (run after upgrade-2026-11c.sql)
--  • Team calendar: everyone sees each other's Google events and who's connected
--  Run once in Supabase > SQL Editor > New query > Run. Safe to run again.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 21. Team calendar: everyone at Tcipher sees each other's synced Google events
--     (title, time, Meet link) and who has connected Google.
-- ---------------------------------------------------------------------
drop policy if exists ws_select on public.calendar_events;
create policy ws_select on public.calendar_events for select to authenticated
  using (public.is_active_user());
drop policy if exists ws_select on public.google_links;
create policy ws_select on public.google_links for select to authenticated
  using (public.is_active_user());
