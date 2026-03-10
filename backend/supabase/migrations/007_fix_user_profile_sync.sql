-- =============================================================================
-- Migration: 006_fix_user_profile_sync.sql
-- Description: Fix auth trigger to copy display_name and avatar_url from
--              OAuth provider metadata (Google, Apple) into public.users.
--              Also backfills existing rows where display_name is NULL.
--
-- Problem:
--   The original handle_new_auth_user() trigger only copied id and email into
--   public.users. display_name and avatar_url were never populated, so the
--   friend search and friend list always showed NULL names.
--
-- Fix:
--   1. Replace the trigger function to read display_name / avatar_url from
--      auth.users.raw_user_meta_data (populated by Google / Apple OAuth).
--   2. Backfill existing public.users rows where display_name IS NULL.
--
-- Created: 2026-03-10
-- Depends on: 001_initial_schema.sql, 005_add_username.sql
-- =============================================================================
--
-- HOW TO RUN:
--   Supabase Dashboard > SQL Editor > paste this file > Run
--
-- HOW TO ROLL BACK:
--   See ROLLBACK section at the bottom.
-- =============================================================================


-- =============================================================================
-- FORWARD MIGRATION
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Replace handle_new_auth_user() trigger function
--
--    Reads display_name from OAuth metadata in priority order:
--      a) raw_user_meta_data->>'full_name'  (Google, Apple)
--      b) raw_user_meta_data->>'name'       (some providers)
--      c) SPLIT_PART(email, '@', 1)         (email/password fallback)
--
--    Uses ON CONFLICT (id) DO UPDATE so re-running is safe and existing
--    rows are kept up to date when a user signs in again after a profile
--    change on the provider side.
-- -----------------------------------------------------------------------------

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
  -- NULLIF(..., '') treats empty strings the same as NULL.
  v_display_name := COALESCE(
    NULLIF(TRIM(NEW.raw_user_meta_data->>'full_name'), ''),
    NULLIF(TRIM(NEW.raw_user_meta_data->>'name'),      ''),
    SPLIT_PART(NEW.email, '@', 1)
  );

  v_avatar_url := NULLIF(TRIM(NEW.raw_user_meta_data->>'avatar_url'), '');

  -- Upsert the user profile row.
  -- On conflict (same id = same user signing in again):
  --   - Always update email (may have changed on provider side).
  --   - Only overwrite display_name / avatar_url when the new value is
  --     non-NULL, so a user who manually set their name is not overwritten
  --     by a NULL from the provider.
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

  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.handle_new_auth_user() IS
  'Upserts a public.users profile row on every auth.users insert (new sign-up '
  'or first social login). Copies display_name and avatar_url from OAuth '
  'provider metadata (raw_user_meta_data). Falls back to the email local-part '
  'when no name is available.';


-- -----------------------------------------------------------------------------
-- 2. Backfill existing users whose display_name is NULL
--
--    Joins public.users against auth.users to read the OAuth metadata that
--    was available at sign-up time but was never copied by the old trigger.
-- -----------------------------------------------------------------------------

UPDATE public.users u
SET
  display_name = COALESCE(
    NULLIF(TRIM(a.raw_user_meta_data->>'full_name'), ''),
    NULLIF(TRIM(a.raw_user_meta_data->>'name'),      ''),
    SPLIT_PART(a.email, '@', 1)
  ),
  avatar_url   = COALESCE(
    NULLIF(TRIM(a.raw_user_meta_data->>'avatar_url'), ''),
    u.avatar_url
  ),
  updated_at   = NOW()
FROM auth.users a
WHERE a.id = u.id
  AND u.display_name IS NULL;


-- =============================================================================
-- ROLLBACK
-- Reverts to the original trigger (no display_name / avatar_url copying).
-- Does NOT undo the backfill UPDATE (data changes are not reversible here).
-- =============================================================================

-- CREATE OR REPLACE FUNCTION public.handle_new_auth_user()
-- RETURNS TRIGGER
-- LANGUAGE plpgsql
-- SECURITY DEFINER
-- SET search_path = public
-- AS $$
-- BEGIN
--   INSERT INTO public.users (id, email, created_at, updated_at)
--   VALUES (NEW.id, NEW.email, NOW(), NOW())
--   ON CONFLICT (id) DO NOTHING;
--
--   INSERT INTO public.time_credits (user_id)
--   VALUES (NEW.id)
--   ON CONFLICT (user_id) DO NOTHING;
--
--   INSERT INTO public.user_settings (user_id)
--   VALUES (NEW.id)
--   ON CONFLICT (user_id) DO NOTHING;
--
--   RETURN NEW;
-- END;
-- $$;


-- =============================================================================
-- END OF MIGRATION 006
-- =============================================================================
