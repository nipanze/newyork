-- Fix loan detail loading after a lender sends an offer.
-- Run this in the Supabase SQL editor.
--
-- v_loan_listings intentionally hides listings where the caller already has
-- a pending/accepted offer, so those listings disappear from the marketplace
-- feed. The detail screen still needs to load that request after offer submit,
-- so this detail-specific view keeps the same public/pro masking but does not
-- exclude participants.

BEGIN;

CREATE OR REPLACE VIEW public.v_loan_listing_details AS
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
    CASE
        WHEN auth.uid() = lr.borrower_id THEN lr.number_of_offers
        ELSE 0
    END                                                                       AS number_of_offers,
    CASE
        WHEN auth.uid() <> lr.borrower_id OR auth.uid() IS NULL THEN NULL
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
    CASE WHEN auth.uid() = lr.borrower_id OR EXISTS (
      SELECT 1 FROM public.subscriptions s
      WHERE s.user_id = auth.uid() AND s.status = 'active' AND s.plan = 'pro'
    ) THEN lr.has_collateral ELSE FALSE END                                  AS has_collateral,
    CASE WHEN auth.uid() = lr.borrower_id OR EXISTS (
      SELECT 1 FROM public.subscriptions s
      WHERE s.user_id = auth.uid() AND s.status = 'active' AND s.plan = 'pro'
    ) THEN lr.collateral_details ELSE NULL END                               AS collateral_details,
    CASE WHEN auth.uid() = lr.borrower_id OR EXISTS (
      SELECT 1 FROM public.subscriptions s
      WHERE s.user_id = auth.uid() AND s.status = 'active' AND s.plan = 'pro'
    ) THEN lr.collateral_estimated_value ELSE NULL END                       AS collateral_estimated_value,
    CASE WHEN auth.uid() = lr.borrower_id OR EXISTS (
      SELECT 1 FROM public.subscriptions s
      WHERE s.user_id = auth.uid() AND s.status = 'active' AND s.plan = 'pro'
    ) THEN lr.collateral_location ELSE NULL END                              AS collateral_location
FROM  public.loan_requests lr
JOIN  public.profiles p ON p.id = lr.borrower_id
JOIN  public.countries c ON c.code = lr.country
LEFT  JOIN public.kyc_verifications k ON k.user_id = lr.borrower_id
LEFT  JOIN public.trust_aggregates ta ON ta.user_id = lr.borrower_id
WHERE lr.status = 'active';

GRANT SELECT ON public.v_loan_listing_details TO authenticated, anon;

COMMIT;
