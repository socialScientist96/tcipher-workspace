-- 2026-11ea · Live updates by broadcast (less database disk use)
-- Until now every open tab asked Supabase to watch 39 tables ("postgres_changes"). Each connection recorded a
-- subscription per table, removed it again on every reconnect, and had every change checked against every user.
-- Now the database itself sends a short signal ("tasks changed", never the data) on the existing private "ws-live"
-- channel, at most once per table per save. Each browser then reloads that table through the normal access rules,
-- as it did before.
-- Not signalled here, because they have their own signals or backup checks: chat messages, chat reads,
-- notifications, and google_links (Google token refreshes, which nobody needs to see live).
-- Run in Supabase › SQL editor BEFORE the 2026-11ea app release goes live. Safe to run more than once.

create or replace function public.live_table_signal() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  r record;
  k text := 'tcipher_sig.' || tg_table_name;
begin
  begin
    if tg_op = 'DELETE' then r := old; else r := new; end if;
    if tg_table_name in ('comments', 'files') then
      -- one per row (rare): only the open item's comments or files section refreshes
      perform realtime.send(jsonb_build_object('t', tg_table_name, 'tbl', r.tbl, 'eid', r.entity_id), 'chg', 'ws-live', true);
    elsif tg_table_name = 'profiles' then
      perform realtime.send(jsonb_build_object('t', 'profiles', 'pid', r.id), 'chg', 'ws-live', true);
    else
      -- one signal per table per save, however many rows it touched (e.g. a Google sync of 200 events)
      if current_setting(k, true) = '1' then return null; end if;
      perform set_config(k, '1', true);
      perform realtime.send(jsonb_build_object('t', tg_table_name), 'chg', 'ws-live', true);
    end if;
  exception when others then null;   -- a live signal must never stop a save
  end;
  return null;
end $$;
revoke all on function public.live_table_signal() from public, anon, authenticated;

do $$
declare t text;
begin
  for t in
    select c.relname from pg_publication_tables p
    join pg_class c on c.relname = p.tablename
    join pg_namespace n on n.oid = c.relnamespace and n.nspname = p.schemaname
    where p.pubname = 'supabase_realtime' and p.schemaname = 'public' and c.relkind = 'r'
      and p.tablename not in ('chat_messages', 'chat_reads', 'notifications', 'google_links')
  loop
    execute format('drop trigger if exists live_table_signal on public.%I', t);
    execute format('create trigger live_table_signal after insert or update or delete on public.%I for each row execute function public.live_table_signal()', t);
  end loop;
end $$;

-- Check: the tables that now send signals (expect about 35)
select event_object_table as table_name from information_schema.triggers
where trigger_name = 'live_table_signal' and event_manipulation = 'INSERT' order by 1;
