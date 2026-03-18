-- =============================================================================
-- Migration 015: Jogging Sessions & Route Points
--
-- Adds tables for GPS-tracked jogging workouts:
--   - jogging_sessions: one row per jogging workout (start/end, distance, pace, etc.)
--   - route_points: GPS breadcrumbs recorded during a jogging session
--
-- Design decisions:
--   - jogging_sessions is separate from workout_sessions because the data model
--     is fundamentally different (distance/pace vs. reps/quality).
--   - route_points stores individual GPS coordinates with timestamps so the
--     route can be reconstructed on a map.
--   - Altitude is stored for future elevation gain/loss calculations.
--   - horizontal_accuracy allows the client to filter out low-quality GPS fixes.
--   - earned_time_credits follows the same pattern as workout_sessions for
--     consistency with the screen-time credit system.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- jogging_sessions
-- ---------------------------------------------------------------------------

CREATE TABLE public.jogging_sessions (
    id                   UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id              UUID        NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    started_at           TIMESTAMPTZ NOT NULL,
    ended_at             TIMESTAMPTZ,
    distance_meters      REAL        NOT NULL DEFAULT 0.0,
    duration_seconds     INTEGER     NOT NULL DEFAULT 0,
    avg_pace_seconds_per_km INTEGER,
    calories_burned      INTEGER     NOT NULL DEFAULT 0,
    earned_time_credits  INTEGER     NOT NULL DEFAULT 0,
    created_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at           TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_jogging_sessions_user_id    ON public.jogging_sessions(user_id);
CREATE INDEX idx_jogging_sessions_started_at ON public.jogging_sessions(started_at);

-- RLS policies
ALTER TABLE public.jogging_sessions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own jogging sessions"
    ON public.jogging_sessions FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own jogging sessions"
    ON public.jogging_sessions FOR INSERT
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own jogging sessions"
    ON public.jogging_sessions FOR UPDATE
    USING (auth.uid() = user_id);

CREATE POLICY "Users can delete own jogging sessions"
    ON public.jogging_sessions FOR DELETE
    USING (auth.uid() = user_id);

-- ---------------------------------------------------------------------------
-- route_points
-- ---------------------------------------------------------------------------

CREATE TABLE public.route_points (
    id                   UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id           UUID        NOT NULL REFERENCES public.jogging_sessions(id) ON DELETE CASCADE,
    timestamp            TIMESTAMPTZ NOT NULL,
    latitude             DOUBLE PRECISION NOT NULL,
    longitude            DOUBLE PRECISION NOT NULL,
    altitude             REAL,
    speed                REAL,
    horizontal_accuracy  REAL,
    distance_from_start  REAL        NOT NULL DEFAULT 0.0,
    created_at           TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_route_points_session_id ON public.route_points(session_id);
CREATE INDEX idx_route_points_timestamp  ON public.route_points(session_id, timestamp);

-- RLS policies (inherit access from parent jogging_sessions via session_id)
ALTER TABLE public.route_points ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own route points"
    ON public.route_points FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM public.jogging_sessions js
            WHERE js.id = route_points.session_id
              AND js.user_id = auth.uid()
        )
    );

CREATE POLICY "Users can insert own route points"
    ON public.route_points FOR INSERT
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM public.jogging_sessions js
            WHERE js.id = route_points.session_id
              AND js.user_id = auth.uid()
        )
    );

CREATE POLICY "Users can delete own route points"
    ON public.route_points FOR DELETE
    USING (
        EXISTS (
            SELECT 1 FROM public.jogging_sessions js
            WHERE js.id = route_points.session_id
              AND js.user_id = auth.uid()
        )
    );
