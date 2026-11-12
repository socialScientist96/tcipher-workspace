-- 2026-11dq · Public demo booking page (internal.tcipher.com/book.html)
-- Leads pick a free demo time themselves. The google-sync function shows only free times (no names or events),
-- checks the time again when they book, gives the demo to whoever on the demo team is free, sends the Google
-- Calendar invite with a Meet link from that person's calendar, and puts the demo on the lead.
-- This table keeps a short log of booking attempts so the page can't be flooded (5 tries an hour per address,
-- 2 bookings a week per email). Only the server reads it: no policies, so signed-in users can't.
-- Turn the page on in Admin › Company settings › Demo team. Run in Supabase › SQL editor. Safe to run more than once.

create table if not exists public.booking_log (
  id bigserial primary key,
  ip text not null default '',
  email text not null default '',
  ok boolean not null default false,
  at timestamptz not null default now()
);
alter table public.booking_log enable row level security;
create index if not exists booking_log_ip_at on public.booking_log (ip, at);
create index if not exists booking_log_email_at on public.booking_log (email, at);
revoke all on public.booking_log from anon, authenticated;
