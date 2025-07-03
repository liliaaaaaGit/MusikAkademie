/*
  # Add comments field to lessons table

  1. Changes
    - Add `comment` text field to lessons table for optional notes
    - Update existing lessons to have null comments by default

  2. Security
    - No changes to RLS policies needed as comments follow same access patterns
*/

-- Add comment field to lessons table
ALTER TABLE lessons ADD COLUMN IF NOT EXISTS comment text;

-- Add index for better performance when filtering by comments
CREATE INDEX IF NOT EXISTS idx_lessons_comment ON lessons(comment) WHERE comment IS NOT NULL;