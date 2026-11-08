-- upgrade-2026-11bi: share notes with "Can edit" as well as "Can view".
-- Editors can open the note and change its content (title, text, blocks); only the owner can change who it's
-- shared with, its visibility, archive it or delete it. Includes the archive columns from 11bf, in case that wasn't run.
-- Run in Supabase › SQL Editor. Safe to run more than once. Changes no existing data.

alter table public.notes add column if not exists editors uuid[] not null default '{}'::uuid[];
alter table public.notes add column if not exists archived boolean not null default false;
alter table public.notes add column if not exists archived_at timestamptz;

-- who can open a note: as before, plus its editors
drop policy if exists ws_select on public.notes;
create policy ws_select on public.notes as permissive for select to authenticated using (
  is_active_user() and (
    owner_id = auth.uid()
    or visibility = 'Company'
    or (visibility = 'Vertical' and (vertical = my_vertical() or is_admin()))
    or (visibility = 'People' and auth.uid() = any (shared_with))
    or auth.uid() = any (mentions)
    or auth.uid() = any (editors)
  ));

-- who can save a note: the owner, or an editor
drop policy if exists ws_update on public.notes;
create policy ws_update on public.notes as permissive for update to authenticated
  using (owner_id = auth.uid() or (is_active_user() and auth.uid() = any (editors)))
  with check (owner_id = auth.uid() or (is_active_user() and auth.uid() = any (editors)));

-- an editor's save keeps everything that only the owner may change
create or replace function public.notes_editor_guard()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is not null and old.owner_id <> auth.uid() then
    new.owner_id := old.owner_id;
    new.visibility := old.visibility;
    new.vertical := old.vertical;
    new.shared_with := old.shared_with;
    new.editors := old.editors;
    new.parent_id := old.parent_id;
    new.pinned := old.pinned;
    new.archived := old.archived;
    new.archived_at := old.archived_at;
  end if;
  return new;
end $$;
drop trigger if exists notes_editor_guard on public.notes;
create trigger notes_editor_guard before update on public.notes
  for each row execute function public.notes_editor_guard();

-- check (read-only): the new column and the rule
select (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'notes' and column_name = 'editors') as editors_column,
       (select count(*) from pg_trigger where tgname = 'notes_editor_guard') as editor_guard;
