-- =============================================================================
-- Migration: 003_example_user.sql
-- Description: Creates an example user in Supabase Auth for development and
--              testing purposes. This user can be used to test the login flow
--              without needing to register a new account.
--
-- Example login credentials:
--   Email:    demo@pushup.app
--   Password: PushUp2024!
--
-- HOW TO RUN:
--   Option A (Supabase Dashboard):
--     1. Go to Authentication > Users > Add user > Create new user
--     2. Email: demo@pushup.app
--     3. Password: PushUp2024!
--     4. Check "Auto Confirm User"
--     5. Click "Create user"
--     The trigger trg_on_auth_user_created will automatically create the
--     public.users, public.time_credits, and public.user_settings rows.
--
--   Option B (SQL Editor — only works if you have service_role access):
--     Paste this file into the SQL Editor and click "Run".
--     Note: Inserting into auth.users requires service_role privileges.
--
-- WARNING: Run this ONLY in a development / staging Supabase project.
--          Never run against production.
-- =============================================================================


-- =============================================================================
-- IMPORTANT: The auth.users insert below requires service_role access.
-- If you are running this in the Supabase SQL Editor with the default
-- postgres role, it will fail with a permission error.
--
-- RECOMMENDED APPROACH: Create the user via the Supabase Dashboard UI:
--   Authentication > Users > Add user > Create new user
--   Email: demo@pushup.app | Password: PushUp2024! | Auto Confirm: YES
--
-- The SQL below is provided as a reference for automated setup scripts
-- that have service_role access (e.g. CI/CD pipelines).
-- =============================================================================

-- Create the example user in Supabase Auth.
-- The bcrypt hash below corresponds to the password: PushUp2024!
-- Generated with: SELECT crypt('PushUp2024!', gen_salt('bf'));
--
-- NOTE: This INSERT will be skipped if the email already exists (ON CONFLICT DO NOTHING).
DO $$
DECLARE
  v_user_id UUID := '11111111-1111-1111-1111-111111111111';
  v_email   TEXT := 'demo@pushup.app';
BEGIN
  -- Only insert if the user does not already exist
  IF NOT EXISTS (
    SELECT 1 FROM auth.users WHERE email = v_email
  ) THEN
    INSERT INTO auth.users (
      id,
      instance_id,
      email,
      encrypted_password,
      email_confirmed_at,
      created_at,
      updated_at,
      raw_app_meta_data,
      raw_user_meta_data,
      is_super_admin,
      role,
      aud
    ) VALUES (
      v_user_id,
      '00000000-0000-0000-0000-000000000000',
      v_email,
      -- bcrypt hash of 'PushUp2024!'
      crypt('PushUp2024!', gen_salt('bf')),
      NOW(),  -- email_confirmed_at: pre-confirmed for development
      NOW(),
      NOW(),
      '{"provider": "email", "providers": ["email"]}',
      '{"display_name": "Demo User"}',
      FALSE,
      'authenticated',
      'authenticated'
    );

    -- The trigger trg_on_auth_user_created should have created the public rows.
    -- Insert them manually as a safety net in case the trigger was not fired.
    INSERT INTO public.users (id, email, display_name, created_at, updated_at)
    VALUES (v_user_id, v_email, 'Demo User', NOW(), NOW())
    ON CONFLICT (id) DO NOTHING;

    INSERT INTO public.time_credits (user_id, total_earned_seconds, total_spent_seconds)
    VALUES (v_user_id, 0, 0)
    ON CONFLICT (user_id) DO NOTHING;

    INSERT INTO public.user_settings (user_id, push_ups_per_minute_credit, quality_multiplier_enabled)
    VALUES (v_user_id, 10, FALSE)
    ON CONFLICT (user_id) DO NOTHING;

    RAISE NOTICE 'Example user created: % (id: %)', v_email, v_user_id;
  ELSE
    RAISE NOTICE 'Example user already exists: %', v_email;
  END IF;
END;
$$;


-- =============================================================================
-- VERIFICATION
-- After running this migration, verify the user was created:
--
-- SELECT id, email, email_confirmed_at FROM auth.users WHERE email = 'demo@pushup.app';
-- SELECT id, email, display_name FROM public.users WHERE email = 'demo@pushup.app';
-- SELECT user_id, total_earned_seconds FROM public.time_credits WHERE user_id = '11111111-1111-1111-1111-111111111111';
--
-- Test login via curl:
-- curl -X POST 'https://<YOUR-PROJECT-REF>.supabase.co/auth/v1/token?grant_type=password' \
--   -H "apikey: <YOUR-ANON-KEY>" \
--   -H "Content-Type: application/json" \
--   -d '{"email": "demo@pushup.app", "password": "PushUp2024!"}'
-- =============================================================================


-- =============================================================================
-- END OF MIGRATION 003
-- =============================================================================
