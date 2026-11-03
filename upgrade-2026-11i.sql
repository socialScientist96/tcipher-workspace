-- =====================================================================
--  Tcipher Workspace upgrade (run after upgrade-2026-11h.sql)
--  • Team chat: channels, direct messages and group chats, kept permanently
--  • Online and last-active status, group chats
--  • Problem reports: automatic error capture and a Report a problem button
--  Run once in Supabase > SQL Editor > New query > Run. Safe to run again.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 24. Team chat (channels + direct messages, kept forever) and last-active status
-- ---------------------------------------------------------------------
create table if not exists public.presence (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  last_seen_at timestamptz not null default now()
);
alter table public.presence enable row level security;
drop policy if exists ws_select on public.presence;
drop policy if exists ws_insert on public.presence;
drop policy if exists ws_update on public.presence;
create policy ws_select on public.presence for select to authenticated using (public.is_active_user());
create policy ws_insert on public.presence for insert to authenticated with check (user_id = auth.uid());
create policy ws_update on public.presence for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

create table if not exists public.chat_channels (
  id uuid primary key default gen_random_uuid(),
  kind text not null default 'channel',
  name text not null default '',
  vertical text,                          -- channel for one vertical (plus admins); null = everyone
  members uuid[] not null default '{}',   -- the two people in a direct message
  dm_key text unique,                     -- "smaller-id:larger-id", so each pair has one conversation
  created_by uuid default auth.uid() references public.profiles(id) on delete set null,
  created_at timestamptz not null default now()
);
create table if not exists public.chat_messages (
  id bigint generated always as identity primary key,
  channel_id uuid not null references public.chat_channels(id) on delete cascade,
  author_id uuid default auth.uid() references public.profiles(id) on delete set null,
  body text not null check (length(body) between 1 and 4000),
  mentions uuid[] not null default '{}',
  created_at timestamptz not null default now(),
  edited_at timestamptz
);
create index if not exists chat_messages_channel on public.chat_messages (channel_id, id desc);
-- where the quick email-reply check left off in each mailbox
alter table public.google_links add column if not exists history_id text not null default '';
create table if not exists public.chat_reads (
  user_id uuid not null references public.profiles(id) on delete cascade,
  channel_id uuid not null references public.chat_channels(id) on delete cascade,
  last_read_id bigint not null default 0,
  primary key (user_id, channel_id)
);

