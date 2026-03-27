-- =============================================================================
-- Migration 016: Jogging pause metrics + segments
-- =============================================================================

ALTER TABLE public.jogging_sessions
    ADD COLUMN IF NOT EXISTS active_duration_seconds INTEGER NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS pause_duration_seconds  INTEGER NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS active_distance_meters  REAL    NOT NULL DEFAULT 0.0,
    ADD COLUMN IF NOT EXISTS pause_distance_meters   REAL    NOT NULL DEFAULT 0.0,
    ADD COLUMN IF NOT EXISTS pause_count             INTEGER NOT NULL DEFAULT 0;

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

CREATE INDEX IF NOT EXISTS idx_jogging_segments_session_id
    ON public.jogging_segments(session_id);
CREATE INDEX IF NOT EXISTS idx_jogging_segments_started_at
    ON public.jogging_segments(session_id, started_at);

ALTER TABLE public.jogging_segments ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename = 'jogging_segments'
          AND policyname = 'Users can view own jogging segments'
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

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename = 'jogging_segments'
          AND policyname = 'Users can insert own jogging segments'
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

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename = 'jogging_segments'
          AND policyname = 'Users can delete own jogging segments'
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
