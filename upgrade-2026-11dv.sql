-- 2026-11dv · A booked demo blocks that time for the whole demo team
-- Before: a time stayed open while anyone on the demo team was free, so two leads could book the same time with
-- different people. Now the free-time functions also return each meeting's type, and the app and the booking page
-- treat a "Sales demo" as busy for everyone on the demo team (unless "Two demos can run at the same time" is ticked
-- in Admin › Company settings › Demo team).
-- Run in Supabase › SQL editor. Safe to run more than once.

create or replace function public.demo_availability(p_from date, p_to date) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare team uuid[] := public.demo_team();
begin
  if not public.is_active_user() then raise exception 'Sign in again.' using errcode = '42501'; end if;
  return jsonb_build_object(
    'team', to_jsonb(team),
    'meetings', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', m.id, 'kind', m.kind, 'meeting_date', m.meeting_date, 'start_time', m.start_time, 'duration_min', m.duration_min,
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
      select jsonb_agg(jsonb_build_object('kind', m.kind, 'meeting_date', m.meeting_date, 'start_time', m.start_time, 'duration_min', m.duration_min,
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
