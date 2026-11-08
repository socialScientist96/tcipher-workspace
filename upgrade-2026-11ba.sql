-- upgrade-2026-11ba: saved work summaries (Admin › Work summary).
-- Claude's summary of one person's day, week or month is saved here, so opening it again is instant.
-- Only admins can read them; only the server (the work-summary function) writes them.
-- Run in Supabase › SQL Editor. Safe to run more than once. Changes no existing data.

create table if not exists public.work_summaries (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  period text not null check (period in ('day', 'week', 'month')),
  start_day date not null,
  end_day date not null,
  summary text not null default '',
  model text not null default '',
  activity_count integer not null default 0,
  generated_at timestamptz not null default now(),
  generated_by uuid references public.profiles(id) on delete set null,
  unique (user_id, period, start_day)
);

alter table public.work_summaries enable row level security;

drop policy if exists "admins read work summaries" on public.work_summaries;
create policy "admins read work summaries" on public.work_summaries
  for select to authenticated using (public.is_admin());

-- no insert / update / delete policies: only the server (service role) writes
revoke insert, update, delete on public.work_summaries from anon, authenticated;

-- check (read-only): should return one row, "work_summaries", with row security on
select relname, relrowsecurity from pg_class where relname = 'work_summaries';
