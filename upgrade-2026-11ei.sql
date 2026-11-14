-- 2026-11ei · Notification-email check every 5 minutes, and not at night
-- Before (2026-11eh): the database checked every minute, day and night, whether a notification email was due.
-- Now: every 5 minutes, and only between 9 am and 10 pm India time.
--   - A notification email goes out 2 to 7 minutes after the notification (was 2 to 3), if it's still unread.
--   - At night nothing is checked. Notifications are emailed only while they're under 3 hours old, so one made at
--     night isn't emailed at all: it's waiting in the workspace in the morning. (Ones from after 6 am are emailed at 9 am.)
--   - Replies still arrive within seconds (Gmail push). An inbox whose push has lapsed is checked every 5 minutes in the day.
-- Run in Supabase › SQL editor. Safe to run more than once. Needs upgrade-2026-11eh.sql (already run).

create or replace function public.mail_due() returns boolean
language sql stable security definer set search_path = public as $$
  select
    -- only in the day: 9 am to 10 pm India time (night is 10 pm to 9 am)
    (now() at time zone 'Asia/Kolkata')::time between time '09:00' and time '21:59:59'
    and (
      -- a notification unread for 2 minutes (and under 3 hours), for someone not seen in the workspace for 6 minutes
      (exists (select 1 from public.mail_sender where id = 1 and refresh_token <> '')
       and exists (select 1 from public.notifications n
                   where n.is_read = false and n.emailed_at is null and n.email_status = ''
                     and n.created_at < now() - interval '2 minutes' and n.created_at > now() - interval '3 hours'
                     and not exists (select 1 from public.presence p where p.user_id = n.user_id and p.last_seen_at > now() - interval '6 minutes')))
      -- or an inbox whose Gmail push has lapsed still needs its replies checked
      or exists (select 1 from public.google_links where scopes like '%gmail.readonly%' and (gmail_watch_until is null or gmail_watch_until < now()))
      or exists (select 1 from public.mail_sender where id = 1 and refresh_token <> '' and scopes like '%gmail.readonly%'
                 and (watch_until is null or watch_until < now()))
    );
$$;
revoke all on function public.mail_due() from public, anon, authenticated;

-- every 5 minutes (same job, same address and secret)
do $$
declare c text;
begin
  select command into c from cron.job where jobname = 'tcipher-mail-due';
  if c is null then raise exception 'The tcipher-mail-due job isn''t there: run upgrade-2026-11eh.sql first.'; end if;
  perform cron.schedule('tcipher-mail-due', '*/5 * * * *', c);
end $$;

-- check (read-only): tcipher-mail-due | */5 * * * *
select jobname, schedule from cron.job where jobname = 'tcipher-mail-due';
