-- =============================================================================
-- MASTER SCHEMA: 000_master_schema.sql
-- PushUp App Ã¢â‚¬â€ Supabase PostgreSQL
--
-- PURPOSE
--   This file is the single source of truth for a FRESH Supabase installation.
--   Run it once on a brand-new project to create the complete, up-to-date schema
--   in one shot Ã¢â‚¬â€ no need to run migrations 001-009 individually.
--
--   ALSO SAFE ON AN EXISTING DATABASE: every statement uses IF NOT EXISTS /
--   CREATE OR REPLACE / DROP Ã¢â‚¬Â¦ IF EXISTS so the file is fully idempotent.
--   Running it again on a live database will not destroy data or break anything.
--
-- SCHEMA SUMMARY
--   public.users            Ã¢â‚¬â€ App user profiles (linked to auth.users)
--   public.workout_sessions Ã¢â‚¬â€ One row per workout session
--   public.push_up_records  Ã¢â‚¬â€ Individual push-up events within a session
--   public.time_credits     Ã¢â‚¬â€ Accumulated screen-time credit balance per user
--   public.user_settings    Ã¢â‚¬â€ Per-user configuration (credit rate, cap, etc.)
--   public.friendships      Ã¢â‚¬â€ Friend requests and accepted friendships
--   public.friend_codes     Ã¢â‚¬â€ Shareable friend codes (one per user)
--   public.notifications    Ã¢â‚¬â€ In-app notifications (friend requests, etc.)
--   public.user_levels      Ã¢â‚¬â€ Accumulated XP per user
--   public.device_tokens    Ã¢â‚¬â€ APNs / FCM push notification tokens
--
-- USER IDENTITY MODEL
--   Every user has three identity fields:
--     email        Ã¢â‚¬â€ always private; used for auth only
--     username     Ã¢â‚¬â€ unique handle (e.g. "john_doe"); used for search / @-mentions
--     display_name Ã¢â‚¬â€ free-form friendly name shown in the UI (e.g. "John Doe")
--   Search works by username, display_name, or (optionally) email.
--   Email search is controlled by user_settings.searchable_by_email (default FALSE).
--
-- LAST UPDATED: 2026-04-02 (reflects migrations 001-019)
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
COMMENT ON COLUMN public.workout_sessions.quality             IS 'Average form quality score (0.0 Ã¢â‚¬â€œ 1.0).';

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

  -- Supply every non-nullable column explicitly Ã¢â‚¬â€ never rely on column DEFAULTs
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


-- =============================================================================
-- =============================================================================
-- Migration 019: Social Running Foundation
--
-- Adds the first-pass schema for planned run events, live sessions,
-- participants, presence, and XP awards.
-- =============================================================================

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'run_visibility') THEN
    CREATE TYPE public.run_visibility AS ENUM ('private', 'friends', 'invite_only');
  END IF;
END;
$$;

COMMENT ON TYPE public.run_visibility IS
  'Visibility for run events and live run sessions: private, friends, or invite_only.';

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'run_mode') THEN
    CREATE TYPE public.run_mode AS ENUM ('recovery', 'base', 'tempo', 'long_run', 'race');
  END IF;
END;
$$;

COMMENT ON TYPE public.run_mode IS
  'Running mode / training intent for a run event or live session.';

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'run_event_status') THEN
    CREATE TYPE public.run_event_status AS ENUM ('planned', 'check_in_open', 'live', 'completed', 'cancelled');
  END IF;
END;
$$;

COMMENT ON TYPE public.run_event_status IS
  'Lifecycle state of a planned run event.';

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'run_event_role') THEN
    CREATE TYPE public.run_event_role AS ENUM ('organizer', 'member');
  END IF;
END;
$$;

COMMENT ON TYPE public.run_event_role IS
  'Role of a user within a planned run event.';

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'run_participant_status') THEN
    CREATE TYPE public.run_participant_status AS ENUM ('invited', 'accepted', 'declined', 'checked_in');
  END IF;
END;
$$;

COMMENT ON TYPE public.run_participant_status IS
  'Invitation / RSVP lifecycle for a planned run participant.';

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'live_run_source_type') THEN
    CREATE TYPE public.live_run_source_type AS ENUM ('planned', 'spontaneous');
  END IF;
