-- upgrade-2026-11ao: admins with two-step sign-in only get admin rights in a session where they entered the code.
-- Before: a stolen admin password was enough for everything an admin can do.
-- Admins who haven't set up two-step sign-in yet keep working exactly as before (set it up in My profile).
-- Run in Supabase › SQL Editor. Safe to run more than once. Changes no data.

-- "aal2" in the session = the authenticator code was entered at sign-in
create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles where id = auth.uid() and is_active and is_admin)
     and (coalesce(auth.jwt() ->> 'aal', 'aal1') = 'aal2'
          or not exists (select 1 from auth.mfa_factors f where f.user_id = auth.uid() and f.status = 'verified'))
$$;

-- admins get full access to every area through is_admin() (so the rule above applies here too)
create or replace function public.perm(m text)
returns integer language sql stable security definer set search_path = public as $$
  select coalesce((
    select case when public.is_admin() then 3 else
      case coalesce(r.permissions ->> m, 'none')
        when 'manage' then 3 when 'edit' then 2 when 'view' then 1 else 0 end
    end
    from public.profiles p left join public.roles r on r.id = p.role_id
    where p.id = auth.uid() and p.is_active
  ), 0)
$$;

-- check (read-only): who has two-step sign-in turned on
select p.full_name, p.is_admin, exists (select 1 from auth.mfa_factors f where f.user_id = p.id and f.status = 'verified') as two_step_on
from public.profiles p where p.is_active order by p.is_admin desc, p.full_name;
