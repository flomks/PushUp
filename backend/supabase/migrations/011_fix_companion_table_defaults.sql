-- =============================================================================
-- Migration: 011_fix_companion_table_defaults.sql
-- Description: Fixes NOT NULL constraint errors on sign-up by ensuring all
--              companion table columns have correct defaults AND by rewriting
--              the trigger to supply every non-nullable column explicitly.
--
-- WHY THIS IS NEEDED
--   When 000_master_schema.sql ran on a DB that already had these tables
--   (created by migrations 001-007), CREATE TABLE IF NOT EXISTS was skipped.
--   The existing tables may be missing column DEFAULTs, causing the trigger
--   INSERT to fail with "null value in column X violates not-null constraint"
--   for id, total_xp, total_earned_seconds, etc.
--
-- SAFE TO RUN: ALTER COLUMN ... SET DEFAULT and CREATE OR REPLACE are idempotent.
-- =============================================================================

-- ---- user_levels ------------------------------------------------------------
ALTER TABLE public.user_levels
  ALTER COLUMN id         SET DEFAULT gen_random_uuid(),
  ALTER COLUMN total_xp   SET DEFAULT 0,
  ALTER COLUMN updated_at SET DEFAULT NOW();

-- ---- time_credits -----------------------------------------------------------
ALTER TABLE public.time_credits
  ALTER COLUMN id                   SET DEFAULT gen_random_uuid(),
  ALTER COLUMN total_earned_seconds SET DEFAULT 0,
  ALTER COLUMN total_spent_seconds  SET DEFAULT 0,
  ALTER COLUMN updated_at           SET DEFAULT NOW();

-- ---- user_settings ----------------------------------------------------------
ALTER TABLE public.user_settings
  ALTER COLUMN id                         SET DEFAULT gen_random_uuid(),
  ALTER COLUMN push_ups_per_minute_credit SET DEFAULT 10,
  ALTER COLUMN quality_multiplier_enabled SET DEFAULT FALSE,
  ALTER COLUMN searchable_by_email        SET DEFAULT FALSE,
  ALTER COLUMN created_at                 SET DEFAULT NOW(),
  ALTER COLUMN updated_at                 SET DEFAULT NOW();

-- ---- Rewrite trigger: supply every non-nullable column explicitly -----------
-- Never rely on column DEFAULTs inside a trigger — always pass values directly.
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

  -- Upsert user profile row.
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

  -- Companion rows: all non-nullable columns supplied explicitly.
  INSERT INTO public.time_credits (id, user_id, total_earned_seconds, total_spent_seconds, updated_at)
  VALUES (gen_random_uuid(), NEW.id, 0, 0, NOW())
  ON CONFLICT (user_id) DO NOTHING;

  INSERT INTO public.user_settings (id, user_id, push_ups_per_minute_credit, quality_multiplier_enabled, searchable_by_email, created_at, updated_at)
  VALUES (gen_random_uuid(), NEW.id, 10, FALSE, FALSE, NOW(), NOW())
  ON CONFLICT (user_id) DO NOTHING;

  INSERT INTO public.user_levels (id, user_id, total_xp, updated_at)
  VALUES (gen_random_uuid(), NEW.id, 0, NOW())
  ON CONFLICT (user_id) DO NOTHING;

  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.handle_new_auth_user() IS
  'Triggered after INSERT on auth.users. Creates companion rows with all '
  'non-nullable columns supplied explicitly (no reliance on column DEFAULTs).';

-- =============================================================================
-- END OF MIGRATION 011
-- =============================================================================
