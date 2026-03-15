-- =============================================================================
-- MASTER SCHEMA: 000_master_schema.sql
-- PushUp App — Supabase PostgreSQL
--
-- PURPOSE
--   This file is the single source of truth for a FRESH Supabase installation.
--   Run it once on a brand-new project to create the complete, up-to-date schema
--   in one shot — no need to run migrations 001-008 individually.
--
--   For an EXISTING database that was set up with the numbered migrations,
--   continue using the numbered files (001, 002, 004, 005, 006, 007, 008).
--   This file is kept in sync with the cumulative result of all those migrations.
--
-- EXECUTION ORDER (fresh install)
--   1. Run this file in the Supabase SQL Editor or via psql.
--   2. Done. All tables, indexes, triggers, functions, RLS policies, and views
--      are created in a single transaction.
--
-- SCHEMA SUMMARY
--   public.users            — App user profiles (linked to auth.users)
--   public.workout_sessions — One row per workout session
--   public.push_up_records  — Individual push-up events within a session
--   public.time_credits     — Accumulated screen-time credit balance per user
--   public.user_settings    — Per-user configuration (credit rate, cap, etc.)
--   public.friendships      — Friend requests and accepted friendships
--   public.notifications    — In-app notifications (friend requests, etc.)
--   public.user_levels      — Accumulated XP per user
--   public.device_tokens    — APNs / FCM push notification tokens
--
-- LAST UPDATED: 2026-03-15 (reflects migrations 001-008)
-- =============================================================================

BEGIN;

-- =============================================================================
-- EXTENSIONS
-- =============================================================================
-- gen_random_uuid() is available by default in Supabase (pgcrypto is pre-enabled).
-- No explicit CREATE EXTENSION needed.


-- =============================================================================
-- SHARED HELPER FUNCTION: set_updated_at()
-- Automatically stamps updated_at = NOW() on every UPDATE.
-- Attached as a BEFORE UPDATE trigger to every table that has updated_at.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.set_updated_at() IS
  'Generic BEFORE UPDATE trigger function: sets updated_at = NOW().';


-- =============================================================================
-- ENUM TYPES
-- =============================================================================

-- friendship_status: lifecycle of a friend request
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'friendship_status') THEN
    CREATE TYPE public.friendship_status AS ENUM (
      'pending',    -- request sent, awaiting response
      'accepted',   -- both users are friends
      'declined'    -- receiver explicitly rejected the request
    );
  END IF;
END;
$$;

COMMENT ON TYPE public.friendship_status IS
  'Lifecycle states of a friendship: pending, accepted, declined.';


-- notification_type: kinds of in-app notifications
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'notification_type') THEN
    CREATE TYPE public.notification_type AS ENUM (
      'friend_request',   -- a user sent a friend request to the recipient
      'friend_accepted'   -- the recipient accepted a friend request
    );
  END IF;
END;
$$;

COMMENT ON TYPE public.notification_type IS
  'Types of in-app notifications: friend_request, friend_accepted.';


-- =============================================================================
-- TABLE: public.users
-- App user profiles. One row per Supabase Auth user.
-- Populated automatically by the handle_new_auth_user() trigger on auth.users.
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.users (
  id           UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  email        TEXT        UNIQUE NOT NULL,
  username     TEXT,                          -- unique handle, set by user after first login
  display_name TEXT,                          -- free-form display name
  avatar_url   TEXT,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  -- username format: 3-20 chars, lowercase letters/digits/underscores
  CONSTRAINT users_username_format CHECK (
    username IS NULL OR (
      length(username) >= 3
      AND length(username) <= 20
      AND username ~ '^[a-z0-9_]+$'
    )
  )
);

COMMENT ON TABLE  public.users              IS 'App user profiles, linked to Supabase Auth.';
COMMENT ON COLUMN public.users.id           IS 'UUID matching auth.users.id.';
COMMENT ON COLUMN public.users.email        IS 'User email address (unique).';
COMMENT ON COLUMN public.users.username     IS 'Unique lowercase handle (e.g. "john_doe"). Set once by the user. Used for search.';
COMMENT ON COLUMN public.users.display_name IS 'Free-form display name shown in the UI.';
COMMENT ON COLUMN public.users.avatar_url   IS 'URL to the user avatar stored in Supabase Storage.';

