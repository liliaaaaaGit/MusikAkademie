require('dotenv').config();
const { createClient } = require('@supabase/supabase-js');

const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;

const TEST_PASSWORD = 'Test1234!';
const TEST_EMAIL = `testuser_${Date.now()}@x.de`; // ✅ Neue E-Mail pro Testlauf

let supabase;

describe('Teacher onboarding trigger', () => {
  beforeAll(() => {
    console.log('SUPABASE_URL:', SUPABASE_URL);
    console.log('SUPABASE_SERVICE_ROLE_KEY:', SUPABASE_SERVICE_ROLE_KEY);
    console.log('Dynamically generated test email:', TEST_EMAIL);

    if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) {
      throw new Error('Please set SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY in your .env file.');
    }

    supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
      auth: { autoRefreshToken: false, persistSession: false }
    });
  });

  afterAll(async () => {
    const { data: userList, error: listError } = await supabase.auth.admin.listUsers();
    if (listError) console.error('Error listing users:', listError);

    const existingUser = userList?.users?.find(u => u.email?.toLowerCase() === TEST_EMAIL.toLowerCase());
    if (existingUser) {
      console.log('Deleting test auth user:', existingUser.id);
      await supabase.auth.admin.deleteUser(existingUser.id);
      await supabase.from('profiles').delete().eq('id', existingUser.id);
      await supabase.from('teachers').update({ profile_id: null }).eq('email', TEST_EMAIL);
    }
  });

  it('creates and links a profile for a new teacher registration', async () => {
    await supabase.from('teachers').update({ profile_id: null }).eq('email', TEST_EMAIL);

    let { data: existingTeacher } = await supabase
      .from('teachers')
      .select('id')
      .eq('email', TEST_EMAIL)
      .maybeSingle();

    if (!existingTeacher) {
      const { error: insertError } = await supabase
        .from('teachers')
        .insert({ email: TEST_EMAIL, name: 'Test Lehrer' })
        .select();

      expect(insertError).toBeNull();

      // 🕒 aktiv warten, bis Insert greift
      for (let i = 0; i < 5; i++) {
        const { data: checkTeacher } = await supabase
          .from('teachers')
          .select('id')
          .eq('email', TEST_EMAIL)
          .maybeSingle();

        if (checkTeacher) {
          existingTeacher = checkTeacher;
          break;
        }
        await new Promise((r) => setTimeout(r, 500));
      }

      expect(existingTeacher).toBeDefined();
    }

    const { data: userData, error: signUpError } = await supabase.auth.signUp({
      email: 'testuser@example.com',
      password: 'securepassword'
    });

    if (!signUpError && userData.user) {
      const { data, error } = await supabase.rpc('create_profile_after_signup', {
        user_id: userData.user.id,
        user_email: userData.user.email
      });
      if (error) {
        console.error('RPC failed:', error);
        // Optionally show an error to the user
      }
    }

    await new Promise((resolve) => setTimeout(resolve, 2000));

    const { data: profile, error: profileError } = await supabase
      .from('profiles')
      .select('id, email, teacher_id')
      .eq('id', userId)
      .single();
    expect(profileError).toBeNull();
    expect(profile).toBeDefined();
    expect(profile.email.toLowerCase()).toBe(TEST_EMAIL.toLowerCase());
    expect(profile.teacher_id).toBeTruthy();

    const { data: teacher, error: teacherError } = await supabase
      .from('teachers')
      .select('id, profile_id')
      .eq('email', TEST_EMAIL)
      .single();
    expect(teacherError).toBeNull();
    expect(teacher).toBeDefined();
    expect(teacher.profile_id).toBe(userId);
  });
});