END;
$$;

COMMENT ON TYPE public.live_run_source_type IS
  'Where a live run session originated from: a planned event or a spontaneous start.';

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'live_run_state') THEN
    CREATE TYPE public.live_run_state AS ENUM ('live', 'cooldown', 'finished');
  END IF;
END;
$$;

COMMENT ON TYPE public.live_run_state IS
  'Current lifecycle state of a live run session.';

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'live_run_participant_status') THEN
    CREATE TYPE public.live_run_participant_status AS ENUM ('invited', 'joined', 'active', 'paused', 'finished', 'left');
  END IF;
END;
$$;

COMMENT ON TYPE public.live_run_participant_status IS
  'Current participation state of a user inside a live run session.';

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'live_run_presence_state') THEN
    CREATE TYPE public.live_run_presence_state AS ENUM ('active', 'paused', 'disconnected', 'finished');
  END IF;
END;
$$;

COMMENT ON TYPE public.live_run_presence_state IS
  'Realtime presence state for a user currently in a live run.';

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'run_xp_bonus_type') THEN
    CREATE TYPE public.run_xp_bonus_type AS ENUM ('solo', 'crew', 'synced');
  END IF;
END;
$$;

COMMENT ON TYPE public.run_xp_bonus_type IS
  'Bonus tier used when awarding XP for a run: solo, crew, or synced.';

CREATE TABLE IF NOT EXISTS public.run_events (
  id                UUID               PRIMARY KEY DEFAULT gen_random_uuid(),
  created_by        UUID               NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  title             TEXT               NOT NULL,
  description       TEXT,
  mode              public.run_mode    NOT NULL,
  visibility        public.run_visibility NOT NULL DEFAULT 'friends',
  planned_start_at  TIMESTAMPTZ        NOT NULL,
  planned_end_at    TIMESTAMPTZ,
  check_in_opens_at TIMESTAMPTZ        NOT NULL,
  status            public.run_event_status NOT NULL DEFAULT 'planned',
  location_name     TEXT,
  created_at        TIMESTAMPTZ        NOT NULL DEFAULT NOW(),
  updated_at        TIMESTAMPTZ        NOT NULL DEFAULT NOW(),
  CONSTRAINT run_events_time_window CHECK (planned_end_at IS NULL OR planned_end_at >= planned_start_at),
  CONSTRAINT run_events_check_in_before_start CHECK (check_in_opens_at <= planned_start_at)
);

COMMENT ON TABLE public.run_events IS
  'Planned social run events that can later materialize into live run sessions.';

CREATE INDEX IF NOT EXISTS idx_run_events_created_by
  ON public.run_events(created_by);
CREATE INDEX IF NOT EXISTS idx_run_events_planned_start_at
  ON public.run_events(planned_start_at);
CREATE INDEX IF NOT EXISTS idx_run_events_status
  ON public.run_events(status);
CREATE INDEX IF NOT EXISTS idx_run_events_visibility
  ON public.run_events(visibility);

DROP TRIGGER IF EXISTS trg_run_events_updated_at ON public.run_events;
CREATE TRIGGER trg_run_events_updated_at
  BEFORE UPDATE ON public.run_events
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

ALTER TABLE public.run_events ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'run_events'
      AND policyname = 'run_events_select_visible'
  ) THEN
    CREATE POLICY "run_events_select_visible"
      ON public.run_events FOR SELECT
      USING (
        auth.uid() = created_by
        OR (
          visibility = 'friends'
          AND EXISTS (
            SELECT 1
            FROM public.friendships f
            WHERE f.status = 'accepted'
              AND (
                (f.requester_id = auth.uid() AND f.receiver_id = run_events.created_by)
                OR (f.receiver_id = auth.uid() AND f.requester_id = run_events.created_by)
              )
          )
        )
      );
  END IF;
END;
$$;

