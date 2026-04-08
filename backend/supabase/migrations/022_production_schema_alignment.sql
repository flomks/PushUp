-- =============================================================================
-- Migration: 022_production_schema_alignment.sql
-- Description: Aligns Supabase with the current production schema expected by
--              the app for jogging sync and XP sync.
--
-- WHY THIS EXISTS
--   During active development, some projects were created from an older subset
--   of migrations. The app now expects:
--   - jogging_sessions with created_at / updated_at defaults, pause metrics,
--     and optional live_run_session_id
--   - jogging_segments and jogging_playback_entries tables
--   - user_levels and exercise_levels tables with triggers + RLS
--
--   This migration makes an existing dev/prod Supabase project match the
--   current expected schema without relying on client-side compatibility code.
--
-- SAFE TO RUN
--   All statements are idempotent (`IF NOT EXISTS`, guarded policies, or
--   `ALTER COLUMN ... SET DEFAULT`).
-- =============================================================================

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- -----------------------------------------------------------------------------
-- Shared helper
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;

-- -----------------------------------------------------------------------------
-- user_levels
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.user_levels (
  id         UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    UUID        NOT NULL UNIQUE REFERENCES public.users(id) ON DELETE CASCADE,
  total_xp   BIGINT      NOT NULL DEFAULT 0,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.user_levels
  ALTER COLUMN id SET DEFAULT gen_random_uuid(),
  ALTER COLUMN total_xp SET DEFAULT 0,
  ALTER COLUMN updated_at SET DEFAULT NOW();

CREATE INDEX IF NOT EXISTS idx_user_levels_user_id
  ON public.user_levels(user_id);

ALTER TABLE public.user_levels ENABLE ROW LEVEL SECURITY;

DROP TRIGGER IF EXISTS trg_user_levels_updated_at ON public.user_levels;
CREATE TRIGGER trg_user_levels_updated_at
  BEFORE UPDATE ON public.user_levels
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'user_levels' AND policyname = 'user_levels_select_own'
  ) THEN
    CREATE POLICY "user_levels_select_own"
      ON public.user_levels FOR SELECT
      USING (auth.uid() = user_id);
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'user_levels' AND policyname = 'user_levels_insert_own'
  ) THEN
    CREATE POLICY "user_levels_insert_own"
      ON public.user_levels FOR INSERT
      WITH CHECK (auth.uid() = user_id);
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'user_levels' AND policyname = 'user_levels_update_own'
  ) THEN
    CREATE POLICY "user_levels_update_own"
      ON public.user_levels FOR UPDATE
      USING (auth.uid() = user_id)
      WITH CHECK (auth.uid() = user_id);
  END IF;
END $$;

-- -----------------------------------------------------------------------------
-- exercise_levels
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.exercise_levels (
  id            UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id       UUID        NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  exercise_type TEXT        NOT NULL,
  total_xp      BIGINT      NOT NULL DEFAULT 0,
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (user_id, exercise_type)
);

ALTER TABLE public.exercise_levels
  ALTER COLUMN id SET DEFAULT gen_random_uuid(),
  ALTER COLUMN total_xp SET DEFAULT 0,
  ALTER COLUMN updated_at SET DEFAULT NOW();

CREATE INDEX IF NOT EXISTS idx_exercise_levels_user_id
  ON public.exercise_levels(user_id);

ALTER TABLE public.exercise_levels ENABLE ROW LEVEL SECURITY;

DROP TRIGGER IF EXISTS trg_exercise_levels_updated_at ON public.exercise_levels;
CREATE TRIGGER trg_exercise_levels_updated_at
  BEFORE UPDATE ON public.exercise_levels
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'exercise_levels' AND policyname = 'exercise_levels_select_own'
  ) THEN
    CREATE POLICY "exercise_levels_select_own"
      ON public.exercise_levels FOR SELECT
      USING (auth.uid() = user_id);
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'exercise_levels' AND policyname = 'exercise_levels_insert_own'
  ) THEN
    CREATE POLICY "exercise_levels_insert_own"
      ON public.exercise_levels FOR INSERT
      WITH CHECK (auth.uid() = user_id);
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'exercise_levels' AND policyname = 'exercise_levels_update_own'
  ) THEN
    CREATE POLICY "exercise_levels_update_own"
      ON public.exercise_levels FOR UPDATE
      USING (auth.uid() = user_id)
      WITH CHECK (auth.uid() = user_id);
  END IF;
