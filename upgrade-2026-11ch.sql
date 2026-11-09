-- upgrade-2026-11ch: late check-outs, forgotten check-outs, and lunch that ends by itself.
-- 1. Checking out after midnight already works in the database (the app now offers it: 2026-11co).
-- 2. Forgot to check out? The app asks "When did you finish?" (that day, or after midnight the next day), up to 7 days
--    back. The time is saved through attendance_set_checkout(), which only accepts a time after the check-in, not in the
--    future, on that day or the next; and the day is marked "check-out entered later" for admins to see.
--    Days an admin marked are not affected; admins can still correct anything as before.
-- 3. Lunch ends by itself when its time is up (45 minutes, or what Company settings say): the person is shown as
--    available again, and inactivity is counted from the end of lunch.
-- Run in Supabase › SQL Editor. Safe to run more than once. Changes no existing data.

alter table public.attendance add column if not exists check_out_late boolean not null default false;
alter table public.attendance add column if not exists check_out_entered_at timestamptz;

create or replace function public.protect_attendance_times()
returns trigger language plpgsql security definer set search_path = public as $$
declare d date := (now() at time zone 'Asia/Kolkata')::date; near interval := interval '10 minutes';
begin
  if auth.uid() is null or public.perm('attendance') >= 2 then return new; end if;
  -- a forgotten check-out entered through attendance_set_checkout(), which checks it itself (2026-11ch)
  if current_setting('tcipher.fill_checkout', true) = 'on' then return new; end if;
  if tg_op = 'INSERT' then
    if new.day <> d then raise exception 'You can only check in for today.' using errcode = '42501'; end if;
    if new.check_in is not null and abs(extract(epoch from new.check_in - now())) > extract(epoch from near) then
      raise exception 'Check-in time must be now. Check your computer''s clock.' using errcode = '42501'; end if;
    if new.check_out is not null then raise exception 'You can''t check out before checking in.' using errcode = '42501'; end if;
    return new;
  end if;
  if new.day <> old.day or new.user_id <> old.user_id then raise exception 'That can''t be changed.' using errcode = '42501'; end if;
  if new.check_in is distinct from old.check_in and not (old.check_in is null and new.check_in is not null and abs(extract(epoch from new.check_in - now())) <= extract(epoch from near)) then
    raise exception 'Check-in time can''t be changed. Ask an admin.' using errcode = '42501'; end if;
  if new.check_out is distinct from old.check_out then
    if new.check_out is null and old.day <> d then raise exception 'You can only check in again on the same day.' using errcode = '42501'; end if;
    if new.check_out is not null and (old.day < d - 1 or abs(extract(epoch from new.check_out - now())) > extract(epoch from near)) then
      raise exception 'Check-out time must be now. Ask an admin to correct an earlier day.' using errcode = '42501'; end if;
  end if;
  return new;
end $$;
drop trigger if exists protect_attendance_times on public.attendance;
create trigger protect_attendance_times before insert or update on public.attendance
  for each row execute function public.protect_attendance_times();

create or replace function public.attendance_set_checkout(p_id uuid, p_at timestamptz)
returns public.attendance language plpgsql security definer set search_path = public as $$
declare a public.attendance; d date := (now() at time zone 'Asia/Kolkata')::date; out_day date;
begin
  select * into a from public.attendance where id = p_id for update;
  if a.id is null or a.user_id is distinct from auth.uid() then raise exception 'That isn''t your attendance.' using errcode = '42501'; end if;
  if a.marked_by is not null then raise exception 'An admin set this day. Ask them to change it.' using errcode = '42501'; end if;
  if a.check_in is null then raise exception 'There''s no check-in on that day.' using errcode = '22023'; end if;
  if a.check_out is not null then raise exception 'You already checked out that day.' using errcode = '22023'; end if;
  if a.day < d - 7 then raise exception 'That''s more than a week ago. Ask an admin to correct it.' using errcode = '42501'; end if;
  out_day := (p_at at time zone 'Asia/Kolkata')::date;
  if p_at <= a.check_in then raise exception 'The check-out has to be after your check-in.' using errcode = '22023'; end if;
  if p_at > now() then raise exception 'That time hasn''t happened yet.' using errcode = '22023'; end if;
  if out_day not in (a.day, a.day + 1) then raise exception 'Choose a time on that day or after midnight the next day.' using errcode = '22023'; end if;
  perform set_config('tcipher.fill_checkout', 'on', true);
  update public.attendance set check_out = p_at, check_out_late = true, check_out_entered_at = now() where id = p_id returning * into a;
  perform set_config('tcipher.fill_checkout', 'off', true);
  return a;
