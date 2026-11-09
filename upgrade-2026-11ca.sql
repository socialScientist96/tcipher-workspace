-- upgrade-2026-11ca: clients are private to the people given access.
-- Who can see a client (and its contacts and client-portal people):
--   - admins, and people whose role includes "Sales: clients & contacts" (as before),
--   - the client's account owner,
--   - people added to the client's new "Team access" list.
-- Everyone else on the team doesn't see the client at all (not in Clients, not in pickers, not its people).
-- Only admins, people whose role can edit clients, and the account owner can change Team access.
-- Run in Supabase › SQL Editor. Safe to run more than once. Changes no existing data.

alter table public.clients add column if not exists team_access uuid[] not null default '{}'::uuid[];

-- reading a client
drop policy if exists ws_select on public.clients;
create policy ws_select on public.clients as permissive for select to authenticated using (
  public.perm(public.table_module('clients')) >= 1
  or (public.is_active_user() and (owner_id = auth.uid() or auth.uid() = any (team_access))));

-- changing a client: people whose role can edit clients, or its account owner
drop policy if exists ws_update on public.clients;
create policy ws_update on public.clients as permissive for update to authenticated
  using (public.perm(public.table_module('clients')) >= 2 or (public.is_active_user() and owner_id = auth.uid()))
  with check (public.perm(public.table_module('clients')) >= 2 or (public.is_active_user() and owner_id = auth.uid()));

-- an account owner who isn't a clients editor can't hand the client to someone else or change who has access
create or replace function public.clients_owner_guard()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is not null and public.perm(public.table_module('clients')) < 2 then
    new.owner_id := old.owner_id;
  end if;
  return new;
end $$;
drop trigger if exists clients_owner_guard on public.clients;
create trigger clients_owner_guard before update on public.clients for each row execute function public.clients_owner_guard();

-- contacts follow their client
drop policy if exists ws_select on public.contacts;
create policy ws_select on public.contacts as permissive for select to authenticated using (
  public.perm(public.table_module('contacts')) >= 1
  or (public.is_active_user() and client_id is not null and public.can_see('clients', client_id)));

-- client-portal people are visible only to those who can see their client
drop policy if exists ws_read on public.profiles;
create policy ws_read on public.profiles as permissive for select to authenticated using (
  id = auth.uid()
  or (public.is_active_user() and (client_id is null or public.can_see('clients', client_id))));

-- check (read-only)
select (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'clients' and column_name = 'team_access') as team_access_column,
       (select count(*) from pg_trigger where tgname = 'clients_owner_guard') as owner_guard;
