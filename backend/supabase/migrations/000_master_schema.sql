-- =============================================================================
-- MASTER SCHEMA: 000_master_schema.sql
-- PushUp App — Supabase PostgreSQL
--
-- PURPOSE
--   This file is the single source of truth for a FRESH Supabase installation.
--   Run it once on a brand-new project to create the complete, up-to-date schema
--   in one shot — no need to run migrations 001-009 individually.
--
--   ALSO SAFE ON AN EXISTING DATABASE: every statement uses IF NOT EXISTS /
--   CREATE OR REPLACE / DROP … IF EXISTS so the file is fully idempotent.
--   Running it again on a live database will not destroy data or break anything.
--
-- SCHEMA SUMMARY
--   public.users            — App user profiles (linked to auth.users)
--   public.workout_sessions — One row per workout session
--   public.push_up_records  — Individual push-up events within a session
--   public.time_credits     — Accumulated screen-time credit balance per user
--   public.user_settings    — Per-user configuration (credit rate, cap, etc.)
--   public.friendships      — Friend requests and accepted friendships
--   public.friend_codes     — Shareable friend codes (one per user)
--   public.notifications    — In-app notifications (friend requests, etc.)
--   public.user_levels      — Accumulated XP per user
--   public.device_tokens    — APNs / FCM push notification tokens
--
-- USER IDENTITY MODEL
--   Every user has three identity fields:
--     email        — always private; used for auth only
--     username     — unique handle (e.g. "john_doe"); used for search / @-mentions
--     display_name — free-form friendly name shown in the UI (e.g. "John Doe")
--   Search works by username, display_name, or (optionally) email.
--   Email search is controlled by user_settings.searchable_by_email (default FALSE).
--
-- LAST UPDATED: 2026-03-15 (reflects migrations 001-012)
-- =============================================================================

BEGIN;

-- =============================================================================
-- SHARED HELPER FUNCTION: set_updated_at()
-- =============================================================================

CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.set_updated_at() IS
  'Generic BEFORE UPDATE trigger function: sets updated_at = NOW().';


-- =============================================================================
-- ENUM TYPES  (idempotent via DO block)
-- =============================================================================

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'friendship_status') THEN
    CREATE TYPE public.friendship_status AS ENUM ('pending', 'accepted', 'declined');
  END IF;
END; $$;

COMMENT ON TYPE public.friendship_status IS
  'Lifecycle states of a friendship: pending, accepted, declined.';

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'notification_type') THEN
    CREATE TYPE public.notification_type AS ENUM ('friend_request', 'friend_accepted');
  END IF;
END; $$;

COMMENT ON TYPE public.notification_type IS
  'Types of in-app notifications: friend_request, friend_accepted.';

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'avatar_visibility') THEN
    CREATE TYPE public.avatar_visibility AS ENUM (
      'everyone',      -- default: any authenticated user can see the avatar
      'friends_only',  -- only accepted friends can see the avatar
      'nobody'         -- avatar hidden; initials shown instead
    );
  END IF;
END; $$;

COMMENT ON TYPE public.avatar_visibility IS
  'Controls who can see a user''s avatar: everyone, friends_only, or nobody.';


-- =============================================================================
-- TABLE: public.users
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.users (
  id                 UUID                    PRIMARY KEY DEFAULT gen_random_uuid(),
  email              TEXT                    UNIQUE NOT NULL,
  username           TEXT,
  display_name       TEXT,
  avatar_url         TEXT,                   -- OAuth provider avatar (Google/Apple)
  custom_avatar_url  TEXT,                   -- user-uploaded avatar (always takes priority)
  avatar_visibility  public.avatar_visibility NOT NULL DEFAULT 'everyone',
  created_at         TIMESTAMPTZ             NOT NULL DEFAULT NOW(),
  updated_at         TIMESTAMPTZ             NOT NULL DEFAULT NOW(),

  CONSTRAINT users_username_format CHECK (
    username IS NULL OR (
      length(username) >= 3
      AND length(username) <= 20
      AND username ~ '^[a-z0-9_.]+$'
      AND username NOT LIKE '.%'
      AND username NOT LIKE '%.'
      AND username NOT LIKE '%..%'
    )
  )
);

