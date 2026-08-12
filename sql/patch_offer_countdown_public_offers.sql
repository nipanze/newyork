-- Expose loan offer expiry to listing-detail participants for countdown UI.
-- Run this in the Supabase SQL editor after professional tags are installed.

BEGIN;

DROP FUNCTION IF EXISTS public.get_public_listing_offers(UUID);

CREATE FUNCTION public.get_public_listing_offers(p_request_id UUID)
RETURNS TABLE (
    id UUID,
    request_id UUID,
    lender_id TEXT,
    offer_amount BIGINT,
    interest_rate_pct NUMERIC,
    late_fee_pct NUMERIC,
    repayment_frequency TEXT,
    installment_amount BIGINT,
    proposed_expectations TEXT,
    terms_locked_at TIMESTAMP,
    status TEXT,
    offered_at TIMESTAMP,
    accepted_at TIMESTAMP,
    expires_at TIMESTAMP,
    preferred_bank TEXT,
    institution_type TEXT,
    is_bank_agent BOOLEAN,
    show_professional_tag BOOLEAN
)
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = ''
AS $$
DECLARE
    v_is_owner BOOLEAN := FALSE;
    v_is_offer_maker BOOLEAN := FALSE;
    v_is_pro BOOLEAN := FALSE;
BEGIN
    SELECT EXISTS (
        SELECT 1 FROM public.subscriptions s
        WHERE s.user_id = auth.uid() AND s.status = 'active' AND s.plan = 'pro'
    ) INTO v_is_pro;

    SELECT lr.borrower_id = auth.uid() INTO v_is_owner
    FROM public.loan_requests lr
    WHERE lr.id = p_request_id;

    SELECT EXISTS (
        SELECT 1 FROM public.loan_offers own
        WHERE own.request_id = p_request_id
          AND own.lender_id = auth.uid()
          AND own.status IN ('pending', 'accepted')
    ) INTO v_is_offer_maker;

    IF NOT COALESCE(v_is_owner, FALSE) AND NOT COALESCE(v_is_offer_maker, FALSE) THEN
        RETURN;
    END IF;

    IF COALESCE(v_is_owner, FALSE) THEN
        RETURN QUERY
        SELECT
            lo.id,
            lo.request_id,
            ('public-offer-' || ROW_NUMBER() OVER (ORDER BY lo.offered_at ASC))::TEXT AS lender_id,
            lo.offer_amount,
            lo.interest_rate_pct,
            lo.late_fee_pct,
            lo.repayment_frequency::TEXT,
            lo.installment_amount,
            lo.proposed_expectations,
            lo.terms_locked_at,
            lo.status::TEXT,
            lo.offered_at,
            lo.accepted_at,
            lo.expires_at,
            CASE WHEN v_is_pro AND p.show_professional_tag THEN p.preferred_bank ELSE NULL END,
            CASE WHEN v_is_pro AND p.show_professional_tag THEN p.institution_type ELSE NULL END,
            CASE WHEN v_is_pro AND p.show_professional_tag THEN p.is_bank_agent ELSE FALSE END,
            CASE WHEN v_is_pro AND p.show_professional_tag THEN TRUE ELSE FALSE END
        FROM public.loan_offers lo
        JOIN public.loan_requests lr ON lr.id = lo.request_id
        JOIN public.profiles p ON p.id = lo.lender_id
        WHERE lo.request_id = p_request_id
          AND lo.status = 'pending'
          AND (lr.status = 'active' OR lr.borrower_id = auth.uid())
        ORDER BY lo.offered_at DESC;
        RETURN;
    END IF;

    RETURN QUERY
    SELECT
        lo.id,
        lo.request_id,
        ('your-offer')::TEXT AS lender_id,
        lo.offer_amount,
        lo.interest_rate_pct,
        lo.late_fee_pct,
        lo.repayment_frequency::TEXT,
        lo.installment_amount,
        lo.proposed_expectations,
        lo.terms_locked_at,
        lo.status::TEXT,
        lo.offered_at,
        lo.accepted_at,
        lo.expires_at,
        CASE WHEN v_is_pro AND p.show_professional_tag THEN p.preferred_bank ELSE NULL END,
        CASE WHEN v_is_pro AND p.show_professional_tag THEN p.institution_type ELSE NULL END,
        CASE WHEN v_is_pro AND p.show_professional_tag THEN p.is_bank_agent ELSE FALSE END,
        CASE WHEN v_is_pro AND p.show_professional_tag THEN TRUE ELSE FALSE END
    FROM public.loan_offers lo
    JOIN public.profiles p ON p.id = lo.lender_id
    WHERE lo.request_id = p_request_id
      AND lo.lender_id = auth.uid()
      AND lo.status IN ('pending', 'accepted');
END;
$$;

COMMENT ON FUNCTION public.get_public_listing_offers(UUID) IS
'Participant-scoped loan bid book. Exact terms and offer expiry are visible only to listing owners and offer-makers. Professional tag fields are returned only to active Pro users and only when the offer-maker opted in.';

GRANT EXECUTE ON FUNCTION public.get_public_listing_offers(UUID) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.get_public_listing_offers(UUID) FROM anon;

CREATE OR REPLACE VIEW public.v_lender_offers WITH (security_invoker = true) AS
SELECT
    lo.lender_id,
    lo.id                                                                     AS offer_id,
    lo.request_id,
    lr.title                                                                  AS listing_title,
    lr.purpose                                                                AS listing_purpose,
    lr.district,
    lr.country,
    c.currency_code,
    lr.duration_months,
    lr.requested_amount,
    lo.offer_amount,
    lo.interest_rate_pct,
    lo.late_fee_pct,
    lo.repayment_frequency,
    lo.installment_amount,
    lo.proposed_expectations,
    lo.terms_locked_at,
    lo.status                                                                 AS offer_status,
    lo.offered_at,
    lo.accepted_at,
    ta.rating_avg                                                             AS trust_rating_avg,
    COALESCE(ta.review_count, 0)                                              AS trust_review_count,
    COALESCE(ta.completed_deals_count, 0)                                     AS trust_completed_deals_count,
    COALESCE(ta.is_repeat_participant, FALSE)                                AS trust_is_repeat_participant,
    (p.phone_verified_at IS NOT NULL)                                        AS trust_phone_verified,
    ta.response_time_bucket                                                   AS trust_response_time_bucket,
    (k.status = 'approved')                                                   AS trust_is_verified,
    cr.status                                                                 AS reveal_status,
    cr.revealed_at,
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
    lo.expires_at
FROM  public.loan_offers lo
JOIN  public.loan_requests lr ON lr.id = lo.request_id
JOIN  public.countries c ON c.code = lr.country
JOIN  public.profiles p ON p.id = lo.lender_id
LEFT  JOIN public.kyc_verifications k ON k.user_id = lo.lender_id
LEFT  JOIN public.trust_aggregates ta ON ta.user_id = lo.lender_id
LEFT  JOIN public.contact_reveals cr ON cr.offer_id = lo.id;

GRANT SELECT ON public.v_lender_offers TO authenticated, anon;

COMMIT;
