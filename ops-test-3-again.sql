-- 24-hour test, round 2 · step 1 of 2 · run NOW in Supabase › SQL editor
-- Keeps the first test's snapshots (as run1_start and run1_end) and starts a new 24 hours.
-- Step 2 (ops-test-4-report.sql) in 24 hours shows: before (old setup) · test 1 (13–14 Nov) · test 2 (from now).
-- Safe to run again (restarts round 2).

-- keep round 1 (only the first time)
update ops.snap set label = 'run1_' || label
where label in ('start', 'end') and not exists (select 1 from ops.snap where label like 'run1_%');

-- per-day figures between two snapshots (tables made or removed in between are handled: new ones count from 0)
create or replace function ops.per_day(l0 text, l1 text)
returns table (ord int, metric text, per_day numeric, days numeric) language sql stable as $$
  with s as (select * from ops.snap where label = l0), e as (select * from ops.snap where label = l1),
       d as (select extract(epoch from (select max(taken_at) from e) - (select max(taken_at) from s)) / 86400 as days),
       m as (
         select 1 as ord, 'Requests to the database (transactions)' as metric, e.a - s.a as v from s join e using (kind, name) where kind = 'db'
         union all select 2, 'Rows written, all tables', e.b - s.b from s join e using (kind, name) where kind = 'db'
         union all select 3, 'Disk writes (write-ahead log, MB)', (e.a - s.a) / 1e6 from s join e using (kind, name) where kind = 'wal'
         union all select 4, 'API calls: ' || case name when 'authenticated' then 'signed-in people (the app)' when 'anon' then 'not signed in (booking page)'
                                              when 'service_role' then 'server functions' end, e.a - s.a
                   from s join e using (kind, name) where kind = 'calls' and name in ('authenticated', 'anon', 'service_role')
         union all select 5, 'Writes: ' || case
                     when x.name like 'realtime.messages%' then 'live signals (realtime.messages)'
                     when x.name = 'realtime.subscription' then 'live connections (realtime.subscription)'
                     when x.name = 'public.calendar_events' then 'calendar events'
                     when x.name = 'public.activity_minutes' then 'time tracking minutes'
                     when x.name = 'public.presence' then 'last seen (presence)'
                     when x.name = 'public.user_status' then 'last active / status'
                     when x.name = 'public.device_usage' then 'old device counter'
                     when x.name in ('public.google_links', 'public.mail_sender') then 'Google / mailbox sync status'
                     when x.name like 'net.%' then 'scheduled job calls (net)'
                     when x.name like 'cron.%' then 'scheduled job log (cron)' end, sum(x.v)
                   from (select coalesce(s.name, e.name) as name,
                                coalesce(e.a + e.b + e.c, s.a + s.b + s.c) - coalesce(s.a + s.b + s.c, 0) as v
                         from (select * from s where kind = 'table') s full join (select * from e where kind = 'table') e using (kind, name)) x
                   where x.name like 'realtime.messages%' or x.name like 'net.%' or x.name like 'cron.%'
                      or x.name in ('realtime.subscription', 'public.calendar_events', 'public.activity_minutes', 'public.presence',
                                    'public.user_status', 'public.device_usage', 'public.google_links', 'public.mail_sender')
                   group by 2)
  select ord, metric, round(v / nullif((select days from d), 0)), round((select days from d)::numeric, 2) from m;
$$;

-- the old setup: a "zero" snapshot at the moment the counters began lets ops.per_day work out the old average the same way
delete from ops.snap where label = 'zero';
insert into ops.snap (taken_at, label, kind, name, a, b, c)
select (select to_timestamp(c) from ops.snap where label = 'run1_start' and kind = 'db'), 'zero', kind, name, 0, 0, 0
from ops.snap where label = 'run1_start';

-- start round 2
select ops.take_snap('start');
select taken_at as round2_started from ops.snap where label = 'start' and kind = 'db';