COMMENT ON TABLE  public.users                    IS 'App user profiles, linked to Supabase Auth.';
COMMENT ON COLUMN public.users.id                 IS 'UUID matching auth.users.id.';
COMMENT ON COLUMN public.users.email              IS 'User email address (unique, private).';
COMMENT ON COLUMN public.users.username           IS 'Unique lowercase handle (e.g. "john_doe"). Used for search and @-mentions.';
COMMENT ON COLUMN public.users.display_name       IS 'Free-form display name shown in the UI (e.g. "John Doe").';
COMMENT ON COLUMN public.users.avatar_url         IS 'OAuth provider avatar URL (Google/Apple). Never overwritten once custom_avatar_url is set.';
COMMENT ON COLUMN public.users.custom_avatar_url  IS 'User-uploaded avatar URL. Always takes priority over avatar_url when set.';
COMMENT ON COLUMN public.users.avatar_visibility  IS 'Who can see this user''s avatar: everyone (default), friends_only, or nobody.';

CREATE UNIQUE INDEX IF NOT EXISTS idx_users_username_unique
  ON public.users (username) WHERE username IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_users_username_lower
  ON public.users (lower(username));

CREATE INDEX IF NOT EXISTS idx_users_display_name_lower
  ON public.users (lower(display_name));

DROP TRIGGER IF EXISTS trg_users_updated_at ON public.users;
CREATE TRIGGER trg_users_updated_at
  BEFORE UPDATE ON public.users
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


-- =============================================================================
-- TABLE: public.workout_sessions
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
COMMENT ON COLUMN public.workout_sessions.ended_at            IS 'NULL = session still running.';
COMMENT ON COLUMN public.workout_sessions.earned_time_credits IS 'Screen-time credits earned (seconds).';
COMMENT ON COLUMN public.workout_sessions.quality             IS 'Average form quality score (0.0 – 1.0).';

CREATE INDEX IF NOT EXISTS idx_workout_sessions_user_id
  ON public.workout_sessions(user_id);
CREATE INDEX IF NOT EXISTS idx_workout_sessions_started_at
  ON public.workout_sessions(started_at DESC);

DROP TRIGGER IF EXISTS trg_workout_sessions_updated_at ON public.workout_sessions;
CREATE TRIGGER trg_workout_sessions_updated_at
  BEFORE UPDATE ON public.workout_sessions
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


-- =============================================================================
-- TABLE: public.push_up_records
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

COMMENT ON TABLE public.push_up_records IS 'Individual push-up events within a workout session.';

CREATE INDEX IF NOT EXISTS idx_push_up_records_session_id
  ON public.push_up_records(session_id);


