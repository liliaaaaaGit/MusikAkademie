-- term & cancellation (if not already present)
alter table public.contracts
  add column if not exists term_start date,
  add column if not exists term_end date,
  add column if not exists term_label text,
  add column if not exists cancelled_at date;

-- billing cycle enum + fields
do $$
begin
  if not exists (select 1 from pg_type where typname = 'billing_cycle') then
    create type billing_cycle as enum ('monthly','upfront');
  end if;
end$$;

alter table public.contracts
  add column if not exists billing_cycle billing_cycle,
  add column if not exists paid_at date,
  add column if not exists paid_through date; 