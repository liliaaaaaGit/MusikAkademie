-- Fix get_variants_for_student to handle null student_id for new students
-- When p_student_id is null, return variants for current_price_version
-- When p_student_id is provided, return variants for that student's price_version

create or replace function public.get_variants_for_student(p_student_id uuid)
returns setof public.contract_variants
language plpgsql
security definer
set search_path = public
as $$
declare
  target_version smallint;
begin
  if p_student_id is null then
    -- New student: use current price version
    target_version := public.get_current_price_version();
  else
    -- Existing student: use their price version
    select price_version into target_version
    from public.students
    where id = p_student_id;
    
    -- If student not found, fallback to current version
    if target_version is null then
      target_version := public.get_current_price_version();
    end if;
  end if;
  
  -- Return variants for the target version
  return query
  select v.*
  from public.contract_variants v
  where v.is_active = true
    and v.price_version = target_version;
end;
$$;

-- Update permissions (idempotent)
grant execute on function public.get_variants_for_student(uuid) to authenticated;
