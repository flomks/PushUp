-- Migration 014: Add daily_credit_snapshots table for historical tracking.
--
-- One row per user per day, written at each daily reset (03:00 local time).
-- Enables weekly/monthly charts showing earned vs spent credit over time.

CREATE TABLE IF NOT EXISTS public.daily_credit_snapshots (
    id                    UUID        NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id               UUID        NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    date                  DATE        NOT NULL,
    earned_seconds        BIGINT      NOT NULL DEFAULT 0,
    spent_seconds         BIGINT      NOT NULL DEFAULT 0,
    carry_over_seconds    BIGINT      NOT NULL DEFAULT 0,
    workout_earned_seconds BIGINT     NOT NULL DEFAULT 0,
    created_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT uq_daily_credit_snapshot_user_date UNIQUE (user_id, date)
);

-- Index for efficient date-range queries per user.
CREATE INDEX IF NOT EXISTS idx_daily_credit_snapshots_user_date
    ON public.daily_credit_snapshots (user_id, date);

-- Comments
COMMENT ON TABLE public.daily_credit_snapshots IS
    'Historical record of daily credit balance, written at each daily reset (03:00 local time).';

COMMENT ON COLUMN public.daily_credit_snapshots.earned_seconds IS
    'Total daily budget that was available (carry-over + workout earnings).';

COMMENT ON COLUMN public.daily_credit_snapshots.spent_seconds IS
    'Credits consumed as screen time during this day.';

COMMENT ON COLUMN public.daily_credit_snapshots.carry_over_seconds IS
    'Credits carried over from the previous day (20% rule + 100% late-night).';

COMMENT ON COLUMN public.daily_credit_snapshots.workout_earned_seconds IS
    'Credits earned from workouts during this day.';

-- RLS: users can only read their own snapshots
ALTER TABLE public.daily_credit_snapshots ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can read own snapshots"
    ON public.daily_credit_snapshots
    FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own snapshots"
    ON public.daily_credit_snapshots
    FOR INSERT
    WITH CHECK (auth.uid() = user_id);
