-- upgrade-2026-11cy: put Development board cards in your own order (move a card up or down in its column).
-- - Each task gets a place on the board (board_rank: smaller is higher up). Existing tasks keep today's order
--   (most recently changed first).
-- - A new task, or a task that moves to another column, goes to the top of that column, as now.
-- - Anyone who works on the Development board (admins, the Development team, testers, project managers) can reorder,
--   through move_task_rank(), which changes only the order and nothing else about the task.
-- Run in Supabase › SQL Editor. Safe to run more than once. Changes no task content.

alter table public.tasks add column if not exists board_rank double precision;
update public.tasks set board_rank = -extract(epoch from coalesce(updated_at, created_at, now())) where board_rank is null;

create or replace function public.task_board_rank()
returns trigger language plpgsql set search_path = public as $$
begin
  if tg_op = 'INSERT' then
    if new.board_rank is null then new.board_rank := -extract(epoch from clock_timestamp()); end if;
  elsif new.status is distinct from old.status and new.board_rank is not distinct from old.board_rank then
    new.board_rank := -extract(epoch from clock_timestamp());
  end if;
  return new;
end $$;
drop trigger if exists task_board_rank on public.tasks;
create trigger task_board_rank before insert or update of status, board_rank on public.tasks
  for each row execute function public.task_board_rank();

create or replace function public.move_task_rank(p_task uuid, p_rank double precision)
returns void language plpgsql security definer set search_path = public as $$
declare me public.profiles; t public.tasks; sub text; claims text; tu text;
begin
  select * into me from public.profiles where id = auth.uid();
  if me.id is null or not me.is_active or me.client_id is not null then raise exception 'Sign in again.' using errcode = '42501'; end if;
  select * into t from public.tasks where id = p_task;
  if t.id is null or t.vertical is distinct from 'Development' then raise exception 'That task isn’t on the Development board.'; end if;
  if not (me.is_admin or me.vertical = 'Development' or public.perm('projects') >= 1 or public.perm('qa') >= 1) then
    raise exception 'Only the Development team can reorder the board.' using errcode = '42501';
  end if;
  if p_rank is null or p_rank = 'NaN'::double precision then raise exception 'Bad position.'; end if;
  -- the order is the only thing changed here, so the "who may edit which task details" rule is stepped over for this one
  -- update (it sees no signed-in person), then the sign-in is put back
  sub := current_setting('request.jwt.claim.sub', true); claims := current_setting('request.jwt.claims', true); tu := current_setting('test.uid', true);
  perform set_config('request.jwt.claim.sub', '', true); perform set_config('request.jwt.claims', '', true); perform set_config('test.uid', '', true);
  update public.tasks set board_rank = p_rank where id = p_task;
  perform set_config('request.jwt.claim.sub', coalesce(sub, ''), true); perform set_config('request.jwt.claims', coalesce(claims, ''), true); perform set_config('test.uid', coalesce(tu, ''), true);
end $$;
revoke all on function public.move_task_rank(uuid, double precision) from public, anon;
grant execute on function public.move_task_rank(uuid, double precision) to authenticated;

-- check (read-only): 1, 1, and 0 tasks without a place
select (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'tasks' and column_name = 'board_rank') as rank_column,
       (select count(*) from pg_proc where proname = 'move_task_rank') as move_function,
       (select count(*) from public.tasks where board_rank is null) as tasks_without_place;
