-- 2026-11eh · Notification emails and email replies only when there's something to do (like WhatsApp)
-- Before: every 2 minutes the database called the google-sync function, which locked the sending mailbox, read every
-- connected Gmail inbox for replies, and looked for notifications to email, even when there was nothing at all.
-- Now:
--   1. Notification emails: the database itself checks every minute, in one small query, whether a notification is due
--      (unread for 2 minutes, by someone who isn't in the workspace). Only then does it call the function. Emails go out
--      a little sooner than before (every minute instead of every 2).
--   2. Replies: once Gmail push is set up (Google Pub/Sub, see the steps Claude gave you), Gmail tells the function when new
--      mail arrives and only then is it read. Until it's set up, or for any inbox whose push has lapsed, replies are still
--      checked every 2 minutes as before. The 30-minute Google job also checks once more, in case a notice was lost.
-- Run in Supabase › SQL editor, then deploy the new google-sync. Safe to run more than once. Needs pg_cron (already on).

-- when each inbox's Gmail push runs out (set by the function; empty until push is set up)
alter table public.google_links add column if not exists gmail_watch_until timestamptz;
alter table public.mail_sender add column if not exists watch_until timestamptz;

-- the notifications that could be due for an email, found quickly
create index if not exists notifications_mail_due on public.notifications (created_at)
  where is_read = false and emailed_at is null and email_status = '';

-- "is there anything for the function to do right now?" (runs inside the database every minute: no call, no write)
create or replace function public.mail_due() returns boolean
language sql stable security definer set search_path = public as $$
  select
    -- a notification unread for 2 minutes (and under 3 hours), for someone not seen in the workspace for 6 minutes
    (exists (select 1 from public.mail_sender where id = 1 and refresh_token <> '')
     and exists (select 1 from public.notifications n
                 where n.is_read = false and n.emailed_at is null and n.email_status = ''
                   and n.created_at < now() - interval '2 minutes' and n.created_at > now() - interval '3 hours'
                   and not exists (select 1 from public.presence p where p.user_id = n.user_id and p.last_seen_at > now() - interval '6 minutes')))
    -- or, every 2 minutes, an inbox without Gmail push still needs its replies checked
    or (extract(minute from now())::int % 2 = 0
        and (exists (select 1 from public.google_links where scopes like '%gmail.readonly%' and (gmail_watch_until is null or gmail_watch_until < now()))
             or exists (select 1 from public.mail_sender where id = 1 and refresh_token <> '' and scopes like '%gmail.readonly%'
                        and (watch_until is null or watch_until < now()))));
$$;
revoke all on function public.mail_due() from public, anon, authenticated;

-- the scheduled job: every minute, call the function only when mail_due() says so
-- (it reuses the address and secret of the existing 2-minute job, then replaces that job)
do $$
declare old text; u text; sec text;
begin
  if not exists (select 1 from pg_extension where extname = 'pg_cron') then
    raise notice 'pg_cron is not on: nothing scheduled.'; return;
  end if;
  select command into old from cron.job where jobname in ('tcipher-email-replies', 'tcipher-mail-due') order by jobname = 'tcipher-mail-due' limit 1;
  u := substring(old from '(https://[^'' ]+/functions/v1/google-sync)');
  sec := substring(old from '"x-cron-secret"\s*:\s*"([^"]+)"');
  if u is null or sec is null then
    raise exception 'Couldn''t find the existing email job''s address and secret. Send Claude the output of: select jobname, schedule from cron.job;';
  end if;
  perform cron.unschedule('tcipher-email-replies') where exists (select 1 from cron.job where jobname = 'tcipher-email-replies');
  perform cron.unschedule('tcipher-mail-due') where exists (select 1 from cron.job where jobname = 'tcipher-mail-due');
  perform cron.schedule('tcipher-mail-due', '* * * * *', format(
    $c$select net.http_post(url := %L, headers := %L::jsonb, body := '{"action": "replies_all"}'::jsonb) where public.mail_due()$c$,
    u, json_build_object('Content-Type', 'application/json', 'x-cron-secret', sec)::text));
end $$;

-- check (read-only): the new job, and the old one gone
select jobname, schedule from cron.job where jobname in ('tcipher-mail-due', 'tcipher-email-replies');
