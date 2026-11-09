-- upgrade-2026-11cg: the Tcipher Tracker browser extension (Chrome and Edge).
-- The extension records which website is in front and for how long, only while the browser is the window in use and
-- the person isn't idle. It keeps the website's name only (github.com), never the full address or what's on the page,
-- and nothing from incognito windows. People can pause it; pauses are recorded as "(paused)".
-- Connecting: in the workspace, Work summary › Connect this browser. That gives the extension its own key, kept only as
-- a fingerprint here; disconnecting turns the key off.
-- Only admins and people who can see attendance can read other people's website time; everyone can read their own.
-- Run in Supabase › SQL Editor. Safe to run more than once. Changes no existing data.

create table if not exists public.tracker_keys (
  key_hash text primary key,                               -- sha-256 of the key; the key itself is never stored
  user_id uuid not null references public.profiles(id) on delete cascade,
  browser text not null default '',
  created_at timestamptz not null default now(),
  last_used_at timestamptz,
  revoked_at timestamptz
);
alter table public.tracker_keys enable row level security;
drop policy if exists ws_select on public.tracker_keys;
create policy ws_select on public.tracker_keys for select to authenticated
  using (public.is_active_user() and (user_id = auth.uid() or public.is_admin()));
revoke insert, update, delete on public.tracker_keys from anon, authenticated;
grant select on public.tracker_keys to authenticated;

create table if not exists public.web_minutes (
  user_id uuid not null references public.profiles(id) on delete cascade,
  day date not null,                                        -- India time
  minute smallint not null check (minute between 0 and 1439),
  domain text not null,
  seconds smallint not null default 0 check (seconds between 0 and 60),
  primary key (user_id, day, minute, domain)
);
alter table public.web_minutes enable row level security;
drop policy if exists ws_select on public.web_minutes;
create policy ws_select on public.web_minutes for select to authenticated
  using (public.is_active_user() and (user_id = auth.uid() or public.is_admin() or public.perm('attendance') >= 1));
revoke insert, update, delete on public.web_minutes from anon, authenticated;
grant select on public.web_minutes to authenticated;

-- the workspace asks for a key for this browser; the extension keeps it
create or replace function public.tracker_connect(p_browser text)
returns text language plpgsql security definer set search_path = public as $$
declare k text;
begin
  if auth.uid() is null or not public.is_active_user() then raise exception 'Sign in first' using errcode = '42501'; end if;
  k := 'tct_' || replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', '');
  insert into public.tracker_keys (key_hash, user_id, browser) values (encode(sha256(convert_to(k, 'UTF8')), 'hex'), auth.uid(), left(coalesce(p_browser, ''), 80));
  return k;
end $$;
revoke all on function public.tracker_connect(text) from public, anon;
grant execute on function public.tracker_connect(text) to authenticated;

-- turn off one of your keys (or, for admins, anyone's)
create or replace function public.tracker_disconnect(p_key_hash text)
returns void language plpgsql security definer set search_path = public as $$
begin
  update public.tracker_keys set revoked_at = coalesce(revoked_at, now())
  where key_hash = p_key_hash and (user_id = auth.uid() or public.is_admin());
end $$;
revoke all on function public.tracker_disconnect(text) from public, anon;
grant execute on function public.tracker_disconnect(text) to authenticated;

-- the extension sends what it saw, a few minutes at a time:
-- p_minutes = [{"t": <start of the minute, ms since 1970>, "d": "github.com", "s": 30}, ...]
-- returns 'ok', or 'disconnected' when the key is unknown or turned off (the extension then asks to connect again)
create or replace function public.tracker_ping(p_key text, p_minutes jsonb)
returns text language plpgsql security definer set search_path = public as $$
declare
  kh text := encode(sha256(convert_to(coalesce(p_key, ''), 'UTF8')), 'hex');
  uid uuid; x jsonb; ts timestamptz; t timestamp; dm text; sec int;
begin
  select user_id into uid from public.tracker_keys where key_hash = kh and revoked_at is null;
  if uid is null then return 'disconnected'; end if;
  if not exists (select 1 from public.profiles where id = uid and is_active and client_id is null) then return 'disconnected'; end if;
  update public.tracker_keys set last_used_at = now() where key_hash = kh;
  if jsonb_typeof(p_minutes) <> 'array' then return 'ok'; end if;
  for x in select value from jsonb_array_elements(p_minutes) limit 240 loop
    begin
      ts := to_timestamp((x->>'t')::double precision / 1000);
      if ts < now() - interval '3 days' or ts > now() + interval '2 minutes' then continue; end if;
      t := ts at time zone 'Asia/Kolkata';
      dm := lower(left(regexp_replace(coalesce(x->>'d', ''), '[^A-Za-z0-9.()_ -]', '', 'g'), 100));
      sec := least(greatest(coalesce((x->>'s')::int, 0), 0), 60);
      if dm = '' or sec = 0 then continue; end if;
      insert into public.web_minutes as w (user_id, day, minute, domain, seconds)
      values (uid, t::date, (extract(hour from t) * 60 + extract(minute from t))::smallint, dm, sec)
      on conflict (user_id, day, minute, domain) do update set seconds = least(w.seconds + excluded.seconds, 60);
    exception when others then null;   -- skip a bad entry, keep the rest
    end;
  end loop;
  return 'ok';
end $$;
revoke all on function public.tracker_ping(text, jsonb) from public;
grant execute on function public.tracker_ping(text, jsonb) to anon, authenticated;

-- website time for a person and a range of days: the top sites, and the total
create or replace function public.web_summary(p_user uuid, p_start date, p_end date)
returns json language plpgsql stable security definer set search_path = public as $$
declare r json;
begin
  if auth.uid() is null or not public.is_active_user()
     or not (p_user = auth.uid() or public.is_admin() or public.perm('attendance') >= 1) then
    raise exception 'Not allowed' using errcode = '42501';
  end if;
  select json_build_object(
    'minutes', (select count(distinct (day, minute)) from public.web_minutes where user_id = p_user and day between p_start and p_end and domain <> '(paused)'),
    'paused', (select count(distinct (day, minute)) from public.web_minutes where user_id = p_user and day between p_start and p_end and domain = '(paused)'),
    'sites', coalesce((select json_agg(json_build_object('domain', domain, 'seconds', s) order by s desc) from (
       select domain, sum(seconds)::int s from public.web_minutes where user_id = p_user and day between p_start and p_end and domain <> '(paused)'
       group by domain order by s desc limit 25) z), '[]'::json),
    'connected', (select max(last_used_at) from public.tracker_keys where user_id = p_user and revoked_at is null))
  into r;
  return r;
end $$;
revoke all on function public.web_summary(uuid, date, date) from public, anon;
grant execute on function public.web_summary(uuid, date, date) to authenticated;

-- check (read-only): 2 tables, 4 functions
select (select count(*) from pg_class where relname in ('tracker_keys', 'web_minutes')) as tables,
       (select count(*) from pg_proc where proname in ('tracker_connect', 'tracker_disconnect', 'tracker_ping', 'web_summary')) as functions;