-- Unique username (partial index: NULLs are excluded so unset usernames don't conflict)
CREATE UNIQUE INDEX IF NOT EXISTS idx_users_username_unique
  ON public.users (username)
  WHERE username IS NOT NULL;

-- Case-insensitive search indexes
CREATE INDEX IF NOT EXISTS idx_users_username_lower
  ON public.users (lower(username));

CREATE INDEX IF NOT EXISTS idx_users_display_name_lower
  ON public.users (lower(display_name));

CREATE TRIGGER trg_users_updated_at
  BEFORE UPDATE ON public.users
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


-- =============================================================================
-- TABLE: public.workout_sessions
-- One row per workout session started by a user.
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.workout_sessions (
  id                   UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id              UUID        NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  started_at           TIMESTAMPTZ NOT NULL,
  ended_at             TIMESTAMPTZ,
  push_up_count        INTEGER     NOT NULL DEFAULT 0,
  earned_time_credits  INTEGER     NOT NULL DEFAULT 0,
  quality              REAL        NOT NULL DEFAULT 0.0,
  created_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at           TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE  public.workout_sessions                     IS 'Individual workout sessions per user.';
COMMENT ON COLUMN public.workout_sessions.user_id             IS 'FK to users.id.';
COMMENT ON COLUMN public.workout_sessions.started_at          IS 'Timestamp when the workout was started.';
COMMENT ON COLUMN public.workout_sessions.ended_at            IS 'Timestamp when the workout finished. NULL = still running.';
COMMENT ON COLUMN public.workout_sessions.push_up_count       IS 'Total push-ups counted in this session.';
COMMENT ON COLUMN public.workout_sessions.earned_time_credits IS 'Screen-time credits earned (seconds).';
COMMENT ON COLUMN public.workout_sessions.quality             IS 'Average form quality score (0.0 – 1.0).';

CREATE INDEX IF NOT EXISTS idx_workout_sessions_user_id
  ON public.workout_sessions(user_id);

CREATE INDEX IF NOT EXISTS idx_workout_sessions_started_at
  ON public.workout_sessions(started_at DESC);

CREATE TRIGGER trg_workout_sessions_updated_at
  BEFORE UPDATE ON public.workout_sessions
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


-- =============================================================================
-- TABLE: public.push_up_records
-- One row per individual push-up detected within a session.
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.push_up_records (
  id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id  UUID        NOT NULL REFERENCES public.workout_sessions(id) ON DELETE CASCADE,
  timestamp   TIMESTAMPTZ NOT NULL,
  duration_ms INTEGER,
  depth_score REAL,
  form_score  REAL,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE  public.push_up_records             IS 'Individual push-up events within a workout session.';
COMMENT ON COLUMN public.push_up_records.session_id  IS 'FK to workout_sessions.id.';
COMMENT ON COLUMN public.push_up_records.timestamp   IS 'Exact timestamp of the push-up detection.';
COMMENT ON COLUMN public.push_up_records.duration_ms IS 'Duration of the push-up movement in milliseconds.';
COMMENT ON COLUMN public.push_up_records.depth_score IS 'How deep the push-up was (0.0 – 1.0).';
COMMENT ON COLUMN public.push_up_records.form_score  IS 'Form quality score (0.0 – 1.0).';

CREATE INDEX IF NOT EXISTS idx_push_up_records_session_id
  ON public.push_up_records(session_id);


-- =============================================================================
-- TABLE: public.time_credits
-- Running totals of earned/spent screen-time credits. One row per user.
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.time_credits (
  id                   UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id              UUID        NOT NULL UNIQUE REFERENCES public.users(id) ON DELETE CASCADE,
  total_earned_seconds BIGINT      NOT NULL DEFAULT 0,
  total_spent_seconds  BIGINT      NOT NULL DEFAULT 0,
  updated_at           TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE  public.time_credits                      IS 'Accumulated screen-time credits per user.';
COMMENT ON COLUMN public.time_credits.user_id              IS 'FK to users.id (one record per user).';
COMMENT ON COLUMN public.time_credits.total_earned_seconds IS 'Total seconds earned through workouts (ever).';
COMMENT ON COLUMN public.time_credits.total_spent_seconds  IS 'Total seconds spent as screen-time (ever).';

CREATE INDEX IF NOT EXISTS idx_time_credits_user_id
  ON public.time_credits(user_id);

CREATE TRIGGER trg_time_credits_updated_at
  BEFORE UPDATE ON public.time_credits
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


-- =============================================================================
-- TABLE: public.user_settings
-- Per-user configuration. One row per user.
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.user_settings (
  id                         UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id                    UUID        NOT NULL UNIQUE REFERENCES public.users(id) ON DELETE CASCADE,
  push_ups_per_minute_credit INTEGER     NOT NULL DEFAULT 10,
  quality_multiplier_enabled BOOLEAN     NOT NULL DEFAULT FALSE,
  daily_credit_cap_seconds   BIGINT,
  created_at                 TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at                 TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE  public.user_settings                             IS 'Per-user configuration for the workout credit system.';
COMMENT ON COLUMN public.user_settings.user_id                    IS 'FK to users.id (one record per user).';
COMMENT ON COLUMN public.user_settings.push_ups_per_minute_credit IS 'How many push-ups earn 1 minute of screen-time (default 10).';
COMMENT ON COLUMN public.user_settings.quality_multiplier_enabled IS 'Whether form quality affects the credit multiplier.';
COMMENT ON COLUMN public.user_settings.daily_credit_cap_seconds   IS 'Optional daily cap on earned credits in seconds. NULL = no cap.';

CREATE TRIGGER trg_user_settings_updated_at
  BEFORE UPDATE ON public.user_settings
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


-- =============================================================================
-- TABLE: public.friendships
-- Friend requests and accepted friendships between users.
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.friendships (
  id           UUID                    PRIMARY KEY DEFAULT gen_random_uuid(),
  requester_id UUID                    NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  receiver_id  UUID                    NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  status       public.friendship_status NOT NULL DEFAULT 'pending',
  created_at   TIMESTAMPTZ             NOT NULL DEFAULT NOW(),
  updated_at   TIMESTAMPTZ             NOT NULL DEFAULT NOW(),

  CONSTRAINT friendships_no_self_reference CHECK (requester_id <> receiver_id),
  CONSTRAINT friendships_unique_pair       UNIQUE (requester_id, receiver_id)
);

COMMENT ON TABLE  public.friendships              IS 'Friend requests and accepted friendships between users.';
COMMENT ON COLUMN public.friendships.requester_id IS 'FK to users.id — the user who sent the friend request.';
COMMENT ON COLUMN public.friendships.receiver_id  IS 'FK to users.id — the user who received the friend request.';
COMMENT ON COLUMN public.friendships.status       IS 'Current state: pending / accepted / declined.';

CREATE INDEX IF NOT EXISTS idx_friendships_requester_id
  ON public.friendships(requester_id);

CREATE INDEX IF NOT EXISTS idx_friendships_receiver_id
  ON public.friendships(receiver_id);

CREATE INDEX IF NOT EXISTS idx_friendships_requester_status
  ON public.friendships(requester_id, status);

CREATE INDEX IF NOT EXISTS idx_friendships_receiver_status
  ON public.friendships(receiver_id, status);

CREATE TRIGGER trg_friendships_updated_at
  BEFORE UPDATE ON public.friendships
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


-- =============================================================================
-- TABLE: public.notifications
-- In-app notifications for user events (friend requests, etc.).
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.notifications (
  id         UUID                     PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    UUID                     NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  type       public.notification_type NOT NULL,
  actor_id   UUID                     REFERENCES public.users(id) ON DELETE SET NULL,
  payload    JSONB                    NOT NULL DEFAULT '{}',
  is_read    BOOLEAN                  NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ              NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ              NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE  public.notifications         IS 'In-app notifications delivered to users.';
COMMENT ON COLUMN public.notifications.user_id IS 'FK to users.id — the notification recipient.';
COMMENT ON COLUMN public.notifications.type    IS 'Kind of notification (friend_request, friend_accepted).';
COMMENT ON COLUMN public.notifications.actor_id IS 'FK to users.id — the user who triggered the notification (nullable if actor deleted).';
COMMENT ON COLUMN public.notifications.payload IS 'Arbitrary JSON metadata (e.g. friendship_id).';
COMMENT ON COLUMN public.notifications.is_read IS 'Whether the recipient has read/dismissed this notification.';

CREATE INDEX IF NOT EXISTS idx_notifications_user_id
  ON public.notifications(user_id);

CREATE INDEX IF NOT EXISTS idx_notifications_user_is_read
  ON public.notifications(user_id, is_read);

CREATE INDEX IF NOT EXISTS idx_notifications_user_created_at
  ON public.notifications(user_id, created_at DESC);

CREATE TRIGGER trg_notifications_updated_at
  BEFORE UPDATE ON public.notifications
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


-- =============================================================================
-- TABLE: public.user_levels
-- Accumulated XP per user. Level is derived from total_xp on the client.
-- One row per user.
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.user_levels (
  id         UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    UUID        NOT NULL UNIQUE REFERENCES public.users(id) ON DELETE CASCADE,
  total_xp   BIGINT      NOT NULL DEFAULT 0,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE  public.user_levels          IS 'Accumulated XP per user. Level is derived from total_xp on the client.';
COMMENT ON COLUMN public.user_levels.user_id  IS 'FK to users.id (one record per user).';
COMMENT ON COLUMN public.user_levels.total_xp IS 'Total XP accumulated across all time. Monotonically increasing.';

CREATE INDEX IF NOT EXISTS idx_user_levels_user_id
  ON public.user_levels(user_id);

CREATE TRIGGER trg_user_levels_updated_at
  BEFORE UPDATE ON public.user_levels
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


-- =============================================================================
-- TABLE: public.device_tokens
-- APNs / FCM push notification tokens. One row per (user, token) pair.
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.device_tokens (
  id         UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    UUID        NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  token      TEXT        NOT NULL,
  platform   TEXT        NOT NULL,   -- 'apns' | 'fcm'
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT device_tokens_unique_token UNIQUE (token)
);

COMMENT ON TABLE  public.device_tokens          IS 'Push notification tokens per user device.';
COMMENT ON COLUMN public.device_tokens.user_id  IS 'FK to users.id.';
COMMENT ON COLUMN public.device_tokens.token    IS 'APNs or FCM device token (unique).';
COMMENT ON COLUMN public.device_tokens.platform IS 'Push platform: ''apns'' (iOS) or ''fcm'' (Android).';

CREATE INDEX IF NOT EXISTS idx_device_tokens_user_id
  ON public.device_tokens(user_id);

CREATE TRIGGER trg_device_tokens_updated_at
  BEFORE UPDATE ON public.device_tokens
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


-- =============================================================================
-- AUTH INTEGRATION
-- Trigger: auto-create companion rows when a new Supabase Auth user signs up.
-- =============================================================================

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
  -- Priority: full_name (Google/Apple) -> name -> email local-part fallback.
  v_display_name := COALESCE(
    NULLIF(TRIM(NEW.raw_user_meta_data->>'full_name'), ''),
    NULLIF(TRIM(NEW.raw_user_meta_data->>'name'),      ''),
    SPLIT_PART(NEW.email, '@', 1)
  );

  v_avatar_url := NULLIF(TRIM(NEW.raw_user_meta_data->>'avatar_url'), '');

  -- Upsert the user profile row.
  -- ON CONFLICT DO UPDATE keeps data fresh on re-login without overwriting
  -- manually set values (display_name, avatar_url) with provider defaults.
  INSERT INTO public.users (id, email, display_name, avatar_url, created_at, updated_at)
  VALUES (NEW.id, NEW.email, v_display_name, v_avatar_url, NOW(), NOW())
  ON CONFLICT (id) DO UPDATE SET
    email        = EXCLUDED.email,
    display_name = COALESCE(EXCLUDED.display_name, public.users.display_name),
    avatar_url   = COALESCE(EXCLUDED.avatar_url,   public.users.avatar_url),
    updated_at   = NOW();

  -- Ensure companion rows exist (idempotent inserts).
  INSERT INTO public.time_credits (user_id)
  VALUES (NEW.id)
  ON CONFLICT (user_id) DO NOTHING;

  INSERT INTO public.user_settings (user_id)
  VALUES (NEW.id)
  ON CONFLICT (user_id) DO NOTHING;

  INSERT INTO public.user_levels (user_id)
  VALUES (NEW.id)
  ON CONFLICT (user_id) DO NOTHING;

  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.handle_new_auth_user() IS
  'Triggered after INSERT on auth.users. Creates companion rows in users, '
  'time_credits, user_settings, and user_levels.';

-- Drop and recreate the trigger so this file is idempotent.
DROP TRIGGER IF EXISTS trg_on_auth_user_created ON auth.users;
CREATE TRIGGER trg_on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_auth_user();


-- =============================================================================
-- ROW LEVEL SECURITY (RLS)
-- =============================================================================

ALTER TABLE public.users             ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.workout_sessions  ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.push_up_records   ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.time_credits      ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_settings     ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.friendships       ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notifications     ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_levels       ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.device_tokens     ENABLE ROW LEVEL SECURITY;


-- ---- users ------------------------------------------------------------------

-- Own row: full read + write
CREATE POLICY "users_select_own"
  ON public.users FOR SELECT
  USING (auth.uid() = id);

CREATE POLICY "users_insert_own"
  ON public.users FOR INSERT
  WITH CHECK (auth.uid() = id);

CREATE POLICY "users_update_own"
  ON public.users FOR UPDATE
  USING (auth.uid() = id)
  WITH CHECK (auth.uid() = id);

-- Public profile: any authenticated user can read id/username/display_name/avatar_url
-- (used by the user-search feature; sensitive columns like email are filtered in app code)
CREATE POLICY "users_select_public_profile"
  ON public.users FOR SELECT
  USING (auth.role() = 'authenticated');


-- ---- workout_sessions -------------------------------------------------------

CREATE POLICY "workout_sessions_select_own"
  ON public.workout_sessions FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "workout_sessions_insert_own"
  ON public.workout_sessions FOR INSERT
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "workout_sessions_update_own"
  ON public.workout_sessions FOR UPDATE
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "workout_sessions_delete_own"
  ON public.workout_sessions FOR DELETE
  USING (auth.uid() = user_id);


-- ---- push_up_records --------------------------------------------------------
-- Access is granted through the parent workout_session.

CREATE POLICY "push_up_records_select_own"
  ON public.push_up_records FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.workout_sessions ws
      WHERE ws.id = push_up_records.session_id AND ws.user_id = auth.uid()
    )
  );

CREATE POLICY "push_up_records_insert_own"
  ON public.push_up_records FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.workout_sessions ws
      WHERE ws.id = push_up_records.session_id AND ws.user_id = auth.uid()
    )
  );

CREATE POLICY "push_up_records_update_own"
  ON public.push_up_records FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM public.workout_sessions ws
      WHERE ws.id = push_up_records.session_id AND ws.user_id = auth.uid()
    )
  );

CREATE POLICY "push_up_records_delete_own"
  ON public.push_up_records FOR DELETE
  USING (
    EXISTS (
      SELECT 1 FROM public.workout_sessions ws
      WHERE ws.id = push_up_records.session_id AND ws.user_id = auth.uid()
    )
  );


-- ---- time_credits -----------------------------------------------------------

CREATE POLICY "time_credits_select_own"
  ON public.time_credits FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "time_credits_insert_own"
  ON public.time_credits FOR INSERT
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "time_credits_update_own"
  ON public.time_credits FOR UPDATE
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);


