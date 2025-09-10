BEGIN;

-- Add teacher_id column to contracts table
ALTER TABLE contracts ADD COLUMN teacher_id UUID REFERENCES teachers(id);

-- Populate existing contracts with teacher_id from students table
UPDATE contracts 
SET teacher_id = (
  SELECT s.teacher_id 
  FROM students s 
  WHERE s.id = contracts.student_id
);

-- Add NOT NULL constraint after population
ALTER TABLE contracts ALTER COLUMN teacher_id SET NOT NULL;

-- Add index for performance
CREATE INDEX idx_contracts_teacher_id ON contracts(teacher_id);

-- Add foreign key constraint name for reference
ALTER TABLE contracts ADD CONSTRAINT fk_contracts_teacher_id 
  FOREIGN KEY (teacher_id) REFERENCES teachers(id);

COMMIT;
