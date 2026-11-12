-- 2026-11ec · Time tracking and "last seen" saved like WhatsApp: when you open or leave the workspace, and every 5 minutes
-- Before: every open workspace sent a check-in twice a minute, and each one wrote to the database.
-- Now the browser counts the minutes itself (on screen, and active or not) and sends them together:
--   - when you open the workspace or come back to it,
--   - when you leave it (switch tab, minimise, close),
--   - every 5 minutes while it stays open (so a crash or a sleeping laptop loses at most a few minutes; a browser that crashed
--     sends what it had the next time it opens).
-- Each minute is still kept once per person (several browsers or devices never double up), so the totals in Work summary
-- ("In the workspace", "Active", per device, parallel browsers) mean exactly what they did.
-- "Last seen" is saved on the same occasions. Whether someone is online right now still comes live from the open connection.
-- The old per-minute device-time counter (device_usage) stops: its history stays, and the totals come from the minutes above
-- (as they already have since upgrade-2026-11cf.sql).
-- Run in Supabase › SQL editor. Safe to run more than once. Needs upgrade-2026-11eb.sql (already run).

-- p_minutes: [[minute, active], ...] where minute = whole minutes since 1970 (UTC) and active = 1 or 0.
-- Minutes older than 2 days or in the future are ignored.
create or replace function public.usage_flush(p_device text, p_session text, p_minutes jsonb, p_last timestamptz default null)
returns int language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
  dev smallint := case p_device when 'laptop' then 1 when 'phone' then 2 when 'tablet' then 4 else 0 end;
  ses text := left(regexp_replace(coalesce(p_session, ''), '[^A-Za-z0-9]', '', 'g'), 12);
  now_m bigint := floor(extract(epoch from now()) / 60)::bigint;
  saved int := 0;
begin
  if uid is null or dev = 0 or not public.is_active_user() then return 0; end if;
  if jsonb_typeof(p_minutes) = 'array' and jsonb_array_length(p_minutes) between 1 and 3000 then
    with raw as (
      select (e->>0)::bigint as em, (e->>1) in ('1', 'true') as act
      from jsonb_array_elements(p_minutes) e
      where jsonb_typeof(e) = 'array' and (e->>0) ~ '^[0-9]{1,10}$'
    ), mins as (
      select to_timestamp(em * 60) at time zone 'Asia/Kolkata' as lt, bool_or(act) as act
      from raw where em between now_m - 2880 and now_m + 1 group by em
    ), up as (
      insert into public.activity_minutes as a (user_id, day, minute, devices, active, sessions)
      select uid, lt::date, (extract(hour from lt) * 60 + extract(minute from lt))::smallint, dev,
             case when act then dev else 0 end, case when ses = '' then '{}'::text[] else array[ses] end
      from mins
      on conflict (user_id, day, minute) do update set
        devices = a.devices | excluded.devices,
        active = a.active | excluded.active,
        sessions = case when ses = '' or ses = any(a.sessions) or cardinality(a.sessions) >= 8 then a.sessions else a.sessions || ses end
      where (a.devices | excluded.devices) <> a.devices or (a.active | excluded.active) <> a.active
         or (ses <> '' and not ses = any(a.sessions) and cardinality(a.sessions) < 8)
      returning 1
    ) select count(*) into saved from up;
  end if;
  -- "last seen" (when you opened, left, or every 5 minutes while open)
  insert into public.presence as p (user_id, last_seen_at, device) values (uid, now(), p_device)
  on conflict (user_id) do update set last_seen_at = excluded.last_seen_at, device = excluded.device
  where p.last_seen_at < now() - interval '30 seconds' or p.device is distinct from excluded.device;
  -- "last active": when you last typed, clicked or scrolled; never in the future, never backwards
  if p_last is not null and p_last > now() - interval '2 days' then
    update public.user_status set last_active_at = least(p_last, now())
    where user_id = uid and last_active_at < least(p_last, now()) - interval '30 seconds';
  end if;
  return saved;
end $$;
revoke all on function public.usage_flush(text, text, jsonb, timestamptz) from public, anon;
grant execute on function public.usage_flush(text, text, jsonb, timestamptz) to authenticated;

-- the old per-minute device counter: no longer needed (its history stays in device_usage)
drop trigger if exists count_device_time on public.presence;

-- check (read-only): 1, 0
select (select count(*) from pg_proc where proname = 'usage_flush') as usage_flush,
       (select count(*) from pg_trigger where tgname = 'count_device_time') as old_counter;