create or replace function public.can_chat(cid uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_active_user() and exists (
    select 1 from public.chat_channels c where c.id = cid and (
      (c.kind = 'channel' and (c.vertical is null or c.vertical = public.my_vertical() or public.is_admin()))
      or auth.uid() = any(c.members)))
$$;

alter table public.chat_channels enable row level security;
alter table public.chat_messages enable row level security;
alter table public.chat_reads enable row level security;
drop policy if exists ws_select on public.chat_channels;
drop policy if exists ws_insert on public.chat_channels;
drop policy if exists ws_update on public.chat_channels;
create policy ws_select on public.chat_channels for select to authenticated
  using (public.is_active_user() and ((kind = 'channel' and (vertical is null or vertical = public.my_vertical() or public.is_admin())) or auth.uid() = any(members)));
-- anyone can start a direct message with one colleague; admins create channels
create policy ws_insert on public.chat_channels for insert to authenticated
  with check (public.is_active_user() and (
    (kind = 'dm' and cardinality(members) = 2 and auth.uid() = any(members))
    or (kind = 'channel' and public.is_admin())));
create policy ws_update on public.chat_channels for update to authenticated using (public.is_admin()) with check (public.is_admin());

drop policy if exists ws_select on public.chat_messages;
drop policy if exists ws_insert on public.chat_messages;
drop policy if exists ws_update on public.chat_messages;
create policy ws_select on public.chat_messages for select to authenticated using (public.can_chat(channel_id));
create policy ws_insert on public.chat_messages for insert to authenticated
  with check (author_id = auth.uid() and public.can_chat(channel_id));
create policy ws_update on public.chat_messages for update to authenticated
  using (author_id = auth.uid()) with check (author_id = auth.uid());
-- no delete policy: chat is kept permanently
revoke delete on public.chat_messages from authenticated;

-- editing only changes the text (and marks it edited)
create or replace function public.protect_chat_edit() returns trigger
language plpgsql as $$
begin
  if new.channel_id <> old.channel_id or new.author_id is distinct from old.author_id or new.created_at <> old.created_at then
    raise exception 'Only the message text can be changed.' using errcode = '42501';
  end if;
  new.edited_at := now();
  return new;
end $$;
drop trigger if exists protect_chat_edit on public.chat_messages;
create trigger protect_chat_edit before update on public.chat_messages for each row execute function public.protect_chat_edit();

drop policy if exists ws_all on public.chat_reads;
create policy ws_all on public.chat_reads for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

-- the starting channels
insert into public.chat_channels (kind, name, vertical)
select 'channel', x.name, x.vertical from (values ('general', null::text), ('development', 'Development'), ('sales', 'Sales'), ('marketing', 'Marketing')) as x(name, vertical)
where not exists (select 1 from public.chat_channels c where c.kind = 'channel' and c.name = x.name);

do $$
begin
  begin alter publication supabase_realtime add table public.chat_messages; exception when duplicate_object then null; end;
  begin alter publication supabase_realtime add table public.chat_channels; exception when duplicate_object then null; end;
end $$;

-- group chats: private conversations with several people
alter table public.chat_channels drop constraint if exists chat_channels_kind_check;
alter table public.chat_channels add constraint chat_channels_kind_check check (kind in ('channel','dm','group'));
drop policy if exists ws_insert on public.chat_channels;
create policy ws_insert on public.chat_channels for insert to authenticated
  with check (public.is_active_user() and (
    (kind = 'dm' and cardinality(members) = 2 and auth.uid() = any(members))
    or (kind = 'group' and cardinality(members) between 2 and 50 and auth.uid() = any(members) and created_by = auth.uid())
    or (kind = 'channel' and public.is_admin())));
drop policy if exists ws_update on public.chat_channels;
-- the person who made a group (or an admin) renames it and adds or removes people
create policy ws_update on public.chat_channels for update to authenticated
  using (public.is_admin() or (kind = 'group' and created_by = auth.uid()))
  with check (public.is_admin() or (kind = 'group' and created_by = auth.uid() and auth.uid() = any(members)));
-- anyone can leave a group
create or replace function public.leave_chat(cid uuid) returns void
language sql security definer set search_path = public as $$
  update public.chat_channels set members = array_remove(members, auth.uid())
  where id = cid and kind = 'group' and auth.uid() = any(members)
$$;
grant execute on function public.leave_chat(uuid) to authenticated;

-- ---------------------------------------------------------------------
-- 25. Problem reports: automatic error capture and the "Report a problem" button
-- ---------------------------------------------------------------------
create table if not exists public.problem_reports (
  id uuid primary key default gen_random_uuid(),
  user_id uuid default auth.uid() references public.profiles(id) on delete set null,
  kind text not null default 'user',
  page text not null default '',
  message text not null default '',
  note text not null default '',
  details jsonb not null default '{}'::jsonb,
  fingerprint text not null default '',
  status text not null default 'Open',
  fixed_note text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
do $$
begin
  alter table public.problem_reports add constraint problem_reports_kind_check check (kind in ('user','auto'));
exception when duplicate_object then null;
end $$;
do $$
begin
  alter table public.problem_reports add constraint problem_reports_status_check check (status in ('Open','Fixed','Ignored'));
exception when duplicate_object then null;
end $$;
do $$
begin
  alter table public.problem_reports add constraint problem_reports_size_check check (length(message) <= 4000 and length(note) <= 4000);
exception when duplicate_object then null;
end $$;
create index if not exists problem_reports_open on public.problem_reports (status, created_at desc);
alter table public.problem_reports enable row level security;
drop policy if exists ws_select on public.problem_reports;
drop policy if exists ws_insert on public.problem_reports;
drop policy if exists ws_update on public.problem_reports;
drop policy if exists ws_delete on public.problem_reports;
-- anyone signed in can report; only admins (and the reporter) see reports; only admins change them
create policy ws_select on public.problem_reports for select to authenticated using (public.is_admin() or user_id = auth.uid());
create policy ws_insert on public.problem_reports for insert to authenticated with check (public.is_active_user() and user_id = auth.uid() and status = 'Open');
create policy ws_update on public.problem_reports for update to authenticated using (public.is_admin()) with check (public.is_admin());
create policy ws_delete on public.problem_reports for delete to authenticated using (public.is_admin());
drop trigger if exists set_updated_at on public.problem_reports;
create trigger set_updated_at before update on public.problem_reports for each row execute function public.set_updated_at();

-- screenshots attached to a report: only the reporter and admins can see them
create or replace function public.can_see(tbl text, rid uuid) returns boolean
language plpgsql stable security invoker set search_path = public as $$
declare ok boolean;
begin
  if tbl = 'email_attachments' then
    return rid = auth.uid() or public.is_admin();
  end if;
  if tbl = 'problem_reports' then
    return exists (select 1 from public.problem_reports p where p.id = rid and (p.user_id = auth.uid() or public.is_admin()));
  end if;
  if tbl not in ('projects','sprints','tasks','releases','tickets','clients','contacts','deals','activities',
                 'proposals','leads','campaigns','content','seo_keywords','meetings','leave_requests',
                 'announcements','documents','notes') then
    return false;
  end if;
  execute format('select exists (select 1 from public.%I where id = $1)', tbl) into ok using rid;
  return coalesce(ok, false);
end $$;
