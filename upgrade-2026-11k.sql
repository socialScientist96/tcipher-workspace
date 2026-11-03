-- =====================================================================
--  Tcipher Workspace upgrade (run after upgrade-2026-11i.sql)
--  • Chat messages create notifications (direct, group, @mentions)
--  • Live updates switched on for chat and notifications
--  • “Seen” in conversations
--  Run once in Supabase > SQL Editor > New query > Run. Safe to run again.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 26. Chat notifications: direct and group messages notify the other people in the conversation,
--     @mentions in channels notify the person tagged. One notification per conversation,
--     kept up to date until it's read, so a busy chat doesn't flood the bell.
-- ---------------------------------------------------------------------
create or replace function public.notify_chat_message() returns trigger
language plpgsql security definer set search_path = public as $$
declare ch record; who uuid; author text; t text; targets uuid[];
begin
  select * into ch from public.chat_channels where id = new.channel_id;
  if not found then return null; end if;
  select full_name into author from public.profiles where id = new.author_id;
  author := coalesce(author, 'Someone');
  if ch.kind in ('dm', 'group') then targets := ch.members; else targets := new.mentions; end if;
  for who in select distinct x from unnest(coalesce(targets, '{}')) as x loop
    continue when who is null or who = new.author_id;
    -- a channel mention only reaches people who can see that channel
    if ch.kind = 'channel' and ch.vertical is not null and not exists (
      select 1 from public.profiles p where p.id = who and p.is_active and (p.is_admin or p.vertical = ch.vertical)) then
      continue;
    end if;
    t := case when ch.kind = 'dm' then 'Message from ' || author
              when ch.kind = 'group' then author || ' in ' || coalesce(nullif(ch.name, ''), 'a group')
              else author || ' mentioned you in #' || ch.name end;
    if exists (select 1 from public.notifications n where n.user_id = who and n.tbl = 'chat' and n.entity_id = new.channel_id and not n.is_read) then
      update public.notifications set title = t, body = left(new.body, 160), created_at = now()
        where user_id = who and tbl = 'chat' and entity_id = new.channel_id and not is_read;
    else
      insert into public.notifications (user_id, title, body, tbl, entity_id, created_by)
      values (who, t, left(new.body, 160), 'chat', new.channel_id, new.author_id);
    end if;
  end loop;
  return null;
end $$;
drop trigger if exists notify_chat_message on public.chat_messages;
create trigger notify_chat_message after insert on public.chat_messages
  for each row execute function public.notify_chat_message();
-- reading a conversation clears its notification
create or replace function public.clear_chat_notifications() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  update public.notifications set is_read = true where user_id = new.user_id and tbl = 'chat' and entity_id = new.channel_id and not is_read;
  return null;
end $$;
drop trigger if exists clear_chat_notifications on public.chat_reads;
create trigger clear_chat_notifications after insert or update on public.chat_reads
  for each row execute function public.clear_chat_notifications();
-- make sure live updates are switched on for chat and notifications
do $$
declare t text;
begin
  foreach t in array array['chat_messages','chat_channels','notifications'] loop
    begin execute format('alter publication supabase_realtime add table public.%I', t); exception when duplicate_object then null; end;
  end loop;
end $$;

-- "Seen" in conversations: people in the same conversation can see how far the others have read (nothing else)
drop policy if exists ws_all on public.chat_reads;
drop policy if exists ws_select on public.chat_reads;
drop policy if exists ws_write on public.chat_reads;
drop policy if exists ws_update on public.chat_reads;
create policy ws_select on public.chat_reads for select to authenticated using (user_id = auth.uid() or public.can_chat(channel_id));
create policy ws_write on public.chat_reads for insert to authenticated with check (user_id = auth.uid());
create policy ws_update on public.chat_reads for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
do $$
begin
  begin alter publication supabase_realtime add table public.chat_reads; exception when duplicate_object then null; end;
end $$;
