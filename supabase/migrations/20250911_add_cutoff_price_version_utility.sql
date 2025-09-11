-- Add utility function to recompute student price versions based on cutoff date
-- This allows changing which students get old vs new prices by adjusting the cutoff date

create or replace function public.recompute_student_price_version(p_cutoff date)
returns table(
  students_updated bigint,
  version_1_count bigint,
  version_2_count bigint,
  cutoff_date date
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_students_updated bigint;
  v_version_1_count bigint;
  v_version_2_count bigint;
begin
  -- Update students based on their earliest contract date
  with student_contract_dates as (
    select 
      s.id,
      s.name,
      min(c.created_at::date) as earliest_contract_date
    from public.students s
    left join public.contracts c on c.student_id = s.id
    group by s.id, s.name
  )
  update public.students
  set price_version = case 
    when scd.earliest_contract_date is not null and scd.earliest_contract_date < p_cutoff then 1
    else 2
  end
  from student_contract_dates scd
  where students.id = scd.id;
  
  -- Get count of updated students
  get diagnostics v_students_updated = row_count;
  
  -- Get distribution counts
  select 
    count(*) filter (where price_version = 1),
    count(*) filter (where price_version = 2)
  into v_version_1_count, v_version_2_count
  from public.students;
  
  -- Return summary
  return query select 
    v_students_updated,
    v_version_1_count,
    v_version_2_count,
    p_cutoff;
end;
$$;

-- Grant execute permission to authenticated users
grant execute on function public.recompute_student_price_version(date) to authenticated;

-- Add helpful comment
comment on function public.recompute_student_price_version(date) is 
'Recomputes all student price_version values based on cutoff date. Students with contracts before cutoff get version 1 (old prices), others get version 2 (new prices). Returns summary of changes.';
