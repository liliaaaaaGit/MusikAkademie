import { useState, useEffect } from 'react';
import { User } from '@supabase/supabase-js';
import { supabase, Profile, isSupabaseConfigured } from '@/lib/supabase';

export function useAuth() {
  const [user, setUser] = useState<User | null>(null);
  const [profile, setProfile] = useState<Profile | null>(null);
  const [loading, setLoading] = useState(true);
  const [configError, setConfigError] = useState(false);

  useEffect(() => {
    // Check if Supabase is properly configured
    if (!isSupabaseConfigured) {
      setConfigError(true);
      setLoading(false);
      return;
    }

    // Get initial session
    supabase.auth.getSession().then(async ({ data: { session } }) => {
      setUser(session?.user ?? null);
      if (session?.user) {
        fetchProfile(session.user.id);
      } else {
        setLoading(false);
      }
    });

    // Listen for auth changes
    const { data: { subscription } } = supabase.auth.onAuthStateChange(
      async (_event, session) => {
        setUser(session?.user ?? null);
        if (session?.user) {
          fetchProfile(session.user.id);
        } else {
          setProfile(null);
          setLoading(false);
        }
      }
    );

    return () => subscription.unsubscribe();
  }, []);

  const fetchProfile = async (userId: string) => {
    try {
      console.log('Fetching profile for user:', userId);
      const { data, error } = await supabase
        .from('profiles')
        .select('*')
        .eq('id', userId);

      if (error) {
        console.error('Error fetching profile:', error);
        // If there's an error fetching the profile, sign out to clear invalid session
        await supabase.auth.signOut();
        setProfile(null);
        setUser(null);
      } else if (data && data.length > 0) {
        console.log('Profile found:', data[0]);
        setProfile(data[0]);
      } else {
        console.log('No profile found for user:', userId);
        // Try to create profile manually
        await createProfileManually(userId);
      }
    } catch (error) {
      console.error('Error fetching profile:', error);
      // If there's an exception, sign out to clear invalid session
      await supabase.auth.signOut();
      setProfile(null);
      setUser(null);
    } finally {
      setLoading(false);
    }
  };

  const createProfileManually = async (userId: string) => {
    try {
      console.log('Attempting to create profile manually for user:', userId);
      
      // Get current session instead of trying to get user data again
      const { data: { session }, error: sessionError } = await supabase.auth.getSession();
      
      if (sessionError || !session?.user) {
        console.error('Error getting session data:', sessionError);
        return;
      }

      const user = session.user;
      console.log('User data from session:', user);

      // Create profile with user metadata (without updated_at field)
      const { data: profileData, error: profileError } = await supabase
        .from('profiles')
        .insert({
          id: userId,
          email: user.email,
          full_name: user.user_metadata?.full_name || 'Unknown',
          role: user.user_metadata?.role || 'teacher'
        })
        .select()
        .single();

      if (profileError) {
        console.error('Error creating profile manually:', profileError);
        
        // If it's an RLS policy issue, try to create without the created_at field
        if (profileError.message.includes('new row violates row-level security policy')) {
          console.log('RLS policy blocked profile creation, trying alternative approach...');
          
          // Try to create profile using a different approach
          const { data: altProfileData, error: altProfileError } = await supabase
            .rpc('create_profile_for_user', {
              user_id: userId,
              user_email: user.email,
              user_full_name: user.user_metadata?.full_name || 'Unknown',
              user_role: user.user_metadata?.role || 'teacher'
            });
          
          if (altProfileError) {
            console.error('Alternative profile creation also failed:', altProfileError);
            await supabase.auth.signOut();
            setProfile(null);
            setUser(null);
            return;
          }
          
          console.log('Profile created via RPC:', altProfileData);
          setProfile(altProfileData);
        } else {
          // If profile creation fails, sign out
          await supabase.auth.signOut();
          setProfile(null);
          setUser(null);
          return;
        }
      } else {
        console.log('Profile created successfully:', profileData);
        setProfile(profileData);
      }

      // Update teacher record if teacher_id is provided
      if (user.user_metadata?.teacher_id) {
        try {
          const { error: updateError } = await supabase
            .from('teachers')
            .update({ profile_id: userId })
            .eq('id', user.user_metadata.teacher_id);
          
          if (updateError) {
            console.error('Error updating teacher record:', updateError);
          } else {
            console.log('Teacher record updated successfully');
          }
        } catch (updateError) {
          console.error('Exception updating teacher record:', updateError);
        }
      }

    } catch (error) {
      console.error('Exception creating profile manually:', error);
      // If there's an exception, sign out
      await supabase.auth.signOut();
      setProfile(null);
      setUser(null);
    } finally {
      setLoading(false);
    }
  };

  const signIn = async (email: string, password: string) => {
    const { data, error } = await supabase.auth.signInWithPassword({
      email,
      password,
    });
    return { data, error };
  };

  const signOut = async () => {
    const { error } = await supabase.auth.signOut();
    return { error };
  };

  return {
    user,
    profile,
    loading,
    configError,
    signIn,
    signOut,
    isAdmin: profile?.role === 'admin',
    isTeacher: profile?.role === 'teacher',
  };
}