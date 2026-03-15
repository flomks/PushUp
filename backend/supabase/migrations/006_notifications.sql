-- =============================================================================
-- Migration: 006_notifications.sql
-- Description: In-app notifications table for user events such as friend
--              requests, accepted friendships, etc.
-- Created: 2026-03-09
-- Depends on: 001_initial_schema.sql (public.users, set_updated_at function)
-- =============================================================================
--
-- HOW TO RUN (forward):
--   Option A (Supabase CLI):
--     supabase db push
--
--   Option B (Supabase Dashboard SQL Editor):
--     Paste this file and click "Run".
--
--   Option C (psql):
--     psql "$DATABASE_URL" -f backend/supabase/migrations/006_notifications.sql
--
-- HOW TO ROLL BACK:
--   Execute the "ROLLBACK" section at the bottom of this file.
-- =============================================================================


-- =============================================================================
-- FORWARD MIGRATION
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. ENUM TYPE: notification_type
--    Represents the kind of in-app notification.
--      friend_request  -- a user sent a friend request to the recipient
--      friend_accepted -- the recipient accepted a friend request
-- -----------------------------------------------------------------------------

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_type WHERE typname = 'notification_type'
  ) THEN
    CREATE TYPE public.notification_type AS ENUM (
      'friend_request',
      'friend_accepted'
    );
  END IF;
END;
$$;

COMMENT ON TYPE public.notification_type IS
  'Types of in-app notifications: friend_request (incoming request), '
  'friend_accepted (request was accepted).';


-- -----------------------------------------------------------------------------
-- 2. TABLE: notifications
--    One row per notification delivered to a user.
--    Notifications are soft-deleted by marking them as read (is_read = true).
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.notifications (
  id           UUID                      PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id      UUID                      NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  type         public.notification_type  NOT NULL,
  actor_id     UUID                      REFERENCES public.users(id) ON DELETE SET NULL,
  payload      JSONB                     NOT NULL DEFAULT '{}',
  is_read      BOOLEAN                   NOT NULL DEFAULT FALSE,
  created_at   TIMESTAMPTZ               NOT NULL DEFAULT NOW(),
  updated_at   TIMESTAMPTZ               NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE  public.notifications            IS 'In-app notifications delivered to users.';
COMMENT ON COLUMN public.notifications.id         IS 'Surrogate primary key (UUID v4).';
COMMENT ON COLUMN public.notifications.user_id    IS 'FK to users.id -- the notification recipient.';
COMMENT ON COLUMN public.notifications.type       IS 'Kind of notification (friend_request, friend_accepted, …).';
COMMENT ON COLUMN public.notifications.actor_id   IS 'FK to users.id -- the user who triggered the notification (nullable if actor deleted).';
COMMENT ON COLUMN public.notifications.payload    IS 'Arbitrary JSON metadata (e.g. friendship_id, message text).';
COMMENT ON COLUMN public.notifications.is_read    IS 'Whether the recipient has read/dismissed this notification.';
COMMENT ON COLUMN public.notifications.created_at IS 'Timestamp when the notification was created.';
COMMENT ON COLUMN public.notifications.updated_at IS 'Timestamp of the last update (auto-updated by trigger).';


-- -----------------------------------------------------------------------------
-- 3. INDEXES
-- -----------------------------------------------------------------------------

-- Most common query: "show all unread notifications for user X"
CREATE INDEX IF NOT EXISTS idx_notifications_user_id
  ON public.notifications(user_id);

-- Composite: user + read status (e.g. "my unread notifications")
CREATE INDEX IF NOT EXISTS idx_notifications_user_is_read
  ON public.notifications(user_id, is_read);

-- Composite: user + created_at for chronological listing
CREATE INDEX IF NOT EXISTS idx_notifications_user_created_at
  ON public.notifications(user_id, created_at DESC);


-- -----------------------------------------------------------------------------
-- 4. TRIGGER: auto-update updated_at on every row change
-- -----------------------------------------------------------------------------

CREATE TRIGGER trg_notifications_updated_at
  BEFORE UPDATE ON public.notifications
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


-- -----------------------------------------------------------------------------
-- 5. ROW LEVEL SECURITY (RLS)
--    Users may only see and manage their own notifications.
-- -----------------------------------------------------------------------------

ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;

-- SELECT: a user can only read their own notifications.
CREATE POLICY "notifications_select_own"
  ON public.notifications
  FOR SELECT
  USING (auth.uid() = user_id);

-- INSERT: only the backend service role inserts notifications on behalf of users.
--         Application code uses the service role key for inserts; regular users
--         cannot insert notifications directly.
--         (No INSERT policy for authenticated role -- service role bypasses RLS.)

-- UPDATE: a user can only mark their own notifications as read.
CREATE POLICY "notifications_update_own"
  ON public.notifications
  FOR UPDATE
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

-- DELETE: a user can delete their own notifications.
CREATE POLICY "notifications_delete_own"
  ON public.notifications
  FOR DELETE
  USING (auth.uid() = user_id);


-- =============================================================================
-- ROLLBACK
-- Execute this block to undo everything created by this migration.
-- =============================================================================

-- BEGIN;
--
-- -- Drop RLS policies
-- DROP POLICY IF EXISTS "notifications_select_own"  ON public.notifications;
-- DROP POLICY IF EXISTS "notifications_update_own"  ON public.notifications;
-- DROP POLICY IF EXISTS "notifications_delete_own"  ON public.notifications;
--
-- -- Drop trigger
-- DROP TRIGGER IF EXISTS trg_notifications_updated_at ON public.notifications;
--
-- -- Drop indexes
-- DROP INDEX IF EXISTS public.idx_notifications_user_id;
-- DROP INDEX IF EXISTS public.idx_notifications_user_is_read;
-- DROP INDEX IF EXISTS public.idx_notifications_user_created_at;
--
-- -- Drop table
-- DROP TABLE IF EXISTS public.notifications CASCADE;
--
-- -- Drop enum type
-- DROP TYPE IF EXISTS public.notification_type;
--
-- COMMIT;


-- =============================================================================
-- END OF MIGRATION 006
-- =============================================================================
