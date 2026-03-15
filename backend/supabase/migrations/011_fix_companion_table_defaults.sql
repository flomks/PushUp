-- =============================================================================
-- Migration: 011_fix_companion_table_defaults.sql
-- Description: Ensures all companion tables (user_levels, time_credits,
--              user_settings) have gen_random_uuid() as the default for their
--              id column, and re-applies the correct handle_new_auth_user()
--              trigger function.
--
-- WHY THIS IS NEEDED
--   When 000_master_schema.sql was run on a database that already had these
--   tables (created by migrations 001-007), the CREATE TABLE IF NOT EXISTS
--   statements were skipped entirely. If the existing tables were created
--   without DEFAULT gen_random_uuid() on the id column (e.g. because an older
--   version of the migration omitted it), the trigger INSERT INTO user_levels
--   (user_id) VALUES (...) fails with:
--     "null value in column id violates not-null constraint"
--
-- SAFE TO RUN: ALTER COLUMN ... SET DEFAULT is idempotent.
-- =============================================================================

-- Ensure id columns have gen_random_uuid() as default on all companion tables.
ALTER TABLE public.user_levels
  ALTER COLUMN id SET DEFAULT gen_random_uuid();

ALTER TABLE public.time_credits
  ALTER COLUMN id SET DEFAULT gen_random_uuid();

ALTER TABLE public.user_settings
  ALTER COLUMN id SET DEFAULT gen_random_uuid();

-- Re-apply the correct trigger function (idempotent via CREATE OR REPLACE).
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
    avatar_url   = CASE
                     WHEN public.users.custom_avatar_url IS NOT NULL THEN public.users.avatar_url
                     ELSE COALESCE(EXCLUDED.avatar_url, public.users.avatar_url)
                   END,
    updated_at   = NOW();

  INSERT INTO public.time_credits  (id, user_id) VALUES (gen_random_uuid(), NEW.id) ON CONFLICT (user_id) DO NOTHING;
  INSERT INTO public.user_settings (id, user_id) VALUES (gen_random_uuid(), NEW.id) ON CONFLICT (user_id) DO NOTHING;
  INSERT INTO public.user_levels   (id, user_id) VALUES (gen_random_uuid(), NEW.id) ON CONFLICT (user_id) DO NOTHING;

  RETURN NEW;
END;
$$;

-- =============================================================================
-- END OF MIGRATION 011
-- =============================================================================
