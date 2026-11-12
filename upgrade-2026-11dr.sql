-- 2026-11dr · WhatsApp consent on leads, and campaign names for Sales
-- * leads remember when and where the person agreed to be contacted on WhatsApp (website form checkbox, booking
--   page checkbox, or ticked by hand). WhatsApp Business needs this consent before messaging people.
-- * campaign_names(): anyone signed in can see a campaign's NAME (not its budget or other details), so Sales sees
--   which campaign a lead came from without getting access to Marketing.
-- Run in Supabase › SQL editor. Safe to run more than once.

alter table public.leads add column if not exists whatsapp_consent_at timestamptz;
alter table public.leads add column if not exists whatsapp_consent_source text not null default '';

create or replace function public.campaign_names() returns table (id uuid, name text)
language sql stable security definer set search_path = public as $$
  select c.id, c.name from public.campaigns c where public.is_active_user();
$$;
revoke all on function public.campaign_names() from public, anon;
grant execute on function public.campaign_names() to authenticated;