END $$;

-- -----------------------------------------------------------------------------
-- jogging_sessions
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.jogging_sessions (
  id                         UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id                    UUID        NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  started_at                 TIMESTAMPTZ NOT NULL,
  ended_at                   TIMESTAMPTZ,
  distance_meters            REAL        NOT NULL DEFAULT 0.0,
  duration_seconds           INTEGER     NOT NULL DEFAULT 0,
  avg_pace_seconds_per_km    INTEGER,
  calories_burned            INTEGER     NOT NULL DEFAULT 0,
  earned_time_credits        INTEGER     NOT NULL DEFAULT 0,
  created_at                 TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at                 TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.jogging_sessions
  ADD COLUMN IF NOT EXISTS active_duration_seconds INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS pause_duration_seconds  INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS active_distance_meters  REAL    NOT NULL DEFAULT 0.0,
  ADD COLUMN IF NOT EXISTS pause_distance_meters   REAL    NOT NULL DEFAULT 0.0,
  ADD COLUMN IF NOT EXISTS pause_count             INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS live_run_session_id     UUID REFERENCES public.live_run_sessions(id) ON DELETE SET NULL;

ALTER TABLE public.jogging_sessions
  ALTER COLUMN id SET DEFAULT gen_random_uuid(),
  ALTER COLUMN distance_meters SET DEFAULT 0.0,
  ALTER COLUMN duration_seconds SET DEFAULT 0,
  ALTER COLUMN calories_burned SET DEFAULT 0,
  ALTER COLUMN earned_time_credits SET DEFAULT 0,
  ALTER COLUMN created_at SET DEFAULT NOW(),
  ALTER COLUMN updated_at SET DEFAULT NOW(),
  ALTER COLUMN active_duration_seconds SET DEFAULT 0,
  ALTER COLUMN pause_duration_seconds SET DEFAULT 0,
  ALTER COLUMN active_distance_meters SET DEFAULT 0.0,
  ALTER COLUMN pause_distance_meters SET DEFAULT 0.0,
  ALTER COLUMN pause_count SET DEFAULT 0;

CREATE INDEX IF NOT EXISTS idx_jogging_sessions_user_id
  ON public.jogging_sessions(user_id);
CREATE INDEX IF NOT EXISTS idx_jogging_sessions_started_at
  ON public.jogging_sessions(started_at);
CREATE INDEX IF NOT EXISTS idx_jogging_sessions_live_run_session_id
  ON public.jogging_sessions(live_run_session_id);

ALTER TABLE public.jogging_sessions ENABLE ROW LEVEL SECURITY;

DROP TRIGGER IF EXISTS trg_jogging_sessions_updated_at ON public.jogging_sessions;
CREATE TRIGGER trg_jogging_sessions_updated_at
  BEFORE UPDATE ON public.jogging_sessions
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'jogging_sessions' AND policyname = 'Users can view own jogging sessions'
  ) THEN
    CREATE POLICY "Users can view own jogging sessions"
      ON public.jogging_sessions FOR SELECT
      USING (auth.uid() = user_id);
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'jogging_sessions' AND policyname = 'Users can insert own jogging sessions'
  ) THEN
    CREATE POLICY "Users can insert own jogging sessions"
      ON public.jogging_sessions FOR INSERT
      WITH CHECK (auth.uid() = user_id);
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'jogging_sessions' AND policyname = 'Users can update own jogging sessions'
  ) THEN
    CREATE POLICY "Users can update own jogging sessions"
      ON public.jogging_sessions FOR UPDATE
      USING (auth.uid() = user_id)
      WITH CHECK (auth.uid() = user_id);
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'jogging_sessions' AND policyname = 'Users can delete own jogging sessions'
  ) THEN
    CREATE POLICY "Users can delete own jogging sessions"
      ON public.jogging_sessions FOR DELETE
      USING (auth.uid() = user_id);
  END IF;
