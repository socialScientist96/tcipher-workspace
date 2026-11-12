-- 2026-11do · Demo booking (CRM Phase 2)
-- * a meeting can belong to a lead, and can invite people outside the company (the lead's email);
-- * the demo team's busy times (workspace meetings, their synced Google Calendar, approved leave) can be read by
--   anyone booking a demo, as times only (no titles, no attendees outside the team);
-- * the meeting keeps links to its Gemini notes, transcript and recording (filled in by the google-sync function);
-- * reminders: a push 15 minutes before each demo, and a morning list of the day's demos for everyone in one.
-- The demo team itself is a list in settings (Admin › Company settings › Demo team).
-- Run in Supabase › SQL editor. Safe to run more than once.

alter table public.meetings add column if not exists lead_id uuid references public.leads(id) on delete set null;
alter table public.meetings add column if not exists guest_emails text[] not null default '{}';
alter table public.meetings add column if not exists notes_doc_url text not null default '';
alter table public.meetings add column if not exists transcript_url text not null default '';
alter table public.meetings add column if not exists recording_url text not null default '';
alter table public.meetings add column if not exists notes_checked_at timestamptz;
alter table public.meetings add column if not exists reminded_at timestamptz;
create index if not exists meetings_lead_id on public.meetings (lead_id);

-- people on the demo team (settings.data.demo_team = ["<profile id>", ...])
create or replace function public.demo_team() returns uuid[]
language sql stable security definer set search_path = public as $$
  select coalesce(array_agg(x::uuid), '{}')
  from jsonb_array_elements_text(coalesce((select data->'demo_team' from public.settings where id = 1), '[]'::jsonb)) x
  where x ~ '^[0-9a-f-]{36}$';
$$;

-- busy times of the demo team between two dates. Only times: no meeting titles or event names.
-- A meeting with no attendees is for everyone (so everyone on the team is busy).
create or replace function public.demo_availability(p_from date, p_to date) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare team uuid[] := public.demo_team();
begin
  if not public.is_active_user() then raise exception 'Sign in again.' using errcode = '42501'; end if;
  return jsonb_build_object(
    'team', to_jsonb(team),
    'meetings', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', m.id, 'meeting_date', m.meeting_date, 'start_time', m.start_time, 'duration_min', m.duration_min,
        'repeat', m.repeat, 'repeat_days', m.repeat_days, 'google_event_id', m.google_event_id,
        'attendees', case when cardinality(coalesce(m.attendees, '{}')) = 0 then to_jsonb(team)
                          else to_jsonb(array(select a from unnest(m.attendees) a where a = any(team))) end))
      from public.meetings m
      where m.start_time is not null
        and (cardinality(coalesce(m.attendees, '{}')) = 0 or m.attendees && team)
        and m.meeting_date <= p_to
        and (m.meeting_date >= p_from or coalesce(m.repeat, 'Does not repeat') <> 'Does not repeat')), '[]'::jsonb),
    'events', coalesce((
      select jsonb_agg(jsonb_build_object('user_id', e.user_id, 'google_event_id', e.google_event_id,
        'starts_at', e.starts_at, 'ends_at', e.ends_at, 'all_day', e.all_day))
      from public.calendar_events e
      where e.user_id = any(team) and not e.all_day and e.start_date <= p_to and coalesce(e.end_date, e.start_date) >= p_from), '[]'::jsonb),
    'leave', coalesce((
      select jsonb_agg(jsonb_build_object('user_id', l.user_id, 'start_date', l.start_date, 'end_date', l.end_date))
      from public.leave_requests l
      where l.user_id = any(team) and l.status = 'Approved' and coalesce(l.type, '') <> 'Work from home'
        and l.start_date <= p_to and l.end_date >= p_from), '[]'::jsonb));
end $$;
revoke all on function public.demo_availability(date, date) from public, anon;
grant execute on function public.demo_availability(date, date) to authenticated;
revoke all on function public.demo_team() from public, anon;
grant execute on function public.demo_team() to authenticated;

-- reminders, run every 5 minutes by pg_cron (below)
create or replace function public.demo_reminders() returns integer
language plpgsql security definer set search_path = public as $$
declare
  n integer := 0;
  local_now timestamp := now() at time zone 'Asia/Kolkata';
  d date := local_now::date;
  t time := local_now::time;
  day_start time := coalesce(nullif((select data->>'work_start' from public.settings where id = 1), ''), '10:00')::time;
  m record; who uuid; list text;
begin
  -- 1. about 15 minutes before each demo (sent once, 0–20 minutes ahead)
  for m in
    select * from public.meetings
    where kind = 'Sales demo' and meeting_date = d and start_time is not null
      and start_time > t and start_time <= t + interval '20 minutes'
      and (reminded_at is null or (reminded_at at time zone 'Asia/Kolkata')::date < d)
  loop
    for who in select distinct x from unnest(coalesce(m.attendees, '{}') || array[m.created_by]) x where x is not null loop
      insert into public.notifications (user_id, title, body, tbl, entity_id, created_by)
      values (who, 'Demo at ' || to_char(d + m.start_time, 'FMHH12:MI am'), m.title || ' starts in ' ||
              greatest(1, extract(epoch from (m.start_time - t))::int / 60) || ' minutes. Open to join.', 'meetings', m.id, null);
      n := n + 1;
    end loop;
    update public.meetings set reminded_at = now() where id = m.id;
  end loop;

  -- 2. morning list, once a day, from the start of the working day
  if t >= day_start and t < day_start + interval '3 hours' then
    for who in
      select distinct x from public.meetings mm, unnest(coalesce(mm.attendees, '{}') || array[mm.created_by]) x
      where mm.kind = 'Sales demo' and mm.meeting_date = d and mm.start_time is not null and x is not null
    loop
      if exists (select 1 from public.notifications where user_id = who and title = 'Your demo calls today'
                 and (created_at at time zone 'Asia/Kolkata')::date = d) then continue; end if;
      select string_agg(to_char(d + mm.start_time, 'FMHH12:MI am') || ' ' || mm.title, ' · ' order by mm.start_time) into list
      from public.meetings mm
      where mm.kind = 'Sales demo' and mm.meeting_date = d and mm.start_time is not null
        and (who = any(mm.attendees) or mm.created_by = who);
      insert into public.notifications (user_id, title, body, tbl, entity_id, created_by)
      values (who, 'Your demo calls today', list, 'meetings', null, null);
      n := n + 1;
    end loop;
  end if;
  return n;
end $$;
revoke all on function public.demo_reminders() from public, anon, authenticated;

do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.unschedule('tcipher-demo-reminders') where exists (select 1 from cron.job where jobname = 'tcipher-demo-reminders');
    perform cron.schedule('tcipher-demo-reminders', '*/5 * * * *', 'select public.demo_reminders()');
  else
    raise notice 'pg_cron is not turned on: turn it on in Database › Extensions and run this file again, or demo reminders won''t be sent.';
  end if;
end $$;