CREATE TABLE IF NOT EXISTS public.live_run_sessions (
  id                UUID                  PRIMARY KEY DEFAULT gen_random_uuid(),
  source_type       public.live_run_source_type NOT NULL DEFAULT 'spontaneous',
  linked_event_id   UUID                  REFERENCES public.run_events(id) ON DELETE SET NULL,
  leader_user_id    UUID                  NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  visibility        public.run_visibility NOT NULL DEFAULT 'friends',
  mode              public.run_mode       NOT NULL,
  state             public.live_run_state NOT NULL DEFAULT 'live',
  started_at        TIMESTAMPTZ           NOT NULL,
  cooldown_started_at TIMESTAMPTZ,
  ended_at          TIMESTAMPTZ,
  last_activity_at  TIMESTAMPTZ           NOT NULL,
  max_ends_at       TIMESTAMPTZ           NOT NULL,
  created_at        TIMESTAMPTZ           NOT NULL DEFAULT NOW(),
  updated_at        TIMESTAMPTZ           NOT NULL DEFAULT NOW(),
  CONSTRAINT live_run_sessions_time_window CHECK (max_ends_at >= started_at)
);

ALTER TABLE public.jogging_sessions
  ADD COLUMN IF NOT EXISTS live_run_session_id UUID REFERENCES public.live_run_sessions(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_jogging_sessions_live_run_session_id
  ON public.jogging_sessions(live_run_session_id);

CREATE INDEX IF NOT EXISTS idx_live_run_sessions_leader_user_id
  ON public.live_run_sessions(leader_user_id);
CREATE INDEX IF NOT EXISTS idx_live_run_sessions_linked_event_id
  ON public.live_run_sessions(linked_event_id);
CREATE INDEX IF NOT EXISTS idx_live_run_sessions_state
  ON public.live_run_sessions(state);
CREATE INDEX IF NOT EXISTS idx_live_run_sessions_last_activity_at
  ON public.live_run_sessions(last_activity_at DESC);

DROP TRIGGER IF EXISTS trg_live_run_sessions_updated_at ON public.live_run_sessions;
CREATE TRIGGER trg_live_run_sessions_updated_at
  BEFORE UPDATE ON public.live_run_sessions
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

ALTER TABLE public.live_run_sessions ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'live_run_sessions'
      AND policyname = 'live_run_sessions_select_visible'
  ) THEN
    CREATE POLICY "live_run_sessions_select_visible"
      ON public.live_run_sessions FOR SELECT
      USING (
        auth.uid() = leader_user_id
        OR (
          visibility = 'friends'
          AND EXISTS (
            SELECT 1
            FROM public.friendships f
            WHERE f.status = 'accepted'
              AND (
                (f.requester_id = auth.uid() AND f.receiver_id = live_run_sessions.leader_user_id)
                OR (f.receiver_id = auth.uid() AND f.requester_id = live_run_sessions.leader_user_id)
              )
          )
        )
      );
  END IF;
END;
$$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'live_run_sessions'
      AND policyname = 'live_run_sessions_insert_leader'
  ) THEN
    CREATE POLICY "live_run_sessions_insert_leader"
      ON public.live_run_sessions FOR INSERT
      WITH CHECK (auth.uid() = leader_user_id);
  END IF;
END;
$$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'live_run_sessions'
      AND policyname = 'live_run_sessions_update_leader'
  ) THEN
    CREATE POLICY "live_run_sessions_update_leader"
      ON public.live_run_sessions FOR UPDATE
      USING (auth.uid() = leader_user_id)
      WITH CHECK (auth.uid() = leader_user_id);
  END IF;
END;
$$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'live_run_sessions'
      AND policyname = 'live_run_sessions_delete_leader'
  ) THEN
    CREATE POLICY "live_run_sessions_delete_leader"
      ON public.live_run_sessions FOR DELETE
      USING (auth.uid() = leader_user_id);
  END IF;
END;
$$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'run_events'
      AND policyname = 'run_events_insert_owner'
  ) THEN
    CREATE POLICY "run_events_insert_owner"
      ON public.run_events FOR INSERT
      WITH CHECK (auth.uid() = created_by);
  END IF;
END;
$$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'run_events'
      AND policyname = 'run_events_update_owner'
  ) THEN
    CREATE POLICY "run_events_update_owner"
      ON public.run_events FOR UPDATE
      USING (auth.uid() = created_by)
      WITH CHECK (
        auth.uid() = created_by
        OR EXISTS (
          SELECT 1
          FROM public.run_event_participants p
          WHERE p.event_id = id
            AND p.user_id = created_by
        )
      );
  END IF;