END $$;

-- -----------------------------------------------------------------------------
-- route_points
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.route_points (
  id                   UUID             PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id           UUID             NOT NULL REFERENCES public.jogging_sessions(id) ON DELETE CASCADE,
  timestamp            TIMESTAMPTZ      NOT NULL,
  latitude             DOUBLE PRECISION NOT NULL,
  longitude            DOUBLE PRECISION NOT NULL,
  altitude             REAL,
  speed                REAL,
  horizontal_accuracy  REAL,
  distance_from_start  REAL             NOT NULL DEFAULT 0.0,
  created_at           TIMESTAMPTZ      NOT NULL DEFAULT NOW()
);

ALTER TABLE public.route_points
  ALTER COLUMN id SET DEFAULT gen_random_uuid(),
  ALTER COLUMN distance_from_start SET DEFAULT 0.0,
  ALTER COLUMN created_at SET DEFAULT NOW();

CREATE INDEX IF NOT EXISTS idx_route_points_session_id
  ON public.route_points(session_id);
CREATE INDEX IF NOT EXISTS idx_route_points_timestamp
  ON public.route_points(session_id, timestamp);

ALTER TABLE public.route_points ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'route_points' AND policyname = 'Users can view own route points'
  ) THEN
    CREATE POLICY "Users can view own route points"
      ON public.route_points FOR SELECT
      USING (
        EXISTS (
          SELECT 1 FROM public.jogging_sessions js
          WHERE js.id = route_points.session_id
            AND js.user_id = auth.uid()
        )
      );
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'route_points' AND policyname = 'Users can insert own route points'
  ) THEN
    CREATE POLICY "Users can insert own route points"
      ON public.route_points FOR INSERT
      WITH CHECK (
        EXISTS (
          SELECT 1 FROM public.jogging_sessions js
          WHERE js.id = route_points.session_id
            AND js.user_id = auth.uid()
        )
      );
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'route_points' AND policyname = 'Users can delete own route points'
  ) THEN
    CREATE POLICY "Users can delete own route points"
      ON public.route_points FOR DELETE
      USING (
        EXISTS (
          SELECT 1 FROM public.jogging_sessions js
          WHERE js.id = route_points.session_id
            AND js.user_id = auth.uid()
        )
      );
  END IF;
END $$;

-- -----------------------------------------------------------------------------
-- jogging_segments
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.jogging_segments (
  id                UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id        UUID        NOT NULL REFERENCES public.jogging_sessions(id) ON DELETE CASCADE,
  segment_type      TEXT        NOT NULL CHECK (segment_type IN ('run', 'pause')),
  started_at        TIMESTAMPTZ NOT NULL,
  ended_at          TIMESTAMPTZ,
  distance_meters   REAL        NOT NULL DEFAULT 0.0,
  duration_seconds  INTEGER     NOT NULL DEFAULT 0,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.jogging_segments
  ALTER COLUMN id SET DEFAULT gen_random_uuid(),
  ALTER COLUMN distance_meters SET DEFAULT 0.0,
  ALTER COLUMN duration_seconds SET DEFAULT 0,
  ALTER COLUMN created_at SET DEFAULT NOW();

CREATE INDEX IF NOT EXISTS idx_jogging_segments_session_id
  ON public.jogging_segments(session_id);
CREATE INDEX IF NOT EXISTS idx_jogging_segments_started_at
  ON public.jogging_segments(session_id, started_at);

ALTER TABLE public.jogging_segments ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'jogging_segments' AND policyname = 'Users can view own jogging segments'
  ) THEN
    CREATE POLICY "Users can view own jogging segments"
      ON public.jogging_segments FOR SELECT
      USING (
        EXISTS (
          SELECT 1 FROM public.jogging_sessions js
          WHERE js.id = jogging_segments.session_id
            AND js.user_id = auth.uid()
        )
      );
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'jogging_segments' AND policyname = 'Users can insert own jogging segments'
  ) THEN
    CREATE POLICY "Users can insert own jogging segments"
      ON public.jogging_segments FOR INSERT
      WITH CHECK (
        EXISTS (
          SELECT 1 FROM public.jogging_sessions js
          WHERE js.id = jogging_segments.session_id
            AND js.user_id = auth.uid()
        )
      );
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'jogging_segments' AND policyname = 'Users can delete own jogging segments'
  ) THEN
    CREATE POLICY "Users can delete own jogging segments"
      ON public.jogging_segments FOR DELETE
      USING (
        EXISTS (
          SELECT 1 FROM public.jogging_sessions js
          WHERE js.id = jogging_segments.session_id
            AND js.user_id = auth.uid()
        )
      );
  END IF;