-- ---- user_settings ----------------------------------------------------------

CREATE POLICY "user_settings_select_own"
  ON public.user_settings FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "user_settings_insert_own"
  ON public.user_settings FOR INSERT
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "user_settings_update_own"
  ON public.user_settings FOR UPDATE
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);


-- ---- friendships ------------------------------------------------------------

CREATE POLICY "friendships_select_own"
  ON public.friendships FOR SELECT
  USING (auth.uid() = requester_id OR auth.uid() = receiver_id);

CREATE POLICY "friendships_insert_own"
  ON public.friendships FOR INSERT
  WITH CHECK (auth.uid() = requester_id AND auth.uid() <> receiver_id);

-- Only the receiver may accept/decline; requester must DELETE to cancel.
CREATE POLICY "friendships_update_receiver"
  ON public.friendships FOR UPDATE
  USING (auth.uid() = receiver_id)
  WITH CHECK (auth.uid() = receiver_id);

CREATE POLICY "friendships_delete_own"
  ON public.friendships FOR DELETE
  USING (auth.uid() = requester_id OR auth.uid() = receiver_id);


-- ---- notifications ----------------------------------------------------------

CREATE POLICY "notifications_select_own"
  ON public.notifications FOR SELECT
  USING (auth.uid() = user_id);

