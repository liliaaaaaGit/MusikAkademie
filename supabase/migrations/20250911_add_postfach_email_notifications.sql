-- Add email notification support for Postfach messages
-- Feature-flagged and teacher-only email notifications

-- Add email_notified_at column to track notification status
ALTER TABLE public.postbox_messages 
ADD COLUMN IF NOT EXISTS email_notified_at timestamptz;

-- Add comment for documentation
COMMENT ON COLUMN public.postbox_messages.email_notified_at IS 'Timestamp when email notification was sent for this message. NULL means no notification sent yet.';

-- Create index for performance on notification queries
CREATE INDEX IF NOT EXISTS idx_postbox_messages_email_notified_at 
ON public.postbox_messages(email_notified_at) 
WHERE email_notified_at IS NULL;
