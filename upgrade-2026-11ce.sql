-- upgrade-2026-11ce: remember the device (phone, tablet or laptop) of everything people do, for the work summary.
-- The app (2026-11cm and later) says which device it runs on with every request (the "x-device" header). Each of these
-- now keeps it in a new "device" column, filled in by the database itself:
--   activity log (anything created, changed or deleted), task changes, record changes, comments, chat messages,
--   time logged, status changes, QA test runs, meeting joins and leave requests.
-- Check-ins and check-outs already keep theirs (upgrade-2026-11cc).
-- Older rows, and anything done by the server itself (scheduled jobs, Google sync), have an empty device.
-- Run in Supabase › SQL Editor. Safe to run more than once. Changes no existing data.

-- the device of the current request: phone, tablet, laptop, or '' when unknown
create or replace function public.req_device()
returns text language plpgsql stable set search_path = public as $$
declare v text;
begin
  begin
    v := lower(coalesce(nullif(current_setting('request.headers', true), '')::json ->> 'x-device', ''));
  exception when others then v := '';
  end;
  return case when v in ('phone', 'tablet', 'laptop') then v else '' end;
end $$;
grant execute on function public.req_device() to anon, authenticated, service_role;

do $$
declare t text;
begin
  foreach t in array array['activity_log', 'task_events', 'record_events', 'comments', 'chat_messages', 'work_logs',
                           'status_events', 'test_runs', 'meeting_joins', 'leave_requests'] loop
    if to_regclass('public.' || t) is not null then
      execute format('alter table public.%I add column if not exists device text not null default ''''', t);
      -- new rows: the device of the request that made them (older rows keep '')
      execute format('alter table public.%I alter column device set default public.req_device()', t);
    end if;
  end loop;
end $$;

-- check (read-only): 10 means every table now keeps the device
select count(*) as tables_with_device from information_schema.columns
where table_schema = 'public' and column_name = 'device'
  and table_name in ('activity_log', 'task_events', 'record_events', 'comments', 'chat_messages', 'work_logs',
                     'status_events', 'test_runs', 'meeting_joins', 'leave_requests');
