-- 2026-11eo · Reported problems: comments, "Done by me", Backend → Frontend
-- 1. Anyone can delete their own comment, on tasks too (the task's History keeps a permanent copy of it, as before).
--    Comments can carry attached files (shown under the comment; the file also appears in the item's Files).
-- 2. (no database change) "Done by me" on the Dev board reads the task history.
-- 3. Task flows: a task can go through stages while In progress (e.g. Backend → Frontend → App), one developer per stage.
--    The database refuses QA before the last stage, and logs each handover in the task's History (it counts in "Done by me").
-- Run in Supabase › SQL editor. Safe to run more than once.

-- 1 -------------------------------------------------------------------------------------------------------------------
drop policy if exists ws_delete on public.comments;
create policy ws_delete on public.comments for delete to authenticated
  using (public.is_admin() or (author_id = auth.uid() and public.is_active_user()));
alter table public.comments add column if not exists attachments jsonb not null default '[]'::jsonb;   -- [{id, name, mime, size}]

-- 3 -------------------------------------------------------------------------------------------------------------------
-- A task can follow a flow: the stages it goes through while In progress, in order (e.g. Backend → Frontend → App),
-- with one developer per stage. Flows are chosen from Admin › Task rules; the task keeps its own copy of the stages.
alter table public.tasks add column if not exists flow text[] not null default '{}';
alter table public.tasks add column if not exists flow_step integer not null default 0;
alter table public.tasks add column if not exists stage_devs jsonb not null default '{}'::jsonb;   -- {"Backend": "<person id>", ...}
-- (an earlier draft of this file added these; not needed)
alter table public.tasks drop constraint if exists tasks_dev_part_check;
alter table public.tasks drop constraint if exists tasks_dev_stage_check;
alter table public.tasks drop column if exists dev_part;
alter table public.tasks drop column if exists dev_stage;
alter table public.tasks drop column if exists backend_dev;
alter table public.tasks drop column if exists frontend_dev;

create or replace function public.task_dev_stage() returns trigger
language plpgsql security definer set search_path = public as $$
declare n integer := coalesce(cardinality(new.flow), 0);
begin
  if new.status = 'To do' or n = 0 then new.flow_step := 0; end if;
  if n > 0 and new.flow_step >= n then new.flow_step := n - 1; end if;
  if new.flow_step < 0 then new.flow_step := 0; end if;
  if tg_op = 'UPDATE' then
    if new.status = 'In review' and old.status is distinct from 'In review' and n > 1 and new.flow_step < n - 1 then
      raise exception 'This task is still at %, and its flow is %. Hand each stage over in turn; it goes to QA after %.', new.flow[new.flow_step + 1], array_to_string(new.flow, ' → '), new.flow[n] using errcode = 'P0001';
    end if;
    if new.flow_step is distinct from old.flow_step and n > 0 and new.status = 'In progress' then
      insert into public.task_events (task_id, actor_id, field, old_value, new_value)
      values (new.id, auth.uid(), 'flow_step', coalesce(old.flow[old.flow_step + 1], ''), coalesce(new.flow[new.flow_step + 1], ''));
    end if;
  end if;
  return new;
end $$;
drop trigger if exists task_dev_stage on public.tasks;
create trigger task_dev_stage before insert or update on public.tasks for each row execute function public.task_dev_stage();
revoke all on function public.task_dev_stage() from public, anon, authenticated;

-- the people working on a task may also set what work it needs and hand it from backend to frontend
create or replace function public.protect_task_fields()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare work text[] := array['status','checklist','blocked','blocked_reason','branch','pr_url','completed_at','updated_at','mentions','tester_id','flow','flow_step','stage_devs','collaborators'];
begin
  if auth.uid() is null or public.is_task_handler(old.vertical) then return new; end if;
  -- (2026-11dm) whoever created the task may change its details
  if old.created_by = auth.uid() and public.is_active_user() then
    if new.created_by is distinct from old.created_by then
      raise exception 'The creator of a task can''t be changed.' using errcode = '42501';
    end if;
    return new;
  end if;
  -- a Development task's owners may change its title, notes and owners through task_edit (2026-11ad)
  if coalesce(current_setting('tcipher.task_owner_edit', true), '') = 'on' then return new; end if;
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
end $function$;

-- check (read-only): 3 new task columns, 1 comment column
select (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'tasks' and column_name in ('flow', 'flow_step', 'stage_devs')) as task_columns,
       (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'comments' and column_name = 'attachments') as comment_column;
