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
