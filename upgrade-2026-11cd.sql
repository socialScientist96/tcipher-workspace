-- upgrade-2026-11cd: the people working on a development task can also be its tester.
-- Replaces rule C of security-fix-2.sql (which refused that with "The people working on a task can't also be its tester").
-- What stays protected: someone working on a task still can't mark it Done themselves, unless they are its tester
-- (approving in QA is the tester's job). Admins are not affected, as before.
-- Run in Supabase › SQL Editor. Safe to run more than once. Changes no existing data.

create or replace function public.guard_self_test()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null or public.is_admin() or new.vertical is distinct from 'Development' then return new; end if;
  -- finishing your own work skips QA, unless you are the task's tester
  if tg_op = 'UPDATE' and new.status = 'Done' and old.status is distinct from 'Done'
     and auth.uid() = any(array_remove(array[old.assignee_id] || coalesce(old.collaborators, '{}'), null))
     and auth.uid() is distinct from old.tester_id then
    raise exception 'Someone else must test and approve your own work, or make yourself its tester first.' using errcode = '42501';
  end if;
  return new;
end $$;
drop trigger if exists guard_self_test on public.tasks;
create trigger guard_self_test before insert or update of tester_id, status, assignee_id, collaborators on public.tasks
  for each row execute function public.guard_self_test();

-- check (read-only): 1 means the new rule is in place
select count(*) as owners_can_test from pg_proc
where proname = 'guard_self_test' and pg_get_functiondef(oid) like '%make yourself its tester first%';
