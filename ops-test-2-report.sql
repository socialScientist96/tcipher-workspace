-- 24-hour test, step 2 of 2 · run about 24 hours after ops-test-1-start.sql, then paste the result to Claude
-- old_per_day: average per day from when the counters began until the start of the test (almost all old setup)
-- new_per_day: per day since the start of the test (new setup)
-- change_pct: negative = less than before (for example -90 means 90% less)

select ops.take_snap('end');

with s as (select * from ops.snap where label = 'start'),
     e as (select * from ops.snap where label = 'end'),
     t as (select (select max(taken_at) from s) as t0, (select max(taken_at) from e) as t1),
     d as (select extract(epoch from t1 - t0) / 86400 as days_new from t),
     began as (select c from s where kind = 'db'),
     m as (
       -- requests and writes overall
       select 1 as ord, 'Requests to the database (transactions)' as metric, s.a as v0, e.a as v1, coalesce(s.c, (select c from began)) as since
       from s join e using (kind, name) where kind = 'db'
       union all
       select 2, 'Rows written, all tables', s.b, e.b, (select c from began) from s join e using (kind, name) where kind = 'db'
       union all
       select 3, 'Disk writes (write-ahead log, MB)', s.a / 1e6, e.a / 1e6, coalesce(s.c, (select c from began)) from s join e using (kind, name) where kind = 'wal'
       union all
       select 4, 'API calls: ' || case name when 'authenticated' then 'signed-in people (the app)' when 'anon' then 'not signed in (booking page)'
                                     when 'service_role' then 'server functions' else name end,
              s.a, e.a, coalesce(s.c, (select c from began))
       from s join e using (kind, name) where kind = 'calls' and name in ('authenticated', 'anon', 'service_role')
       union all
       -- the tables tonight's changes were about (writes = inserts + updates + deletes)
       select 5, 'Writes: ' || case
                  when x.name like 'realtime.messages%' then 'live signals (realtime.messages)'
                  when x.name = 'realtime.subscription' then 'live connections (realtime.subscription)'
                  when x.name = 'public.calendar_events' then 'calendar events'
                  when x.name = 'public.activity_minutes' then 'time tracking minutes'
                  when x.name = 'public.presence' then 'last seen (presence)'
                  when x.name = 'public.user_status' then 'last active / status'
                  when x.name = 'public.device_usage' then 'old device counter'
                  when x.name = 'public.google_links' then 'Google sync status'
                  when x.name like 'net.%' then 'scheduled job calls (net)'
                  when x.name like 'cron.%' then 'scheduled job log (cron)' end,
              sum(x.s0), sum(x.s1), (select c from began)
       -- a table made after the start (Supabase makes a new live-signal table each day) counts from 0; one removed since counts as unchanged
       from (select coalesce(s.name, e.name) as name, coalesce(s.a + s.b + s.c, 0) as s0, coalesce(e.a + e.b + e.c, s.a + s.b + s.c) as s1
             from (select * from s where kind = 'table') s full join (select * from e where kind = 'table') e using (kind, name)) x
       where x.name like 'realtime.messages%' or x.name in ('realtime.subscription', 'public.calendar_events', 'public.activity_minutes',
             'public.presence', 'public.user_status', 'public.device_usage', 'public.google_links') or x.name like 'net.%' or x.name like 'cron.%'
       group by 2
     )
select metric,
       round(v0 / nullif(extract(epoch from (select t0 from t) - to_timestamp(since)) / 86400, 0)) as old_per_day,
       round((v1 - v0) / nullif((select days_new from d), 0)) as new_per_day,
       round(100 * ((v1 - v0) / nullif((select days_new from d), 0)
                    - v0 / nullif(extract(epoch from (select t0 from t) - to_timestamp(since)) / 86400, 0))
             / nullif(v0 / nullif(extract(epoch from (select t0 from t) - to_timestamp(since)) / 86400, 0), 0)) as change_pct,
       round(extract(epoch from (select t0 from t) - to_timestamp(since)) / 86400, 1) as old_days,
       round((select days_new from d)::numeric, 2) as new_days
from m
order by ord, metric;
