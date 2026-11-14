-- 24-hour test, step 1 of 2 · run NOW in Supabase › SQL editor (read-only for the app: it only saves counters)
-- Saves the database's running counters (requests, rows written, disk writes, per-table writes) as the "start" of the test.
-- Step 2 (ops-test-2-report.sql) runs in 24 hours and compares:
--   old setup = average per day from when the counters began until now (almost all of it before tonight's changes)
--   new setup = the 24 hours after this snapshot
-- The snapshot goes in the private "ops" schema, which the app and its API can't reach. Safe to run again (restarts the test).

create schema if not exists ops;
create table if not exists ops.snap (
  taken_at timestamptz not null default now(),
  label text not null,          -- 'start' or 'end'
  kind text not null,           -- db, wal, calls, table
  name text not null,
  a numeric, b numeric, c numeric
);
revoke all on schema ops from public, anon, authenticated;

create or replace function ops.take_snap(p_label text) returns int language plpgsql as $$
declare n int;
begin
  delete from ops.snap where label = p_label;
  -- every request to the database is at least one transaction; rows written; when the counters began
  insert into ops.snap (label, kind, name, a, b, c)
  select p_label, 'db', 'db', xact_commit + xact_rollback, tup_inserted + tup_updated + tup_deleted,
         extract(epoch from coalesce(stats_reset, pg_postmaster_start_time()))
  from pg_stat_database where datname = current_database();
  -- what was written to disk (the write-ahead log)
  if to_regclass('pg_catalog.pg_stat_wal') is not null then
    execute format($q$insert into ops.snap (label, kind, name, a, b, c)
      select %L, 'wal', 'wal', wal_bytes, wal_records, extract(epoch from stats_reset) from pg_stat_wal$q$, p_label);
  end if;
  -- API calls by who made them (signed-in people, the public booking page, the server's own jobs)
  if to_regclass('extensions.pg_stat_statements') is not null and to_regclass('extensions.pg_stat_statements_info') is not null then
    execute format($q$insert into ops.snap (label, kind, name, a, b, c)
      select %L, 'calls', r.rolname, sum(s.calls), sum(s.rows), extract(epoch from (select stats_reset from extensions.pg_stat_statements_info))
      from extensions.pg_stat_statements s join pg_roles r on r.oid = s.userid group by r.rolname$q$, p_label);
  end if;
  -- writes per table
  insert into ops.snap (label, kind, name, a, b, c)
  select p_label, 'table', schemaname || '.' || relname, n_tup_ins, n_tup_upd, n_tup_del
  from pg_stat_all_tables where schemaname in ('public', 'realtime', 'net', 'cron', 'auth');
  get diagnostics n = row_count;
  return n;
end $$;
revoke all on function ops.take_snap(text) from public, anon, authenticated;

select ops.take_snap('start');
select taken_at as test_started, to_timestamp(c) as counters_began from ops.snap where label = 'start' and kind = 'db';
