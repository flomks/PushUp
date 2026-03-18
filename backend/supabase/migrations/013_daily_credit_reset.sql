-- Migration 013: Add daily credit reset fields to time_credits table.
--
-- These fields support the daily reset with carry-over mechanism:
-- - daily_earned_seconds: credits available in the current daily period
-- - daily_spent_seconds: credits spent in the current daily period
-- - last_reset_at: timestamp of the most recent daily reset (03:00 local time)
--
-- Existing rows are backfilled with the current available balance so users
-- see the same credit they had before the migration.

-- Add new columns
ALTER TABLE public.time_credits
    ADD COLUMN IF NOT EXISTS daily_earned_seconds BIGINT NOT NULL DEFAULT 0;

ALTER TABLE public.time_credits
    ADD COLUMN IF NOT EXISTS daily_spent_seconds BIGINT NOT NULL DEFAULT 0;

ALTER TABLE public.time_credits
    ADD COLUMN IF NOT EXISTS last_reset_at TIMESTAMPTZ;

-- Backfill: set daily_earned_seconds to the current available balance
UPDATE public.time_credits
SET daily_earned_seconds = GREATEST(0, total_earned_seconds - total_spent_seconds);

-- Add comments
COMMENT ON COLUMN public.time_credits.daily_earned_seconds IS
    'Credits available in the current daily period (earned + carry-over from previous day).';

COMMENT ON COLUMN public.time_credits.daily_spent_seconds IS
    'Credits spent in the current daily period. Reset to 0 at daily reset.';

COMMENT ON COLUMN public.time_credits.last_reset_at IS
    'Timestamp of the most recent daily reset (03:00 local device time). NULL for legacy records.';
