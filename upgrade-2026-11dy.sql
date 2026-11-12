-- 2026-11dy · Fixes for states that could get stuck or contradict each other (tasks/QA, CRM, demos, attendance, leave)
-- Run in Supabase › SQL editor. Safe to run more than once.

-- ===== Tasks and QA =====
-- One place decides QA state on every status change, whoever makes it (Dev board, Tasks board, form, import):
-- * In review → In progress / To do by the TESTER (or an admin) = sent back by QA: Failed, reopen count +1.
--   The same move by an owner = taken back out of QA: no "Failed", no count (it used to look like a QA failure).
-- * Done → anything else = reopened: the old QA result and the finish date are cleared.
-- * A move straight to Done that didn't come through QA (admins only) carries no QA result.
-- * A new task (or a duplicate) never starts with an old QA result.
-- * completed_at follows Done for every vertical.
create or replace function public.track_qa_stage() returns trigger
language plpgsql security definer set search_path to 'public' as $function$
declare t uuid; by_tester boolean;
begin
  if new.status = 'Done' and (tg_op = 'INSERT' or old.status is distinct from 'Done') and new.completed_at is null then new.completed_at := now(); end if;
  if tg_op = 'UPDATE' and old.status = 'Done' and new.status is distinct from 'Done' then new.completed_at := null; end if;
  if new.vertical is distinct from 'Development' then return new; end if;
  if tg_op = 'UPDATE' and new.status is not distinct from old.status then return new; end if;
  if new.status = 'In review' then
    new.qa_state := case when tg_op = 'UPDATE' and old.qa_state in ('Failed', 'Retest') then 'Retest' else 'Waiting for QA' end;
    if new.tester_id is null then
      select coalesce(f.tester_id, p.qa_lead_id) into t
        from public.projects p left join public.features f on f.id = new.feature_id
        where p.id = new.project_id;
      if t is null and new.feature_id is not null then select f.tester_id into t from public.features f where f.id = new.feature_id; end if;
      new.tester_id := t;
    end if;
    new.reviewer_id := coalesce(new.tester_id, new.reviewer_id);
  elsif tg_op = 'INSERT' then
    new.qa_state := ''; new.reopen_count := 0;
  elsif old.status = 'In review' and new.status = 'Done' then
    new.qa_state := case when coalesce(old.qa_state, '') <> '' then 'Passed' else old.qa_state end;
  elsif old.status = 'In review' and new.status in ('In progress', 'To do') then
    by_tester := auth.uid() is null or public.is_admin() or auth.uid() = old.tester_id;
    if by_tester and coalesce(old.qa_state, '') <> '' then
      new.qa_state := 'Failed';
      new.reopen_count := coalesce(old.reopen_count, 0) + 1;
    elsif not by_tester then
      new.qa_state := '';
    end if;
  elsif old.status = 'Done' then
    new.qa_state := '';
  elsif new.status = 'Done' then
    new.qa_state := '';
  end if;
  return new;
end $function$;
drop trigger if exists track_qa_stage on public.tasks;
create trigger track_qa_stage before insert or update of status on public.tasks
  for each row execute function public.track_qa_stage();