end $$;
revoke all on function public.attendance_set_checkout(uuid, timestamptz) from public, anon;
grant execute on function public.attendance_set_checkout(uuid, timestamptz) to authenticated;

-- people can't mark a check-out as "entered later" (or hide that) themselves
create or replace function public.protect_checkout_late()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null or public.perm('attendance') >= 2 or current_setting('tcipher.fill_checkout', true) = 'on' then return new; end if;
  if tg_op = 'INSERT' then new.check_out_late := false; new.check_out_entered_at := null; return new; end if;
  new.check_out_late := old.check_out_late; new.check_out_entered_at := old.check_out_entered_at;
  return new;
end $$;
drop trigger if exists protect_checkout_late on public.attendance;
create trigger protect_checkout_late before insert or update on public.attendance
  for each row execute function public.protect_checkout_late();

-- lunch ends by itself (the scheduled check, every few minutes)
create or replace function public.presence_watch(p_now timestamp with time zone DEFAULT now())
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  s jsonb; lt timestamp; d date; ws time; we time;
  warn int; grace int; alert_after int; remind int; watch_admins boolean;
  admins uuid[]; r record; st public.user_status; last timestamptz; idle_min numeric;
  n_off int := 0; n_alert int := 0; n_remind int := 0;
begin
  select coalesce(data, '{}'::jsonb) into s from public.settings where id = 1;
  s := coalesce(s, '{}'::jsonb);
  lt := p_now at time zone 'Asia/Kolkata'; d := lt::date;
  perform set_config('tcipher.server', 'on', true);
  if to_regprocedure('public.refresh_leave_status()') is not null then perform public.refresh_leave_status(); end if;
  ws := coalesce(nullif(s->>'work_start', ''), '10:00')::time; we := coalesce(nullif(s->>'work_end', ''), '18:00')::time;
  if not (coalesce(s->'working_days', '[1,2,3,4,5,6]'::jsonb) @> to_jsonb(extract(dow from lt)::int)) then return jsonb_build_object('skipped', 'not a working day'); end if;
  if exists (select 1 from jsonb_array_elements(coalesce(s->'holidays', '[]'::jsonb)) h where h->>'date' = d::text) then return jsonb_build_object('skipped', 'holiday'); end if;
  if lt::time < ws or lt::time >= we then return jsonb_build_object('skipped', 'outside working hours'); end if;
  warn := coalesce((s->>'idle_warn_min')::int, 30); grace := coalesce((s->>'offline_grace_min')::int, 5);
  alert_after := coalesce((s->>'admin_alert_min')::int, 60); remind := coalesce((s->>'checkin_remind_min')::int, 30);
  watch_admins := coalesce((s->>'watch_admins')::boolean, false);
  admins := array(select id from public.profiles where is_admin and is_active);

  for r in
    select p.id, p.full_name, p.is_admin, a.check_in, a.check_out, a.status as att_status
    from public.profiles p
    left join public.attendance a on a.user_id = p.id and a.day = d
    where p.is_active and (watch_admins or not p.is_admin)
      and not exists (select 1 from public.leave_requests l where l.user_id = p.id and l.status = 'Approved'
                      and d between l.start_date and l.end_date and l.type <> 'Work from home')
      and coalesce(a.status, '') <> 'Absent'
  loop
    insert into public.user_status (user_id, last_active_at) values (r.id, p_now - interval '1 minute') on conflict (user_id) do nothing;
    select * into st from public.user_status where user_id = r.id;

    -- not checked in yet: remind them, then tell the admins
    if r.check_in is null then
      if lt::time >= ws + make_interval(mins => remind) and st.checkin_reminded_on is distinct from d then
        insert into public.notifications (user_id, title, body) values (r.id, 'You haven’t checked in yet', 'Check in on Home or in Attendance, or set yourself out of office.');
        update public.user_status set checkin_reminded_on = d where user_id = r.id;
        insert into public.status_events (user_id, at, kind) values (r.id, p_now, 'checkin_reminder');
        n_remind := n_remind + 1;
      end if;
      if lt::time >= ws + make_interval(mins => alert_after) and st.checkin_alerted_on is distinct from d then
        insert into public.notifications (user_id, title, body, tbl, entity_id)
        select unnest(admins), r.full_name || ' hasn’t checked in', 'It’s ' || to_char(lt, 'FMHH12:MI am') || ' and there’s no check-in yet today.', 'team-day', r.id;
        update public.user_status set checkin_alerted_on = d where user_id = r.id;
        n_alert := n_alert + 1;
      end if;
      continue;
    end if;
    if r.check_out is not null then continue; end if;

    -- out of office or at lunch until a time: nothing to check until then
    if st.state in ('ooo', 'lunch') and st.until > p_now then continue; end if;
    last := greatest(st.last_active_at, r.check_in, case when st.state in ('ooo', 'lunch') then st.until end);
    if st.state = 'lunch' and st.until <= p_now and (st.lunch_reminded_at is null or st.lunch_reminded_at < st.until) then
      insert into public.notifications (user_id, title, body) values (r.id, 'Your lunch break is over', 'It ended at ' || to_char(st.until at time zone 'Asia/Kolkata', 'FMHH12:MI am') || '. You’re shown as available again.');
      -- lunch is over: back to normal, and inactivity counts from when lunch ended (2026-11ch)
      update public.user_status set lunch_reminded_at = p_now, state = 'active', until = null, note = '',
             last_active_at = greatest(last_active_at, st.until) where user_id = r.id;
      insert into public.status_events (user_id, at, kind) values (r.id, p_now, 'lunch_over');
      n_remind := n_remind + 1;
    end if;
    if st.state = 'ooo' and st.until <= p_now then
      update public.user_status set state = 'idle', idle_since = st.until, until = null, note = '' where user_id = r.id;
    end if;

    idle_min := extract(epoch from (p_now - last)) / 60;
    -- inactive past the warning and its grace: offline
    if idle_min >= warn + grace and st.state not in ('offline', 'lunch') then
      update public.user_status set state = 'offline', idle_since = last, until = null where user_id = r.id;
      n_off := n_off + 1;
    end if;
    -- inactive for an hour: tell every admin, once per stretch
    if idle_min >= alert_after and (st.admins_alerted_at is null or st.admins_alerted_at < last) then
      insert into public.notifications (user_id, title, body, tbl, entity_id)
      select unnest(admins), 'No activity from ' || r.full_name || ' for over ' || (floor(idle_min / 60))::int || ' hour' || case when floor(idle_min / 60) >= 2 then 's' else '' end,
             'Last active at ' || to_char(last at time zone 'Asia/Kolkata', 'FMHH12:MI am') || '.', 'team-day', r.id;
      update public.user_status set admins_alerted_at = p_now where user_id = r.id;
      insert into public.status_events (user_id, at, kind, note) values (r.id, p_now, 'admin_alert', 'inactive since ' || to_char(last at time zone 'Asia/Kolkata', 'FMHH12:MI am'));
      n_alert := n_alert + 1;
    end if;
  end loop;
  -- keep six months of history
  delete from public.status_events where at < p_now - interval '183 days';
  return jsonb_build_object('marked_offline', n_off, 'admin_alerts', n_alert, 'reminders', n_remind);
end $function$
;
revoke execute on function public.presence_watch(timestamptz) from public, anon, authenticated;

-- check (read-only): 2 columns, 1 function, 1 lunch rule
select (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'attendance' and column_name in ('check_out_late', 'check_out_entered_at')) as columns,
       (select count(*) from pg_proc where proname = 'attendance_set_checkout') as fill_function,
       (select count(*) from pg_proc where proname = 'presence_watch' and pg_get_functiondef(oid) like '%lunch is over: back to normal%') as lunch_ends;