-- =============================================================================
-- TABLE: public.time_credits
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.time_credits (
  id                   UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id              UUID        NOT NULL UNIQUE REFERENCES public.users(id) ON DELETE CASCADE,
  total_earned_seconds BIGINT      NOT NULL DEFAULT 0,
  total_spent_seconds  BIGINT      NOT NULL DEFAULT 0,
  updated_at           TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE  public.time_credits                      IS 'Accumulated screen-time credits per user (one row per user).';
COMMENT ON COLUMN public.time_credits.total_earned_seconds IS 'Total seconds earned through workouts (ever).';
COMMENT ON COLUMN public.time_credits.total_spent_seconds  IS 'Total seconds spent as screen-time (ever).';

CREATE INDEX IF NOT EXISTS idx_time_credits_user_id
  ON public.time_credits(user_id);

DROP TRIGGER IF EXISTS trg_time_credits_updated_at ON public.time_credits;
CREATE TRIGGER trg_time_credits_updated_at
  BEFORE UPDATE ON public.time_credits
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


-- =============================================================================
-- TABLE: public.user_settings
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.user_settings (
  id                         UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id                    UUID        NOT NULL UNIQUE REFERENCES public.users(id) ON DELETE CASCADE,
  push_ups_per_minute_credit INTEGER     NOT NULL DEFAULT 10,
  quality_multiplier_enabled BOOLEAN     NOT NULL DEFAULT FALSE,
  daily_credit_cap_seconds   BIGINT,
  searchable_by_email        BOOLEAN     NOT NULL DEFAULT FALSE,
  created_at                 TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at                 TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE  public.user_settings                             IS 'Per-user configuration (one row per user).';
COMMENT ON COLUMN public.user_settings.push_ups_per_minute_credit IS 'How many push-ups earn 1 minute of screen-time (default 10).';
COMMENT ON COLUMN public.user_settings.quality_multiplier_enabled IS 'Whether form quality affects the credit multiplier.';
COMMENT ON COLUMN public.user_settings.daily_credit_cap_seconds   IS 'Optional daily cap on earned credits in seconds. NULL = no cap.';
COMMENT ON COLUMN public.user_settings.searchable_by_email        IS 'Whether other users can find this account by email address (default FALSE).';

DROP TRIGGER IF EXISTS trg_user_settings_updated_at ON public.user_settings;
CREATE TRIGGER trg_user_settings_updated_at
  BEFORE UPDATE ON public.user_settings
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


-- =============================================================================
-- TABLE: public.friendships
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.friendships (
  id           UUID                     PRIMARY KEY DEFAULT gen_random_uuid(),
  requester_id UUID                     NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  receiver_id  UUID                     NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  status       public.friendship_status NOT NULL DEFAULT 'pending',
  created_at   TIMESTAMPTZ              NOT NULL DEFAULT NOW(),
  updated_at   TIMESTAMPTZ              NOT NULL DEFAULT NOW(),

  CONSTRAINT friendships_no_self_reference CHECK (requester_id <> receiver_id),
  CONSTRAINT friendships_unique_pair       UNIQUE (requester_id, receiver_id)
);

COMMENT ON TABLE  public.friendships              IS 'Friend requests and accepted friendships between users.';
COMMENT ON COLUMN public.friendships.requester_id IS 'The user who sent the friend request.';
COMMENT ON COLUMN public.friendships.receiver_id  IS 'The user who received the friend request.';
COMMENT ON COLUMN public.friendships.status       IS 'Current state: pending / accepted / declined.';

CREATE INDEX IF NOT EXISTS idx_friendships_requester_id     ON public.friendships(requester_id);
CREATE INDEX IF NOT EXISTS idx_friendships_receiver_id      ON public.friendships(receiver_id);
CREATE INDEX IF NOT EXISTS idx_friendships_requester_status ON public.friendships(requester_id, status);
CREATE INDEX IF NOT EXISTS idx_friendships_receiver_status  ON public.friendships(receiver_id, status);

DROP TRIGGER IF EXISTS trg_friendships_updated_at ON public.friendships;
CREATE TRIGGER trg_friendships_updated_at
  BEFORE UPDATE ON public.friendships
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


-- =============================================================================
-- TABLE: public.friend_codes
-- =============================================================================

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'friend_code_privacy') THEN
    CREATE TYPE public.friend_code_privacy AS ENUM (
      'auto_accept',
      'require_approval',
      'inactive'
    );
  END IF;
END; $$;

COMMENT ON TYPE public.friend_code_privacy IS
  'Privacy setting for a friend code: auto_accept (instant friend), require_approval (pending request), inactive (disabled).';

CREATE TABLE IF NOT EXISTS public.friend_codes (
  id         UUID                       PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    UUID                       NOT NULL UNIQUE REFERENCES public.users(id) ON DELETE CASCADE,
  code       TEXT                       NOT NULL UNIQUE,
  privacy    public.friend_code_privacy NOT NULL DEFAULT 'require_approval',
  created_at TIMESTAMPTZ                NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ                NOT NULL DEFAULT NOW(),
  CONSTRAINT friend_codes_code_format CHECK (code ~ '^[A-Z0-9]{4,16}$')
);

COMMENT ON TABLE  public.friend_codes            IS 'Shareable friend codes -- one per user.';
COMMENT ON COLUMN public.friend_codes.user_id    IS 'FK to users.id -- the owner of this code.';
COMMENT ON COLUMN public.friend_codes.code       IS 'Short uppercase alphanumeric code (4-16 chars, globally unique).';
COMMENT ON COLUMN public.friend_codes.privacy    IS 'Controls what happens when someone uses this code.';

CREATE INDEX IF NOT EXISTS idx_friend_codes_code    ON public.friend_codes(code);
CREATE INDEX IF NOT EXISTS idx_friend_codes_user_id ON public.friend_codes(user_id);

DROP TRIGGER IF EXISTS trg_friend_codes_updated_at ON public.friend_codes;
CREATE TRIGGER trg_friend_codes_updated_at
  BEFORE UPDATE ON public.friend_codes
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

ALTER TABLE public.friend_codes ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='friend_codes' AND policyname='friend_codes_select') THEN
    CREATE POLICY "friend_codes_select" ON public.friend_codes FOR SELECT USING (true);
  END IF;
END; $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='friend_codes' AND policyname='friend_codes_insert_own') THEN
    CREATE POLICY "friend_codes_insert_own" ON public.friend_codes FOR INSERT WITH CHECK (auth.uid() = user_id);
  END IF;
