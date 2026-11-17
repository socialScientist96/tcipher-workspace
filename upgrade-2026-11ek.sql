-- 2026-11ek · Finance: billing accounts, invoices, client dues, balance sheet, salaries and salary slips
-- Who sees it: super admins, and anyone ticked for "Finance" in Admin › Roles & permissions (nobody else is ticked to start).
-- Everyone can see their own salary and download their own slips (My salary), never anyone else's.
-- Paying an invoice adds the money to Revenue, and paying a salary slip adds it to Expenses, by themselves.
-- Run in Supabase › SQL editor. Safe to run more than once.

-- 1. Your companies / bank accounts that invoices are raised from ----------------------------------------------------
create table if not exists public.finance_accounts (
  id uuid primary key default gen_random_uuid(),
  name text not null,                                   -- a short label, e.g. "Tcipher India (HDFC)"
  legal_name text not null default '',
  gstin text not null default '', pan text not null default '', lut_number text not null default '',
  address text not null default '', state text not null default '',
  email text not null default '', phone text not null default '',
  bank_name text not null default '', account_name text not null default '', account_number text not null default '',
  ifsc text not null default '', swift text not null default '', upi_id text not null default '',
  invoice_prefix text not null default 'TCT', next_number integer not null default 1,
  terms text not null default '',
  owner_line text not null default '',                  -- e.g. "Prop. Saurabh Mishra"
  signatory text not null default '', signatory_title text not null default '',   -- "Saurabh Mishra", "Proprietor"
  website text not null default '',
  signature text not null default '',                   -- a small signature image (data URL), printed above "Authorised Signatory"
  is_default boolean not null default false,
  created_by uuid default auth.uid(), created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);

