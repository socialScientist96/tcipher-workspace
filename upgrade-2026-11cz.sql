-- upgrade-2026-11cz: phone and desktop notifications (web push), also used by the Tcipher Android app, and Apple
-- notifications (APNs) for the Tcipher iPhone app.
-- - push_subscriptions: one row per device where someone switched notifications on (only they can see or remove it).
--   kind: 'web' (browsers, Android app), 'apns' (iPhone app from TestFlight/App Store), 'apns-sandbox' (built in Xcode).
-- - Every new notification (and every new message in a chat that already had an unread one) asks the "push" Edge
--   Function to send it to that person's devices, at once. The function skips read ones, muted chats and accounts
--   that are off. If anything here fails, the notification itself is still saved as usual.
--
-- Before running:
--   1. Database › Extensions: "pg_net" is on (it already is for Google sync).
--   2. Run this once, with your real CRON_SECRET between the quotes (the same one as in Edge Functions › Secrets),
--      so the database can prove to the push function that it's really the database calling:
--        select vault.create_secret('<CRON_SECRET>', 'cron_secret');
--      (If it says the name already exists, it's already done.)
-- Then run this file in Supabase › SQL Editor. Safe to run more than once. Changes no existing data.

create table if not exists public.push_subscriptions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  endpoint text not null unique,
  p256dh text not null,
  auth text not null,
  device text not null default '',
  kind text not null default 'web',
  user_agent text not null default '',
  created_at timestamptz not null default now(),
  last_ok_at timestamptz,
  last_error text not null default ''
);
alter table public.push_subscriptions add column if not exists kind text not null default 'web';
create index if not exists push_subscriptions_user on public.push_subscriptions (user_id);
alter table public.push_subscriptions enable row level security;
drop policy if exists own_select on public.push_subscriptions;
drop policy if exists own_insert on public.push_subscriptions;
drop policy if exists own_update on public.push_subscriptions;
drop policy if exists own_delete on public.push_subscriptions;
create policy own_select on public.push_subscriptions for select to authenticated using (user_id = auth.uid());
create policy own_insert on public.push_subscriptions for insert to authenticated with check (user_id = auth.uid());
create policy own_update on public.push_subscriptions for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy own_delete on public.push_subscriptions for delete to authenticated using (user_id = auth.uid());
grant select, insert, update, delete on public.push_subscriptions to authenticated;
revoke all on public.push_subscriptions from anon;

-- a device moves to whoever signs in on it last (a shared laptop doesn't keep sending someone else's messages)
create or replace function public.claim_push_subscription(p_endpoint text, p_p256dh text, p_auth text, p_device text, p_ua text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'Sign in again.' using errcode = '42501'; end if;
  if coalesce(p_endpoint, '') !~ '^https://' or coalesce(p_p256dh, '') = '' or coalesce(p_auth, '') = '' then raise exception 'That device didn’t give a push address.'; end if;
  insert into public.push_subscriptions (user_id, endpoint, p256dh, auth, device, user_agent)
  values (auth.uid(), p_endpoint, p_p256dh, p_auth, left(coalesce(p_device, ''), 20), left(coalesce(p_ua, ''), 300))
  on conflict (endpoint) do update set user_id = excluded.user_id, p256dh = excluded.p256dh, auth = excluded.auth,
    device = excluded.device, user_agent = excluded.user_agent, last_error = '';
end $$;
revoke all on function public.claim_push_subscription(text, text, text, text, text) from public, anon;
grant execute on function public.claim_push_subscription(text, text, text, text, text) to authenticated;

-- the iPhone app: its Apple device token (kept as endpoint 'apns:<token>')
create or replace function public.claim_native_push(p_token text, p_kind text, p_device text)
returns text language plpgsql security definer set search_path = public as $$
declare ep text;
begin
  if auth.uid() is null then raise exception 'Sign in again.' using errcode = '42501'; end if;
  if coalesce(p_token, '') !~ '^[0-9a-fA-F]{32,200}$' then raise exception 'That isn’t an Apple device token.'; end if;
  if p_kind not in ('apns', 'apns-sandbox') then raise exception 'Unknown kind.'; end if;
  ep := 'apns:' || lower(p_token);
  insert into public.push_subscriptions (user_id, endpoint, p256dh, auth, device, kind, user_agent)
  values (auth.uid(), ep, '', '', left(coalesce(p_device, 'phone'), 20), p_kind, 'Tcipher iPhone app')
  on conflict (endpoint) do update set user_id = excluded.user_id, kind = excluded.kind, device = excluded.device, last_error = '';
  return ep;
end $$;
revoke all on function public.claim_native_push(text, text, text) from public, anon;
grant execute on function public.claim_native_push(text, text, text) to authenticated;

create or replace function public.push_notification()
returns trigger language plpgsql security definer set search_path = public as $$
declare secret text;
begin
  if new.is_read then return null; end if;
  if tg_op = 'UPDATE' and new.created_at is not distinct from old.created_at then return null; end if;
  begin
    select decrypted_secret into secret from vault.decrypted_secrets where name = 'cron_secret' limit 1;
    if coalesce(secret, '') = '' then return null; end if;
    perform net.http_post(
      url := 'https://pfdnziybqaumnofjknsj.supabase.co/functions/v1/push',
      headers := jsonb_build_object('Content-Type', 'application/json', 'x-cron-secret', secret),
      body := jsonb_build_object('id', new.id));
  exception when others then
    null;   -- push is a nice-to-have: never lose the notification because of it
  end;
  return null;
end $$;
drop trigger if exists push_notification on public.notifications;
create trigger push_notification after insert or update of created_at on public.notifications
  for each row execute function public.push_notification();

-- check (read-only): 1, 1, 1, and 1 if the secret is in the vault
select (select count(*) from pg_class where relname = 'push_subscriptions') as push_table,
       (select count(*) from pg_trigger where tgname = 'push_notification') as push_trigger,
       (select count(*) from pg_extension where extname = 'pg_net') as pg_net_on,
       (select count(*) from vault.secrets where name = 'cron_secret') as secret_in_vault;
