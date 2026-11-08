-- upgrade-2026-11bi: note sharing with "Can view" / "Can edit", and asking for access.
-- - Tagging someone in a note notifies them but does NOT let them open it.
-- - Someone without access can press "Request access"; the owner is notified and answers Can view, Can edit or Decline.
-- - "Can view" people (shared_with) and "Can edit" people (editors) can open the note whatever its visibility setting.
-- - Editors can change the content; only the owner can change sharing, archive or delete (enforced here).
-- Also adds the archive columns from 11bf, in case that wasn't run.
-- Run in Supabase › SQL Editor. Safe to run more than once. Changes no existing data.

alter table public.notes add column if not exists editors uuid[] not null default '{}'::uuid[];
alter table public.notes add column if not exists archived boolean not null default false;
alter table public.notes add column if not exists archived_at timestamptz;

-- who can open a note (being tagged is no longer enough)
drop policy if exists ws_select on public.notes;
create policy ws_select on public.notes as permissive for select to authenticated using (
  is_active_user() and (
    owner_id = auth.uid()
    or visibility = 'Company'
    or (visibility = 'Vertical' and (vertical = my_vertical() or is_admin()))
    or auth.uid() = any (shared_with)
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
    new.owner_id := old.owner_id; new.visibility := old.visibility; new.vertical := old.vertical;
    new.shared_with := old.shared_with; new.editors := old.editors; new.parent_id := old.parent_id;
    new.pinned := old.pinned; new.archived := old.archived; new.archived_at := old.archived_at;
  end if;
  return new;
end $$;
drop trigger if exists notes_editor_guard on public.notes;
create trigger notes_editor_guard before update on public.notes for each row execute function public.notes_editor_guard();

-- asking for access
create table if not exists public.note_access_requests (
  id uuid primary key default gen_random_uuid(),
  note_id uuid not null references public.notes(id) on delete cascade,
  requester_id uuid not null references public.profiles(id) on delete cascade,
  status text not null default 'pending' check (status in ('pending', 'approved', 'declined')),
  granted text not null default '' check (granted in ('', 'view', 'edit')),
  created_at timestamptz not null default now(),
  decided_at timestamptz,
  decided_by uuid references public.profiles(id) on delete set null,
  unique (note_id, requester_id)
);
alter table public.note_access_requests enable row level security;
drop policy if exists "see own requests or requests for my notes" on public.note_access_requests;
create policy "see own requests or requests for my notes" on public.note_access_requests for select to authenticated
  using (requester_id = auth.uid() or exists (select 1 from public.notes n where n.id = note_id and n.owner_id = auth.uid()));
drop policy if exists "owner answers requests" on public.note_access_requests;
create policy "owner answers requests" on public.note_access_requests for update to authenticated
  using (exists (select 1 from public.notes n where n.id = note_id and n.owner_id = auth.uid()))
  with check (exists (select 1 from public.notes n where n.id = note_id and n.owner_id = auth.uid()));
revoke insert, delete on public.note_access_requests from anon, authenticated;
grant select, update on public.note_access_requests to authenticated;

-- "Request access": records the request and notifies the owner (at most once a day per person and note)
create or replace function public.request_note_access(p_note uuid)
returns text language plpgsql security definer set search_path = public as $$
declare n record; me uuid := auth.uid(); who text; prev record;
begin
  if me is null or not is_active_user() then return 'signed_out'; end if;
  select id, owner_id, title into n from public.notes where id = p_note;
  if not found then return 'not_found'; end if;
  if n.owner_id = me then return 'has_access'; end if;
  select * into prev from public.note_access_requests where note_id = p_note and requester_id = me;
  if found and prev.status = 'pending' and prev.created_at > now() - interval '1 day' then return 'already'; end if;
  insert into public.note_access_requests (note_id, requester_id) values (p_note, me)
    on conflict (note_id, requester_id) do update set status = 'pending', granted = '', created_at = now(), decided_at = null, decided_by = null;
  select full_name into who from public.profiles where id = me;
  insert into public.notifications (user_id, title, body, tbl, entity_id)
    values (n.owner_id, coalesce(who, 'Someone') || ' asked for access to your note: ' || coalesce(nullif(n.title, ''), 'Untitled'),
            'Open the note to give view or edit access, or decline.', 'notes', p_note);
  return 'requested';
end $$;
revoke execute on function public.request_note_access(uuid) from public, anon;
grant execute on function public.request_note_access(uuid) to authenticated;

-- check (read-only)
select (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'notes' and column_name = 'editors') as editors_column,
       (select count(*) from pg_trigger where tgname = 'notes_editor_guard') as editor_guard,
       (select count(*) from pg_class where relname = 'note_access_requests') as requests_table;
