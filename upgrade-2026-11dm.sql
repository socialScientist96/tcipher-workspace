-- 2026-11dm · Whoever creates a task can edit it, and delete it while it hasn't been started
-- Before: only the vertical's task handlers (and admins) could edit or delete a task, so someone who created a task by
-- mistake, or with the wrong project, couldn't fix or remove it ("add an option to edit the task to update project and
-- delete the empty tasks").
-- Now: the creator can edit their own task, and delete it while it is still "To do" and not in QA.
-- Task handlers and admins keep their rights. Deleted tasks are still copied by the existing trigger. Run in Supabase › SQL editor.

drop policy if exists ws_update on public.tasks;
create policy ws_update on public.tasks as PERMISSIVE for UPDATE to authenticated
  using (is_task_handler(vertical) or (is_active_user() and (auth.uid() = assignee_id or auth.uid() = reviewer_id or auth.uid() = any(collaborators) or auth.uid() = created_by)))
  with check (is_task_handler(vertical) or (is_active_user() and (auth.uid() = assignee_id or auth.uid() = reviewer_id or auth.uid() = any(collaborators) or auth.uid() = created_by)));

drop policy if exists ws_delete on public.tasks;
create policy ws_delete on public.tasks as PERMISSIVE for DELETE to authenticated
  using (is_task_handler(vertical) or (is_active_user() and created_by = auth.uid() and lower(coalesce(status, '')) = 'to do' and coalesce(qa_state, '') = ''));

-- The field guard also has to let the creator through (otherwise only status/checklist could change).
-- The creator can't hand the task to someone else as "creator".
create or replace function public.protect_task_fields()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare work text[] := array['status','checklist','blocked','blocked_reason','branch','pr_url','completed_at','updated_at','mentions','tester_id'];
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
