# Postfach Email Notifications - Manual Test Guide

## Setup
1. Set environment variables in your `.env` file:
   ```bash
   VITE_EMAIL_NOTIFICATIONS_ENABLED=true
   VITE_RESEND_API_KEY=your_resend_api_key
   VITE_MAIL_FROM=noreply@yourdomain.com
   ```

2. Apply the migration:
   ```sql
   -- Run in Supabase SQL Editor
   ALTER TABLE public.postbox_messages 
   ADD COLUMN IF NOT EXISTS email_notified_at timestamptz;
   
   CREATE INDEX IF NOT EXISTS idx_postbox_messages_email_notified_at 
   ON public.postbox_messages(email_notified_at) 
   WHERE email_notified_at IS NULL;
   ```

## Test Cases

### Test 1: Admin-only Postfach item (no teacher_id) → no email
```sql
-- Insert message without teacher_id
INSERT INTO public.postbox_messages (subject, content, created_at)
VALUES ('Admin Message', 'This is for admins only', now())
RETURNING id;
```
**Expected Result:** No email sent, email_notified_at remains NULL

### Test 2: Teacher-targeted message → email sent once
```sql
-- Insert message for a teacher (replace with actual teacher_id)
INSERT INTO public.postbox_messages (teacher_id, subject, content, created_at)
VALUES ('actual-teacher-uuid-here', 'Teacher Message', 'This is for a teacher', now())
RETURNING id;
```
**Expected Result:** 
- Email sent to teacher's email address
- email_notified_at set to current timestamp

### Test 3: Re-run notification for same message → no duplicate
```sql
-- Check the message was marked as notified
SELECT id, teacher_id, email_notified_at 
FROM public.postbox_messages 
WHERE id = 'message-id-from-test-2';
```
**Expected Result:** email_notified_at is not NULL, no duplicate email sent

### Test 4: Feature flag disabled → no emails
```bash
# Set environment variable in .env file
VITE_EMAIL_NOTIFICATIONS_ENABLED=false
```
**Expected Result:** No emails sent regardless of message type

## Verification Queries

```sql
-- Check all messages and their notification status
SELECT 
  id,
  teacher_id,
  subject,
  email_notified_at,
  CASE 
    WHEN email_notified_at IS NOT NULL THEN 'Notified'
    WHEN teacher_id IS NULL THEN 'No teacher (no notification)'
    ELSE 'Pending notification'
  END as notification_status
FROM public.postbox_messages
ORDER BY created_at DESC;

-- Check teacher email resolution
SELECT 
  t.id as teacher_id,
  p.email,
  p.is_active
FROM public.teachers t
JOIN public.profiles p ON p.id = t.profile_id
WHERE t.id = 'your-teacher-id';
```

## Success Criteria
- ✅ Admin messages (no teacher_id) never trigger emails
- ✅ Teacher messages trigger exactly one email per message
- ✅ Duplicate calls don't send duplicate emails
- ✅ Feature flag properly controls email sending
- ✅ Invalid/disabled teachers don't receive emails
