-- upgrade-2026-11bc: notes as pages (Notion-style).
-- Each note keeps its content as blocks (text, headings, lists, to-dos, toggles, quotes, callouts, code, sub-pages)
-- and can sit inside another note as a sub-page. The plain-text "body" is still kept up to date by the app,
-- so search, @mentions and older notes keep working.
-- Run in Supabase › SQL Editor. Safe to run more than once. Changes no existing data.

alter table public.notes add column if not exists blocks jsonb not null default '[]'::jsonb;
alter table public.notes add column if not exists parent_id uuid references public.notes(id) on delete cascade;
alter table public.notes add column if not exists icon text not null default '';
create index if not exists notes_parent_id_idx on public.notes (parent_id);

-- a sub-page can only sit under a note the same person owns (the app also copies the parent's sharing to it)
create or replace function public.notes_parent_check()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.parent_id is not null then
    if new.parent_id = new.id then raise exception 'A note can''t be inside itself'; end if;
    if not exists (select 1 from public.notes p where p.id = new.parent_id and p.owner_id = new.owner_id) then
      raise exception 'A sub-page has to be inside one of your own notes';
    end if;
  end if;
  return new;
end $$;
drop trigger if exists notes_parent_check on public.notes;
create trigger notes_parent_check before insert or update of parent_id on public.notes
  for each row execute function public.notes_parent_check();

-- check (read-only): the three new columns
select column_name, data_type from information_schema.columns
where table_schema = 'public' and table_name = 'notes' and column_name in ('blocks', 'parent_id', 'icon') order by column_name;
