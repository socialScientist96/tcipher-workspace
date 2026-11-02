-- =====================================================================
--  Tcipher Workspace upgrade (run after upgrade-2026-11d.sql)
--  • CRM for Marketing and Sales: lead numbers, lead type, priority, tags, address,
--    zone, Instagram pipeline, website form answers, call outcomes, lead/deal
--    history, tasks linked to leads and deals
--  Run once in Supabase > SQL Editor > New query > Run. Safe to run again.
-- =====================================================================

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
