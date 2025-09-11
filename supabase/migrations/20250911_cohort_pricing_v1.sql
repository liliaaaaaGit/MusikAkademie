-- 1) Tables & columns
create table if not exists public.pricing_settings (
  id int primary key check (id = 1),
  current_price_version smallint not null check (current_price_version > 0),
  updated_at timestamptz not null default now()
);

insert into public.pricing_settings (id, current_price_version)
values (1, 2)
on conflict (id) do update
set current_price_version = excluded.current_price_version,
    updated_at = now();

alter table public.students
  add column if not exists price_version smallint;

alter table public.contract_variants
  add column if not exists price_version smallint;

-- 2) Helper function to read current version
create or replace function public.get_current_price_version()
returns smallint
language sql
stable
as $$
  select current_price_version
  from public.pricing_settings
  where id = 1
$$;

-- 3) Trigger: assign students.price_version on INSERT if NULL
create or replace function public.set_student_price_version()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
begin
  if new.price_version is null then
    new.price_version := public.get_current_price_version();
  end if;
  return new;
end;
$fn$;

do $$
begin
  if not exists (
    select 1
    from pg_trigger
    where tgname = 'trg_set_student_price_version'
  ) then
    create trigger trg_set_student_price_version
    before insert on public.students
    for each row
    execute function public.set_student_price_version();
  end if;
end$$;

-- 4) RPC: return variants matching a student's price_version
create or replace function public.get_variants_for_student(p_student_id uuid)
returns setof public.contract_variants
language sql
security definer
set search_path = public
as $$
  with s as (
    select price_version
    from public.students
    where id = p_student_id
  )
  select v.*
  from public.contract_variants v
  cross join s
  where v.is_active = true
    and v.price_version = s.price_version
$$;

-- 5) Minimal permissions (least-privilege)
revoke all on function public.get_current_price_version() from public;
revoke all on function public.set_student_price_version() from public;
revoke all on function public.get_variants_for_student(uuid) from public;

grant execute on function public.get_current_price_version() to authenticated;
grant execute on function public.get_variants_for_student(uuid) to authenticated;
