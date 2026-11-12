-- 2026-11dn · Leads get their ad campaign automatically
-- Website forms already send the ad's tracking code (utm_campaign), stored with each lead, but nobody matched it to a
-- campaign. Now:
--   * each campaign can have a "Tracking code" (the utm_campaign value used in its ads);
--   * a new lead (or a lead that sends another form) without a campaign is matched by that code, or by the campaign's
--     name, ignoring case, spaces and punctuation ("AI Guide – Nov" = "ai_guide_nov");
--   * existing leads without a campaign are matched once, now.
-- Nothing is overwritten: a campaign someone picked by hand stays. Safe to run more than once. Run in Supabase › SQL editor.

alter table public.campaigns add column if not exists utm_code text;

create or replace function public.norm_code(t text) returns text language sql immutable as $$
  select nullif(lower(regexp_replace(coalesce(t, ''), '[^a-zA-Z0-9]+', '', 'g')), '')
$$;

-- the campaign for a tracking code: by code first, then by name; only when exactly one campaign matches
create or replace function public.campaign_for_code(code text) returns uuid language sql stable security definer set search_path to 'public' as $$
  with k as (select public.norm_code(code) as c),
  by_code as (select id from public.campaigns, k where k.c is not null and public.norm_code(utm_code) = k.c),
  by_name as (select id from public.campaigns, k where k.c is not null and public.norm_code(name) = k.c)
  select case when (select count(*) from by_code) = 1 then (select id from by_code)
              when (select count(*) from by_code) = 0 and (select count(*) from by_name) = 1 then (select id from by_name) end
$$;

-- newest form submission's utm_campaign
create or replace function public.lead_utm_campaign(subs jsonb) returns text language sql immutable as $$
  select s->'utm'->>'campaign' from jsonb_array_elements(case when jsonb_typeof(subs) = 'array' then subs else '[]'::jsonb end) with ordinality as x(s, i)
  where coalesce(s->'utm'->>'campaign', '') <> '' order by i desc limit 1
$$;

create or replace function public.lead_match_campaign() returns trigger language plpgsql security definer set search_path to 'public' as $$
begin
  if new.campaign_id is null then new.campaign_id := public.campaign_for_code(public.lead_utm_campaign(new.form_submissions)); end if;
  return new;
end $$;

drop trigger if exists lead_match_campaign on public.leads;
create trigger lead_match_campaign before insert or update of form_submissions on public.leads
  for each row execute function public.lead_match_campaign();

-- one-time: existing leads
update public.leads l set campaign_id = public.campaign_for_code(public.lead_utm_campaign(l.form_submissions))
  where l.campaign_id is null and public.lead_utm_campaign(l.form_submissions) is not null
    and public.campaign_for_code(public.lead_utm_campaign(l.form_submissions)) is not null;
