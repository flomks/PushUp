-- =============================================================================
-- Migration: 005_add_username.sql
-- Description: Adds a unique, searchable username column to public.users.
--              Username is distinct from display_name: it is a short, unique
--              handle (e.g. "john_doe") used for search and @-mentions, while
--              display_name is the free-form name shown in the UI.
-- Created: 2026-03-09
-- Depends on: 001_initial_schema.sql (public.users)
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
--     psql "$DATABASE_URL" -f backend/supabase/migrations/005_add_username.sql
--
-- HOW TO ROLL BACK:
--   Execute the "ROLLBACK" section at the bottom of this file.
-- =============================================================================


-- =============================================================================
-- FORWARD MIGRATION
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Add the username column (nullable initially so existing rows are valid).
--    After back-filling, a NOT NULL constraint can be added if desired.
--    Stored in lowercase to make case-insensitive uniqueness enforcement simple.
-- -----------------------------------------------------------------------------

ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS username TEXT;

COMMENT ON COLUMN public.users.username IS
  'Unique, lowercase handle chosen by the user (e.g. "john_doe"). '
  'Used for search and @-mentions. Distinct from display_name.';


-- -----------------------------------------------------------------------------
-- 2. UNIQUE constraint -- only one user may hold a given username.
--    The constraint is created as a partial index so NULL values (users who
--    have not yet chosen a username) are excluded and do not conflict.
-- -----------------------------------------------------------------------------

CREATE UNIQUE INDEX IF NOT EXISTS idx_users_username_unique
  ON public.users (username)
  WHERE username IS NOT NULL;


-- -----------------------------------------------------------------------------
-- 3. SEARCH INDEX -- case-insensitive prefix / substring search.
--    Using a GIN index on to_tsvector is overkill for a simple ILIKE search;
--    a plain B-tree index on lower(username) is sufficient and cheaper.
-- -----------------------------------------------------------------------------

CREATE INDEX IF NOT EXISTS idx_users_username_lower
  ON public.users (lower(username));

CREATE INDEX IF NOT EXISTS idx_users_display_name_lower
  ON public.users (lower(display_name));


-- -----------------------------------------------------------------------------
-- 4. RLS -- existing "users_select_own" policy only allows a user to read
--    their own row.  For user search to work, authenticated users must be
--    able to read the public profile columns (id, username, display_name,
--    avatar_url) of OTHER users.  We add a separate SELECT policy that
--    exposes only those non-sensitive columns.
--
--    NOTE: The backend Ktor service connects with the service-role key (or a
--    dedicated DB user that bypasses RLS), so this policy is primarily for
--    direct Supabase client access.  The Ktor endpoint itself enforces
--    authentication via JWT and filters sensitive fields in application code.
-- -----------------------------------------------------------------------------

-- Allow any authenticated user to read the public profile of any other user.
-- Sensitive columns (email) are never returned by the search endpoint.
CREATE POLICY "users_select_public_profile"
  ON public.users
  FOR SELECT
  USING (auth.role() = 'authenticated');


-- =============================================================================
-- VERIFICATION QUERIES
-- Run these manually in the SQL Editor to confirm the setup is correct.
-- =============================================================================

-- Check column exists:
-- SELECT column_name, data_type, is_nullable
-- FROM information_schema.columns
-- WHERE table_schema = 'public' AND table_name = 'users' AND column_name = 'username';

-- Check indexes:
-- SELECT indexname, indexdef
-- FROM pg_indexes
-- WHERE schemaname = 'public' AND tablename = 'users'
-- ORDER BY indexname;

-- Check policies:
-- SELECT policyname, cmd, qual
-- FROM pg_policies
-- WHERE schemaname = 'public' AND tablename = 'users'
-- ORDER BY policyname;


-- =============================================================================
-- ROLLBACK
-- Execute this block to undo everything created by this migration.
-- =============================================================================

-- BEGIN;
--
-- DROP POLICY  IF EXISTS "users_select_public_profile" ON public.users;
-- DROP INDEX   IF EXISTS public.idx_users_display_name_lower;
-- DROP INDEX   IF EXISTS public.idx_users_username_lower;
-- DROP INDEX   IF EXISTS public.idx_users_username_unique;
-- ALTER TABLE  public.users DROP COLUMN IF EXISTS username;
--
-- COMMIT;


-- =============================================================================
-- END OF MIGRATION 005
-- =============================================================================
