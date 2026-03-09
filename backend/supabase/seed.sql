-- =============================================================================
-- seed.sql -- Test / Development Data for PushUp App
-- =============================================================================
-- WARNING: Run this ONLY in a development / staging Supabase project.
--          Never run against production.
--
-- How to run:
--   Option A (Supabase CLI):
--     supabase db reset          -- resets DB and applies migrations + seed
--
--   Option B (SQL Editor in Supabase Dashboard):
--     Paste this file into the SQL Editor and click "Run".
--
--   Option C (psql):
--     psql "$DATABASE_URL" -f backend/supabase/seed.sql
-- =============================================================================


-- =============================================================================
-- 1. SEED USERS
-- =============================================================================
-- These UUIDs are fixed so that foreign keys in the rest of the seed are stable.
-- In a real Supabase project the auth.users rows are created by Supabase Auth.
-- For local development we insert directly into public.users (bypassing auth).

INSERT INTO public.users (id, email, display_name, avatar_url, created_at, updated_at)
VALUES
  (
    '00000000-0000-0000-0000-000000000001',
    'alice@example.com',
    'Alice',
    NULL,
    NOW() - INTERVAL '30 days',
    NOW() - INTERVAL '30 days'
  ),
  (
    '00000000-0000-0000-0000-000000000002',
    'bob@example.com',
    'Bob',
    NULL,
    NOW() - INTERVAL '14 days',
    NOW() - INTERVAL '14 days'
  )
ON CONFLICT (id) DO NOTHING;


-- =============================================================================
-- 2. SEED USER SETTINGS
-- =============================================================================

INSERT INTO public.user_settings (
  user_id,
  push_ups_per_minute_credit,
  quality_multiplier_enabled,
  daily_credit_cap_seconds
)
VALUES
  -- Alice: default settings
  (
    '00000000-0000-0000-0000-000000000001',
    10,
    FALSE,
    NULL
  ),
  -- Bob: quality multiplier on, 30-minute daily cap
  (
    '00000000-0000-0000-0000-000000000002',
    10,
    TRUE,
    1800
  )
ON CONFLICT (user_id) DO NOTHING;


-- =============================================================================
-- 3. SEED TIME CREDITS
-- =============================================================================

INSERT INTO public.time_credits (
  user_id,
  total_earned_seconds,
  total_spent_seconds,
  updated_at
)
VALUES
  -- Alice: earned 25 min, spent 10 min -> 15 min available
  (
    '00000000-0000-0000-0000-000000000001',
    1500,
    600,
    NOW()
  ),
  -- Bob: earned 8 min, spent 0 -> 8 min available
  (
    '00000000-0000-0000-0000-000000000002',
    480,
    0,
    NOW()
  )
ON CONFLICT (user_id) DO NOTHING;


-- =============================================================================
-- 4. SEED WORKOUT SESSIONS
-- =============================================================================

INSERT INTO public.workout_sessions (
  id,
  user_id,
  started_at,
  ended_at,
  push_up_count,
  earned_time_credits,
  quality,
  created_at,
  updated_at
)
VALUES
  -- Alice: session 3 days ago, 25 push-ups, good quality
  (
    'aaaaaaaa-0000-0000-0000-000000000001',
    '00000000-0000-0000-0000-000000000001',
    NOW() - INTERVAL '3 days' + INTERVAL '7 hours',
    NOW() - INTERVAL '3 days' + INTERVAL '7 hours 8 minutes',
    25,
    150,   -- 25 / 10 * 60 = 150 seconds
    0.82,
    NOW() - INTERVAL '3 days',
    NOW() - INTERVAL '3 days'
  ),
  -- Alice: session 2 days ago, 30 push-ups, average quality
  (
    'aaaaaaaa-0000-0000-0000-000000000002',
    '00000000-0000-0000-0000-000000000001',
    NOW() - INTERVAL '2 days' + INTERVAL '8 hours',
    NOW() - INTERVAL '2 days' + INTERVAL '8 hours 10 minutes',
    30,
    180,   -- 30 / 10 * 60 = 180 seconds
    0.65,
    NOW() - INTERVAL '2 days',
    NOW() - INTERVAL '2 days'
  ),
  -- Alice: session today, 20 push-ups, still running (ended_at = NULL)
  (
    'aaaaaaaa-0000-0000-0000-000000000003',
    '00000000-0000-0000-0000-000000000001',
    NOW() - INTERVAL '5 minutes',
    NULL,
    20,
    0,
    0.70,
    NOW() - INTERVAL '5 minutes',
    NOW() - INTERVAL '5 minutes'
  ),
  -- Bob: session yesterday, 8 push-ups, low quality
  (
    'bbbbbbbb-0000-0000-0000-000000000001',
    '00000000-0000-0000-0000-000000000002',
    NOW() - INTERVAL '1 day' + INTERVAL '6 hours',
    NOW() - INTERVAL '1 day' + INTERVAL '6 hours 3 minutes',
    8,
    48,    -- 8 / 10 * 60 = 48 seconds
    0.45,
    NOW() - INTERVAL '1 day',
    NOW() - INTERVAL '1 day'
  )
