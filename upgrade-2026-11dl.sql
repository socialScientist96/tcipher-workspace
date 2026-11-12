-- 2026-11dl · Channel messages notify everyone who can see the channel
-- Before: a channel message only notified people who were @mentioned ("Notifications not received for channel messages").
-- Now:    every active staff member who can see the channel gets one notification per channel (newer messages update it),
--         except people who muted the channel. An @mention still reaches a muted person and reads "mentioned you".
-- DMs and groups are unchanged. Safe to run more than once. Run in Supabase › SQL editor.

CREATE OR REPLACE FUNCTION public.notify_chat_message()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare ch record; who uuid; author text; t text; targets uuid[]; body_txt text; tagged boolean;
begin
  select * into ch from public.chat_channels where id = new.channel_id;
  if not found then return null; end if;
  select full_name into author from public.profiles where id = new.author_id;
  author := coalesce(author, 'Someone');
  body_txt := left(coalesce(nullif(new.body, ''), '📎 ' || coalesce(new.attachments->0->>'name', 'a file')), 160);
  if ch.kind in ('dm', 'group') then
    targets := ch.members;
  else
    -- everyone who can see the channel (staff only), plus anyone tagged
    select array_agg(p.id) into targets from public.profiles p
      where p.is_active and p.client_id is null and (ch.vertical is null or p.is_admin or p.vertical = ch.vertical);
    targets := coalesce(targets, '{}') || coalesce(new.mentions, '{}');
  end if;
  for who in select distinct x from unnest(coalesce(targets, '{}')) as x loop
    continue when who is null or who = new.author_id;
    tagged := who = any(coalesce(new.mentions, '{}'));
    if ch.kind = 'channel' then
      -- a channel mention only reaches people who can see that channel
      if ch.vertical is not null and not exists (
        select 1 from public.profiles p where p.id = who and p.is_active and (p.is_admin or p.vertical = ch.vertical)) then
        continue;
      end if;
      -- muted channel: only a mention gets through
      continue when not tagged and exists (select 1 from public.chat_mutes m where m.user_id = who and m.channel_id = ch.id);
    end if;
    t := case when ch.kind = 'dm' then 'Message from ' || author
              when ch.kind = 'group' then author || ' in ' || coalesce(nullif(ch.name, ''), 'a group')
              when tagged then author || ' mentioned you in #' || ch.name
              else author || ' in #' || ch.name end;
    if exists (select 1 from public.notifications n where n.user_id = who and n.tbl = 'chat' and n.entity_id = new.channel_id and not n.is_read) then
      -- keep "mentioned you" if an earlier unread message tagged them
      update public.notifications set title = case when title like '%mentioned you%' and not tagged then title else t end, body = body_txt, created_at = now()
        where user_id = who and tbl = 'chat' and entity_id = new.channel_id and not is_read;
    else
      insert into public.notifications (user_id, title, body, tbl, entity_id, created_by)
      values (who, t, body_txt, 'chat', new.channel_id, new.author_id);
    end if;
  end loop;
  return null;
end $function$;
