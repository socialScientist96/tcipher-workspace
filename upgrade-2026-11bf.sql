-- upgrade-2026-11bf: archive notes.
-- An archived note leaves the Notes list and the sidebar but is kept; it can be restored from Notes › Archived.
-- Run in Supabase › SQL Editor. Safe to run more than once. Changes no existing data.

alter table public.notes add column if not exists archived boolean not null default false;
alter table public.notes add column if not exists archived_at timestamptz;

-- check (read-only): the two new columns
select column_name, data_type from information_schema.columns
where table_schema = 'public' and table_name = 'notes' and column_name in ('archived', 'archived_at') order by column_name;
