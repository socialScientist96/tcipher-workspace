-- =====================================================================================
-- schema-live-2026-11-07.sql: the full database structure as it runs live (public schema).
-- Structure only, no data. Exported from Supabase on 7 Nov 2026 with export-schema.sql.
--
-- Why: several upgrades (2026-11e, f, j, l and others) were run in Supabase but never saved here,
-- so the older .sql files no longer describe the live database. This file does.
--
-- Use it to set up a new database (after supabase-setup.sql's extensions/roles are in place), or to
-- check what's live. It is safe to run again: everything is "if not exists" / "create or replace",
-- and policies and triggers are dropped and re-created.
--
-- Not included (outside the public schema): the trigger on auth.users that calls
-- public.handle_new_user(), and Storage bucket rules. See supabase-setup.sql for those.
-- To refresh this file: run export-schema.sql in the SQL Editor and download the result.
-- =====================================================================================

-- Live schema of the Tcipher workspace (public), exported 2026-11-07 13:22 IST
set check_function_bodies = off;

create sequence if not exists public.lead_number_seq;

create sequence if not exists public.test_case_number;

create table if not exists public.activities (
  id uuid default gen_random_uuid() not null,
  kind text default 'Call'::text not null,
  subject text not null,
  activity_date date default CURRENT_DATE not null,
  deal_id uuid,
  client_id uuid,
  contact_id uuid,
  lead_id uuid,
  owner_id uuid default auth.uid(),
  outcome text default ''::text not null,
  next_step text default ''::text not null,
  next_step_date date,
  created_by uuid default auth.uid(),
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now() not null,
  outcome_type text default ''::text not null,
  duration_min integer,
  direction text default 'Outbound'::text not null
);

create table if not exists public.activity_log (
  id bigint generated always as identity not null,
  actor_id uuid,
  tbl text not null,
  action text not null,
  entity_id uuid,
  summary text default ''::text not null,
  at timestamp with time zone default now() not null
);

create table if not exists public.announcements (
  id uuid default gen_random_uuid() not null,
  title text not null,
  body text default ''::text not null,
  pinned boolean default false not null,
  created_by uuid default auth.uid(),
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now() not null
);

create table if not exists public.attendance (
  id uuid default gen_random_uuid() not null,
  user_id uuid default auth.uid() not null,
  day date default CURRENT_DATE not null,
  check_in timestamp with time zone,
  check_out timestamp with time zone,
  mode text default 'Remote'::text not null,
  note text default ''::text not null,
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now() not null,
  status text default 'Present'::text not null,
  marked_by uuid
);

create table if not exists public.calendar_events (
  id uuid default gen_random_uuid() not null,
  user_id uuid not null,
  google_event_id text not null,
  ical_uid text default ''::text not null,
  title text default ''::text not null,
  starts_at timestamp with time zone,
  ends_at timestamp with time zone,
  all_day boolean default false not null,
  start_date date,
  end_date date,
  meet_link text default ''::text not null,
  html_link text default ''::text not null,
  location text default ''::text not null,
  organizer_email text default ''::text not null,
  attendee_emails text[] default '{}'::text[] not null,
  updated_at timestamp with time zone default now() not null
);

create table if not exists public.campaigns (
  id uuid default gen_random_uuid() not null,
  name text not null,
  channel text default ''::text not null,
  objective text default ''::text not null,
  status text default 'Planned'::text not null,
  start_date date,
  end_date date,
  budget numeric,
  spent numeric,
  leads integer,
  conversions integer,
  owner_id uuid,
  notes text default ''::text not null,
  created_by uuid default auth.uid(),
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now() not null
);

create table if not exists public.chat_channels (
  id uuid default gen_random_uuid() not null,
  kind text default 'channel'::text not null,
  name text default ''::text not null,
  vertical text,
  members uuid[] default '{}'::uuid[] not null,
  dm_key text,
  created_by uuid default auth.uid(),
  created_at timestamp with time zone default now() not null
);

create table if not exists public.chat_email_log (
  user_id uuid not null,
  channel_id uuid not null,
  last_message_id bigint default 0 not null,
  last_emailed_at timestamp with time zone
);

create table if not exists public.chat_hidden (
  user_id uuid default auth.uid() not null,
  message_id bigint not null,
  created_at timestamp with time zone default now() not null
);

create table if not exists public.chat_messages (
  id bigint generated always as identity not null,
  channel_id uuid not null,
  author_id uuid default auth.uid(),
  body text not null,
  mentions uuid[] default '{}'::uuid[] not null,
  created_at timestamp with time zone default now() not null,
  edited_at timestamp with time zone,
  attachments jsonb default '[]'::jsonb not null,
  reply_to bigint,
  unsent_at timestamp with time zone,
  via_email boolean default false not null
);

create table if not exists public.chat_mutes (
  user_id uuid default auth.uid() not null,
  channel_id uuid not null,
  created_at timestamp with time zone default now() not null
);

create table if not exists public.chat_reactions (
  message_id bigint not null,
  user_id uuid default auth.uid() not null,
  emoji text not null,
  channel_id uuid not null,
  created_at timestamp with time zone default now() not null
);

create table if not exists public.chat_reads (
  user_id uuid not null,
  channel_id uuid not null,
  last_read_id bigint default 0 not null
);

create table if not exists public.clients (
  id uuid default gen_random_uuid() not null,
  name text not null,
  industry text default ''::text not null,
  contact_name text default ''::text not null,
  email text default ''::text not null,
  phone text default ''::text not null,
  website text default ''::text not null,
  city text default ''::text not null,
  country text default 'India'::text not null,
  tax_id text default ''::text not null,
  status text default 'Active'::text not null,
  owner_id uuid,
  notes text default ''::text not null,
  created_by uuid default auth.uid(),
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now() not null,
  zone text default ''::text not null,
  state text default ''::text not null,
  pincode text default ''::text not null
);

create table if not exists public.comments (
  id uuid default gen_random_uuid() not null,
  tbl text not null,
  entity_id uuid not null,
  body text not null,
  author_id uuid default auth.uid(),
  created_at timestamp with time zone default now() not null,
  mentions uuid[] default '{}'::uuid[] not null,
  kind text default ''::text not null,
  via_email boolean default false not null
);

create table if not exists public.contacts (
  id uuid default gen_random_uuid() not null,
  name text not null,
  client_id uuid,
  title text default ''::text not null,
  email text default ''::text not null,
  phone text default ''::text not null,
  linkedin text default ''::text not null,
  is_primary boolean default false not null,
  owner_id uuid,
  notes text default ''::text not null,
  created_by uuid default auth.uid(),
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now() not null
);

create table if not exists public.content (
  id uuid default gen_random_uuid() not null,
  title text not null,
  channel text default 'LinkedIn'::text not null,
  format text default 'Post'::text not null,
  status text default 'Idea'::text not null,
  publish_date date,
  owner_id uuid,
  campaign_id uuid,
  link text default ''::text not null,
  notes text default ''::text not null,
  created_by uuid default auth.uid(),
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now() not null
);

create table if not exists public.deals (
  id uuid default gen_random_uuid() not null,
  title text not null,
  client_id uuid,
  contact_id uuid,
  company text default ''::text not null,
  contact_name text default ''::text not null,
  email text default ''::text not null,
  phone text default ''::text not null,
  service text default ''::text not null,
  value numeric,
  stage text default 'Lead'::text not null,
  source text default ''::text not null,
  probability integer,
  owner_id uuid,
  expected_close date,
  next_followup date,
  lost_reason text default ''::text not null,
  notes text default ''::text not null,
  closed_at timestamp with time zone,
  created_by uuid default auth.uid(),
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now() not null,
  lead_id uuid,
  lead_type text default ''::text not null,
  priority text default 'Medium'::text not null,
  tags text[] default '{}'::text[] not null,
  city text default ''::text not null,
  zone text default ''::text not null,
  last_contacted_at timestamp with time zone
);

create table if not exists public.deleted_records (
  id bigint generated always as identity not null,
  tbl text not null,
  entity_id uuid,
  data jsonb not null,
  deleted_by uuid,
  deleted_at timestamp with time zone default now() not null
);

create table if not exists public.documents (
  id uuid default gen_random_uuid() not null,
  title text not null,
  category text default 'Other'::text not null,
  vertical text default 'Company'::text not null,
  description text default ''::text not null,
  created_by uuid default auth.uid(),
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now() not null
);

create table if not exists public.email_reply_log (
  gmail_message_id text not null,
  token text default ''::text not null,
  user_id uuid,
  from_email text default ''::text not null,
  status text default ''::text not null,
  created_at timestamp with time zone default now() not null
);

create table if not exists public.email_reply_tokens (
  token text not null,
  user_id uuid not null,
  channel_id uuid,
  tbl text,
  entity_id uuid,
  created_at timestamp with time zone default now() not null,
  expires_at timestamp with time zone default (now() + '30 days'::interval) not null
);

create table if not exists public.emails (
  id uuid default gen_random_uuid() not null,
  user_id uuid not null,
  direction text default 'out'::text not null,
  tbl text default ''::text not null,
  entity_id uuid,
  from_email text default ''::text not null,
  to_email text default ''::text not null,
  cc text default ''::text not null,
  subject text default ''::text not null,
  body text default ''::text not null,
  snippet text default ''::text not null,
  attachments jsonb default '[]'::jsonb not null,
  gmail_message_id text,
  gmail_thread_id text,
  rfc_message_id text default ''::text not null,
  sent_at timestamp with time zone default now() not null,
  read_at timestamp with time zone,
  created_at timestamp with time zone default now() not null
);

create table if not exists public.features (
  id uuid default gen_random_uuid() not null,
  project_id uuid not null,
  key text default ''::text not null,
  name text not null,
  description text default ''::text not null,
  status text default 'In development'::text not null,
  priority text default ''::text not null,
  owner_id uuid,
  tester_id uuid,
  created_by uuid default auth.uid(),
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now() not null
);

create table if not exists public.files (
  id uuid default gen_random_uuid() not null,
  tbl text not null,
  entity_id uuid not null,
  name text not null,
  path text not null,
  size bigint default 0 not null,
  mime text default ''::text not null,
  uploaded_by uuid default auth.uid(),
  created_at timestamp with time zone default now() not null,
  storage text default 'supabase'::text not null
);

create table if not exists public.google_links (
  user_id uuid not null,
  google_email text default ''::text not null,
  connected_at timestamp with time zone default now() not null,
  last_sync_at timestamp with time zone,
  last_error text default ''::text not null,
  scopes text default ''::text not null,
  history_id text default ''::text not null
);

create table if not exists public.google_tokens (
  user_id uuid not null,
  refresh_token text not null,
  scopes text default ''::text not null,
  updated_at timestamp with time zone default now() not null
);

create table if not exists public.leads (
  id uuid default gen_random_uuid() not null,
  name text not null,
  company text default ''::text not null,
  email text default ''::text not null,
  phone text default ''::text not null,
  source text default 'Website'::text not null,
  campaign_id uuid,
  service text default ''::text not null,
  budget numeric,
  status text default 'New'::text not null,
  owner_id uuid,
  sales_owner_id uuid,
  deal_id uuid,
  handed_over_at timestamp with time zone,
  notes text default ''::text not null,
  created_by uuid default auth.uid(),
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now() not null,
  lead_number text,
  pipeline text default 'General'::text not null,
  lead_type text default ''::text not null,
  priority text default 'Medium'::text not null,
  tags text[] default '{}'::text[] not null,
  alt_phone text default ''::text not null,
  address text default ''::text not null,
  city text default ''::text not null,
  state text default ''::text not null,
  country text default 'India'::text not null,
  pincode text default ''::text not null,
  zone text default ''::text not null,
  next_followup date,
  last_contacted_at timestamp with time zone,
  lost_reason text default ''::text not null,
  form_submissions jsonb default '[]'::jsonb not null
);

create table if not exists public.leave_requests (
  id uuid default gen_random_uuid() not null,
  user_id uuid default auth.uid() not null,
  type text default 'Paid leave'::text not null,
  start_date date not null,
  end_date date not null,
  half_day boolean default false not null,
  reason text default ''::text not null,
  status text default 'Pending'::text not null,
  reviewed_by uuid,
  review_note text default ''::text not null,
  created_by uuid default auth.uid(),
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now() not null
);

create table if not exists public.mail_sender (
  id integer default 1 not null,
  google_email text default ''::text not null,
  refresh_token text default ''::text not null,
  scopes text default ''::text not null,
  connected_by uuid,
  connected_at timestamp with time zone,
  last_sent_at timestamp with time zone,
  last_error text default ''::text not null,
  sent_day date,
  sent_count integer default 0 not null,
  running_until timestamp with time zone,
  history_id text default ''::text not null
);

create table if not exists public.meeting_joins (
  id uuid default gen_random_uuid() not null,
  meeting_id uuid,
  user_id uuid,
  display_name text default ''::text not null,
  joined_on date default CURRENT_DATE not null,
  joined_at timestamp with time zone default now() not null,
  left_at timestamp with time zone,
  source text default 'Workspace'::text not null,
  external_id text,
  created_by uuid default auth.uid(),
  created_at timestamp with time zone default now() not null,
  event_uid text default ''::text not null,
  title text default ''::text not null
);

create table if not exists public.meetings (
  id uuid default gen_random_uuid() not null,
  title text not null,
  meeting_date date default CURRENT_DATE not null,
  start_time time without time zone,
  duration_min integer default 30,
  kind text default 'Internal'::text not null,
  attendees uuid[] default '{}'::uuid[] not null,
  project_id uuid,
  client_id uuid,
  link text default ''::text not null,
  agenda text default ''::text not null,
  notes text default ''::text not null,
  action_items text default ''::text not null,
  created_by uuid default auth.uid(),
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now() not null,
  repeat text default 'Does not repeat'::text not null,
  google_event_id text,
  google_owner uuid,
  google_html_link text default ''::text not null,
  repeat_days integer[] default '{}'::integer[] not null
);

create table if not exists public.notes (
  id uuid default gen_random_uuid() not null,
  title text default ''::text not null,
  body text default ''::text not null,
  owner_id uuid default auth.uid() not null,
  visibility text default 'Private'::text not null,
  vertical text,
  shared_with uuid[] default '{}'::uuid[] not null,
  mentions uuid[] default '{}'::uuid[] not null,
  pinned boolean default false not null,
  task_id uuid,
  project_id uuid,
  meeting_id uuid,
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now() not null
);

create table if not exists public.notifications (
  id uuid default gen_random_uuid() not null,
  user_id uuid not null,
  title text not null,
  body text default ''::text not null,
  tbl text default ''::text not null,
  entity_id uuid,
  is_read boolean default false not null,
  created_by uuid default auth.uid(),
  created_at timestamp with time zone default now() not null,
  emailed_at timestamp with time zone,
  email_status text default ''::text not null
);

create table if not exists public.presence (
  user_id uuid not null,
  last_seen_at timestamp with time zone default now() not null
);

create table if not exists public.problem_reports (
  id uuid default gen_random_uuid() not null,
  user_id uuid default auth.uid(),
  kind text default 'user'::text not null,
  page text default ''::text not null,
  message text default ''::text not null,
  note text default ''::text not null,
  details jsonb default '{}'::jsonb not null,
  fingerprint text default ''::text not null,
  status text default 'Open'::text not null,
  fixed_note text default ''::text not null,
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now() not null
);

create table if not exists public.profile_private (
  user_id uuid not null,
  personal_email text default ''::text not null,
  updated_at timestamp with time zone default now() not null
);

create table if not exists public.profiles (
  id uuid not null,
  email text default ''::text not null,
  full_name text default ''::text not null,
  title text default ''::text not null,
  phone text default ''::text not null,
  vertical text,
  role_id uuid,
  is_admin boolean default false not null,
  is_active boolean default true not null,
  joined_on date,
  color text default '#5B2BA6'::text not null,
  created_at timestamp with time zone default now() not null,
  avatar_url text default ''::text not null,
  email_notifications text default 'all'::text not null
);

create table if not exists public.projects (
  id uuid default gen_random_uuid() not null,
  name text not null,
  code text default ''::text not null,
  client_id uuid,
  status text default 'Planning'::text not null,
  priority text default 'Medium'::text not null,
  manager_id uuid,
  members uuid[] default '{}'::uuid[] not null,
  start_date date,
  end_date date,
  budget numeric,
  tech_stack text default ''::text not null,
  repo_url text default ''::text not null,
  description text default ''::text not null,
  created_by uuid default auth.uid(),
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now() not null,
  qa_lead_id uuid
);

create table if not exists public.proposals (
  id uuid default gen_random_uuid() not null,
  number text not null,
  title text default ''::text not null,
  deal_id uuid,
  client_id uuid,
  amount numeric,
  status text default 'Draft'::text not null,
  sent_on date,
  valid_until date,
  owner_id uuid,
  notes text default ''::text not null,
  created_by uuid default auth.uid(),
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now() not null
);

create table if not exists public.record_events (
  id bigint generated always as identity not null,
  tbl text not null,
  entity_id uuid not null,
  actor_id uuid,
  field text not null,
  old_value text default ''::text not null,
  new_value text default ''::text not null,
  at timestamp with time zone default now() not null
);

create table if not exists public.releases (
  id uuid default gen_random_uuid() not null,
  version text not null,
  name text default ''::text not null,
  project_id uuid,
  status text default 'Planned'::text not null,
  environment text default 'Production'::text not null,
  release_date date,
  owner_id uuid,
  qa_signoff_id uuid,
  notes text default ''::text not null,
  created_by uuid default auth.uid(),
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now() not null
);

create table if not exists public.roles (
  id uuid default gen_random_uuid() not null,
  name text not null,
  description text default ''::text not null,
  permissions jsonb default '{}'::jsonb not null,
  created_at timestamp with time zone default now() not null
);

create table if not exists public.seo_keywords (
  id uuid default gen_random_uuid() not null,
  keyword text not null,
  target_url text default ''::text not null,
  "position" integer,
  previous_position integer,
  search_volume integer,
  status text default 'Tracking'::text not null,
  owner_id uuid,
  notes text default ''::text not null,
  created_by uuid default auth.uid(),
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now() not null
);

create table if not exists public.settings (
  id integer default 1 not null,
  data jsonb default '{}'::jsonb not null,
  updated_at timestamp with time zone default now() not null
);

create table if not exists public.social_stats (
  id uuid default gen_random_uuid() not null,
  channel text not null,
  month date not null,
  followers integer,
  posts integer,
  reach integer,
  engagement integer,
  clicks integer,
  leads integer,
  notes text default ''::text not null,
  created_by uuid default auth.uid(),
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now() not null
);

create table if not exists public.sprints (
  id uuid default gen_random_uuid() not null,
  project_id uuid,
  name text not null,
  status text default 'Planned'::text not null,
  start_date date,
  end_date date,
  goal text default ''::text not null,
  created_by uuid default auth.uid(),
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now() not null
);

create table if not exists public.status_events (
  id bigint generated always as identity not null,
  user_id uuid not null,
  at timestamp with time zone default now() not null,
  kind text not null,
  until timestamp with time zone,
  note text default ''::text not null
);

create table if not exists public.targets (
  id uuid default gen_random_uuid() not null,
  user_id uuid not null,
  month date not null,
  target_amount numeric,
  target_deals integer,
  notes text default ''::text not null,
  created_by uuid default auth.uid(),
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now() not null
);

create table if not exists public.task_events (
  id bigint generated always as identity not null,
  task_id uuid not null,
  actor_id uuid,
  field text not null,
  old_value text default ''::text not null,
  new_value text default ''::text not null,
  at timestamp with time zone default now() not null
);

create table if not exists public.tasks (
  id uuid default gen_random_uuid() not null,
  title text not null,
  description text default ''::text not null,
  project_id uuid,
  sprint_id uuid,
  vertical text default 'Development'::text not null,
  type text default 'Feature'::text not null,
  priority text default 'Medium'::text not null,
  status text default 'To do'::text not null,
  assignee_id uuid,
  collaborators uuid[] default '{}'::uuid[] not null,
  reviewer_id uuid,
  due_date date,
  estimate_hours numeric,
  story_points integer,
  severity text default ''::text not null,
  environment text default ''::text not null,
  steps text default ''::text not null,
  blocked boolean default false not null,
  blocked_reason text default ''::text not null,
  completed_at timestamp with time zone,
  created_by uuid default auth.uid(),
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now() not null,
  number bigint generated by default as identity not null,
  labels text[] default '{}'::text[] not null,
  component text default ''::text not null,
  checklist jsonb default '[]'::jsonb not null,
  branch text default ''::text not null,
  pr_url text default ''::text not null,
  design_url text default ''::text not null,
  blocked_by uuid[] default '{}'::uuid[] not null,
  release_id uuid,
  start_date date,
  expected_result text default ''::text not null,
  actual_result text default ''::text not null,
  build_version text default ''::text not null,
  device text default ''::text not null,
  reproducibility text default ''::text not null,
  mentions uuid[] default '{}'::uuid[] not null,
  lead_id uuid,
  deal_id uuid,
  archived boolean default false not null,
  archived_at timestamp with time zone,
  archived_by uuid,
  feature_id uuid,
  test_case_id uuid,
  qa_state text default ''::text not null,
  tester_id uuid,
  reopen_count integer default 0 not null,
  bug_type text default ''::text not null,
  page text default ''::text not null,
  url text default ''::text not null,
  suggested_fix text default ''::text not null,
  evidence text default ''::text not null,
  external_id text default ''::text not null,
  source text default ''::text not null,
  parent_id uuid
);

create table if not exists public.test_cases (
  id uuid default gen_random_uuid() not null,
  number integer default nextval('test_case_number'::regclass) not null,
  external_id text default ''::text not null,
  project_id uuid not null,
  feature_id uuid,
  title text not null,
  preconditions text default ''::text not null,
  test_data text default ''::text not null,
  steps text default ''::text not null,
  expected text default ''::text not null,
  actual text default ''::text not null,
  status text default 'Not run'::text not null,
  test_type text default ''::text not null,
  priority text default ''::text not null,
  platform text default ''::text not null,
  evidence text default ''::text not null,
  notes text default ''::text not null,
  tester_id uuid,
  assignee_id uuid,
  task_id uuid,
  retest_count integer default 0 not null,
  last_run_at timestamp with time zone,
  source text default ''::text not null,
  created_by uuid default auth.uid(),
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now() not null
);

create table if not exists public.test_runs (
  id bigint generated always as identity not null,
  test_case_id uuid not null,
  status text not null,
  actual text default ''::text not null,
  evidence text default ''::text not null,
  tester_id uuid default auth.uid(),
  at timestamp with time zone default now() not null
);

create table if not exists public.tickets (
  id uuid default gen_random_uuid() not null,
  title text not null,
  description text default ''::text not null,
  client_id uuid,
  project_id uuid,
  priority text default 'Medium'::text not null,
  status text default 'Open'::text not null,
  channel text default 'Email'::text not null,
  assignee_id uuid,
  due_date date,
  resolved_at timestamp with time zone,
  created_by uuid default auth.uid(),
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now() not null
);

create table if not exists public.user_status (
  user_id uuid not null,
  state text default 'active'::text not null,
  until timestamp with time zone,
  note text default ''::text not null,
  last_active_at timestamp with time zone default now() not null,
  idle_since timestamp with time zone,
  admins_alerted_at timestamp with time zone,
  lunch_reminded_at timestamp with time zone,
  checkin_reminded_on date,
  checkin_alerted_on date,
  updated_at timestamp with time zone default now() not null,
  checked_in_at timestamp with time zone,
  checked_out_at timestamp with time zone,
  leave_day date,
  leave_half boolean default false not null
);

create table if not exists public.work_logs (
  id uuid default gen_random_uuid() not null,
  task_id uuid not null,
  user_id uuid default auth.uid() not null,
  work_date date default ((now() AT TIME ZONE 'Asia/Kolkata'::text))::date not null,
  minutes integer not null,
  note text default ''::text not null,
  created_at timestamp with time zone default now() not null
);

alter table public.activities add column if not exists activity_date date default CURRENT_DATE;

alter table public.activities add column if not exists id uuid default gen_random_uuid();

alter table public.activities add column if not exists next_step_date date;

alter table public.activities add column if not exists duration_min integer;

alter table public.activities add column if not exists client_id uuid;

alter table public.activities add column if not exists lead_id uuid;

alter table public.activities add column if not exists outcome_type text default ''::text;

alter table public.activities add column if not exists direction text default 'Outbound'::text;

alter table public.activities add column if not exists subject text;

alter table public.activities add column if not exists contact_id uuid;

alter table public.activities add column if not exists deal_id uuid;

alter table public.activities add column if not exists updated_at timestamp with time zone default now();

alter table public.activities add column if not exists created_at timestamp with time zone default now();

alter table public.activities add column if not exists created_by uuid default auth.uid();

alter table public.activities add column if not exists next_step text default ''::text;

alter table public.activities add column if not exists outcome text default ''::text;

alter table public.activities add column if not exists owner_id uuid default auth.uid();

alter table public.activities add column if not exists kind text default 'Call'::text;

alter table public.activity_log add column if not exists tbl text;

alter table public.activity_log add column if not exists action text;

alter table public.activity_log add column if not exists actor_id uuid;

alter table public.activity_log add column if not exists at timestamp with time zone default now();

alter table public.activity_log add column if not exists summary text default ''::text;

alter table public.activity_log add column if not exists entity_id uuid;

alter table public.announcements add column if not exists pinned boolean default false;

alter table public.announcements add column if not exists updated_at timestamp with time zone default now();

alter table public.announcements add column if not exists id uuid default gen_random_uuid();

alter table public.announcements add column if not exists body text default ''::text;

alter table public.announcements add column if not exists created_by uuid default auth.uid();

alter table public.announcements add column if not exists title text;

alter table public.announcements add column if not exists created_at timestamp with time zone default now();

alter table public.attendance add column if not exists mode text default 'Remote'::text;

alter table public.attendance add column if not exists check_out timestamp with time zone;

alter table public.attendance add column if not exists status text default 'Present'::text;

alter table public.attendance add column if not exists marked_by uuid;

alter table public.attendance add column if not exists check_in timestamp with time zone;

alter table public.attendance add column if not exists created_at timestamp with time zone default now();

alter table public.attendance add column if not exists updated_at timestamp with time zone default now();

alter table public.attendance add column if not exists note text default ''::text;

alter table public.attendance add column if not exists day date default CURRENT_DATE;

alter table public.attendance add column if not exists user_id uuid default auth.uid();

alter table public.attendance add column if not exists id uuid default gen_random_uuid();

alter table public.calendar_events add column if not exists title text default ''::text;

alter table public.calendar_events add column if not exists updated_at timestamp with time zone default now();

alter table public.calendar_events add column if not exists attendee_emails text[] default '{}'::text[];

alter table public.calendar_events add column if not exists organizer_email text default ''::text;

alter table public.calendar_events add column if not exists ical_uid text default ''::text;

alter table public.calendar_events add column if not exists id uuid default gen_random_uuid();

alter table public.calendar_events add column if not exists location text default ''::text;

alter table public.calendar_events add column if not exists google_event_id text;

alter table public.calendar_events add column if not exists html_link text default ''::text;

alter table public.calendar_events add column if not exists end_date date;

alter table public.calendar_events add column if not exists meet_link text default ''::text;

alter table public.calendar_events add column if not exists start_date date;

alter table public.calendar_events add column if not exists all_day boolean default false;

alter table public.calendar_events add column if not exists user_id uuid;

alter table public.calendar_events add column if not exists starts_at timestamp with time zone;

alter table public.calendar_events add column if not exists ends_at timestamp with time zone;

alter table public.campaigns add column if not exists name text;

alter table public.campaigns add column if not exists id uuid default gen_random_uuid();

alter table public.campaigns add column if not exists budget numeric;

alter table public.campaigns add column if not exists channel text default ''::text;

alter table public.campaigns add column if not exists conversions integer;

alter table public.campaigns add column if not exists objective text default ''::text;

alter table public.campaigns add column if not exists spent numeric;

alter table public.campaigns add column if not exists notes text default ''::text;

alter table public.campaigns add column if not exists created_by uuid default auth.uid();

alter table public.campaigns add column if not exists end_date date;

alter table public.campaigns add column if not exists updated_at timestamp with time zone default now();

alter table public.campaigns add column if not exists owner_id uuid;

alter table public.campaigns add column if not exists leads integer;

alter table public.campaigns add column if not exists created_at timestamp with time zone default now();

alter table public.campaigns add column if not exists start_date date;

alter table public.campaigns add column if not exists status text default 'Planned'::text;

alter table public.chat_channels add column if not exists id uuid default gen_random_uuid();

alter table public.chat_channels add column if not exists vertical text;

alter table public.chat_channels add column if not exists dm_key text;

alter table public.chat_channels add column if not exists created_at timestamp with time zone default now();

alter table public.chat_channels add column if not exists created_by uuid default auth.uid();

alter table public.chat_channels add column if not exists members uuid[] default '{}'::uuid[];

alter table public.chat_channels add column if not exists name text default ''::text;

alter table public.chat_channels add column if not exists kind text default 'channel'::text;

alter table public.chat_email_log add column if not exists channel_id uuid;

alter table public.chat_email_log add column if not exists last_message_id bigint default 0;

alter table public.chat_email_log add column if not exists last_emailed_at timestamp with time zone;

alter table public.chat_email_log add column if not exists user_id uuid;

alter table public.chat_hidden add column if not exists created_at timestamp with time zone default now();

alter table public.chat_hidden add column if not exists message_id bigint;

alter table public.chat_hidden add column if not exists user_id uuid default auth.uid();

alter table public.chat_messages add column if not exists body text;

alter table public.chat_messages add column if not exists via_email boolean default false;

alter table public.chat_messages add column if not exists created_at timestamp with time zone default now();

alter table public.chat_messages add column if not exists mentions uuid[] default '{}'::uuid[];

alter table public.chat_messages add column if not exists author_id uuid default auth.uid();

alter table public.chat_messages add column if not exists unsent_at timestamp with time zone;

alter table public.chat_messages add column if not exists channel_id uuid;

alter table public.chat_messages add column if not exists attachments jsonb default '[]'::jsonb;

alter table public.chat_messages add column if not exists edited_at timestamp with time zone;

alter table public.chat_messages add column if not exists reply_to bigint;

alter table public.chat_mutes add column if not exists channel_id uuid;

alter table public.chat_mutes add column if not exists user_id uuid default auth.uid();

alter table public.chat_mutes add column if not exists created_at timestamp with time zone default now();

alter table public.chat_reactions add column if not exists channel_id uuid;

alter table public.chat_reactions add column if not exists emoji text;

alter table public.chat_reactions add column if not exists user_id uuid default auth.uid();

alter table public.chat_reactions add column if not exists message_id bigint;

alter table public.chat_reactions add column if not exists created_at timestamp with time zone default now();

alter table public.chat_reads add column if not exists channel_id uuid;

alter table public.chat_reads add column if not exists last_read_id bigint default 0;

alter table public.chat_reads add column if not exists user_id uuid;

alter table public.clients add column if not exists website text default ''::text;

alter table public.clients add column if not exists name text;

alter table public.clients add column if not exists owner_id uuid;

alter table public.clients add column if not exists created_at timestamp with time zone default now();

alter table public.clients add column if not exists created_by uuid default auth.uid();

alter table public.clients add column if not exists notes text default ''::text;

alter table public.clients add column if not exists status text default 'Active'::text;

alter table public.clients add column if not exists tax_id text default ''::text;

alter table public.clients add column if not exists country text default 'India'::text;

alter table public.clients add column if not exists city text default ''::text;

alter table public.clients add column if not exists updated_at timestamp with time zone default now();

alter table public.clients add column if not exists phone text default ''::text;

alter table public.clients add column if not exists email text default ''::text;

alter table public.clients add column if not exists contact_name text default ''::text;

alter table public.clients add column if not exists industry text default ''::text;

alter table public.clients add column if not exists id uuid default gen_random_uuid();

alter table public.clients add column if not exists pincode text default ''::text;

alter table public.clients add column if not exists state text default ''::text;

alter table public.clients add column if not exists zone text default ''::text;

alter table public.comments add column if not exists kind text default ''::text;

alter table public.comments add column if not exists body text;

alter table public.comments add column if not exists author_id uuid default auth.uid();

alter table public.comments add column if not exists id uuid default gen_random_uuid();

alter table public.comments add column if not exists via_email boolean default false;

alter table public.comments add column if not exists created_at timestamp with time zone default now();

alter table public.comments add column if not exists tbl text;

alter table public.comments add column if not exists entity_id uuid;

alter table public.comments add column if not exists mentions uuid[] default '{}'::uuid[];

alter table public.contacts add column if not exists client_id uuid;

alter table public.contacts add column if not exists name text;

alter table public.contacts add column if not exists updated_at timestamp with time zone default now();

alter table public.contacts add column if not exists created_at timestamp with time zone default now();

alter table public.contacts add column if not exists created_by uuid default auth.uid();

alter table public.contacts add column if not exists notes text default ''::text;

alter table public.contacts add column if not exists is_primary boolean default false;

alter table public.contacts add column if not exists id uuid default gen_random_uuid();

alter table public.contacts add column if not exists linkedin text default ''::text;

alter table public.contacts add column if not exists phone text default ''::text;

alter table public.contacts add column if not exists owner_id uuid;

alter table public.contacts add column if not exists email text default ''::text;

alter table public.contacts add column if not exists title text default ''::text;

alter table public.content add column if not exists title text;

alter table public.content add column if not exists owner_id uuid;

alter table public.content add column if not exists campaign_id uuid;

alter table public.content add column if not exists id uuid default gen_random_uuid();

alter table public.content add column if not exists publish_date date;

alter table public.content add column if not exists channel text default 'LinkedIn'::text;

alter table public.content add column if not exists created_at timestamp with time zone default now();

alter table public.content add column if not exists link text default ''::text;

alter table public.content add column if not exists created_by uuid default auth.uid();

alter table public.content add column if not exists status text default 'Idea'::text;

alter table public.content add column if not exists format text default 'Post'::text;

alter table public.content add column if not exists updated_at timestamp with time zone default now();

alter table public.content add column if not exists notes text default ''::text;

alter table public.deals add column if not exists contact_id uuid;

alter table public.deals add column if not exists updated_at timestamp with time zone default now();

alter table public.deals add column if not exists created_at timestamp with time zone default now();

alter table public.deals add column if not exists created_by uuid default auth.uid();

alter table public.deals add column if not exists notes text default ''::text;

alter table public.deals add column if not exists lost_reason text default ''::text;

alter table public.deals add column if not exists source text default ''::text;

alter table public.deals add column if not exists client_id uuid;

alter table public.deals add column if not exists owner_id uuid;

alter table public.deals add column if not exists last_contacted_at timestamp with time zone;

alter table public.deals add column if not exists stage text default 'Lead'::text;

alter table public.deals add column if not exists expected_close date;

alter table public.deals add column if not exists service text default ''::text;

alter table public.deals add column if not exists phone text default ''::text;

alter table public.deals add column if not exists email text default ''::text;

alter table public.deals add column if not exists contact_name text default ''::text;

alter table public.deals add column if not exists company text default ''::text;

alter table public.deals add column if not exists id uuid default gen_random_uuid();

alter table public.deals add column if not exists zone text default ''::text;

alter table public.deals add column if not exists title text;

alter table public.deals add column if not exists lead_id uuid;

alter table public.deals add column if not exists city text default ''::text;

alter table public.deals add column if not exists tags text[] default '{}'::text[];

alter table public.deals add column if not exists next_followup date;

alter table public.deals add column if not exists priority text default 'Medium'::text;

alter table public.deals add column if not exists lead_type text default ''::text;

alter table public.deals add column if not exists closed_at timestamp with time zone;

alter table public.deals add column if not exists probability integer;

alter table public.deals add column if not exists value numeric;

alter table public.deleted_records add column if not exists tbl text;

alter table public.deleted_records add column if not exists deleted_by uuid;

alter table public.deleted_records add column if not exists deleted_at timestamp with time zone default now();

alter table public.deleted_records add column if not exists data jsonb;

alter table public.deleted_records add column if not exists entity_id uuid;

alter table public.documents add column if not exists description text default ''::text;

alter table public.documents add column if not exists title text;

alter table public.documents add column if not exists id uuid default gen_random_uuid();

alter table public.documents add column if not exists vertical text default 'Company'::text;

alter table public.documents add column if not exists created_at timestamp with time zone default now();

alter table public.documents add column if not exists updated_at timestamp with time zone default now();

alter table public.documents add column if not exists category text default 'Other'::text;

alter table public.documents add column if not exists created_by uuid default auth.uid();

alter table public.email_reply_log add column if not exists gmail_message_id text;

alter table public.email_reply_log add column if not exists status text default ''::text;

alter table public.email_reply_log add column if not exists from_email text default ''::text;

alter table public.email_reply_log add column if not exists created_at timestamp with time zone default now();

alter table public.email_reply_log add column if not exists token text default ''::text;

alter table public.email_reply_log add column if not exists user_id uuid;

alter table public.email_reply_tokens add column if not exists created_at timestamp with time zone default now();

alter table public.email_reply_tokens add column if not exists expires_at timestamp with time zone default (now() + '30 days'::interval);

alter table public.email_reply_tokens add column if not exists token text;

alter table public.email_reply_tokens add column if not exists entity_id uuid;

alter table public.email_reply_tokens add column if not exists user_id uuid;

alter table public.email_reply_tokens add column if not exists tbl text;

alter table public.email_reply_tokens add column if not exists channel_id uuid;

alter table public.emails add column if not exists body text default ''::text;

alter table public.emails add column if not exists read_at timestamp with time zone;

alter table public.emails add column if not exists created_at timestamp with time zone default now();

alter table public.emails add column if not exists user_id uuid;

alter table public.emails add column if not exists gmail_thread_id text;

alter table public.emails add column if not exists entity_id uuid;

alter table public.emails add column if not exists sent_at timestamp with time zone default now();

alter table public.emails add column if not exists rfc_message_id text default ''::text;

alter table public.emails add column if not exists attachments jsonb default '[]'::jsonb;

alter table public.emails add column if not exists snippet text default ''::text;

alter table public.emails add column if not exists gmail_message_id text;

alter table public.emails add column if not exists subject text default ''::text;

alter table public.emails add column if not exists cc text default ''::text;

alter table public.emails add column if not exists to_email text default ''::text;

alter table public.emails add column if not exists from_email text default ''::text;

alter table public.emails add column if not exists tbl text default ''::text;

alter table public.emails add column if not exists direction text default 'out'::text;

alter table public.emails add column if not exists id uuid default gen_random_uuid();

alter table public.features add column if not exists priority text default ''::text;

alter table public.features add column if not exists description text default ''::text;

alter table public.features add column if not exists key text default ''::text;

alter table public.features add column if not exists id uuid default gen_random_uuid();

alter table public.features add column if not exists project_id uuid;

alter table public.features add column if not exists tester_id uuid;

alter table public.features add column if not exists owner_id uuid;

alter table public.features add column if not exists name text;

alter table public.features add column if not exists updated_at timestamp with time zone default now();

alter table public.features add column if not exists created_at timestamp with time zone default now();

alter table public.features add column if not exists created_by uuid default auth.uid();

alter table public.features add column if not exists status text default 'In development'::text;

alter table public.files add column if not exists created_at timestamp with time zone default now();

alter table public.files add column if not exists name text;

alter table public.files add column if not exists path text;

alter table public.files add column if not exists uploaded_by uuid default auth.uid();

alter table public.files add column if not exists mime text default ''::text;

alter table public.files add column if not exists size bigint default 0;

alter table public.files add column if not exists storage text default 'supabase'::text;

alter table public.files add column if not exists id uuid default gen_random_uuid();

alter table public.files add column if not exists entity_id uuid;

alter table public.files add column if not exists tbl text;

alter table public.google_links add column if not exists scopes text default ''::text;

alter table public.google_links add column if not exists user_id uuid;

alter table public.google_links add column if not exists history_id text default ''::text;

alter table public.google_links add column if not exists connected_at timestamp with time zone default now();

alter table public.google_links add column if not exists google_email text default ''::text;

alter table public.google_links add column if not exists last_sync_at timestamp with time zone;

alter table public.google_links add column if not exists last_error text default ''::text;

alter table public.google_tokens add column if not exists user_id uuid;

alter table public.google_tokens add column if not exists updated_at timestamp with time zone default now();

alter table public.google_tokens add column if not exists scopes text default ''::text;

alter table public.google_tokens add column if not exists refresh_token text;

alter table public.leads add column if not exists company text default ''::text;

alter table public.leads add column if not exists sales_owner_id uuid;

alter table public.leads add column if not exists campaign_id uuid;

alter table public.leads add column if not exists lead_number text;

alter table public.leads add column if not exists deal_id uuid;

alter table public.leads add column if not exists handed_over_at timestamp with time zone;

alter table public.leads add column if not exists pipeline text default 'General'::text;

alter table public.leads add column if not exists lead_type text default ''::text;

alter table public.leads add column if not exists priority text default 'Medium'::text;

alter table public.leads add column if not exists tags text[] default '{}'::text[];

alter table public.leads add column if not exists alt_phone text default ''::text;

alter table public.leads add column if not exists address text default ''::text;

alter table public.leads add column if not exists city text default ''::text;

alter table public.leads add column if not exists state text default ''::text;

alter table public.leads add column if not exists country text default 'India'::text;

alter table public.leads add column if not exists pincode text default ''::text;

alter table public.leads add column if not exists zone text default ''::text;

alter table public.leads add column if not exists lost_reason text default ''::text;

alter table public.leads add column if not exists form_submissions jsonb default '[]'::jsonb;

alter table public.leads add column if not exists last_contacted_at timestamp with time zone;

alter table public.leads add column if not exists next_followup date;

alter table public.leads add column if not exists owner_id uuid;

alter table public.leads add column if not exists updated_at timestamp with time zone default now();

alter table public.leads add column if not exists created_at timestamp with time zone default now();

alter table public.leads add column if not exists created_by uuid default auth.uid();

alter table public.leads add column if not exists notes text default ''::text;

alter table public.leads add column if not exists status text default 'New'::text;

alter table public.leads add column if not exists service text default ''::text;

alter table public.leads add column if not exists source text default 'Website'::text;

alter table public.leads add column if not exists phone text default ''::text;

alter table public.leads add column if not exists email text default ''::text;

alter table public.leads add column if not exists id uuid default gen_random_uuid();

alter table public.leads add column if not exists name text;

alter table public.leads add column if not exists budget numeric;

alter table public.leave_requests add column if not exists start_date date;

alter table public.leave_requests add column if not exists end_date date;

alter table public.leave_requests add column if not exists reason text default ''::text;

alter table public.leave_requests add column if not exists half_day boolean default false;

alter table public.leave_requests add column if not exists type text default 'Paid leave'::text;

alter table public.leave_requests add column if not exists user_id uuid default auth.uid();

alter table public.leave_requests add column if not exists id uuid default gen_random_uuid();

alter table public.leave_requests add column if not exists status text default 'Pending'::text;

alter table public.leave_requests add column if not exists review_note text default ''::text;

alter table public.leave_requests add column if not exists updated_at timestamp with time zone default now();

alter table public.leave_requests add column if not exists created_at timestamp with time zone default now();

alter table public.leave_requests add column if not exists created_by uuid default auth.uid();

alter table public.leave_requests add column if not exists reviewed_by uuid;

alter table public.mail_sender add column if not exists last_error text default ''::text;

alter table public.mail_sender add column if not exists scopes text default ''::text;

alter table public.mail_sender add column if not exists refresh_token text default ''::text;

alter table public.mail_sender add column if not exists google_email text default ''::text;

alter table public.mail_sender add column if not exists id integer default 1;

alter table public.mail_sender add column if not exists running_until timestamp with time zone;

alter table public.mail_sender add column if not exists sent_day date;

alter table public.mail_sender add column if not exists history_id text default ''::text;

alter table public.mail_sender add column if not exists connected_at timestamp with time zone;

alter table public.mail_sender add column if not exists connected_by uuid;

alter table public.mail_sender add column if not exists sent_count integer default 0;

alter table public.mail_sender add column if not exists last_sent_at timestamp with time zone;

alter table public.meeting_joins add column if not exists display_name text default ''::text;

alter table public.meeting_joins add column if not exists meeting_id uuid;

alter table public.meeting_joins add column if not exists title text default ''::text;

alter table public.meeting_joins add column if not exists event_uid text default ''::text;

alter table public.meeting_joins add column if not exists user_id uuid;

alter table public.meeting_joins add column if not exists left_at timestamp with time zone;

alter table public.meeting_joins add column if not exists external_id text;

alter table public.meeting_joins add column if not exists created_at timestamp with time zone default now();

alter table public.meeting_joins add column if not exists created_by uuid default auth.uid();

alter table public.meeting_joins add column if not exists source text default 'Workspace'::text;

alter table public.meeting_joins add column if not exists joined_at timestamp with time zone default now();

alter table public.meeting_joins add column if not exists joined_on date default CURRENT_DATE;

alter table public.meeting_joins add column if not exists id uuid default gen_random_uuid();

alter table public.meetings add column if not exists action_items text default ''::text;

alter table public.meetings add column if not exists created_by uuid default auth.uid();

alter table public.meetings add column if not exists created_at timestamp with time zone default now();

alter table public.meetings add column if not exists updated_at timestamp with time zone default now();

alter table public.meetings add column if not exists project_id uuid;

alter table public.meetings add column if not exists link text default ''::text;

alter table public.meetings add column if not exists repeat_days integer[] default '{}'::integer[];

alter table public.meetings add column if not exists attendees uuid[] default '{}'::uuid[];

alter table public.meetings add column if not exists kind text default 'Internal'::text;

alter table public.meetings add column if not exists duration_min integer default 30;

alter table public.meetings add column if not exists repeat text default 'Does not repeat'::text;

alter table public.meetings add column if not exists google_owner uuid;

alter table public.meetings add column if not exists google_html_link text default ''::text;

alter table public.meetings add column if not exists client_id uuid;

alter table public.meetings add column if not exists google_event_id text;

alter table public.meetings add column if not exists title text;

alter table public.meetings add column if not exists id uuid default gen_random_uuid();

alter table public.meetings add column if not exists start_time time without time zone;

alter table public.meetings add column if not exists agenda text default ''::text;

alter table public.meetings add column if not exists notes text default ''::text;

alter table public.meetings add column if not exists meeting_date date default CURRENT_DATE;

alter table public.notes add column if not exists visibility text default 'Private'::text;

alter table public.notes add column if not exists body text default ''::text;

alter table public.notes add column if not exists title text default ''::text;

alter table public.notes add column if not exists id uuid default gen_random_uuid();

alter table public.notes add column if not exists meeting_id uuid;

alter table public.notes add column if not exists task_id uuid;

alter table public.notes add column if not exists vertical text;

alter table public.notes add column if not exists project_id uuid;

alter table public.notes add column if not exists updated_at timestamp with time zone default now();

alter table public.notes add column if not exists created_at timestamp with time zone default now();

alter table public.notes add column if not exists pinned boolean default false;

alter table public.notes add column if not exists mentions uuid[] default '{}'::uuid[];

alter table public.notes add column if not exists shared_with uuid[] default '{}'::uuid[];

alter table public.notes add column if not exists owner_id uuid default auth.uid();

alter table public.notifications add column if not exists title text;

alter table public.notifications add column if not exists body text default ''::text;

alter table public.notifications add column if not exists tbl text default ''::text;

alter table public.notifications add column if not exists user_id uuid;

alter table public.notifications add column if not exists id uuid default gen_random_uuid();

alter table public.notifications add column if not exists email_status text default ''::text;

alter table public.notifications add column if not exists emailed_at timestamp with time zone;

alter table public.notifications add column if not exists entity_id uuid;

alter table public.notifications add column if not exists created_by uuid default auth.uid();

alter table public.notifications add column if not exists is_read boolean default false;

alter table public.notifications add column if not exists created_at timestamp with time zone default now();

alter table public.presence add column if not exists user_id uuid;

alter table public.presence add column if not exists last_seen_at timestamp with time zone default now();

alter table public.problem_reports add column if not exists note text default ''::text;

alter table public.problem_reports add column if not exists page text default ''::text;

alter table public.problem_reports add column if not exists kind text default 'user'::text;

alter table public.problem_reports add column if not exists updated_at timestamp with time zone default now();

alter table public.problem_reports add column if not exists created_at timestamp with time zone default now();

alter table public.problem_reports add column if not exists fixed_note text default ''::text;

alter table public.problem_reports add column if not exists id uuid default gen_random_uuid();

alter table public.problem_reports add column if not exists status text default 'Open'::text;

alter table public.problem_reports add column if not exists user_id uuid default auth.uid();

alter table public.problem_reports add column if not exists fingerprint text default ''::text;

alter table public.problem_reports add column if not exists details jsonb default '{}'::jsonb;

alter table public.problem_reports add column if not exists message text default ''::text;

alter table public.profile_private add column if not exists user_id uuid;

alter table public.profile_private add column if not exists personal_email text default ''::text;

alter table public.profile_private add column if not exists updated_at timestamp with time zone default now();

alter table public.profiles add column if not exists email_notifications text default 'all'::text;

alter table public.profiles add column if not exists avatar_url text default ''::text;

alter table public.profiles add column if not exists is_admin boolean default false;

alter table public.profiles add column if not exists vertical text;

alter table public.profiles add column if not exists phone text default ''::text;

alter table public.profiles add column if not exists id uuid;

alter table public.profiles add column if not exists email text default ''::text;

alter table public.profiles add column if not exists role_id uuid;

alter table public.profiles add column if not exists joined_on date;

alter table public.profiles add column if not exists title text default ''::text;

alter table public.profiles add column if not exists full_name text default ''::text;

alter table public.profiles add column if not exists created_at timestamp with time zone default now();

alter table public.profiles add column if not exists color text default '#5B2BA6'::text;

alter table public.profiles add column if not exists is_active boolean default true;

alter table public.projects add column if not exists repo_url text default ''::text;

alter table public.projects add column if not exists budget numeric;

alter table public.projects add column if not exists updated_at timestamp with time zone default now();

alter table public.projects add column if not exists created_at timestamp with time zone default now();

alter table public.projects add column if not exists created_by uuid default auth.uid();

alter table public.projects add column if not exists description text default ''::text;

alter table public.projects add column if not exists tech_stack text default ''::text;

alter table public.projects add column if not exists name text;

alter table public.projects add column if not exists members uuid[] default '{}'::uuid[];

alter table public.projects add column if not exists end_date date;

alter table public.projects add column if not exists priority text default 'Medium'::text;

alter table public.projects add column if not exists qa_lead_id uuid;

alter table public.projects add column if not exists status text default 'Planning'::text;

alter table public.projects add column if not exists client_id uuid;

alter table public.projects add column if not exists code text default ''::text;

alter table public.projects add column if not exists id uuid default gen_random_uuid();

alter table public.projects add column if not exists manager_id uuid;

alter table public.projects add column if not exists start_date date;

alter table public.proposals add column if not exists deal_id uuid;

alter table public.proposals add column if not exists valid_until date;

alter table public.proposals add column if not exists id uuid default gen_random_uuid();

alter table public.proposals add column if not exists title text default ''::text;

alter table public.proposals add column if not exists status text default 'Draft'::text;

alter table public.proposals add column if not exists notes text default ''::text;

alter table public.proposals add column if not exists created_by uuid default auth.uid();

alter table public.proposals add column if not exists number text;

alter table public.proposals add column if not exists created_at timestamp with time zone default now();

alter table public.proposals add column if not exists updated_at timestamp with time zone default now();

alter table public.proposals add column if not exists owner_id uuid;

alter table public.proposals add column if not exists sent_on date;

alter table public.proposals add column if not exists amount numeric;

alter table public.proposals add column if not exists client_id uuid;

alter table public.record_events add column if not exists tbl text;

alter table public.record_events add column if not exists old_value text default ''::text;

alter table public.record_events add column if not exists new_value text default ''::text;

alter table public.record_events add column if not exists at timestamp with time zone default now();

alter table public.record_events add column if not exists actor_id uuid;

alter table public.record_events add column if not exists entity_id uuid;

alter table public.record_events add column if not exists field text;

alter table public.releases add column if not exists id uuid default gen_random_uuid();

alter table public.releases add column if not exists owner_id uuid;

alter table public.releases add column if not exists release_date date;

alter table public.releases add column if not exists name text default ''::text;

alter table public.releases add column if not exists project_id uuid;

alter table public.releases add column if not exists status text default 'Planned'::text;

alter table public.releases add column if not exists environment text default 'Production'::text;

alter table public.releases add column if not exists notes text default ''::text;

alter table public.releases add column if not exists updated_at timestamp with time zone default now();

alter table public.releases add column if not exists created_at timestamp with time zone default now();

alter table public.releases add column if not exists created_by uuid default auth.uid();

alter table public.releases add column if not exists qa_signoff_id uuid;

alter table public.releases add column if not exists version text;

alter table public.roles add column if not exists name text;

alter table public.roles add column if not exists created_at timestamp with time zone default now();

alter table public.roles add column if not exists permissions jsonb default '{}'::jsonb;

alter table public.roles add column if not exists description text default ''::text;

alter table public.roles add column if not exists id uuid default gen_random_uuid();

alter table public.seo_keywords add column if not exists updated_at timestamp with time zone default now();

alter table public.seo_keywords add column if not exists search_volume integer;

alter table public.seo_keywords add column if not exists created_by uuid default auth.uid();

alter table public.seo_keywords add column if not exists target_url text default ''::text;

alter table public.seo_keywords add column if not exists keyword text;

alter table public.seo_keywords add column if not exists status text default 'Tracking'::text;

alter table public.seo_keywords add column if not exists owner_id uuid;

alter table public.seo_keywords add column if not exists id uuid default gen_random_uuid();

alter table public.seo_keywords add column if not exists previous_position integer;

alter table public.seo_keywords add column if not exists created_at timestamp with time zone default now();

alter table public.seo_keywords add column if not exists "position" integer;

alter table public.seo_keywords add column if not exists notes text default ''::text;

alter table public.settings add column if not exists id integer default 1;

alter table public.settings add column if not exists updated_at timestamp with time zone default now();

alter table public.settings add column if not exists data jsonb default '{}'::jsonb;

alter table public.social_stats add column if not exists channel text;

alter table public.social_stats add column if not exists reach integer;

alter table public.social_stats add column if not exists id uuid default gen_random_uuid();

alter table public.social_stats add column if not exists notes text default ''::text;

alter table public.social_stats add column if not exists created_by uuid default auth.uid();

alter table public.social_stats add column if not exists engagement integer;

alter table public.social_stats add column if not exists clicks integer;

alter table public.social_stats add column if not exists posts integer;

alter table public.social_stats add column if not exists created_at timestamp with time zone default now();

alter table public.social_stats add column if not exists updated_at timestamp with time zone default now();

alter table public.social_stats add column if not exists month date;

alter table public.social_stats add column if not exists leads integer;

alter table public.social_stats add column if not exists followers integer;

alter table public.sprints add column if not exists start_date date;

alter table public.sprints add column if not exists name text;

alter table public.sprints add column if not exists status text default 'Planned'::text;

alter table public.sprints add column if not exists end_date date;

alter table public.sprints add column if not exists id uuid default gen_random_uuid();

alter table public.sprints add column if not exists created_by uuid default auth.uid();

alter table public.sprints add column if not exists updated_at timestamp with time zone default now();

alter table public.sprints add column if not exists created_at timestamp with time zone default now();

alter table public.sprints add column if not exists project_id uuid;

alter table public.sprints add column if not exists goal text default ''::text;

alter table public.status_events add column if not exists user_id uuid;

alter table public.status_events add column if not exists until timestamp with time zone;

alter table public.status_events add column if not exists at timestamp with time zone default now();

alter table public.status_events add column if not exists kind text;

alter table public.status_events add column if not exists note text default ''::text;

alter table public.targets add column if not exists user_id uuid;

alter table public.targets add column if not exists target_deals integer;

alter table public.targets add column if not exists notes text default ''::text;

alter table public.targets add column if not exists created_by uuid default auth.uid();

alter table public.targets add column if not exists target_amount numeric;

alter table public.targets add column if not exists updated_at timestamp with time zone default now();

alter table public.targets add column if not exists month date;

alter table public.targets add column if not exists id uuid default gen_random_uuid();

alter table public.targets add column if not exists created_at timestamp with time zone default now();

alter table public.task_events add column if not exists task_id uuid;

alter table public.task_events add column if not exists field text;

alter table public.task_events add column if not exists actor_id uuid;

alter table public.task_events add column if not exists old_value text default ''::text;

alter table public.task_events add column if not exists new_value text default ''::text;

alter table public.task_events add column if not exists at timestamp with time zone default now();

alter table public.tasks add column if not exists created_by uuid default auth.uid();

alter table public.tasks add column if not exists assignee_id uuid;

alter table public.tasks add column if not exists reviewer_id uuid;

alter table public.tasks add column if not exists blocked boolean default false;

alter table public.tasks add column if not exists steps text default ''::text;

alter table public.tasks add column if not exists start_date date;

alter table public.tasks add column if not exists environment text default ''::text;

alter table public.tasks add column if not exists severity text default ''::text;

alter table public.tasks add column if not exists collaborators uuid[] default '{}'::uuid[];

alter table public.tasks add column if not exists story_points integer;

alter table public.tasks add column if not exists status text default 'To do'::text;

alter table public.tasks add column if not exists priority text default 'Medium'::text;

alter table public.tasks add column if not exists type text default 'Feature'::text;

alter table public.tasks add column if not exists feature_id uuid;

alter table public.tasks add column if not exists vertical text default 'Development'::text;

alter table public.tasks add column if not exists test_case_id uuid;

alter table public.tasks add column if not exists description text default ''::text;

alter table public.tasks add column if not exists id uuid default gen_random_uuid();

alter table public.tasks add column if not exists source text default ''::text;

alter table public.tasks add column if not exists external_id text default ''::text;

alter table public.tasks add column if not exists evidence text default ''::text;

alter table public.tasks add column if not exists suggested_fix text default ''::text;

alter table public.tasks add column if not exists archived_by uuid;

alter table public.tasks add column if not exists tester_id uuid;

alter table public.tasks add column if not exists url text default ''::text;

alter table public.tasks add column if not exists page text default ''::text;

alter table public.tasks add column if not exists bug_type text default ''::text;

alter table public.tasks add column if not exists parent_id uuid;

alter table public.tasks add column if not exists reopen_count integer default 0;

alter table public.tasks add column if not exists qa_state text default ''::text;

alter table public.tasks add column if not exists estimate_hours numeric;

alter table public.tasks add column if not exists lead_id uuid;

alter table public.tasks add column if not exists deal_id uuid;

alter table public.tasks add column if not exists archived_at timestamp with time zone;

alter table public.tasks add column if not exists archived boolean default false;

alter table public.tasks add column if not exists mentions uuid[] default '{}'::uuid[];

alter table public.tasks add column if not exists reproducibility text default ''::text;

alter table public.tasks add column if not exists device text default ''::text;

alter table public.tasks add column if not exists build_version text default ''::text;

alter table public.tasks add column if not exists actual_result text default ''::text;

alter table public.tasks add column if not exists project_id uuid;

alter table public.tasks add column if not exists expected_result text default ''::text;

alter table public.tasks add column if not exists blocked_by uuid[] default '{}'::uuid[];

alter table public.tasks add column if not exists design_url text default ''::text;

alter table public.tasks add column if not exists pr_url text default ''::text;

alter table public.tasks add column if not exists branch text default ''::text;

alter table public.tasks add column if not exists checklist jsonb default '[]'::jsonb;

alter table public.tasks add column if not exists component text default ''::text;

alter table public.tasks add column if not exists labels text[] default '{}'::text[];

alter table public.tasks add column if not exists release_id uuid;

alter table public.tasks add column if not exists due_date date;

alter table public.tasks add column if not exists completed_at timestamp with time zone;

alter table public.tasks add column if not exists sprint_id uuid;

alter table public.tasks add column if not exists title text;

alter table public.tasks add column if not exists updated_at timestamp with time zone default now();

alter table public.tasks add column if not exists created_at timestamp with time zone default now();

alter table public.tasks add column if not exists blocked_reason text default ''::text;

alter table public.test_cases add column if not exists id uuid default gen_random_uuid();

alter table public.test_cases add column if not exists tester_id uuid;

alter table public.test_cases add column if not exists task_id uuid;

alter table public.test_cases add column if not exists assignee_id uuid;

alter table public.test_cases add column if not exists updated_at timestamp with time zone default now();

alter table public.test_cases add column if not exists created_at timestamp with time zone default now();

alter table public.test_cases add column if not exists created_by uuid default auth.uid();

alter table public.test_cases add column if not exists source text default ''::text;

alter table public.test_cases add column if not exists retest_count integer default 0;

alter table public.test_cases add column if not exists notes text default ''::text;

alter table public.test_cases add column if not exists feature_id uuid;

alter table public.test_cases add column if not exists evidence text default ''::text;

alter table public.test_cases add column if not exists platform text default ''::text;

alter table public.test_cases add column if not exists priority text default ''::text;

alter table public.test_cases add column if not exists test_type text default ''::text;

alter table public.test_cases add column if not exists status text default 'Not run'::text;

alter table public.test_cases add column if not exists actual text default ''::text;

alter table public.test_cases add column if not exists expected text default ''::text;

alter table public.test_cases add column if not exists steps text default ''::text;

alter table public.test_cases add column if not exists test_data text default ''::text;

alter table public.test_cases add column if not exists preconditions text default ''::text;

alter table public.test_cases add column if not exists external_id text default ''::text;

alter table public.test_cases add column if not exists number integer default nextval('test_case_number'::regclass);

alter table public.test_cases add column if not exists title text;

alter table public.test_cases add column if not exists project_id uuid;

alter table public.test_cases add column if not exists last_run_at timestamp with time zone;

alter table public.test_runs add column if not exists evidence text default ''::text;

alter table public.test_runs add column if not exists tester_id uuid default auth.uid();

alter table public.test_runs add column if not exists at timestamp with time zone default now();

alter table public.test_runs add column if not exists test_case_id uuid;

alter table public.test_runs add column if not exists status text;

alter table public.test_runs add column if not exists actual text default ''::text;

alter table public.tickets add column if not exists status text default 'Open'::text;

alter table public.tickets add column if not exists channel text default 'Email'::text;

alter table public.tickets add column if not exists created_by uuid default auth.uid();

alter table public.tickets add column if not exists created_at timestamp with time zone default now();

alter table public.tickets add column if not exists updated_at timestamp with time zone default now();

alter table public.tickets add column if not exists resolved_at timestamp with time zone;

alter table public.tickets add column if not exists project_id uuid;

alter table public.tickets add column if not exists assignee_id uuid;

alter table public.tickets add column if not exists id uuid default gen_random_uuid();

alter table public.tickets add column if not exists due_date date;

alter table public.tickets add column if not exists title text;

alter table public.tickets add column if not exists priority text default 'Medium'::text;

alter table public.tickets add column if not exists client_id uuid;

alter table public.tickets add column if not exists description text default ''::text;

alter table public.user_status add column if not exists note text default ''::text;

alter table public.user_status add column if not exists checkin_alerted_on date;

alter table public.user_status add column if not exists checked_in_at timestamp with time zone;

alter table public.user_status add column if not exists lunch_reminded_at timestamp with time zone;

alter table public.user_status add column if not exists idle_since timestamp with time zone;

alter table public.user_status add column if not exists state text default 'active'::text;

alter table public.user_status add column if not exists last_active_at timestamp with time zone default now();

alter table public.user_status add column if not exists updated_at timestamp with time zone default now();

alter table public.user_status add column if not exists leave_half boolean default false;

alter table public.user_status add column if not exists until timestamp with time zone;

alter table public.user_status add column if not exists leave_day date;

alter table public.user_status add column if not exists user_id uuid;

alter table public.user_status add column if not exists checkin_reminded_on date;

alter table public.user_status add column if not exists admins_alerted_at timestamp with time zone;

alter table public.user_status add column if not exists checked_out_at timestamp with time zone;

alter table public.work_logs add column if not exists created_at timestamp with time zone default now();

alter table public.work_logs add column if not exists minutes integer;

alter table public.work_logs add column if not exists task_id uuid;

alter table public.work_logs add column if not exists id uuid default gen_random_uuid();

alter table public.work_logs add column if not exists user_id uuid default auth.uid();

alter table public.work_logs add column if not exists work_date date default ((now() AT TIME ZONE 'Asia/Kolkata'::text))::date;

alter table public.work_logs add column if not exists note text default ''::text;

CREATE OR REPLACE FUNCTION public.can_chat(cid uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select public.is_active_user() and exists (
    select 1 from public.chat_channels c where c.id = cid and (
      (c.kind = 'channel' and (c.vertical is null or c.vertical = public.my_vertical() or public.is_admin()))
      or auth.uid() = any(c.members)))
$function$
;

CREATE OR REPLACE FUNCTION public.can_run_sprints()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select public.is_active_user() and (public.is_admin() or public.is_task_handler('Development') or public.perm(public.table_module('sprints')) >= 2)
$function$
;

CREATE OR REPLACE FUNCTION public.can_see(tbl text, rid uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public'
AS $function$
declare ok boolean;
begin
  if tbl = 'email_attachments' then
    return rid = auth.uid() or public.is_admin();
  end if;
  if tbl = 'chat' then
    return public.can_chat(rid);            -- files in a conversation: its members only
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
end $function$
;

CREATE OR REPLACE FUNCTION public.check_avatar_url()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if new.avatar_url is distinct from old.avatar_url and new.avatar_url <> ''
     and new.avatar_url !~ ('/storage/v1/object/public/avatars/' || new.id::text || '/') then
    raise exception 'That photo address isn’t allowed.' using errcode = '22023';
  end if;
  return new;
end $function$
;

CREATE OR REPLACE FUNCTION public.check_chat_attachments()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if tg_op = 'UPDATE' then
    if old.unsent_at is not null then raise exception 'This message was deleted.' using errcode = '42501'; end if;
    if current_setting('tcipher.unsend', true) is distinct from 'on' then new.attachments := old.attachments; new.unsent_at := old.unsent_at; end if;
    return new;
  end if;
  if jsonb_typeof(new.attachments) <> 'array' or jsonb_array_length(new.attachments) > 10 then
    raise exception 'Attach up to 10 files to a message.' using errcode = '22023';
  end if;
  if exists (select 1 from jsonb_array_elements(new.attachments) a
             where not exists (select 1 from public.files f where f.id::text = a->>'id' and f.tbl = 'chat'
                               and f.entity_id = new.channel_id and f.uploaded_by = new.author_id and f.path not like 'pending-%')) then
    raise exception 'A file in this message isn’t in this conversation, or hasn’t finished uploading.' using errcode = '42501';
  end if;
  new.attachments := coalesce((select jsonb_agg(jsonb_build_object('id', f.id, 'name', f.name, 'size', f.size, 'mime', f.mime) order by a.ord)
    from jsonb_array_elements(new.attachments) with ordinality a(v, ord) join public.files f on f.id::text = a.v->>'id'), '[]'::jsonb);
  new.unsent_at := null;
  return new;
end $function$
;

CREATE OR REPLACE FUNCTION public.check_chat_reply()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if tg_op = 'UPDATE' then new.reply_to := old.reply_to; return new; end if;
  if new.reply_to is not null and not exists (select 1 from public.chat_messages m where m.id = new.reply_to and m.channel_id = new.channel_id) then
    raise exception 'You can only reply to a message in the same conversation.' using errcode = '22023';
  end if;
  return new;
end $function$
;

CREATE OR REPLACE FUNCTION public.check_task_parent()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare par record;
begin
  if new.type = 'Epic' then new.parent_id := null; end if;
  if new.parent_id is null then
    if new.type = 'Subtask' then raise exception 'A subtask needs the task it belongs to.' using errcode = '22023'; end if;
    return new;
  end if;
  if new.parent_id = new.id then raise exception 'A task can’t be its own parent.' using errcode = '22023'; end if;
  select id, type, vertical, parent_id into par from public.tasks where id = new.parent_id;
  if not found then raise exception 'That parent task doesn’t exist.' using errcode = '22023'; end if;
  if par.vertical <> new.vertical then raise exception 'A task and its parent must be in the same vertical.' using errcode = '22023'; end if;
  if new.type = 'Subtask' and par.type in ('Epic', 'Subtask') then raise exception 'A subtask belongs to a task, not to an epic or another subtask.' using errcode = '22023'; end if;
  if new.type <> 'Subtask' and par.type <> 'Epic' then raise exception 'A task can only be put under an epic.' using errcode = '22023'; end if;
  return new;
end $function$
;

CREATE OR REPLACE FUNCTION public.cleanup_children()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  delete from public.comments where tbl = tg_table_name and entity_id = old.id;
  delete from public.files where tbl = tg_table_name and entity_id = old.id;
  return old;
end $function$
;

CREATE OR REPLACE FUNCTION public.clear_chat_notifications()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  update public.notifications set is_read = true where user_id = new.user_id and tbl = 'chat' and entity_id = new.channel_id and not is_read;
  return null;
end $function$
;

CREATE OR REPLACE FUNCTION public.complete_sprint(p_sprint uuid, p_move_to uuid DEFAULT NULL::uuid, p_new boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r public.sprints; target uuid := p_move_to; done_n int; moved int; nxt public.sprints;
begin
  if not public.can_run_sprints() then raise exception 'Only admins and task handlers can complete a sprint.' using errcode = '42501'; end if;
  select * into r from public.sprints where id = p_sprint for update;
  if not found then raise exception 'That sprint doesn’t exist.' using errcode = '22023'; end if;
  if r.status <> 'Active' then raise exception 'Only an active sprint can be completed.' using errcode = '22023'; end if;
  if p_new then nxt := public.create_sprint(''); target := nxt.id;
  elsif target is not null and not exists (select 1 from public.sprints s where s.id = target and s.status = 'Planned' and s.id <> p_sprint) then
    raise exception 'Open work can only move to a sprint that hasn’t started yet.' using errcode = '22023';
  end if;
  select count(*) into done_n from public.tasks where sprint_id = p_sprint and status = 'Done';
  -- the caller's own rights still apply to each task (task handlers and admins may move them)
  update public.tasks set sprint_id = target, updated_at = now() where sprint_id = p_sprint and status <> 'Done' and not coalesce(archived, false);
  get diagnostics moved = row_count;
  update public.sprints set status = 'Completed', end_date = least(coalesce(end_date, current_date), current_date), updated_at = now() where id = p_sprint;
  return jsonb_build_object('ok', true, 'done', done_n, 'moved', moved, 'moved_to', target);
end $function$
;

CREATE OR REPLACE FUNCTION public.create_sprint(p_name text DEFAULT ''::text)
 RETURNS sprints
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare n int; r public.sprints;
begin
  if not public.can_run_sprints() then raise exception 'Only admins and task handlers can create sprints.' using errcode = '42501'; end if;
  select count(*) + 1 into n from public.sprints;
  insert into public.sprints (name, status, created_by) values (coalesce(nullif(btrim(p_name), ''), 'Sprint ' || n), 'Planned', auth.uid()) returning * into r;
  return r;
end $function$
;

CREATE OR REPLACE FUNCTION public.day_history(p_day date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare lo timestamptz := (p_day::timestamp at time zone 'Asia/Kolkata'); hi timestamptz := ((p_day + 1)::timestamp at time zone 'Asia/Kolkata');
begin
  if not public.is_admin() then return null; end if;
  return coalesce((select jsonb_agg(jsonb_build_object(
    'user_id', p.id,
    'attendance', (select to_jsonb(a) - 'created_at' - 'updated_at' from public.attendance a where a.user_id = p.id and a.day = p_day),
    'leave', (select l.type from public.leave_requests l where l.user_id = p.id and l.status = 'Approved' and p_day between l.start_date and l.end_date limit 1),
    'events', coalesce((select jsonb_agg(jsonb_build_object('at', e.at, 'kind', e.kind, 'until', e.until, 'note', e.note) order by e.at) from public.status_events e where e.user_id = p.id and e.at >= lo and e.at < hi), '[]'::jsonb),
    'meetings', coalesce((select jsonb_agg(jsonb_build_object('title', m.title, 'joined_at', m.joined_at, 'left_at', m.left_at) order by m.joined_at) from public.meeting_joins m where m.user_id = p.id and m.joined_at >= lo and m.joined_at < hi), '[]'::jsonb),
    'tasks', coalesce((select jsonb_agg(jsonb_build_object('at', te.at, 'field', te.field, 'old', left(te.old_value, 80), 'new', left(te.new_value, 80), 'number', t.number, 'title', left(t.title, 120), 'task_id', t.id) order by te.at)
                       from public.task_events te join public.tasks t on t.id = te.task_id where te.actor_id = p.id and te.at >= lo and te.at < hi), '[]'::jsonb),
    'counts', jsonb_build_object(
      'messages', (select count(*) from public.chat_messages c where c.author_id = p.id and c.created_at >= lo and c.created_at < hi),
      'comments', (select count(*) from public.comments c where c.author_id = p.id and c.created_at >= lo and c.created_at < hi),
      'emails', (select count(*) from public.emails em where em.user_id = p.id and em.direction = 'out' and em.sent_at >= lo and em.sent_at < hi),
      'test_runs', (select count(*) from public.test_runs tr where tr.tester_id = p.id and tr.at >= lo and tr.at < hi)),
    'activity', coalesce((select jsonb_agg(x.at order by x.at) from (
        select c.created_at as at from public.chat_messages c where c.author_id = p.id and c.created_at >= lo and c.created_at < hi
        union all select c.created_at from public.comments c where c.author_id = p.id and c.created_at >= lo and c.created_at < hi
        union all select te.at from public.task_events te where te.actor_id = p.id and te.at >= lo and te.at < hi
        union all select em.sent_at from public.emails em where em.user_id = p.id and em.direction = 'out' and em.sent_at >= lo and em.sent_at < hi) x), '[]'::jsonb)
  ) order by p.full_name) from public.profiles p where p.is_active), '[]'::jsonb);
end $function$
;

CREATE OR REPLACE FUNCTION public.guard_dev_done()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if new.vertical is distinct from 'Development' or new.status is distinct from 'Done' then return new; end if;
  if tg_op = 'UPDATE' and old.status = 'Done' then return new; end if;
  if auth.uid() is null or public.is_admin() then return new; end if;
  if tg_op = 'INSERT' or old.status <> 'In review' then raise exception 'A task is finished only after QA approves it. Move it to QA first.' using errcode = '42501'; end if;
  if auth.uid() is distinct from old.tester_id then raise exception 'Only the task’s tester can approve it.' using errcode = '42501'; end if;
  return new;
end $function$
;

CREATE OR REPLACE FUNCTION public.handle_new_user()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
end $function$
;

CREATE OR REPLACE FUNCTION public.is_active_user()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select exists (select 1 from public.profiles where id = auth.uid() and is_active)
$function$
;

CREATE OR REPLACE FUNCTION public.is_admin()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select exists (select 1 from public.profiles where id = auth.uid() and is_active and is_admin)
$function$
;

CREATE OR REPLACE FUNCTION public.is_task_handler(v text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select public.is_admin() or exists (
    select 1 from public.settings s
    where s.id = 1 and coalesce(s.data->'task_handlers'->v, '[]'::jsonb) ? auth.uid()::text)
$function$
;

CREATE OR REPLACE FUNCTION public.keep_deleted_task()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  insert into public.deleted_records (tbl, entity_id, data, deleted_by)
  values ('tasks', old.id, to_jsonb(old) || jsonb_build_object('history', coalesce((select jsonb_agg(to_jsonb(e) order by e.at) from public.task_events e where e.task_id = old.id), '[]'::jsonb)), auth.uid());
  return old;
end $function$
;

CREATE OR REPLACE FUNCTION public.keep_via_email()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
begin
  if tg_op = 'INSERT' then
    if coalesce(current_setting('tcipher.via_email', true), '') <> 'on' then new.via_email := false; end if;
  else
    new.via_email := old.via_email;
  end if;
  return new;
end $function$
;

CREATE OR REPLACE FUNCTION public.keep_work_log_owner()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
begin
  new.task_id := old.task_id; new.user_id := old.user_id; new.created_at := old.created_at;
  return new;
end $function$
;

CREATE OR REPLACE FUNCTION public.leave_changed()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  perform set_config('tcipher.server', 'on', true);
  perform public.refresh_leave_status();
  perform set_config('tcipher.server', 'off', true);
  return null;
end $function$
;

CREATE OR REPLACE FUNCTION public.leave_chat(cid uuid)
 RETURNS void
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  update public.chat_channels set members = array_remove(members, auth.uid())
  where id = cid and kind = 'group' and auth.uid() = any(members)
$function$
;

CREATE OR REPLACE FUNCTION public.live_chat_signal()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  begin
    perform realtime.send(jsonb_build_object('cid', new.channel_id, 'mid', new.id, 'uid', new.author_id, 'edit', tg_op = 'UPDATE'),
                          'msg', 'chat:' || new.channel_id::text, true);
  exception when others then null;   -- a live signal must never stop a message being saved
  end;
  return null;
end $function$
;

CREATE OR REPLACE FUNCTION public.live_notify_signal()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  begin
    perform realtime.send(jsonb_build_object('id', new.id, 'tbl', new.tbl, 'entity_id', new.entity_id, 'title', new.title),
                          'notif', 'user:' || new.user_id::text, true);
  exception when others then null;
  end;
  return null;
end $function$
;

CREATE OR REPLACE FUNCTION public.live_reaction_signal()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r record;
begin
  if tg_op = 'DELETE' then r := old; else r := new; end if;
  begin
    perform realtime.send(jsonb_build_object('cid', r.channel_id, 'mid', r.message_id, 'uid', r.user_id, 'react', true), 'msg', 'chat:' || r.channel_id::text, true);
  exception when others then null;
  end;
  return null;
end $function$
;

CREATE OR REPLACE FUNCTION public.log_activity()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r jsonb; label text;
begin
  r := case when tg_op = 'DELETE' then to_jsonb(old) else to_jsonb(new) end;
  label := coalesce(r->>'title', r->>'name', r->>'subject', r->>'keyword', r->>'number', r->>'version', r->>'type', '');
  insert into public.activity_log (actor_id, tbl, action, entity_id, summary)
  values (auth.uid(), tg_table_name, lower(tg_op), nullif(r->>'id', '')::uuid, left(label, 200));
  return null;
end $function$
;

CREATE OR REPLACE FUNCTION public.log_record_change()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
end $function$
;

CREATE OR REPLACE FUNCTION public.log_settings_change()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if (old.data->'task_handlers') is distinct from (new.data->'task_handlers')
     or (old.data->'owners_can_update_status') is distinct from (new.data->'owners_can_update_status') then
    insert into public.activity_log (actor_id, tbl, action, summary)
    values (auth.uid(), 'settings', 'update', 'Task rules changed');
  end if;
  return null;
end $function$
;

CREATE OR REPLACE FUNCTION public.log_status_change()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if tg_op = 'INSERT' or new.state is distinct from old.state or new.until is distinct from old.until then
    insert into public.status_events (user_id, at, kind, until, note)
    values (new.user_id, case when new.state in ('idle', 'offline') then coalesce(new.idle_since, now()) else now() end, new.state, new.until, new.note);
  end if;
  return null;
end $function$
;

CREATE OR REPLACE FUNCTION public.log_task_change()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
end $function$
;

CREATE OR REPLACE FUNCTION public.log_task_comment_or_file()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
end $function$
;

CREATE OR REPLACE FUNCTION public.mail_sender_status()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select case when not public.is_admin() then null else coalesce((
    select jsonb_build_object(
      'email', s.google_email, 'connected_at', s.connected_at,
      'connected_by', (select full_name from public.profiles p where p.id = s.connected_by),
      'last_sent_at', s.last_sent_at, 'last_error', s.last_error,
      'sent_today', case when s.sent_day = (now() at time zone 'Asia/Kolkata')::date then s.sent_count else 0 end,
      'can_read', position('gmail.readonly' in s.scopes) > 0)
    from public.mail_sender s where s.id = 1 and s.refresh_token <> ''), '{}'::jsonb) end
$function$
;

CREATE OR REPLACE FUNCTION public.merge_comment_mentions()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if new.tbl = 'tasks' and cardinality(new.mentions) > 0 then
    update public.tasks t set mentions = array(select distinct x from unnest(t.mentions || new.mentions) as x)
    where t.id = new.entity_id;
  elsif new.tbl = 'notes' and cardinality(new.mentions) > 0 then
    update public.notes n set mentions = array(select distinct x from unnest(n.mentions || new.mentions) as x)
    where n.id = new.entity_id;
  end if;
  return new;
end $function$
;

CREATE OR REPLACE FUNCTION public.my_email()
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select lower(email) from public.profiles where id = auth.uid()
$function$
;

CREATE OR REPLACE FUNCTION public.my_vertical()
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select vertical from public.profiles where id = auth.uid()
$function$
;

CREATE OR REPLACE FUNCTION public.notify_chat_message()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare ch record; who uuid; author text; t text; targets uuid[];
begin
  select * into ch from public.chat_channels where id = new.channel_id;
  if not found then return null; end if;
  select full_name into author from public.profiles where id = new.author_id;
  author := coalesce(author, 'Someone');
  if ch.kind in ('dm', 'group') then targets := ch.members; else targets := new.mentions; end if;
  for who in select distinct x from unnest(coalesce(targets, '{}')) as x loop
    continue when who is null or who = new.author_id;
    -- a channel mention only reaches people who can see that channel
    if ch.kind = 'channel' and ch.vertical is not null and not exists (
      select 1 from public.profiles p where p.id = who and p.is_active and (p.is_admin or p.vertical = ch.vertical)) then
      continue;
    end if;
    t := case when ch.kind = 'dm' then 'Message from ' || author
              when ch.kind = 'group' then author || ' in ' || coalesce(nullif(ch.name, ''), 'a group')
              else author || ' mentioned you in #' || ch.name end;
    if exists (select 1 from public.notifications n where n.user_id = who and n.tbl = 'chat' and n.entity_id = new.channel_id and not n.is_read) then
      update public.notifications set title = t, body = left(coalesce(nullif(new.body, ''), '📎 ' || coalesce(new.attachments->0->>'name', 'a file')), 160), created_at = now()
        where user_id = who and tbl = 'chat' and entity_id = new.channel_id and not is_read;
    else
      insert into public.notifications (user_id, title, body, tbl, entity_id, created_by)
      values (who, t, left(coalesce(nullif(new.body, ''), '📎 ' || coalesce(new.attachments->0->>'name', 'a file')), 160), 'chat', new.channel_id, new.author_id);
    end if;
  end loop;
  return null;
end $function$
;

CREATE OR REPLACE FUNCTION public.perm(m text)
 RETURNS integer
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select coalesce((
    select case when p.is_admin then 3 else
      case coalesce(r.permissions->>m, 'none')
        when 'manage' then 3 when 'edit' then 2 when 'view' then 1 else 0 end
    end
    from public.profiles p left join public.roles r on r.id = p.role_id
    where p.id = auth.uid() and p.is_active
  ), 0)
$function$
;

CREATE OR REPLACE FUNCTION public.post_email_reply(p_token text, p_body text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare t record; p record; mid bigint; cid uuid; r jsonb; label text; body text;
begin
  select * into t from public.email_reply_tokens where token = p_token;
  if not found then return jsonb_build_object('error', 'unknown'); end if;
  if t.expires_at < now() then return jsonb_build_object('error', 'expired'); end if;
  select * into p from public.profiles where id = t.user_id;
  if not found or not p.is_active then return jsonb_build_object('error', 'inactive'); end if;
  body := left(btrim(coalesce(p_body, '')), 4000);
  if body = '' then return jsonb_build_object('error', 'empty'); end if;
  -- from here on, the database treats this as that person
  perform set_config('request.jwt.claim.sub', t.user_id::text, true);
  perform set_config('tcipher.via_email', 'on', true);
  if t.channel_id is not null then
    if not public.can_chat(t.channel_id) then return jsonb_build_object('error', 'no_access'); end if;
    insert into public.chat_messages (channel_id, author_id, body, via_email) values (t.channel_id, t.user_id, body, true) returning id into mid;
    insert into public.chat_reads (user_id, channel_id, last_read_id) values (t.user_id, t.channel_id, mid)
      on conflict (user_id, channel_id) do update set last_read_id = greatest(public.chat_reads.last_read_id, excluded.last_read_id);
    return jsonb_build_object('ok', true, 'kind', 'chat', 'id', mid, 'channel_id', t.channel_id);
  end if;
  if to_regclass('public.' || t.tbl) is null or not public.can_see(t.tbl, t.entity_id) then return jsonb_build_object('error', 'no_access'); end if;
  insert into public.comments (tbl, entity_id, body, author_id, via_email) values (t.tbl, t.entity_id, body, t.user_id, true) returning id into cid;
  -- replying counts as reading it
  update public.notifications set is_read = true where user_id = t.user_id and tbl = t.tbl and entity_id = t.entity_id and not is_read;
  -- tell the people on that item, like a comment posted in the app does
  execute format('select to_jsonb(x) from public.%I x where id = $1', t.tbl) into r using t.entity_id;
  label := case when t.tbl = 'tasks' and r ? 'number' then 'TC-' || (r->>'number') || ' ' else '' end || coalesce(r->>'title', r->>'name', 'an item');
  insert into public.notifications (user_id, title, body, tbl, entity_id, created_by)
  select x.id, p.full_name || ' commented on ' || label, left(body, 140), t.tbl, t.entity_id, t.user_id
  from (select distinct v::uuid as id from unnest(array[r->>'assignee_id', r->>'reviewer_id', r->>'owner_id', r->>'sales_owner_id', r->>'manager_id', r->>'created_by', r->>'user_id']
          || coalesce(array(select jsonb_array_elements_text(case when jsonb_typeof(r->'collaborators') = 'array' then r->'collaborators' else '[]'::jsonb end)), '{}')) as v
        where v is not null and v <> '') x
  where x.id <> t.user_id and exists (select 1 from public.profiles q where q.id = x.id and q.is_active);
  return jsonb_build_object('ok', true, 'kind', 'comment', 'id', cid, 'tbl', t.tbl, 'entity_id', t.entity_id);
end $function$
;

CREATE OR REPLACE FUNCTION public.presence_watch(p_now timestamp with time zone DEFAULT now())
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  s jsonb; lt timestamp; d date; ws time; we time;
  warn int; grace int; alert_after int; remind int; watch_admins boolean;
  admins uuid[]; r record; st public.user_status; last timestamptz; idle_min numeric;
  n_off int := 0; n_alert int := 0; n_remind int := 0;
begin
  select coalesce(data, '{}'::jsonb) into s from public.settings where id = 1;
  s := coalesce(s, '{}'::jsonb);
  lt := p_now at time zone 'Asia/Kolkata'; d := lt::date;
  perform set_config('tcipher.server', 'on', true);
  if to_regprocedure('public.refresh_leave_status()') is not null then perform public.refresh_leave_status(); end if;
  ws := coalesce(nullif(s->>'work_start', ''), '10:00')::time; we := coalesce(nullif(s->>'work_end', ''), '18:00')::time;
  if not (coalesce(s->'working_days', '[1,2,3,4,5,6]'::jsonb) @> to_jsonb(extract(dow from lt)::int)) then return jsonb_build_object('skipped', 'not a working day'); end if;
  if exists (select 1 from jsonb_array_elements(coalesce(s->'holidays', '[]'::jsonb)) h where h->>'date' = d::text) then return jsonb_build_object('skipped', 'holiday'); end if;
  if lt::time < ws or lt::time >= we then return jsonb_build_object('skipped', 'outside working hours'); end if;
  warn := coalesce((s->>'idle_warn_min')::int, 30); grace := coalesce((s->>'offline_grace_min')::int, 5);
  alert_after := coalesce((s->>'admin_alert_min')::int, 60); remind := coalesce((s->>'checkin_remind_min')::int, 30);
  watch_admins := coalesce((s->>'watch_admins')::boolean, false);
  admins := array(select id from public.profiles where is_admin and is_active);

  for r in
    select p.id, p.full_name, p.is_admin, a.check_in, a.check_out, a.status as att_status
    from public.profiles p
    left join public.attendance a on a.user_id = p.id and a.day = d
    where p.is_active and (watch_admins or not p.is_admin)
      and not exists (select 1 from public.leave_requests l where l.user_id = p.id and l.status = 'Approved'
                      and d between l.start_date and l.end_date and l.type <> 'Work from home')
      and coalesce(a.status, '') <> 'Absent'
  loop
    insert into public.user_status (user_id, last_active_at) values (r.id, p_now - interval '1 minute') on conflict (user_id) do nothing;
    select * into st from public.user_status where user_id = r.id;

    -- not checked in yet: remind them, then tell the admins
    if r.check_in is null then
      if lt::time >= ws + make_interval(mins => remind) and st.checkin_reminded_on is distinct from d then
        insert into public.notifications (user_id, title, body) values (r.id, 'You haven’t checked in yet', 'Check in on Home or in Attendance, or set yourself out of office.');
        update public.user_status set checkin_reminded_on = d where user_id = r.id;
        insert into public.status_events (user_id, at, kind) values (r.id, p_now, 'checkin_reminder');
        n_remind := n_remind + 1;
      end if;
      if lt::time >= ws + make_interval(mins => alert_after) and st.checkin_alerted_on is distinct from d then
        insert into public.notifications (user_id, title, body, tbl, entity_id)
        select unnest(admins), r.full_name || ' hasn’t checked in', 'It’s ' || to_char(lt, 'FMHH12:MI am') || ' and there’s no check-in yet today.', 'team-day', r.id;
        update public.user_status set checkin_alerted_on = d where user_id = r.id;
        n_alert := n_alert + 1;
      end if;
      continue;
    end if;
    if r.check_out is not null then continue; end if;

    -- out of office or at lunch until a time: nothing to check until then
    if st.state in ('ooo', 'lunch') and st.until > p_now then continue; end if;
    last := greatest(st.last_active_at, r.check_in, case when st.state in ('ooo', 'lunch') then st.until end);
    if st.state = 'lunch' and st.until <= p_now and (st.lunch_reminded_at is null or st.lunch_reminded_at < st.until) then
      insert into public.notifications (user_id, title, body) values (r.id, 'Your lunch break is over', 'It ended at ' || to_char(st.until at time zone 'Asia/Kolkata', 'FMHH12:MI am') || '. Click I’m back when you’re at your desk.');
      update public.user_status set lunch_reminded_at = p_now where user_id = r.id;
      insert into public.status_events (user_id, at, kind) values (r.id, p_now, 'lunch_over');
      n_remind := n_remind + 1;
    end if;
    if st.state = 'ooo' and st.until <= p_now then
      update public.user_status set state = 'idle', idle_since = st.until, until = null, note = '' where user_id = r.id;
    end if;

    idle_min := extract(epoch from (p_now - last)) / 60;
    -- inactive past the warning and its grace: offline
    if idle_min >= warn + grace and st.state not in ('offline', 'lunch') then
      update public.user_status set state = 'offline', idle_since = last, until = null where user_id = r.id;
      n_off := n_off + 1;
    end if;
    -- inactive for an hour: tell every admin, once per stretch
    if idle_min >= alert_after and (st.admins_alerted_at is null or st.admins_alerted_at < last) then
      insert into public.notifications (user_id, title, body, tbl, entity_id)
      select unnest(admins), 'No activity from ' || r.full_name || ' for over ' || (floor(idle_min / 60))::int || ' hour' || case when floor(idle_min / 60) >= 2 then 's' else '' end,
             'Last active at ' || to_char(last at time zone 'Asia/Kolkata', 'FMHH12:MI am') || '.', 'team-day', r.id;
      update public.user_status set admins_alerted_at = p_now where user_id = r.id;
      insert into public.status_events (user_id, at, kind, note) values (r.id, p_now, 'admin_alert', 'inactive since ' || to_char(last at time zone 'Asia/Kolkata', 'FMHH12:MI am'));
      n_alert := n_alert + 1;
    end if;
  end loop;
  -- keep six months of history
  delete from public.status_events where at < p_now - interval '183 days';
  return jsonb_build_object('marked_offline', n_off, 'admin_alerts', n_alert, 'reminders', n_remind);
end $function$
;

CREATE OR REPLACE FUNCTION public.protect_attendance()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
end $function$
;

CREATE OR REPLACE FUNCTION public.protect_attendance_insert()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if auth.uid() is not null and public.perm('attendance') < 2 and (new.marked_by is not null or new.status <> 'Present') then
    raise exception 'Only an admin can mark attendance for this.' using errcode = '42501';
  end if;
  return new;
end $function$
;

CREATE OR REPLACE FUNCTION public.protect_chat_edit()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
begin
  if new.channel_id <> old.channel_id or new.author_id is distinct from old.author_id or new.created_at <> old.created_at then
    raise exception 'Only the message text can be changed.' using errcode = '42501';
  end if;
  new.edited_at := now();
  return new;
end $function$
;

CREATE OR REPLACE FUNCTION public.protect_profile()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
end $function$
;

CREATE OR REPLACE FUNCTION public.protect_task_fields()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare work text[] := array['status','checklist','blocked','blocked_reason','branch','pr_url','completed_at','updated_at','mentions','tester_id'];
begin
  if auth.uid() is null or public.is_task_handler(old.vertical) then return new; end if;
  -- a Development task's owners may change its title, notes and owners through task_edit (2026-11ad)
  if coalesce(current_setting('tcipher.task_owner_edit', true), '') = 'on' then return new; end if;
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
end $function$
;

CREATE OR REPLACE FUNCTION public.protect_test_case()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  new.updated_at := now();
  if auth.uid() is null or public.perm('qa') >= 3 then return new; end if;
  if new.status is distinct from old.status and not (new.status = 'Retest' and old.status in ('Fail','Blocked')) then
    raise exception 'Only a tester can pass or fail a test case. When your fix is ready, mark it Retest.' using errcode = '42501';
  end if;
  if (new.title, new.steps, new.expected, new.feature_id, new.project_id, new.tester_id, new.assignee_id)
     is distinct from (old.title, old.steps, old.expected, old.feature_id, old.project_id, old.tester_id, old.assignee_id) then
    raise exception 'Only a tester can change a test case. You can add notes and mark it Retest.' using errcode = '42501';
  end if;
  return new;
end $function$
;

CREATE OR REPLACE FUNCTION public.protect_user_status()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  new.updated_at := now();
  if auth.uid() is not null and current_setting('tcipher.server', true) is distinct from 'on' then
    if tg_op = 'UPDATE' then
      new.admins_alerted_at := old.admins_alerted_at; new.lunch_reminded_at := old.lunch_reminded_at;
      new.checkin_reminded_on := old.checkin_reminded_on; new.checkin_alerted_on := old.checkin_alerted_on;
      new.leave_day := old.leave_day; new.leave_half := old.leave_half;
      new.checked_in_at := old.checked_in_at; new.checked_out_at := old.checked_out_at;
    else
      new.admins_alerted_at := null; new.lunch_reminded_at := null; new.checkin_reminded_on := null; new.checkin_alerted_on := null;
      new.leave_day := null; new.leave_half := false; new.checked_in_at := null; new.checked_out_at := null;
    end if;
    if new.last_active_at > now() + interval '1 minute' then new.last_active_at := now(); end if;
  end if;
  return new;
end $function$
;

CREATE OR REPLACE FUNCTION public.refresh_leave_status()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare d date := (now() at time zone 'Asia/Kolkata')::date;
begin
  insert into public.user_status (user_id, last_active_at)
  select l.user_id, now() - interval '1 day' from public.leave_requests l
   where l.status = 'Approved' and d between l.start_date and l.end_date and l.type <> 'Work from home'
  on conflict (user_id) do nothing;
  update public.user_status us set leave_day = null, leave_half = false
   where us.leave_day is not null and not exists (select 1 from public.leave_requests l where l.user_id = us.user_id and l.status = 'Approved' and d between l.start_date and l.end_date and l.type <> 'Work from home');
  update public.user_status us set leave_day = d, leave_half = coalesce(l.half_day, false)
    from public.leave_requests l
   where l.user_id = us.user_id and l.status = 'Approved' and d between l.start_date and l.end_date and l.type <> 'Work from home'
     and (us.leave_day is distinct from d or us.leave_half is distinct from coalesce(l.half_day, false));
end $function$
;

CREATE OR REPLACE FUNCTION public.set_lead_number()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
begin
  if new.lead_number is null or new.lead_number = '' then
    new.lead_number := 'LD-' || lpad(nextval('public.lead_number_seq')::text, 4, '0');
  end if;
  return new;
end $function$
;

CREATE OR REPLACE FUNCTION public.set_reaction_channel()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  select channel_id into new.channel_id from public.chat_messages where id = new.message_id;
  if new.channel_id is null then raise exception 'Message not found.' using errcode = '22023'; end if;
  return new;
end $function$
;

CREATE OR REPLACE FUNCTION public.set_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$ begin new.updated_at := now(); return new; end $function$
;

CREATE OR REPLACE FUNCTION public.start_sprint(p_sprint uuid, p_name text, p_start date, p_end date, p_goal text DEFAULT ''::text)
 RETURNS sprints
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r public.sprints;
begin
  if not public.can_run_sprints() then raise exception 'Only admins and task handlers can start a sprint.' using errcode = '42501'; end if;
  select * into r from public.sprints where id = p_sprint for update;
  if not found then raise exception 'That sprint doesn’t exist.' using errcode = '22023'; end if;
  if r.status <> 'Planned' then raise exception 'This sprint has already started.' using errcode = '22023'; end if;
  if p_start is null or p_end is null or p_end < p_start then raise exception 'Choose a start date and an end date after it.' using errcode = '22023'; end if;
  update public.sprints set name = coalesce(nullif(btrim(p_name), ''), name), start_date = p_start, end_date = p_end, goal = coalesce(p_goal, ''), status = 'Active', updated_at = now()
    where id = p_sprint returning * into r;
  return r;
end $function$
;

CREATE OR REPLACE FUNCTION public.storage_usage()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select case when public.is_admin() then jsonb_build_object(
    'supabase_files', count(*) filter (where storage = 'supabase'),
    'supabase_bytes', coalesce(sum(size) filter (where storage = 'supabase'), 0),
    'drive_files', count(*) filter (where storage = 'drive'),
    'drive_bytes', coalesce(sum(size) filter (where storage = 'drive'), 0),
    'database_bytes', pg_database_size(current_database()))
  else null end
  from public.files
$function$
;

CREATE OR REPLACE FUNCTION public.sync_attendance_status()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if new.day <> (now() at time zone 'Asia/Kolkata')::date then return null; end if;
  perform set_config('tcipher.server', 'on', true);
  insert into public.user_status (user_id, state, last_active_at, checked_in_at, checked_out_at)
  values (new.user_id, 'active', coalesce(new.check_in, now()), new.check_in, new.check_out)
  on conflict (user_id) do update set checked_in_at = excluded.checked_in_at, checked_out_at = excluded.checked_out_at,
    state = case when excluded.checked_out_at is null and public.user_status.state in ('idle', 'offline') and excluded.checked_in_at is not null then 'active' else public.user_status.state end,
    last_active_at = greatest(public.user_status.last_active_at, coalesce(excluded.checked_in_at, public.user_status.last_active_at));
  perform set_config('tcipher.server', 'off', true);
  return null;
end $function$
;

CREATE OR REPLACE FUNCTION public.table_module(tbl text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
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
$function$
;

CREATE OR REPLACE FUNCTION public.task_edit(p_task uuid, p_title text DEFAULT NULL::text, p_description text DEFAULT NULL::text, p_owners uuid[] DEFAULT NULL::uuid[])
 RETURNS tasks
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare t public.tasks; me uuid := auth.uid();
begin
  if me is null or not public.is_active_user() then raise exception 'Please sign in again.' using errcode = '42501'; end if;
  select * into t from public.tasks where id = p_task for update;
  if not found or not public.can_see('tasks', p_task) then raise exception 'That task isn’t available.' using errcode = '22023'; end if;
  if t.vertical <> 'Development' then raise exception 'This is only for Development tasks.' using errcode = '22023'; end if;
  if not (coalesce(me = t.assignee_id, false) or coalesce(me = any(coalesce(t.collaborators, '{}')), false) or public.is_admin() or public.is_task_handler('Development')) then
    raise exception 'Only the task’s owners can change it.' using errcode = '42501';
  end if;
  if p_title is not null and length(btrim(p_title)) = 0 then raise exception 'The title can’t be empty.' using errcode = '22023'; end if;
  if p_owners is not null and exists (select 1 from unnest(p_owners) o where not exists (select 1 from public.profiles p where p.id = o and p.is_active)) then
    raise exception 'One of those people isn’t available.' using errcode = '22023';
  end if;
  perform set_config('tcipher.task_owner_edit', 'on', true);
  update public.tasks set
    title = coalesce(nullif(btrim(p_title), ''), title),
    description = coalesce(p_description, description),
    assignee_id = case when p_owners is null then assignee_id else p_owners[1] end,
    collaborators = case when p_owners is null then collaborators else coalesce(p_owners[2:], '{}') end
  where id = p_task returning * into t;
  perform set_config('tcipher.task_owner_edit', '', true);
  return t;
end $function$
;

CREATE OR REPLACE FUNCTION public.task_flow(p_task uuid, p_action text, p_reason text DEFAULT ''::text, p_user uuid DEFAULT NULL::uuid)
 RETURNS tasks
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare t public.tasks; me uuid := auth.uid(); owner boolean; tester boolean; adm boolean;
begin
  if me is null or not public.is_active_user() then raise exception 'Please sign in again.' using errcode = '42501'; end if;
  select * into t from public.tasks where id = p_task for update;
  if not found or not public.can_see('tasks', p_task) then raise exception 'That task isn’t available.' using errcode = '22023'; end if;
  if t.vertical <> 'Development' then raise exception 'This is only for Development tasks.' using errcode = '22023'; end if;
  -- (null-safe: a task with no owner or no tester must never count as "yours")
  owner := coalesce(me = t.assignee_id, false) or coalesce(me = any(coalesce(t.collaborators, '{}')), false);
  tester := public.perm('qa') >= 3;
  adm := public.is_admin();
  if p_action = 'start' then
    if not (owner or adm) then raise exception 'Only the task’s owners can start it.' using errcode = '42501'; end if;
    if t.status <> 'To do' then raise exception 'This task has already started.' using errcode = '22023'; end if;
    update public.tasks set status = 'In progress' where id = p_task returning * into t;
  elsif p_action = 'to_qa' then
    if not (owner or adm) then raise exception 'Only the task’s owners can move it to QA.' using errcode = '42501'; end if;
    if t.status not in ('To do', 'In progress') then raise exception 'This task is already in QA or done.' using errcode = '22023'; end if;
    update public.tasks set status = 'In review' where id = p_task returning * into t;
  elsif p_action = 'pick_up' then
    if not tester then raise exception 'Only testers can pick up a task.' using errcode = '42501'; end if;
    if t.status <> 'In review' then raise exception 'This task isn’t waiting for QA.' using errcode = '22023'; end if;
    if t.tester_id is not null and t.tester_id <> me then raise exception 'Another tester already has this task.' using errcode = '22023'; end if;
    update public.tasks set tester_id = me where id = p_task returning * into t;
  elsif p_action = 'set_tester' then
    if not (owner or adm) then raise exception 'Only the task’s owners or an admin can choose the tester.' using errcode = '42501'; end if;
    if p_user is not null and not exists (select 1 from public.profiles where id = p_user and is_active) then raise exception 'That person isn’t available.' using errcode = '22023'; end if;
    update public.tasks set tester_id = p_user where id = p_task returning * into t;
  elsif p_action = 'approve' then
    if not (t.tester_id is not distinct from me and t.tester_id is not null or adm) then raise exception 'Only the task’s tester can approve it.' using errcode = '42501'; end if;
    if t.status <> 'In review' then raise exception 'Only a task in QA can be approved.' using errcode = '22023'; end if;
    update public.tasks set status = 'Done', completed_at = now() where id = p_task returning * into t;
  elsif p_action = 'back' then
    if not (t.tester_id is not distinct from me and t.tester_id is not null or adm) then raise exception 'Only the task’s tester can send it back.' using errcode = '42501'; end if;
    if t.status <> 'In review' then raise exception 'Only a task in QA can be sent back.' using errcode = '22023'; end if;
    if length(btrim(coalesce(p_reason, ''))) < 3 then raise exception 'Write a short reason, so the developer knows what to fix.' using errcode = '22023'; end if;
    update public.tasks set status = 'In progress' where id = p_task returning * into t;
    insert into public.comments (tbl, entity_id, body, author_id) values ('tasks', p_task, 'Sent back to development: ' || btrim(p_reason), me);
  else
    raise exception 'Unknown step.' using errcode = '22023';
  end if;
  return t;
end $function$
;

CREATE OR REPLACE FUNCTION public.task_workers_can_update()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select coalesce((select (data->>'owners_can_update_status')::boolean from public.settings where id = 1), true)
$function$
;

CREATE OR REPLACE FUNCTION public.touch_last_contacted()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if new.lead_id is not null then update public.leads set last_contacted_at = greatest(coalesce(last_contacted_at, 'epoch'), now()) where id = new.lead_id; end if;
  if new.deal_id is not null then update public.deals set last_contacted_at = greatest(coalesce(last_contacted_at, 'epoch'), now()) where id = new.deal_id; end if;
  return null;
end $function$
;

CREATE OR REPLACE FUNCTION public.touch_profile_private()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
begin
  new.personal_email := lower(trim(new.personal_email));
  new.updated_at := now();
  return new;
end $function$
;

CREATE OR REPLACE FUNCTION public.track_qa_stage()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare t uuid;
begin
  if new.vertical is distinct from 'Development' then return new; end if;
  if tg_op = 'UPDATE' and new.status is not distinct from old.status then return new; end if;
  if new.status = 'In review' then
    new.qa_state := case when tg_op = 'UPDATE' and old.qa_state in ('Failed', 'Retest') then 'Retest' else 'Waiting for QA' end;
    if new.tester_id is null then
      select coalesce(f.tester_id, p.qa_lead_id) into t
        from public.projects p left join public.features f on f.id = new.feature_id
        where p.id = new.project_id;
      if t is null and new.feature_id is not null then select f.tester_id into t from public.features f where f.id = new.feature_id; end if;
      new.tester_id := t;
    end if;
    new.reviewer_id := coalesce(new.tester_id, new.reviewer_id);
  elsif tg_op = 'UPDATE' and old.status = 'In review' and new.status = 'Done' then
    new.qa_state := case when old.qa_state <> '' then 'Passed' else old.qa_state end;
  elsif tg_op = 'UPDATE' and old.status = 'In review' and new.status in ('In progress', 'To do') and old.qa_state <> '' then
    new.qa_state := 'Failed';
    new.reopen_count := coalesce(old.reopen_count, 0) + 1;
  end if;
  return new;
end $function$
;

CREATE OR REPLACE FUNCTION public.unsend_message(p_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare m public.chat_messages;
begin
  select * into m from public.chat_messages where id = p_id;
  if m.id is null or m.author_id is distinct from auth.uid() then raise exception 'You can only delete your own messages for everyone.' using errcode = '42501'; end if;
  if m.unsent_at is not null then return jsonb_build_object('ok', true, 'files', '[]'::jsonb); end if;
  delete from public.chat_reactions where message_id = p_id;
  delete from public.chat_hidden where message_id = p_id;
  if m.body <> '' then
    delete from public.notifications where tbl = 'chat' and entity_id = m.channel_id and created_at >= m.created_at and body = left(m.body, 160);
  end if;
  perform set_config('tcipher.unsend', 'on', true);
  update public.chat_messages set body = '', attachments = '[]'::jsonb, mentions = '{}', unsent_at = now() where id = p_id;
  perform set_config('tcipher.unsend', 'off', true);
  return jsonb_build_object('ok', true, 'files', m.attachments);
end $function$
;

CREATE OR REPLACE FUNCTION public.work_files_open()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select coalesce((select (data->>'files_visible_all')::boolean from public.settings where id = 1), true)
$function$
;

do $x$ begin alter table public.activities add constraint activities_pkey PRIMARY KEY (id); exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.activity_log add constraint activity_log_pkey PRIMARY KEY (id); exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.announcements add constraint announcements_pkey PRIMARY KEY (id); exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.attendance add constraint attendance_pkey PRIMARY KEY (id); exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.attendance add constraint attendance_status_check CHECK ((status = ANY (ARRAY['Present'::text, 'Half day'::text, 'Absent'::text]))); exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.attendance add constraint attendance_user_id_day_key UNIQUE (user_id, day); exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.calendar_events add constraint calendar_events_pkey PRIMARY KEY (id); exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.calendar_events add constraint calendar_events_user_id_google_event_id_key UNIQUE (user_id, google_event_id); exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.campaigns add constraint campaigns_pkey PRIMARY KEY (id); exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.chat_channels add constraint chat_channels_dm_key_key UNIQUE (dm_key); exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.chat_channels add constraint chat_channels_kind_check CHECK ((kind = ANY (ARRAY['channel'::text, 'dm'::text, 'group'::text]))); exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.chat_channels add constraint chat_channels_pkey PRIMARY KEY (id); exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.chat_email_log add constraint chat_email_log_pkey PRIMARY KEY (user_id, channel_id); exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.chat_hidden add constraint chat_hidden_pkey PRIMARY KEY (user_id, message_id); exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.chat_messages add constraint chat_messages_body_check CHECK (((length(body) <= 4000) AND ((length(body) >= 1) OR (jsonb_array_length(attachments) > 0) OR (unsent_at IS NOT NULL)))) NOT VALID; exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.chat_messages add constraint chat_messages_pkey PRIMARY KEY (id); exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.chat_mutes add constraint chat_mutes_pkey PRIMARY KEY (user_id, channel_id); exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.chat_reactions add constraint chat_reactions_emoji_check CHECK (((char_length(emoji) >= 1) AND (char_length(emoji) <= 16))); exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.chat_reactions add constraint chat_reactions_pkey PRIMARY KEY (message_id, user_id, emoji); exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.chat_reads add constraint chat_reads_pkey PRIMARY KEY (user_id, channel_id); exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.clients add constraint clients_pkey PRIMARY KEY (id); exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.comments add constraint comments_pkey PRIMARY KEY (id); exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.contacts add constraint contacts_pkey PRIMARY KEY (id); exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.content add constraint content_pkey PRIMARY KEY (id); exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.deals add constraint deals_pkey PRIMARY KEY (id); exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.deleted_records add constraint deleted_records_pkey PRIMARY KEY (id); exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.documents add constraint documents_pkey PRIMARY KEY (id); exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.email_reply_log add constraint email_reply_log_pkey PRIMARY KEY (gmail_message_id); exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.email_reply_tokens add constraint email_reply_tokens_check CHECK (((channel_id IS NOT NULL) OR ((tbl IS NOT NULL) AND (entity_id IS NOT NULL)))); exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.email_reply_tokens add constraint email_reply_tokens_pkey PRIMARY KEY (token); exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.emails add constraint emails_direction_check CHECK ((direction = ANY (ARRAY['out'::text, 'in'::text]))); exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.emails add constraint emails_gmail_message_id_key UNIQUE (gmail_message_id); exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.emails add constraint emails_pkey PRIMARY KEY (id); exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.features add constraint features_pkey PRIMARY KEY (id); exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.files add constraint files_path_key UNIQUE (path); exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.files add constraint files_pkey PRIMARY KEY (id); exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.files add constraint files_storage_check CHECK ((storage = ANY (ARRAY['supabase'::text, 'drive'::text, 'bunny'::text]))); exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.google_links add constraint google_links_pkey PRIMARY KEY (user_id); exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.google_tokens add constraint google_tokens_pkey PRIMARY KEY (user_id); exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.leads add constraint leads_pkey PRIMARY KEY (id); exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.leave_requests add constraint leave_requests_pkey PRIMARY KEY (id); exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.mail_sender add constraint mail_sender_id_check CHECK ((id = 1)); exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.mail_sender add constraint mail_sender_pkey PRIMARY KEY (id); exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.meeting_joins add constraint meeting_joins_external_id_key UNIQUE (external_id); exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.meeting_joins add constraint meeting_joins_pkey PRIMARY KEY (id); exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.meetings add constraint meetings_pkey PRIMARY KEY (id); exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.notes add constraint notes_pkey PRIMARY KEY (id); exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.notes add constraint notes_visibility_check CHECK ((visibility = ANY (ARRAY['Private'::text, 'People'::text, 'Vertical'::text, 'Company'::text]))); exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.notifications add constraint notifications_pkey PRIMARY KEY (id); exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.presence add constraint presence_pkey PRIMARY KEY (user_id); exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.problem_reports add constraint problem_reports_kind_check CHECK ((kind = ANY (ARRAY['user'::text, 'auto'::text]))); exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.problem_reports add constraint problem_reports_pkey PRIMARY KEY (id); exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.problem_reports add constraint problem_reports_size_check CHECK (((length(message) <= 4000) AND (length(note) <= 4000))); exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.problem_reports add constraint problem_reports_status_check CHECK ((status = ANY (ARRAY['Open'::text, 'Fixed'::text, 'Ignored'::text]))); exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.profile_private add constraint profile_private_personal_email_check CHECK (((length(personal_email) <= 200) AND ((personal_email = ''::text) OR (personal_email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$'::text)))); exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.profile_private add constraint profile_private_pkey PRIMARY KEY (user_id); exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.profiles add constraint profiles_email_notifications_check CHECK ((email_notifications = ANY (ARRAY['all'::text, 'direct'::text, 'off'::text]))); exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.profiles add constraint profiles_pkey PRIMARY KEY (id); exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.profiles add constraint profiles_vertical_check CHECK ((vertical = ANY (ARRAY['Development'::text, 'Sales'::text, 'Marketing'::text]))); exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.projects add constraint projects_pkey PRIMARY KEY (id); exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.proposals add constraint proposals_pkey PRIMARY KEY (id); exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.record_events add constraint record_events_pkey PRIMARY KEY (id); exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.releases add constraint releases_pkey PRIMARY KEY (id); exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.roles add constraint roles_name_key UNIQUE (name); exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.roles add constraint roles_pkey PRIMARY KEY (id); exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.seo_keywords add constraint seo_keywords_pkey PRIMARY KEY (id); exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.settings add constraint settings_id_check CHECK ((id = 1)); exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.settings add constraint settings_pkey PRIMARY KEY (id); exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.social_stats add constraint social_stats_channel_month_key UNIQUE (channel, month); exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.social_stats add constraint social_stats_pkey PRIMARY KEY (id); exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.sprints add constraint sprints_pkey PRIMARY KEY (id); exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.status_events add constraint status_events_pkey PRIMARY KEY (id); exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.targets add constraint targets_pkey PRIMARY KEY (id); exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.targets add constraint targets_user_id_month_key UNIQUE (user_id, month); exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.task_events add constraint task_events_pkey PRIMARY KEY (id); exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.tasks add constraint tasks_pkey PRIMARY KEY (id); exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.tasks add constraint tasks_vertical_check CHECK ((vertical = ANY (ARRAY['Development'::text, 'Sales'::text, 'Marketing'::text]))); exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.test_cases add constraint test_cases_pkey PRIMARY KEY (id); exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.test_cases add constraint test_cases_status_check CHECK ((status = ANY (ARRAY['Not run'::text, 'Pass'::text, 'Fail'::text, 'Blocked'::text, 'Pending'::text, 'Retest'::text]))); exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.test_runs add constraint test_runs_pkey PRIMARY KEY (id); exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.tickets add constraint tickets_pkey PRIMARY KEY (id); exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.user_status add constraint user_status_pkey PRIMARY KEY (user_id); exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.user_status add constraint user_status_state_check CHECK ((state = ANY (ARRAY['active'::text, 'idle'::text, 'offline'::text, 'lunch'::text, 'ooo'::text]))); exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.work_logs add constraint work_logs_minutes_check CHECK (((minutes >= 1) AND (minutes <= 1440))); exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.work_logs add constraint work_logs_note_check CHECK ((length(note) <= 500)); exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.work_logs add constraint work_logs_pkey PRIMARY KEY (id); exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.activities add constraint activities_client_id_fkey FOREIGN KEY (client_id) REFERENCES clients(id) ON DELETE SET NULL; exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.activities add constraint activities_contact_id_fkey FOREIGN KEY (contact_id) REFERENCES contacts(id) ON DELETE SET NULL; exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.activities add constraint activities_created_by_fkey FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE SET NULL; exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.activities add constraint activities_deal_id_fkey FOREIGN KEY (deal_id) REFERENCES deals(id) ON DELETE SET NULL; exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.activities add constraint activities_lead_id_fkey FOREIGN KEY (lead_id) REFERENCES leads(id) ON DELETE SET NULL; exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.activities add constraint activities_owner_id_fkey FOREIGN KEY (owner_id) REFERENCES profiles(id) ON DELETE SET NULL; exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.activity_log add constraint activity_log_actor_id_fkey FOREIGN KEY (actor_id) REFERENCES profiles(id) ON DELETE SET NULL; exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.announcements add constraint announcements_created_by_fkey FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE SET NULL; exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.attendance add constraint attendance_marked_by_fkey FOREIGN KEY (marked_by) REFERENCES profiles(id) ON DELETE SET NULL; exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.attendance add constraint attendance_user_id_fkey FOREIGN KEY (user_id) REFERENCES profiles(id) ON DELETE CASCADE; exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.calendar_events add constraint calendar_events_user_id_fkey FOREIGN KEY (user_id) REFERENCES profiles(id) ON DELETE CASCADE; exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.campaigns add constraint campaigns_created_by_fkey FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE SET NULL; exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.campaigns add constraint campaigns_owner_id_fkey FOREIGN KEY (owner_id) REFERENCES profiles(id) ON DELETE SET NULL; exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.chat_channels add constraint chat_channels_created_by_fkey FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE SET NULL; exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.chat_email_log add constraint chat_email_log_channel_id_fkey FOREIGN KEY (channel_id) REFERENCES chat_channels(id) ON DELETE CASCADE; exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.chat_email_log add constraint chat_email_log_user_id_fkey FOREIGN KEY (user_id) REFERENCES profiles(id) ON DELETE CASCADE; exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.chat_hidden add constraint chat_hidden_message_id_fkey FOREIGN KEY (message_id) REFERENCES chat_messages(id) ON DELETE CASCADE; exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.chat_hidden add constraint chat_hidden_user_id_fkey FOREIGN KEY (user_id) REFERENCES profiles(id) ON DELETE CASCADE; exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.chat_messages add constraint chat_messages_author_id_fkey FOREIGN KEY (author_id) REFERENCES profiles(id) ON DELETE SET NULL; exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.chat_messages add constraint chat_messages_channel_id_fkey FOREIGN KEY (channel_id) REFERENCES chat_channels(id) ON DELETE CASCADE; exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.chat_messages add constraint chat_messages_reply_to_fkey FOREIGN KEY (reply_to) REFERENCES chat_messages(id) ON DELETE SET NULL; exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.chat_mutes add constraint chat_mutes_channel_id_fkey FOREIGN KEY (channel_id) REFERENCES chat_channels(id) ON DELETE CASCADE; exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.chat_mutes add constraint chat_mutes_user_id_fkey FOREIGN KEY (user_id) REFERENCES profiles(id) ON DELETE CASCADE; exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.chat_reactions add constraint chat_reactions_channel_id_fkey FOREIGN KEY (channel_id) REFERENCES chat_channels(id) ON DELETE CASCADE; exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.chat_reactions add constraint chat_reactions_message_id_fkey FOREIGN KEY (message_id) REFERENCES chat_messages(id) ON DELETE CASCADE; exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.chat_reactions add constraint chat_reactions_user_id_fkey FOREIGN KEY (user_id) REFERENCES profiles(id) ON DELETE CASCADE; exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.chat_reads add constraint chat_reads_channel_id_fkey FOREIGN KEY (channel_id) REFERENCES chat_channels(id) ON DELETE CASCADE; exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.chat_reads add constraint chat_reads_user_id_fkey FOREIGN KEY (user_id) REFERENCES profiles(id) ON DELETE CASCADE; exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.clients add constraint clients_created_by_fkey FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE SET NULL; exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.clients add constraint clients_owner_id_fkey FOREIGN KEY (owner_id) REFERENCES profiles(id) ON DELETE SET NULL; exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.comments add constraint comments_author_id_fkey FOREIGN KEY (author_id) REFERENCES profiles(id) ON DELETE SET NULL; exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.contacts add constraint contacts_client_id_fkey FOREIGN KEY (client_id) REFERENCES clients(id) ON DELETE SET NULL; exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.contacts add constraint contacts_created_by_fkey FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE SET NULL; exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.contacts add constraint contacts_owner_id_fkey FOREIGN KEY (owner_id) REFERENCES profiles(id) ON DELETE SET NULL; exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.content add constraint content_campaign_id_fkey FOREIGN KEY (campaign_id) REFERENCES campaigns(id) ON DELETE SET NULL; exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.content add constraint content_created_by_fkey FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE SET NULL; exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.content add constraint content_owner_id_fkey FOREIGN KEY (owner_id) REFERENCES profiles(id) ON DELETE SET NULL; exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.deals add constraint deals_client_id_fkey FOREIGN KEY (client_id) REFERENCES clients(id) ON DELETE SET NULL; exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.deals add constraint deals_contact_id_fkey FOREIGN KEY (contact_id) REFERENCES contacts(id) ON DELETE SET NULL; exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.deals add constraint deals_created_by_fkey FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE SET NULL; exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.deals add constraint deals_lead_id_fkey FOREIGN KEY (lead_id) REFERENCES leads(id) ON DELETE SET NULL; exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.deals add constraint deals_owner_id_fkey FOREIGN KEY (owner_id) REFERENCES profiles(id) ON DELETE SET NULL; exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.deleted_records add constraint deleted_records_deleted_by_fkey FOREIGN KEY (deleted_by) REFERENCES profiles(id) ON DELETE SET NULL; exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.documents add constraint documents_created_by_fkey FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE SET NULL; exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.email_reply_log add constraint email_reply_log_user_id_fkey FOREIGN KEY (user_id) REFERENCES profiles(id) ON DELETE SET NULL; exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.email_reply_tokens add constraint email_reply_tokens_channel_id_fkey FOREIGN KEY (channel_id) REFERENCES chat_channels(id) ON DELETE CASCADE; exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.email_reply_tokens add constraint email_reply_tokens_user_id_fkey FOREIGN KEY (user_id) REFERENCES profiles(id) ON DELETE CASCADE; exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.emails add constraint emails_user_id_fkey FOREIGN KEY (user_id) REFERENCES profiles(id) ON DELETE CASCADE; exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.features add constraint features_created_by_fkey FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE SET NULL; exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.features add constraint features_owner_id_fkey FOREIGN KEY (owner_id) REFERENCES profiles(id) ON DELETE SET NULL; exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.features add constraint features_project_id_fkey FOREIGN KEY (project_id) REFERENCES projects(id) ON DELETE CASCADE; exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.features add constraint features_tester_id_fkey FOREIGN KEY (tester_id) REFERENCES profiles(id) ON DELETE SET NULL; exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.files add constraint files_uploaded_by_fkey FOREIGN KEY (uploaded_by) REFERENCES profiles(id) ON DELETE SET NULL; exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.google_links add constraint google_links_user_id_fkey FOREIGN KEY (user_id) REFERENCES profiles(id) ON DELETE CASCADE; exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.google_tokens add constraint google_tokens_user_id_fkey FOREIGN KEY (user_id) REFERENCES profiles(id) ON DELETE CASCADE; exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.leads add constraint leads_campaign_id_fkey FOREIGN KEY (campaign_id) REFERENCES campaigns(id) ON DELETE SET NULL; exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.leads add constraint leads_created_by_fkey FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE SET NULL; exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.leads add constraint leads_deal_id_fkey FOREIGN KEY (deal_id) REFERENCES deals(id) ON DELETE SET NULL; exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.leads add constraint leads_owner_id_fkey FOREIGN KEY (owner_id) REFERENCES profiles(id) ON DELETE SET NULL; exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.leads add constraint leads_sales_owner_id_fkey FOREIGN KEY (sales_owner_id) REFERENCES profiles(id) ON DELETE SET NULL; exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.leave_requests add constraint leave_requests_created_by_fkey FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE SET NULL; exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.leave_requests add constraint leave_requests_reviewed_by_fkey FOREIGN KEY (reviewed_by) REFERENCES profiles(id) ON DELETE SET NULL; exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.leave_requests add constraint leave_requests_user_id_fkey FOREIGN KEY (user_id) REFERENCES profiles(id) ON DELETE CASCADE; exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.mail_sender add constraint mail_sender_connected_by_fkey FOREIGN KEY (connected_by) REFERENCES profiles(id) ON DELETE SET NULL; exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.meeting_joins add constraint meeting_joins_created_by_fkey FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE SET NULL; exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.meeting_joins add constraint meeting_joins_meeting_id_fkey FOREIGN KEY (meeting_id) REFERENCES meetings(id) ON DELETE CASCADE; exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.meeting_joins add constraint meeting_joins_user_id_fkey FOREIGN KEY (user_id) REFERENCES profiles(id) ON DELETE SET NULL; exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.meetings add constraint meetings_client_id_fkey FOREIGN KEY (client_id) REFERENCES clients(id) ON DELETE SET NULL; exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.meetings add constraint meetings_created_by_fkey FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE SET NULL; exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.meetings add constraint meetings_google_owner_fkey FOREIGN KEY (google_owner) REFERENCES profiles(id) ON DELETE SET NULL; exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.meetings add constraint meetings_project_id_fkey FOREIGN KEY (project_id) REFERENCES projects(id) ON DELETE SET NULL; exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.notes add constraint notes_meeting_id_fkey FOREIGN KEY (meeting_id) REFERENCES meetings(id) ON DELETE SET NULL; exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.notes add constraint notes_owner_id_fkey FOREIGN KEY (owner_id) REFERENCES profiles(id) ON DELETE CASCADE; exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.notes add constraint notes_project_id_fkey FOREIGN KEY (project_id) REFERENCES projects(id) ON DELETE SET NULL; exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.notes add constraint notes_task_id_fkey FOREIGN KEY (task_id) REFERENCES tasks(id) ON DELETE SET NULL; exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.notifications add constraint notifications_created_by_fkey FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE SET NULL; exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.notifications add constraint notifications_user_id_fkey FOREIGN KEY (user_id) REFERENCES profiles(id) ON DELETE CASCADE; exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.presence add constraint presence_user_id_fkey FOREIGN KEY (user_id) REFERENCES profiles(id) ON DELETE CASCADE; exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.problem_reports add constraint problem_reports_user_id_fkey FOREIGN KEY (user_id) REFERENCES profiles(id) ON DELETE SET NULL; exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.profile_private add constraint profile_private_user_id_fkey FOREIGN KEY (user_id) REFERENCES profiles(id) ON DELETE CASCADE; exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.profiles add constraint profiles_id_fkey FOREIGN KEY (id) REFERENCES auth.users(id) ON DELETE CASCADE; exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.profiles add constraint profiles_role_id_fkey FOREIGN KEY (role_id) REFERENCES roles(id) ON DELETE SET NULL; exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.projects add constraint projects_client_id_fkey FOREIGN KEY (client_id) REFERENCES clients(id) ON DELETE SET NULL; exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.projects add constraint projects_created_by_fkey FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE SET NULL; exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.projects add constraint projects_manager_id_fkey FOREIGN KEY (manager_id) REFERENCES profiles(id) ON DELETE SET NULL; exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.projects add constraint projects_qa_lead_id_fkey FOREIGN KEY (qa_lead_id) REFERENCES profiles(id) ON DELETE SET NULL; exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.proposals add constraint proposals_client_id_fkey FOREIGN KEY (client_id) REFERENCES clients(id) ON DELETE SET NULL; exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.proposals add constraint proposals_created_by_fkey FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE SET NULL; exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.proposals add constraint proposals_deal_id_fkey FOREIGN KEY (deal_id) REFERENCES deals(id) ON DELETE SET NULL; exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.proposals add constraint proposals_owner_id_fkey FOREIGN KEY (owner_id) REFERENCES profiles(id) ON DELETE SET NULL; exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.record_events add constraint record_events_actor_id_fkey FOREIGN KEY (actor_id) REFERENCES profiles(id) ON DELETE SET NULL; exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.releases add constraint releases_created_by_fkey FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE SET NULL; exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.releases add constraint releases_owner_id_fkey FOREIGN KEY (owner_id) REFERENCES profiles(id) ON DELETE SET NULL; exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.releases add constraint releases_project_id_fkey FOREIGN KEY (project_id) REFERENCES projects(id) ON DELETE SET NULL; exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.releases add constraint releases_qa_signoff_id_fkey FOREIGN KEY (qa_signoff_id) REFERENCES profiles(id) ON DELETE SET NULL; exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.seo_keywords add constraint seo_keywords_created_by_fkey FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE SET NULL; exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.seo_keywords add constraint seo_keywords_owner_id_fkey FOREIGN KEY (owner_id) REFERENCES profiles(id) ON DELETE SET NULL; exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.social_stats add constraint social_stats_created_by_fkey FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE SET NULL; exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.sprints add constraint sprints_created_by_fkey FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE SET NULL; exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.sprints add constraint sprints_project_id_fkey FOREIGN KEY (project_id) REFERENCES projects(id) ON DELETE CASCADE; exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.status_events add constraint status_events_user_id_fkey FOREIGN KEY (user_id) REFERENCES profiles(id) ON DELETE CASCADE; exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.targets add constraint targets_created_by_fkey FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE SET NULL; exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.targets add constraint targets_user_id_fkey FOREIGN KEY (user_id) REFERENCES profiles(id) ON DELETE CASCADE; exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.task_events add constraint task_events_actor_id_fkey FOREIGN KEY (actor_id) REFERENCES profiles(id) ON DELETE SET NULL; exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.task_events add constraint task_events_task_id_fkey FOREIGN KEY (task_id) REFERENCES tasks(id) ON DELETE CASCADE; exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.tasks add constraint tasks_archived_by_fkey FOREIGN KEY (archived_by) REFERENCES profiles(id) ON DELETE SET NULL; exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.tasks add constraint tasks_assignee_id_fkey FOREIGN KEY (assignee_id) REFERENCES profiles(id) ON DELETE SET NULL; exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.tasks add constraint tasks_created_by_fkey FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE SET NULL; exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.tasks add constraint tasks_deal_id_fkey FOREIGN KEY (deal_id) REFERENCES deals(id) ON DELETE SET NULL; exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.tasks add constraint tasks_feature_id_fkey FOREIGN KEY (feature_id) REFERENCES features(id) ON DELETE SET NULL; exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.tasks add constraint tasks_lead_id_fkey FOREIGN KEY (lead_id) REFERENCES leads(id) ON DELETE SET NULL; exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.tasks add constraint tasks_parent_id_fkey FOREIGN KEY (parent_id) REFERENCES tasks(id) ON DELETE SET NULL; exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.tasks add constraint tasks_project_id_fkey FOREIGN KEY (project_id) REFERENCES projects(id) ON DELETE SET NULL; exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.tasks add constraint tasks_release_id_fkey FOREIGN KEY (release_id) REFERENCES releases(id) ON DELETE SET NULL; exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.tasks add constraint tasks_reviewer_id_fkey FOREIGN KEY (reviewer_id) REFERENCES profiles(id) ON DELETE SET NULL; exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.tasks add constraint tasks_sprint_id_fkey FOREIGN KEY (sprint_id) REFERENCES sprints(id) ON DELETE SET NULL; exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.tasks add constraint tasks_test_case_id_fkey FOREIGN KEY (test_case_id) REFERENCES test_cases(id) ON DELETE SET NULL; exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.tasks add constraint tasks_tester_id_fkey FOREIGN KEY (tester_id) REFERENCES profiles(id) ON DELETE SET NULL; exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.test_cases add constraint test_cases_assignee_id_fkey FOREIGN KEY (assignee_id) REFERENCES profiles(id) ON DELETE SET NULL; exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.test_cases add constraint test_cases_created_by_fkey FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE SET NULL; exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.test_cases add constraint test_cases_feature_id_fkey FOREIGN KEY (feature_id) REFERENCES features(id) ON DELETE SET NULL; exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.test_cases add constraint test_cases_project_id_fkey FOREIGN KEY (project_id) REFERENCES projects(id) ON DELETE CASCADE; exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.test_cases add constraint test_cases_task_id_fkey FOREIGN KEY (task_id) REFERENCES tasks(id) ON DELETE SET NULL; exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.test_cases add constraint test_cases_tester_id_fkey FOREIGN KEY (tester_id) REFERENCES profiles(id) ON DELETE SET NULL; exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.test_runs add constraint test_runs_test_case_id_fkey FOREIGN KEY (test_case_id) REFERENCES test_cases(id) ON DELETE CASCADE; exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.test_runs add constraint test_runs_tester_id_fkey FOREIGN KEY (tester_id) REFERENCES profiles(id) ON DELETE SET NULL; exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.tickets add constraint tickets_assignee_id_fkey FOREIGN KEY (assignee_id) REFERENCES profiles(id) ON DELETE SET NULL; exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.tickets add constraint tickets_client_id_fkey FOREIGN KEY (client_id) REFERENCES clients(id) ON DELETE SET NULL; exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.tickets add constraint tickets_created_by_fkey FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE SET NULL; exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.tickets add constraint tickets_project_id_fkey FOREIGN KEY (project_id) REFERENCES projects(id) ON DELETE SET NULL; exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.user_status add constraint user_status_user_id_fkey FOREIGN KEY (user_id) REFERENCES profiles(id) ON DELETE CASCADE; exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.work_logs add constraint work_logs_task_id_fkey FOREIGN KEY (task_id) REFERENCES tasks(id) ON DELETE CASCADE; exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

do $x$ begin alter table public.work_logs add constraint work_logs_user_id_fkey FOREIGN KEY (user_id) REFERENCES profiles(id) ON DELETE CASCADE; exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;

CREATE INDEX IF NOT EXISTS calendar_events_day ON public.calendar_events USING btree (start_date);

CREATE INDEX IF NOT EXISTS chat_messages_channel ON public.chat_messages USING btree (channel_id, id DESC);

CREATE INDEX IF NOT EXISTS chat_messages_recent ON public.chat_messages USING btree (created_at);

CREATE INDEX IF NOT EXISTS chat_reactions_channel ON public.chat_reactions USING btree (channel_id);

CREATE INDEX IF NOT EXISTS comments_entity ON public.comments USING btree (tbl, entity_id);

CREATE INDEX IF NOT EXISTS email_reply_tokens_expiry ON public.email_reply_tokens USING btree (expires_at);

CREATE INDEX IF NOT EXISTS emails_entity ON public.emails USING btree (tbl, entity_id, sent_at DESC);

CREATE INDEX IF NOT EXISTS emails_thread ON public.emails USING btree (gmail_thread_id);

CREATE INDEX IF NOT EXISTS emails_user ON public.emails USING btree (user_id, sent_at DESC);

CREATE UNIQUE INDEX IF NOT EXISTS features_project_name ON public.features USING btree (project_id, lower(name));

CREATE INDEX IF NOT EXISTS files_entity ON public.files USING btree (tbl, entity_id);

CREATE INDEX IF NOT EXISTS files_storage ON public.files USING btree (storage);

CREATE UNIQUE INDEX IF NOT EXISTS leads_number ON public.leads USING btree (lead_number);

CREATE INDEX IF NOT EXISTS leads_pipeline ON public.leads USING btree (pipeline, status);

CREATE INDEX IF NOT EXISTS meeting_joins_meeting ON public.meeting_joins USING btree (meeting_id, joined_on);

CREATE INDEX IF NOT EXISTS meeting_joins_user ON public.meeting_joins USING btree (user_id, joined_on);

CREATE INDEX IF NOT EXISTS notes_owner ON public.notes USING btree (owner_id);

CREATE INDEX IF NOT EXISTS notifications_to_email ON public.notifications USING btree (created_at) WHERE (emailed_at IS NULL);

CREATE INDEX IF NOT EXISTS notifications_user ON public.notifications USING btree (user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS problem_reports_open ON public.problem_reports USING btree (status, created_at DESC);

CREATE INDEX IF NOT EXISTS record_events_entity ON public.record_events USING btree (tbl, entity_id, at DESC);

CREATE INDEX IF NOT EXISTS status_events_user_day ON public.status_events USING btree (user_id, at DESC);

CREATE INDEX IF NOT EXISTS task_events_task ON public.task_events USING btree (task_id, at DESC);

CREATE UNIQUE INDEX IF NOT EXISTS tasks_external ON public.tasks USING btree (project_id, external_id) WHERE (external_id <> ''::text);

CREATE UNIQUE INDEX IF NOT EXISTS tasks_number ON public.tasks USING btree (number);

CREATE INDEX IF NOT EXISTS tasks_parent ON public.tasks USING btree (parent_id) WHERE (parent_id IS NOT NULL);

CREATE INDEX IF NOT EXISTS tasks_qa ON public.tasks USING btree (qa_state, tester_id);

CREATE UNIQUE INDEX IF NOT EXISTS test_cases_external ON public.test_cases USING btree (project_id, external_id) WHERE (external_id <> ''::text);

CREATE INDEX IF NOT EXISTS test_cases_feature ON public.test_cases USING btree (feature_id, status);

CREATE INDEX IF NOT EXISTS test_cases_project ON public.test_cases USING btree (project_id, status);

CREATE INDEX IF NOT EXISTS test_runs_case ON public.test_runs USING btree (test_case_id, at DESC);

CREATE INDEX IF NOT EXISTS work_logs_task ON public.work_logs USING btree (task_id);

drop trigger if exists cleanup_children on public.activities;
CREATE TRIGGER cleanup_children AFTER DELETE ON public.activities FOR EACH ROW EXECUTE FUNCTION cleanup_children();

drop trigger if exists log_activity on public.activities;
CREATE TRIGGER log_activity AFTER INSERT OR DELETE OR UPDATE ON public.activities FOR EACH ROW EXECUTE FUNCTION log_activity();

drop trigger if exists set_updated_at on public.activities;
CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.activities FOR EACH ROW EXECUTE FUNCTION set_updated_at();

drop trigger if exists touch_last_contacted on public.activities;
CREATE TRIGGER touch_last_contacted AFTER INSERT ON public.activities FOR EACH ROW EXECUTE FUNCTION touch_last_contacted();

drop trigger if exists cleanup_children on public.announcements;
CREATE TRIGGER cleanup_children AFTER DELETE ON public.announcements FOR EACH ROW EXECUTE FUNCTION cleanup_children();

drop trigger if exists log_activity on public.announcements;
CREATE TRIGGER log_activity AFTER INSERT OR DELETE OR UPDATE ON public.announcements FOR EACH ROW EXECUTE FUNCTION log_activity();

drop trigger if exists set_updated_at on public.announcements;
CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.announcements FOR EACH ROW EXECUTE FUNCTION set_updated_at();

drop trigger if exists protect_attendance on public.attendance;
CREATE TRIGGER protect_attendance BEFORE DELETE OR UPDATE ON public.attendance FOR EACH ROW EXECUTE FUNCTION protect_attendance();

drop trigger if exists protect_attendance_insert on public.attendance;
CREATE TRIGGER protect_attendance_insert BEFORE INSERT ON public.attendance FOR EACH ROW EXECUTE FUNCTION protect_attendance_insert();

drop trigger if exists set_updated_at on public.attendance;
CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.attendance FOR EACH ROW EXECUTE FUNCTION set_updated_at();

drop trigger if exists sync_attendance_status on public.attendance;
CREATE TRIGGER sync_attendance_status AFTER INSERT OR UPDATE OF check_in, check_out ON public.attendance FOR EACH ROW EXECUTE FUNCTION sync_attendance_status();

drop trigger if exists cleanup_children on public.campaigns;
CREATE TRIGGER cleanup_children AFTER DELETE ON public.campaigns FOR EACH ROW EXECUTE FUNCTION cleanup_children();

drop trigger if exists log_activity on public.campaigns;
CREATE TRIGGER log_activity AFTER INSERT OR DELETE OR UPDATE ON public.campaigns FOR EACH ROW EXECUTE FUNCTION log_activity();

drop trigger if exists set_updated_at on public.campaigns;
CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.campaigns FOR EACH ROW EXECUTE FUNCTION set_updated_at();

drop trigger if exists check_chat_attachments on public.chat_messages;
CREATE TRIGGER check_chat_attachments BEFORE INSERT OR UPDATE ON public.chat_messages FOR EACH ROW EXECUTE FUNCTION check_chat_attachments();

drop trigger if exists check_chat_reply on public.chat_messages;
CREATE TRIGGER check_chat_reply BEFORE INSERT OR UPDATE ON public.chat_messages FOR EACH ROW EXECUTE FUNCTION check_chat_reply();

drop trigger if exists keep_via_email on public.chat_messages;
CREATE TRIGGER keep_via_email BEFORE INSERT OR UPDATE ON public.chat_messages FOR EACH ROW EXECUTE FUNCTION keep_via_email();

drop trigger if exists live_chat_signal on public.chat_messages;
CREATE TRIGGER live_chat_signal AFTER INSERT OR UPDATE ON public.chat_messages FOR EACH ROW EXECUTE FUNCTION live_chat_signal();

drop trigger if exists notify_chat_message on public.chat_messages;
CREATE TRIGGER notify_chat_message AFTER INSERT ON public.chat_messages FOR EACH ROW EXECUTE FUNCTION notify_chat_message();

drop trigger if exists protect_chat_edit on public.chat_messages;
CREATE TRIGGER protect_chat_edit BEFORE UPDATE ON public.chat_messages FOR EACH ROW EXECUTE FUNCTION protect_chat_edit();

drop trigger if exists live_reaction_signal on public.chat_reactions;
CREATE TRIGGER live_reaction_signal AFTER INSERT OR DELETE ON public.chat_reactions FOR EACH ROW EXECUTE FUNCTION live_reaction_signal();

drop trigger if exists set_reaction_channel on public.chat_reactions;
CREATE TRIGGER set_reaction_channel BEFORE INSERT ON public.chat_reactions FOR EACH ROW EXECUTE FUNCTION set_reaction_channel();

drop trigger if exists clear_chat_notifications on public.chat_reads;
CREATE TRIGGER clear_chat_notifications AFTER INSERT OR UPDATE ON public.chat_reads FOR EACH ROW EXECUTE FUNCTION clear_chat_notifications();

drop trigger if exists cleanup_children on public.clients;
CREATE TRIGGER cleanup_children AFTER DELETE ON public.clients FOR EACH ROW EXECUTE FUNCTION cleanup_children();

drop trigger if exists log_activity on public.clients;
CREATE TRIGGER log_activity AFTER INSERT OR DELETE OR UPDATE ON public.clients FOR EACH ROW EXECUTE FUNCTION log_activity();

drop trigger if exists set_updated_at on public.clients;
CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.clients FOR EACH ROW EXECUTE FUNCTION set_updated_at();

drop trigger if exists keep_via_email on public.comments;
CREATE TRIGGER keep_via_email BEFORE INSERT OR UPDATE ON public.comments FOR EACH ROW EXECUTE FUNCTION keep_via_email();

drop trigger if exists log_task_comment on public.comments;
CREATE TRIGGER log_task_comment AFTER INSERT OR DELETE ON public.comments FOR EACH ROW EXECUTE FUNCTION log_task_comment_or_file();

drop trigger if exists merge_comment_mentions on public.comments;
CREATE TRIGGER merge_comment_mentions AFTER INSERT ON public.comments FOR EACH ROW EXECUTE FUNCTION merge_comment_mentions();

drop trigger if exists cleanup_children on public.contacts;
CREATE TRIGGER cleanup_children AFTER DELETE ON public.contacts FOR EACH ROW EXECUTE FUNCTION cleanup_children();

drop trigger if exists log_activity on public.contacts;
CREATE TRIGGER log_activity AFTER INSERT OR DELETE OR UPDATE ON public.contacts FOR EACH ROW EXECUTE FUNCTION log_activity();

drop trigger if exists set_updated_at on public.contacts;
CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.contacts FOR EACH ROW EXECUTE FUNCTION set_updated_at();

drop trigger if exists cleanup_children on public.content;
CREATE TRIGGER cleanup_children AFTER DELETE ON public.content FOR EACH ROW EXECUTE FUNCTION cleanup_children();

drop trigger if exists log_activity on public.content;
CREATE TRIGGER log_activity AFTER INSERT OR DELETE OR UPDATE ON public.content FOR EACH ROW EXECUTE FUNCTION log_activity();

drop trigger if exists set_updated_at on public.content;
CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.content FOR EACH ROW EXECUTE FUNCTION set_updated_at();

drop trigger if exists cleanup_children on public.deals;
CREATE TRIGGER cleanup_children AFTER DELETE ON public.deals FOR EACH ROW EXECUTE FUNCTION cleanup_children();

drop trigger if exists log_activity on public.deals;
CREATE TRIGGER log_activity AFTER INSERT OR DELETE OR UPDATE ON public.deals FOR EACH ROW EXECUTE FUNCTION log_activity();

drop trigger if exists log_record_change on public.deals;
CREATE TRIGGER log_record_change AFTER INSERT OR UPDATE ON public.deals FOR EACH ROW EXECUTE FUNCTION log_record_change();

drop trigger if exists set_updated_at on public.deals;
CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.deals FOR EACH ROW EXECUTE FUNCTION set_updated_at();

drop trigger if exists cleanup_children on public.documents;
CREATE TRIGGER cleanup_children AFTER DELETE ON public.documents FOR EACH ROW EXECUTE FUNCTION cleanup_children();

drop trigger if exists log_activity on public.documents;
CREATE TRIGGER log_activity AFTER INSERT OR DELETE OR UPDATE ON public.documents FOR EACH ROW EXECUTE FUNCTION log_activity();

drop trigger if exists set_updated_at on public.documents;
CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.documents FOR EACH ROW EXECUTE FUNCTION set_updated_at();

drop trigger if exists set_updated_at on public.features;
CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.features FOR EACH ROW EXECUTE FUNCTION set_updated_at();

drop trigger if exists log_task_file on public.files;
CREATE TRIGGER log_task_file AFTER INSERT OR DELETE ON public.files FOR EACH ROW EXECUTE FUNCTION log_task_comment_or_file();

drop trigger if exists cleanup_children on public.leads;
CREATE TRIGGER cleanup_children AFTER DELETE ON public.leads FOR EACH ROW EXECUTE FUNCTION cleanup_children();

drop trigger if exists log_activity on public.leads;
CREATE TRIGGER log_activity AFTER INSERT OR DELETE OR UPDATE ON public.leads FOR EACH ROW EXECUTE FUNCTION log_activity();

drop trigger if exists log_record_change on public.leads;
CREATE TRIGGER log_record_change AFTER INSERT OR UPDATE ON public.leads FOR EACH ROW EXECUTE FUNCTION log_record_change();

drop trigger if exists set_lead_number on public.leads;
CREATE TRIGGER set_lead_number BEFORE INSERT ON public.leads FOR EACH ROW EXECUTE FUNCTION set_lead_number();

drop trigger if exists set_updated_at on public.leads;
CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.leads FOR EACH ROW EXECUTE FUNCTION set_updated_at();

drop trigger if exists cleanup_children on public.leave_requests;
CREATE TRIGGER cleanup_children AFTER DELETE ON public.leave_requests FOR EACH ROW EXECUTE FUNCTION cleanup_children();

drop trigger if exists leave_changed on public.leave_requests;
CREATE TRIGGER leave_changed AFTER INSERT OR DELETE OR UPDATE ON public.leave_requests FOR EACH STATEMENT EXECUTE FUNCTION leave_changed();

drop trigger if exists log_activity on public.leave_requests;
CREATE TRIGGER log_activity AFTER INSERT OR DELETE OR UPDATE ON public.leave_requests FOR EACH ROW EXECUTE FUNCTION log_activity();

drop trigger if exists set_updated_at on public.leave_requests;
CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.leave_requests FOR EACH ROW EXECUTE FUNCTION set_updated_at();

drop trigger if exists cleanup_children on public.meetings;
CREATE TRIGGER cleanup_children AFTER DELETE ON public.meetings FOR EACH ROW EXECUTE FUNCTION cleanup_children();

drop trigger if exists log_activity on public.meetings;
CREATE TRIGGER log_activity AFTER INSERT OR DELETE OR UPDATE ON public.meetings FOR EACH ROW EXECUTE FUNCTION log_activity();

drop trigger if exists set_updated_at on public.meetings;
CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.meetings FOR EACH ROW EXECUTE FUNCTION set_updated_at();

drop trigger if exists cleanup_children on public.notes;
CREATE TRIGGER cleanup_children AFTER DELETE ON public.notes FOR EACH ROW EXECUTE FUNCTION cleanup_children();

drop trigger if exists set_updated_at on public.notes;
CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.notes FOR EACH ROW EXECUTE FUNCTION set_updated_at();

drop trigger if exists live_notify_signal on public.notifications;
CREATE TRIGGER live_notify_signal AFTER INSERT OR UPDATE OF title, created_at ON public.notifications FOR EACH ROW EXECUTE FUNCTION live_notify_signal();

drop trigger if exists set_updated_at on public.problem_reports;
CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.problem_reports FOR EACH ROW EXECUTE FUNCTION set_updated_at();

drop trigger if exists touch_profile_private on public.profile_private;
CREATE TRIGGER touch_profile_private BEFORE INSERT OR UPDATE ON public.profile_private FOR EACH ROW EXECUTE FUNCTION touch_profile_private();

drop trigger if exists check_avatar_url on public.profiles;
CREATE TRIGGER check_avatar_url BEFORE UPDATE OF avatar_url ON public.profiles FOR EACH ROW EXECUTE FUNCTION check_avatar_url();

drop trigger if exists protect_profile on public.profiles;
CREATE TRIGGER protect_profile BEFORE UPDATE ON public.profiles FOR EACH ROW EXECUTE FUNCTION protect_profile();

drop trigger if exists cleanup_children on public.projects;
CREATE TRIGGER cleanup_children AFTER DELETE ON public.projects FOR EACH ROW EXECUTE FUNCTION cleanup_children();

drop trigger if exists log_activity on public.projects;
CREATE TRIGGER log_activity AFTER INSERT OR DELETE OR UPDATE ON public.projects FOR EACH ROW EXECUTE FUNCTION log_activity();

drop trigger if exists set_updated_at on public.projects;
CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.projects FOR EACH ROW EXECUTE FUNCTION set_updated_at();

drop trigger if exists cleanup_children on public.proposals;
CREATE TRIGGER cleanup_children AFTER DELETE ON public.proposals FOR EACH ROW EXECUTE FUNCTION cleanup_children();

drop trigger if exists log_activity on public.proposals;
CREATE TRIGGER log_activity AFTER INSERT OR DELETE OR UPDATE ON public.proposals FOR EACH ROW EXECUTE FUNCTION log_activity();

drop trigger if exists set_updated_at on public.proposals;
CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.proposals FOR EACH ROW EXECUTE FUNCTION set_updated_at();

drop trigger if exists cleanup_children on public.releases;
CREATE TRIGGER cleanup_children AFTER DELETE ON public.releases FOR EACH ROW EXECUTE FUNCTION cleanup_children();

drop trigger if exists log_activity on public.releases;
CREATE TRIGGER log_activity AFTER INSERT OR DELETE OR UPDATE ON public.releases FOR EACH ROW EXECUTE FUNCTION log_activity();

drop trigger if exists set_updated_at on public.releases;
CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.releases FOR EACH ROW EXECUTE FUNCTION set_updated_at();

drop trigger if exists cleanup_children on public.seo_keywords;
CREATE TRIGGER cleanup_children AFTER DELETE ON public.seo_keywords FOR EACH ROW EXECUTE FUNCTION cleanup_children();

drop trigger if exists log_activity on public.seo_keywords;
CREATE TRIGGER log_activity AFTER INSERT OR DELETE OR UPDATE ON public.seo_keywords FOR EACH ROW EXECUTE FUNCTION log_activity();

drop trigger if exists set_updated_at on public.seo_keywords;
CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.seo_keywords FOR EACH ROW EXECUTE FUNCTION set_updated_at();

drop trigger if exists log_settings_change on public.settings;
CREATE TRIGGER log_settings_change AFTER UPDATE ON public.settings FOR EACH ROW EXECUTE FUNCTION log_settings_change();

drop trigger if exists set_updated_at on public.social_stats;
CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.social_stats FOR EACH ROW EXECUTE FUNCTION set_updated_at();

drop trigger if exists cleanup_children on public.sprints;
CREATE TRIGGER cleanup_children AFTER DELETE ON public.sprints FOR EACH ROW EXECUTE FUNCTION cleanup_children();

drop trigger if exists log_activity on public.sprints;
CREATE TRIGGER log_activity AFTER INSERT OR DELETE OR UPDATE ON public.sprints FOR EACH ROW EXECUTE FUNCTION log_activity();

drop trigger if exists set_updated_at on public.sprints;
CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.sprints FOR EACH ROW EXECUTE FUNCTION set_updated_at();

drop trigger if exists cleanup_children on public.targets;
CREATE TRIGGER cleanup_children AFTER DELETE ON public.targets FOR EACH ROW EXECUTE FUNCTION cleanup_children();

drop trigger if exists log_activity on public.targets;
CREATE TRIGGER log_activity AFTER INSERT OR DELETE OR UPDATE ON public.targets FOR EACH ROW EXECUTE FUNCTION log_activity();

drop trigger if exists set_updated_at on public.targets;
CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.targets FOR EACH ROW EXECUTE FUNCTION set_updated_at();

drop trigger if exists check_task_parent on public.tasks;
CREATE TRIGGER check_task_parent BEFORE INSERT OR UPDATE OF parent_id, type, vertical ON public.tasks FOR EACH ROW EXECUTE FUNCTION check_task_parent();

drop trigger if exists cleanup_children on public.tasks;
CREATE TRIGGER cleanup_children AFTER DELETE ON public.tasks FOR EACH ROW EXECUTE FUNCTION cleanup_children();

drop trigger if exists guard_dev_done on public.tasks;
CREATE TRIGGER guard_dev_done BEFORE INSERT OR UPDATE OF status ON public.tasks FOR EACH ROW EXECUTE FUNCTION guard_dev_done();

drop trigger if exists keep_deleted_task on public.tasks;
CREATE TRIGGER keep_deleted_task BEFORE DELETE ON public.tasks FOR EACH ROW EXECUTE FUNCTION keep_deleted_task();

drop trigger if exists log_activity on public.tasks;
CREATE TRIGGER log_activity AFTER INSERT OR DELETE OR UPDATE ON public.tasks FOR EACH ROW EXECUTE FUNCTION log_activity();

drop trigger if exists log_task_change on public.tasks;
CREATE TRIGGER log_task_change AFTER INSERT OR UPDATE ON public.tasks FOR EACH ROW EXECUTE FUNCTION log_task_change();

drop trigger if exists protect_task_fields on public.tasks;
CREATE TRIGGER protect_task_fields BEFORE UPDATE ON public.tasks FOR EACH ROW EXECUTE FUNCTION protect_task_fields();

drop trigger if exists set_updated_at on public.tasks;
CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.tasks FOR EACH ROW EXECUTE FUNCTION set_updated_at();

drop trigger if exists track_qa_stage on public.tasks;
CREATE TRIGGER track_qa_stage BEFORE INSERT OR UPDATE OF status ON public.tasks FOR EACH ROW EXECUTE FUNCTION track_qa_stage();

drop trigger if exists protect_test_case on public.test_cases;
CREATE TRIGGER protect_test_case BEFORE UPDATE ON public.test_cases FOR EACH ROW EXECUTE FUNCTION protect_test_case();

drop trigger if exists cleanup_children on public.tickets;
CREATE TRIGGER cleanup_children AFTER DELETE ON public.tickets FOR EACH ROW EXECUTE FUNCTION cleanup_children();

drop trigger if exists log_activity on public.tickets;
CREATE TRIGGER log_activity AFTER INSERT OR DELETE OR UPDATE ON public.tickets FOR EACH ROW EXECUTE FUNCTION log_activity();

drop trigger if exists set_updated_at on public.tickets;
CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.tickets FOR EACH ROW EXECUTE FUNCTION set_updated_at();

drop trigger if exists log_status_change on public.user_status;
CREATE TRIGGER log_status_change AFTER INSERT OR UPDATE ON public.user_status FOR EACH ROW EXECUTE FUNCTION log_status_change();

drop trigger if exists protect_user_status on public.user_status;
CREATE TRIGGER protect_user_status BEFORE INSERT OR UPDATE ON public.user_status FOR EACH ROW EXECUTE FUNCTION protect_user_status();

drop trigger if exists keep_work_log_owner on public.work_logs;
CREATE TRIGGER keep_work_log_owner BEFORE UPDATE ON public.work_logs FOR EACH ROW EXECUTE FUNCTION keep_work_log_owner();

alter table public.activities enable row level security;

alter table public.activity_log enable row level security;

alter table public.announcements enable row level security;

alter table public.attendance enable row level security;

alter table public.calendar_events enable row level security;

alter table public.campaigns enable row level security;

alter table public.chat_channels enable row level security;

alter table public.chat_email_log enable row level security;

alter table public.chat_hidden enable row level security;

alter table public.chat_messages enable row level security;

alter table public.chat_mutes enable row level security;

alter table public.chat_reactions enable row level security;

alter table public.chat_reads enable row level security;

alter table public.clients enable row level security;

alter table public.comments enable row level security;

alter table public.contacts enable row level security;

alter table public.content enable row level security;

alter table public.deals enable row level security;

alter table public.deleted_records enable row level security;

alter table public.documents enable row level security;

alter table public.email_reply_log enable row level security;

alter table public.email_reply_tokens enable row level security;

alter table public.emails enable row level security;

alter table public.features enable row level security;

alter table public.files enable row level security;

alter table public.google_links enable row level security;

alter table public.google_tokens enable row level security;

alter table public.leads enable row level security;

alter table public.leave_requests enable row level security;

alter table public.mail_sender enable row level security;

alter table public.meeting_joins enable row level security;

alter table public.meetings enable row level security;

alter table public.notes enable row level security;

alter table public.notifications enable row level security;

alter table public.presence enable row level security;

alter table public.problem_reports enable row level security;

alter table public.profile_private enable row level security;

alter table public.profiles enable row level security;

alter table public.projects enable row level security;

alter table public.proposals enable row level security;

alter table public.record_events enable row level security;

alter table public.releases enable row level security;

alter table public.roles enable row level security;

alter table public.seo_keywords enable row level security;

alter table public.settings enable row level security;

alter table public.social_stats enable row level security;

alter table public.sprints enable row level security;

alter table public.status_events enable row level security;

alter table public.targets enable row level security;

alter table public.task_events enable row level security;

alter table public.tasks enable row level security;

alter table public.test_cases enable row level security;

alter table public.test_runs enable row level security;

alter table public.tickets enable row level security;

alter table public.user_status enable row level security;

alter table public.work_logs enable row level security;

drop policy if exists ws_delete on public.activities;
create policy ws_delete on public.activities as PERMISSIVE for DELETE to authenticated using ((perm(table_module('activities'::text)) >= 3));

drop policy if exists ws_insert on public.activities;
create policy ws_insert on public.activities as PERMISSIVE for INSERT to authenticated with check ((perm(table_module('activities'::text)) >= 2));

drop policy if exists ws_select on public.activities;
create policy ws_select on public.activities as PERMISSIVE for SELECT to authenticated using (((perm(table_module('activities'::text)) >= 1) OR (is_active_user() AND (owner_id = auth.uid()))));

drop policy if exists ws_update on public.activities;
create policy ws_update on public.activities as PERMISSIVE for UPDATE to authenticated using (((perm(table_module('activities'::text)) >= 2) OR (is_active_user() AND (owner_id = auth.uid())))) with check (((perm(table_module('activities'::text)) >= 2) OR (is_active_user() AND (owner_id = auth.uid()))));

drop policy if exists ws_select on public.activity_log;
create policy ws_select on public.activity_log as PERMISSIVE for SELECT to authenticated using (is_admin());

drop policy if exists ws_delete on public.announcements;
create policy ws_delete on public.announcements as PERMISSIVE for DELETE to authenticated using ((perm('announcements'::text) >= 3));

drop policy if exists ws_insert on public.announcements;
create policy ws_insert on public.announcements as PERMISSIVE for INSERT to authenticated with check ((perm('announcements'::text) >= 2));

drop policy if exists ws_select on public.announcements;
create policy ws_select on public.announcements as PERMISSIVE for SELECT to authenticated using (is_active_user());

drop policy if exists ws_update on public.announcements;
create policy ws_update on public.announcements as PERMISSIVE for UPDATE to authenticated using ((perm('announcements'::text) >= 2)) with check ((perm('announcements'::text) >= 2));

drop policy if exists ws_delete on public.attendance;
create policy ws_delete on public.attendance as PERMISSIVE for DELETE to authenticated using (((perm(table_module('attendance'::text)) >= 3) OR (is_active_user() AND (user_id = auth.uid()))));

drop policy if exists ws_insert on public.attendance;
create policy ws_insert on public.attendance as PERMISSIVE for INSERT to authenticated with check (((perm(table_module('attendance'::text)) >= 2) OR (is_active_user() AND (user_id = auth.uid()))));

drop policy if exists ws_select on public.attendance;
create policy ws_select on public.attendance as PERMISSIVE for SELECT to authenticated using (((perm(table_module('attendance'::text)) >= 1) OR (is_active_user() AND (user_id = auth.uid()))));

drop policy if exists ws_update on public.attendance;
create policy ws_update on public.attendance as PERMISSIVE for UPDATE to authenticated using (((perm(table_module('attendance'::text)) >= 2) OR (is_active_user() AND (user_id = auth.uid())))) with check (((perm(table_module('attendance'::text)) >= 2) OR (is_active_user() AND (user_id = auth.uid()))));

drop policy if exists ws_select on public.calendar_events;
create policy ws_select on public.calendar_events as PERMISSIVE for SELECT to authenticated using (is_active_user());

drop policy if exists ws_delete on public.campaigns;
create policy ws_delete on public.campaigns as PERMISSIVE for DELETE to authenticated using ((perm(table_module('campaigns'::text)) >= 3));

drop policy if exists ws_insert on public.campaigns;
create policy ws_insert on public.campaigns as PERMISSIVE for INSERT to authenticated with check ((perm(table_module('campaigns'::text)) >= 2));

drop policy if exists ws_select on public.campaigns;
create policy ws_select on public.campaigns as PERMISSIVE for SELECT to authenticated using ((perm(table_module('campaigns'::text)) >= 1));

drop policy if exists ws_update on public.campaigns;
create policy ws_update on public.campaigns as PERMISSIVE for UPDATE to authenticated using ((perm(table_module('campaigns'::text)) >= 2)) with check ((perm(table_module('campaigns'::text)) >= 2));

drop policy if exists ws_insert on public.chat_channels;
create policy ws_insert on public.chat_channels as PERMISSIVE for INSERT to authenticated with check ((is_active_user() AND (((kind = 'dm'::text) AND (cardinality(members) = 2) AND (auth.uid() = ANY (members))) OR ((kind = 'group'::text) AND ((cardinality(members) >= 2) AND (cardinality(members) <= 50)) AND (auth.uid() = ANY (members)) AND (created_by = auth.uid())) OR ((kind = 'channel'::text) AND is_admin()))));

drop policy if exists ws_select on public.chat_channels;
create policy ws_select on public.chat_channels as PERMISSIVE for SELECT to authenticated using ((is_active_user() AND (((kind = 'channel'::text) AND ((vertical IS NULL) OR (vertical = my_vertical()) OR is_admin())) OR (auth.uid() = ANY (members)))));

drop policy if exists ws_update on public.chat_channels;
create policy ws_update on public.chat_channels as PERMISSIVE for UPDATE to authenticated using ((is_admin() OR ((kind = 'group'::text) AND (created_by = auth.uid())))) with check ((is_admin() OR ((kind = 'group'::text) AND (created_by = auth.uid()) AND (auth.uid() = ANY (members)))));

drop policy if exists ws_own on public.chat_hidden;
create policy ws_own on public.chat_hidden as PERMISSIVE for ALL to authenticated using ((user_id = auth.uid())) with check ((user_id = auth.uid()));

drop policy if exists ws_insert on public.chat_messages;
create policy ws_insert on public.chat_messages as PERMISSIVE for INSERT to authenticated with check (((author_id = auth.uid()) AND can_chat(channel_id)));

drop policy if exists ws_select on public.chat_messages;
create policy ws_select on public.chat_messages as PERMISSIVE for SELECT to authenticated using (can_chat(channel_id));

drop policy if exists ws_update on public.chat_messages;
create policy ws_update on public.chat_messages as PERMISSIVE for UPDATE to authenticated using ((author_id = auth.uid())) with check ((author_id = auth.uid()));

drop policy if exists ws_delete on public.chat_mutes;
create policy ws_delete on public.chat_mutes as PERMISSIVE for DELETE to authenticated using ((user_id = auth.uid()));

drop policy if exists ws_insert on public.chat_mutes;
create policy ws_insert on public.chat_mutes as PERMISSIVE for INSERT to authenticated with check (((user_id = auth.uid()) AND is_active_user() AND can_chat(channel_id) AND (EXISTS ( SELECT 1
   FROM chat_channels c
  WHERE ((c.id = chat_mutes.channel_id) AND (c.kind = ANY (ARRAY['group'::text, 'channel'::text])))))));

drop policy if exists ws_select on public.chat_mutes;
create policy ws_select on public.chat_mutes as PERMISSIVE for SELECT to authenticated using ((user_id = auth.uid()));

drop policy if exists ws_delete on public.chat_reactions;
create policy ws_delete on public.chat_reactions as PERMISSIVE for DELETE to authenticated using ((user_id = auth.uid()));

drop policy if exists ws_insert on public.chat_reactions;
create policy ws_insert on public.chat_reactions as PERMISSIVE for INSERT to authenticated with check (((user_id = auth.uid()) AND can_chat(channel_id)));

drop policy if exists ws_select on public.chat_reactions;
create policy ws_select on public.chat_reactions as PERMISSIVE for SELECT to authenticated using (can_chat(channel_id));

drop policy if exists ws_select on public.chat_reads;
create policy ws_select on public.chat_reads as PERMISSIVE for SELECT to authenticated using (((user_id = auth.uid()) OR can_chat(channel_id)));

drop policy if exists ws_update on public.chat_reads;
create policy ws_update on public.chat_reads as PERMISSIVE for UPDATE to authenticated using ((user_id = auth.uid())) with check ((user_id = auth.uid()));

drop policy if exists ws_write on public.chat_reads;
create policy ws_write on public.chat_reads as PERMISSIVE for INSERT to authenticated with check ((user_id = auth.uid()));

drop policy if exists ws_delete on public.clients;
create policy ws_delete on public.clients as PERMISSIVE for DELETE to authenticated using ((perm(table_module('clients'::text)) >= 3));

drop policy if exists ws_insert on public.clients;
create policy ws_insert on public.clients as PERMISSIVE for INSERT to authenticated with check ((perm(table_module('clients'::text)) >= 2));

drop policy if exists ws_select on public.clients;
create policy ws_select on public.clients as PERMISSIVE for SELECT to authenticated using ((perm(table_module('clients'::text)) >= 1));

drop policy if exists ws_update on public.clients;
create policy ws_update on public.clients as PERMISSIVE for UPDATE to authenticated using ((perm(table_module('clients'::text)) >= 2)) with check ((perm(table_module('clients'::text)) >= 2));

drop policy if exists ws_delete on public.comments;
create policy ws_delete on public.comments as PERMISSIVE for DELETE to authenticated using ((is_admin() OR ((author_id = auth.uid()) AND (tbl <> 'tasks'::text))));

drop policy if exists ws_insert on public.comments;
create policy ws_insert on public.comments as PERMISSIVE for INSERT to authenticated with check ((is_active_user() AND (author_id = auth.uid()) AND can_see(tbl, entity_id)));

drop policy if exists ws_select on public.comments;
create policy ws_select on public.comments as PERMISSIVE for SELECT to authenticated using ((is_active_user() AND can_see(tbl, entity_id)));

drop policy if exists ws_delete on public.contacts;
create policy ws_delete on public.contacts as PERMISSIVE for DELETE to authenticated using ((perm(table_module('contacts'::text)) >= 3));

drop policy if exists ws_insert on public.contacts;
create policy ws_insert on public.contacts as PERMISSIVE for INSERT to authenticated with check ((perm(table_module('contacts'::text)) >= 2));

drop policy if exists ws_select on public.contacts;
create policy ws_select on public.contacts as PERMISSIVE for SELECT to authenticated using ((perm(table_module('contacts'::text)) >= 1));

drop policy if exists ws_update on public.contacts;
create policy ws_update on public.contacts as PERMISSIVE for UPDATE to authenticated using ((perm(table_module('contacts'::text)) >= 2)) with check ((perm(table_module('contacts'::text)) >= 2));

drop policy if exists ws_delete on public.content;
create policy ws_delete on public.content as PERMISSIVE for DELETE to authenticated using ((perm(table_module('content'::text)) >= 3));

drop policy if exists ws_insert on public.content;
create policy ws_insert on public.content as PERMISSIVE for INSERT to authenticated with check ((perm(table_module('content'::text)) >= 2));

drop policy if exists ws_select on public.content;
create policy ws_select on public.content as PERMISSIVE for SELECT to authenticated using ((perm(table_module('content'::text)) >= 1));

drop policy if exists ws_update on public.content;
create policy ws_update on public.content as PERMISSIVE for UPDATE to authenticated using ((perm(table_module('content'::text)) >= 2)) with check ((perm(table_module('content'::text)) >= 2));

drop policy if exists ws_delete on public.deals;
create policy ws_delete on public.deals as PERMISSIVE for DELETE to authenticated using ((perm(table_module('deals'::text)) >= 3));

drop policy if exists ws_insert on public.deals;
create policy ws_insert on public.deals as PERMISSIVE for INSERT to authenticated with check ((perm(table_module('deals'::text)) >= 2));

drop policy if exists ws_select on public.deals;
create policy ws_select on public.deals as PERMISSIVE for SELECT to authenticated using (((perm(table_module('deals'::text)) >= 1) OR (is_active_user() AND (owner_id = auth.uid()))));

drop policy if exists ws_update on public.deals;
create policy ws_update on public.deals as PERMISSIVE for UPDATE to authenticated using (((perm(table_module('deals'::text)) >= 2) OR (is_active_user() AND (owner_id = auth.uid())))) with check (((perm(table_module('deals'::text)) >= 2) OR (is_active_user() AND (owner_id = auth.uid()))));

drop policy if exists ws_select on public.deleted_records;
create policy ws_select on public.deleted_records as PERMISSIVE for SELECT to authenticated using (is_admin());

drop policy if exists ws_delete on public.documents;
create policy ws_delete on public.documents as PERMISSIVE for DELETE to authenticated using (((perm('documents'::text) >= 3) AND ((vertical = 'Company'::text) OR (vertical = my_vertical()) OR is_admin())));

drop policy if exists ws_insert on public.documents;
create policy ws_insert on public.documents as PERMISSIVE for INSERT to authenticated with check (((perm('documents'::text) >= 2) AND ((vertical = 'Company'::text) OR (vertical = my_vertical()) OR is_admin())));

drop policy if exists ws_select on public.documents;
create policy ws_select on public.documents as PERMISSIVE for SELECT to authenticated using (((perm('documents'::text) >= 1) AND ((vertical = 'Company'::text) OR (vertical = my_vertical()) OR is_admin())));

drop policy if exists ws_update on public.documents;
create policy ws_update on public.documents as PERMISSIVE for UPDATE to authenticated using (((perm('documents'::text) >= 2) AND ((vertical = 'Company'::text) OR (vertical = my_vertical()) OR is_admin()))) with check (((perm('documents'::text) >= 2) AND ((vertical = 'Company'::text) OR (vertical = my_vertical()) OR is_admin())));

drop policy if exists ws_select on public.emails;
create policy ws_select on public.emails as PERMISSIVE for SELECT to authenticated using ((is_active_user() AND ((user_id = auth.uid()) OR is_admin() OR ((tbl = ANY (ARRAY['leads'::text, 'deals'::text, 'clients'::text, 'contacts'::text, 'proposals'::text])) AND (entity_id IS NOT NULL) AND can_see(tbl, entity_id)))));

drop policy if exists ws_update on public.emails;
create policy ws_update on public.emails as PERMISSIVE for UPDATE to authenticated using ((user_id = auth.uid())) with check ((user_id = auth.uid()));

drop policy if exists ws_select on public.features;
create policy ws_select on public.features as PERMISSIVE for SELECT to authenticated using (((perm('qa'::text) >= 1) OR (perm('projects'::text) >= 1)));

drop policy if exists ws_write on public.features;
create policy ws_write on public.features as PERMISSIVE for ALL to authenticated using (((perm('qa'::text) >= 3) OR (perm('projects'::text) >= 3))) with check (((perm('qa'::text) >= 3) OR (perm('projects'::text) >= 3)));

drop policy if exists ws_delete on public.files;
create policy ws_delete on public.files as PERMISSIVE for DELETE to authenticated using (((uploaded_by = auth.uid()) OR (perm(table_module(tbl)) >= 3)));

drop policy if exists ws_insert on public.files;
create policy ws_insert on public.files as PERMISSIVE for INSERT to authenticated with check ((is_active_user() AND (uploaded_by = auth.uid()) AND can_see(tbl, entity_id)));

drop policy if exists ws_select on public.files;
create policy ws_select on public.files as PERMISSIVE for SELECT to authenticated using ((is_active_user() AND (can_see(tbl, entity_id) OR ((tbl = ANY (ARRAY['tasks'::text, 'test_cases'::text, 'features'::text, 'projects'::text, 'releases'::text, 'tickets'::text])) AND work_files_open()))));

drop policy if exists ws_select on public.google_links;
create policy ws_select on public.google_links as PERMISSIVE for SELECT to authenticated using (is_active_user());

drop policy if exists ws_delete on public.leads;
create policy ws_delete on public.leads as PERMISSIVE for DELETE to authenticated using ((perm(table_module('leads'::text)) >= 3));

drop policy if exists ws_insert on public.leads;
create policy ws_insert on public.leads as PERMISSIVE for INSERT to authenticated with check ((perm(table_module('leads'::text)) >= 2));

drop policy if exists ws_select on public.leads;
create policy ws_select on public.leads as PERMISSIVE for SELECT to authenticated using (((perm(table_module('leads'::text)) >= 1) OR (is_active_user() AND (owner_id = auth.uid()))));

drop policy if exists ws_update on public.leads;
create policy ws_update on public.leads as PERMISSIVE for UPDATE to authenticated using (((perm(table_module('leads'::text)) >= 2) OR (is_active_user() AND (owner_id = auth.uid())))) with check (((perm(table_module('leads'::text)) >= 2) OR (is_active_user() AND (owner_id = auth.uid()))));

drop policy if exists ws_delete on public.leave_requests;
create policy ws_delete on public.leave_requests as PERMISSIVE for DELETE to authenticated using (((perm('leave'::text) >= 3) OR (is_active_user() AND (user_id = auth.uid()) AND (status = 'Pending'::text))));

drop policy if exists ws_insert on public.leave_requests;
create policy ws_insert on public.leave_requests as PERMISSIVE for INSERT to authenticated with check (((perm('leave'::text) >= 2) OR (is_active_user() AND (user_id = auth.uid()) AND (status = 'Pending'::text))));

drop policy if exists ws_select on public.leave_requests;
create policy ws_select on public.leave_requests as PERMISSIVE for SELECT to authenticated using (((perm('leave'::text) >= 1) OR (is_active_user() AND (user_id = auth.uid()))));

drop policy if exists ws_update on public.leave_requests;
create policy ws_update on public.leave_requests as PERMISSIVE for UPDATE to authenticated using (((perm('leave'::text) >= 2) OR (is_active_user() AND (user_id = auth.uid()) AND (status = 'Pending'::text)))) with check (((perm('leave'::text) >= 2) OR (is_active_user() AND (user_id = auth.uid()) AND (status = 'Pending'::text))));

drop policy if exists ws_delete on public.meeting_joins;
create policy ws_delete on public.meeting_joins as PERMISSIVE for DELETE to authenticated using (is_admin());

drop policy if exists ws_insert on public.meeting_joins;
create policy ws_insert on public.meeting_joins as PERMISSIVE for INSERT to authenticated with check ((is_active_user() AND ((user_id = auth.uid()) OR is_admin() OR (EXISTS ( SELECT 1
   FROM meetings m
  WHERE ((m.id = meeting_joins.meeting_id) AND ((m.created_by = auth.uid()) OR (m.google_owner = auth.uid()))))))));

drop policy if exists ws_select on public.meeting_joins;
create policy ws_select on public.meeting_joins as PERMISSIVE for SELECT to authenticated using ((is_active_user() AND ((user_id = auth.uid()) OR (perm('meetings'::text) >= 1) OR can_see('meetings'::text, meeting_id))));

drop policy if exists ws_update on public.meeting_joins;
create policy ws_update on public.meeting_joins as PERMISSIVE for UPDATE to authenticated using ((is_active_user() AND ((user_id = auth.uid()) OR is_admin() OR (EXISTS ( SELECT 1
   FROM meetings m
  WHERE ((m.id = meeting_joins.meeting_id) AND ((m.created_by = auth.uid()) OR (m.google_owner = auth.uid()))))))));

drop policy if exists ws_delete on public.meetings;
create policy ws_delete on public.meetings as PERMISSIVE for DELETE to authenticated using (((perm('meetings'::text) >= 3) OR (is_active_user() AND (created_by = auth.uid()))));

drop policy if exists ws_insert on public.meetings;
create policy ws_insert on public.meetings as PERMISSIVE for INSERT to authenticated with check (is_active_user());

drop policy if exists ws_select on public.meetings;
create policy ws_select on public.meetings as PERMISSIVE for SELECT to authenticated using (((perm('meetings'::text) >= 1) OR (is_active_user() AND ((auth.uid() = ANY (attendees)) OR (created_by = auth.uid())))));

drop policy if exists ws_update on public.meetings;
create policy ws_update on public.meetings as PERMISSIVE for UPDATE to authenticated using (((perm('meetings'::text) >= 2) OR (is_active_user() AND (created_by = auth.uid())))) with check (((perm('meetings'::text) >= 2) OR (is_active_user() AND (created_by = auth.uid()))));

drop policy if exists ws_delete on public.notes;
create policy ws_delete on public.notes as PERMISSIVE for DELETE to authenticated using ((owner_id = auth.uid()));

drop policy if exists ws_insert on public.notes;
create policy ws_insert on public.notes as PERMISSIVE for INSERT to authenticated with check ((is_active_user() AND (owner_id = auth.uid())));

drop policy if exists ws_select on public.notes;
create policy ws_select on public.notes as PERMISSIVE for SELECT to authenticated using ((is_active_user() AND ((owner_id = auth.uid()) OR (visibility = 'Company'::text) OR ((visibility = 'Vertical'::text) AND ((vertical = my_vertical()) OR is_admin())) OR ((visibility = 'People'::text) AND (auth.uid() = ANY (shared_with))) OR (auth.uid() = ANY (mentions)))));

drop policy if exists ws_update on public.notes;
create policy ws_update on public.notes as PERMISSIVE for UPDATE to authenticated using ((owner_id = auth.uid())) with check ((owner_id = auth.uid()));

drop policy if exists ws_delete on public.notifications;
create policy ws_delete on public.notifications as PERMISSIVE for DELETE to authenticated using ((user_id = auth.uid()));

drop policy if exists ws_insert on public.notifications;
create policy ws_insert on public.notifications as PERMISSIVE for INSERT to authenticated with check (is_active_user());

drop policy if exists ws_select on public.notifications;
create policy ws_select on public.notifications as PERMISSIVE for SELECT to authenticated using ((user_id = auth.uid()));

drop policy if exists ws_update on public.notifications;
create policy ws_update on public.notifications as PERMISSIVE for UPDATE to authenticated using ((user_id = auth.uid())) with check ((user_id = auth.uid()));

drop policy if exists ws_insert on public.presence;
create policy ws_insert on public.presence as PERMISSIVE for INSERT to authenticated with check ((user_id = auth.uid()));

drop policy if exists ws_select on public.presence;
create policy ws_select on public.presence as PERMISSIVE for SELECT to authenticated using (is_active_user());

drop policy if exists ws_update on public.presence;
create policy ws_update on public.presence as PERMISSIVE for UPDATE to authenticated using ((user_id = auth.uid())) with check ((user_id = auth.uid()));

drop policy if exists ws_delete on public.problem_reports;
create policy ws_delete on public.problem_reports as PERMISSIVE for DELETE to authenticated using (is_admin());

drop policy if exists ws_insert on public.problem_reports;
create policy ws_insert on public.problem_reports as PERMISSIVE for INSERT to authenticated with check ((is_active_user() AND (user_id = auth.uid()) AND (status = 'Open'::text)));

drop policy if exists ws_select on public.problem_reports;
create policy ws_select on public.problem_reports as PERMISSIVE for SELECT to authenticated using ((is_admin() OR (user_id = auth.uid())));

drop policy if exists ws_update on public.problem_reports;
create policy ws_update on public.problem_reports as PERMISSIVE for UPDATE to authenticated using (is_admin()) with check (is_admin());

drop policy if exists ws_delete on public.profile_private;
create policy ws_delete on public.profile_private as PERMISSIVE for DELETE to authenticated using (is_admin());

drop policy if exists ws_insert on public.profile_private;
create policy ws_insert on public.profile_private as PERMISSIVE for INSERT to authenticated with check ((((user_id = auth.uid()) AND is_active_user()) OR is_admin()));

drop policy if exists ws_select on public.profile_private;
create policy ws_select on public.profile_private as PERMISSIVE for SELECT to authenticated using (((user_id = auth.uid()) OR is_admin()));

drop policy if exists ws_update on public.profile_private;
create policy ws_update on public.profile_private as PERMISSIVE for UPDATE to authenticated using (((user_id = auth.uid()) OR is_admin())) with check (((user_id = auth.uid()) OR is_admin()));

drop policy if exists ws_read on public.profiles;
create policy ws_read on public.profiles as PERMISSIVE for SELECT to authenticated using (((id = auth.uid()) OR is_active_user()));

drop policy if exists ws_update on public.profiles;
create policy ws_update on public.profiles as PERMISSIVE for UPDATE to authenticated using (((id = auth.uid()) OR is_admin())) with check (((id = auth.uid()) OR is_admin()));

drop policy if exists ws_delete on public.projects;
create policy ws_delete on public.projects as PERMISSIVE for DELETE to authenticated using ((perm('projects'::text) >= 3));

drop policy if exists ws_insert on public.projects;
create policy ws_insert on public.projects as PERMISSIVE for INSERT to authenticated with check ((perm('projects'::text) >= 2));

drop policy if exists ws_select on public.projects;
create policy ws_select on public.projects as PERMISSIVE for SELECT to authenticated using (((perm('projects'::text) >= 1) OR (is_active_user() AND ((manager_id = auth.uid()) OR (auth.uid() = ANY (members))))));

drop policy if exists ws_update on public.projects;
create policy ws_update on public.projects as PERMISSIVE for UPDATE to authenticated using (((perm('projects'::text) >= 2) OR (is_active_user() AND (manager_id = auth.uid())))) with check (((perm('projects'::text) >= 2) OR (is_active_user() AND (manager_id = auth.uid()))));

drop policy if exists ws_delete on public.proposals;
create policy ws_delete on public.proposals as PERMISSIVE for DELETE to authenticated using ((perm(table_module('proposals'::text)) >= 3));

drop policy if exists ws_insert on public.proposals;
create policy ws_insert on public.proposals as PERMISSIVE for INSERT to authenticated with check ((perm(table_module('proposals'::text)) >= 2));

drop policy if exists ws_select on public.proposals;
create policy ws_select on public.proposals as PERMISSIVE for SELECT to authenticated using ((perm(table_module('proposals'::text)) >= 1));

drop policy if exists ws_update on public.proposals;
create policy ws_update on public.proposals as PERMISSIVE for UPDATE to authenticated using ((perm(table_module('proposals'::text)) >= 2)) with check ((perm(table_module('proposals'::text)) >= 2));

drop policy if exists ws_select on public.record_events;
create policy ws_select on public.record_events as PERMISSIVE for SELECT to authenticated using ((is_active_user() AND can_see(tbl, entity_id)));

drop policy if exists ws_delete on public.releases;
create policy ws_delete on public.releases as PERMISSIVE for DELETE to authenticated using ((perm(table_module('releases'::text)) >= 3));

drop policy if exists ws_insert on public.releases;
create policy ws_insert on public.releases as PERMISSIVE for INSERT to authenticated with check ((perm(table_module('releases'::text)) >= 2));

drop policy if exists ws_select on public.releases;
create policy ws_select on public.releases as PERMISSIVE for SELECT to authenticated using ((perm(table_module('releases'::text)) >= 1));

drop policy if exists ws_update on public.releases;
create policy ws_update on public.releases as PERMISSIVE for UPDATE to authenticated using ((perm(table_module('releases'::text)) >= 2)) with check ((perm(table_module('releases'::text)) >= 2));

drop policy if exists ws_read on public.roles;
create policy ws_read on public.roles as PERMISSIVE for SELECT to authenticated using (is_active_user());

drop policy if exists ws_write on public.roles;
create policy ws_write on public.roles as PERMISSIVE for ALL to authenticated using (is_admin()) with check (is_admin());

drop policy if exists ws_delete on public.seo_keywords;
create policy ws_delete on public.seo_keywords as PERMISSIVE for DELETE to authenticated using ((perm(table_module('seo_keywords'::text)) >= 3));

drop policy if exists ws_insert on public.seo_keywords;
create policy ws_insert on public.seo_keywords as PERMISSIVE for INSERT to authenticated with check ((perm(table_module('seo_keywords'::text)) >= 2));

drop policy if exists ws_select on public.seo_keywords;
create policy ws_select on public.seo_keywords as PERMISSIVE for SELECT to authenticated using ((perm(table_module('seo_keywords'::text)) >= 1));

drop policy if exists ws_update on public.seo_keywords;
create policy ws_update on public.seo_keywords as PERMISSIVE for UPDATE to authenticated using ((perm(table_module('seo_keywords'::text)) >= 2)) with check ((perm(table_module('seo_keywords'::text)) >= 2));

drop policy if exists ws_read on public.settings;
create policy ws_read on public.settings as PERMISSIVE for SELECT to authenticated using (is_active_user());

drop policy if exists ws_write on public.settings;
create policy ws_write on public.settings as PERMISSIVE for ALL to authenticated using (is_admin()) with check (is_admin());

drop policy if exists ws_delete on public.social_stats;
create policy ws_delete on public.social_stats as PERMISSIVE for DELETE to authenticated using ((perm(table_module('social_stats'::text)) >= 3));

drop policy if exists ws_insert on public.social_stats;
create policy ws_insert on public.social_stats as PERMISSIVE for INSERT to authenticated with check ((perm(table_module('social_stats'::text)) >= 2));

drop policy if exists ws_select on public.social_stats;
create policy ws_select on public.social_stats as PERMISSIVE for SELECT to authenticated using ((perm(table_module('social_stats'::text)) >= 1));

drop policy if exists ws_update on public.social_stats;
create policy ws_update on public.social_stats as PERMISSIVE for UPDATE to authenticated using ((perm(table_module('social_stats'::text)) >= 2)) with check ((perm(table_module('social_stats'::text)) >= 2));

drop policy if exists ws_delete on public.sprints;
create policy ws_delete on public.sprints as PERMISSIVE for DELETE to authenticated using ((perm(table_module('sprints'::text)) >= 3));

drop policy if exists ws_insert on public.sprints;
create policy ws_insert on public.sprints as PERMISSIVE for INSERT to authenticated with check ((perm(table_module('sprints'::text)) >= 2));

drop policy if exists ws_select on public.sprints;
create policy ws_select on public.sprints as PERMISSIVE for SELECT to authenticated using ((perm(table_module('sprints'::text)) >= 1));

drop policy if exists ws_update on public.sprints;
create policy ws_update on public.sprints as PERMISSIVE for UPDATE to authenticated using ((perm(table_module('sprints'::text)) >= 2)) with check ((perm(table_module('sprints'::text)) >= 2));

drop policy if exists ws_insert on public.status_events;
create policy ws_insert on public.status_events as PERMISSIVE for INSERT to authenticated with check (((user_id = auth.uid()) AND (kind = ANY (ARRAY['warned'::text, 'im_here'::text]))));

drop policy if exists ws_select on public.status_events;
create policy ws_select on public.status_events as PERMISSIVE for SELECT to authenticated using (((user_id = auth.uid()) OR is_admin()));

drop policy if exists ws_delete on public.targets;
create policy ws_delete on public.targets as PERMISSIVE for DELETE to authenticated using ((perm('sales'::text) >= 3));

drop policy if exists ws_insert on public.targets;
create policy ws_insert on public.targets as PERMISSIVE for INSERT to authenticated with check ((perm('sales'::text) >= 3));

drop policy if exists ws_select on public.targets;
create policy ws_select on public.targets as PERMISSIVE for SELECT to authenticated using (((perm('sales'::text) >= 1) OR (is_active_user() AND (user_id = auth.uid()))));

drop policy if exists ws_update on public.targets;
create policy ws_update on public.targets as PERMISSIVE for UPDATE to authenticated using ((perm('sales'::text) >= 3)) with check ((perm('sales'::text) >= 3));

drop policy if exists ws_select on public.task_events;
create policy ws_select on public.task_events as PERMISSIVE for SELECT to authenticated using ((is_active_user() AND (EXISTS ( SELECT 1
   FROM tasks t
  WHERE (t.id = task_events.task_id)))));

drop policy if exists ws_delete on public.tasks;
create policy ws_delete on public.tasks as PERMISSIVE for DELETE to authenticated using (is_task_handler(vertical));

drop policy if exists ws_insert on public.tasks;
create policy ws_insert on public.tasks as PERMISSIVE for INSERT to authenticated with check ((is_task_handler(vertical) OR (is_active_user() AND ((vertical = my_vertical()) OR (assignee_id = auth.uid())))));

drop policy if exists ws_select on public.tasks;
create policy ws_select on public.tasks as PERMISSIVE for SELECT to authenticated using ((is_task_handler(vertical) OR (is_active_user() AND ((((auth.uid() = assignee_id) OR (auth.uid() = reviewer_id)) OR (auth.uid() = created_by)) OR (auth.uid() = ANY (collaborators)) OR (auth.uid() = ANY (mentions)))) OR ((perm('tasks'::text) >= 1) AND (vertical = my_vertical()))));

drop policy if exists ws_update on public.tasks;
create policy ws_update on public.tasks as PERMISSIVE for UPDATE to authenticated using ((is_task_handler(vertical) OR (is_active_user() AND (((auth.uid() = assignee_id) OR (auth.uid() = reviewer_id)) OR (auth.uid() = ANY (collaborators)))))) with check ((is_task_handler(vertical) OR (is_active_user() AND (((auth.uid() = assignee_id) OR (auth.uid() = reviewer_id)) OR (auth.uid() = ANY (collaborators))))));

drop policy if exists ws_delete on public.test_cases;
create policy ws_delete on public.test_cases as PERMISSIVE for DELETE to authenticated using ((perm('qa'::text) >= 3));

drop policy if exists ws_insert on public.test_cases;
create policy ws_insert on public.test_cases as PERMISSIVE for INSERT to authenticated with check ((perm('qa'::text) >= 3));

drop policy if exists ws_select on public.test_cases;
create policy ws_select on public.test_cases as PERMISSIVE for SELECT to authenticated using (((perm('qa'::text) >= 1) OR ((auth.uid() = assignee_id) OR (auth.uid() = tester_id))));

drop policy if exists ws_update on public.test_cases;
create policy ws_update on public.test_cases as PERMISSIVE for UPDATE to authenticated using (((perm('qa'::text) >= 3) OR ((perm('qa'::text) >= 2) AND (auth.uid() = assignee_id)))) with check (((perm('qa'::text) >= 3) OR ((perm('qa'::text) >= 2) AND (auth.uid() = assignee_id))));

drop policy if exists ws_insert on public.test_runs;
create policy ws_insert on public.test_runs as PERMISSIVE for INSERT to authenticated with check (((perm('qa'::text) >= 3) AND (tester_id = auth.uid())));

drop policy if exists ws_select on public.test_runs;
create policy ws_select on public.test_runs as PERMISSIVE for SELECT to authenticated using ((perm('qa'::text) >= 1));

drop policy if exists ws_delete on public.tickets;
create policy ws_delete on public.tickets as PERMISSIVE for DELETE to authenticated using ((perm(table_module('tickets'::text)) >= 3));

drop policy if exists ws_insert on public.tickets;
create policy ws_insert on public.tickets as PERMISSIVE for INSERT to authenticated with check ((perm(table_module('tickets'::text)) >= 2));

drop policy if exists ws_select on public.tickets;
create policy ws_select on public.tickets as PERMISSIVE for SELECT to authenticated using ((perm(table_module('tickets'::text)) >= 1));

drop policy if exists ws_update on public.tickets;
create policy ws_update on public.tickets as PERMISSIVE for UPDATE to authenticated using ((perm(table_module('tickets'::text)) >= 2)) with check ((perm(table_module('tickets'::text)) >= 2));

drop policy if exists ws_insert on public.user_status;
create policy ws_insert on public.user_status as PERMISSIVE for INSERT to authenticated with check ((user_id = auth.uid()));

drop policy if exists ws_select on public.user_status;
create policy ws_select on public.user_status as PERMISSIVE for SELECT to authenticated using (is_active_user());

drop policy if exists ws_update on public.user_status;
create policy ws_update on public.user_status as PERMISSIVE for UPDATE to authenticated using ((user_id = auth.uid())) with check ((user_id = auth.uid()));

drop policy if exists ws_delete on public.work_logs;
create policy ws_delete on public.work_logs as PERMISSIVE for DELETE to authenticated using (((user_id = auth.uid()) OR is_admin()));

drop policy if exists ws_insert on public.work_logs;
create policy ws_insert on public.work_logs as PERMISSIVE for INSERT to authenticated with check (((user_id = auth.uid()) AND is_active_user() AND can_see('tasks'::text, task_id) AND (work_date <= ((now() AT TIME ZONE 'Asia/Kolkata'::text))::date)));

drop policy if exists ws_select on public.work_logs;
create policy ws_select on public.work_logs as PERMISSIVE for SELECT to authenticated using ((is_active_user() AND can_see('tasks'::text, task_id)));

drop policy if exists ws_update on public.work_logs;
create policy ws_update on public.work_logs as PERMISSIVE for UPDATE to authenticated using (((user_id = auth.uid()) OR is_admin())) with check ((((user_id = auth.uid()) OR is_admin()) AND (work_date <= ((now() AT TIME ZONE 'Asia/Kolkata'::text))::date)));

do $x$ begin alter publication supabase_realtime add table public.activities; exception when duplicate_object then null; end $x$;

do $x$ begin alter publication supabase_realtime add table public.announcements; exception when duplicate_object then null; end $x$;

do $x$ begin alter publication supabase_realtime add table public.attendance; exception when duplicate_object then null; end $x$;

do $x$ begin alter publication supabase_realtime add table public.calendar_events; exception when duplicate_object then null; end $x$;

do $x$ begin alter publication supabase_realtime add table public.campaigns; exception when duplicate_object then null; end $x$;

do $x$ begin alter publication supabase_realtime add table public.chat_channels; exception when duplicate_object then null; end $x$;

do $x$ begin alter publication supabase_realtime add table public.chat_messages; exception when duplicate_object then null; end $x$;

do $x$ begin alter publication supabase_realtime add table public.chat_reads; exception when duplicate_object then null; end $x$;

do $x$ begin alter publication supabase_realtime add table public.clients; exception when duplicate_object then null; end $x$;

do $x$ begin alter publication supabase_realtime add table public.comments; exception when duplicate_object then null; end $x$;

do $x$ begin alter publication supabase_realtime add table public.contacts; exception when duplicate_object then null; end $x$;

do $x$ begin alter publication supabase_realtime add table public.content; exception when duplicate_object then null; end $x$;

do $x$ begin alter publication supabase_realtime add table public.deals; exception when duplicate_object then null; end $x$;

do $x$ begin alter publication supabase_realtime add table public.documents; exception when duplicate_object then null; end $x$;

do $x$ begin alter publication supabase_realtime add table public.emails; exception when duplicate_object then null; end $x$;

do $x$ begin alter publication supabase_realtime add table public.features; exception when duplicate_object then null; end $x$;

do $x$ begin alter publication supabase_realtime add table public.files; exception when duplicate_object then null; end $x$;

do $x$ begin alter publication supabase_realtime add table public.google_links; exception when duplicate_object then null; end $x$;

do $x$ begin alter publication supabase_realtime add table public.leads; exception when duplicate_object then null; end $x$;

do $x$ begin alter publication supabase_realtime add table public.leave_requests; exception when duplicate_object then null; end $x$;

do $x$ begin alter publication supabase_realtime add table public.meeting_joins; exception when duplicate_object then null; end $x$;

do $x$ begin alter publication supabase_realtime add table public.meetings; exception when duplicate_object then null; end $x$;

do $x$ begin alter publication supabase_realtime add table public.notes; exception when duplicate_object then null; end $x$;

do $x$ begin alter publication supabase_realtime add table public.notifications; exception when duplicate_object then null; end $x$;

do $x$ begin alter publication supabase_realtime add table public.profiles; exception when duplicate_object then null; end $x$;

do $x$ begin alter publication supabase_realtime add table public.projects; exception when duplicate_object then null; end $x$;

do $x$ begin alter publication supabase_realtime add table public.proposals; exception when duplicate_object then null; end $x$;

do $x$ begin alter publication supabase_realtime add table public.record_events; exception when duplicate_object then null; end $x$;

do $x$ begin alter publication supabase_realtime add table public.releases; exception when duplicate_object then null; end $x$;

do $x$ begin alter publication supabase_realtime add table public.roles; exception when duplicate_object then null; end $x$;

do $x$ begin alter publication supabase_realtime add table public.seo_keywords; exception when duplicate_object then null; end $x$;

do $x$ begin alter publication supabase_realtime add table public.settings; exception when duplicate_object then null; end $x$;

do $x$ begin alter publication supabase_realtime add table public.social_stats; exception when duplicate_object then null; end $x$;

do $x$ begin alter publication supabase_realtime add table public.sprints; exception when duplicate_object then null; end $x$;

do $x$ begin alter publication supabase_realtime add table public.targets; exception when duplicate_object then null; end $x$;

do $x$ begin alter publication supabase_realtime add table public.tasks; exception when duplicate_object then null; end $x$;

do $x$ begin alter publication supabase_realtime add table public.test_cases; exception when duplicate_object then null; end $x$;

do $x$ begin alter publication supabase_realtime add table public.tickets; exception when duplicate_object then null; end $x$;

do $x$ begin alter publication supabase_realtime add table public.user_status; exception when duplicate_object then null; end $x$;
