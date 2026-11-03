-- =====================================================================
--  Tcipher Workspace upgrade (run after upgrade-2026-11k.sql)
--  • Instant chat and notifications on private live channels
--  Run once in Supabase > SQL Editor > New query > Run. Safe to run again.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 27. Instant updates on private live channels (works even when "Allow public access" is off):
--     the database itself sends a short signal ("new message in conversation X", never the text)
--     to that conversation's private channel, and new notifications to each person's own channel.
-- ---------------------------------------------------------------------
create or replace function public.live_chat_signal() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  begin
    perform realtime.send(jsonb_build_object('cid', new.channel_id, 'mid', new.id, 'uid', new.author_id, 'edit', tg_op = 'UPDATE'),
                          'msg', 'chat:' || new.channel_id::text, true);
  exception when others then null;   -- a live signal must never stop a message being saved
  end;
  return null;
end $$;
drop trigger if exists live_chat_signal on public.chat_messages;
create trigger live_chat_signal after insert or update on public.chat_messages
  for each row execute function public.live_chat_signal();

create or replace function public.live_notify_signal() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  begin
    perform realtime.send(jsonb_build_object('id', new.id, 'tbl', new.tbl, 'entity_id', new.entity_id, 'title', new.title),
                          'notif', 'user:' || new.user_id::text, true);
  exception when others then null;
  end;
  return null;
end $$;
drop trigger if exists live_notify_signal on public.notifications;
create trigger live_notify_signal after insert or update of title, created_at on public.notifications
  for each row execute function public.live_notify_signal();

-- who may listen and send on the private channels
--   chat:<conversation>  only the people in that conversation
--   user:<person>        only that person
--   online, ws-live      anyone signed in (online dots, live data changes, which are filtered by the normal access rules)
do $$
begin
  if exists (select 1 from information_schema.tables where table_schema = 'realtime' and table_name = 'messages') then
    execute 'drop policy if exists tc_listen on realtime.messages';
    execute $p$create policy tc_listen on realtime.messages for select to authenticated using (
      public.is_active_user() and (
        (realtime.topic() like 'chat:%' and public.can_chat(substr(realtime.topic(), 6)::uuid))
        or realtime.topic() = 'user:' || auth.uid()::text
        or realtime.topic() in ('online', 'ws-live')))$p$;
    execute 'drop policy if exists tc_send on realtime.messages';
    execute $p$create policy tc_send on realtime.messages for insert to authenticated with check (
      public.is_active_user() and (
        (realtime.topic() like 'chat:%' and public.can_chat(substr(realtime.topic(), 6)::uuid))
        or realtime.topic() = 'online'))$p$;
  end if;
end $$;
