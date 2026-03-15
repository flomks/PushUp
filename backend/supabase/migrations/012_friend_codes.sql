-- =============================================================================
-- Migration: 012_friend_codes.sql
-- Description: Friend Codes feature -- friend_codes table with privacy enum,
--              indexes, updated_at trigger, and Row Level Security policies.
--
-- A friend code is a short, shareable alphanumeric code (8 characters) that
-- lets any user add the owner as a friend without a manual search.
--
-- Privacy modes:
--   auto_accept      -- anyone who uses the code is added as a friend immediately
--   require_approval -- using the code creates a pending friend request that the
--                       owner must accept
--   inactive         -- the code is disabled; attempts to use it are rejected
--
-- Created: 2026-03-15
-- Depends on: 001_initial_schema.sql (public.users, set_updated_at function)
-- =============================================================================


-- =============================================================================
-- FORWARD MIGRATION
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. ENUM TYPE: friend_code_privacy
-- -----------------------------------------------------------------------------

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_type WHERE typname = 'friend_code_privacy'
  ) THEN
    CREATE TYPE public.friend_code_privacy AS ENUM (
      'auto_accept',
      'require_approval',
      'inactive'
    );
  END IF;
END;
$$;

COMMENT ON TYPE public.friend_code_privacy IS
  'Privacy setting for a friend code: '
  'auto_accept (instant friend), require_approval (pending request), inactive (disabled).';


-- -----------------------------------------------------------------------------
-- 2. TABLE: friend_codes
--    One row per user. Each user has exactly one friend code at a time.
--    The code can be reset (new value generated) or deactivated.
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.friend_codes (
  id         UUID                      PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    UUID                      NOT NULL UNIQUE REFERENCES public.users(id) ON DELETE CASCADE,
  code       TEXT                      NOT NULL UNIQUE,
  privacy    public.friend_code_privacy NOT NULL DEFAULT 'require_approval',
  created_at TIMESTAMPTZ               NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ               NOT NULL DEFAULT NOW(),

  -- Code must be 4-16 uppercase alphanumeric characters.
  CONSTRAINT friend_codes_code_format CHECK (code ~ '^[A-Z0-9]{4,16}$')
);

COMMENT ON TABLE  public.friend_codes            IS 'Shareable friend codes -- one per user.';
COMMENT ON COLUMN public.friend_codes.id         IS 'Surrogate primary key (UUID v4).';
COMMENT ON COLUMN public.friend_codes.user_id    IS 'FK to users.id -- the owner of this code.';
COMMENT ON COLUMN public.friend_codes.code       IS 'Short uppercase alphanumeric code (4-16 chars, globally unique).';
COMMENT ON COLUMN public.friend_codes.privacy    IS 'Controls what happens when someone uses this code.';
COMMENT ON COLUMN public.friend_codes.created_at IS 'Timestamp when the code was first generated.';
COMMENT ON COLUMN public.friend_codes.updated_at IS 'Timestamp of the last change (auto-updated by trigger).';


-- -----------------------------------------------------------------------------
-- 3. INDEXES
-- -----------------------------------------------------------------------------

-- Fast lookup by code value (used when someone enters/scans a code).
CREATE INDEX IF NOT EXISTS idx_friend_codes_code
  ON public.friend_codes(code);

-- Fast lookup by owner (used to fetch/update the user's own code).
CREATE INDEX IF NOT EXISTS idx_friend_codes_user_id
  ON public.friend_codes(user_id);


-- -----------------------------------------------------------------------------
-- 4. TRIGGER: auto-update updated_at on every row change
-- -----------------------------------------------------------------------------

CREATE TRIGGER trg_friend_codes_updated_at
  BEFORE UPDATE ON public.friend_codes
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


-- -----------------------------------------------------------------------------
-- 5. ROW LEVEL SECURITY (RLS)
-- -----------------------------------------------------------------------------

ALTER TABLE public.friend_codes ENABLE ROW LEVEL SECURITY;

-- SELECT: anyone authenticated can look up a code by its value (needed to use it).
--         The owner can also read their own row.
CREATE POLICY "friend_codes_select"
  ON public.friend_codes
  FOR SELECT
  USING (true);

-- INSERT: a user can only create a code for themselves.
CREATE POLICY "friend_codes_insert_own"
  ON public.friend_codes
  FOR INSERT
  WITH CHECK (auth.uid() = user_id);

-- UPDATE: only the owner may update their own code row.
CREATE POLICY "friend_codes_update_own"
  ON public.friend_codes
  FOR UPDATE
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

-- DELETE: only the owner may delete their own code row.
CREATE POLICY "friend_codes_delete_own"
  ON public.friend_codes
  FOR DELETE
  USING (auth.uid() = user_id);


-- =============================================================================
-- VERIFICATION QUERIES (run manually in SQL Editor)
-- =============================================================================

-- SELECT column_name, data_type, is_nullable, column_default
-- FROM information_schema.columns
-- WHERE table_schema = 'public' AND table_name = 'friend_codes'
-- ORDER BY ordinal_position;

-- SELECT enumlabel FROM pg_enum
-- JOIN pg_type ON pg_enum.enumtypid = pg_type.oid
-- WHERE pg_type.typname = 'friend_code_privacy'
-- ORDER BY enumsortorder;


-- =============================================================================
-- ROLLBACK
-- =============================================================================

-- BEGIN;
-- DROP POLICY IF EXISTS "friend_codes_select"      ON public.friend_codes;
-- DROP POLICY IF EXISTS "friend_codes_insert_own"  ON public.friend_codes;
-- DROP POLICY IF EXISTS "friend_codes_update_own"  ON public.friend_codes;
-- DROP POLICY IF EXISTS "friend_codes_delete_own"  ON public.friend_codes;
-- DROP TRIGGER IF EXISTS trg_friend_codes_updated_at ON public.friend_codes;
-- DROP INDEX IF EXISTS public.idx_friend_codes_code;
-- DROP INDEX IF EXISTS public.idx_friend_codes_user_id;
-- DROP TABLE IF EXISTS public.friend_codes CASCADE;
-- DROP TYPE IF EXISTS public.friend_code_privacy;
-- COMMIT;


-- =============================================================================
-- END OF MIGRATION 012
-- =============================================================================