END $$;

-- -----------------------------------------------------------------------------
-- jogging_playback_entries
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.jogging_playback_entries (
  id                            UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id                    UUID        NOT NULL REFERENCES public.jogging_sessions(id) ON DELETE CASCADE,
  source                        TEXT        NOT NULL,
  track_title                   TEXT        NOT NULL,
  artist_name                   TEXT,
  spotify_track_uri             TEXT,
  started_at                    TIMESTAMPTZ NOT NULL,
  ended_at                      TIMESTAMPTZ NOT NULL,
  start_distance_meters         REAL        NOT NULL DEFAULT 0.0,
  end_distance_meters           REAL        NOT NULL DEFAULT 0.0,
  start_active_duration_seconds INTEGER     NOT NULL DEFAULT 0,
  end_active_duration_seconds   INTEGER     NOT NULL DEFAULT 0,
  created_at                    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT jogging_playback_entries_time_window CHECK (ended_at >= started_at),
  CONSTRAINT jogging_playback_entries_distance_window CHECK (
    start_distance_meters >= 0.0
    AND end_distance_meters >= 0.0
    AND end_distance_meters >= start_distance_meters
  ),
  CONSTRAINT jogging_playback_entries_duration_window CHECK (
    start_active_duration_seconds >= 0
    AND end_active_duration_seconds >= 0
    AND end_active_duration_seconds >= start_active_duration_seconds
  )
);

ALTER TABLE public.jogging_playback_entries
  ALTER COLUMN id SET DEFAULT gen_random_uuid(),
  ALTER COLUMN start_distance_meters SET DEFAULT 0.0,
  ALTER COLUMN end_distance_meters SET DEFAULT 0.0,
  ALTER COLUMN start_active_duration_seconds SET DEFAULT 0,
  ALTER COLUMN end_active_duration_seconds SET DEFAULT 0,
  ALTER COLUMN created_at SET DEFAULT NOW();

CREATE INDEX IF NOT EXISTS idx_jogging_playback_entries_session_id
  ON public.jogging_playback_entries(session_id);
CREATE INDEX IF NOT EXISTS idx_jogging_playback_entries_started_at
  ON public.jogging_playback_entries(session_id, started_at);

ALTER TABLE public.jogging_playback_entries ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'jogging_playback_entries' AND policyname = 'Users can view own jogging playback entries'
  ) THEN
    CREATE POLICY "Users can view own jogging playback entries"
      ON public.jogging_playback_entries FOR SELECT
      USING (
        EXISTS (
          SELECT 1 FROM public.jogging_sessions js
          WHERE js.id = jogging_playback_entries.session_id
            AND js.user_id = auth.uid()
        )
      );
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'jogging_playback_entries' AND policyname = 'Users can insert own jogging playback entries'
  ) THEN
    CREATE POLICY "Users can insert own jogging playback entries"
      ON public.jogging_playback_entries FOR INSERT
      WITH CHECK (
        EXISTS (
          SELECT 1 FROM public.jogging_sessions js
          WHERE js.id = jogging_playback_entries.session_id
            AND js.user_id = auth.uid()
        )
      );
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'jogging_playback_entries' AND policyname = 'Users can delete own jogging playback entries'
  ) THEN
    CREATE POLICY "Users can delete own jogging playback entries"
      ON public.jogging_playback_entries FOR DELETE
      USING (
        EXISTS (
          SELECT 1 FROM public.jogging_sessions js
          WHERE js.id = jogging_playback_entries.session_id
            AND js.user_id = auth.uid()
        )
      );
  END IF;
END $$;

COMMIT;
