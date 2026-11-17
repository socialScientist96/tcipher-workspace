-- 2026-11ej · Access per person (Admin › Roles & permissions › "Who can see what")
-- Before: what someone could see came only from their role, so changing one person meant changing everyone with that role.
-- Now each person has their own ticks. To start, everyone gets exactly what their role gives them today, so nothing changes
-- until an admin changes a tick. Super admins (admins) still see everything. A role becomes the starting template for new
-- people (and for someone whose role is changed).
-- Only admins can change anyone's ticks; the database refuses anyone else.
-- Run in Supabase › SQL editor. Safe to run more than once.

alter table public.profiles add column if not exists permissions jsonb;   -- null: follow the role

-- everyone starts with what their role gives them today (only people who don't have their own ticks yet)
update public.profiles p set permissions = coalesce(r.permissions, '{}'::jsonb)
from public.roles r
where r.id = p.role_id and p.permissions is null and not p.is_admin;

-- the access check used by every table's rules: the person's own ticks first, then their role
create or replace function public.perm(m text)
returns integer language sql stable security definer set search_path = public as $$
  select coalesce((
    select case when public.is_admin() then 3 else
      case coalesce(coalesce(p.permissions, r.permissions) ->> m, 'none')
        when 'manage' then 3 when 'edit' then 2 when 'view' then 1 else 0 end
    end
    from public.profiles p left join public.roles r on r.id = p.role_id
    where p.id = auth.uid() and p.is_active
  ), 0)
$$;

-- only admins can change anyone's ticks (including their own)
create or replace function public.protect_profile_permissions() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is not null and not public.is_admin() then
    if tg_op = 'INSERT' then new.permissions := null;
    else new.permissions := old.permissions; end if;
  end if;
  return new;
end $$;
drop trigger if exists protect_profile_permissions on public.profiles;
create trigger protect_profile_permissions before insert or update on public.profiles
  for each row execute function public.protect_profile_permissions();
revoke all on function public.protect_profile_permissions() from public, anon, authenticated;

-- check (read-only): each active person's access source
select p.full_name, case when p.is_admin then 'super admin: everything' when p.permissions is not null then 'own ticks' else 'role' end as access
from public.profiles p where p.is_active and p.client_id is null order by p.is_admin desc, p.full_name;
