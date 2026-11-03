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
  mode text not null default 'Remote',
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
  "working_days": [1,2,3,4,5,6],
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


-- ---------------------------------------------------------------------
-- 14. Meetings: repeats, Google Calendar + Meet, and the join log
--     (safe to run on an existing workspace: only adds what's missing)
-- ---------------------------------------------------------------------
alter table public.meetings add column if not exists repeat text not null default 'Does not repeat';
alter table public.meetings add column if not exists google_event_id text;
alter table public.meetings add column if not exists google_owner uuid references public.profiles(id) on delete set null;
alter table public.meetings add column if not exists google_html_link text not null default '';
update public.meetings set kind = 'Morning scrum' where kind = 'Stand-up';

-- Tcipher is remote-first: new attendance defaults to Remote.
alter table public.attendance alter column mode set default 'Remote';

-- Every time someone joins a meeting: from the workspace's Join button, or imported from Google Meet.
create table if not exists public.meeting_joins (
  id uuid primary key default gen_random_uuid(),
  meeting_id uuid not null references public.meetings(id) on delete cascade,
  user_id uuid references public.profiles(id) on delete set null,
  display_name text not null default '',
  joined_on date not null default current_date,
  joined_at timestamptz not null default now(),
  left_at timestamptz,
  source text not null default 'Workspace',
  external_id text unique,
  created_by uuid default auth.uid() references public.profiles(id) on delete set null,
  created_at timestamptz not null default now()
);
create index if not exists meeting_joins_meeting on public.meeting_joins (meeting_id, joined_on);
create index if not exists meeting_joins_user on public.meeting_joins (user_id, joined_on);
alter table public.meeting_joins enable row level security;

-- See joins for meetings you can see; log your own joins; the organiser and admins can import everyone's.
drop policy if exists ws_select on public.meeting_joins;
drop policy if exists ws_insert on public.meeting_joins;
drop policy if exists ws_update on public.meeting_joins;
drop policy if exists ws_delete on public.meeting_joins;
create policy ws_select on public.meeting_joins for select to authenticated
  using (public.is_active_user() and (user_id = auth.uid() or public.perm('meetings') >= 1 or public.can_see('meetings', meeting_id)));
create policy ws_insert on public.meeting_joins for insert to authenticated
  with check (public.is_active_user() and (user_id = auth.uid() or public.is_admin()
    or exists (select 1 from public.meetings m where m.id = meeting_id and (m.created_by = auth.uid() or m.google_owner = auth.uid()))));
create policy ws_update on public.meeting_joins for update to authenticated
  using (public.is_active_user() and (user_id = auth.uid() or public.is_admin()
    or exists (select 1 from public.meetings m where m.id = meeting_id and (m.created_by = auth.uid() or m.google_owner = auth.uid()))));
create policy ws_delete on public.meeting_joins for delete to authenticated using (public.is_admin());

do $$
begin
  begin
    alter publication supabase_realtime add table public.meeting_joins;
  exception when duplicate_object then null;
  end;
end $$;


-- ---------------------------------------------------------------------
-- 16. Google Calendar sync (server-side, automatic)
--     Tokens are stored where only the server function can read them.
-- ---------------------------------------------------------------------
create or replace function public.my_email() returns text
language sql stable security definer set search_path = public as $$
  select lower(email) from public.profiles where id = auth.uid()
$$;

create table if not exists public.google_tokens (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  refresh_token text not null,
  scopes text not null default '',
  updated_at timestamptz not null default now()
);
alter table public.google_tokens enable row level security;   -- no policies: browsers can never read tokens

create table if not exists public.google_links (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  google_email text not null default '',
  connected_at timestamptz not null default now(),
  last_sync_at timestamptz,
  last_error text not null default ''
);
alter table public.google_links enable row level security;
drop policy if exists ws_select on public.google_links;
create policy ws_select on public.google_links for select to authenticated using (user_id = auth.uid() or public.is_admin());

create table if not exists public.calendar_events (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  google_event_id text not null,
  ical_uid text not null default '',
  title text not null default '',
  starts_at timestamptz,
  ends_at timestamptz,
  all_day boolean not null default false,
  start_date date,
  end_date date,
  meet_link text not null default '',
  html_link text not null default '',
  location text not null default '',
  organizer_email text not null default '',
  attendee_emails text[] not null default '{}',
  updated_at timestamptz not null default now(),
  unique (user_id, google_event_id)
);
create index if not exists calendar_events_day on public.calendar_events (start_date);
alter table public.calendar_events enable row level security;
drop policy if exists ws_select on public.calendar_events;
-- you see your own Google events, and events from colleagues' calendars that you're invited to
create policy ws_select on public.calendar_events for select to authenticated
  using (public.is_active_user() and (user_id = auth.uid() or public.my_email() = any(attendee_emails) or public.is_admin()));

-- joins can also be for Google-only events (not created in the workspace)
alter table public.meeting_joins alter column meeting_id drop not null;
alter table public.meeting_joins add column if not exists event_uid text not null default '';
alter table public.meeting_joins add column if not exists title text not null default '';

do $$
declare t text;
begin
  foreach t in array array['calendar_events','google_links']
  loop
    begin
      execute format('alter publication supabase_realtime add table public.%I', t);
    exception when duplicate_object then null;
    end;
  end loop;
end $$;


-- ---------------------------------------------------------------------
-- 17. Dev tasks: IDs, tagging, checklists, links, dependencies, bug details, history
-- ---------------------------------------------------------------------
alter table public.tasks add column if not exists number bigint generated by default as identity;
create unique index if not exists tasks_number on public.tasks (number);
alter table public.tasks add column if not exists labels text[] not null default '{}';
alter table public.tasks add column if not exists component text not null default '';
alter table public.tasks add column if not exists checklist jsonb not null default '[]'::jsonb;
alter table public.tasks add column if not exists branch text not null default '';
alter table public.tasks add column if not exists pr_url text not null default '';
alter table public.tasks add column if not exists design_url text not null default '';
alter table public.tasks add column if not exists blocked_by uuid[] not null default '{}';
alter table public.tasks add column if not exists release_id uuid references public.releases(id) on delete set null;
alter table public.tasks add column if not exists start_date date;
alter table public.tasks add column if not exists expected_result text not null default '';
alter table public.tasks add column if not exists actual_result text not null default '';
alter table public.tasks add column if not exists build_version text not null default '';
alter table public.tasks add column if not exists device text not null default '';
alter table public.tasks add column if not exists reproducibility text not null default '';
alter table public.tasks add column if not exists mentions uuid[] not null default '{}';
alter table public.comments add column if not exists mentions uuid[] not null default '{}';

-- People tagged on a task can open it and comment, even from another vertical (they can't edit it).
drop trigger if exists track_task_changes on public.tasks;
drop function if exists public.track_task_changes();
drop trigger if exists comment_mentions_to_task on public.comments;
drop function if exists public.comment_mentions_to_task();
drop policy if exists ws_update on public.tasks;
create policy ws_update on public.tasks for update to authenticated
  using (public.is_admin()
    or (public.is_active_user() and (auth.uid() in (assignee_id, reviewer_id, created_by) or auth.uid() = any(collaborators)))
    or (public.perm('tasks') >= 2 and vertical = public.my_vertical()))
  with check (public.is_admin()
    or (public.is_active_user() and (auth.uid() in (assignee_id, reviewer_id, created_by) or auth.uid() = any(collaborators)))
    or (public.perm('tasks') >= 2 and vertical = public.my_vertical()));
drop policy if exists ws_select on public.tasks;
create policy ws_select on public.tasks for select to authenticated
  using (public.is_admin()
    or (public.is_active_user() and (auth.uid() in (assignee_id, reviewer_id, created_by) or auth.uid() = any(collaborators) or auth.uid() = any(mentions)))
    or (public.perm('tasks') >= 1 and vertical = public.my_vertical()));

-- Tagging someone in a task comment gives them access to the task.
create or replace function public.merge_comment_mentions() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.tbl = 'tasks' and cardinality(new.mentions) > 0 then
    update public.tasks t set mentions = array(select distinct x from unnest(t.mentions || new.mentions) as x)
    where t.id = new.entity_id;
  elsif new.tbl = 'notes' and cardinality(new.mentions) > 0 then
    update public.notes n set mentions = array(select distinct x from unnest(n.mentions || new.mentions) as x)
    where n.id = new.entity_id;
  end if;
  return new;
end $$;

-- Task history: who changed what, when (written automatically).
create table if not exists public.task_events (
  id bigint generated always as identity primary key,
  task_id uuid not null references public.tasks(id) on delete cascade,
  actor_id uuid references public.profiles(id) on delete set null,
  field text not null,
  old_value text not null default '',
  new_value text not null default '',
  at timestamptz not null default now()
);
create index if not exists task_events_task on public.task_events (task_id, at desc);
alter table public.task_events enable row level security;
drop policy if exists ws_select on public.task_events;
create policy ws_select on public.task_events for select to authenticated
  using (public.is_active_user() and exists (select 1 from public.tasks t where t.id = task_id));

create or replace function public.log_task_change() returns trigger
language plpgsql security definer set search_path = public as $$
declare f text; o jsonb; n jsonb;
begin
  if tg_op = 'INSERT' then
    insert into public.task_events (task_id, actor_id, field, new_value) values (new.id, auth.uid(), 'created', new.status);
    return null;
  end if;
  o := to_jsonb(old); n := to_jsonb(new);
  foreach f in array array['status','assignee_id','reviewer_id','priority','due_date','sprint_id','release_id','blocked','title','collaborators']
  loop
    if (o->f) is distinct from (n->f) then
      insert into public.task_events (task_id, actor_id, field, old_value, new_value)
      values (new.id, auth.uid(), f, coalesce(o->>f, ''), coalesce(n->>f, ''));
    end if;
  end loop;
  return null;
end $$;
drop trigger if exists log_task_change on public.tasks;
create trigger log_task_change after insert or update on public.tasks
  for each row execute function public.log_task_change();

-- ---------------------------------------------------------------------
-- 18. Notes: private by default; share with people, your vertical, or everyone
-- ---------------------------------------------------------------------
create table if not exists public.notes (
  id uuid primary key default gen_random_uuid(),
  title text not null default '',
  body text not null default '',
  owner_id uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  visibility text not null default 'Private' check (visibility in ('Private','People','Vertical','Company')),
  vertical text,
  shared_with uuid[] not null default '{}',
  mentions uuid[] not null default '{}',
  pinned boolean not null default false,
  task_id uuid references public.tasks(id) on delete set null,
  project_id uuid references public.projects(id) on delete set null,
  meeting_id uuid references public.meetings(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists notes_owner on public.notes (owner_id);
alter table public.notes enable row level security;
drop policy if exists ws_select on public.notes;
drop policy if exists ws_insert on public.notes;
drop policy if exists ws_update on public.notes;
drop policy if exists ws_delete on public.notes;
create policy ws_select on public.notes for select to authenticated
  using (public.is_active_user() and (owner_id = auth.uid()
    or visibility = 'Company'
    or (visibility = 'Vertical' and (vertical = public.my_vertical() or public.is_admin()))
    or (visibility = 'People' and auth.uid() = any(shared_with))
    or auth.uid() = any(mentions)));
create policy ws_insert on public.notes for insert to authenticated
  with check (public.is_active_user() and owner_id = auth.uid());
create policy ws_update on public.notes for update to authenticated
  using (owner_id = auth.uid()) with check (owner_id = auth.uid());
create policy ws_delete on public.notes for delete to authenticated
  using (owner_id = auth.uid());

drop trigger if exists set_updated_at on public.notes;
create trigger set_updated_at before update on public.notes for each row execute function public.set_updated_at();
drop trigger if exists cleanup_children on public.notes;
create trigger cleanup_children after delete on public.notes for each row execute function public.cleanup_children();

drop trigger if exists merge_comment_mentions on public.comments;
create trigger merge_comment_mentions after insert on public.comments
  for each row execute function public.merge_comment_mentions();

-- comments and files can now belong to notes too
create or replace function public.can_see(tbl text, rid uuid) returns boolean
language plpgsql stable security invoker set search_path = public as $$
declare ok boolean;
begin
  if tbl not in ('projects','sprints','tasks','releases','tickets','clients','contacts','deals','activities',
                 'proposals','leads','campaigns','content','seo_keywords','meetings','leave_requests',
                 'announcements','documents','notes') then
    return false;
  end if;
  execute format('select exists (select 1 from public.%I where id = $1)', tbl) into ok using rid;
  return coalesce(ok, false);
end $$;

do $$
declare t text;
begin
  foreach t in array array['notes']
  loop
    begin
      execute format('alter publication supabase_realtime add table public.%I', t);
    exception when duplicate_object then null;
    end;
  end loop;
end $$;


-- ---------------------------------------------------------------------
-- 19. Meetings on chosen days (e.g. Mon–Sat), and Saturday as a working day
-- ---------------------------------------------------------------------
alter table public.meetings add column if not exists repeat_days int[] not null default '{}';



-- ---------------------------------------------------------------------
-- 20. Task rules: handlers chosen in Admin panel › Task rules
--     Handlers edit everything; people on the task can update status and checklist;
--     the team creates and comments; nobody deletes (archive instead); history is permanent.
-- ---------------------------------------------------------------------
alter table public.tasks add column if not exists archived boolean not null default false;
alter table public.tasks add column if not exists archived_at timestamptz;
alter table public.tasks add column if not exists archived_by uuid references public.profiles(id) on delete set null;

-- Is the current person a task handler for this vertical? (set in settings.data.task_handlers)
create or replace function public.is_task_handler(v text) returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_admin() or exists (
    select 1 from public.settings s
    where s.id = 1 and coalesce(s.data->'task_handlers'->v, '[]'::jsonb) ? auth.uid()::text)
$$;
create or replace function public.task_workers_can_update() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select (data->>'owners_can_update_status')::boolean from public.settings where id = 1), true)
$$;

drop policy if exists ws_select on public.tasks;
drop policy if exists ws_insert on public.tasks;
drop policy if exists ws_update on public.tasks;
drop policy if exists ws_delete on public.tasks;
create policy ws_select on public.tasks for select to authenticated
  using (public.is_task_handler(vertical)
    or (public.is_active_user() and (auth.uid() in (assignee_id, reviewer_id, created_by) or auth.uid() = any(collaborators) or auth.uid() = any(mentions)))
    or (public.perm('tasks') >= 1 and vertical = public.my_vertical()));
-- anyone can create tasks in their own vertical (or for themselves); handlers in theirs
create policy ws_insert on public.tasks for insert to authenticated
  with check (public.is_task_handler(vertical)
    or (public.is_active_user() and (vertical = public.my_vertical() or assignee_id = auth.uid())));
create policy ws_update on public.tasks for update to authenticated
  using (public.is_task_handler(vertical)
    or (public.is_active_user() and (auth.uid() in (assignee_id, reviewer_id) or auth.uid() = any(collaborators))))
  with check (public.is_task_handler(vertical)
    or (public.is_active_user() and (auth.uid() in (assignee_id, reviewer_id) or auth.uid() = any(collaborators))));
-- no delete policy: tasks can't be deleted from the app (archive them instead)

-- People who aren't handlers may only change the "work" fields of tasks they're on.
create or replace function public.protect_task_fields() returns trigger
language plpgsql security definer set search_path = public as $$
declare work text[] := array['status','checklist','blocked','blocked_reason','branch','pr_url','completed_at','updated_at','mentions'];
begin
  if auth.uid() is null or public.is_task_handler(old.vertical) then return new; end if;
  if (to_jsonb(new) - work) is distinct from (to_jsonb(old) - work) then
    raise exception 'Only a task handler can change these details. You can update the status and checklist.' using errcode = '42501';
  end if;
  if not public.task_workers_can_update() then
    -- only reviewing stays open: the reviewer may approve or send back
    if auth.uid() = old.reviewer_id
       and (to_jsonb(new) - array['status','completed_at','blocked','updated_at','mentions']) is not distinct from (to_jsonb(old) - array['status','completed_at','blocked','updated_at','mentions']) then
      return new;
    end if;
    if (to_jsonb(new) - 'mentions' - 'updated_at') is distinct from (to_jsonb(old) - 'mentions' - 'updated_at') then
      raise exception 'Only a task handler can change tasks.' using errcode = '42501';
    end if;
  end if;
  return new;
end $$;
drop trigger if exists protect_task_fields on public.tasks;
create trigger protect_task_fields before update on public.tasks
  for each row execute function public.protect_task_fields();

-- Complete, permanent history: every field, comments and files.
create or replace function public.log_task_change() returns trigger
language plpgsql security definer set search_path = public as $$
declare f text; o jsonb; n jsonb;
begin
  if tg_op = 'INSERT' then
    insert into public.task_events (task_id, actor_id, field, new_value) values (new.id, auth.uid(), 'created', new.status);
    return null;
  end if;
  o := to_jsonb(old); n := to_jsonb(new);
  foreach f in array array['title','description','status','vertical','type','priority','assignee_id','reviewer_id','collaborators',
    'project_id','sprint_id','release_id','component','labels','start_date','due_date','estimate_hours','story_points',
    'severity','environment','reproducibility','build_version','device','steps','expected_result','actual_result',
    'branch','pr_url','design_url','blocked_by','blocked','blocked_reason','checklist','archived']
  loop
    if (o->f) is distinct from (n->f) then
      insert into public.task_events (task_id, actor_id, field, old_value, new_value)
      values (new.id, auth.uid(), f, coalesce(o->>f, ''), coalesce(n->>f, ''));
    end if;
  end loop;
  return null;
end $$;

create or replace function public.log_task_comment_or_file() returns trigger
language plpgsql security definer set search_path = public as $$
declare r record; label text;
begin
  if tg_op = 'DELETE' then r := old; else r := new; end if;
  if r.tbl <> 'tasks' or not exists (select 1 from public.tasks where id = r.entity_id) then return null; end if;
  if tg_table_name = 'comments' then
    label := case tg_op when 'INSERT' then 'comment_added' else 'comment_removed' end;
    insert into public.task_events (task_id, actor_id, field, new_value, old_value)
    values (r.entity_id, auth.uid(), label, case when tg_op = 'INSERT' then r.body else '' end, case when tg_op = 'DELETE' then r.body else '' end);
  else
    label := case tg_op when 'INSERT' then 'file_added' else 'file_removed' end;
    insert into public.task_events (task_id, actor_id, field, new_value) values (r.entity_id, auth.uid(), label, r.name);
  end if;
  return null;
end $$;
drop trigger if exists log_task_comment on public.comments;
create trigger log_task_comment after insert or delete on public.comments
  for each row execute function public.log_task_comment_or_file();
drop trigger if exists log_task_file on public.files;
create trigger log_task_file after insert or delete on public.files
  for each row execute function public.log_task_comment_or_file();

-- Comments on tasks can only be removed by an admin (and that's logged above).
drop policy if exists ws_delete on public.comments;
create policy ws_delete on public.comments for delete to authenticated
  using (public.is_admin() or (author_id = auth.uid() and tbl <> 'tasks'));

-- History can never be changed or removed from the app.
revoke update, delete on public.task_events from authenticated;

-- Changes to the handler list are recorded in the activity log.
create or replace function public.log_settings_change() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if (old.data->'task_handlers') is distinct from (new.data->'task_handlers')
     or (old.data->'owners_can_update_status') is distinct from (new.data->'owners_can_update_status') then
    insert into public.activity_log (actor_id, tbl, action, summary)
    values (auth.uid(), 'settings', 'update', 'Task rules changed');
  end if;
  return null;
end $$;
drop trigger if exists log_settings_change on public.settings;
create trigger log_settings_change after update on public.settings
  for each row execute function public.log_settings_change();

-- Start with nobody but admins as handlers, and people on a task allowed to update its status.
update public.settings
set data = data || jsonb_build_object(
  'task_handlers', coalesce(data->'task_handlers', '{"Development": [], "Sales": [], "Marketing": []}'::jsonb),
  'owners_can_update_status', coalesce(data->'owners_can_update_status', 'true'::jsonb))
where id = 1;


-- ---------------------------------------------------------------------
-- 21. Team calendar: everyone at Tcipher sees each other's synced Google events
--     (title, time, Meet link) and who has connected Google.
-- ---------------------------------------------------------------------
drop policy if exists ws_select on public.calendar_events;
create policy ws_select on public.calendar_events for select to authenticated
  using (public.is_active_user());
drop policy if exists ws_select on public.google_links;
create policy ws_select on public.google_links for select to authenticated
  using (public.is_active_user());


-- ---------------------------------------------------------------------
-- 22. CRM for Marketing and Sales (from the old marketing app):
--     lead numbers, lead type, priority, tags, address, zone, Instagram pipeline,
--     website form answers, call outcomes, lead/deal history, linked tasks
-- ---------------------------------------------------------------------
create sequence if not exists public.lead_number_seq;
alter table public.leads add column if not exists lead_number text;
alter table public.leads add column if not exists pipeline text not null default 'General';
alter table public.leads add column if not exists lead_type text not null default '';
alter table public.leads add column if not exists priority text not null default 'Medium';
alter table public.leads add column if not exists tags text[] not null default '{}';
alter table public.leads add column if not exists alt_phone text not null default '';
alter table public.leads add column if not exists address text not null default '';
alter table public.leads add column if not exists city text not null default '';
alter table public.leads add column if not exists state text not null default '';
alter table public.leads add column if not exists country text not null default 'India';
alter table public.leads add column if not exists pincode text not null default '';
alter table public.leads add column if not exists zone text not null default '';
alter table public.leads add column if not exists next_followup date;
alter table public.leads add column if not exists last_contacted_at timestamptz;
alter table public.leads add column if not exists lost_reason text not null default '';
alter table public.leads add column if not exists form_submissions jsonb not null default '[]'::jsonb;
create unique index if not exists leads_number on public.leads (lead_number);
create index if not exists leads_pipeline on public.leads (pipeline, status);

create or replace function public.set_lead_number() returns trigger
language plpgsql as $$
begin
  if new.lead_number is null or new.lead_number = '' then
    new.lead_number := 'LD-' || lpad(nextval('public.lead_number_seq')::text, 4, '0');
  end if;
  return new;
end $$;
drop trigger if exists set_lead_number on public.leads;
create trigger set_lead_number before insert on public.leads
  for each row execute function public.set_lead_number();
-- number any existing leads, oldest first
do $$
declare r record;
begin
  for r in select id from public.leads where lead_number is null order by created_at loop
    update public.leads set lead_number = 'LD-' || lpad(nextval('public.lead_number_seq')::text, 4, '0') where id = r.id;
  end loop;
end $$;

alter table public.deals add column if not exists lead_type text not null default '';
alter table public.deals add column if not exists priority text not null default 'Medium';
alter table public.deals add column if not exists tags text[] not null default '{}';
alter table public.deals add column if not exists city text not null default '';
alter table public.deals add column if not exists zone text not null default '';
alter table public.deals add column if not exists last_contacted_at timestamptz;
alter table public.clients add column if not exists zone text not null default '';
alter table public.clients add column if not exists state text not null default '';
alter table public.clients add column if not exists pincode text not null default '';

alter table public.activities add column if not exists outcome_type text not null default '';
alter table public.activities add column if not exists duration_min int;
alter table public.activities add column if not exists direction text not null default 'Outbound';

alter table public.tasks add column if not exists lead_id uuid references public.leads(id) on delete set null;
alter table public.tasks add column if not exists deal_id uuid references public.deals(id) on delete set null;

alter table public.comments add column if not exists kind text not null default '';

-- Logging an activity updates "last contacted" on its lead or deal.
create or replace function public.touch_last_contacted() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.lead_id is not null then update public.leads set last_contacted_at = greatest(coalesce(last_contacted_at, 'epoch'), now()) where id = new.lead_id; end if;
  if new.deal_id is not null then update public.deals set last_contacted_at = greatest(coalesce(last_contacted_at, 'epoch'), now()) where id = new.deal_id; end if;
  return null;
end $$;
drop trigger if exists touch_last_contacted on public.activities;
create trigger touch_last_contacted after insert on public.activities
  for each row execute function public.touch_last_contacted();

-- Permanent history for leads and deals (stage changes, owners, value, follow-ups).
create table if not exists public.record_events (
  id bigint generated always as identity primary key,
  tbl text not null,
  entity_id uuid not null,
  actor_id uuid references public.profiles(id) on delete set null,
  field text not null,
  old_value text not null default '',
  new_value text not null default '',
  at timestamptz not null default now()
);
create index if not exists record_events_entity on public.record_events (tbl, entity_id, at desc);
alter table public.record_events enable row level security;
drop policy if exists ws_select on public.record_events;
create policy ws_select on public.record_events for select to authenticated
  using (public.is_active_user() and public.can_see(tbl, entity_id));
revoke update, delete on public.record_events from authenticated;

create or replace function public.log_record_change() returns trigger
language plpgsql security definer set search_path = public as $$
declare f text; o jsonb; n jsonb; flds text[];
begin
  if tg_table_name = 'leads' then
    flds := array['status','pipeline','owner_id','sales_owner_id','priority','lead_type','budget','next_followup','zone','deal_id','lost_reason','tags'];
  else
    flds := array['stage','owner_id','value','probability','priority','next_followup','expected_close','lost_reason','zone','tags'];
  end if;
  if tg_op = 'INSERT' then
    insert into public.record_events (tbl, entity_id, actor_id, field, new_value)
    values (tg_table_name, new.id, auth.uid(), 'created', coalesce(to_jsonb(new)->>(case when tg_table_name = 'leads' then 'status' else 'stage' end), ''));
    return null;
  end if;
  o := to_jsonb(old); n := to_jsonb(new);
  foreach f in array flds loop
    if (o->f) is distinct from (n->f) then
      insert into public.record_events (tbl, entity_id, actor_id, field, old_value, new_value)
      values (tg_table_name, new.id, auth.uid(), f, coalesce(o->>f, ''), coalesce(n->>f, ''));
    end if;
  end loop;
  if tg_table_name = 'leads' and (o->'form_submissions') is distinct from (n->'form_submissions')
     and jsonb_array_length(coalesce(n->'form_submissions','[]')) > jsonb_array_length(coalesce(o->'form_submissions','[]')) then
    insert into public.record_events (tbl, entity_id, actor_id, field, new_value)
    values ('leads', new.id, auth.uid(), 'form_submitted', coalesce(n->'form_submissions'->-1->>'form_title', n->'form_submissions'->-1->>'form_name', 'a form'));
  end if;
  return null;
end $$;
drop trigger if exists log_record_change on public.leads;
create trigger log_record_change after insert or update on public.leads for each row execute function public.log_record_change();
drop trigger if exists log_record_change on public.deals;
create trigger log_record_change after insert or update on public.deals for each row execute function public.log_record_change();

-- Lead types and zones used by Marketing and Sales (editable in Admin panel › Company settings)
update public.settings
set data = data || jsonb_build_object(
  'lead_types', coalesce(data->'lead_types', '["Client","Vendor","Rider","Customer","Partner"]'::jsonb),
  'zones', coalesce(data->'zones', '[]'::jsonb))
where id = 1;

do $$
begin
  begin alter publication supabase_realtime add table public.record_events; exception when duplicate_object then null; end;
end $$;


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

-- Done. Next: create your own login in Authentication > Users.
-- The very first person created becomes the admin automatically.
