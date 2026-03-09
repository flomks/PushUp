-- =============================================================================
-- Migration: 004_friendships.sql
-- Description: Friends feature -- friendships table with status enum, indexes,
--              updated_at trigger, and Row Level Security policies.
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
--     psql "$DATABASE_URL" -f backend/supabase/migrations/004_friendships.sql
--
-- HOW TO ROLL BACK:
--   Execute the "ROLLBACK" section at the bottom of this file.
--   It drops all objects created here in reverse dependency order.
-- =============================================================================


-- =============================================================================
-- FORWARD MIGRATION
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. ENUM TYPE: friendship_status
--    Represents the lifecycle of a friend request.
--      pending  -- request sent, awaiting response
--      accepted -- both users are friends
--      declined -- receiver explicitly rejected the request
-- -----------------------------------------------------------------------------

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_type WHERE typname = 'friendship_status'
  ) THEN
    CREATE TYPE public.friendship_status AS ENUM (
      'pending',
      'accepted',
      'declined'
    );
  END IF;
END;
$$;

COMMENT ON TYPE public.friendship_status IS
  'Lifecycle states of a friendship: pending (awaiting response), '
  'accepted (friends), declined (request rejected).';


-- -----------------------------------------------------------------------------
-- 2. TABLE: friendships
--    One row per directed friend request.
--    The pair (requester_id, receiver_id) is unique -- only one active request
--    can exist between any two users at a time.
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.friendships (
  id           UUID               PRIMARY KEY DEFAULT gen_random_uuid(),
  requester_id UUID               NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  receiver_id  UUID               NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  status       public.friendship_status NOT NULL DEFAULT 'pending',
  created_at   TIMESTAMPTZ        NOT NULL DEFAULT NOW(),
  updated_at   TIMESTAMPTZ        NOT NULL DEFAULT NOW(),

  -- A user cannot send a friend request to themselves.
  CONSTRAINT friendships_no_self_reference CHECK (requester_id <> receiver_id),

  -- Only one request row may exist per ordered (requester, receiver) pair.
  -- If user A declines user B's request, B must delete the old row before
  -- re-sending (or the application handles re-send by updating status).
  CONSTRAINT friendships_unique_pair UNIQUE (requester_id, receiver_id)
);

COMMENT ON TABLE  public.friendships              IS 'Friend requests and accepted friendships between users.';
COMMENT ON COLUMN public.friendships.id           IS 'Surrogate primary key (UUID v4).';
COMMENT ON COLUMN public.friendships.requester_id IS 'FK to users.id -- the user who sent the friend request.';
COMMENT ON COLUMN public.friendships.receiver_id  IS 'FK to users.id -- the user who received the friend request.';
COMMENT ON COLUMN public.friendships.status       IS 'Current state of the friendship (pending / accepted / declined).';
COMMENT ON COLUMN public.friendships.created_at   IS 'Timestamp when the friend request was first sent.';
COMMENT ON COLUMN public.friendships.updated_at   IS 'Timestamp of the last status change (auto-updated by trigger).';


-- -----------------------------------------------------------------------------
-- 3. INDEXES
--    Optimise the two most common lookup patterns:
--      a) "Show all requests I sent"     -> filter by requester_id
--      b) "Show all requests I received" -> filter by receiver_id
--    The composite index on (requester_id, status) and (receiver_id, status)
--    also accelerates filtered queries such as "show my pending requests".
-- -----------------------------------------------------------------------------

-- Lookup by requester (e.g. "friends I added")
CREATE INDEX IF NOT EXISTS idx_friendships_requester_id
  ON public.friendships(requester_id);

-- Lookup by receiver (e.g. "incoming friend requests")
CREATE INDEX IF NOT EXISTS idx_friendships_receiver_id
  ON public.friendships(receiver_id);

-- Composite: requester + status (e.g. "my pending outgoing requests")
CREATE INDEX IF NOT EXISTS idx_friendships_requester_status
  ON public.friendships(requester_id, status);

-- Composite: receiver + status (e.g. "my pending incoming requests")
CREATE INDEX IF NOT EXISTS idx_friendships_receiver_status
  ON public.friendships(receiver_id, status);


-- -----------------------------------------------------------------------------
-- 4. TRIGGER: auto-update updated_at on every row change
--    Reuses the set_updated_at() function created in migration 001.
-- -----------------------------------------------------------------------------

CREATE TRIGGER trg_friendships_updated_at
  BEFORE UPDATE ON public.friendships
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