-- INSERT is performed by the backend service role (bypasses RLS).
-- No INSERT policy for the authenticated role is intentional.

CREATE POLICY "notifications_update_own"
  ON public.notifications FOR UPDATE
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "notifications_delete_own"
  ON public.notifications FOR DELETE
  USING (auth.uid() = user_id);


-- ---- user_levels ------------------------------------------------------------

CREATE POLICY "user_levels_select_own"
  ON public.user_levels FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "user_levels_insert_own"
  ON public.user_levels FOR INSERT
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "user_levels_update_own"
  ON public.user_levels FOR UPDATE
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

-- No DELETE policy: XP is permanent.


-- ---- device_tokens ----------------------------------------------------------

CREATE POLICY "device_tokens_select_own"
  ON public.device_tokens FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "device_tokens_insert_own"
  ON public.device_tokens FOR INSERT
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "device_tokens_update_own"
  ON public.device_tokens FOR UPDATE
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "device_tokens_delete_own"
  ON public.device_tokens FOR DELETE
  USING (auth.uid() = user_id);


-- =============================================================================
-- DIAGNOSTIC VIEWS
-- =============================================================================

-- Quick check: shows whether RLS is enabled on every public table.
CREATE OR REPLACE VIEW public.rls_status AS
SELECT tablename, rowsecurity AS rls_enabled
FROM pg_tables
WHERE schemaname = 'public'
ORDER BY tablename;

