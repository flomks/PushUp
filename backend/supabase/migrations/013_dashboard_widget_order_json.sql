-- Dashboard widget layout (JSON array of widget id strings), synced with the app like other user_settings fields.
ALTER TABLE public.user_settings
  ADD COLUMN IF NOT EXISTS dashboard_widget_order_json TEXT;

COMMENT ON COLUMN public.user_settings.dashboard_widget_order_json IS
  'JSON array of dashboard widget identifiers (e.g. ["timeCredit","dailyStats"]). NULL = use app default.';
