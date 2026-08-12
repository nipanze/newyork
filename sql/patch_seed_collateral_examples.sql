-- Demo collateral data for existing cloud loan requests.
-- Run after sql/patch_collateral_selection.sql.
-- This makes a mixed marketplace: some requests are Secured, others have no collateral.

BEGIN;

-- Start from a clean mixed-demo baseline for active requests.
UPDATE public.loan_requests
SET
    has_collateral = FALSE,
    collateral_details = NULL,
    collateral_estimated_value = NULL,
    collateral_location = NULL,
    updated_at = CURRENT_TIMESTAMP
WHERE status = 'active';

WITH ranked AS (
    SELECT
        id,
        ROW_NUMBER() OVER (ORDER BY listed_at DESC, created_at DESC, id) AS rn
    FROM public.loan_requests
    WHERE status = 'active'
)
UPDATE public.loan_requests lr
SET
    has_collateral = TRUE,
    collateral_details = CASE (ranked.rn % 4)
        WHEN 1 THEN 'Land plot with local council ownership documents'
        WHEN 2 THEN 'Motorcycle used for delivery work'
        WHEN 3 THEN 'Shop electronics and inventory'
        ELSE 'Farming equipment and irrigation pump'
    END,
    collateral_estimated_value = CASE (ranked.rn % 4)
        WHEN 1 THEN 12000000
        WHEN 2 THEN 4500000
        WHEN 3 THEN 3000000
        ELSE 6500000
    END,
    collateral_location = CASE (ranked.rn % 4)
        WHEN 1 THEN lr.district
        WHEN 2 THEN lr.district
        WHEN 3 THEN lr.district
        ELSE lr.district
    END,
    updated_at = CURRENT_TIMESTAMP
FROM ranked
WHERE lr.id = ranked.id
  AND ranked.rn % 2 = 1;

COMMIT;
