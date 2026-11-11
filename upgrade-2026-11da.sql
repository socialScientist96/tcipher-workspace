-- upgrade-2026-11da: the Tcipher Workspace Android app (native) registers for notifications through Firebase.
-- claim_native_push() now also takes kind 'fcm' (an Android device's Firebase token), as well as Apple's 'apns'.
-- Run in Supabase › SQL Editor after upgrade-2026-11cz.sql. Safe to run more than once. Changes no data.
create or replace function public.claim_native_push(p_token text, p_kind text, p_device text)
returns text language plpgsql security definer set search_path = public as $$
declare ep text;
begin
  if auth.uid() is null then raise exception 'Sign in again.' using errcode = '42501'; end if;
  if p_kind in ('apns', 'apns-sandbox') then
    if coalesce(p_token, '') !~ '^[0-9a-fA-F]{32,200}$' then raise exception 'That isn’t an Apple device token.'; end if;
    ep := 'apns:' || lower(p_token);
  elsif p_kind = 'fcm' then
    if coalesce(p_token, '') !~ '^[A-Za-z0-9_:-]+$' or length(p_token) not between 20 and 4096 then raise exception 'That isn’t a Firebase device token.'; end if;
    ep := 'fcm:' || p_token;
  else
    raise exception 'Unknown kind.';
  end if;
  insert into public.push_subscriptions (user_id, endpoint, p256dh, auth, device, kind, user_agent)
  values (auth.uid(), ep, '', '', left(coalesce(p_device, 'phone'), 20), p_kind,
          case when p_kind = 'fcm' then 'Tcipher Workspace Android app' else 'Tcipher Workspace iPhone app' end)
  on conflict (endpoint) do update set user_id = excluded.user_id, kind = excluded.kind, device = excluded.device, last_error = '';
  return ep;
end $$;
revoke all on function public.claim_native_push(text, text, text) from public, anon;
grant execute on function public.claim_native_push(text, text, text) to authenticated;

-- check (read-only): 1 means Android tokens are accepted
select count(*) as android_ready from pg_proc where proname = 'claim_native_push' and pg_get_functiondef(oid) like '%fcm%';
