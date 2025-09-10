-- Robust helper: is_admin (idempotent)
create or replace function public.is_admin()
returns boolean
language sql stable security definer set search_path=public as $$
  select coalesce((select role from public.profiles where id = auth.uid()), 'teacher') = 'admin';
$$;

-- Column (idempotent)
alter table public.contracts add column if not exists private_notes text;

-- RPC that tolerates projects without student_teachers (falls back to legacy teacher_id if available)
create or replace function public.update_contract_notes(_contract_id uuid, _notes text)
returns void
language plpgsql security definer set search_path=public as $$
declare
  _student_id uuid;
  _allowed boolean;
  _has_st boolean;
begin
  select student_id into _student_id from public.contracts where id = _contract_id;
  if _student_id is null then
    raise exception 'contract not found';
  end if;

  -- check if student_teachers exists
  select exists (
    select 1 from pg_tables where schemaname = 'public' and tablename = 'student_teachers'
  ) into _has_st;

  if _has_st then
    select public.is_admin() or exists (
      select 1 from public.student_teachers st where st.student_id = _student_id and st.teacher_id = auth.uid()
    ) into _allowed;
  else
    -- fallback: allow admin only
    select public.is_admin() into _allowed;
  end if;

  if not _allowed then
    raise exception 'not allowed';
  end if;

  update public.contracts set private_notes = _notes where id = _contract_id;
end;
$$;
