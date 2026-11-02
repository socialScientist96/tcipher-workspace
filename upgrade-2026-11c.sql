-- =====================================================================
--  Tcipher Workspace upgrade (run after upgrade-2026-11b.sql)
--  • Task rules: choose task handlers per vertical in Admin panel › Task rules
--  • Nobody deletes tasks (archive instead); complete, permanent task history
--  Run once in Supabase > SQL Editor > New query > Run. Safe to run again.
-- =====================================================================

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