-- picking up or choosing the tester also makes them the reviewer; approving clears "Blocked"
CREATE OR REPLACE FUNCTION public.task_flow(p_task uuid, p_action text, p_reason text DEFAULT ''::text, p_user uuid DEFAULT NULL::uuid)
 RETURNS tasks
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare t public.tasks; me uuid := auth.uid(); owner boolean; tester boolean; adm boolean;
begin
  if me is null or not public.is_active_user() then raise exception 'Please sign in again.' using errcode = '42501'; end if;
  select * into t from public.tasks where id = p_task for update;
  if not found or not public.can_see('tasks', p_task) then raise exception 'That task isn’t available.' using errcode = '22023'; end if;
  if t.vertical <> 'Development' then raise exception 'This is only for Development tasks.' using errcode = '22023'; end if;
  -- (null-safe: a task with no owner or no tester must never count as "yours")
  owner := coalesce(me = t.assignee_id, false) or coalesce(me = any(coalesce(t.collaborators, '{}')), false);
  tester := public.perm('qa') >= 3;
  adm := public.is_admin();
  if p_action = 'start' then
    if not (owner or adm) then raise exception 'Only the task’s owners can start it.' using errcode = '42501'; end if;
    if t.status <> 'To do' then raise exception 'This task has already started.' using errcode = '22023'; end if;
    update public.tasks set status = 'In progress' where id = p_task returning * into t;
  elsif p_action = 'to_qa' then
    if not (owner or adm) then raise exception 'Only the task’s owners can move it to QA.' using errcode = '42501'; end if;
    if t.status not in ('To do', 'In progress') then raise exception 'This task is already in QA or done.' using errcode = '22023'; end if;
    update public.tasks set status = 'In review' where id = p_task returning * into t;
  elsif p_action = 'pick_up' then
    if not tester then raise exception 'Only testers can pick up a task.' using errcode = '42501'; end if;
    if t.status <> 'In review' then raise exception 'This task isn’t waiting for QA.' using errcode = '22023'; end if;
    if t.tester_id is not null and t.tester_id <> me then raise exception 'Another tester already has this task.' using errcode = '22023'; end if;
    -- (2026-11dy) the tester who picks it up is also its reviewer, so Approve shows for the right person
    update public.tasks set tester_id = me, reviewer_id = me where id = p_task returning * into t;
  elsif p_action = 'set_tester' then
    if not (owner or adm) then raise exception 'Only the task’s owners or an admin can choose the tester.' using errcode = '42501'; end if;
    if p_user is not null and not exists (select 1 from public.profiles where id = p_user and is_active) then raise exception 'That person isn’t available.' using errcode = '22023'; end if;
    update public.tasks set tester_id = p_user, reviewer_id = case when t.status = 'In review' and p_user is not null then p_user else reviewer_id end where id = p_task returning * into t;
  elsif p_action = 'approve' then
    if not (t.tester_id is not distinct from me and t.tester_id is not null or adm) then raise exception 'Only the task’s tester can approve it.' using errcode = '42501'; end if;
    if t.status <> 'In review' then raise exception 'Only a task in QA can be approved.' using errcode = '22023'; end if;
    update public.tasks set status = 'Done', completed_at = now(), blocked = false, blocked_reason = '' where id = p_task returning * into t;
  elsif p_action = 'back' then
    if not (t.tester_id is not distinct from me and t.tester_id is not null or adm) then raise exception 'Only the task’s tester can send it back.' using errcode = '42501'; end if;
    if t.status <> 'In review' then raise exception 'Only a task in QA can be sent back.' using errcode = '22023'; end if;
    if length(btrim(coalesce(p_reason, ''))) < 3 then raise exception 'Write a short reason, so the developer knows what to fix.' using errcode = '22023'; end if;
    update public.tasks set status = 'In progress' where id = p_task returning * into t;
    insert into public.comments (tbl, entity_id, body, author_id) values ('tasks', p_task, 'Sent back to development: ' || btrim(p_reason), me);
  else
    raise exception 'Unknown step.' using errcode = '22023';
  end if;
  return t;
end $function$
;

-- the task's tester can save the steps they're allowed to take (before: only owners, reviewer, collaborators, creator)
drop policy if exists ws_update on public.tasks;
create policy ws_update on public.tasks as PERMISSIVE for UPDATE to authenticated
  using (is_task_handler(vertical) or (is_active_user() and (auth.uid() = assignee_id or auth.uid() = reviewer_id or auth.uid() = tester_id or auth.uid() = any(collaborators) or auth.uid() = created_by)))
  with check (is_task_handler(vertical) or (is_active_user() and (auth.uid() = assignee_id or auth.uid() = reviewer_id or auth.uid() = tester_id or auth.uid() = any(collaborators) or auth.uid() = created_by)));

-- a bug's QA decision updates its test case: approved → Pass, sent back by QA → Fail
create or replace function public.protect_test_case() returns trigger
language plpgsql security definer set search_path to 'public' as $function$
begin
  new.updated_at := now();
  if auth.uid() is null or public.perm('qa') >= 3 or coalesce(current_setting('tcipher.tc_sync', true), '') = 'on' then return new; end if;
  if new.status is distinct from old.status and not (new.status = 'Retest' and old.status in ('Fail','Blocked')) then
    raise exception 'Only a tester can pass or fail a test case. When your fix is ready, mark it Retest.' using errcode = '42501';
  end if;
  if (new.title, new.steps, new.expected, new.feature_id, new.project_id, new.tester_id, new.assignee_id)
     is distinct from (old.title, old.steps, old.expected, old.feature_id, old.project_id, old.tester_id, old.assignee_id) then
    raise exception 'Only a tester can change a test case. You can add notes and mark it Retest.' using errcode = '42501';
  end if;
  return new;
end $function$;
create or replace function public.sync_test_case_from_bug() returns trigger
language plpgsql security definer set search_path to 'public' as $function$
begin
  if new.test_case_id is null or new.status is not distinct from old.status or old.status <> 'In review' then return new; end if;
  perform set_config('tcipher.tc_sync', 'on', true);
  if new.status = 'Done' then
    update public.test_cases set status = 'Pass' where id = new.test_case_id and status is distinct from 'Pass';
  elsif new.status in ('In progress', 'To do') and new.qa_state = 'Failed' then
    update public.test_cases set status = 'Fail' where id = new.test_case_id and status in ('Retest', 'Pending', 'Not run');
  end if;
  perform set_config('tcipher.tc_sync', '', true);
  return new;
