-- =====================================================================
--  Tcipher Technologies Workspace: Supabase setup
--  Three verticals: Development, Sales, Marketing
--  + company-wide leave, attendance, meetings, announcements, documents.
--
--  Paste this whole file into Supabase > SQL Editor > New query > Run.
--  Use a NEW, empty Supabase project. Safe to run again.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. People, roles and company settings
-- ---------------------------------------------------------------------
create table if not exists public.roles (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  description text not null default '',
  permissions jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text not null default '',
  full_name text not null default '',
  title text not null default '',
  phone text not null default '',
  vertical text check (vertical in ('Development','Sales','Marketing')),
  role_id uuid references public.roles(id) on delete set null,
  is_admin boolean not null default false,
  is_active boolean not null default true,
  joined_on date,
  color text not null default '#5B2BA6',
  created_at timestamptz not null default now()
);

create table if not exists public.settings (
  id int primary key default 1 check (id = 1),
  data jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- 2. Permission helpers. Levels: 0 none, 1 view, 2 edit, 3 manage. Admin = 3.
-- ---------------------------------------------------------------------
create or replace function public.perm(m text) returns int
language sql stable security definer set search_path = public as $$
  select coalesce((
    select case when p.is_admin then 3 else
      case coalesce(r.permissions->>m, 'none')
        when 'manage' then 3 when 'edit' then 2 when 'view' then 1 else 0 end
    end
    from public.profiles p left join public.roles r on r.id = p.role_id
    where p.id = auth.uid() and p.is_active
  ), 0)
$$;

create or replace function public.is_active_user() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles where id = auth.uid() and is_active)
$$;

create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles where id = auth.uid() and is_active and is_admin)
$$;

create or replace function public.my_vertical() returns text
language sql stable security definer set search_path = public as $$
  select vertical from public.profiles where id = auth.uid()
$$;

create or replace function public.table_module(tbl text) returns text
language sql immutable as $$
  select case tbl
    -- Development
    when 'projects' then 'projects' when 'sprints' then 'projects'
    when 'tasks' then 'tasks' when 'releases' then 'releases'
    when 'tickets' then 'support'
    -- Sales
    when 'clients' then 'clients' when 'contacts' then 'clients'
    when 'deals' then 'sales' when 'activities' then 'sales'
    when 'proposals' then 'sales' when 'targets' then 'sales'
    -- Shared between Marketing and Sales
    when 'leads' then 'leads'
    -- Marketing
    when 'campaigns' then 'marketing' when 'content' then 'marketing'
    when 'seo_keywords' then 'marketing' when 'social_stats' then 'marketing'
    -- Company
    when 'meetings' then 'meetings' when 'leave_requests' then 'leave'
    when 'attendance' then 'attendance' when 'announcements' then 'announcements'
    when 'documents' then 'documents'
    else 'none' end
$$;