-- 2. Invoices ----------------------------------------------------------------------------------------------------------
create table if not exists public.invoices (
  id uuid primary key default gen_random_uuid(),
  number text,                                          -- given when the invoice is issued (never reused)
  account_id uuid references public.finance_accounts(id) on delete restrict,
  client_id uuid references public.clients(id) on delete set null,
  bill_to jsonb not null default '{}'::jsonb,           -- the client's details as printed on the invoice
  kind text not null default 'GST' check (kind in ('GST', 'Export')),
  currency text not null default 'INR',
  issue_date date not null default current_date,
  due_date date,
  status text not null default 'Draft' check (status in ('Draft', 'Issued', 'Sent', 'Paid', 'Cancelled')),
  items jsonb not null default '[]'::jsonb,             -- [{description, sac, qty, rate, gst}]
  place_of_supply text not null default '',
  subtotal numeric not null default 0, cgst numeric not null default 0, sgst numeric not null default 0,
  igst numeric not null default 0, total numeric not null default 0,
  amount_received_inr numeric, paid_on date,
  notes text not null default '',
  sent_at timestamptz,
  created_by uuid default auth.uid(), created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create unique index if not exists invoices_number on public.invoices (number) where number is not null;
-- (also when the tables already existed from an earlier run of this file)
alter table public.finance_accounts add column if not exists owner_line text not null default '';
alter table public.finance_accounts add column if not exists signatory text not null default '';
alter table public.finance_accounts add column if not exists signatory_title text not null default '';
alter table public.finance_accounts add column if not exists website text not null default '';
alter table public.finance_accounts add column if not exists signature text not null default '';
create index if not exists invoices_client on public.invoices (client_id);

-- 3. What each client pays and when the next invoice is due -------------------------------------------------------------
create table if not exists public.client_billing (
  id uuid primary key default gen_random_uuid(),
  client_id uuid not null unique references public.clients(id) on delete cascade,
  cycle text not null default 'Monthly' check (cycle in ('Monthly', 'Quarterly', 'Half-yearly', 'Yearly', 'One-off')),
  amount numeric not null default 0, currency text not null default 'INR',
  description text not null default '', sac text not null default '998314', gst_rate numeric not null default 18,
  next_due date, account_id uuid references public.finance_accounts(id) on delete set null,
  term_count integer,                                   -- e.g. 6 for a 6-month subscription (empty: no end)
  billed_count integer not null default 0,              -- invoices made from this plan so far
  period_start date,                                    -- first day of the next period to bill
  active boolean not null default true,
  created_by uuid default auth.uid(), created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);

-- 4. Balance sheet: money in, money out, what you owe ---------------------------------------------------------------------
create table if not exists public.finance_entries (
  id uuid primary key default gen_random_uuid(),
  kind text not null check (kind in ('Revenue', 'Expense', 'Liability')),
  category text not null default '',
  description text not null default '',
  amount numeric not null default 0,                    -- rupees
  entry_date date not null default current_date,
  account_id uuid references public.finance_accounts(id) on delete set null,
  payment_mode text not null default '', reference text not null default '',
  status text not null default '',                      -- liabilities: Open or Settled
  due_date date, settled_on date,
  invoice_id uuid references public.invoices(id) on delete cascade,
  salary_slip_id uuid,
  auto boolean not null default false,                  -- added by the workspace (invoice paid, salary paid)
  created_by uuid default auth.uid(), created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create index if not exists finance_entries_date on public.finance_entries (entry_date);

-- 5. Salaries -------------------------------------------------------------------------------------------------------------
create table if not exists public.salary_setup (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  monthly_salary numeric not null default 0,
  pan text not null default '', bank_name text not null default '', account_number text not null default '', ifsc text not null default '',
  updated_at timestamptz not null default now()
);
create table if not exists public.salary_slips (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  month date not null,                                  -- the 1st of the month
  salary numeric not null default 0,
  earnings jsonb not null default '[]'::jsonb,          -- extra lines: [{label, amount}]
  deductions jsonb not null default '[]'::jsonb,
  net numeric not null default 0,
  status text not null default 'Draft' check (status in ('Draft', 'Issued', 'Paid')),
  paid_on date, notes text not null default '',
  created_by uuid default auth.uid(), created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  unique (user_id, month)
);
alter table public.finance_entries drop constraint if exists finance_entries_salary_slip_id_fkey;
alter table public.finance_entries add constraint finance_entries_salary_slip_id_fkey foreign key (salary_slip_id) references public.salary_slips(id) on delete cascade;

alter table public.client_billing add column if not exists term_count integer;
alter table public.client_billing add column if not exists billed_count integer not null default 0;
alter table public.client_billing add column if not exists period_start date;

-- updated_at
do $$ declare t text; begin
  foreach t in array array['finance_accounts', 'invoices', 'client_billing', 'finance_entries', 'salary_setup', 'salary_slips'] loop
    execute format('drop trigger if exists set_updated_at on public.%I', t);
    execute format('create trigger set_updated_at before update on public.%I for each row execute function public.set_updated_at()', t);
  end loop;
end $$;

-- 6. Who can read and change what -----------------------------------------------------------------------------------------
do $$ declare t text; begin
  foreach t in array array['finance_accounts', 'invoices', 'client_billing', 'finance_entries'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists fin_select on public.%I', t);
    execute format('drop policy if exists fin_insert on public.%I', t);
    execute format('drop policy if exists fin_update on public.%I', t);
    execute format('drop policy if exists fin_delete on public.%I', t);
    execute format('create policy fin_select on public.%I for select to authenticated using (public.perm(''finance'') >= 1)', t);
    execute format('create policy fin_insert on public.%I for insert to authenticated with check (public.perm(''finance'') >= 2)', t);
    execute format('create policy fin_update on public.%I for update to authenticated using (public.perm(''finance'') >= 2) with check (public.perm(''finance'') >= 2)', t);
    execute format('create policy fin_delete on public.%I for delete to authenticated using (public.perm(''finance'') >= 3)', t);
    execute format('grant select, insert, update, delete on public.%I to authenticated', t);
    execute format('revoke all on public.%I from anon', t);
  end loop;
end $$;
-- salaries: Finance people see all; everyone sees their own (slips once issued)
alter table public.salary_setup enable row level security;
alter table public.salary_slips enable row level security;
drop policy if exists sal_select on public.salary_setup;
drop policy if exists sal_write on public.salary_setup;
create policy sal_select on public.salary_setup for select to authenticated
  using (public.perm('finance') >= 1 or (user_id = auth.uid() and public.is_active_user()));
create policy sal_write on public.salary_setup for all to authenticated
  using (public.perm('finance') >= 2) with check (public.perm('finance') >= 2);
drop policy if exists slip_select on public.salary_slips;
drop policy if exists slip_insert on public.salary_slips;
drop policy if exists slip_update on public.salary_slips;
drop policy if exists slip_delete on public.salary_slips;
create policy slip_select on public.salary_slips for select to authenticated
  using (public.perm('finance') >= 1 or (user_id = auth.uid() and status <> 'Draft' and public.is_active_user()));
create policy slip_insert on public.salary_slips for insert to authenticated with check (public.perm('finance') >= 2);
create policy slip_update on public.salary_slips for update to authenticated using (public.perm('finance') >= 2) with check (public.perm('finance') >= 2);
create policy slip_delete on public.salary_slips for delete to authenticated using (public.perm('finance') >= 3);
grant select, insert, update, delete on public.salary_setup, public.salary_slips to authenticated;
revoke all on public.salary_setup, public.salary_slips from anon;

-- 7. Invoice numbers: TCT/26-27/001, in order, per account, given when an invoice is issued -------------------------------
create or replace function public.issue_invoice(p_invoice uuid) returns text
language plpgsql security definer set search_path = public as $$
declare inv public.invoices; acc public.finance_accounts; d date; fy text; n integer; num text;
begin
  if public.perm('finance') < 2 then raise exception 'Only Finance can issue invoices.' using errcode = '42501'; end if;
  select * into inv from public.invoices where id = p_invoice for update;
  if inv.id is null then raise exception 'Invoice not found.'; end if;
  if inv.number is not null then return inv.number; end if;
  select * into acc from public.finance_accounts where id = inv.account_id for update;
  if acc.id is null then raise exception 'Choose the account this invoice is from.'; end if;
  d := inv.issue_date;
  fy := case when extract(month from d) >= 4
             then lpad((extract(year from d)::int % 100)::text, 2, '0') || '-' || lpad(((extract(year from d)::int + 1) % 100)::text, 2, '0')
             else lpad(((extract(year from d)::int - 1) % 100)::text, 2, '0') || '-' || lpad((extract(year from d)::int % 100)::text, 2, '0') end;
  n := acc.next_number;
  num := coalesce(nullif(acc.invoice_prefix, ''), 'INV') || '/' || fy || '/' || lpad(n::text, 3, '0');
  while exists (select 1 from public.invoices where number = num) loop
    n := n + 1; num := coalesce(nullif(acc.invoice_prefix, ''), 'INV') || '/' || fy || '/' || lpad(n::text, 3, '0');
  end loop;
  update public.finance_accounts set next_number = n + 1 where id = acc.id;
  update public.invoices set number = num, status = case when status = 'Draft' then 'Issued' else status end where id = inv.id;
  return num;
end $$;
revoke all on function public.issue_invoice(uuid) from public, anon;
grant execute on function public.issue_invoice(uuid) to authenticated;

-- 8. Paid invoices go into Revenue, paid salaries into Expenses (and come out again if un-marked) --------------------------
create or replace function public.finance_auto_invoice() returns trigger
language plpgsql security definer set search_path = public as $$
declare tax numeric := coalesce(new.cgst, 0) + coalesce(new.sgst, 0) + coalesce(new.igst, 0); paid date := coalesce(new.paid_on, current_date);
        label text := 'Invoice ' || coalesce(new.number, 'draft') || coalesce(' · ' || nullif(new.bill_to ->> 'name', ''), '');
begin
  delete from public.finance_entries where invoice_id = new.id and auto;
  if new.status = 'Paid' then
    -- revenue is the taxable value; the GST collected is owed to the government (due by the 20th of next month, GSTR-3B)
    insert into public.finance_entries (kind, category, description, amount, entry_date, account_id, invoice_id, auto, payment_mode)
    values ('Revenue', 'Client payment', label,
            case when new.currency = 'INR' then coalesce(new.subtotal, new.total) else coalesce(new.amount_received_inr, 0) end,
            paid, new.account_id, new.id, true, 'Bank transfer');
    if new.currency = 'INR' and tax > 0 then
      insert into public.finance_entries (kind, category, description, amount, entry_date, account_id, invoice_id, auto, status, due_date)
      values ('Liability', 'GST payable', 'GST on ' || label, tax, paid, new.account_id, new.id, true, 'Open',
              (date_trunc('month', paid) + interval '1 month' + interval '19 days')::date);
    end if;
  end if;
  return null;
end $$;
drop trigger if exists finance_auto_invoice on public.invoices;
create trigger finance_auto_invoice after insert or update of status, total, amount_received_inr, paid_on, account_id on public.invoices
  for each row execute function public.finance_auto_invoice();

create or replace function public.finance_auto_salary() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  delete from public.finance_entries where salary_slip_id = new.id and auto;
  if new.status = 'Paid' then
    insert into public.finance_entries (kind, category, description, amount, entry_date, salary_slip_id, auto, payment_mode)
    values ('Expense', 'Salaries',
            'Salary · ' || coalesce((select full_name from public.profiles where id = new.user_id), '') || ' · ' || to_char(new.month, 'Mon YYYY'),
            new.net, coalesce(new.paid_on, current_date), new.id, true, 'Bank');
  end if;
  return null;
end $$;
drop trigger if exists finance_auto_salary on public.salary_slips;
create trigger finance_auto_salary after insert or update of status, net, paid_on on public.salary_slips
  for each row execute function public.finance_auto_salary();
revoke all on function public.finance_auto_invoice() from public, anon, authenticated;
revoke all on function public.finance_auto_salary() from public, anon, authenticated;

-- 9. Files on invoices and balance-sheet entries (invoice PDFs, receipts): only Finance can see them -----------------------
create or replace function public.can_see(tbl text, rid uuid)
 returns boolean language plpgsql stable set search_path to 'public' as $function$
declare ok boolean;
begin
  if tbl = 'email_attachments' then
    return rid = auth.uid() or public.is_admin();
  end if;
  if tbl = 'chat' then
    return public.can_chat(rid);            -- files in a conversation: its members only
  end if;
  if tbl = 'problem_reports' then
    return exists (select 1 from public.problem_reports p where p.id = rid and (p.user_id = auth.uid() or public.is_admin()));
  end if;
  if tbl in ('invoices', 'finance_entries') then   -- (2026-11ek) Finance only
    return public.perm('finance') >= 1;
  end if;
  if tbl not in ('projects','sprints','tasks','releases','tickets','clients','contacts','deals','activities',
                 'proposals','leads','campaigns','content','seo_keywords','meetings','leave_requests',
                 'announcements','documents','notes') then
    return false;
  end if;
  execute format('select exists (select 1 from public.%I where id = $1)', tbl) into ok using rid;
  return coalesce(ok, false);
end $function$;

-- check (read-only): 6 tables, 1 numbering function
select (select count(*) from pg_tables where schemaname = 'public' and tablename in
          ('finance_accounts', 'invoices', 'client_billing', 'finance_entries', 'salary_setup', 'salary_slips')) as finance_tables,
       (select count(*) from pg_proc where proname = 'issue_invoice') as numbering;