end $function$;
drop trigger if exists sync_test_case_from_bug on public.tasks;
create trigger sync_test_case_from_bug after update of status on public.tasks
  for each row execute function public.sync_test_case_from_bug();

-- ===== Lead → deal =====
-- One locked step: a second click, a retry after an error, or a deal already made from this lead returns that deal
-- instead of creating another. Sales can convert even where their role can't edit leads.
create or replace function public.convert_lead(p_lead uuid) returns public.deals
language plpgsql security definer set search_path to 'public' as $function$
declare l public.leads; d public.deals; me uuid := auth.uid(); ig boolean;
begin
  if me is null or not public.is_active_user() then raise exception 'Please sign in again.' using errcode = '42501'; end if;
  if not (public.is_admin() or public.perm('sales') >= 2) then raise exception 'Only Sales can turn a lead into a deal.' using errcode = '42501'; end if;
  select * into l from public.leads where id = p_lead for update;
  if not found or not public.can_see('leads', p_lead) then raise exception 'That lead isn’t available.' using errcode = '22023'; end if;
  ig := l.pipeline = 'Instagram';
  if l.deal_id is not null then select * into d from public.deals where id = l.deal_id; end if;
  if d.id is null then select * into d from public.deals where lead_id = p_lead order by created_at limit 1; end if;
  if d.id is null then
    insert into public.deals (title, company, contact_name, email, phone, service, value, stage, source, lead_type, priority, tags, city, zone, owner_id, lead_id, next_followup, created_by)
    values (coalesce(nullif(l.company, ''), l.name) || case when coalesce(l.service, '') <> '' then ' – ' || l.service else '' end,
            coalesce(l.company, ''), l.name, coalesce(l.email, ''), coalesce(l.phone, ''), coalesce(l.service, ''), l.budget,
            case when ig and l.status in ('Demo booked', 'Demo done', 'Follow up') then 'Meeting' else 'Qualified' end,
            coalesce(l.source, ''), coalesce(l.lead_type, ''), coalesce(l.priority, 'Medium'), coalesce(l.tags, '{}'), coalesce(l.city, ''), coalesce(l.zone, ''),
            coalesce(l.sales_owner_id, me), p_lead, current_date + 2, me)
    returning * into d;
  end if;
  update public.leads set deal_id = d.id, status = case when ig then 'Closed' else 'Converted' end,
         sales_owner_id = coalesce(sales_owner_id, me), handed_over_at = coalesce(handed_over_at, now())
   where id = p_lead;
  return d;
end $function$;
revoke all on function public.convert_lead(uuid) from public, anon;
grant execute on function public.convert_lead(uuid) to authenticated;

-- a deal deleted: its lead can be worked (and converted) again, instead of staying "Converted" with no deal
create or replace function public.lead_after_deal_delete() returns trigger
language plpgsql security definer set search_path to 'public' as $function$
begin
  if old.lead_id is null then return old; end if;
  update public.leads set deal_id = null,
         status = case when pipeline = 'Instagram' then 'Follow up' else 'Qualified' end
   where id = old.lead_id and (deal_id is null or deal_id = old.id) and status in ('Converted', 'Closed');
  return old;
end $function$;
drop trigger if exists lead_after_deal_delete on public.deals;
create trigger lead_after_deal_delete after delete on public.deals
  for each row execute function public.lead_after_deal_delete();

-- ===== Demos =====
-- * never two demos in the same time (unless "two demos at the same time" is allowed, then never for the same person)
-- * a demo moved to another time gets its 15-minute reminder again
-- * a demo deleted: an Instagram lead waiting on it goes back to "Qualified" when no other demo is ahead
create or replace function public.guard_demo_slot() returns trigger
language plpgsql security definer set search_path to 'public' as $function$
declare par boolean; a int; b int;
begin
  if tg_op = 'UPDATE' and (new.meeting_date, new.start_time, new.duration_min) is not distinct from (old.meeting_date, old.start_time, old.duration_min) then
    if new.kind is distinct from 'Sales demo' or new.attendees is not distinct from old.attendees then return new; end if;
  end if;
  if tg_op = 'UPDATE' and (new.meeting_date, new.start_time) is distinct from (old.meeting_date, old.start_time) then new.reminded_at := null; end if;
  if new.kind is distinct from 'Sales demo' or new.start_time is null then return new; end if;
  perform pg_advisory_xact_lock(hashtext('demo-slot:' || new.meeting_date::text));
  par := coalesce((select (data->>'demo_parallel')::boolean from public.settings where id = 1), false);
  a := extract(epoch from new.start_time)::int / 60; b := a + coalesce(new.duration_min, 45);
  if exists (select 1 from public.meetings m
             where m.kind = 'Sales demo' and m.meeting_date = new.meeting_date and m.start_time is not null and m.id <> new.id
               and extract(epoch from m.start_time)::int / 60 < b
               and extract(epoch from m.start_time)::int / 60 + coalesce(m.duration_min, 45) > a
               and (not par or m.attendees && new.attendees)) then
    raise exception 'That time was just taken. Please pick another one.' using errcode = '23P01';
  end if;
  return new;
