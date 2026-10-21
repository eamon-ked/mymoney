-- mymoney v1.2 budgeting. NOT APPLIED YET: budget sync is a later step, and
-- the app currently keeps budgets on the device only. Apply after
-- 20261020_balance_hotfix_v1_1.sql (it reuses public.set_updated_at()).

create table if not exists public.category_budgets (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  category_id uuid not null references public.categories(id) on delete cascade,
  month text not null check (month ~ '^\d{4}-\d{2}$'),
  assigned numeric(15,2) not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  unique (user_id, category_id, month)
);

alter table public.category_budgets enable row level security;

drop policy if exists "Users manage their own budgets" on public.category_budgets;
create policy "Users manage their own budgets" on public.category_budgets
  for all using (user_id = auth.uid()) with check (user_id = auth.uid());

drop trigger if exists trg_category_budgets_updated_at on public.category_budgets;
create trigger trg_category_budgets_updated_at
  before insert or update on public.category_budgets
  for each row execute function public.set_updated_at();

create index if not exists idx_category_budgets_user_updated
  on public.category_budgets (user_id, updated_at);

alter table public.accounts
  add column if not exists on_budget boolean not null default true;

alter table public.categories
  add column if not exists monthly_target numeric(15,2),
  add column if not exists is_pay_first boolean not null default false;