-- ---------------------------------------------------------------------
-- 3. Sales: clients, contacts, deals, activities, proposals, targets
-- ---------------------------------------------------------------------
create table if not exists public.clients (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  industry text not null default '',
  contact_name text not null default '',
  email text not null default '',
  phone text not null default '',
  website text not null default '',
  city text not null default '',
  country text not null default 'India',
  tax_id text not null default '',
  status text not null default 'Active',
  owner_id uuid references public.profiles(id) on delete set null,
  notes text not null default '',
  created_by uuid default auth.uid() references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.contacts (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  client_id uuid references public.clients(id) on delete set null,
  title text not null default '',
  email text not null default '',
  phone text not null default '',
  linkedin text not null default '',
  is_primary boolean not null default false,
  owner_id uuid references public.profiles(id) on delete set null,
  notes text not null default '',
  created_by uuid default auth.uid() references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.deals (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  client_id uuid references public.clients(id) on delete set null,
  contact_id uuid references public.contacts(id) on delete set null,
  company text not null default '',
  contact_name text not null default '',
  email text not null default '',
  phone text not null default '',
  service text not null default '',
  value numeric,
  stage text not null default 'Lead',
  source text not null default '',
  probability int,
  owner_id uuid references public.profiles(id) on delete set null,
  expected_close date,
  next_followup date,
  lost_reason text not null default '',
  notes text not null default '',
  closed_at timestamptz,
  created_by uuid default auth.uid() references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.proposals (
  id uuid primary key default gen_random_uuid(),
  number text not null,
  title text not null default '',
  deal_id uuid references public.deals(id) on delete set null,
  client_id uuid references public.clients(id) on delete set null,
  amount numeric,
  status text not null default 'Draft',
  sent_on date,
  valid_until date,
  owner_id uuid references public.profiles(id) on delete set null,
  notes text not null default '',
  created_by uuid default auth.uid() references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.targets (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  month date not null,
  target_amount numeric,
  target_deals int,
  notes text not null default '',
  created_by uuid default auth.uid() references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, month)
);

-- ---------------------------------------------------------------------
-- 4. Marketing: campaigns, leads, content, SEO, social
-- ---------------------------------------------------------------------
create table if not exists public.campaigns (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  channel text not null default '',
  objective text not null default '',
  status text not null default 'Planned',
  start_date date,
  end_date date,
  budget numeric,
  spent numeric,
  leads int,
  conversions int,
  owner_id uuid references public.profiles(id) on delete set null,
  notes text not null default '',
  created_by uuid default auth.uid() references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.leads (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  company text not null default '',
  email text not null default '',
  phone text not null default '',
  source text not null default 'Website',
  campaign_id uuid references public.campaigns(id) on delete set null,
  service text not null default '',
  budget numeric,
  status text not null default 'New',
  owner_id uuid references public.profiles(id) on delete set null,
  sales_owner_id uuid references public.profiles(id) on delete set null,
  deal_id uuid references public.deals(id) on delete set null,
  handed_over_at timestamptz,
  notes text not null default '',
  created_by uuid default auth.uid() references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table public.deals add column if not exists lead_id uuid references public.leads(id) on delete set null;

create table if not exists public.activities (
  id uuid primary key default gen_random_uuid(),
  kind text not null default 'Call',
  subject text not null,
  activity_date date not null default current_date,
  deal_id uuid references public.deals(id) on delete set null,
  client_id uuid references public.clients(id) on delete set null,
  contact_id uuid references public.contacts(id) on delete set null,
  lead_id uuid references public.leads(id) on delete set null,
  owner_id uuid default auth.uid() references public.profiles(id) on delete set null,
  outcome text not null default '',
  next_step text not null default '',
  next_step_date date,
  created_by uuid default auth.uid() references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.content (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  channel text not null default 'LinkedIn',
  format text not null default 'Post',
  status text not null default 'Idea',
  publish_date date,
  owner_id uuid references public.profiles(id) on delete set null,
  campaign_id uuid references public.campaigns(id) on delete set null,
  link text not null default '',
  notes text not null default '',
  created_by uuid default auth.uid() references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.seo_keywords (
  id uuid primary key default gen_random_uuid(),
  keyword text not null,
  target_url text not null default '',
  position int,
  previous_position int,
  search_volume int,
  status text not null default 'Tracking',
  owner_id uuid references public.profiles(id) on delete set null,
  notes text not null default '',
  created_by uuid default auth.uid() references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.social_stats (
  id uuid primary key default gen_random_uuid(),
  channel text not null,
  month date not null,
  followers int,
  posts int,
  reach int,
  engagement int,
  clicks int,
  leads int,
  notes text not null default '',
  created_by uuid default auth.uid() references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (channel, month)
);

-- ---------------------------------------------------------------------
-- 5. Tasks (all verticals) and Development: projects, sprints, releases, tickets
-- ---------------------------------------------------------------------
create table if not exists public.projects (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  code text not null default '',
  client_id uuid references public.clients(id) on delete set null,
  status text not null default 'Planning',
  priority text not null default 'Medium',
  manager_id uuid references public.profiles(id) on delete set null,
  members uuid[] not null default '{}',
  start_date date,
  end_date date,
  budget numeric,
  tech_stack text not null default '',
  repo_url text not null default '',
  description text not null default '',
  created_by uuid default auth.uid() references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.sprints (
  id uuid primary key default gen_random_uuid(),
  project_id uuid references public.projects(id) on delete cascade,
  name text not null,
  status text not null default 'Planned',
  start_date date,
  end_date date,
  goal text not null default '',
  created_by uuid default auth.uid() references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.tasks (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  description text not null default '',
  project_id uuid references public.projects(id) on delete set null,
  sprint_id uuid references public.sprints(id) on delete set null,
  vertical text not null default 'Development' check (vertical in ('Development','Sales','Marketing')),
  type text not null default 'Feature',
  priority text not null default 'Medium',
  status text not null default 'To do',
  assignee_id uuid references public.profiles(id) on delete set null,
  collaborators uuid[] not null default '{}',
  reviewer_id uuid references public.profiles(id) on delete set null,
  due_date date,
  estimate_hours numeric,
  story_points int,
  severity text not null default '',
  environment text not null default '',
  steps text not null default '',
  blocked boolean not null default false,
  blocked_reason text not null default '',
  completed_at timestamptz,
  created_by uuid default auth.uid() references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.releases (
  id uuid primary key default gen_random_uuid(),
  version text not null,
  name text not null default '',
  project_id uuid references public.projects(id) on delete set null,
  status text not null default 'Planned',
  environment text not null default 'Production',
  release_date date,
  owner_id uuid references public.profiles(id) on delete set null,
  qa_signoff_id uuid references public.profiles(id) on delete set null,
  notes text not null default '',
  created_by uuid default auth.uid() references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.tickets (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  description text not null default '',
  client_id uuid references public.clients(id) on delete set null,
  project_id uuid references public.projects(id) on delete set null,
  priority text not null default 'Medium',
  status text not null default 'Open',
  channel text not null default 'Email',
  assignee_id uuid references public.profiles(id) on delete set null,
  due_date date,
  resolved_at timestamptz,
  created_by uuid default auth.uid() references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);



-- ---------------------------------------------------------------------
-- 6. Company-wide: meetings, leave, attendance, announcements, documents
-- ---------------------------------------------------------------------
create table if not exists public.meetings (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  meeting_date date not null default current_date,
  start_time time,
  duration_min int default 30,
  kind text not null default 'Internal',
  attendees uuid[] not null default '{}',
  project_id uuid references public.projects(id) on delete set null,
  client_id uuid references public.clients(id) on delete set null,
  link text not null default '',
  agenda text not null default '',
  notes text not null default '',
  action_items text not null default '',
  created_by uuid default auth.uid() references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.leave_requests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  type text not null default 'Paid leave',
  start_date date not null,
  end_date date not null,
  half_day boolean not null default false,
  reason text not null default '',
  status text not null default 'Pending',
  reviewed_by uuid references public.profiles(id) on delete set null,
  review_note text not null default '',
  created_by uuid default auth.uid() references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.attendance (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  day date not null default current_date,
  check_in timestamptz,
  check_out timestamptz,
  mode text not null default 'Office',
  note text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, day)
);

create table if not exists public.announcements (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  body text not null default '',
  pinned boolean not null default false,
  created_by uuid default auth.uid() references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.documents (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  category text not null default 'Other',
  vertical text not null default 'Company',
  description text not null default '',
  created_by uuid default auth.uid() references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- 7. Shared: comments, files, notifications, activity log
-- ---------------------------------------------------------------------
create table if not exists public.comments (
  id uuid primary key default gen_random_uuid(),
  tbl text not null,
  entity_id uuid not null,
  body text not null,
  author_id uuid default auth.uid() references public.profiles(id) on delete set null,
  created_at timestamptz not null default now()
);
create index if not exists comments_entity on public.comments (tbl, entity_id);

create table if not exists public.files (
  id uuid primary key default gen_random_uuid(),
  tbl text not null,
  entity_id uuid not null,
  name text not null,
  path text not null unique,
  size bigint not null default 0,
  mime text not null default '',
  uploaded_by uuid default auth.uid() references public.profiles(id) on delete set null,
  created_at timestamptz not null default now()
);
create index if not exists files_entity on public.files (tbl, entity_id);

create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  title text not null,
  body text not null default '',
  tbl text not null default '',
  entity_id uuid,
  is_read boolean not null default false,
  created_by uuid default auth.uid() references public.profiles(id) on delete set null,
  created_at timestamptz not null default now()
);
create index if not exists notifications_user on public.notifications (user_id, created_at desc);

create table if not exists public.activity_log (
  id bigint generated always as identity primary key,
  actor_id uuid references public.profiles(id) on delete set null,
  tbl text not null,
  action text not null,
  entity_id uuid,
  summary text not null default '',
  at timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- 8. Can the current person see a record? (follows that table's rules)
-- ---------------------------------------------------------------------
create or replace function public.can_see(tbl text, rid uuid) returns boolean
language plpgsql stable security invoker set search_path = public as $$
declare ok boolean;
begin
  if tbl not in ('projects','sprints','tasks','releases','tickets','clients','contacts','deals','activities',
                 'proposals','leads','campaigns','content','seo_keywords','meetings','leave_requests',
                 'announcements','documents') then
    return false;
  end if;
  execute format('select exists (select 1 from public.%I where id = $1)', tbl) into ok using rid;
  return coalesce(ok, false);
end $$;

-- ---------------------------------------------------------------------
-- 9. Triggers
-- ---------------------------------------------------------------------
create or replace function public.set_updated_at() returns trigger
language plpgsql as $$ begin new.updated_at := now(); return new; end $$;

create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
declare first_user boolean; emp uuid;
begin
  select not exists (select 1 from public.profiles) into first_user;
  select id into emp from public.roles where name = 'Employee' limit 1;
  insert into public.profiles (id, email, full_name, is_admin, role_id, joined_on)
  values (new.id, coalesce(new.email, ''),
          coalesce(nullif(new.raw_user_meta_data->>'full_name', ''), split_part(coalesce(new.email, ''), '@', 1)),
          first_user, emp, current_date)
  on conflict (id) do nothing;
  return new;
end $$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

-- Only admins can change someone's role, vertical, admin flag or active status.
create or replace function public.protect_profile() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is not null and not public.is_admin() then
    new.is_admin := old.is_admin;
    new.is_active := old.is_active;
    new.role_id := old.role_id;
    new.vertical := old.vertical;
    new.email := old.email;
    new.joined_on := old.joined_on;
  end if;
  return new;
end $$;
drop trigger if exists protect_profile on public.profiles;
create trigger protect_profile before update on public.profiles
  for each row execute function public.protect_profile();

create or replace function public.log_activity() returns trigger
language plpgsql security definer set search_path = public as $$
declare r jsonb; label text;
begin
  r := case when tg_op = 'DELETE' then to_jsonb(old) else to_jsonb(new) end;
  label := coalesce(r->>'title', r->>'name', r->>'subject', r->>'keyword', r->>'number', r->>'version', r->>'type', '');
  insert into public.activity_log (actor_id, tbl, action, entity_id, summary)
  values (auth.uid(), tg_table_name, lower(tg_op), nullif(r->>'id', '')::uuid, left(label, 200));
  return null;
end $$;

create or replace function public.cleanup_children() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  delete from public.comments where tbl = tg_table_name and entity_id = old.id;
  delete from public.files where tbl = tg_table_name and entity_id = old.id;
  return old;
end $$;

do $$
declare t text;
begin
  foreach t in array array['clients','contacts','deals','activities','proposals','targets','leads','campaigns','content',
    'seo_keywords','social_stats','projects','sprints','tasks','releases','tickets','meetings',
    'leave_requests','attendance','announcements','documents']
  loop
    execute format('drop trigger if exists set_updated_at on public.%I', t);
    execute format('create trigger set_updated_at before update on public.%I for each row execute function public.set_updated_at()', t);
  end loop;

  foreach t in array array['clients','contacts','deals','activities','proposals','targets','leads','campaigns','content',
    'seo_keywords','projects','sprints','tasks','releases','tickets','meetings','leave_requests','announcements','documents']
  loop
    execute format('drop trigger if exists log_activity on public.%I', t);
    execute format('create trigger log_activity after insert or update or delete on public.%I for each row execute function public.log_activity()', t);
    execute format('drop trigger if exists cleanup_children on public.%I', t);
    execute format('create trigger cleanup_children after delete on public.%I for each row execute function public.cleanup_children()', t);
  end loop;
end $$;

-- ---------------------------------------------------------------------
-- 10. Security rules (Row Level Security)
-- ---------------------------------------------------------------------
do $$
declare t text;
begin
  foreach t in array array['roles','profiles','settings','clients','contacts','deals','activities','proposals','targets',
    'leads','campaigns','content','seo_keywords','social_stats','projects','sprints','tasks','releases','tickets',
    'meetings','leave_requests','attendance','announcements','documents','comments','files',
    'notifications','activity_log']
  loop
    execute format('alter table public.%I enable row level security', t);
  end loop;
end $$;

do $$
declare p record;
begin
  for p in select policyname, tablename from pg_policies where schemaname = 'public' and policyname like 'ws_%'
  loop
    execute format('drop policy %I on public.%I', p.policyname, p.tablename);
  end loop;
end $$;

-- Reference data: everyone signed in reads, admins change.
do $$
declare t text;
begin
  foreach t in array array['roles','settings']
  loop
    execute format('create policy ws_read on public.%I for select to authenticated using (public.is_active_user())', t);
    execute format('create policy ws_write on public.%I for all to authenticated using (public.is_admin()) with check (public.is_admin())', t);
  end loop;
end $$;

create policy ws_read on public.profiles for select to authenticated
  using (id = auth.uid() or public.is_active_user());
create policy ws_update on public.profiles for update to authenticated
  using (id = auth.uid() or public.is_admin()) with check (id = auth.uid() or public.is_admin());

-- Standard vertical modules: view / edit / manage by role.
do $$
declare t text;
begin
  foreach t in array array['clients','contacts','proposals','campaigns','content','seo_keywords','social_stats',
    'sprints','releases','tickets']
  loop
    execute format('create policy ws_select on public.%I for select to authenticated using (public.perm(public.table_module(%L)) >= 1)', t, t);
    execute format('create policy ws_insert on public.%I for insert to authenticated with check (public.perm(public.table_module(%L)) >= 2)', t, t);
    execute format('create policy ws_update on public.%I for update to authenticated using (public.perm(public.table_module(%L)) >= 2) with check (public.perm(public.table_module(%L)) >= 2)', t, t, t);
    execute format('create policy ws_delete on public.%I for delete to authenticated using (public.perm(public.table_module(%L)) >= 3)', t, t);
  end loop;
end $$;

-- Owned records: the owner can always see and update their own.
do $$
declare t text;
begin
  foreach t in array array['deals','activities','leads']
  loop
    execute format('create policy ws_select on public.%I for select to authenticated using (public.perm(public.table_module(%L)) >= 1 or (public.is_active_user() and owner_id = auth.uid()))', t, t);
    execute format('create policy ws_insert on public.%I for insert to authenticated with check (public.perm(public.table_module(%L)) >= 2)', t, t);
    execute format('create policy ws_update on public.%I for update to authenticated using (public.perm(public.table_module(%L)) >= 2 or (public.is_active_user() and owner_id = auth.uid())) with check (public.perm(public.table_module(%L)) >= 2 or (public.is_active_user() and owner_id = auth.uid()))', t, t, t);
    execute format('create policy ws_delete on public.%I for delete to authenticated using (public.perm(public.table_module(%L)) >= 3)', t, t);
  end loop;
end $$;

-- Documents: company-wide ones for everyone with access; vertical ones only for that vertical.
create policy ws_select on public.documents for select to authenticated
  using (public.perm('documents') >= 1 and (vertical = 'Company' or vertical = public.my_vertical() or public.is_admin()));
create policy ws_insert on public.documents for insert to authenticated
  with check (public.perm('documents') >= 2 and (vertical = 'Company' or vertical = public.my_vertical() or public.is_admin()));
create policy ws_update on public.documents for update to authenticated
  using (public.perm('documents') >= 2 and (vertical = 'Company' or vertical = public.my_vertical() or public.is_admin()))
  with check (public.perm('documents') >= 2 and (vertical = 'Company' or vertical = public.my_vertical() or public.is_admin()));
create policy ws_delete on public.documents for delete to authenticated
  using (public.perm('documents') >= 3 and (vertical = 'Company' or vertical = public.my_vertical() or public.is_admin()));

-- Projects: members and the manager always see their project.
create policy ws_select on public.projects for select to authenticated
  using (public.perm('projects') >= 1 or (public.is_active_user() and (manager_id = auth.uid() or auth.uid() = any(members))));
create policy ws_insert on public.projects for insert to authenticated with check (public.perm('projects') >= 2);
create policy ws_update on public.projects for update to authenticated
  using (public.perm('projects') >= 2 or (public.is_active_user() and manager_id = auth.uid()))
  with check (public.perm('projects') >= 2 or (public.is_active_user() and manager_id = auth.uid()));
create policy ws_delete on public.projects for delete to authenticated using (public.perm('projects') >= 3);

-- Tasks: each vertical sees its own; anyone on a task (owner, collaborator, reviewer, creator) can see and update it.
create policy ws_select on public.tasks for select to authenticated
  using (public.is_admin()
    or (public.is_active_user() and (auth.uid() in (assignee_id, reviewer_id, created_by) or auth.uid() = any(collaborators)))
    or (public.perm('tasks') >= 1 and vertical = public.my_vertical()));
create policy ws_insert on public.tasks for insert to authenticated
  with check (public.is_admin()
    or (public.is_active_user() and assignee_id = auth.uid())
    or (public.perm('tasks') >= 2 and vertical = public.my_vertical()));
create policy ws_update on public.tasks for update to authenticated
  using (public.is_admin()
    or (public.is_active_user() and (auth.uid() in (assignee_id, reviewer_id, created_by) or auth.uid() = any(collaborators)))
    or (public.perm('tasks') >= 2 and vertical = public.my_vertical()))
  with check (public.is_admin()
    or (public.is_active_user() and (auth.uid() in (assignee_id, reviewer_id, created_by) or auth.uid() = any(collaborators)))
    or (public.perm('tasks') >= 2 and vertical = public.my_vertical()));
create policy ws_delete on public.tasks for delete to authenticated
  using (public.is_admin()
    or (public.is_active_user() and created_by = auth.uid())
    or (public.perm('tasks') >= 3 and vertical = public.my_vertical()));

-- Meetings: attendees and the organiser always see them; anyone can schedule one.
create policy ws_select on public.meetings for select to authenticated
  using (public.perm('meetings') >= 1 or (public.is_active_user() and (auth.uid() = any(attendees) or created_by = auth.uid())));
create policy ws_insert on public.meetings for insert to authenticated with check (public.is_active_user());
create policy ws_update on public.meetings for update to authenticated
  using (public.perm('meetings') >= 2 or (public.is_active_user() and created_by = auth.uid()))
  with check (public.perm('meetings') >= 2 or (public.is_active_user() and created_by = auth.uid()));
create policy ws_delete on public.meetings for delete to authenticated
  using (public.perm('meetings') >= 3 or (public.is_active_user() and created_by = auth.uid()));

-- Leave: everyone manages their own while pending; approvers see all.
create policy ws_select on public.leave_requests for select to authenticated
  using (public.perm('leave') >= 1 or (public.is_active_user() and user_id = auth.uid()));
create policy ws_insert on public.leave_requests for insert to authenticated
  with check (public.perm('leave') >= 2 or (public.is_active_user() and user_id = auth.uid() and status = 'Pending'));
create policy ws_update on public.leave_requests for update to authenticated
  using (public.perm('leave') >= 2 or (public.is_active_user() and user_id = auth.uid() and status = 'Pending'))
  with check (public.perm('leave') >= 2 or (public.is_active_user() and user_id = auth.uid() and status = 'Pending'));
create policy ws_delete on public.leave_requests for delete to authenticated
  using (public.perm('leave') >= 3 or (public.is_active_user() and user_id = auth.uid() and status = 'Pending'));

-- Attendance: your own always; managers see everyone's.
do $$
declare t text;
begin
  foreach t in array array['attendance']
  loop
    execute format('create policy ws_select on public.%I for select to authenticated using (public.perm(public.table_module(%L)) >= 1 or (public.is_active_user() and user_id = auth.uid()))', t, t);
    execute format('create policy ws_insert on public.%I for insert to authenticated with check (public.perm(public.table_module(%L)) >= 2 or (public.is_active_user() and user_id = auth.uid()))', t, t);
    execute format('create policy ws_update on public.%I for update to authenticated using (public.perm(public.table_module(%L)) >= 2 or (public.is_active_user() and user_id = auth.uid())) with check (public.perm(public.table_module(%L)) >= 2 or (public.is_active_user() and user_id = auth.uid()))', t, t, t);
    execute format('create policy ws_delete on public.%I for delete to authenticated using (public.perm(public.table_module(%L)) >= 3 or (public.is_active_user() and user_id = auth.uid()))', t, t);
  end loop;
end $$;

-- Sales targets: sales heads set them; everyone in sales sees them; each person sees their own.
create policy ws_select on public.targets for select to authenticated
  using (public.perm('sales') >= 1 or (public.is_active_user() and user_id = auth.uid()));
create policy ws_insert on public.targets for insert to authenticated with check (public.perm('sales') >= 3);
create policy ws_update on public.targets for update to authenticated using (public.perm('sales') >= 3) with check (public.perm('sales') >= 3);
create policy ws_delete on public.targets for delete to authenticated using (public.perm('sales') >= 3);

-- Announcements: everyone reads; posting needs edit rights.
create policy ws_select on public.announcements for select to authenticated using (public.is_active_user());
create policy ws_insert on public.announcements for insert to authenticated with check (public.perm('announcements') >= 2);
create policy ws_update on public.announcements for update to authenticated
  using (public.perm('announcements') >= 2) with check (public.perm('announcements') >= 2);
create policy ws_delete on public.announcements for delete to authenticated using (public.perm('announcements') >= 3);

-- Comments and files follow the record they belong to.
create policy ws_select on public.comments for select to authenticated using (public.is_active_user() and public.can_see(tbl, entity_id));
create policy ws_insert on public.comments for insert to authenticated
  with check (public.is_active_user() and author_id = auth.uid() and public.can_see(tbl, entity_id));
create policy ws_delete on public.comments for delete to authenticated using (author_id = auth.uid() or public.is_admin());

create policy ws_select on public.files for select to authenticated using (public.is_active_user() and public.can_see(tbl, entity_id));
create policy ws_insert on public.files for insert to authenticated
  with check (public.is_active_user() and uploaded_by = auth.uid() and public.can_see(tbl, entity_id));
create policy ws_delete on public.files for delete to authenticated
  using (uploaded_by = auth.uid() or public.perm(public.table_module(tbl)) >= 3);

create policy ws_select on public.notifications for select to authenticated using (user_id = auth.uid());
create policy ws_insert on public.notifications for insert to authenticated with check (public.is_active_user());
create policy ws_update on public.notifications for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy ws_delete on public.notifications for delete to authenticated using (user_id = auth.uid());

create policy ws_select on public.activity_log for select to authenticated using (public.is_admin());

-- ---------------------------------------------------------------------
-- 11. Private file storage
-- ---------------------------------------------------------------------
insert into storage.buckets (id, name, public)
values ('files', 'files', false)
on conflict (id) do nothing;

drop policy if exists "ws files read" on storage.objects;
drop policy if exists "ws files upload" on storage.objects;
drop policy if exists "ws files delete" on storage.objects;
create policy "ws files read" on storage.objects for select to authenticated
  using (bucket_id = 'files' and exists (select 1 from public.files f where f.path = storage.objects.name));
create policy "ws files upload" on storage.objects for insert to authenticated
  with check (bucket_id = 'files' and public.is_active_user());
create policy "ws files delete" on storage.objects for delete to authenticated
  using (bucket_id = 'files' and exists (
    select 1 from public.files f where f.path = storage.objects.name
      and (f.uploaded_by = auth.uid() or public.perm(public.table_module(f.tbl)) >= 3)));

-- ---------------------------------------------------------------------
-- 12. Live updates
-- ---------------------------------------------------------------------
do $$
declare t text;
begin
  foreach t in array array['roles','profiles','settings','clients','contacts','deals','activities','proposals','targets',
    'leads','campaigns','content','seo_keywords','social_stats','projects','sprints','tasks','releases','tickets',
    'meetings','leave_requests','attendance','announcements','documents','comments','files','notifications']
  loop
    begin
      execute format('alter publication supabase_realtime add table public.%I', t);
    exception when duplicate_object then null;
    end;
  end loop;
end $$;

-- ---------------------------------------------------------------------
-- 13. Starting data: roles and settings
--     Each role only reaches its own vertical. Leads are shared by Marketing and Sales.
-- ---------------------------------------------------------------------
insert into public.roles (name, description, permissions) values
  ('Development head', 'Runs the Development vertical: projects, sprints, releases, support and the dev team’s tasks.',
   '{"projects":"manage","tasks":"manage","releases":"manage","support":"manage","clients":"view","meetings":"edit","announcements":"view","documents":"edit"}'),
  ('Developer', 'Development vertical: builds features and fixes bugs.',
   '{"projects":"view","tasks":"edit","releases":"view","support":"edit","meetings":"edit","announcements":"view","documents":"view"}'),
  ('QA', 'Development vertical: tests work, files bugs and signs off releases.',
   '{"projects":"view","tasks":"edit","releases":"edit","support":"edit","meetings":"edit","announcements":"view","documents":"view"}'),
  ('Sales head', 'Runs the Sales vertical: pipeline, clients, proposals and targets.',
   '{"tasks":"manage","clients":"manage","sales":"manage","leads":"manage","meetings":"edit","announcements":"view","documents":"edit"}'),
  ('Sales executive', 'Sales vertical: works leads and deals, logs calls and sends proposals.',
   '{"tasks":"edit","clients":"edit","sales":"edit","leads":"edit","meetings":"edit","announcements":"view","documents":"view"}'),
  ('Marketing head', 'Runs the Marketing vertical: campaigns, content, SEO, social and leads.',
   '{"tasks":"manage","marketing":"manage","leads":"manage","meetings":"edit","announcements":"view","documents":"edit"}'),
  ('Marketing executive', 'Marketing vertical: content, campaigns, SEO, social and lead capture.',
   '{"tasks":"edit","marketing":"edit","leads":"edit","meetings":"edit","announcements":"view","documents":"view"}'),
  ('Employee', 'Basic access: their own tasks, leave and attendance.',
   '{"announcements":"view","documents":"view"}')
on conflict (name) do nothing;

insert into public.settings (id, data) values (1, '{
  "company": "Tcipher Technologies",
  "currency": "INR",
  "working_days": [1,2,3,4,5],
  "leave_types": ["Paid leave","Sick leave","Work from home","Unpaid leave"],
  "annual_leave": 12,
  "counted_leave_types": ["Paid leave","Sick leave"],
  "holidays": [
    {"date": "2026-11-08", "name": "Diwali"},
    {"date": "2026-12-25", "name": "Christmas"},
    {"date": "2027-01-01", "name": "New Year’s Day"},
    {"date": "2027-01-26", "name": "Republic Day"}
  ]
}'::jsonb)
on conflict (id) do nothing;

-- Done. Next: create your own login in Authentication > Users.
-- The very first person created becomes the admin automatically.
