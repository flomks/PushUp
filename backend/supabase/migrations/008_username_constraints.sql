-- =============================================================================
-- Migration: 008_username_constraints.sql
-- Description: Adds a CHECK constraint to enforce username format rules:
--              - 3 to 20 characters
--              - Only lowercase letters (a-z), digits (0-9), and underscores (_)
--              These rules mirror the client-side validation in SafeAuthBridge
--              and the server-side validation in UsernameRoutes.
-- Created: 2026-03-13
-- Depends on: 005_add_username.sql (public.users.username column)
-- =============================================================================

-- Add a CHECK constraint to enforce username format.
-- The constraint is named so it can be dropped/modified in a future migration.
ALTER TABLE public.users
  ADD CONSTRAINT users_username_format
  CHECK (
    username IS NULL OR (
      length(username) >= 3
      AND length(username) <= 20
      AND username ~ '^[a-z0-9_]+$'
    )
  );

COMMENT ON CONSTRAINT users_username_format ON public.users IS
  'Enforces username format: 3-20 chars, lowercase letters/digits/underscores only.';


-- =============================================================================
-- ROLLBACK
-- =============================================================================

-- ALTER TABLE public.users DROP CONSTRAINT IF EXISTS users_username_format;
