-- =============================================================================
-- Migration: 007_user_levels.sql
-- Description: Add user_levels table for XP / level tracking
-- Created: 2026-03-12
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Table: user_levels
-- Stores the accumulated XP for each user (one row per user).
-- The current level and progress are derived from total_xp on the client side
-- using the LevelCalculator formula: xpForLevel(n) = floor(100 * n^1.5).
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.user_levels (
  id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     UUID        NOT NULL UNIQUE REFERENCES public.users(id) ON DELETE CASCADE,
  total_xp    BIGINT      NOT NULL DEFAULT 0,
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_user_levels_user_id
  ON public.user_levels(user_id);

COMMENT ON TABLE  public.user_levels           IS 'Accumulated XP per user. Level is derived from total_xp on the client.';
COMMENT ON COLUMN public.user_levels.id        IS 'UUID primary key.';
COMMENT ON COLUMN public.user_levels.user_id   IS 'References public.users(id). One row per user.';
COMMENT ON COLUMN public.user_levels.total_xp  IS 'Total XP accumulated across all time. Monotonically increasing.';
COMMENT ON COLUMN public.user_levels.updated_at IS 'Timestamp of last update (server-managed).';

-- Automatically update updated_at on every row change.
CREATE OR REPLACE FUNCTION public.set_user_levels_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_user_levels_updated_at
  BEFORE UPDATE ON public.user_levels
  FOR EACH ROW EXECUTE FUNCTION public.set_user_levels_updated_at();

-- =============================================================================
-- Row Level Security (RLS)
-- =============================================================================

ALTER TABLE public.user_levels ENABLE ROW LEVEL SECURITY;

-- Users can only read their own level record.
CREATE POLICY "user_levels_select_own"
  ON public.user_levels
  FOR SELECT
  USING (auth.uid() = user_id);

-- Users can insert their own level record (first sync).
CREATE POLICY "user_levels_insert_own"
  ON public.user_levels
  FOR INSERT
  WITH CHECK (auth.uid() = user_id);

-- Users can update their own level record.
CREATE POLICY "user_levels_update_own"
  ON public.user_levels
  FOR UPDATE
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

-- Users cannot delete their own level record (XP is permanent).
-- No DELETE policy is created intentionally.
