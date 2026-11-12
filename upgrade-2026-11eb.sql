-- 2026-11eb · Fewer live messages and writes (towards the Supabase free plan)
-- 1. Status signals only when a status really changes. Each person's "last active" time is saved about once a minute,
--    and each save was sending a live signal to every open tab (the free plan allows 2 million live messages a month).
--    Reminder bookkeeping (lunch, check-in, admin alerts) no longer sends signals either.
-- 2. One check-in instead of three. The browser's twice-a-minute usage check-in now also refreshes "last seen" (presence)
--    and "last active" (status) when they're over 50 seconds old, so the app stops sending those two separately.
--    Time tracking (device minutes, active minutes) counts exactly as before.
-- 3. A second check-in in the same minute no longer rewrites that minute's row when nothing changed.
-- Run in Supabase › SQL editor. Safe to run more than once. Needs upgrade-2026-11ea.sql (already run).

-- 1 -------------------------------------------------------------------------------------------------------------------
create or replace function public.live_table_signal() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  r record;
  k text := 'tcipher_sig.' || tg_table_name;
  quiet constant text[] := array['last_active_at', 'updated_at', 'admins_alerted_at', 'lunch_reminded_at', 'checkin_reminded_on', 'checkin_alerted_on'];
begin
  begin
    if tg_op = 'DELETE' then r := old; else r := new; end if;
    if tg_table_name = 'user_status' and tg_op = 'UPDATE' and (to_jsonb(new) - quiet) = (to_jsonb(old) - quiet) then
      return null;   -- only the "last active" time or reminder bookkeeping changed: nothing anyone needs to see live
    end if;
    if tg_table_name in ('comments', 'files') then
      perform realtime.send(jsonb_build_object('t', tg_table_name, 'tbl', r.tbl, 'eid', r.entity_id), 'chg', 'ws-live', true);
    elsif tg_table_name = 'profiles' then
      perform realtime.send(jsonb_build_object('t', 'profiles', 'pid', r.id), 'chg', 'ws-live', true);
    else
      if current_setting(k, true) = '1' then return null; end if;
      perform set_config(k, '1', true);
      perform realtime.send(jsonb_build_object('t', tg_table_name), 'chg', 'ws-live', true);
    end if;
  exception when others then null;   -- a live signal must never stop a save
  end;
  return null;
end $$;
revoke all on function public.live_table_signal() from public, anon, authenticated;

-- 2 and 3 -------------------------------------------------------------------------------------------------------------
-- p_last: when the person last typed, clicked or scrolled in the workspace (the same moment the idle timer uses). Older apps call it
-- without p_last and work as before.
drop function if exists public.usage_ping(text, boolean, text);
create or replace function public.usage_ping(p_device text, p_active boolean, p_session text, p_last timestamptz default null)
returns void language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
  t timestamp := now() at time zone 'Asia/Kolkata';
  b smallint := case p_device when 'laptop' then 1 when 'phone' then 2 when 'tablet' then 4 else 0 end;
  s text := left(regexp_replace(coalesce(p_session, ''), '[^A-Za-z0-9]', '', 'g'), 12);
begin
  if uid is null or b = 0 or not public.is_active_user() then return; end if;
  insert into public.activity_minutes as a (user_id, day, minute, devices, active, sessions)
  values (uid, t::date, (extract(hour from t) * 60 + extract(minute from t))::smallint, b,
          case when p_active then b else 0 end, case when s = '' then '{}' else array[s] end)
  on conflict (user_id, day, minute) do update set
    devices = a.devices | excluded.devices,
    active = a.active | excluded.active,
    sessions = case when s = '' or s = any(a.sessions) or cardinality(a.sessions) >= 8 then a.sessions else a.sessions || s end
  where (a.devices | excluded.devices) <> a.devices or (a.active | excluded.active) <> a.active
     or (s <> '' and not s = any(a.sessions) and cardinality(a.sessions) < 8);
  if p_last is null then return; end if;   -- an older app: it still sends "last seen" and "last active" itself
  -- "last seen" on this device (feeds the device-time totals: one beat about every minute, as before)
  insert into public.presence as p (user_id, last_seen_at, device) values (uid, now(), p_device)
  on conflict (user_id) do update set last_seen_at = excluded.last_seen_at, device = excluded.device
  where p.last_seen_at < now() - interval '50 seconds' or p.device is distinct from excluded.device;
  -- "last active": never in the future, never backwards
  if p_last > now() - interval '2 minutes' then
    update public.user_status set last_active_at = least(p_last, now())
    where user_id = uid and last_active_at < least(p_last, now()) - interval '50 seconds';
  end if;
end $$;
revoke all on function public.usage_ping(text, boolean, text, timestamptz) from public, anon;
grant execute on function public.usage_ping(text, boolean, text, timestamptz) to authenticated;

-- check (read-only): 1
select count(*) as usage_ping_versions from pg_proc where proname = 'usage_ping';
