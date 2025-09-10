import { createClient } from '@supabase/supabase-js'

const supabaseUrl = 'https://gosyvigqhfwiexzpwaya.supabase.co'
const supabaseKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imdvc3l2aWdxaGZ3aWV4enB3YXlhIiwicm9sZSI6ImFub24iLCJpYXQiOjE3MTk0OTQ4NzMsImV4cCI6MjAzNTA3MDg3M30.8Q5Q5Q5Q5Q5Q5Q5Q5Q5Q5Q5Q5Q5Q5Q5Q5Q5Q5Q5Q'

const supabase = createClient(supabaseUrl, supabaseKey)

async function applyMigration() {
  try {
    console.log('Applying migration: Phase A - contracts.teacher_id setup...')
    
    // Read the migration file
    const fs = await import('fs')
    const migrationSQL = fs.readFileSync('supabase/migrations/20250108_phase_a_contracts_teacher_id_setup.sql', 'utf8')
    
    // Execute the migration
    const { data, error } = await supabase.rpc('exec_sql', { sql: migrationSQL })
    
    if (error) {
      console.error('Migration failed:', error)
    } else {
      console.log('Migration applied successfully!')
    }
  } catch (err) {
    console.error('Error:', err)
  }
}

applyMigration()
