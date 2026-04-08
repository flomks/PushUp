-- =============================================================================
-- Migration 021: Live jogging presence
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.live_jogging_status (
    user_id               UUID        PRIMARY KEY REFERENCES public.users(id) ON DELETE CASCADE,
    session_id            UUID        NOT NULL REFERENCES public.jogging_sessions(id) ON DELETE CASCADE,
    started_at            TIMESTAMPTZ NOT NULL,
    last_latitude         DOUBLE PRECISION,
    last_longitude        DOUBLE PRECISION,
    last_distance_meters  REAL        NOT NULL DEFAULT 0.0,
    last_duration_seconds INTEGER     NOT NULL DEFAULT 0,
    last_updated_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_live_jogging_status_session_id
    ON public.live_jogging_status(session_id);

CREATE INDEX IF NOT EXISTS idx_live_jogging_status_last_updated_at
    ON public.live_jogging_status(last_updated_at DESC);

ALTER TABLE public.live_jogging_status ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename = 'live_jogging_status'
          AND policyname = 'Users can view own live jogging status'
    ) THEN
        CREATE POLICY "Users can view own live jogging status"
            ON public.live_jogging_status FOR SELECT
            USING (auth.uid() = user_id);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename = 'live_jogging_status'
          AND policyname = 'Users can upsert own live jogging status'
    ) THEN
        CREATE POLICY "Users can upsert own live jogging status"
            ON public.live_jogging_status FOR INSERT
            WITH CHECK (auth.uid() = user_id);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename = 'live_jogging_status'
          AND policyname = 'Users can update own live jogging status'
    ) THEN
        CREATE POLICY "Users can update own live jogging status"
            ON public.live_jogging_status FOR UPDATE
            USING (auth.uid() = user_id)
            WITH CHECK (auth.uid() = user_id);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename = 'live_jogging_status'
          AND policyname = 'Users can delete own live jogging status'
    ) THEN
        CREATE POLICY "Users can delete own live jogging status"
            ON public.live_jogging_status FOR DELETE
            USING (auth.uid() = user_id);
    END IF;
END $$;
