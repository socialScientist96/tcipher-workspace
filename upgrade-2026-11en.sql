-- 2026-11en · Task videos play in Google Drive's own player (no workspace data used)
-- The files function shares each video added to a task with tcipher.com ("anyone at tcipher.com with the link can view")
-- and marks it here. Everything else in the workspace's Drive folder stays private.
-- Run in Supabase › SQL editor, then deploy the new files function. Safe to run more than once.
alter table public.files add column if not exists drive_shared boolean not null default false;

-- check (read-only): 1
select count(*) as drive_shared_column from information_schema.columns where table_schema = 'public' and table_name = 'files' and column_name = 'drive_shared';
