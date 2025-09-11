// Example React component showing how to use the postfach notification system
// This is just an example - adapt to your actual postfach message creation component

import { useState } from 'react';
import { supabase } from '@/lib/supabase';
import { maybeNotifyPostfachMessage } from '@/lib/notifications/postfach';

export function PostfachMessageExample() {
  const [loading, setLoading] = useState(false);
  const [message, setMessage] = useState('');

  const createPostfachMessage = async (teacherId: string, subject: string, content: string) => {
    setLoading(true);
    try {
      // Create the postfach message
      const { data, error } = await supabase
        .from('postbox_messages')
        .insert({
          teacher_id: teacherId,
          subject,
          content,
        })
        .select()
        .single();

      if (error) {
        throw error;
      }

      // Send email notification (if enabled and teacher exists)
      await maybeNotifyPostfachMessage(data.id);

      setMessage('Message created and notification sent!');
    } catch (error) {
      console.error('Error creating postfach message:', error);
      setMessage('Error creating message');
    } finally {
      setLoading(false);
    }
  };

  return (
    <div>
      <h3>Postfach Message Example</h3>
      <p>This shows how to create a postfach message and trigger email notifications.</p>
      {message && <p>{message}</p>}
      <button 
        onClick={() => createPostfachMessage('teacher-id', 'Test Subject', 'Test Content')}
        disabled={loading}
      >
        {loading ? 'Creating...' : 'Create Test Message'}
      </button>
    </div>
  );
}
