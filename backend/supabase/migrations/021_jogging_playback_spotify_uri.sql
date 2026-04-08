-- =============================================================================
-- Migration 021: Persist Spotify track URI on jogging playback entries
-- =============================================================================

ALTER TABLE public.jogging_playback_entries
    ADD COLUMN IF NOT EXISTS spotify_track_uri TEXT;
