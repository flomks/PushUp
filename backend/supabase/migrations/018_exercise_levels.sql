-- =============================================================================
-- Migration: 018_exercise_levels.sql
-- Description: Add exercise_levels table for per-exercise XP / level tracking.
--              Each (user_id, exercise_type) pair has its own XP counter.
--              The current level is derived from total_xp on the client using
--              the same formula as user_levels: xpForLevel(n) = floor(100 * n^1.5).
-- Created: 2026-03-29
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
--     psql "$DATABASE_URL" -f backend/supabase/migrations/018_exercise_levels.sql
--
-- HOW TO ROLL BACK:
--   Execute the ROLLBACK section at the bottom of this file.
-- =============================================================================


-- =============================================================================
-- FORWARD MIGRATION
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. TABLE: exercise_levels
--    Stores accumulated XP per (user, exercise_type) pair.
--    exercise_type values: 'pushUps', 'plank', 'jumpingJacks', 'squats',
--                          'crunches', 'jogging'.
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.exercise_levels (
  id            UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id       UUID        NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  exercise_type TEXT        NOT NULL,
  total_xp      BIGINT      NOT NULL DEFAULT 0,
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(user_id, exercise_type)
);

CREATE INDEX IF NOT EXISTS idx_exercise_levels_user_id
  ON public.exercise_levels(user_id);

COMMENT ON TABLE  public.exercise_levels               IS 'Per-exercise XP tracking. Level is derived from total_xp on the client.';
COMMENT ON COLUMN public.exercise_levels.id             IS 'UUID primary key.';
COMMENT ON COLUMN public.exercise_levels.user_id        IS 'FK to users.id.';
COMMENT ON COLUMN public.exercise_levels.exercise_type  IS 'Exercise identifier (pushUps, plank, jumpingJacks, squats, crunches, jogging).';
COMMENT ON COLUMN public.exercise_levels.total_xp       IS 'Total XP accumulated for this exercise. Monotonically increasing.';


-- -----------------------------------------------------------------------------
-- 2. TRIGGER: auto-update updated_at
--    Reuses the shared set_updated_at() function from migration 001.
-- -----------------------------------------------------------------------------

CREATE TRIGGER trg_exercise_levels_updated_at
  BEFORE UPDATE ON public.exercise_levels
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


-- -----------------------------------------------------------------------------
-- 3. ROW LEVEL SECURITY (RLS)
-- -----------------------------------------------------------------------------

ALTER TABLE public.exercise_levels ENABLE ROW LEVEL SECURITY;

CREATE POLICY "exercise_levels_select_own"
  ON public.exercise_levels FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "exercise_levels_insert_own"
  ON public.exercise_levels FOR INSERT
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "exercise_levels_update_own"
  ON public.exercise_levels FOR UPDATE
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

-- No DELETE policy: exercise XP is permanent.


-- =============================================================================
-- ROLLBACK
-- =============================================================================

-- BEGIN;
--
-- DROP POLICY IF EXISTS "exercise_levels_select_own" ON public.exercise_levels;
-- DROP POLICY IF EXISTS "exercise_levels_insert_own" ON public.exercise_levels;
-- DROP POLICY IF EXISTS "exercise_levels_update_own" ON public.exercise_levels;
-- DROP TRIGGER IF EXISTS trg_exercise_levels_updated_at ON public.exercise_levels;
-- DROP INDEX  IF EXISTS public.idx_exercise_levels_user_id;
-- DROP TABLE  IF EXISTS public.exercise_levels CASCADE;
--
-- COMMIT;


-- =============================================================================
-- END OF MIGRATION 018
-- =============================================================================
