-- 2026-11dx · Edit your own comments
-- The person who wrote a comment (on a task, lead, deal or anything else) can change its text; the comment then shows
-- "edited". Nothing else about a comment can change (where it is, who wrote it, when, its type or who sees it), and
-- nobody can edit someone else's comment. Deleting stays as it was (task comments: admins only).
-- Run in Supabase › SQL editor. Safe to run more than once.

alter table public.comments add column if not exists edited_at timestamptz;

create or replace function public.guard_comment_edit() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then return new; end if;   -- the server itself (e.g. email replies)
  if new.tbl is distinct from old.tbl or new.entity_id is distinct from old.entity_id
     or new.author_id is distinct from old.author_id or new.created_at is distinct from old.created_at
     or new.kind is distinct from old.kind or new.client_visible is distinct from old.client_visible
     or new.via_email is distinct from old.via_email then
    raise exception 'Only the text of a comment can be edited.' using errcode = '42501';
  end if;
  if new.body is distinct from old.body then new.edited_at := now(); else new.edited_at := old.edited_at; end if;
  return new;
end $$;
drop trigger if exists guard_comment_edit on public.comments;
create trigger guard_comment_edit before update on public.comments
  for each row execute function public.guard_comment_edit();

drop policy if exists ws_update on public.comments;
create policy ws_update on public.comments as PERMISSIVE for UPDATE to authenticated
  using (public.is_active_user() and author_id = auth.uid() and public.can_see(tbl, entity_id))
  with check (public.is_active_user() and author_id = auth.uid());