END; $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='friend_codes' AND policyname='friend_codes_update_own') THEN
    CREATE POLICY "friend_codes_update_own" ON public.friend_codes FOR UPDATE USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
  END IF;
END; $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='friend_codes' AND policyname='friend_codes_delete_own') THEN
    CREATE POLICY "friend_codes_delete_own" ON public.friend_codes FOR DELETE USING (auth.uid() = user_id);
  END IF;
END; $$;


-- =============================================================================
-- TABLE: public.notifications
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

COMMENT ON TABLE  public.notifications          IS 'In-app notifications delivered to users.';
COMMENT ON COLUMN public.notifications.user_id  IS 'The notification recipient.';
COMMENT ON COLUMN public.notifications.actor_id IS 'The user who triggered the notification (NULL if actor deleted).';
COMMENT ON COLUMN public.notifications.payload  IS 'Arbitrary JSON metadata (e.g. friendship_id).';
COMMENT ON COLUMN public.notifications.is_read  IS 'Whether the recipient has dismissed this notification.';

CREATE INDEX IF NOT EXISTS idx_notifications_user_id         ON public.notifications(user_id);
CREATE INDEX IF NOT EXISTS idx_notifications_user_is_read    ON public.notifications(user_id, is_read);
CREATE INDEX IF NOT EXISTS idx_notifications_user_created_at ON public.notifications(user_id, created_at DESC);

DROP TRIGGER IF EXISTS trg_notifications_updated_at ON public.notifications;
CREATE TRIGGER trg_notifications_updated_at
  BEFORE UPDATE ON public.notifications
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


-- =============================================================================
-- TABLE: public.user_levels
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.user_levels (
  id         UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    UUID        NOT NULL UNIQUE REFERENCES public.users(id) ON DELETE CASCADE,
  total_xp   BIGINT      NOT NULL DEFAULT 0,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE  public.user_levels          IS 'Accumulated XP per user. Level is derived from total_xp on the client.';
COMMENT ON COLUMN public.user_levels.total_xp IS 'Total XP accumulated across all time. Monotonically increasing.';

CREATE INDEX IF NOT EXISTS idx_user_levels_user_id ON public.user_levels(user_id);

DROP TRIGGER IF EXISTS trg_user_levels_updated_at ON public.user_levels;
CREATE TRIGGER trg_user_levels_updated_at
  BEFORE UPDATE ON public.user_levels
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


-- =============================================================================
-- TABLE: public.device_tokens
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.device_tokens (
  id         UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    UUID        NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  token      TEXT        NOT NULL,
  platform   TEXT        NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT device_tokens_unique_token UNIQUE (token)
);

COMMENT ON TABLE  public.device_tokens          IS 'Push notification tokens per user device.';
COMMENT ON COLUMN public.device_tokens.token    IS 'APNs or FCM device token (unique across all users).';
COMMENT ON COLUMN public.device_tokens.platform IS 'Push platform: ''apns'' (iOS) or ''fcm'' (Android).';

CREATE INDEX IF NOT EXISTS idx_device_tokens_user_id ON public.device_tokens(user_id);

DROP TRIGGER IF EXISTS trg_device_tokens_updated_at ON public.device_tokens;
CREATE TRIGGER trg_device_tokens_updated_at
  BEFORE UPDATE ON public.device_tokens
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


-- =============================================================================
-- AUTH INTEGRATION: auto-create companion rows on sign-up
-- =============================================================================

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

  -- Supply every non-nullable column explicitly — never rely on column DEFAULTs
  -- inside a trigger, as they may not be set on tables created by older migrations.
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
  'Triggered after INSERT on auth.users. Creates companion rows. '
  'Sets avatar_url from OAuth metadata only when no custom avatar has been uploaded.';

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

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='users' AND policyname='users_select_own') THEN
    CREATE POLICY "users_select_own" ON public.users FOR SELECT USING (auth.uid() = id);
  END IF;
END; $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='users' AND policyname='users_insert_own') THEN
    CREATE POLICY "users_insert_own" ON public.users FOR INSERT WITH CHECK (auth.uid() = id);
  END IF;
END; $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='users' AND policyname='users_update_own') THEN
    CREATE POLICY "users_update_own" ON public.users FOR UPDATE USING (auth.uid() = id) WITH CHECK (auth.uid() = id);
  END IF;
END; $$;

