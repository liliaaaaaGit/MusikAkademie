/*
  # Fix Lesson Number Constraint for High-Lesson Contracts

  1. Changes
    - Update the lesson_number constraint to allow up to 110 lessons
    - This accommodates contract variants like Diplomausbildung that have 72-108 lessons
    - Ensures contract creation doesn't fail for high-lesson contracts

  2. Security
    - No changes to RLS policies
    - Maintains existing security constraints
*/

-- Update the lesson number constraint to allow up to 110 lessons
ALTER TABLE lessons DROP CONSTRAINT IF EXISTS lessons_lesson_number_check;
ALTER TABLE lessons ADD CONSTRAINT lessons_lesson_number_check CHECK (lesson_number >= 1 AND lesson_number <= 110);