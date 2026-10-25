-- mymoney v1.1 balance hotfix. Run once in the Supabase SQL editor BEFORE the
-- v1.1 build goes live. Every change is additive, so v1.0 clients keep working.

-- Opening balance replaces the synced running total
alter table public.accounts
  add column if not exists opening_balance numeric(15,2) not null default 0;

-- Lets a second device skip the balance repair sheet
alter table public.accounts
  add column if not exists balance_confirmed_at timestamptz;

-- Soft deletes so deletions reach other devices
alter table public.transactions
  add column if not exists deleted_at timestamptz;

alter table public.accounts
  add column if not exists deleted_at timestamptz;

-- Destination account for transfers
alter table public.transactions
  add column if not exists transfer_account_id uuid
  references public.accounts(id) on delete set null;

-- Store the real instant, not a UTC date
alter table public.transactions
  alter column transaction_date type timestamptz
  using transaction_date::timestamptz;

-- Server clock stamps every write, so incremental pulls never miss a row
-- because of a device clock that is behind.
create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists trg_transactions_updated_at on public.transactions;
create trigger trg_transactions_updated_at
  before insert or update on public.transactions
  for each row execute function public.set_updated_at();

drop trigger if exists trg_accounts_updated_at on public.accounts;
create trigger trg_accounts_updated_at
  before insert or update on public.accounts
  for each row execute function public.set_updated_at();

create index if not exists idx_transactions_user_updated
  on public.transactions (user_id, updated_at);
