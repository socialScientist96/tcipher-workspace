-- 2026-11ed · Google Calendar like WhatsApp: Google tells the workspace when a calendar changes
-- Before: every 30 minutes the server read everyone's whole calendar (7 days back, 45 ahead), and each open workspace
-- asked for a sync every 15 minutes as well.
-- Now: when someone connects Google (or at the next scheduled run for people already connected), the server asks Google
-- to send a notice whenever that calendar changes. On a notice, only the events changed in the last few minutes are read,
-- and the workspace shows them within seconds. The scheduled run still checks the last 35 minutes in case a notice was
-- lost, reads the whole calendar once a day, and renews each notice subscription (Google ends them after about a week).
-- The browser's own 15-minute sync is skipped while notices are on.
-- Run in Supabase › SQL editor, then deploy the new google-sync. Safe to run more than once.

-- the subscription (server only: browsers can never read google_tokens)
alter table public.google_tokens add column if not exists cal_channel_id text;
alter table public.google_tokens add column if not exists cal_channel_resource text;
alter table public.google_tokens add column if not exists cal_channel_token text;
alter table public.google_tokens add column if not exists cal_channel_expires timestamptz;
alter table public.google_tokens add column if not exists cal_full_at timestamptz;
create index if not exists google_tokens_cal_channel on public.google_tokens (cal_channel_id);
-- what the person's browser sees: notices are on until this time
alter table public.google_links add column if not exists cal_live_until timestamptz;

-- check (read-only): 5, 1
select (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'google_tokens' and column_name like 'cal\_%') as token_columns,
       (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'google_links' and column_name = 'cal_live_until') as link_column;