-- -----------------------------------------------------------------------------
-- 5. ROW LEVEL SECURITY (RLS)
--    Users may only see and manage friendship rows that involve themselves
--    (either as requester or receiver).
-- -----------------------------------------------------------------------------

ALTER TABLE public.friendships ENABLE ROW LEVEL SECURITY;

-- SELECT: a user can read any row where they are the requester or the receiver.
CREATE POLICY "friendships_select_own"
  ON public.friendships
  FOR SELECT
  USING (
    auth.uid() = requester_id OR
    auth.uid() = receiver_id
  );

-- INSERT: a user can only create a request where they are the requester.
--         The receiver_id must differ from the authenticated user (enforced by
--         the CHECK constraint as well, but the policy adds a second layer).
CREATE POLICY "friendships_insert_own"
  ON public.friendships
  FOR INSERT
  WITH CHECK (
    auth.uid() = requester_id AND
    auth.uid() <> receiver_id
  );

-- UPDATE: only the receiver may change the status (accept / decline).
--         The requester cannot alter the status after sending -- they must
--         DELETE the row to cancel the request.
CREATE POLICY "friendships_update_receiver"
  ON public.friendships
  FOR UPDATE
  USING (auth.uid() = receiver_id)
  WITH CHECK (auth.uid() = receiver_id);

-- DELETE: either party may remove the friendship row (cancel / unfriend).
CREATE POLICY "friendships_delete_own"
  ON public.friendships
  FOR DELETE
  USING (
    auth.uid() = requester_id OR
    auth.uid() = receiver_id
  );


-- =============================================================================
-- VERIFICATION QUERIES
-- Run these manually in the SQL Editor to confirm the setup is correct.
-- =============================================================================

-- Check table exists with correct columns:
-- SELECT column_name, data_type, is_nullable, column_default
-- FROM information_schema.columns
-- WHERE table_schema = 'public' AND table_name = 'friendships'
-- ORDER BY ordinal_position;

-- Check enum values:
-- SELECT enumlabel FROM pg_enum
-- JOIN pg_type ON pg_enum.enumtypid = pg_type.oid
-- WHERE pg_type.typname = 'friendship_status'
-- ORDER BY enumsortorder;

-- Check indexes:
-- SELECT indexname, indexdef
-- FROM pg_indexes
-- WHERE schemaname = 'public' AND tablename = 'friendships'
-- ORDER BY indexname;

-- Check RLS is enabled:
-- SELECT * FROM public.rls_status WHERE tablename = 'friendships';

-- Check policies:
-- SELECT * FROM public.policy_overview WHERE tablename = 'friendships';

-- Check trigger:
-- SELECT trigger_name, event_manipulation, action_timing
-- FROM information_schema.triggers
-- WHERE event_object_schema = 'public'
--   AND event_object_table  = 'friendships';


-- =============================================================================
-- ROLLBACK
-- Execute this block to undo everything created by this migration.
-- Run it in the Supabase SQL Editor or via psql.
-- =============================================================================

-- BEGIN;
--
-- -- Drop RLS policies
-- DROP POLICY IF EXISTS "friendships_select_own"       ON public.friendships;
-- DROP POLICY IF EXISTS "friendships_insert_own"       ON public.friendships;
-- DROP POLICY IF EXISTS "friendships_update_receiver"  ON public.friendships;
-- DROP POLICY IF EXISTS "friendships_delete_own"       ON public.friendships;
--
-- -- Drop trigger (function set_updated_at is shared -- do NOT drop it here)
-- DROP TRIGGER IF EXISTS trg_friendships_updated_at ON public.friendships;
--
-- -- Drop indexes (dropped automatically with the table, listed for clarity)
-- DROP INDEX IF EXISTS public.idx_friendships_requester_id;
-- DROP INDEX IF EXISTS public.idx_friendships_receiver_id;
-- DROP INDEX IF EXISTS public.idx_friendships_requester_status;
-- DROP INDEX IF EXISTS public.idx_friendships_receiver_status;
--
-- -- Drop table (CASCADE removes dependent objects such as indexes and triggers)
-- DROP TABLE IF EXISTS public.friendships CASCADE;
--
-- -- Drop enum type (must be dropped after the table that uses it)
-- DROP TYPE IF EXISTS public.friendship_status;
--
-- COMMIT;


-- =============================================================================
-- END OF MIGRATION 004
-- =============================================================================
