-- MAM WebApp Database Audit
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

-- Functions
select n.nspname, p.proname, p.pronargs
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname='public'
  and (pg_get_functiondef(p.oid) ilike '%s.teacher_id%'
    or pg_get_functiondef(p.oid) ilike '%students.teacher_id%'
    or pg_get_functiondef(p.oid) ilike '% contract_id %');

-- Triggers
select tg.tgname, pg_get_triggerdef(tg.oid) as def
from pg_trigger tg
join pg_class c on c.oid = tg.tgrelid
join pg_namespace n on n.oid = c.relnamespace
where n.nspname='public'
  and (pg_get_triggerdef(tg.oid) ilike '%s.teacher_id%'
    or pg_get_triggerdef(tg.oid) ilike '%students.teacher_id%');

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

-- Rules
select r.rulename, pg_get_ruledef(r.oid) as def
from pg_rewrite r
where pg_get_ruledef(r.oid) ilike '%s.teacher_id%'
   or pg_get_ruledef(r.oid) ilike '%students.teacher_id%';

-- Generated/default expressions
select c.relname as table_name, a.attname as column_name, pg_get_expr(adbin, adrelid) as expr
from pg_attrdef d
join pg_class c on c.oid = d.adrelid
join pg_attribute a on a.attrelid = d.adrelid and a.attnum = d.adnum
join pg_namespace n on n.oid = c.relnamespace
where n.nspname='public'
  and (pg_get_expr(adbin, adrelid) ilike '%s.teacher_id%'
    or pg_get_expr(adbin, adrelid) ilike '%students.teacher_id%');