END;
$$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'run_events'
      AND policyname = 'run_events_delete_owner'
  ) THEN
    CREATE POLICY "run_events_delete_owner"
      ON public.run_events FOR DELETE
      USING (auth.uid() = created_by);
  END IF;
END;
$$;

CREATE TABLE IF NOT EXISTS public.run_event_participants (
  id          UUID                    PRIMARY KEY DEFAULT gen_random_uuid(),
  event_id    UUID                    NOT NULL REFERENCES public.run_events(id) ON DELETE CASCADE,
  user_id     UUID                    NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  role        public.run_event_role   NOT NULL DEFAULT 'member',
  status      public.run_participant_status NOT NULL DEFAULT 'invited',
  invited_by  UUID                    REFERENCES public.users(id) ON DELETE SET NULL,
  invited_at  TIMESTAMPTZ,
  responded_at TIMESTAMPTZ,
  checked_in_at TIMESTAMPTZ,
  created_at  TIMESTAMPTZ             NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMPTZ             NOT NULL DEFAULT NOW(),
  CONSTRAINT run_event_participants_unique_pair UNIQUE (event_id, user_id),
  CONSTRAINT run_event_participants_not_self_invited CHECK (invited_by IS NULL OR invited_by <> user_id)
);

CREATE INDEX IF NOT EXISTS idx_run_event_participants_event_id
  ON public.run_event_participants(event_id);
CREATE INDEX IF NOT EXISTS idx_run_event_participants_user_id
  ON public.run_event_participants(user_id);
CREATE INDEX IF NOT EXISTS idx_run_event_participants_status
  ON public.run_event_participants(status);

DROP TRIGGER IF EXISTS trg_run_event_participants_updated_at ON public.run_event_participants;
CREATE TRIGGER trg_run_event_participants_updated_at
  BEFORE UPDATE ON public.run_event_participants
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

ALTER TABLE public.run_event_participants ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'run_event_participants'
      AND policyname = 'run_event_participants_select_visible'
  ) THEN
    CREATE POLICY "run_event_participants_select_visible"
      ON public.run_event_participants FOR SELECT
      USING (
        auth.uid() = user_id
        OR EXISTS (
          SELECT 1
          FROM public.run_events e
          WHERE e.id = run_event_participants.event_id
            AND e.created_by = auth.uid()
        )
      );
  END IF;
END;
$$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'run_event_participants'
      AND policyname = 'run_event_participants_insert_visible'
  ) THEN
    CREATE POLICY "run_event_participants_insert_visible"
      ON public.run_event_participants FOR INSERT
      WITH CHECK (
        auth.uid() = user_id
        OR EXISTS (
          SELECT 1
          FROM public.run_events e
          WHERE e.id = event_id
            AND e.created_by = auth.uid()
        )
      );
  END IF;
END;
$$;

