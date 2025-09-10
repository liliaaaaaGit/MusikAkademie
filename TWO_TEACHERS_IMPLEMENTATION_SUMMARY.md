# Two Teachers Per Student Feature Implementation

## Overview
This implementation adds support for assigning up to 2 teachers per student, allowing multiple teachers to share responsibility for a single student.

## Database Changes

### 1. New Table: `student_teachers`
- **Purpose**: Many-to-many relationship between students and teachers
- **Structure**:
  - `student_id` (bigint, FK to students.id)
  - `teacher_id` (uuid, FK to auth.users.id)
  - `assigned_by` (uuid, FK to auth.users.id)
  - `created_at` (timestamptz)
  - Primary key: (student_id, teacher_id)

### 2. RLS Policies
- **student_teachers table**: Admins can manage all, teachers can read/insert/delete their own assignments
- **students table**: Updated to work with student_teachers table
- **contracts table**: Updated to work with student_teachers table
- **lessons table**: Updated to work with student_teachers table

### 3. Constraints
- **Max 2 teachers per student**: Enforced via database trigger
- **Backwards compatibility**: Existing `students.teacher_id` field maintained

### 4. Helper Functions
- `is_admin()`: Check if current user is admin
- `is_teacher_of_student(student_id)`: Check if current user teaches a student

## Frontend Changes

### 1. StudentForm Component
- **Multi-teacher selection**: Dropdown with ability to select up to 2 teachers
- **Visual feedback**: Selected teachers displayed as badges with remove option
- **Validation**: Prevents selecting more than 2 teachers
- **Backwards compatibility**: Uses first selected teacher as primary teacher_id

### 2. StudentsTab Component
- **Updated queries**: Includes student_teachers relationships
- **Teacher filtering**: Works with new student_teachers table
- **Display**: Shows all assigned teachers (primary + additional)

### 3. StudentCardView Component
- **Multi-teacher display**: Shows all assigned teachers as badges
- **Action buttons**: Edit, delete, view contract functionality

### 4. ContractsTab Component
- **Updated queries**: Includes student_teachers relationships
- **Teacher filtering**: Works with new student_teachers table

### 5. StudentCountTooltip Component
- **Updated queries**: Uses student_teachers table for accurate counts

## Migration Files

### 1. `apply_two_teachers_migration.sql`
- Creates student_teachers table
- Sets up RLS policies
- Creates helper functions
- Adds constraints and triggers
- Migrates existing data

### 2. `update_students_rls_for_two_teachers.sql`
- Updates RLS policies for students, contracts, and lessons tables
- Ensures compatibility with new student_teachers table

## How to Apply

### Step 1: Apply Database Migrations
1. Copy the SQL from `apply_two_teachers_migration.sql`
2. Run it in your Supabase SQL editor
3. Copy the SQL from `update_students_rls_for_two_teachers.sql`
4. Run it in your Supabase SQL editor

### Step 2: Deploy Frontend Changes
The frontend changes are already applied to the following files:
- `src/components/forms/StudentForm.tsx`
- `src/components/tabs/StudentsTab.tsx`
- `src/components/tabs/StudentCardView.tsx`
- `src/components/tabs/ContractsTab.tsx`
- `src/components/StudentCountTooltip.tsx`

## Usage

### For Admins
1. When adding/editing a student, you can select up to 2 teachers
2. Both teachers will have access to the student's contracts and lessons
3. The first selected teacher becomes the "primary" teacher (stored in students.teacher_id)

### For Teachers
1. Teachers can see all students assigned to them (either as primary or additional teacher)
2. Teachers can edit contracts and lessons for their assigned students
3. Teachers can only assign students to themselves (existing behavior maintained)

## Backwards Compatibility
- Existing students with single teacher assignments continue to work
- The `students.teacher_id` field is maintained for backwards compatibility
- All existing RLS policies continue to work
- Existing contracts and lessons are unaffected

## Testing
1. Create a new student with 2 teachers
2. Verify both teachers can see the student
3. Verify both teachers can edit the student's contracts
4. Verify the max 2 teachers constraint works
5. Test backwards compatibility with existing single-teacher students
