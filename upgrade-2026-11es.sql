-- 2026-11es · WhatsApp Business and Meta Lead Ads
-- 1. whatsapp_messages: every WhatsApp message to and from the business number, attached to a lead (or deal / contact).
--    Readable by whoever can see that lead or deal; written only by the meta-webhook and whatsapp-send functions.
--    People who can see a conversation can mark it read.
-- 2. leads.whatsapp_opted_out_at (someone sent STOP) and leads.source_meta (Meta form, ad, ad set, campaign).
-- 3. A live signal when a message arrives, like every other table (the inbox updates without reloading).
-- Run in Supabase › SQL editor. Safe to run more than once. Nothing changes for anyone until the functions are deployed.

-- 1 -------------------------------------------------------------------------------------------------------------------
create table if not exists public.whatsapp_messages (
  id uuid primary key default gen_random_uuid(),
  wamid text unique,                                   -- Meta's message id: a repeated webhook is ignored
  direction text not null check (direction in ('in', 'out')),
  phone text not null,                                 -- the other person, digits with country code (E.164 without +)
  profile_name text,                                   -- their WhatsApp name (inbound)
  lead_id uuid references public.leads(id) on delete cascade,
  deal_id uuid references public.deals(id) on delete set null,
  contact_id uuid references public.contacts(id) on delete set null,
  type text not null default 'text',                   -- text, image, document, audio, video, sticker, location, template, interactive, button, reaction, unsupported
  body text not null default '',                       -- the text, caption or a short description
  template_name text,
  media_id text,                                       -- Meta's media id (inbound), until it is saved as a file
  file_id uuid references public.files(id) on delete set null,
  meta jsonb not null default '{}'::jsonb,             -- location, button payload, reply-to, file name …
  status text not null default 'received' check (status in ('received', 'sending', 'sent', 'delivered', 'read', 'failed')),
  error_code integer,
  error_text text,
  sent_by uuid references public.profiles(id) on delete set null,
  read_at timestamptz,                                 -- inbound: when someone on the team opened it
  sent_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists whatsapp_messages_phone_idx on public.whatsapp_messages (phone, sent_at desc);
create index if not exists whatsapp_messages_lead_idx on public.whatsapp_messages (lead_id, sent_at desc);
create index if not exists whatsapp_messages_deal_idx on public.whatsapp_messages (deal_id, sent_at desc) where deal_id is not null;
create index if not exists whatsapp_messages_sent_idx on public.whatsapp_messages (sent_at desc);

alter table public.whatsapp_messages enable row level security;
drop policy if exists ws_select on public.whatsapp_messages;
create policy ws_select on public.whatsapp_messages for select to authenticated using (
  public.is_active_user() and (
    (lead_id is not null and public.can_see('leads', lead_id)) or
    (deal_id is not null and public.can_see('deals', deal_id)) or
    (contact_id is not null and public.can_see('contacts', contact_id))));
drop policy if exists ws_read on public.whatsapp_messages;
create policy ws_read on public.whatsapp_messages for update to authenticated using (
  public.is_active_user() and direction = 'in' and (
    (lead_id is not null and public.can_see('leads', lead_id)) or
    (deal_id is not null and public.can_see('deals', deal_id)) or
    (contact_id is not null and public.can_see('contacts', contact_id))));
-- the team can only mark messages read; everything else is written by the two functions (service role)
revoke all on public.whatsapp_messages from anon, authenticated;
grant select on public.whatsapp_messages to authenticated;
grant update (read_at) on public.whatsapp_messages to authenticated;

create or replace function public.whatsapp_touch() returns trigger language plpgsql set search_path = public as $$
begin new.updated_at := now(); return new; end $$;
drop trigger if exists whatsapp_touch on public.whatsapp_messages;
create trigger whatsapp_touch before update on public.whatsapp_messages for each row execute function public.whatsapp_touch();

-- 2 -------------------------------------------------------------------------------------------------------------------
alter table public.leads add column if not exists whatsapp_opted_out_at timestamptz;
alter table public.leads add column if not exists source_meta jsonb;   -- {form_id, form_name, ad_id, ad_name, adset_name, campaign_name, platform, leadgen_id}
create index if not exists leads_phone10_idx on public.leads (right(regexp_replace(coalesce(phone, ''), '\D', '', 'g'), 10));

-- who a phone number belongs to (last 10 digits): the newest lead, else a deal, else a contact. Used by the functions only.
create or replace function public.wa_match(p_phone text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare d text := right(regexp_replace(coalesce(p_phone, ''), '\D', '', 'g'), 10); l record; dl record; c record;
begin
  if length(d) < 8 then return '{}'::jsonb; end if;
  select id, deal_id into l from public.leads where right(regexp_replace(coalesce(phone, ''), '\D', '', 'g'), 10) = d order by created_at desc limit 1;
  if found then return jsonb_build_object('lead_id', l.id, 'deal_id', l.deal_id); end if;
  select id, lead_id, contact_id into dl from public.deals where right(regexp_replace(coalesce(phone, ''), '\D', '', 'g'), 10) = d order by created_at desc limit 1;
  if found then return jsonb_build_object('lead_id', dl.lead_id, 'deal_id', dl.id, 'contact_id', dl.contact_id); end if;
  select id into c from public.contacts where right(regexp_replace(coalesce(phone, ''), '\D', '', 'g'), 10) = d order by created_at desc limit 1;
  if found then return jsonb_build_object('contact_id', c.id); end if;
  return '{}'::jsonb;
end $$;
revoke all on function public.wa_match(text) from public, anon, authenticated;
grant execute on function public.wa_match(text) to service_role;

-- 3 -------------------------------------------------------------------------------------------------------------------
drop trigger if exists live_table_signal on public.whatsapp_messages;
create trigger live_table_signal after insert or update or delete on public.whatsapp_messages for each row execute function public.live_table_signal();

-- check (read-only): 1 table, 2 lead columns, 1 live trigger
select (select count(*) from information_schema.tables where table_schema = 'public' and table_name = 'whatsapp_messages') as wa_table,
       (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'leads' and column_name in ('whatsapp_opted_out_at', 'source_meta')) as lead_columns,
       (select count(*) from information_schema.triggers where event_object_table = 'whatsapp_messages' and trigger_name = 'live_table_signal' and event_manipulation = 'INSERT') as live_trigger;
