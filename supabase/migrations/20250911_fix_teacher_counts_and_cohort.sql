-- 1) Drop obsolete triggers and functions on students (if present)
do $$
begin
  -- Drop the old trigger
  if exists (
    select 1
    from pg_trigger t
    join pg_class c on c.oid = t.tgrelid
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relname = 'students'
      and t.tgname = 'trigger_update_teacher_student_count'
  ) then
    drop trigger trigger_update_teacher_student_count on public.students;
  end if;
  
  -- Also drop the alternative trigger name
  if exists (
    select 1
    from pg_trigger t
    join pg_class c on c.oid = t.tgrelid
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relname = 'students'
      and t.tgname = 'trg_update_teacher_student_count'
  ) then
    drop trigger trg_update_teacher_student_count on public.students;
  end if;
end$$;

-- Drop the old function that references students.teacher_id
drop function if exists public.update_teacher_student_count();

-- 2) Replace the old function with a contracts-based version
create or replace function public.refresh_teacher_student_count(p_teacher_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.teachers t
  set student_count = coalesce((
    select count(distinct c.student_id)
    from public.contracts c
    where c.teacher_id = p_teacher_id
      and c.status = 'active'
  ), 0)
  where t.id = p_teacher_id;
end;
$$;

-- 3) Trigger helper that refreshes counts after contract changes
create or replace function public.refresh_teacher_student_count_after_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op in ('INSERT','UPDATE') then
    if new.teacher_id is not null then
      perform public.refresh_teacher_student_count(new.teacher_id);
    end if;
  end if;
  if tg_op in ('UPDATE','DELETE') then
    if old.teacher_id is not null and (new.teacher_id is distinct from old.teacher_id) then
      perform public.refresh_teacher_student_count(old.teacher_id);
    end if;
  end if;
  return null;
end;
$$;

-- 4) Recreate contract-based triggers (idempotent)
do $$
begin
  if exists (select 1 from pg_trigger where tgname = 'trg_refresh_teacher_student_count_ins') then
    drop trigger trg_refresh_teacher_student_count_ins on public.contracts;
  end if;
  if exists (select 1 from pg_trigger where tgname = 'trg_refresh_teacher_student_count_upd') then
    drop trigger trg_refresh_teacher_student_count_upd on public.contracts;
  end if;
  if exists (select 1 from pg_trigger where tgname = 'trg_refresh_teacher_student_count_del') then
    drop trigger trg_refresh_teacher_student_count_del on public.contracts;
  end if;
end$$;

create trigger trg_refresh_teacher_student_count_ins
after insert on public.contracts
for each row execute function public.refresh_teacher_student_count_after_change();

create trigger trg_refresh_teacher_student_count_upd
after update on public.contracts
for each row execute function public.refresh_teacher_student_count_after_change();

create trigger trg_refresh_teacher_student_count_del
after delete on public.contracts
for each row execute function public.refresh_teacher_student_count_after_change();

-- 5) Minimal permissions
revoke all on function public.refresh_teacher_student_count(uuid) from public;
revoke all on function public.refresh_teacher_student_count_after_change() from public;
grant execute on function public.refresh_teacher_student_count(uuid) to authenticated;

-- 6) One-time backfill of teacher counts (safe no-op if none)
do $$
declare r record;
begin
  for r in (select id from public.teachers) loop
    perform public.refresh_teacher_student_count(r.id);
  end loop;
end$$;
