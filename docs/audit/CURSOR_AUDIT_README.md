# MAM WebApp Database Audit

## Instructions

This audit identifies forbidden references (`s.teacher_id`, `students.teacher_id`, ambiguous `contract_id`) across the database schema.

### Steps

1. **Open Supabase SQL Editor**
   - Go to your Supabase dashboard
   - Navigate to SQL Editor
   - Create a new query

2. **Run the Audit SQL**
   - Copy the contents of `scripts/audit/db_audit.sql`
   - Paste into the SQL Editor
   - Execute the query

3. **Collect Results**
   - Copy all result tables from the SQL Editor
   - Paste each result set into `docs/audit/DB_AUDIT_RESULTS.md`
   - Maintain the table structure and section headers

4. **Run Code Audit**
   ```bash
   npm run audit:code
   ```

5. **Review Fixlist**
   - Check `docs/audit/FIXLIST.md` for specific objects requiring changes
   - Only modify objects listed in the fixlist
   - Do NOT modify app logic or database schema beyond listed items

## Output Files

- `docs/audit/DB_AUDIT_RESULTS.md` - Database audit results
- `docs/audit/CODE_AUDIT_REPORT.json` - Detailed code audit JSON
- `docs/audit/CODE_AUDIT_SUMMARY.md` - Code audit summary
- `docs/audit/FIXLIST.md` - Surgical cleanup targets only

## Safety

This is a READ-ONLY audit. No modifications are made to the database or codebase during the audit process.
