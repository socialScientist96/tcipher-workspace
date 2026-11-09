-- upgrade-2026-11cc: which device people use (phone, tablet or laptop).
-- - Online status: the device of the latest "I'm here" signal is kept with it ("Active 5 min ago on phone").
-- - Attendance: each check-in and check-out remembers the device it was made from.
-- - Work summary: minutes with the workspace open, per person, per day, per device (from the once-a-minute signal
--   the app already sends while it's on screen). Only admins and people who can see attendance can read it.
-- Run in Supabase › SQL Editor. Safe to run more than once. Changes no existing data.

alter table public.presence add column if not exists device text not null default '';
alter table public.attendance add column if not exists check_in_device text not null default '';
alter table public.attendance add column if not exists check_out_device text not null default '';

create table if not exists public.device_usage (
  user_id uuid not null references public.profiles(id) on delete cascade,
  day date not null,
  device text not null check (device in ('phone', 'tablet', 'laptop')),
  minutes numeric(7, 1) not null default 0,
  updated_at timestamptz not null default now(),
  primary key (user_id, day, device)
);
alter table public.device_usage enable row level security;
drop policy if exists ws_select on public.device_usage;
create policy ws_select on public.device_usage for select to authenticated
  using (public.is_active_user() and (user_id = auth.uid() or public.is_admin() or public.perm('attendance') >= 1));
revoke insert, update, delete on public.device_usage from anon, authenticated;
grant select on public.device_usage to authenticated;

-- every "I'm here" signal adds the time since the previous one to that day's total for the device
-- (gaps over 3 minutes mean the workspace wasn't on screen in between, so they don't count)
create or replace function public.count_device_time()
returns trigger language plpgsql security definer set search_path = public as $$
declare gap numeric; d date;
begin
  if new.device not in ('phone', 'tablet', 'laptop') then new.device := coalesce(old.device, ''); return new; end if;
  if tg_op = 'UPDATE' and old.last_seen_at is not null and new.last_seen_at > old.last_seen_at then
    gap := extract(epoch from (new.last_seen_at - old.last_seen_at)) / 60.0;
    if gap <= 3 then
      d := (new.last_seen_at at time zone 'Asia/Kolkata')::date;
      insert into public.device_usage (user_id, day, device, minutes) values (new.user_id, d, new.device, round(least(gap, 1.5), 1))
      on conflict (user_id, day, device) do update set minutes = least(public.device_usage.minutes + excluded.minutes, 1440), updated_at = now();
    end if;
  end if;
  return new;
end $$;
drop trigger if exists count_device_time on public.presence;
create trigger count_device_time before insert or update on public.presence for each row execute function public.count_device_time();

-- check (read-only)
select (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'presence' and column_name = 'device') as presence_device,
       (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'attendance' and column_name in ('check_in_device', 'check_out_device')) as attendance_devices,
       (select count(*) from pg_class where relname = 'device_usage') as usage_table;