-- Public profile read: any authenticated user can read id/username/display_name/avatar_url
-- (used by user-search; sensitive columns like email are filtered in app code)
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='users' AND policyname='users_select_public_profile') THEN
    CREATE POLICY "users_select_public_profile" ON public.users FOR SELECT USING (auth.role() = 'authenticated');
  END IF;
END; $$;

-- ---- workout_sessions -------------------------------------------------------

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='workout_sessions' AND policyname='workout_sessions_select_own') THEN
    CREATE POLICY "workout_sessions_select_own" ON public.workout_sessions FOR SELECT USING (auth.uid() = user_id);
  END IF;
END; $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='workout_sessions' AND policyname='workout_sessions_insert_own') THEN
    CREATE POLICY "workout_sessions_insert_own" ON public.workout_sessions FOR INSERT WITH CHECK (auth.uid() = user_id);
  END IF;
END; $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='workout_sessions' AND policyname='workout_sessions_update_own') THEN
    CREATE POLICY "workout_sessions_update_own" ON public.workout_sessions FOR UPDATE USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
  END IF;
END; $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='workout_sessions' AND policyname='workout_sessions_delete_own') THEN
    CREATE POLICY "workout_sessions_delete_own" ON public.workout_sessions FOR DELETE USING (auth.uid() = user_id);
  END IF;
END; $$;

-- ---- push_up_records --------------------------------------------------------

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='push_up_records' AND policyname='push_up_records_select_own') THEN
    CREATE POLICY "push_up_records_select_own" ON public.push_up_records FOR SELECT
      USING (EXISTS (SELECT 1 FROM public.workout_sessions ws WHERE ws.id = push_up_records.session_id AND ws.user_id = auth.uid()));
  END IF;
END; $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='push_up_records' AND policyname='push_up_records_insert_own') THEN
    CREATE POLICY "push_up_records_insert_own" ON public.push_up_records FOR INSERT
      WITH CHECK (EXISTS (SELECT 1 FROM public.workout_sessions ws WHERE ws.id = push_up_records.session_id AND ws.user_id = auth.uid()));
  END IF;
END; $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='push_up_records' AND policyname='push_up_records_update_own') THEN
    CREATE POLICY "push_up_records_update_own" ON public.push_up_records FOR UPDATE
      USING (EXISTS (SELECT 1 FROM public.workout_sessions ws WHERE ws.id = push_up_records.session_id AND ws.user_id = auth.uid()));
  END IF;
END; $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='push_up_records' AND policyname='push_up_records_delete_own') THEN
    CREATE POLICY "push_up_records_delete_own" ON public.push_up_records FOR DELETE
      USING (EXISTS (SELECT 1 FROM public.workout_sessions ws WHERE ws.id = push_up_records.session_id AND ws.user_id = auth.uid()));
  END IF;
END; $$;

-- ---- time_credits -----------------------------------------------------------

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='time_credits' AND policyname='time_credits_select_own') THEN
    CREATE POLICY "time_credits_select_own" ON public.time_credits FOR SELECT USING (auth.uid() = user_id);
  END IF;
END; $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='time_credits' AND policyname='time_credits_insert_own') THEN
    CREATE POLICY "time_credits_insert_own" ON public.time_credits FOR INSERT WITH CHECK (auth.uid() = user_id);
  END IF;
END; $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='time_credits' AND policyname='time_credits_update_own') THEN
    CREATE POLICY "time_credits_update_own" ON public.time_credits FOR UPDATE USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
  END IF;
END; $$;

-- ---- user_settings ----------------------------------------------------------

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='user_settings' AND policyname='user_settings_select_own') THEN
    CREATE POLICY "user_settings_select_own" ON public.user_settings FOR SELECT USING (auth.uid() = user_id);
  END IF;
END; $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='user_settings' AND policyname='user_settings_insert_own') THEN
    CREATE POLICY "user_settings_insert_own" ON public.user_settings FOR INSERT WITH CHECK (auth.uid() = user_id);
  END IF;
END; $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='user_settings' AND policyname='user_settings_update_own') THEN
    CREATE POLICY "user_settings_update_own" ON public.user_settings FOR UPDATE USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
  END IF;
END; $$;

-- ---- friendships ------------------------------------------------------------

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='friendships' AND policyname='friendships_select_own') THEN
    CREATE POLICY "friendships_select_own" ON public.friendships FOR SELECT
      USING (auth.uid() = requester_id OR auth.uid() = receiver_id);
  END IF;
END; $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='friendships' AND policyname='friendships_insert_own') THEN
    CREATE POLICY "friendships_insert_own" ON public.friendships FOR INSERT
      WITH CHECK (auth.uid() = requester_id AND auth.uid() <> receiver_id);
  END IF;