CREATE TABLE IF NOT EXISTS public.live_run_participants (
  id               UUID                               PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id       UUID                               NOT NULL REFERENCES public.live_run_sessions(id) ON DELETE CASCADE,
  user_id          UUID                               NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  status           public.live_run_participant_status NOT NULL DEFAULT 'joined',
  joined_at        TIMESTAMPTZ                        NOT NULL DEFAULT NOW(),
  became_active_at TIMESTAMPTZ,
  finished_at      TIMESTAMPTZ,
  left_at          TIMESTAMPTZ,
  is_leader        BOOLEAN                            NOT NULL DEFAULT FALSE,
  created_at       TIMESTAMPTZ                        NOT NULL DEFAULT NOW(),
  updated_at       TIMESTAMPTZ                        NOT NULL DEFAULT NOW(),
  CONSTRAINT live_run_participants_unique_pair UNIQUE (session_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_live_run_participants_session_id
  ON public.live_run_participants(session_id);
CREATE INDEX IF NOT EXISTS idx_live_run_participants_user_id
  ON public.live_run_participants(user_id);
CREATE INDEX IF NOT EXISTS idx_live_run_participants_status
  ON public.live_run_participants(status);
CREATE INDEX IF NOT EXISTS idx_live_run_participants_is_leader
  ON public.live_run_participants(session_id, is_leader);

DROP TRIGGER IF EXISTS trg_live_run_participants_updated_at ON public.live_run_participants;
CREATE TRIGGER trg_live_run_participants_updated_at
  BEFORE UPDATE ON public.live_run_participants
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

ALTER TABLE public.live_run_participants ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'live_run_participants'
      AND policyname = 'live_run_participants_select_visible'
  ) THEN
    CREATE POLICY "live_run_participants_select_visible"
      ON public.live_run_participants FOR SELECT
      USING (
        auth.uid() = user_id
        OR EXISTS (
          SELECT 1
          FROM public.live_run_sessions s
          WHERE s.id = live_run_participants.session_id
            AND s.leader_user_id = auth.uid()
        )
        OR EXISTS (
          SELECT 1
          FROM public.live_run_sessions s
          JOIN public.run_events e ON e.id = s.linked_event_id
          WHERE s.id = live_run_participants.session_id
            AND e.created_by = auth.uid()
        )
      );
  END IF;
END;
$$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'live_run_participants'
      AND policyname = 'live_run_participants_insert_visible'
  ) THEN
    CREATE POLICY "live_run_participants_insert_visible"
      ON public.live_run_participants FOR INSERT
      WITH CHECK (
        auth.uid() = user_id
        OR EXISTS (
          SELECT 1
          FROM public.live_run_sessions s
          WHERE s.id = session_id
            AND s.leader_user_id = auth.uid()
        )
      );
  END IF;
END;
$$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'live_run_participants'
      AND policyname = 'live_run_participants_update_visible'
  ) THEN
    CREATE POLICY "live_run_participants_update_visible"
      ON public.live_run_participants FOR UPDATE
      USING (
        auth.uid() = user_id
        OR EXISTS (
          SELECT 1
          FROM public.live_run_sessions s
          WHERE s.id = live_run_participants.session_id
            AND s.leader_user_id = auth.uid()
        )
      )
      WITH CHECK (
        auth.uid() = user_id
        OR EXISTS (
          SELECT 1
          FROM public.live_run_sessions s
          WHERE s.id = live_run_participants.session_id
            AND s.leader_user_id = auth.uid()
        )
      );
  END IF;
END;
$$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'live_run_participants'
      AND policyname = 'live_run_participants_delete_visible'
  ) THEN
    CREATE POLICY "live_run_participants_delete_visible"
      ON public.live_run_participants FOR DELETE
      USING (
        auth.uid() = user_id
        OR EXISTS (
          SELECT 1
          FROM public.live_run_sessions s
          WHERE s.id = live_run_participants.session_id
            AND s.leader_user_id = auth.uid()
        )
      );
  END IF;
END;
$$;

