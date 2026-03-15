-- =============================================================================
-- Migration: 003_device_tokens.sql
-- Description: APNs / FCM push notification device token storage.
--              One row per (user, token) pair. Tokens are upserted on each
--              app launch so stale tokens are replaced automatically.
-- Created: 2026-03-09
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
--     psql "$DATABASE_URL" -f backend/supabase/migrations/003_device_tokens.sql
--
-- HOW TO ROLL BACK:
--   Execute the ROLLBACK section at the bottom of this file.
-- =============================================================================


-- =============================================================================
-- FORWARD MIGRATION
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. TABLE: device_tokens
--    Stores APNs (iOS) and FCM (Android) push notification tokens.
--    One row per (user, token) pair. The token column has a UNIQUE constraint
--    so upserts on the token value replace the old row atomically.
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.device_tokens (
  id         UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    UUID        NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  token      TEXT        NOT NULL,
  platform   TEXT        NOT NULL,   -- 'apns' | 'fcm'
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT device_tokens_unique_token UNIQUE (token)
);

COMMENT ON TABLE  public.device_tokens          IS 'Push notification tokens per user device.';
COMMENT ON COLUMN public.device_tokens.id       IS 'UUID primary key.';
COMMENT ON COLUMN public.device_tokens.user_id  IS 'FK to users.id.';
COMMENT ON COLUMN public.device_tokens.token    IS 'APNs or FCM device token (unique across all users).';
COMMENT ON COLUMN public.device_tokens.platform IS 'Push platform: ''apns'' (iOS) or ''fcm'' (Android).';


-- -----------------------------------------------------------------------------
-- 2. INDEXES
-- -----------------------------------------------------------------------------

CREATE INDEX IF NOT EXISTS idx_device_tokens_user_id
  ON public.device_tokens(user_id);


-- -----------------------------------------------------------------------------
-- 3. TRIGGER: auto-update updated_at
--    Reuses the shared set_updated_at() function from migration 001.
-- -----------------------------------------------------------------------------

CREATE TRIGGER trg_device_tokens_updated_at
  BEFORE UPDATE ON public.device_tokens
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


-- -----------------------------------------------------------------------------
-- 4. ROW LEVEL SECURITY (RLS)
-- -----------------------------------------------------------------------------

ALTER TABLE public.device_tokens ENABLE ROW LEVEL SECURITY;

-- Users can only read their own tokens.
CREATE POLICY "device_tokens_select_own"
  ON public.device_tokens FOR SELECT
  USING (auth.uid() = user_id);

-- Users can register tokens for their own account.
CREATE POLICY "device_tokens_insert_own"
  ON public.device_tokens FOR INSERT
  WITH CHECK (auth.uid() = user_id);

-- Users can update their own tokens (e.g. platform change).
CREATE POLICY "device_tokens_update_own"
  ON public.device_tokens FOR UPDATE
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

-- Users can delete their own tokens (e.g. on logout).
CREATE POLICY "device_tokens_delete_own"
  ON public.device_tokens FOR DELETE
  USING (auth.uid() = user_id);


-- =============================================================================
-- ROLLBACK
-- =============================================================================

-- BEGIN;
--
-- DROP POLICY IF EXISTS "device_tokens_select_own" ON public.device_tokens;
-- DROP POLICY IF EXISTS "device_tokens_insert_own" ON public.device_tokens;
-- DROP POLICY IF EXISTS "device_tokens_update_own" ON public.device_tokens;
-- DROP POLICY IF EXISTS "device_tokens_delete_own" ON public.device_tokens;
-- DROP TRIGGER IF EXISTS trg_device_tokens_updated_at ON public.device_tokens;
-- DROP INDEX  IF EXISTS public.idx_device_tokens_user_id;
-- DROP TABLE  IF EXISTS public.device_tokens CASCADE;
--
-- COMMIT;


-- =============================================================================
-- END OF MIGRATION 003
-- =============================================================================
