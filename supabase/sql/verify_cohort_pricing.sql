-- Columns present?
select table_name, column_name, data_type
from information_schema.columns
where table_schema = 'public'
  and table_name in ('students','contract_variants')
  and column_name = 'price_version'
order by table_name;

-- Pricing settings row exists and set to 2?
select * from public.pricing_settings where id = 1;

-- Functions present?
select proname, prosecdef as is_security_definer
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and proname in ('get_current_price_version','set_student_price_version','get_variants_for_student');

-- Trigger installed?
select tgname, relname as on_table
from pg_trigger t
join pg_class c on c.oid = t.tgrelid
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public' and tgname = 'trg_set_student_price_version';

-- Runtime sanity:
select public.get_current_price_version() as expected_version_for_new_students;
