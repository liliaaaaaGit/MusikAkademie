-- MAM WebApp Database Audit (Simple Version)
-- Focuses on the most critical checks without problematic functions

-- 1. Check RLS Policies for forbidden references
select tablename, policyname, qual, with_check
from pg_policies
where schemaname='public'
  and tablename in ('lessons','contracts','students')
  and (coalesce(qual,'') ilike '%s.teacher_id%'
    or coalesce(qual,'') ilike '%students.teacher_id%'
    or coalesce(with_check,'') ilike '%s.teacher_id%'
    or coalesce(with_check,'') ilike '%students.teacher_id%');

-- 2. List all custom functions (for manual review)
select n.nspname as schema, p.proname as function_name, p.pronargs as arg_count
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname='public'
  and p.proname not like 'pg_%'
  and p.proname not like 'array_%'
  and p.proname not like 'RI_%'
order by p.proname;

-- 3. Check views for forbidden references
select schemaname, viewname, definition
from pg_views
where schemaname='public'
  and (definition ilike '%s.teacher_id%'
    or definition ilike '%students.teacher_id%');

-- 4. Check materialized views
select schemaname, matviewname, definition
from pg_matviews
where schemaname='public'
  and (definition ilike '%s.teacher_id%'
    or definition ilike '%students.teacher_id%');

-- 5. Check for duplicate function names
select proname as function_name, count(*) as definition_count
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname='public'
  and p.proname not like 'pg_%'
group by proname
having count(*) > 1
order by definition_count desc, proname;
