-- =============================================================================
-- Migration: 010_avatar_visibility.sql
-- Description: Adds avatar visibility control and separates custom vs OAuth
--              avatar URLs in public.users.
--
-- DESIGN
--   avatar_url        — The OAuth provider avatar URL (set automatically on
--                       sign-in from Google/Apple metadata). Never overwritten
--                       once a custom avatar has been uploaded.
--   custom_avatar_url — URL to an avatar the user explicitly uploaded to
--                       Supabase Storage. When set, this ALWAYS takes priority
--                       over avatar_url in the resolved avatar shown to others.
--   avatar_visibility — Controls who can see the avatar:
--                         'everyone' (default) — visible to all authenticated users
--                         'friends_only'       — visible only to accepted friends
--                         'nobody'             — hidden for everyone (initials shown)
--
-- The backend resolves the effective avatar URL as:
--   COALESCE(custom_avatar_url, avatar_url)  -- custom wins over OAuth
--   Then applies visibility: if the viewer is not allowed to see it, NULL is
--   returned so the client shows the initials fallback.
--
-- Created: 2026-03-15
-- Depends on: 001_initial_schema.sql (public.users)
-- =============================================================================

-- 1. Avatar visibility enum
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'avatar_visibility') THEN
    CREATE TYPE public.avatar_visibility AS ENUM (
      'everyone',      -- default: any authenticated user can see the avatar
      'friends_only',  -- only accepted friends can see the avatar
      'nobody'         -- avatar is hidden; initials are shown instead
    );
  END IF;
END; $$;

COMMENT ON TYPE public.avatar_visibility IS
  'Controls who can see a user''s avatar: everyone, friends_only, or nobody.';

-- 2. Add custom_avatar_url column (user-uploaded, takes priority over OAuth avatar)
ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS custom_avatar_url TEXT;

COMMENT ON COLUMN public.users.custom_avatar_url IS
  'URL to an avatar explicitly uploaded by the user to Supabase Storage. '
  'When set, this always takes priority over avatar_url (OAuth provider avatar).';

-- 3. Add avatar_visibility column
ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS avatar_visibility public.avatar_visibility NOT NULL DEFAULT 'everyone';

COMMENT ON COLUMN public.users.avatar_visibility IS
  'Controls who can see this user''s avatar: everyone (default), friends_only, or nobody.';

-- 4. Update handle_new_auth_user() to only set avatar_url when custom_avatar_url
--    is not already set. This prevents an OAuth re-login from overwriting a
--    custom avatar the user uploaded.
CREATE OR REPLACE FUNCTION public.handle_new_auth_user()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_display_name TEXT;
  v_avatar_url   TEXT;
BEGIN
  v_display_name := COALESCE(
    NULLIF(TRIM(NEW.raw_user_meta_data->>'full_name'), ''),
    NULLIF(TRIM(NEW.raw_user_meta_data->>'name'),      ''),
    SPLIT_PART(NEW.email, '@', 1)
  );
  v_avatar_url := NULLIF(TRIM(NEW.raw_user_meta_data->>'avatar_url'), '');

  INSERT INTO public.users (id, email, display_name, avatar_url, created_at, updated_at)
  VALUES (NEW.id, NEW.email, v_display_name, v_avatar_url, NOW(), NOW())
  ON CONFLICT (id) DO UPDATE SET
    email        = EXCLUDED.email,
    display_name = COALESCE(EXCLUDED.display_name, public.users.display_name),
    -- Only update avatar_url when the user has NOT uploaded a custom avatar.
    -- This prevents an OAuth re-login from overwriting a user-uploaded photo.
    avatar_url   = CASE
                     WHEN public.users.custom_avatar_url IS NOT NULL THEN public.users.avatar_url
                     ELSE COALESCE(EXCLUDED.avatar_url, public.users.avatar_url)
                   END,
    updated_at   = NOW();

  INSERT INTO public.time_credits  (user_id) VALUES (NEW.id) ON CONFLICT (user_id) DO NOTHING;
  INSERT INTO public.user_settings (user_id) VALUES (NEW.id) ON CONFLICT (user_id) DO NOTHING;
  INSERT INTO public.user_levels   (user_id) VALUES (NEW.id) ON CONFLICT (user_id) DO NOTHING;

  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.handle_new_auth_user() IS
  'Triggered after INSERT on auth.users. Creates companion rows and sets '
  'avatar_url from OAuth metadata only when no custom avatar has been uploaded.';

-- =============================================================================
-- ROLLBACK
-- =============================================================================
-- ALTER TABLE public.users DROP COLUMN IF EXISTS custom_avatar_url;
-- ALTER TABLE public.users DROP COLUMN IF EXISTS avatar_visibility;
-- DROP TYPE IF EXISTS public.avatar_visibility;
-- (Restore previous handle_new_auth_user from migration 007)

-- =============================================================================
-- END OF MIGRATION 010
-- =============================================================================