CREATE TABLE IF NOT EXISTS public.live_run_presence (
  id                       UUID                           PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id               UUID                           NOT NULL REFERENCES public.live_run_sessions(id) ON DELETE CASCADE,
  user_id                  UUID                           NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  presence_state           public.live_run_presence_state NOT NULL DEFAULT 'active',
  last_seen_at             TIMESTAMPTZ                    NOT NULL DEFAULT NOW(),
  current_distance_meters  REAL                           NOT NULL DEFAULT 0.0,
  current_duration_seconds INTEGER                        NOT NULL DEFAULT 0,
  current_pace_seconds_per_km INTEGER,
  current_latitude         DOUBLE PRECISION,
  current_longitude        DOUBLE PRECISION,
  updated_at               TIMESTAMPTZ                    NOT NULL DEFAULT NOW(),
  CONSTRAINT live_run_presence_unique_pair UNIQUE (session_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_live_run_presence_session_id
  ON public.live_run_presence(session_id);
CREATE INDEX IF NOT EXISTS idx_live_run_presence_user_id
  ON public.live_run_presence(user_id);
CREATE INDEX IF NOT EXISTS idx_live_run_presence_last_seen_at
  ON public.live_run_presence(last_seen_at DESC);

DROP TRIGGER IF EXISTS trg_live_run_presence_updated_at ON public.live_run_presence;
CREATE TRIGGER trg_live_run_presence_updated_at
  BEFORE UPDATE ON public.live_run_presence
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

ALTER TABLE public.live_run_presence ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'live_run_presence'
      AND policyname = 'live_run_presence_select_visible'
  ) THEN
    CREATE POLICY "live_run_presence_select_visible"
      ON public.live_run_presence FOR SELECT
      USING (
        auth.uid() = user_id
        OR EXISTS (
          SELECT 1
          FROM public.live_run_sessions s
          WHERE s.id = live_run_presence.session_id
            AND s.leader_user_id = auth.uid()
        )
        OR EXISTS (
          SELECT 1
          FROM public.live_run_participants p
          WHERE p.session_id = live_run_presence.session_id
            AND p.user_id = auth.uid()
        )
      );
  END IF;
END;
$$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'live_run_presence'
      AND policyname = 'live_run_presence_insert_visible'
  ) THEN
    CREATE POLICY "live_run_presence_insert_visible"
      ON public.live_run_presence FOR INSERT
      WITH CHECK (
        auth.uid() = user_id
        OR EXISTS (
          SELECT 1
          FROM public.live_run_sessions s
          WHERE s.id = session_id
            AND s.leader_user_id = auth.uid()
        )
      );
  END IF;
END;
$$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'live_run_presence'
      AND policyname = 'live_run_presence_update_visible'
  ) THEN
    CREATE POLICY "live_run_presence_update_visible"
      ON public.live_run_presence FOR UPDATE
      USING (
        auth.uid() = user_id
        OR EXISTS (
          SELECT 1
          FROM public.live_run_sessions s
          WHERE s.id = live_run_presence.session_id
            AND s.leader_user_id = auth.uid()
        )
      )
      WITH CHECK (
        auth.uid() = user_id
        OR EXISTS (
          SELECT 1
          FROM public.live_run_sessions s
          WHERE s.id = live_run_presence.session_id
            AND s.leader_user_id = auth.uid()
        )
      );
  END IF;
END;
$$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'live_run_presence'
      AND policyname = 'live_run_presence_delete_visible'
  ) THEN
    CREATE POLICY "live_run_presence_delete_visible"
      ON public.live_run_presence FOR DELETE
      USING (
        auth.uid() = user_id
        OR EXISTS (
          SELECT 1
          FROM public.live_run_sessions s
          WHERE s.id = live_run_presence.session_id
            AND s.leader_user_id = auth.uid()
        )
      );
  END IF;
END;
$$;

CREATE TABLE IF NOT EXISTS public.run_xp_awards (
  id               UUID                    PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id          UUID                    NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  session_id       UUID                    NOT NULL REFERENCES public.live_run_sessions(id) ON DELETE CASCADE,
  base_xp          BIGINT                  NOT NULL DEFAULT 0,
  bonus_type       public.run_xp_bonus_type NOT NULL DEFAULT 'solo',
  bonus_multiplier NUMERIC(4,2)            NOT NULL DEFAULT 1.00,
  bonus_xp         BIGINT                  NOT NULL DEFAULT 0,
  total_xp_awarded BIGINT                  NOT NULL DEFAULT 0,
  awarded_at       TIMESTAMPTZ             NOT NULL DEFAULT NOW(),
  created_at       TIMESTAMPTZ             NOT NULL DEFAULT NOW(),
  updated_at       TIMESTAMPTZ             NOT NULL DEFAULT NOW(),
  CONSTRAINT run_xp_awards_unique_pair UNIQUE (user_id, session_id),
  CONSTRAINT run_xp_awards_multiplier_check CHECK (bonus_multiplier >= 1.00),
  CONSTRAINT run_xp_awards_totals_check CHECK (base_xp >= 0 AND bonus_xp >= 0 AND total_xp_awarded >= base_xp)
);

CREATE INDEX IF NOT EXISTS idx_run_xp_awards_user_id
  ON public.run_xp_awards(user_id);
CREATE INDEX IF NOT EXISTS idx_run_xp_awards_session_id
  ON public.run_xp_awards(session_id);

