-- =============================================================================
-- Migration: 007_user_levels.sql
-- Description: Add user_levels table for XP / level tracking.
--              Also updates handle_new_auth_user() to auto-create a user_levels
--              row on sign-up so new users start at XP = 0 immediately.
-- Created: 2026-03-12
-- Depends on: 001_initial_schema.sql (public.users, set_updated_at function)
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
--     psql "$DATABASE_URL" -f backend/supabase/migrations/007_user_levels.sql
--
-- HOW TO ROLL BACK:
--   Execute the ROLLBACK section at the bottom of this file.
-- =============================================================================


-- =============================================================================
-- FORWARD MIGRATION
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. TABLE: user_levels
--    Stores the accumulated XP for each user (one row per user).
--    The current level and progress are derived from total_xp on the client
--    using: xpForLevel(n) = floor(100 * n^1.5)
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.user_levels (
  id         UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    UUID        NOT NULL UNIQUE REFERENCES public.users(id) ON DELETE CASCADE,
  total_xp   BIGINT      NOT NULL DEFAULT 0,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_user_levels_user_id
  ON public.user_levels(user_id);

COMMENT ON TABLE  public.user_levels          IS 'Accumulated XP per user. Level is derived from total_xp on the client.';
COMMENT ON COLUMN public.user_levels.id       IS 'UUID primary key.';
COMMENT ON COLUMN public.user_levels.user_id  IS 'FK to users.id (one record per user).';
COMMENT ON COLUMN public.user_levels.total_xp IS 'Total XP accumulated across all time. Monotonically increasing.';


-- -----------------------------------------------------------------------------
-- 2. TRIGGER: auto-update updated_at
--    Reuses the shared set_updated_at() function from migration 001.
-- -----------------------------------------------------------------------------

CREATE TRIGGER trg_user_levels_updated_at
  BEFORE UPDATE ON public.user_levels
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


-- -----------------------------------------------------------------------------
-- 3. ROW LEVEL SECURITY (RLS)
-- -----------------------------------------------------------------------------

ALTER TABLE public.user_levels ENABLE ROW LEVEL SECURITY;

CREATE POLICY "user_levels_select_own"
  ON public.user_levels FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "user_levels_insert_own"
  ON public.user_levels FOR INSERT
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "user_levels_update_own"
  ON public.user_levels FOR UPDATE
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

-- No DELETE policy: XP is permanent.


-- -----------------------------------------------------------------------------
-- 4. UPDATE handle_new_auth_user() to also create a user_levels row.
--    This ensures every new sign-up starts with XP = 0 automatically.
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.handle_new_auth_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_display_name TEXT;
  v_avatar_url   TEXT;
BEGIN
  v_display_name := COALESCE(
    NULLIF(TRIM(NEW.raw_user_meta_data->>'full_name'), ''),
    NULLIF(TRIM(NEW.raw_user_meta_data->>'name'),      ''),
    SPLIT_PART(NEW.email, '@', 1)
  );

  v_avatar_url := NULLIF(TRIM(NEW.raw_user_meta_data->>'avatar_url'), '');

  INSERT INTO public.users (id, email, display_name, avatar_url, created_at, updated_at)
  VALUES (NEW.id, NEW.email, v_display_name, v_avatar_url, NOW(), NOW())
  ON CONFLICT (id) DO UPDATE SET
    email        = EXCLUDED.email,
    display_name = COALESCE(EXCLUDED.display_name, public.users.display_name),
    avatar_url   = COALESCE(EXCLUDED.avatar_url,   public.users.avatar_url),
    updated_at   = NOW();

  INSERT INTO public.time_credits (id, user_id, total_earned_seconds, total_spent_seconds, updated_at)
  VALUES (gen_random_uuid(), NEW.id, 0, 0, NOW())
  ON CONFLICT (user_id) DO NOTHING;

  INSERT INTO public.user_settings (id, user_id, push_ups_per_minute_credit, quality_multiplier_enabled, searchable_by_email, created_at, updated_at)
  VALUES (gen_random_uuid(), NEW.id, 10, FALSE, FALSE, NOW(), NOW())
  ON CONFLICT (user_id) DO NOTHING;

  INSERT INTO public.user_levels (id, user_id, total_xp, updated_at)
  VALUES (gen_random_uuid(), NEW.id, 0, NOW())
  ON CONFLICT (user_id) DO NOTHING;

  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.handle_new_auth_user() IS
  'Triggered after INSERT on auth.users. Creates companion rows in users, '
  'time_credits, user_settings, and user_levels.';


-- =============================================================================
-- ROLLBACK
-- =============================================================================

-- BEGIN;
--
-- -- Revert handle_new_auth_user to the version without user_levels insert.
-- -- (Paste the original function body from migration 001 here.)
--
-- DROP POLICY IF EXISTS "user_levels_select_own" ON public.user_levels;
-- DROP POLICY IF EXISTS "user_levels_insert_own" ON public.user_levels;
-- DROP POLICY IF EXISTS "user_levels_update_own" ON public.user_levels;
-- DROP TRIGGER IF EXISTS trg_user_levels_updated_at ON public.user_levels;
-- DROP INDEX  IF EXISTS public.idx_user_levels_user_id;
-- DROP TABLE  IF EXISTS public.user_levels CASCADE;
--
-- COMMIT;


-- =============================================================================
-- END OF MIGRATION 007
-- =============================================================================
