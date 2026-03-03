-- =============================================================================
-- Migration: 002_auth_verification.sql
-- Description: Auth verification helpers and additional RLS hardening
--              for Email, Apple, and Google Sign-In providers.
-- Created: 2026-03-03
-- =============================================================================
-- Run this AFTER 001_initial_schema.sql.
-- Execute in: Supabase Dashboard > SQL Editor > New query > Run
-- =============================================================================


-- =============================================================================
-- 1. VERIFICATION VIEW
-- Lets you quickly confirm that RLS is active on all tables.
-- Usage: SELECT * FROM public.rls_status;
-- =============================================================================

CREATE OR REPLACE VIEW public.rls_status AS
SELECT
  tablename,
  rowsecurity AS rls_enabled
FROM pg_tables
WHERE schemaname = 'public'
ORDER BY tablename;

COMMENT ON VIEW public.rls_status IS
  'Quick check: shows whether RLS is enabled on every public table.';


-- =============================================================================
-- 2. VERIFICATION VIEW
-- Lists all RLS policies so you can confirm they are in place.
-- Usage: SELECT * FROM public.policy_overview;
-- =============================================================================

CREATE OR REPLACE VIEW public.policy_overview AS
SELECT
  tablename,
  policyname,
  cmd        AS operation,
  roles,
  qual       AS using_expression,
  with_check AS with_check_expression
FROM pg_policies
WHERE schemaname = 'public'
ORDER BY tablename, policyname;

COMMENT ON VIEW public.policy_overview IS
  'Quick check: lists all RLS policies on public tables.';


-- =============================================================================
-- 3. HELPER FUNCTION: is_authenticated()
-- Returns TRUE when the current request carries a valid Supabase JWT.
-- Can be used in policies or application code for clarity.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.is_authenticated()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
AS $$
  SELECT auth.uid() IS NOT NULL;
$$;

COMMENT ON FUNCTION public.is_authenticated() IS
  'Returns TRUE if the current request is authenticated (has a valid JWT).';


-- =============================================================================
-- 4. ADDITIONAL POLICY: users table -- allow authenticated insert for OAuth
-- When a user signs in via Apple or Google for the first time, the trigger
-- handle_new_auth_user() (SECURITY DEFINER) inserts the row.
-- This policy is a safety net in case the trigger is bypassed in tests.
-- =============================================================================

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename   = 'users'
      AND policyname  = 'users_insert_own'
  ) THEN
    EXECUTE $policy$
      CREATE POLICY "users_insert_own"
        ON public.users
        FOR INSERT
        WITH CHECK (auth.uid() = id)
    $policy$;
  END IF;
END;
$$;


-- =============================================================================
-- 5. VERIFICATION QUERIES
-- Run these manually in the SQL Editor to confirm the setup is correct.
-- They are wrapped in a DO block so they produce a NOTICE, not a result set.
-- To get result sets, run each SELECT individually.
-- =============================================================================

-- Check 1: All tables have RLS enabled
-- SELECT * FROM public.rls_status;

-- Check 2: All policies are present
-- SELECT * FROM public.policy_overview;

-- Check 3: Auth trigger exists
-- SELECT trigger_name, event_object_schema, event_object_table
-- FROM information_schema.triggers
-- WHERE trigger_name = 'trg_on_auth_user_created';

-- Check 4: After creating a test user, verify auto-created rows
-- SELECT u.id, u.email, tc.total_earned_seconds, us.push_ups_per_minute_credit
-- FROM public.users u
-- LEFT JOIN public.time_credits tc ON tc.user_id = u.id
-- LEFT JOIN public.user_settings us ON us.user_id = u.id
-- WHERE u.email = 'test@example.com';


-- =============================================================================
-- END OF MIGRATION 002
-- =============================================================================
