-- upgrade-2026-11bt: the client portal.
-- People at a client company get their own login (invited from the workspace). After signing in they see only
-- their portal: their requirements and bugs, meetings, project progress, releases, shared files and proposals.
--
-- How clients are kept out of everything else:
-- - A client login is a profile with client_id set. Such a profile is ALWAYS "inactive" as a staff account
--   (enforced below), so every existing rule, list and job that needs an active staff member leaves it out.
--   Access to the portal is a separate switch: portal_active.
-- - Clients get no direct access to any table. They read and write only through the portal_* functions below,
--   which check their company on every call and return only what the portal shows.
-- - From a signed-in session nobody (not even an admin) can change client_id or portal_active; only the
--   admin-users function (server side) does that, when someone presses Invite or turns access off.
-- - A client only ever receives notifications from the portal functions here, never from the staff app
--   (so internal comments can't reach them by accident).
--
-- Run in Supabase › SQL Editor. Safe to run more than once. Changes no existing data.

-- ---------- columns ----------
alter table public.profiles add column if not exists client_id uuid references public.clients(id) on delete set null;
alter table public.profiles add column if not exists portal_active boolean not null default false;
create index if not exists profiles_client on public.profiles (client_id) where client_id is not null;

alter table public.tickets add column if not exists kind text not null default 'Bug';
do $x$ begin alter table public.tickets add constraint tickets_kind_check check (kind in ('Bug', 'Requirement', 'Question'));
exception when duplicate_object or duplicate_table then null; end $x$;
-- shown in the client's portal (staff can untick it on an internal ticket)
alter table public.tickets add column if not exists client_visible boolean not null default true;
-- a comment on a ticket is internal unless it's a reply to the client
alter table public.comments add column if not exists client_visible boolean not null default false;

-- ---------- a client login can never be a staff login ----------
create or replace function public.profiles_client_guard()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  -- from a signed-in session (the app), these two never change; the admin-users function (server key) sets them
  if tg_op = 'UPDATE' and auth.uid() is not null then
    new.client_id := old.client_id; new.portal_active := old.portal_active;
  end if;
  if new.client_id is not null then
    new.is_active := false; new.is_admin := false; new.role_id := null; new.vertical := null;
  end if;
  return new;
end $$;
drop trigger if exists profiles_client_guard on public.profiles;
create trigger profiles_client_guard before insert or update on public.profiles for each row execute function public.profiles_client_guard();

-- the signed-in person's company, if they're an active portal user
create or replace function public.portal_client()
returns uuid language sql stable security definer set search_path = public as $$
  select p.client_id from public.profiles p join public.clients c on c.id = p.client_id
  where p.id = auth.uid() and p.portal_active and p.client_id is not null
$$;
revoke execute on function public.portal_client() from public, anon;
grant execute on function public.portal_client() to authenticated;

-- ---------- notifications to clients only come from the portal ----------
create or replace function public.notifications_client_guard()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null or coalesce(current_setting('tc.portal', true), '') = 'on' then return new; end if;
  if exists (select 1 from public.profiles where id = new.user_id and client_id is not null) then return null; end if;
  return new;
end $$;
drop trigger if exists notifications_client_guard on public.notifications;
create trigger notifications_client_guard before insert on public.notifications for each row execute function public.notifications_client_guard();

-- tell everyone with portal access at a client
create or replace function public.portal_notify(p_client uuid, p_title text, p_body text, p_tbl text, p_entity uuid, p_skip uuid default null)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform set_config('tc.portal', 'on', true);
  insert into public.notifications (user_id, title, body, tbl, entity_id)
  select p.id, left(p_title, 200), left(coalesce(p_body, ''), 300), p_tbl, p_entity
  from public.profiles p where p.client_id = p_client and p.portal_active and p.id is distinct from p_skip;
  perform set_config('tc.portal', 'off', true);
end $$;
revoke execute on function public.portal_notify(uuid, text, text, text, uuid, uuid) from public, anon, authenticated;

-- tell the team: the account owner and anyone named (assignee, project manager); admins if none of them is active
create or replace function public.portal_notify_team(p_client uuid, p_title text, p_body text, p_tbl text, p_entity uuid, p_people uuid[] default '{}')
returns void language plpgsql security definer set search_path = public as $$
declare ids uuid[];
begin
  select array_agg(distinct x) into ids from unnest(array[(select owner_id from public.clients where id = p_client)] || coalesce(p_people, '{}')) x
  where x is not null and exists (select 1 from public.profiles q where q.id = x and q.is_active);
  if ids is null then select array_agg(id) into ids from public.profiles where is_admin and is_active; end if;
  insert into public.notifications (user_id, title, body, tbl, entity_id)
  select x, left(p_title, 200), left(coalesce(p_body, ''), 300), p_tbl, p_entity from unnest(coalesce(ids, '{}')) x;
end $$;
revoke execute on function public.portal_notify_team(uuid, text, text, text, uuid, uuid[]) from public, anon, authenticated;

-- ---------- meeting requests ----------
create table if not exists public.meeting_requests (
  id uuid primary key default gen_random_uuid(),
  client_id uuid not null references public.clients(id) on delete cascade,
  requested_by uuid not null references public.profiles(id) on delete cascade,
  topic text not null check (char_length(topic) between 1 and 200),
  details text not null default '' check (char_length(details) <= 4000),
  slots timestamptz[] not null default '{}',
  status text not null default 'Requested' check (status in ('Requested', 'Confirmed', 'Declined', 'Cancelled')),
  meeting_id uuid references public.meetings(id) on delete set null,
  answer text not null default '' check (char_length(answer) <= 1000),
  decided_by uuid references public.profiles(id) on delete set null,
  decided_at timestamptz,
  created_at timestamptz not null default now()
);
create index if not exists meeting_requests_client on public.meeting_requests (client_id, created_at desc);
alter table public.meeting_requests enable row level security;
drop policy if exists staff_read on public.meeting_requests;
create policy staff_read on public.meeting_requests for select to authenticated using (public.is_active_user() and public.can_see('clients', client_id));
drop policy if exists staff_answer on public.meeting_requests;
create policy staff_answer on public.meeting_requests for update to authenticated
  using (public.is_active_user() and public.can_see('clients', client_id)) with check (public.is_active_user() and public.can_see('clients', client_id));
revoke insert, delete on public.meeting_requests from anon, authenticated;
grant select, update on public.meeting_requests to authenticated;

-- answering a request tells the client
create or replace function public.meeting_request_answered()
returns trigger language plpgsql security definer set search_path = public as $$
declare m record;
begin
  new.client_id := old.client_id; new.requested_by := old.requested_by; new.topic := old.topic; new.details := old.details; new.slots := old.slots; new.created_at := old.created_at;
  if new.status is distinct from old.status and new.status in ('Confirmed', 'Declined') then
    new.decided_by := auth.uid(); new.decided_at := now();
    if new.status = 'Confirmed' then
      select * into m from public.meetings where id = new.meeting_id;
      perform public.portal_notify(new.client_id, 'Meeting confirmed: ' || coalesce(m.title, new.topic),
        coalesce(to_char(m.meeting_date, 'Dy DD Mon') || coalesce(', ' || to_char(m.start_time, 'HH12:MI AM'), ''), '') || case when new.answer <> '' then ' · ' || new.answer else '' end,
        'meetings', new.meeting_id);
    else
      perform public.portal_notify(new.client_id, 'Meeting request: ' || new.topic, 'The team couldn’t take this one' || case when new.answer <> '' then ': ' || new.answer else '.' end, 'meeting_requests', new.id);
    end if;
  end if;
  return new;
end $$;
drop trigger if exists meeting_request_answered on public.meeting_requests;
create trigger meeting_request_answered before update on public.meeting_requests for each row execute function public.meeting_request_answered();

-- ---------- tickets and replies: keep the client posted ----------
create or replace function public.ticket_portal_update()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.client_id is not null and new.client_visible and new.status is distinct from old.status and public.portal_client() is null then
    perform public.portal_notify(new.client_id,
      case new.status when 'Resolved' then 'Resolved: ' when 'Closed' then 'Closed: ' when 'Waiting on client' then 'We need your input: ' else 'Update: ' end || new.title,
      'Status: ' || case new.status when 'Open' then 'Received' when 'Waiting on client' then 'Waiting on you' else new.status end, 'tickets', new.id);
  end if;
  return new;
end $$;
drop trigger if exists ticket_portal_update on public.tickets;
create trigger ticket_portal_update after update of status on public.tickets for each row execute function public.ticket_portal_update();

create or replace function public.comment_portal_reply()
returns trigger language plpgsql security definer set search_path = public as $$
declare t record;
begin
  if new.tbl <> 'tickets' or not new.client_visible then return new; end if;
  if exists (select 1 from public.profiles where id = new.author_id and client_id is not null) then return new; end if;
  select * into t from public.tickets where id = new.entity_id;
  if t.client_id is null or not t.client_visible then return new; end if;
  perform public.portal_notify(t.client_id, 'Reply from the team: ' || t.title, left(new.body, 140), 'tickets', t.id);
  return new;
end $$;
drop trigger if exists comment_portal_reply on public.comments;
create trigger comment_portal_reply after insert on public.comments for each row execute function public.comment_portal_reply();

-- ---------- what the portal reads ----------
create or replace function public.portal_overview()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare cid uuid := public.portal_client(); me uuid := auth.uid();
begin
  if cid is null then raise exception 'This page is for client accounts.' using errcode = '42501'; end if;
  return jsonb_build_object(
    'me', (select jsonb_build_object('id', p.id, 'name', p.full_name, 'email', p.email, 'phone', coalesce(p.phone, ''), 'email_notifications', p.email_notifications) from public.profiles p where p.id = me),
    'client', (select jsonb_build_object('id', c.id, 'name', c.name) from public.clients c where c.id = cid),
    'owner', (select jsonb_build_object('name', o.full_name, 'email', o.email, 'phone', coalesce(o.phone, ''), 'title', coalesce(o.title, ''))
              from public.clients c join public.profiles o on o.id = c.owner_id and o.is_active where c.id = cid),
    'tickets', coalesce((select jsonb_agg(jsonb_build_object('id', t.id, 'title', t.title, 'kind', t.kind, 'status', t.status, 'priority', t.priority,
        'project', pr.name, 'project_id', t.project_id, 'created_at', t.created_at, 'updated_at', t.updated_at,
        'opened_by', coalesce(op.full_name, ''), 'from_portal', t.channel = 'Portal',
        'replies', (select count(*) from public.comments cm where cm.tbl = 'tickets' and cm.entity_id = t.id and (cm.client_visible or exists (select 1 from public.profiles q where q.id = cm.author_id and q.client_id = cid))),
        'last_reply_at', (select max(cm.created_at) from public.comments cm where cm.tbl = 'tickets' and cm.entity_id = t.id and (cm.client_visible or exists (select 1 from public.profiles q where q.id = cm.author_id and q.client_id = cid))))
        order by t.updated_at desc)
      from public.tickets t left join public.projects pr on pr.id = t.project_id left join public.profiles op on op.id = t.created_by and op.client_id = cid
      where t.client_id = cid and t.client_visible), '[]'::jsonb),
    'projects', coalesce((select jsonb_agg(jsonb_build_object('id', p.id, 'name', p.name, 'status', p.status, 'start_date', p.start_date, 'end_date', p.end_date,
        'tasks', (select count(*) from public.tasks k where k.project_id = p.id and not coalesce(k.archived, false)),
        'done', (select count(*) from public.tasks k where k.project_id = p.id and not coalesce(k.archived, false) and k.status = 'Done'))
        order by p.created_at desc) from public.projects p where p.client_id = cid), '[]'::jsonb),
    'releases', coalesce((select jsonb_agg(x order by (x->>'release_date') desc nulls last) from (
        select jsonb_build_object('id', r.id, 'project', p.name, 'version', r.version, 'name', r.name, 'environment', r.environment, 'status', r.status,
          'release_date', r.release_date, 'notes', left(coalesce(r.notes, ''), 3000)) x
        from public.releases r join public.projects p on p.id = r.project_id and p.client_id = cid limit 100) s), '[]'::jsonb),
    'proposals', coalesce((select jsonb_agg(jsonb_build_object('id', q.id, 'number', q.number, 'title', q.title, 'amount', q.amount, 'status', q.status,
        'sent_on', q.sent_on, 'valid_until', q.valid_until) order by q.created_at desc)
      from public.proposals q where q.client_id = cid and q.status <> 'Draft'), '[]'::jsonb),
    'meetings', coalesce((select jsonb_agg(jsonb_build_object('id', m.id, 'title', m.title, 'meeting_date', m.meeting_date, 'start_time', m.start_time,
        'duration_min', m.duration_min, 'link', coalesce(m.link, ''), 'agenda', coalesce(m.agenda, ''), 'repeat', m.repeat, 'repeat_days', m.repeat_days)
        order by m.meeting_date, m.start_time)
      from public.meetings m where m.client_id = cid and me = any (m.attendees)
        and (m.meeting_date >= current_date - 60 or coalesce(m.repeat, 'Does not repeat') <> 'Does not repeat')), '[]'::jsonb),
    'requests', coalesce((select jsonb_agg(jsonb_build_object('id', r.id, 'topic', r.topic, 'details', r.details, 'slots', to_jsonb(r.slots), 'status', r.status,
        'answer', r.answer, 'meeting_id', r.meeting_id, 'created_at', r.created_at, 'by', coalesce(p.full_name, '')) order by r.created_at desc)
      from public.meeting_requests r left join public.profiles p on p.id = r.requested_by where r.client_id = cid), '[]'::jsonb),
    'files', coalesce((select jsonb_agg(jsonb_build_object('id', f.id, 'name', f.name, 'size', f.size, 'mime', f.mime, 'path', f.path, 'created_at', f.created_at,
        'by', coalesce(u.full_name, ''), 'from_team', coalesce(u.client_id is null, true), 'ticket_id', case when f.tbl = 'tickets' then f.entity_id end,
        'ticket', case when f.tbl = 'tickets' then (select t.title from public.tickets t where t.id = f.entity_id) end) order by f.created_at desc)
      from public.files f left join public.profiles u on u.id = f.uploaded_by
      where f.storage = 'supabase' and f.path like 'portal/' || cid::text || '/%'
        and (f.tbl = 'clients' or (f.tbl = 'tickets' and exists (select 1 from public.tickets t where t.id = f.entity_id and t.client_id = cid and t.client_visible)))), '[]'::jsonb)
  );
end $$;

create or replace function public.portal_ticket(p_id uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare cid uuid := public.portal_client(); t record;
begin
  if cid is null then raise exception 'This page is for client accounts.' using errcode = '42501'; end if;
  select * into t from public.tickets where id = p_id and client_id = cid and client_visible;
  if not found then return null; end if;
  return jsonb_build_object(
    'id', t.id, 'title', t.title, 'kind', t.kind, 'status', t.status, 'priority', t.priority, 'description', coalesce(t.description, ''),
    'project', (select name from public.projects where id = t.project_id), 'created_at', t.created_at, 'updated_at', t.updated_at, 'resolved_at', t.resolved_at,
    'opened_by', (select full_name from public.profiles where id = t.created_by and client_id = cid),
    'comments', coalesce((select jsonb_agg(jsonb_build_object('id', c.id, 'body', c.body, 'created_at', c.created_at,
        'author', coalesce(a.full_name, 'Tcipher team'), 'mine', c.author_id = auth.uid(), 'team', a.client_id is null) order by c.created_at)
      from public.comments c left join public.profiles a on a.id = c.author_id
      where c.tbl = 'tickets' and c.entity_id = t.id and (c.client_visible or a.client_id = cid)), '[]'::jsonb),
    'files', coalesce((select jsonb_agg(jsonb_build_object('id', f.id, 'name', f.name, 'size', f.size, 'mime', f.mime, 'path', f.path, 'created_at', f.created_at,
        'by', coalesce(u.full_name, ''), 'from_team', coalesce(u.client_id is null, true)) order by f.created_at)
      from public.files f left join public.profiles u on u.id = f.uploaded_by
      where f.tbl = 'tickets' and f.entity_id = t.id and f.storage = 'supabase' and f.path like 'portal/' || cid::text || '/%'), '[]'::jsonb));
end $$;

-- ---------- what the portal writes ----------
create or replace function public.portal_new_ticket(p_kind text, p_title text, p_details text, p_priority text, p_project uuid default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare cid uuid := public.portal_client(); me uuid := auth.uid(); nid uuid; owner uuid; mgr uuid; who text;
begin
  if cid is null then raise exception 'This page is for client accounts.' using errcode = '42501'; end if;
  if p_kind not in ('Bug', 'Requirement', 'Question') then raise exception 'Pick bug, requirement or question.' using errcode = '22023'; end if;
  p_title := btrim(coalesce(p_title, ''));
  if char_length(p_title) not between 3 and 200 then raise exception 'Give it a short title (3 to 200 characters).' using errcode = '22023'; end if;
  if char_length(coalesce(p_details, '')) > 8000 then raise exception 'The details are too long (8,000 characters at most).' using errcode = '22023'; end if;
  if p_priority not in ('Low', 'Medium', 'High', 'Critical') then p_priority := 'Medium'; end if;
  if p_project is not null and not exists (select 1 from public.projects where id = p_project and client_id = cid) then p_project := null; end if;
  if (select count(*) from public.tickets where created_by = me and created_at > now() - interval '1 day') >= 40 then
    raise exception 'That’s a lot for one day. Please call or email your account manager.' using errcode = '22023'; end if;
  select owner_id into owner from public.clients where id = cid;
  select manager_id into mgr from public.projects where id = p_project;
  insert into public.tickets (title, description, client_id, project_id, priority, status, channel, assignee_id, created_by, kind, client_visible)
  values (p_title, coalesce(p_details, ''), cid, p_project, p_priority, 'Open', 'Portal',
          (select id from public.profiles where id = coalesce(owner, mgr) and is_active), me, p_kind, true)
  returning id into nid;
  select full_name into who from public.profiles where id = me;
  perform public.portal_notify_team(cid, coalesce(who, 'A client') || ' (' || (select name from public.clients where id = cid) || ') reported a ' || lower(p_kind) || ': ' || p_title,
    left(coalesce(p_details, ''), 140), 'tickets', nid, array[mgr]);
  return nid;
end $$;

create or replace function public.portal_reply(p_ticket uuid, p_body text)
returns uuid language plpgsql security definer set search_path = public as $$
declare cid uuid := public.portal_client(); me uuid := auth.uid(); t record; nid uuid; who text;
begin
  if cid is null then raise exception 'This page is for client accounts.' using errcode = '42501'; end if;
  select * into t from public.tickets where id = p_ticket and client_id = cid and client_visible;
  if not found then raise exception 'That item isn’t available.' using errcode = '22023'; end if;
  p_body := btrim(coalesce(p_body, ''));
  if p_body = '' or char_length(p_body) > 4000 then raise exception 'Write a message (4,000 characters at most).' using errcode = '22023'; end if;
  insert into public.comments (tbl, entity_id, body, author_id, client_visible) values ('tickets', t.id, p_body, me, true) returning id into nid;
  -- an answer moves it along; a message on something finished opens it again
  if t.status = 'Waiting on client' then update public.tickets set status = 'In progress' where id = t.id;
  elsif t.status in ('Resolved', 'Closed') then update public.tickets set status = 'Open', resolved_at = null where id = t.id;
  else update public.tickets set updated_at = now() where id = t.id; end if;
  select full_name into who from public.profiles where id = me;
  perform public.portal_notify_team(cid, coalesce(who, 'The client') || ' replied on ' || t.title, left(p_body, 140), 'tickets', t.id, array[t.assignee_id]);
  return nid;
end $$;

-- record a file the client uploaded to their own folder (portal/<their company>/...)
create or replace function public.portal_attach(p_ticket uuid, p_path text, p_name text, p_size bigint, p_mime text)
returns uuid language plpgsql security definer set search_path = public as $$
declare cid uuid := public.portal_client(); me uuid := auth.uid(); nid uuid;
begin
  if cid is null then raise exception 'This page is for client accounts.' using errcode = '42501'; end if;
  if p_path not like 'portal/' || cid::text || '/%' or p_path like '%..%' then raise exception 'That file can’t be added here.' using errcode = '22023'; end if;
  if not exists (select 1 from storage.objects o where o.bucket_id = 'files' and o.name = p_path) then raise exception 'The upload didn’t finish. Try again.' using errcode = '22023'; end if;
  if p_ticket is not null and not exists (select 1 from public.tickets where id = p_ticket and client_id = cid and client_visible) then raise exception 'That item isn’t available.' using errcode = '22023'; end if;
  if coalesce(p_size, 0) > 52428800 then raise exception 'Files can be up to 50 MB.' using errcode = '22023'; end if;
  insert into public.files (tbl, entity_id, name, path, size, mime, uploaded_by, storage)
  values (case when p_ticket is null then 'clients' else 'tickets' end, coalesce(p_ticket, cid), left(coalesce(nullif(btrim(p_name), ''), 'file'), 200), p_path, coalesce(p_size, 0), left(coalesce(p_mime, ''), 120), me, 'supabase')
  returning id into nid;
  return nid;
end $$;

create or replace function public.portal_request_meeting(p_topic text, p_details text, p_slots timestamptz[])
returns uuid language plpgsql security definer set search_path = public as $$
declare cid uuid := public.portal_client(); me uuid := auth.uid(); nid uuid; who text; s timestamptz;
begin
  if cid is null then raise exception 'This page is for client accounts.' using errcode = '42501'; end if;
  p_topic := btrim(coalesce(p_topic, ''));
  if char_length(p_topic) not between 3 and 200 then raise exception 'Say what the meeting is about (3 to 200 characters).' using errcode = '22023'; end if;
  if char_length(coalesce(p_details, '')) > 4000 then raise exception 'The details are too long.' using errcode = '22023'; end if;
  if coalesce(array_length(p_slots, 1), 0) not between 1 and 3 then raise exception 'Suggest one to three times.' using errcode = '22023'; end if;
  foreach s in array p_slots loop
    if s < now() + interval '30 minutes' or s > now() + interval '120 days' then raise exception 'Pick times from 30 minutes from now up to four months ahead.' using errcode = '22023'; end if;
  end loop;
  if (select count(*) from public.meeting_requests where client_id = cid and status = 'Requested') >= 10 then
    raise exception 'There are already 10 open requests. Wait for an answer, or cancel one.' using errcode = '22023'; end if;
  insert into public.meeting_requests (client_id, requested_by, topic, details, slots) values (cid, me, p_topic, coalesce(p_details, ''), p_slots) returning id into nid;
  select full_name into who from public.profiles where id = me;
  perform public.portal_notify_team(cid, coalesce(who, 'A client') || ' (' || (select name from public.clients where id = cid) || ') asked for a meeting: ' || p_topic,
    'Open the client to confirm a time.', 'clients', cid);
  return nid;
end $$;

create or replace function public.portal_cancel_meeting_request(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare cid uuid := public.portal_client(); r record;
begin
  if cid is null then raise exception 'This page is for client accounts.' using errcode = '42501'; end if;
  select * into r from public.meeting_requests where id = p_id and client_id = cid and status = 'Requested';
  if not found then return; end if;
  update public.meeting_requests set status = 'Cancelled' where id = p_id;
  perform public.portal_notify_team(cid, 'Meeting request cancelled: ' || r.topic, '', 'clients', cid);
end $$;

do $x$ declare f text; begin
  foreach f in array array['portal_overview()', 'portal_ticket(uuid)', 'portal_new_ticket(text, text, text, text, uuid)', 'portal_reply(uuid, text)',
    'portal_attach(uuid, text, text, bigint, text)', 'portal_request_meeting(text, text, timestamptz[])', 'portal_cancel_meeting_request(uuid)'] loop
    execute 'revoke execute on function public.' || f || ' from public, anon';
    execute 'grant execute on function public.' || f || ' to authenticated';
  end loop;
end $x$;

-- ---------- files: each client reads and uploads only in its own folder ----------
drop policy if exists "portal files read" on storage.objects;
create policy "portal files read" on storage.objects for select to authenticated
  using (bucket_id = 'files' and public.portal_client() is not null and name like 'portal/' || public.portal_client()::text || '/%');
drop policy if exists "portal files upload" on storage.objects;
create policy "portal files upload" on storage.objects for insert to authenticated
  with check (bucket_id = 'files' and public.portal_client() is not null and name like 'portal/' || public.portal_client()::text || '/%');

-- check (read-only)
select (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'profiles' and column_name in ('client_id', 'portal_active')) as profile_columns,
       (select count(*) from pg_class where relname = 'meeting_requests') as requests_table,
       (select count(*) from pg_proc where proname like 'portal\_%') as portal_functions;
