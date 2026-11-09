-- upgrade-2026-11cf: time in the workspace, counted right when people use several browsers or devices at once.
-- Before: one "last seen" per person, so two browsers overwrote each other and the device kept flipping.
-- Now every browser (app 2026-11cn and later) checks in twice a minute, and each minute of the day is kept once per person:
--   - which devices had the workspace on screen in that minute (laptop, phone, tablet; several at once is fine),
--   - on which of them the person was actually active (typing, clicking or scrolling in the last 2 minutes),
--   - how many browsers had it open (2 or more means parallel browsers).
-- A minute counts once however many browsers are open, so totals are real time, never doubled.
-- Only admins and people who can see attendance can read other people's minutes; everyone can read their own.
-- Run in Supabase › SQL Editor. Safe to run more than once. Changes no existing data.

create table if not exists public.activity_minutes (
  user_id uuid not null references public.profiles(id) on delete cascade,
  day date not null,                                   -- India time
  minute smallint not null check (minute between 0 and 1439),
  devices smallint not null default 0,                 -- 1 laptop, 2 phone, 4 tablet (added together)
  active smallint not null default 0,                  -- the same, for devices where the person was active
  sessions text[] not null default '{}',               -- the browsers that had it open (short random ids)
  primary key (user_id, day, minute)
);
alter table public.activity_minutes enable row level security;
drop policy if exists ws_select on public.activity_minutes;
create policy ws_select on public.activity_minutes for select to authenticated
  using (public.is_active_user() and (user_id = auth.uid() or public.is_admin() or public.perm('attendance') >= 1));
revoke insert, update, delete on public.activity_minutes from anon, authenticated;
grant select on public.activity_minutes to authenticated;

-- a browser checks in: "I'm on screen on this device, and the person is (or isn't) active"
create or replace function public.usage_ping(p_device text, p_active boolean, p_session text)
returns void language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
  t timestamp := now() at time zone 'Asia/Kolkata';
  b smallint := case p_device when 'laptop' then 1 when 'phone' then 2 when 'tablet' then 4 else 0 end;
  s text := left(regexp_replace(coalesce(p_session, ''), '[^A-Za-z0-9]', '', 'g'), 12);
begin
  if uid is null or b = 0 or not public.is_active_user() then return; end if;
  insert into public.activity_minutes as a (user_id, day, minute, devices, active, sessions)
  values (uid, t::date, (extract(hour from t) * 60 + extract(minute from t))::smallint, b,
          case when p_active then b else 0 end, case when s = '' then '{}' else array[s] end)
  on conflict (user_id, day, minute) do update set
    devices = a.devices | excluded.devices,
    active = a.active | excluded.active,
    sessions = case when s = '' or s = any(a.sessions) or cardinality(a.sessions) >= 8 then a.sessions else a.sessions || s end;
end $$;
revoke all on function public.usage_ping(text, boolean, text) from public, anon;
grant execute on function public.usage_ping(text, boolean, text) to authenticated;

-- totals for a person and a range of days (minutes)
create or replace function public.usage_summary(p_user uuid, p_start date, p_end date)
returns json language plpgsql stable security definer set search_path = public as $$
declare r json;
begin
  if auth.uid() is null or not public.is_active_user()
     or not (p_user = auth.uid() or public.is_admin() or public.perm('attendance') >= 1) then
    raise exception 'Not allowed' using errcode = '42501';
  end if;
  select json_build_object(
    'open', count(*), 'active', count(*) filter (where active <> 0),
    'laptop', count(*) filter (where devices & 1 <> 0), 'laptop_active', count(*) filter (where active & 1 <> 0),
    'phone', count(*) filter (where devices & 2 <> 0), 'phone_active', count(*) filter (where active & 2 <> 0),
    'tablet', count(*) filter (where devices & 4 <> 0), 'tablet_active', count(*) filter (where active & 4 <> 0),
    'parallel', count(*) filter (where cardinality(sessions) > 1),
    'first', min(day + make_interval(mins => minute)), 'last', max(day + make_interval(mins => minute)))
  into r from public.activity_minutes where user_id = p_user and day between p_start and p_end;
  return r;
end $$;
revoke all on function public.usage_summary(uuid, date, date) from public, anon;
grant execute on function public.usage_summary(uuid, date, date) to authenticated;

-- check (read-only): 1, 1, 1
select (select count(*) from pg_class where relname = 'activity_minutes') as minutes_table,
       (select count(*) from pg_proc where proname = 'usage_ping') as ping,
       (select count(*) from pg_proc where proname = 'usage_summary') as summary;
