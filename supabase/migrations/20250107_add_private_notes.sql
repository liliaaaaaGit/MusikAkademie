-- Add private_notes column to contracts table
alter table public.contracts
  add column if not exists private_notes text;

-- Create RPC function to update contract notes with least privilege
create or replace function public.update_contract_notes(_contract_id uuid, _notes text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  _student_id uuid;
  _allowed boolean;
begin
  -- find the student for this contract
  select student_id into _student_id
  from public.contracts
  where id = _contract_id;

  if _student_id is null then
    raise exception 'contract not found';
  end if;

  -- permission: admin or assigned teacher of the student
  select public.is_admin()
         or exists (
              select 1 from public.student_teachers st
              where st.student_id = _student_id
                and st.teacher_id = auth.uid()
            )
  into _allowed;

  if not _allowed then
    raise exception 'not allowed';
  end if;

  update public.contracts
  set private_notes = _notes
  where id = _contract_id;
end;
$$;