end $function$;
drop trigger if exists guard_demo_slot on public.meetings;
create trigger guard_demo_slot before insert or update on public.meetings
  for each row execute function public.guard_demo_slot();

create or replace function public.lead_after_demo_delete() returns trigger
language plpgsql security definer set search_path to 'public' as $function$
begin
  if old.kind is distinct from 'Sales demo' or old.lead_id is null then return old; end if;
  update public.leads l set status = 'Qualified'
   where l.id = old.lead_id and l.pipeline = 'Instagram' and l.status = 'Demo booked'
     and not exists (select 1 from public.meetings m where m.lead_id = l.id and m.kind = 'Sales demo' and m.id <> old.id and m.meeting_date >= current_date);
  return old;
end $function$;
drop trigger if exists lead_after_demo_delete on public.meetings;
create trigger lead_after_demo_delete after delete on public.meetings
  for each row execute function public.lead_after_demo_delete();

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
  -- 3. (2026-11dy) Instagram leads move on from "Demo booked" once their demo has ended and no other demo is ahead
  update public.leads l set status = 'Demo done'
  where l.pipeline = 'Instagram' and l.status = 'Demo booked'
    and exists (select 1 from public.meetings m where m.lead_id = l.id and m.kind = 'Sales demo' and m.start_time is not null
                and (m.meeting_date + m.start_time + make_interval(mins => coalesce(m.duration_min, 45))) < local_now)
    and not exists (select 1 from public.meetings m where m.lead_id = l.id and m.kind = 'Sales demo'
                and (m.meeting_date > d or (m.meeting_date = d and m.start_time is not null and m.start_time + make_interval(mins => coalesce(m.duration_min, 45)) > t)));
  return n;
end $$;
revoke all on function public.demo_reminders() from public, anon, authenticated;

-- ===== Leave =====
-- nobody approves or rejects their own request (admins excepted); people can cancel their own pending or future request
create or replace function public.guard_leave_self_decide() returns trigger
language plpgsql security definer set search_path to 'public' as $function$
begin
  if auth.uid() is null or public.is_admin() then return new; end if;
  if new.status is distinct from old.status and new.status in ('Approved', 'Rejected') and new.user_id = auth.uid() then
    raise exception 'Someone else has to approve your own leave.' using errcode = '42501';
  end if;
  return new;
end $function$;
drop trigger if exists guard_leave_self_decide on public.leave_requests;
create trigger guard_leave_self_decide before update on public.leave_requests
  for each row execute function public.guard_leave_self_decide();

create or replace function public.cancel_leave(p_id uuid) returns public.leave_requests
language plpgsql security definer set search_path to 'public' as $function$
declare r public.leave_requests;
begin
  select * into r from public.leave_requests where id = p_id for update;
  if not found or r.user_id is distinct from auth.uid() then raise exception 'That request isn’t yours to cancel.' using errcode = '42501'; end if;
  if not (r.status = 'Pending' or (r.status = 'Approved' and r.start_date > (now() at time zone 'Asia/Kolkata')::date)) then
    raise exception 'Only a pending request, or approved leave that hasn’t started, can be cancelled.' using errcode = '22023';
  end if;
  update public.leave_requests set status = 'Cancelled' where id = p_id returning * into r;
  return r;
end $function$;
revoke all on function public.cancel_leave(uuid) from public, anon;
grant execute on function public.cancel_leave(uuid) to authenticated;

-- ===== Attendance =====
-- no "you haven't checked in" reminder (or admin alert) while someone is out of office or at lunch until later
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
    -- (2026-11dy) unless they set themselves out of office (or at lunch) until later: the app offers exactly that
    if r.check_in is null and st.state in ('ooo', 'lunch') and (st.until is null or st.until > p_now) then continue; end if;
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

-- ===== Phone notifications =====
-- the app removes the previous person's phone registration when someone else signs in on that phone
-- (it only knows the endpoint because that phone registered it)
create or replace function public.release_push_endpoint(p_endpoint text) returns void
language sql security definer set search_path to 'public' as $$
  delete from public.push_subscriptions
   where endpoint = p_endpoint and (p_endpoint like 'fcm:%' or p_endpoint like 'apns:%') and user_id is distinct from auth.uid();
$$;
revoke all on function public.release_push_endpoint(text) from public, anon;
grant execute on function public.release_push_endpoint(text) to authenticated;
