-- =====================================================================
-- DailyBudget — Supabase database setup
-- Run this whole file once in: Supabase Dashboard -> SQL Editor -> New query
-- It is safe to re-run (idempotent where possible).
-- =====================================================================

create extension if not exists "pgcrypto";

-- ---------------------------------------------------------------------
-- Helper: keep updated_at current
-- ---------------------------------------------------------------------
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

-- Helper: forbid changing the owner of a row (blocks "hand my row to someone else")
create or replace function public.prevent_owner_change()
returns trigger
language plpgsql
as $$
begin
  if new.user_id is distinct from old.user_id then
    raise exception 'user_id cannot be changed';
  end if;
  return new;
end;
$$;

-- ---------------------------------------------------------------------
-- profiles (one row per auth user)
-- ---------------------------------------------------------------------
create table if not exists public.profiles (
  id          uuid primary key references auth.users(id) on delete cascade,
  full_name   text check (char_length(full_name) <= 100),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- preferences (one row per user)
-- ---------------------------------------------------------------------
create table if not exists public.preferences (
  user_id             uuid primary key references auth.users(id) on delete cascade,
  currency            text not null default 'USD' check (currency ~ '^[A-Z]{3}$'),
  daily_budget        numeric(14,2) not null default 0 check (daily_budget >= 0 and daily_budget < 1e11),
  rollover_enabled    boolean not null default false,
  opening_balance     numeric(14,2) not null default 0 check (abs(opening_balance) < 1e11),
  theme               text not null default 'system' check (theme in ('light','dark','system')),
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- transactions
-- ---------------------------------------------------------------------
create table if not exists public.transactions (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null default auth.uid() references auth.users(id) on delete cascade,
  type            text not null check (type in ('income','expense')),
  amount          numeric(14,2) not null check (amount > 0 and amount < 1e11),
  currency        text not null default 'USD' check (currency ~ '^[A-Z]{3}$'),
  txn_date        date not null,
  category        text not null check (char_length(category) between 1 and 60),
  description     text not null default '' check (char_length(description) <= 200),
  payment_method  text not null default 'other'
                  check (payment_method in ('cash','debit_card','credit_card','bank_transfer','other')),
  essential       boolean,                       -- null for income
  notes           text check (char_length(notes) <= 1000),
  bill_id         uuid,                          -- optional link to the bill this paid (FK added below)
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);

create index if not exists transactions_user_date_idx on public.transactions (user_id, txn_date desc);
create index if not exists transactions_user_type_idx on public.transactions (user_id, type);
create index if not exists transactions_user_cat_idx  on public.transactions (user_id, category);
create index if not exists transactions_bill_idx      on public.transactions (bill_id);

-- ---------------------------------------------------------------------
-- budgets  (monthly + per-category limits; month = first day of month)
-- category = '__total__' means the overall monthly budget
-- ---------------------------------------------------------------------
create table if not exists public.budgets (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null default auth.uid() references auth.users(id) on delete cascade,
  month       date not null check (extract(day from month) = 1),
  category    text not null check (char_length(category) between 1 and 60),
  amount      numeric(14,2) not null check (amount >= 0 and amount < 1e11),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  unique (user_id, month, category)
);

create index if not exists budgets_user_month_idx on public.budgets (user_id, month);

-- ---------------------------------------------------------------------
-- bills
-- ---------------------------------------------------------------------
create table if not exists public.bills (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null default auth.uid() references auth.users(id) on delete cascade,
  name         text not null check (char_length(name) between 1 and 100),
  bill_type    text not null default 'other'
               check (bill_type in ('rent','utilities','phone_internet','insurance','loan','credit_card','subscription','other')),
  amount       numeric(14,2) not null check (amount > 0 and amount < 1e11),
  due_date     date not null,
  recurrence   text not null default 'monthly' check (recurrence in ('once','weekly','monthly','annually')),
  status       text not null default 'unpaid' check (status in ('unpaid','paid')),
  last_paid_on date,
  notes        text check (char_length(notes) <= 1000),
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

create index if not exists bills_user_due_idx on public.bills (user_id, due_date);

-- Link transactions.bill_id -> bills.id. If a bill is deleted the expense stays (bill_id becomes null).
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'transactions_bill_id_fkey') then
    alter table public.transactions
      add constraint transactions_bill_id_fkey
      foreign key (bill_id) references public.bills(id) on delete set null;
  end if;
end $$;

-- ---------------------------------------------------------------------
-- savings_goals
-- NOTE: saved_amount is a number the user records. It is NOT verified by any bank.
-- ---------------------------------------------------------------------
create table if not exists public.savings_goals (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null default auth.uid() references auth.users(id) on delete cascade,
  name          text not null check (char_length(name) between 1 and 100),
  goal_type     text not null default 'general'
                check (goal_type in ('emergency','house','car','education','vacation','general')),
  target_amount numeric(14,2) not null check (target_amount > 0 and target_amount < 1e11),
  saved_amount  numeric(14,2) not null default 0 check (saved_amount >= 0 and saved_amount < 1e11),
  target_date   date,
  description   text check (char_length(description) <= 500),
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

create index if not exists savings_goals_user_idx on public.savings_goals (user_id);

-- ---------------------------------------------------------------------
-- Triggers
-- ---------------------------------------------------------------------
do $$
declare t text;
begin
  foreach t in array array['profiles','preferences','transactions','budgets','bills','savings_goals']
  loop
    execute format('drop trigger if exists %I_set_updated_at on public.%I', t, t);
    execute format('create trigger %I_set_updated_at before update on public.%I
                    for each row execute function public.set_updated_at()', t, t);
  end loop;

  foreach t in array array['preferences','transactions','budgets','bills','savings_goals']
  loop
    execute format('drop trigger if exists %I_no_owner_change on public.%I', t, t);
    execute format('create trigger %I_no_owner_change before update on public.%I
                    for each row execute function public.prevent_owner_change()', t, t);
  end loop;
end $$;

-- profiles uses "id" as owner column
create or replace function public.prevent_profile_id_change()
returns trigger language plpgsql as $$
begin
  if new.id is distinct from old.id then
    raise exception 'id cannot be changed';
  end if;
  return new;
end;
$$;
drop trigger if exists profiles_no_id_change on public.profiles;
create trigger profiles_no_id_change before update on public.profiles
  for each row execute function public.prevent_profile_id_change();

-- ---------------------------------------------------------------------
-- Ensure a transaction can only link to a bill owned by the same user
-- ---------------------------------------------------------------------
create or replace function public.check_txn_bill_owner()
returns trigger language plpgsql as $$
begin
  if new.bill_id is not null then
    if not exists (select 1 from public.bills b where b.id = new.bill_id and b.user_id = new.user_id) then
      raise exception 'bill does not belong to this user';
    end if;
  end if;
  return new;
end;
$$;
drop trigger if exists transactions_check_bill on public.transactions;
create trigger transactions_check_bill before insert or update on public.transactions
  for each row execute function public.check_txn_bill_owner();

-- ---------------------------------------------------------------------
-- New-user bootstrap: create profile + preferences automatically
-- ---------------------------------------------------------------------
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, full_name)
  values (new.id, left(coalesce(new.raw_user_meta_data->>'full_name', ''), 100))
  on conflict (id) do nothing;

  insert into public.preferences (user_id)
  values (new.id)
  on conflict (user_id) do nothing;

  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- Backfill for any users created before this script ran
insert into public.profiles (id)
select u.id from auth.users u
on conflict (id) do nothing;
insert into public.preferences (user_id)
select u.id from auth.users u
on conflict (user_id) do nothing;

-- ---------------------------------------------------------------------
-- Row Level Security
-- ---------------------------------------------------------------------
alter table public.profiles       enable row level security;
alter table public.preferences    enable row level security;
alter table public.transactions   enable row level security;
alter table public.budgets        enable row level security;
alter table public.bills          enable row level security;
alter table public.savings_goals  enable row level security;

-- Force RLS even for the table owner role used by some tooling
alter table public.profiles       force row level security;
alter table public.preferences    force row level security;
alter table public.transactions   force row level security;
alter table public.budgets        force row level security;
alter table public.bills          force row level security;
alter table public.savings_goals  force row level security;

-- profiles (owner column: id)
drop policy if exists profiles_select on public.profiles;
drop policy if exists profiles_insert on public.profiles;
drop policy if exists profiles_update on public.profiles;
drop policy if exists profiles_delete on public.profiles;
create policy profiles_select on public.profiles for select to authenticated using ((select auth.uid()) = id);
create policy profiles_insert on public.profiles for insert to authenticated with check ((select auth.uid()) = id);
create policy profiles_update on public.profiles for update to authenticated
  using ((select auth.uid()) = id) with check ((select auth.uid()) = id);
create policy profiles_delete on public.profiles for delete to authenticated using ((select auth.uid()) = id);

-- Generic policies for tables that use user_id
do $$
declare t text;
begin
  foreach t in array array['preferences','transactions','budgets','bills','savings_goals']
  loop
    execute format('drop policy if exists %I_select on public.%I', t, t);
    execute format('drop policy if exists %I_insert on public.%I', t, t);
    execute format('drop policy if exists %I_update on public.%I', t, t);
    execute format('drop policy if exists %I_delete on public.%I', t, t);

    execute format('create policy %I_select on public.%I for select to authenticated
                    using ((select auth.uid()) = user_id)', t, t);
    execute format('create policy %I_insert on public.%I for insert to authenticated
                    with check ((select auth.uid()) = user_id)', t, t);
    execute format('create policy %I_update on public.%I for update to authenticated
                    using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id)', t, t);
    execute format('create policy %I_delete on public.%I for delete to authenticated
                    using ((select auth.uid()) = user_id)', t, t);
  end loop;
end $$;

-- ---------------------------------------------------------------------
-- Privileges: anonymous visitors get nothing; signed-in users get CRUD (filtered by RLS)
-- ---------------------------------------------------------------------
revoke all on public.profiles, public.preferences, public.transactions,
              public.budgets, public.bills, public.savings_goals from anon;
grant select, insert, update, delete on public.profiles, public.preferences, public.transactions,
              public.budgets, public.bills, public.savings_goals to authenticated;

-- ---------------------------------------------------------------------
-- Account deletion: a signed-in user can delete ONLY their own account.
-- All their rows are removed through ON DELETE CASCADE.
-- ---------------------------------------------------------------------
create or replace function public.delete_my_account()
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
declare uid uuid := auth.uid();
begin
  if uid is null then
    raise exception 'not authenticated';
  end if;
  delete from auth.users where id = uid;
end;
$$;

revoke all on function public.delete_my_account() from public, anon;
grant execute on function public.delete_my_account() to authenticated;

-- Lock down trigger-only functions so they cannot be called through the API
revoke all on function public.handle_new_user() from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- Done. Next: Authentication -> URL Configuration (see README.md).
-- ---------------------------------------------------------------------
