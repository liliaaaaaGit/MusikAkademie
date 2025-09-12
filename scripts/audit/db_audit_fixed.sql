-- MAM WebApp Database Audit (Fixed)
-- Identifies forbidden references across database objects

-- Policies
select tablename, policyname, qual, with_check
from pg_policies
where schemaname='public'
  and tablename in ('lessons','contracts','students')
  and (coalesce(qual,'') ilike '%s.teacher_id%'
    or coalesce(qual,'') ilike '%students.teacher_id%'
    or coalesce(with_check,'') ilike '%s.teacher_id%'
    or coalesce(with_check,'') ilike '%students.teacher_id%');

-- Functions (simplified to avoid aggregate function issues)
select n.nspname, p.proname, p.pronargs, p.oid
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname='public'
  and p.proname not like 'pg_%'
  and p.proname not like 'array_%';

-- Triggers (simplified)
select tg.tgname, c.relname as table_name
from pg_trigger tg
join pg_class c on c.oid = tg.tgrelid
join pg_namespace n on n.oid = c.relnamespace
where n.nspname='public'
  and tg.tgname not like 'RI_%'
  and tg.tgname not like 'pg_%';

-- Views
select schemaname, viewname, definition
from pg_views
where schemaname='public'
  and (definition ilike '%s.teacher_id%'
    or definition ilike '%students.teacher_id%');

-- Materialized views
select schemaname, matviewname, definition
from pg_matviews
where schemaname='public'
  and (definition ilike '%s.teacher_id%'
    or definition ilike '%students.teacher_id%');

-- Check for problematic function definitions (manual check needed)
select 'Manual check required for functions containing s.teacher_id or students.teacher_id' as note;