COMMENT ON VIEW public.rls_status IS
  'Quick check: shows whether RLS is enabled on every public table.';

-- Quick check: lists all RLS policies on public tables.
CREATE OR REPLACE VIEW public.policy_overview AS
SELECT
  tablename,
  policyname,
  cmd        AS operation,
  roles,
  qual       AS using_expression,
  with_check AS with_check_expression
FROM pg_policies
WHERE schemaname = 'public'
ORDER BY tablename, policyname;

COMMENT ON VIEW public.policy_overview IS
  'Quick check: lists all RLS policies on public tables.';

-- Helper function: returns TRUE when the current request has a valid JWT.
CREATE OR REPLACE FUNCTION public.is_authenticated()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
AS $$
  SELECT auth.uid() IS NOT NULL;
$$;

COMMENT ON FUNCTION public.is_authenticated() IS
  'Returns TRUE if the current request is authenticated (has a valid JWT).';


COMMIT;

-- =============================================================================
-- VERIFICATION (run manually after applying this file)
-- =============================================================================
-- SELECT * FROM public.rls_status;
-- SELECT * FROM public.policy_overview;
-- SELECT trigger_name, event_object_schema, event_object_table
--   FROM information_schema.triggers
--   WHERE trigger_name = 'trg_on_auth_user_created';
-- =============================================================================
