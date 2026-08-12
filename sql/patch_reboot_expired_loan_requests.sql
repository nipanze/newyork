-- Reboot expired loan requests for marketplace testing.
-- Run this in the Supabase SQL editor.
-- It reactivates expired loan requests and gives them 3 months from now.

BEGIN;

UPDATE public.loan_requests
SET
    status = 'active',
    listed_at = CURRENT_TIMESTAMP,
    expires_at = CURRENT_TIMESTAMP + INTERVAL '3 months',
    contracted_at = NULL,
    cancelled_at = NULL,
    updated_at = CURRENT_TIMESTAMP
WHERE (
        status = 'expired'
        OR (status = 'active' AND expires_at <= CURRENT_TIMESTAMP)
    )
  AND status NOT IN ('contracted', 'cancelled');

COMMIT;