ON CONFLICT (id) DO NOTHING;


-- =============================================================================
-- 5. SEED PUSH-UP RECORDS
-- =============================================================================
-- A few individual push-up records for Alice's first completed session.

INSERT INTO public.push_up_records (
  id,
  session_id,
  timestamp,
  duration_ms,
  depth_score,
  form_score,
  created_at
)
VALUES
  (
    gen_random_uuid(),
    'aaaaaaaa-0000-0000-0000-000000000001',
    NOW() - INTERVAL '3 days' + INTERVAL '7 hours 0 minutes 10 seconds',
    1200,
    0.85,
    0.80,
    NOW() - INTERVAL '3 days'
  ),
  (
    gen_random_uuid(),
    'aaaaaaaa-0000-0000-0000-000000000001',
    NOW() - INTERVAL '3 days' + INTERVAL '7 hours 0 minutes 22 seconds',
    1100,
    0.90,
    0.85,
    NOW() - INTERVAL '3 days'
  ),
  (
    gen_random_uuid(),
    'aaaaaaaa-0000-0000-0000-000000000001',
    NOW() - INTERVAL '3 days' + INTERVAL '7 hours 0 minutes 35 seconds',
    1300,
    0.75,
    0.78,
    NOW() - INTERVAL '3 days'
  ),
  (
    gen_random_uuid(),
    'aaaaaaaa-0000-0000-0000-000000000001',
    NOW() - INTERVAL '3 days' + INTERVAL '7 hours 0 minutes 48 seconds',
    1150,
    0.88,
    0.83,
    NOW() - INTERVAL '3 days'
  ),
  (
    gen_random_uuid(),
    'aaaaaaaa-0000-0000-0000-000000000001',
    NOW() - INTERVAL '3 days' + INTERVAL '7 hours 1 minute 2 seconds',
    1250,
    0.80,
    0.82,
    NOW() - INTERVAL '3 days'
  )
ON CONFLICT (id) DO NOTHING;


-- =============================================================================
-- 6. SEED FRIENDSHIPS
-- =============================================================================
-- Demonstrates all three friendship_status values using the two seed users
-- (Alice and Bob) plus the demo user created in migration 003.
--
-- Scenario:
--   Alice -> Bob   : accepted  (they are friends)
--   Demo  -> Alice : pending   (demo user sent Alice a request, not yet answered)
--   Bob   -> Demo  : declined  (Bob sent demo user a request, demo declined)

INSERT INTO public.friendships (id, requester_id, receiver_id, status, created_at, updated_at)
VALUES
  -- Alice and Bob are friends (Alice sent the request, Bob accepted)
  (
    'ffffffff-0000-0000-0000-000000000001',
    '00000000-0000-0000-0000-000000000001',  -- Alice (requester)
    '00000000-0000-0000-0000-000000000002',  -- Bob   (receiver)
    'accepted',
    NOW() - INTERVAL '10 days',
    NOW() - INTERVAL '9 days'
  ),
  -- Demo user sent Alice a friend request that is still pending
  (
    'ffffffff-0000-0000-0000-000000000002',
    '11111111-1111-1111-1111-111111111111',  -- Demo  (requester)
    '00000000-0000-0000-0000-000000000001',  -- Alice (receiver)
    'pending',
    NOW() - INTERVAL '2 days',
    NOW() - INTERVAL '2 days'
  ),
  -- Bob sent Demo a friend request that Demo declined
  (
    'ffffffff-0000-0000-0000-000000000003',
    '00000000-0000-0000-0000-000000000002',  -- Bob   (requester)
    '11111111-1111-1111-1111-111111111111',  -- Demo  (receiver)
    'declined',
    NOW() - INTERVAL '5 days',
    NOW() - INTERVAL '4 days'
  )
ON CONFLICT (id) DO NOTHING;


-- =============================================================================
-- END OF SEED
-- =============================================================================
