-- =====================================================================
--  Tcipher Workspace upgrade (run after upgrade-2026-11g.sql)
--  • Email from your own Gmail: sent emails and replies, on leads, deals,
--    clients, contacts, proposals and new joinees
--  • Admins can mark attendance (Present, Half day, Absent)
--  Run once in Supabase > SQL Editor > New query > Run. Safe to run again.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 23. Email from your own Gmail, and attendance marked by admins
-- ---------------------------------------------------------------------
create table if not exists public.emails (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,   -- whose mailbox: the sender
  direction text not null default 'out' check (direction in ('out','in')),
  tbl text not null default '',
  entity_id uuid,
  from_email text not null default '',
  to_email text not null default '',
  cc text not null default '',
  subject text not null default '',
  body text not null default '',
  snippet text not null default '',
  attachments jsonb not null default '[]'::jsonb,
  gmail_message_id text unique,
  gmail_thread_id text,
  rfc_message_id text not null default '',
  sent_at timestamptz not null default now(),
  read_at timestamptz,
  created_at timestamptz not null default now()
);
create index if not exists emails_entity on public.emails (tbl, entity_id, sent_at desc);
create index if not exists emails_user on public.emails (user_id, sent_at desc);
create index if not exists emails_thread on public.emails (gmail_thread_id);
alter table public.emails enable row level security;
drop policy if exists ws_select on public.emails;
drop policy if exists ws_update on public.emails;
-- you see your own emails; emails on a lead, deal, client, contact or proposal are visible to whoever can open it;
-- emails to employees (offer letters, onboarding) stay with the sender and admins
create policy ws_select on public.emails for select to authenticated
  using (public.is_active_user() and (user_id = auth.uid() or public.is_admin()
    or (tbl in ('leads','deals','clients','contacts','proposals') and entity_id is not null and public.can_see(tbl, entity_id))));
create policy ws_update on public.emails for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());
-- no insert/delete policies: only the server sends and records email

alter table public.google_links add column if not exists scopes text not null default '';

alter table public.attendance add column if not exists status text not null default 'Present';
alter table public.attendance add column if not exists marked_by uuid references public.profiles(id) on delete set null;
do $$
begin
  alter table public.attendance add constraint attendance_status_check check (status in ('Present','Half day','Absent'));
exception when duplicate_object then null;
end $$;
alter table public.attendance alter column check_in drop not null;

-- attendance an admin marked can only be changed by an admin (or attendance manager)
create or replace function public.protect_attendance() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null or public.perm('attendance') >= 2 then return coalesce(new, old); end if;
  if tg_op = 'DELETE' then
    if old.marked_by is not null then raise exception 'Your attendance for this day was set by an admin.' using errcode = '42501'; end if;
    return old;
  end if;
  if new.marked_by is distinct from old.marked_by or new.status is distinct from old.status then
    raise exception 'Only an admin can change this.' using errcode = '42501';
  end if;
  if old.marked_by is not null and (new.check_in is distinct from old.check_in or new.check_out is distinct from old.check_out or new.mode is distinct from old.mode) then
    raise exception 'Your attendance for this day was set by an admin. Ask them to change it.' using errcode = '42501';
  end if;
  return new;
end $$;
drop trigger if exists protect_attendance on public.attendance;
create trigger protect_attendance before update or delete on public.attendance
  for each row execute function public.protect_attendance();
create or replace function public.protect_attendance_insert() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is not null and public.perm('attendance') < 2 and (new.marked_by is not null or new.status <> 'Present') then
    raise exception 'Only an admin can mark attendance for this.' using errcode = '42501';
  end if;
  return new;
end $$;
drop trigger if exists protect_attendance_insert on public.attendance;
create trigger protect_attendance_insert before insert on public.attendance
  for each row execute function public.protect_attendance_insert();

do $$
begin
  begin alter publication supabase_realtime add table public.emails; exception when duplicate_object then null; end;
end $$;

-- private attachments for emails (e.g. an offer letter): only the uploader and admins can see them
create or replace function public.can_see(tbl text, rid uuid) returns boolean
language plpgsql stable security invoker set search_path = public as $$
declare ok boolean;
begin
  if tbl = 'email_attachments' then
    return rid = auth.uid() or public.is_admin();
  end if;
  if tbl not in ('projects','sprints','tasks','releases','tickets','clients','contacts','deals','activities',
                 'proposals','leads','campaigns','content','seo_keywords','meetings','leave_requests',
                 'announcements','documents','notes') then
    return false;
  end if;
  execute format('select exists (select 1 from public.%I where id = $1)', tbl) into ok using rid;
  return coalesce(ok, false);
end $$;
