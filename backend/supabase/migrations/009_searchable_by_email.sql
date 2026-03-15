-- =============================================================================
-- Migration: 009_searchable_by_email.sql
-- Description: Adds searchable_by_email flag to user_settings.
--              When TRUE, other authenticated users can find this account by
--              searching for its email address. Defaults to FALSE (private).
--
--              This is part of the three-layer identity model:
--                username     — unique handle, always searchable
--                display_name — free-form name, always searchable
--                email        — private by default, opt-in searchable
--
-- Created: 2026-03-15
-- Depends on: 001_initial_schema.sql (public.user_settings)
-- =============================================================================
--
-- HOW TO RUN:
--   Supabase Dashboard SQL Editor — paste and Run.
--   psql: psql "$DATABASE_URL" -f backend/supabase/migrations/009_searchable_by_email.sql
--
-- HOW TO ROLL BACK:
--   ALTER TABLE public.user_settings DROP COLUMN IF EXISTS searchable_by_email;
-- =============================================================================

ALTER TABLE public.user_settings
  ADD COLUMN IF NOT EXISTS searchable_by_email BOOLEAN NOT NULL DEFAULT FALSE;

COMMENT ON COLUMN public.user_settings.searchable_by_email IS
  'When TRUE, other authenticated users can find this account by email address. '
  'Default FALSE (email is private).';

-- =============================================================================
-- END OF MIGRATION 009
-- =============================================================================
