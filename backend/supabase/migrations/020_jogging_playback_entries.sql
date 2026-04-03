-- =============================================================================
-- Migration 020: Jogging playback timeline entries
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.jogging_playback_entries (
    id                            UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id                    UUID        NOT NULL REFERENCES public.jogging_sessions(id) ON DELETE CASCADE,
    source                        TEXT        NOT NULL,
    track_title                   TEXT        NOT NULL,
    artist_name                   TEXT,
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

CREATE INDEX IF NOT EXISTS idx_jogging_playback_entries_session_id
    ON public.jogging_playback_entries(session_id);

CREATE INDEX IF NOT EXISTS idx_jogging_playback_entries_started_at
    ON public.jogging_playback_entries(session_id, started_at);

ALTER TABLE public.jogging_playback_entries ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename = 'jogging_playback_entries'
          AND policyname = 'Users can view own jogging playback entries'
    ) THEN
        CREATE POLICY "Users can view own jogging playback entries"
            ON public.jogging_playback_entries FOR SELECT
            USING (
                EXISTS (
                    SELECT 1
                    FROM public.jogging_sessions js
                    WHERE js.id = jogging_playback_entries.session_id
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
          AND tablename = 'jogging_playback_entries'
          AND policyname = 'Users can insert own jogging playback entries'
    ) THEN
        CREATE POLICY "Users can insert own jogging playback entries"
            ON public.jogging_playback_entries FOR INSERT
            WITH CHECK (
                EXISTS (
                    SELECT 1
                    FROM public.jogging_sessions js
                    WHERE js.id = jogging_playback_entries.session_id
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
          AND tablename = 'jogging_playback_entries'
          AND policyname = 'Users can delete own jogging playback entries'
    ) THEN
        CREATE POLICY "Users can delete own jogging playback entries"
            ON public.jogging_playback_entries FOR DELETE
            USING (
                EXISTS (
                    SELECT 1
                    FROM public.jogging_sessions js
                    WHERE js.id = jogging_playback_entries.session_id
                      AND js.user_id = auth.uid()
                )
            );
    END IF;
END $$;
