-- Two Teachers Per Student Feature Migration (FIXED v2)
-- This migration adds support for assigning up to 2 teachers per student

-- Create join table for student-teacher assignments
create table if not exists public.student_teachers (
  student_id uuid not null references public.students(id) on delete cascade,
  teacher_id uuid not null references auth.users(id) on delete cascade,
  assigned_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  primary key (student_id, teacher_id)
);

-- Enable RLS on the new table
alter table public.student_teachers enable row level security;

-- Create RLS policies for student_teachers table
do $$
begin
  -- Admins can do everything
  if not exists (select 1 from pg_policies where policyname = 'student_teachers_admin_all' and tablename = 'student_teachers') then
    create policy student_teachers_admin_all on public.student_teachers
      for all to authenticated
      using (public.is_admin())
      with check (public.is_admin());
  end if;

  -- Teachers can read their own assignments
  if not exists (select 1 from pg_policies where policyname = 'student_teachers_teacher_read' and tablename = 'student_teachers') then
    create policy student_teachers_teacher_read on public.student_teachers
      for select to authenticated
      using (teacher_id = auth.uid());
  end if;

  -- Teachers can insert assignments for students they teach
  if not exists (select 1 from pg_policies where policyname = 'student_teachers_teacher_insert' and tablename = 'student_teachers') then
    create policy student_teachers_teacher_insert on public.student_teachers
      for insert to authenticated
      with check (
        teacher_id = auth.uid() and
        public.is_teacher_of_student(student_id)
      );
  end if;

  -- Teachers can delete their own assignments
  if not exists (select 1 from pg_policies where policyname = 'student_teachers_teacher_delete' and tablename = 'student_teachers') then
    create policy student_teachers_teacher_delete on public.student_teachers
      for delete to authenticated
      using (teacher_id = auth.uid());
  end if;
end $$;

-- Enforce max 2 teachers per student via trigger
create or replace function public.enforce_max_two_teachers()
returns trigger
language plpgsql as $$
begin
  if (select count(*) from public.student_teachers
      where student_id = new.student_id) >= 2 then
    raise exception 'A student can have at most 2 teachers';
  end if;
  return new;
end; $$;

drop trigger if exists trg_max_two_teachers on public.student_teachers;
create trigger trg_max_two_teachers
  before insert on public.student_teachers
  for each row execute function public.enforce_max_two_teachers();

-- Helper functions (create only if missing)
create or replace function public.is_admin()
returns boolean
language sql stable security definer set search_path=public as $$
  select public.get_user_role(auth.uid()) = 'admin';
$$;

create or replace function public.is_teacher_of_student(_student uuid)
returns boolean
language sql stable security definer set search_path=public as $$
  select exists(
    select 1 from public.student_teachers st
    where st.student_id = _student and st.teacher_id = auth.uid()
  );
$$;

-- Update existing students table to maintain backwards compatibility
-- Add a trigger to automatically create student_teacher entries when a student is created
create or replace function public.create_student_teacher_assignment()
returns trigger
language plpgsql as $$
begin
  -- If the student has a teacher_id, create the assignment in student_teachers
  if new.teacher_id is not null then
    insert into public.student_teachers (student_id, teacher_id, assigned_by)
    values (new.id, new.teacher_id, auth.uid())
    on conflict (student_id, teacher_id) do nothing;
  end if;
  return new;
end; $$;

drop trigger if exists trg_create_student_teacher_assignment on public.students;
create trigger trg_create_student_teacher_assignment
  after insert on public.students
  for each row execute function public.create_student_teacher_assignment();

-- Migrate existing student-teacher relationships to the new table
insert into public.student_teachers (student_id, teacher_id, assigned_by, created_at)
select 
  s.id as student_id,
  s.teacher_id,
  s.teacher_id as assigned_by, -- Assuming the teacher assigned themselves
  s.created_at
from public.students s
where s.teacher_id is not null
on conflict (student_id, teacher_id) do nothing;
