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
    supabase.auth.getSession().then(({ data: { session } }) => {
      setUser(session?.user ?? null);
      if (session?.user) {
        fetchProfile(session.user.id);
      } else {
        setLoading(false);
      }
    });

    // Listen for auth changes
    const { data: { subscription } } = supabase.auth.onAuthStateChange(
      async (event, session) => {
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
        // If user exists but no profile is found, sign out to clear invalid session
        await supabase.auth.signOut();
        setProfile(null);
        setUser(null);
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