END; $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='friendships' AND policyname='friendships_update_receiver') THEN
    CREATE POLICY "friendships_update_receiver" ON public.friendships FOR UPDATE
      USING (auth.uid() = receiver_id) WITH CHECK (auth.uid() = receiver_id);
  END IF;
END; $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='friendships' AND policyname='friendships_delete_own') THEN
    CREATE POLICY "friendships_delete_own" ON public.friendships FOR DELETE
      USING (auth.uid() = requester_id OR auth.uid() = receiver_id);
  END IF;
END; $$;

-- ---- notifications ----------------------------------------------------------

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='notifications' AND policyname='notifications_select_own') THEN
    CREATE POLICY "notifications_select_own" ON public.notifications FOR SELECT USING (auth.uid() = user_id);
  END IF;
END; $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='notifications' AND policyname='notifications_update_own') THEN
    CREATE POLICY "notifications_update_own" ON public.notifications FOR UPDATE USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
  END IF;
END; $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='notifications' AND policyname='notifications_delete_own') THEN
    CREATE POLICY "notifications_delete_own" ON public.notifications FOR DELETE USING (auth.uid() = user_id);
  END IF;
END; $$;

-- ---- user_levels ------------------------------------------------------------

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='user_levels' AND policyname='user_levels_select_own') THEN
    CREATE POLICY "user_levels_select_own" ON public.user_levels FOR SELECT USING (auth.uid() = user_id);
  END IF;
END; $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='user_levels' AND policyname='user_levels_insert_own') THEN
    CREATE POLICY "user_levels_insert_own" ON public.user_levels FOR INSERT WITH CHECK (auth.uid() = user_id);
  END IF;
END; $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='user_levels' AND policyname='user_levels_update_own') THEN
    CREATE POLICY "user_levels_update_own" ON public.user_levels FOR UPDATE USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
  END IF;
END; $$;

-- No DELETE policy for user_levels: XP is permanent.

-- ---- device_tokens ----------------------------------------------------------

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='device_tokens' AND policyname='device_tokens_select_own') THEN
    CREATE POLICY "device_tokens_select_own" ON public.device_tokens FOR SELECT USING (auth.uid() = user_id);
  END IF;
END; $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='device_tokens' AND policyname='device_tokens_insert_own') THEN
    CREATE POLICY "device_tokens_insert_own" ON public.device_tokens FOR INSERT WITH CHECK (auth.uid() = user_id);
  END IF;
END; $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='device_tokens' AND policyname='device_tokens_update_own') THEN
    CREATE POLICY "device_tokens_update_own" ON public.device_tokens FOR UPDATE USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
  END IF;
END; $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='device_tokens' AND policyname='device_tokens_delete_own') THEN
    CREATE POLICY "device_tokens_delete_own" ON public.device_tokens FOR DELETE USING (auth.uid() = user_id);
  END IF;
END; $$;


-- =============================================================================
-- DIAGNOSTIC VIEWS & HELPERS
-- =============================================================================

CREATE OR REPLACE VIEW public.rls_status AS
SELECT tablename, rowsecurity AS rls_enabled
FROM pg_tables WHERE schemaname = 'public' ORDER BY tablename;

COMMENT ON VIEW public.rls_status IS 'Quick check: RLS status per public table.';

CREATE OR REPLACE VIEW public.policy_overview AS
SELECT tablename, policyname, cmd AS operation, roles,
       qual AS using_expression, with_check AS with_check_expression
FROM pg_policies WHERE schemaname = 'public' ORDER BY tablename, policyname;

COMMENT ON VIEW public.policy_overview IS 'Quick check: all RLS policies on public tables.';

CREATE OR REPLACE FUNCTION public.is_authenticated()
RETURNS BOOLEAN LANGUAGE sql STABLE AS $$
  SELECT auth.uid() IS NOT NULL;
$$;

COMMENT ON FUNCTION public.is_authenticated() IS
  'Returns TRUE if the current request has a valid JWT.';


COMMIT;

-- =============================================================================
-- VERIFICATION (run manually after applying)
-- =============================================================================
-- SELECT * FROM public.rls_status;
-- SELECT tablename FROM pg_tables WHERE schemaname = 'public' ORDER BY tablename;
-- SELECT trigger_name FROM information_schema.triggers WHERE trigger_name = 'trg_on_auth_user_created';
-- =============================================================================
