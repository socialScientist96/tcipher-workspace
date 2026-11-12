-- 2026-11ds · Faster demo booking page
-- The demo-booking function made about five database requests one after another to work out the free times.
-- This gives it everything in one call: settings, the demo team, their meetings, synced calendar events, approved
-- leave, who has Google connected, and (for a personal link) the lead's details to fill in.
-- Only the server can call it (service role); signed-in users and visitors can't.
-- Run in Supabase › SQL editor. Safe to run more than once. demo-booking keeps working without it, just slower.

create or replace function public.demo_booking_data(p_from date, p_to date, p_lead uuid default null) returns jsonb
language sql stable security definer set search_path = public as $$
  with st as (select coalesce((select data from public.settings where id = 1), '{}'::jsonb) as d),
  ids as (
    select x::uuid as id from st, jsonb_array_elements_text(coalesce(st.d->'demo_team', '[]'::jsonb)) x
    where x ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'),
  team as (select p.id, p.full_name from public.profiles p join ids on ids.id = p.id where p.is_active),
  arr as (select coalesce(array_agg(id), '{}'::uuid[]) as a from team)
  select jsonb_build_object(
    'settings', (select d from st),
    'people', coalesce((select jsonb_agg(jsonb_build_object('id', id, 'full_name', full_name, 'is_active', true)) from team), '[]'::jsonb),
    'meetings', coalesce((
      select jsonb_agg(jsonb_build_object('meeting_date', m.meeting_date, 'start_time', m.start_time, 'duration_min', m.duration_min,
        'repeat', m.repeat, 'repeat_days', m.repeat_days, 'attendees', m.attendees))
      from public.meetings m, arr
      where m.start_time is not null and m.meeting_date <= p_to
        and (m.meeting_date >= p_from or coalesce(m.repeat, 'Does not repeat') <> 'Does not repeat')
        and (cardinality(coalesce(m.attendees, '{}'::uuid[])) = 0 or m.attendees && arr.a)), '[]'::jsonb),
    'events', coalesce((
      select jsonb_agg(jsonb_build_object('user_id', e.user_id, 'starts_at', e.starts_at, 'ends_at', e.ends_at))
      from public.calendar_events e, arr
      where e.user_id = any(arr.a) and not e.all_day and e.start_date <= p_to and coalesce(e.end_date, e.start_date) >= p_from), '[]'::jsonb),
    'leave', coalesce((
      select jsonb_agg(jsonb_build_object('user_id', l.user_id, 'start_date', l.start_date, 'end_date', l.end_date, 'type', l.type))
      from public.leave_requests l, arr
      where l.user_id = any(arr.a) and l.status = 'Approved' and l.start_date <= p_to and l.end_date >= p_from), '[]'::jsonb),
    'linked', coalesce((select jsonb_agg(g.user_id) from public.google_links g, arr where g.user_id = any(arr.a)), '[]'::jsonb),
    'lead', (select jsonb_build_object('name', name, 'email', email, 'phone', phone, 'company', company) from public.leads where id = p_lead)
  );
$$;
revoke all on function public.demo_booking_data(date, date, uuid) from public, anon, authenticated;
grant execute on function public.demo_booking_data(date, date, uuid) to service_role;
