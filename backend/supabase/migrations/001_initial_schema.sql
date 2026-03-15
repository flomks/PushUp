-- =============================================================================
-- Migration: 001_initial_schema.sql
-- Description: Initial PostgreSQL schema for PushUp App.
--              Creates users, workout_sessions, push_up_records, time_credits,
--              user_settings tables with RLS, triggers, and the auth trigger.
-- Created: 2026-03-03
-- NOTE: For a fresh install, prefer 000_master_schema.sql which applies the
--       complete up-to-date schema in one shot.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- EXTENSIONS
-- -----------------------------------------------------------------------------

-- gen_random_uuid() is available by default in Supabase (pgcrypto is enabled)


-- =============================================================================
-- TABLES
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Table: users
-- Mirrors Supabase Auth users. Populated via trigger on auth.users insert.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.users (
  id           UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  email        TEXT        UNIQUE NOT NULL,
  display_name TEXT,
  avatar_url   TEXT,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE  public.users              IS 'App user profiles, linked to Supabase Auth.';
COMMENT ON COLUMN public.users.id           IS 'UUID matching auth.users.id.';
COMMENT ON COLUMN public.users.email        IS 'User email address (unique).';
COMMENT ON COLUMN public.users.display_name IS 'Optional display name chosen by the user.';
COMMENT ON COLUMN public.users.avatar_url   IS 'URL to the user avatar stored in Supabase Storage.';


-- -----------------------------------------------------------------------------
-- Table: workout_sessions
-- One row per workout session started by a user.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.workout_sessions (
  id                   UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id              UUID        NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  started_at           TIMESTAMPTZ NOT NULL,
  ended_at             TIMESTAMPTZ,
  push_up_count        INTEGER     NOT NULL DEFAULT 0,
  earned_time_credits  INTEGER     NOT NULL DEFAULT 0,
  quality              REAL        NOT NULL DEFAULT 0.0,
  created_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at           TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_workout_sessions_user_id
  ON public.workout_sessions(user_id);

CREATE INDEX IF NOT EXISTS idx_workout_sessions_started_at
  ON public.workout_sessions(started_at DESC);

COMMENT ON TABLE  public.workout_sessions                    IS 'Individual workout sessions per user.';
COMMENT ON COLUMN public.workout_sessions.user_id            IS 'FK to users.id.';
COMMENT ON COLUMN public.workout_sessions.started_at         IS 'Timestamp when the workout was started.';
COMMENT ON COLUMN public.workout_sessions.ended_at           IS 'Timestamp when the workout was finished. NULL = still running.';
COMMENT ON COLUMN public.workout_sessions.push_up_count      IS 'Total push-ups counted in this session.';
COMMENT ON COLUMN public.workout_sessions.earned_time_credits IS 'Screen-time credits earned (in seconds).';
COMMENT ON COLUMN public.workout_sessions.quality            IS 'Average form quality score (0.0 - 1.0).';


-- -----------------------------------------------------------------------------
-- Table: push_up_records
-- One row per individual push-up detected within a session.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.push_up_records (
  id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id  UUID        NOT NULL REFERENCES public.workout_sessions(id) ON DELETE CASCADE,
  timestamp   TIMESTAMPTZ NOT NULL,
  duration_ms INTEGER,
  depth_score REAL,
  form_score  REAL,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_push_up_records_session_id
  ON public.push_up_records(session_id);

COMMENT ON TABLE  public.push_up_records             IS 'Individual push-up events within a workout session.';
COMMENT ON COLUMN public.push_up_records.session_id  IS 'FK to workout_sessions.id.';
COMMENT ON COLUMN public.push_up_records.timestamp   IS 'Exact timestamp of the push-up detection.';
COMMENT ON COLUMN public.push_up_records.duration_ms IS 'Duration of the push-up movement in milliseconds.';
COMMENT ON COLUMN public.push_up_records.depth_score IS 'How deep the push-up was (0.0 - 1.0).';
COMMENT ON COLUMN public.push_up_records.form_score  IS 'Form quality score (0.0 - 1.0).';


-- -----------------------------------------------------------------------------
-- Table: time_credits
-- One row per user (UNIQUE on user_id). Running totals of earned/spent credits.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.time_credits (
  id                   UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id              UUID        NOT NULL UNIQUE REFERENCES public.users(id) ON DELETE CASCADE,
  total_earned_seconds BIGINT      NOT NULL DEFAULT 0,
  total_spent_seconds  BIGINT      NOT NULL DEFAULT 0,
  updated_at           TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_time_credits_user_id
  ON public.time_credits(user_id);

COMMENT ON TABLE  public.time_credits                      IS 'Accumulated screen-time credits per user.';
COMMENT ON COLUMN public.time_credits.user_id              IS 'FK to users.id (one record per user).';
COMMENT ON COLUMN public.time_credits.total_earned_seconds IS 'Total seconds earned through workouts (ever).';
COMMENT ON COLUMN public.time_credits.total_spent_seconds  IS 'Total seconds spent as screen-time (ever).';


-- -----------------------------------------------------------------------------
-- Table: user_settings
-- One row per user (UNIQUE on user_id). Configurable workout parameters.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.user_settings (
  id                          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id                     UUID        NOT NULL UNIQUE REFERENCES public.users(id) ON DELETE CASCADE,
  push_ups_per_minute_credit  INTEGER     NOT NULL DEFAULT 10,
  quality_multiplier_enabled  BOOLEAN     NOT NULL DEFAULT FALSE,
  daily_credit_cap_seconds    BIGINT,
  created_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE  public.user_settings                              IS 'Per-user configuration for the workout credit system.';
COMMENT ON COLUMN public.user_settings.user_id                     IS 'FK to users.id (one record per user).';
COMMENT ON COLUMN public.user_settings.push_ups_per_minute_credit  IS 'How many push-ups earn 1 minute of screen-time (default 10).';
COMMENT ON COLUMN public.user_settings.quality_multiplier_enabled  IS 'Whether form quality affects the credit multiplier.';
COMMENT ON COLUMN public.user_settings.daily_credit_cap_seconds    IS 'Optional daily cap on earned credits in seconds. NULL = no cap.';


-- =============================================================================
-- HELPER FUNCTION: updated_at auto-update trigger
-- =============================================================================

CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;

-- Attach trigger to every table that has an updated_at column
CREATE TRIGGER trg_users_updated_at
  BEFORE UPDATE ON public.users
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE TRIGGER trg_workout_sessions_updated_at
  BEFORE UPDATE ON public.workout_sessions
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE TRIGGER trg_time_credits_updated_at
  BEFORE UPDATE ON public.time_credits
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE TRIGGER trg_user_settings_updated_at
  BEFORE UPDATE ON public.user_settings
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


-- =============================================================================
-- AUTH INTEGRATION: auto-create user profile on sign-up
-- =============================================================================

-- When a new user signs up via Supabase Auth, automatically upsert a row in
-- public.users and copy display_name / avatar_url from the OAuth provider
-- metadata (Google: raw_user_meta_data->>'full_name', Apple: 'full_name').
-- Falls back to the email local-part when no name is available.
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
  -- Resolve display_name from OAuth provider metadata.
  -- Priority: full_name (Google/Apple) -> name -> email local-part fallback.
  -- NULLIF(..., '') treats empty strings the same as NULL.
  v_display_name := COALESCE(
    NULLIF(TRIM(NEW.raw_user_meta_data->>'full_name'), ''),
    NULLIF(TRIM(NEW.raw_user_meta_data->>'name'),      ''),
    SPLIT_PART(NEW.email, '@', 1)
  );

  v_avatar_url := NULLIF(TRIM(NEW.raw_user_meta_data->>'avatar_url'), '');

  -- Upsert the user profile row.
  -- ON CONFLICT DO UPDATE so re-running (e.g. on next login) keeps data fresh.
  -- Only overwrites display_name / avatar_url when the new value is non-NULL,
  -- so a user who manually updated their name is not overwritten by the provider.
  INSERT INTO public.users (id, email, display_name, avatar_url, created_at, updated_at)
  VALUES (
    NEW.id,
    NEW.email,
    v_display_name,
    v_avatar_url,
    NOW(),
    NOW()
  )
  ON CONFLICT (id) DO UPDATE SET
    email        = EXCLUDED.email,
    display_name = COALESCE(EXCLUDED.display_name, public.users.display_name),
    avatar_url   = COALESCE(EXCLUDED.avatar_url,   public.users.avatar_url),
    updated_at   = NOW();

  -- Ensure companion rows exist (idempotent).
  INSERT INTO public.time_credits (user_id)
  VALUES (NEW.id)
  ON CONFLICT (user_id) DO NOTHING;

  INSERT INTO public.user_settings (user_id)
  VALUES (NEW.id)
  ON CONFLICT (user_id) DO NOTHING;

  -- user_levels row is created by migration 007_user_levels.sql once that
  -- table exists. The 000_master_schema.sql handles this in one shot.

  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_auth_user();


-- =============================================================================
-- ROW LEVEL SECURITY (RLS)
-- =============================================================================

-- Enable RLS on all tables
ALTER TABLE public.users          ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.workout_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.push_up_records  ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.time_credits     ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_settings    ENABLE ROW LEVEL SECURITY;


-- -----------------------------------------------------------------------------
-- RLS Policies: users
-- -----------------------------------------------------------------------------

-- Users can read their own profile
CREATE POLICY "users_select_own"
  ON public.users
  FOR SELECT
  USING (auth.uid() = id);

-- Users can update their own profile (email is managed by Supabase Auth)
CREATE POLICY "users_update_own"
  ON public.users
  FOR UPDATE
  USING (auth.uid() = id)
  WITH CHECK (auth.uid() = id);

-- Insert is handled by the trigger (SECURITY DEFINER), not by the user directly.
-- If you want to allow direct insert (e.g. for testing), add:
-- CREATE POLICY "users_insert_own" ON public.users FOR INSERT WITH CHECK (auth.uid() = id);


-- -----------------------------------------------------------------------------
-- RLS Policies: workout_sessions
-- -----------------------------------------------------------------------------

CREATE POLICY "workout_sessions_select_own"
  ON public.workout_sessions
  FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "workout_sessions_insert_own"
  ON public.workout_sessions
  FOR INSERT
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "workout_sessions_update_own"
  ON public.workout_sessions
  FOR UPDATE
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "workout_sessions_delete_own"
  ON public.workout_sessions
  FOR DELETE
  USING (auth.uid() = user_id);


-- -----------------------------------------------------------------------------
-- RLS Policies: push_up_records
-- Users access push_up_records through their workout_sessions.
-- -----------------------------------------------------------------------------

CREATE POLICY "push_up_records_select_own"
  ON public.push_up_records
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.workout_sessions ws
      WHERE ws.id = push_up_records.session_id
        AND ws.user_id = auth.uid()
    )
  );

CREATE POLICY "push_up_records_insert_own"
  ON public.push_up_records
  FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.workout_sessions ws
      WHERE ws.id = push_up_records.session_id
        AND ws.user_id = auth.uid()
    )
  );

CREATE POLICY "push_up_records_update_own"
  ON public.push_up_records
  FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM public.workout_sessions ws
      WHERE ws.id = push_up_records.session_id
        AND ws.user_id = auth.uid()
    )
  );

CREATE POLICY "push_up_records_delete_own"
  ON public.push_up_records
  FOR DELETE
  USING (
    EXISTS (
      SELECT 1 FROM public.workout_sessions ws
      WHERE ws.id = push_up_records.session_id
        AND ws.user_id = auth.uid()
    )
  );


-- -----------------------------------------------------------------------------
-- RLS Policies: time_credits
-- -----------------------------------------------------------------------------

CREATE POLICY "time_credits_select_own"
  ON public.time_credits
  FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "time_credits_insert_own"
  ON public.time_credits
  FOR INSERT
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "time_credits_update_own"
  ON public.time_credits
  FOR UPDATE
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);


-- -----------------------------------------------------------------------------
-- RLS Policies: user_settings
-- -----------------------------------------------------------------------------

CREATE POLICY "user_settings_select_own"
  ON public.user_settings
  FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "user_settings_insert_own"
  ON public.user_settings
  FOR INSERT
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "user_settings_update_own"
  ON public.user_settings
  FOR UPDATE
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);


-- =============================================================================
-- END OF MIGRATION 001
-- =============================================================================
