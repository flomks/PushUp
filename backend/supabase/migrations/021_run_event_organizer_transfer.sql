-- Migration 021: Allow planned run organizers to transfer event ownership
-- to another existing participant before leaving the event themselves.

DROP POLICY IF EXISTS "run_events_update_owner" ON public.run_events;

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
