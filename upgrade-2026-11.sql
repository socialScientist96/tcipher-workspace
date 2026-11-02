-- =====================================================================
--  Tcipher Workspace upgrade (November 2026)
--  • Morning scrum, Google Meet join log, remote-first attendance
--  • Leave: 2 days for the rest of 2026; back to 12 from 1 January 2027
--  • Automatic Google Calendar sync and Meet links on the dashboard
--  • Dev tasks: IDs, @tagging, checklists, code links, dependencies, bug details, history
--  • Notes
--  • Dev tasks: task IDs, tagging people, checklist, code links, dependencies, labels, history
--  Run once in Supabase > SQL Editor > New query > Run. Safe to run again.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 14. Meetings: repeats, Google Calendar + Meet, and the join log
--     (safe to run on an existing workspace: only adds what's missing)
-- ---------------------------------------------------------------------
alter table public.meetings add column if not exists repeat text not null default 'Does not repeat';
alter table public.meetings add column if not exists google_event_id text;
alter table public.meetings add column if not exists google_owner uuid references public.profiles(id) on delete set null;
alter table public.meetings add column if not exists google_html_link text not null default '';
update public.meetings set kind = 'Morning scrum' where kind = 'Stand-up';

-- Tcipher is remote-first: new attendance defaults to Remote.
alter table public.attendance alter column mode set default 'Remote';

-- Every time someone joins a meeting: from the workspace's Join button, or imported from Google Meet.
create table if not exists public.meeting_joins (
  id uuid primary key default gen_random_uuid(),
  meeting_id uuid not null references public.meetings(id) on delete cascade,
  user_id uuid references public.profiles(id) on delete set null,
  display_name text not null default '',
  joined_on date not null default current_date,
  joined_at timestamptz not null default now(),
  left_at timestamptz,
  source text not null default 'Workspace',
  external_id text unique,
  created_by uuid default auth.uid() references public.profiles(id) on delete set null,
  created_at timestamptz not null default now()
);
create index if not exists meeting_joins_meeting on public.meeting_joins (meeting_id, joined_on);
create index if not exists meeting_joins_user on public.meeting_joins (user_id, joined_on);
alter table public.meeting_joins enable row level security;

-- See joins for meetings you can see; log your own joins; the organiser and admins can import everyone's.
drop policy if exists ws_select on public.meeting_joins;
drop policy if exists ws_insert on public.meeting_joins;
drop policy if exists ws_update on public.meeting_joins;
drop policy if exists ws_delete on public.meeting_joins;
create policy ws_select on public.meeting_joins for select to authenticated
  using (public.is_active_user() and (user_id = auth.uid() or public.perm('meetings') >= 1 or public.can_see('meetings', meeting_id)));
create policy ws_insert on public.meeting_joins for insert to authenticated
  with check (public.is_active_user() and (user_id = auth.uid() or public.is_admin()
    or exists (select 1 from public.meetings m where m.id = meeting_id and (m.created_by = auth.uid() or m.google_owner = auth.uid()))));
create policy ws_update on public.meeting_joins for update to authenticated
  using (public.is_active_user() and (user_id = auth.uid() or public.is_admin()
    or exists (select 1 from public.meetings m where m.id = meeting_id and (m.created_by = auth.uid() or m.google_owner = auth.uid()))));
create policy ws_delete on public.meeting_joins for delete to authenticated using (public.is_admin());

do $$
begin
  begin
    alter publication supabase_realtime add table public.meeting_joins;
  exception when duplicate_object then null;
  end;
end $$;


-- ---------------------------------------------------------------------
-- 15. Leave allowance: 2 days for 2026 only (normal yearly number stays 12)
-- ---------------------------------------------------------------------
update public.settings
set data = data || jsonb_build_object('leave_overrides', coalesce(data->'leave_overrides', '{}'::jsonb) || '{"2026": 2}'::jsonb),
    updated_at = now()
where id = 1;

-- ---------------------------------------------------------------------
-- 16. Google Calendar sync (server-side, automatic)
--     Tokens are stored where only the server function can read them.
-- ---------------------------------------------------------------------
create or replace function public.my_email() returns text
language sql stable security definer set search_path = public as $$
  select lower(email) from public.profiles where id = auth.uid()
$$;

create table if not exists public.google_tokens (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  refresh_token text not null,
  scopes text not null default '',
  updated_at timestamptz not null default now()
);
alter table public.google_tokens enable row level security;   -- no policies: browsers can never read tokens

create table if not exists public.google_links (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  google_email text not null default '',
  connected_at timestamptz not null default now(),
  last_sync_at timestamptz,
  last_error text not null default ''
);
alter table public.google_links enable row level security;
drop policy if exists ws_select on public.google_links;
create policy ws_select on public.google_links for select to authenticated using (user_id = auth.uid() or public.is_admin());

create table if not exists public.calendar_events (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  google_event_id text not null,
  ical_uid text not null default '',
  title text not null default '',
  starts_at timestamptz,
  ends_at timestamptz,
  all_day boolean not null default false,
  start_date date,
  end_date date,
  meet_link text not null default '',
  html_link text not null default '',
  location text not null default '',
  organizer_email text not null default '',
  attendee_emails text[] not null default '{}',
  updated_at timestamptz not null default now(),
  unique (user_id, google_event_id)
);
create index if not exists calendar_events_day on public.calendar_events (start_date);
alter table public.calendar_events enable row level security;
drop policy if exists ws_select on public.calendar_events;
-- you see your own Google events, and events from colleagues' calendars that you're invited to
create policy ws_select on public.calendar_events for select to authenticated
  using (public.is_active_user() and (user_id = auth.uid() or public.my_email() = any(attendee_emails) or public.is_admin()));

-- joins can also be for Google-only events (not created in the workspace)
alter table public.meeting_joins alter column meeting_id drop not null;
alter table public.meeting_joins add column if not exists event_uid text not null default '';
alter table public.meeting_joins add column if not exists title text not null default '';

do $$
declare t text;
begin
  foreach t in array array['calendar_events','google_links']
  loop
    begin
      execute format('alter publication supabase_realtime add table public.%I', t);
    exception when duplicate_object then null;
    end;
  end loop;
end $$;

-- ---------------------------------------------------------------------
-- 17. Dev tasks: IDs, tagging, checklists, links, dependencies, bug details, history
-- ---------------------------------------------------------------------
alter table public.tasks add column if not exists number bigint generated by default as identity;
create unique index if not exists tasks_number on public.tasks (number);
alter table public.tasks add column if not exists labels text[] not null default '{}';
alter table public.tasks add column if not exists component text not null default '';
alter table public.tasks add column if not exists checklist jsonb not null default '[]'::jsonb;
alter table public.tasks add column if not exists branch text not null default '';
alter table public.tasks add column if not exists pr_url text not null default '';
alter table public.tasks add column if not exists design_url text not null default '';
alter table public.tasks add column if not exists blocked_by uuid[] not null default '{}';
alter table public.tasks add column if not exists release_id uuid references public.releases(id) on delete set null;
alter table public.tasks add column if not exists start_date date;
alter table public.tasks add column if not exists expected_result text not null default '';
alter table public.tasks add column if not exists actual_result text not null default '';
alter table public.tasks add column if not exists build_version text not null default '';
alter table public.tasks add column if not exists device text not null default '';
alter table public.tasks add column if not exists reproducibility text not null default '';
alter table public.tasks add column if not exists mentions uuid[] not null default '{}';
alter table public.comments add column if not exists mentions uuid[] not null default '{}';

-- People tagged on a task can open it and comment, even from another vertical (they can't edit it).
drop trigger if exists track_task_changes on public.tasks;
drop function if exists public.track_task_changes();
drop trigger if exists comment_mentions_to_task on public.comments;
drop function if exists public.comment_mentions_to_task();
drop policy if exists ws_update on public.tasks;
create policy ws_update on public.tasks for update to authenticated
  using (public.is_admin()
    or (public.is_active_user() and (auth.uid() in (assignee_id, reviewer_id, created_by) or auth.uid() = any(collaborators)))
    or (public.perm('tasks') >= 2 and vertical = public.my_vertical()))
  with check (public.is_admin()
    or (public.is_active_user() and (auth.uid() in (assignee_id, reviewer_id, created_by) or auth.uid() = any(collaborators)))
    or (public.perm('tasks') >= 2 and vertical = public.my_vertical()));
drop policy if exists ws_select on public.tasks;
create policy ws_select on public.tasks for select to authenticated
  using (public.is_admin()
    or (public.is_active_user() and (auth.uid() in (assignee_id, reviewer_id, created_by) or auth.uid() = any(collaborators) or auth.uid() = any(mentions)))
    or (public.perm('tasks') >= 1 and vertical = public.my_vertical()));

-- Tagging someone in a task comment gives them access to the task.
create or replace function public.merge_comment_mentions() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.tbl = 'tasks' and cardinality(new.mentions) > 0 then
    update public.tasks t set mentions = array(select distinct x from unnest(t.mentions || new.mentions) as x)
    where t.id = new.entity_id;
  elsif new.tbl = 'notes' and cardinality(new.mentions) > 0 then
    update public.notes n set mentions = array(select distinct x from unnest(n.mentions || new.mentions) as x)
    where n.id = new.entity_id;
  end if;
  return new;
end $$;

-- Task history: who changed what, when (written automatically).
create table if not exists public.task_events (
  id bigint generated always as identity primary key,
  task_id uuid not null references public.tasks(id) on delete cascade,
  actor_id uuid references public.profiles(id) on delete set null,
  field text not null,
  old_value text not null default '',
  new_value text not null default '',
  at timestamptz not null default now()
);
create index if not exists task_events_task on public.task_events (task_id, at desc);
alter table public.task_events enable row level security;
drop policy if exists ws_select on public.task_events;
create policy ws_select on public.task_events for select to authenticated
  using (public.is_active_user() and exists (select 1 from public.tasks t where t.id = task_id));

create or replace function public.log_task_change() returns trigger
language plpgsql security definer set search_path = public as $$
declare f text; o jsonb; n jsonb;
begin
  if tg_op = 'INSERT' then
    insert into public.task_events (task_id, actor_id, field, new_value) values (new.id, auth.uid(), 'created', new.status);
    return null;
  end if;
  o := to_jsonb(old); n := to_jsonb(new);
  foreach f in array array['status','assignee_id','reviewer_id','priority','due_date','sprint_id','release_id','blocked','title','collaborators']
  loop
    if (o->f) is distinct from (n->f) then
      insert into public.task_events (task_id, actor_id, field, old_value, new_value)
      values (new.id, auth.uid(), f, coalesce(o->>f, ''), coalesce(n->>f, ''));
    end if;
  end loop;
  return null;
end $$;
drop trigger if exists log_task_change on public.tasks;
create trigger log_task_change after insert or update on public.tasks
  for each row execute function public.log_task_change();

-- ---------------------------------------------------------------------
-- 18. Notes: private by default; share with people, your vertical, or everyone
-- ---------------------------------------------------------------------
create table if not exists public.notes (
  id uuid primary key default gen_random_uuid(),
  title text not null default '',
  body text not null default '',
  owner_id uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  visibility text not null default 'Private' check (visibility in ('Private','People','Vertical','Company')),
  vertical text,
  shared_with uuid[] not null default '{}',
  mentions uuid[] not null default '{}',
  pinned boolean not null default false,
  task_id uuid references public.tasks(id) on delete set null,
  project_id uuid references public.projects(id) on delete set null,
  meeting_id uuid references public.meetings(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists notes_owner on public.notes (owner_id);
alter table public.notes enable row level security;
drop policy if exists ws_select on public.notes;
drop policy if exists ws_insert on public.notes;
drop policy if exists ws_update on public.notes;
drop policy if exists ws_delete on public.notes;
create policy ws_select on public.notes for select to authenticated
  using (public.is_active_user() and (owner_id = auth.uid()
    or visibility = 'Company'
    or (visibility = 'Vertical' and (vertical = public.my_vertical() or public.is_admin()))
    or (visibility = 'People' and auth.uid() = any(shared_with))
    or auth.uid() = any(mentions)));
create policy ws_insert on public.notes for insert to authenticated
  with check (public.is_active_user() and owner_id = auth.uid());
create policy ws_update on public.notes for update to authenticated
  using (owner_id = auth.uid()) with check (owner_id = auth.uid());
create policy ws_delete on public.notes for delete to authenticated
  using (owner_id = auth.uid());

drop trigger if exists set_updated_at on public.notes;
create trigger set_updated_at before update on public.notes for each row execute function public.set_updated_at();
drop trigger if exists cleanup_children on public.notes;
create trigger cleanup_children after delete on public.notes for each row execute function public.cleanup_children();

drop trigger if exists merge_comment_mentions on public.comments;
create trigger merge_comment_mentions after insert on public.comments
  for each row execute function public.merge_comment_mentions();

-- comments and files can now belong to notes too
create or replace function public.can_see(tbl text, rid uuid) returns boolean
language plpgsql stable security invoker set search_path = public as $$
declare ok boolean;
begin
  if tbl not in ('projects','sprints','tasks','releases','tickets','clients','contacts','deals','activities',
                 'proposals','leads','campaigns','content','seo_keywords','meetings','leave_requests',
                 'announcements','documents','notes') then
    return false;
  end if;
  execute format('select exists (select 1 from public.%I where id = $1)', tbl) into ok using rid;
  return coalesce(ok, false);
end $$;

do $$
declare t text;
begin
  foreach t in array array['notes']
  loop
    begin
      execute format('alter publication supabase_realtime add table public.%I', t);
    exception when duplicate_object then null;
    end;
  end loop;
end $$;

-- ---------------------------------------------------------------------
-- 19. Meetings on chosen days (e.g. Mon–Sat), and Saturday as a working day
-- ---------------------------------------------------------------------
alter table public.meetings add column if not exists repeat_days int[] not null default '{}';

-- Tcipher works Monday to Saturday (change any time in Admin panel › Company settings)
update public.settings
set data = jsonb_set(data, '{working_days}', '[1,2,3,4,5,6]'::jsonb, true), updated_at = now()
where id = 1 and coalesce(data->'working_days', '[]'::jsonb) <> '[1,2,3,4,5,6]'::jsonb;

-- ---------------------------------------------------------------------
-- 20. Task rules: handlers chosen in Admin panel › Task rules
--     Handlers edit everything; people on the task can update status and checklist;
--     the team creates and comments; nobody deletes (archive instead); history is permanent.
-- ---------------------------------------------------------------------
alter table public.tasks add column if not exists archived boolean not null default false;
alter table public.tasks add column if not exists archived_at timestamptz;
alter table public.tasks add column if not exists archived_by uuid references public.profiles(id) on delete set null;

-- Is the current person a task handler for this vertical? (set in settings.data.task_handlers)
create or replace function public.is_task_handler(v text) returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_admin() or exists (
    select 1 from public.settings s
    where s.id = 1 and coalesce(s.data->'task_handlers'->v, '[]'::jsonb) ? auth.uid()::text)
$$;
create or replace function public.task_workers_can_update() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select (data->>'owners_can_update_status')::boolean from public.settings where id = 1), true)
$$;

drop policy if exists ws_select on public.tasks;
drop policy if exists ws_insert on public.tasks;
drop policy if exists ws_update on public.tasks;
drop policy if exists ws_delete on public.tasks;
create policy ws_select on public.tasks for select to authenticated
  using (public.is_task_handler(vertical)
    or (public.is_active_user() and (auth.uid() in (assignee_id, reviewer_id, created_by) or auth.uid() = any(collaborators) or auth.uid() = any(mentions)))
    or (public.perm('tasks') >= 1 and vertical = public.my_vertical()));
-- anyone can create tasks in their own vertical (or for themselves); handlers in theirs
create policy ws_insert on public.tasks for insert to authenticated
  with check (public.is_task_handler(vertical)
    or (public.is_active_user() and (vertical = public.my_vertical() or assignee_id = auth.uid())));
create policy ws_update on public.tasks for update to authenticated
  using (public.is_task_handler(vertical)
    or (public.is_active_user() and (auth.uid() in (assignee_id, reviewer_id) or auth.uid() = any(collaborators))))
  with check (public.is_task_handler(vertical)
    or (public.is_active_user() and (auth.uid() in (assignee_id, reviewer_id) or auth.uid() = any(collaborators))));
-- no delete policy: tasks can't be deleted from the app (archive them instead)

-- People who aren't handlers may only change the "work" fields of tasks they're on.
create or replace function public.protect_task_fields() returns trigger
language plpgsql security definer set search_path = public as $$
declare work text[] := array['status','checklist','blocked','blocked_reason','branch','pr_url','completed_at','updated_at','mentions'];
begin
  if auth.uid() is null or public.is_task_handler(old.vertical) then return new; end if;
  if (to_jsonb(new) - work) is distinct from (to_jsonb(old) - work) then
    raise exception 'Only a task handler can change these details. You can update the status and checklist.' using errcode = '42501';
  end if;
  if not public.task_workers_can_update() then
    -- only reviewing stays open: the reviewer may approve or send back
    if auth.uid() = old.reviewer_id
       and (to_jsonb(new) - array['status','completed_at','blocked','updated_at','mentions']) is not distinct from (to_jsonb(old) - array['status','completed_at','blocked','updated_at','mentions']) then
      return new;
    end if;
    if (to_jsonb(new) - 'mentions' - 'updated_at') is distinct from (to_jsonb(old) - 'mentions' - 'updated_at') then
      raise exception 'Only a task handler can change tasks.' using errcode = '42501';
    end if;
  end if;
  return new;
end $$;
drop trigger if exists protect_task_fields on public.tasks;
create trigger protect_task_fields before update on public.tasks
  for each row execute function public.protect_task_fields();

-- Complete, permanent history: every field, comments and files.
create or replace function public.log_task_change() returns trigger
language plpgsql security definer set search_path = public as $$
declare f text; o jsonb; n jsonb;
begin
  if tg_op = 'INSERT' then
    insert into public.task_events (task_id, actor_id, field, new_value) values (new.id, auth.uid(), 'created', new.status);
    return null;
  end if;
  o := to_jsonb(old); n := to_jsonb(new);
  foreach f in array array['title','description','status','vertical','type','priority','assignee_id','reviewer_id','collaborators',
    'project_id','sprint_id','release_id','component','labels','start_date','due_date','estimate_hours','story_points',
    'severity','environment','reproducibility','build_version','device','steps','expected_result','actual_result',
    'branch','pr_url','design_url','blocked_by','blocked','blocked_reason','checklist','archived']
  loop
    if (o->f) is distinct from (n->f) then
      insert into public.task_events (task_id, actor_id, field, old_value, new_value)
      values (new.id, auth.uid(), f, coalesce(o->>f, ''), coalesce(n->>f, ''));
    end if;
  end loop;
  return null;
end $$;

create or replace function public.log_task_comment_or_file() returns trigger
language plpgsql security definer set search_path = public as $$
declare r record; label text;
begin
  if tg_op = 'DELETE' then r := old; else r := new; end if;
  if r.tbl <> 'tasks' or not exists (select 1 from public.tasks where id = r.entity_id) then return null; end if;
  if tg_table_name = 'comments' then
    label := case tg_op when 'INSERT' then 'comment_added' else 'comment_removed' end;
    insert into public.task_events (task_id, actor_id, field, new_value, old_value)
    values (r.entity_id, auth.uid(), label, case when tg_op = 'INSERT' then r.body else '' end, case when tg_op = 'DELETE' then r.body else '' end);
  else
    label := case tg_op when 'INSERT' then 'file_added' else 'file_removed' end;
    insert into public.task_events (task_id, actor_id, field, new_value) values (r.entity_id, auth.uid(), label, r.name);
  end if;
  return null;
end $$;
drop trigger if exists log_task_comment on public.comments;
create trigger log_task_comment after insert or delete on public.comments
  for each row execute function public.log_task_comment_or_file();
drop trigger if exists log_task_file on public.files;
create trigger log_task_file after insert or delete on public.files
  for each row execute function public.log_task_comment_or_file();

-- Comments on tasks can only be removed by an admin (and that's logged above).
drop policy if exists ws_delete on public.comments;
create policy ws_delete on public.comments for delete to authenticated
  using (public.is_admin() or (author_id = auth.uid() and tbl <> 'tasks'));

-- History can never be changed or removed from the app.
revoke update, delete on public.task_events from authenticated;

-- Changes to the handler list are recorded in the activity log.
create or replace function public.log_settings_change() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if (old.data->'task_handlers') is distinct from (new.data->'task_handlers')
     or (old.data->'owners_can_update_status') is distinct from (new.data->'owners_can_update_status') then
    insert into public.activity_log (actor_id, tbl, action, summary)
    values (auth.uid(), 'settings', 'update', 'Task rules changed');
  end if;
  return null;
end $$;
drop trigger if exists log_settings_change on public.settings;
create trigger log_settings_change after update on public.settings
  for each row execute function public.log_settings_change();

-- Start with nobody but admins as handlers, and people on a task allowed to update its status.
update public.settings
set data = data || jsonb_build_object(
  'task_handlers', coalesce(data->'task_handlers', '{"Development": [], "Sales": [], "Marketing": []}'::jsonb),
  'owners_can_update_status', coalesce(data->'owners_can_update_status', 'true'::jsonb))
where id = 1;

-- ---------------------------------------------------------------------
-- 21. Team calendar: everyone at Tcipher sees each other's synced Google events
--     (title, time, Meet link) and who has connected Google.
-- ---------------------------------------------------------------------
drop policy if exists ws_select on public.calendar_events;
create policy ws_select on public.calendar_events for select to authenticated
  using (public.is_active_user());
drop policy if exists ws_select on public.google_links;
create policy ws_select on public.google_links for select to authenticated
  using (public.is_active_user());
