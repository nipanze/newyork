-- Collateral selection for loan request flow.
-- Run this in the Supabase SQL editor for an existing cloud database.

BEGIN;

ALTER TABLE public.loan_requests
    ADD COLUMN IF NOT EXISTS has_collateral BOOLEAN NOT NULL DEFAULT FALSE,
    ADD COLUMN IF NOT EXISTS collateral_details TEXT,
    ADD COLUMN IF NOT EXISTS collateral_estimated_value BIGINT,
    ADD COLUMN IF NOT EXISTS collateral_location TEXT;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'chk_lr_collateral_value_positive'
          AND conrelid = 'public.loan_requests'::regclass
    ) THEN
        ALTER TABLE public.loan_requests
            ADD CONSTRAINT chk_lr_collateral_value_positive
            CHECK (
                collateral_estimated_value IS NULL
                OR collateral_estimated_value > 0
            );
    END IF;
END $$;

COMMENT ON COLUMN public.loan_requests.has_collateral IS
'Borrower-declared collateral choice. FALSE means No Collateral; TRUE means Secured.';
COMMENT ON COLUMN public.loan_requests.collateral_details IS
'Borrower-entered description of the collateral asset, shown as a marketplace risk signal.';
COMMENT ON COLUMN public.loan_requests.collateral_estimated_value IS
'Optional borrower-estimated collateral value in the listing currency.';
COMMENT ON COLUMN public.loan_requests.collateral_location IS
'Optional location of the collateral asset.';

CREATE OR REPLACE VIEW public.v_loan_listings AS
SELECT
    lr.id                                                                     AS request_id,
    lr.title,
    lr.purpose,
    lr.district,
    lr.country,
    c.currency_code,
    lr.duration_months,
    lr.requested_amount,
    lr.preferred_repayment_plan,
    lr.repayment_amount_per_period,
    lr.repayment_timeline,
    lr.suggested_interest_rate_pct,
    lr.suggested_late_fee_pct,
    lr.suggested_repayment_frequency,
    lr.suggested_installment_amount,
    lr.terms_locked_at,
    lr.status,
    lr.number_of_offers,
    CASE
        WHEN lr.number_of_offers = 0 THEN 'low'
        WHEN lr.number_of_offers <= 2 THEN 'medium'
        ELSE 'high'
    END                                                                       AS offer_coverage_tier,
    lr.listed_at,
    lr.expires_at,
    k.status                                                                  AS kyc_status,
    ta.rating_avg                                                             AS trust_rating_avg,
    COALESCE(ta.review_count, 0)                                              AS trust_review_count,
    COALESCE(ta.completed_deals_count, 0)                                     AS trust_completed_deals_count,
    COALESCE(ta.is_repeat_participant, FALSE)                                AS trust_is_repeat_participant,
    (p.phone_verified_at IS NOT NULL)                                        AS trust_phone_verified,
    ta.response_time_bucket                                                   AS trust_response_time_bucket,
    (k.status = 'approved')                                                   AS trust_is_verified,
    GREATEST(lr.expires_at - NOW(), INTERVAL '0')                            AS time_remaining,
    (lr.expires_at < NOW() + INTERVAL '24 hours')                            AS closing_soon_24h,
    (lr.expires_at < NOW() + INTERVAL '6 hours')                             AS closing_soon_6h,
    CASE WHEN p.show_professional_tag AND EXISTS (
      SELECT 1 FROM public.subscriptions s
      WHERE s.user_id = auth.uid() AND s.status = 'active' AND s.plan = 'pro'
    ) THEN p.preferred_bank ELSE NULL END                                    AS preferred_bank,
    CASE WHEN p.show_professional_tag AND EXISTS (
      SELECT 1 FROM public.subscriptions s
      WHERE s.user_id = auth.uid() AND s.status = 'active' AND s.plan = 'pro'
    ) THEN p.institution_type ELSE NULL END                                  AS institution_type,
    CASE WHEN p.show_professional_tag AND EXISTS (
      SELECT 1 FROM public.subscriptions s
      WHERE s.user_id = auth.uid() AND s.status = 'active' AND s.plan = 'pro'
    ) THEN p.is_bank_agent ELSE FALSE END                                    AS is_bank_agent,
    CASE WHEN p.show_professional_tag AND EXISTS (
      SELECT 1 FROM public.subscriptions s
      WHERE s.user_id = auth.uid() AND s.status = 'active' AND s.plan = 'pro'
    ) THEN TRUE ELSE FALSE END                                               AS show_professional_tag,
    CASE WHEN EXISTS (
      SELECT 1 FROM public.subscriptions s
      WHERE s.user_id = auth.uid() AND s.status = 'active' AND s.plan = 'pro'
    ) THEN lr.has_collateral ELSE FALSE END                                  AS has_collateral,
    CASE WHEN EXISTS (
      SELECT 1 FROM public.subscriptions s
      WHERE s.user_id = auth.uid() AND s.status = 'active' AND s.plan = 'pro'
    ) THEN lr.collateral_details ELSE NULL END                               AS collateral_details,
    CASE WHEN EXISTS (
      SELECT 1 FROM public.subscriptions s
      WHERE s.user_id = auth.uid() AND s.status = 'active' AND s.plan = 'pro'
    ) THEN lr.collateral_estimated_value ELSE NULL END                       AS collateral_estimated_value,
    CASE WHEN EXISTS (
      SELECT 1 FROM public.subscriptions s
      WHERE s.user_id = auth.uid() AND s.status = 'active' AND s.plan = 'pro'
    ) THEN lr.collateral_location ELSE NULL END                              AS collateral_location
FROM  public.loan_requests lr
JOIN  public.profiles p ON p.id = lr.borrower_id
JOIN  public.countries c ON c.code = lr.country
LEFT  JOIN public.kyc_verifications k ON k.user_id = lr.borrower_id
LEFT  JOIN public.trust_aggregates ta ON ta.user_id = lr.borrower_id
WHERE lr.status = 'active'
  AND (
    auth.uid() IS NULL OR lr.borrower_id <> auth.uid()
  )
  AND (
    auth.uid() IS NULL OR NOT EXISTS (
      SELECT 1 FROM public.loan_offers lo
      WHERE lo.request_id = lr.id
        AND lo.lender_id = auth.uid()
        AND lo.status IN ('pending', 'accepted')
    )
  );

GRANT SELECT ON public.v_loan_listings TO authenticated, anon;

COMMIT;
