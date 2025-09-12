-- Fix update_contract_notes function to allow teachers to edit notes for their own contracts
-- This works with the current database structure where contracts have teacher_id

create or replace function public.update_contract_notes(_contract_id uuid, _notes text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  _contract_teacher_id uuid;
  _allowed boolean;
begin
  -- Get the teacher_id for this contract
  select teacher_id into _contract_teacher_id
  from public.contracts
  where id = _contract_id;

  if _contract_teacher_id is null then
    raise exception 'contract not found';
  end if;

  -- Permission: admin or the teacher assigned to this contract
  select public.is_admin() or _contract_teacher_id = auth.uid()
  into _allowed;

  if not _allowed then
    raise exception 'not allowed';
  end if;

  update public.contracts
  set private_notes = _notes
  where id = _contract_id;
end;
$$;
