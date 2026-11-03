-- Tcipher Workspace: run Google sync automatically.
--   • every 10 minutes: calendars, Meet attendance, and a full check of email replies
--   • every minute: a quick check for new email replies (only conversations started from the workspace)
-- Before running: Database > Extensions > enable "pg_cron" and "pg_net".
-- The secret below must match the CRON_SECRET you add in Edge Functions > Secrets.
-- Run in Supabase > SQL Editor > New query > Run. Safe to run again.

select cron.unschedule('tcipher-google-sync') where exists (select 1 from cron.job where jobname = 'tcipher-google-sync');
select cron.unschedule('tcipher-email-replies') where exists (select 1 from cron.job where jobname = 'tcipher-email-replies');

select cron.schedule(
  'tcipher-google-sync',
  '*/10 * * * *',
  $$
  select net.http_post(
    url := 'https://pfdnziybqaumnofjknsj.supabase.co/functions/v1/google-sync',
    headers := '{"Content-Type": "application/json", "x-cron-secret": "Q6StCwyjs7n6uHf7NOnUY3GStlvUQP_O"}'::jsonb,
    body := '{"action": "sync_all"}'::jsonb
  );
  $$
);

select cron.schedule(
  'tcipher-email-replies',
  '* * * * *',
  $$
  select net.http_post(
    url := 'https://pfdnziybqaumnofjknsj.supabase.co/functions/v1/google-sync',
    headers := '{"Content-Type": "application/json", "x-cron-secret": "Q6StCwyjs7n6uHf7NOnUY3GStlvUQP_O"}'::jsonb,
    body := '{"action": "replies_all"}'::jsonb
  );
  $$
);