DROP TRIGGER IF EXISTS trg_run_xp_awards_updated_at ON public.run_xp_awards;
CREATE TRIGGER trg_run_xp_awards_updated_at
  BEFORE UPDATE ON public.run_xp_awards
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

ALTER TABLE public.run_xp_awards ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'run_xp_awards'
      AND policyname = 'run_xp_awards_select_visible'
  ) THEN
    CREATE POLICY "run_xp_awards_select_visible"
      ON public.run_xp_awards FOR SELECT
      USING (
        auth.uid() = user_id
        OR EXISTS (
          SELECT 1
          FROM public.live_run_sessions s
          WHERE s.id = run_xp_awards.session_id
            AND s.leader_user_id = auth.uid()
        )
        OR EXISTS (
          SELECT 1
          FROM public.live_run_participants p
          WHERE p.session_id = run_xp_awards.session_id
            AND p.user_id = auth.uid()
        )
      );
  END IF;
END;
$$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'run_xp_awards'
      AND policyname = 'run_xp_awards_insert_visible'
  ) THEN
    CREATE POLICY "run_xp_awards_insert_visible"
      ON public.run_xp_awards FOR INSERT
      WITH CHECK (
        auth.uid() = user_id
        OR EXISTS (
          SELECT 1
          FROM public.live_run_sessions s
          WHERE s.id = session_id
            AND s.leader_user_id = auth.uid()
        )
      );
  END IF;
END;
$$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'run_xp_awards'
      AND policyname = 'run_xp_awards_update_visible'
  ) THEN
    CREATE POLICY "run_xp_awards_update_visible"
      ON public.run_xp_awards FOR UPDATE
      USING (
        auth.uid() = user_id
        OR EXISTS (
          SELECT 1
          FROM public.live_run_sessions s
          WHERE s.id = run_xp_awards.session_id
            AND s.leader_user_id = auth.uid()
        )
      )
      WITH CHECK (
        auth.uid() = user_id
        OR EXISTS (
          SELECT 1
          FROM public.live_run_sessions s
          WHERE s.id = run_xp_awards.session_id
            AND s.leader_user_id = auth.uid()
        )
      );
  END IF;
END;
$$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'run_xp_awards'
      AND policyname = 'run_xp_awards_delete_visible'
  ) THEN
    CREATE POLICY "run_xp_awards_delete_visible"
      ON public.run_xp_awards FOR DELETE
      USING (
        auth.uid() = user_id
        OR EXISTS (
          SELECT 1
          FROM public.live_run_sessions s
          WHERE s.id = run_xp_awards.session_id
            AND s.leader_user_id = auth.uid()
        )
      );
  END IF;
END;
$$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'live_run_sessions'
      AND policyname = 'live_run_sessions_select_participant'
  ) THEN
    CREATE POLICY "live_run_sessions_select_participant"
      ON public.live_run_sessions FOR SELECT
      USING (
        EXISTS (
          SELECT 1
          FROM public.live_run_participants lrp
          WHERE lrp.session_id = live_run_sessions.id
            AND lrp.user_id = auth.uid()
        )
      );
  END IF;
END;
$$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'run_event_participants'
      AND policyname = 'run_event_participants_update_visible'
  ) THEN
    CREATE POLICY "run_event_participants_update_visible"
      ON public.run_event_participants FOR UPDATE
      USING (
        auth.uid() = user_id
        OR EXISTS (
          SELECT 1
          FROM public.run_events e
          WHERE e.id = event_id
            AND e.created_by = auth.uid()
        )
      )
      WITH CHECK (
        auth.uid() = user_id
        OR EXISTS (
          SELECT 1
          FROM public.run_events e
          WHERE e.id = event_id
            AND e.created_by = auth.uid()
        )
      );
  END IF;
END;
$$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'run_event_participants'
      AND policyname = 'run_event_participants_delete_visible'
  ) THEN
    CREATE POLICY "run_event_participants_delete_visible"
      ON public.run_event_participants FOR DELETE
      USING (
        auth.uid() = user_id
        OR EXISTS (
          SELECT 1
          FROM public.run_events e
          WHERE e.id = event_id
            AND e.created_by = auth.uid()
        )
      );
  END IF;
END;
$$;
