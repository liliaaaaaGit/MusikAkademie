// Email sending utility using Resend API
// Feature-flagged and teacher-only for Postfach notifications

export async function sendEmail(to: string[], subject: string, text: string, html?: string): Promise<void> {
  const apiKey = import.meta.env.VITE_RESEND_API_KEY;
  if (!apiKey) {
    console.warn('VITE_RESEND_API_KEY not configured, skipping email send');
    return;
  }

  const from = import.meta.env.VITE_MAIL_FROM || 'noreply@example.com';
  
  const payload = {
    from,
    to,
    subject,
    text,
    ...(html && { html }),
  };

  try {
    const response = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${apiKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(payload),
    });

    if (!response.ok) {
      const errorText = await response.text();
      console.error('Email send failed:', response.status, errorText);
      throw new Error(`Email send failed: ${response.status}`);
    }

    const result = await response.json();
    console.log('Email sent successfully:', result.id);
  } catch (error) {
    console.error('Email sending error:', error);
    throw error;
  }
}
