-- =============================================================================
-- Migration: 008_username_constraints.sql
-- Description: Adds a CHECK constraint to enforce username format rules:
--              - 3 to 20 characters
--              - Only lowercase letters (a-z), digits (0-9), and underscores (_)
--              These rules mirror the client-side validation in SafeAuthBridge
--              and the server-side validation in UsernameRoutes.
-- Created: 2026-03-13
-- Depends on: 005_add_username.sql (public.users.username column)
-- =============================================================================
--
-- HOW TO RUN (forward):
--   Option A (Supabase CLI):
--     supabase db push
--
--   Option B (Supabase Dashboard SQL Editor):
--     Paste this file and click "Run".
--
--   Option C (psql):
--     psql "$DATABASE_URL" -f backend/supabase/migrations/008_username_constraints.sql
--
-- HOW TO ROLL BACK:
--   Execute the ROLLBACK section at the bottom of this file.
-- =============================================================================


-- =============================================================================
-- FORWARD MIGRATION
-- =============================================================================

-- Add the CHECK constraint only if it does not already exist.
-- This makes the migration idempotent (safe to run more than once).
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM   pg_constraint
    WHERE  conname = 'users_username_format'
      AND  conrelid = 'public.users'::regclass
  ) THEN
    ALTER TABLE public.users
      ADD CONSTRAINT users_username_format
      CHECK (
        username IS NULL OR (
          length(username) >= 3
          AND length(username) <= 20
          AND username ~ '^[a-z0-9_.]+$'
          AND username NOT LIKE '.%'
          AND username NOT LIKE '%.'
          AND username NOT LIKE '%..%'
        )
      );
  END IF;
END;
$$;

COMMENT ON CONSTRAINT users_username_format ON public.users IS
  'Enforces username format: 3-20 chars, lowercase letters/digits/underscores only.';


-- =============================================================================
-- ROLLBACK
-- =============================================================================

-- ALTER TABLE public.users DROP CONSTRAINT IF EXISTS users_username_format;


-- =============================================================================
-- END OF MIGRATION 008
-- =============================================================================
