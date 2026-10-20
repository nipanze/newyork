-- Nipanze professional tags patch
-- Paste this into Supabase SQL editor.
--
-- Adds profile metadata for preferred bank/deposit bank, bank-agent status,
-- and public professional tags for banks, forex exchange companies, SACCOs,
-- and companies. Tag fields are only exposed to active Pro users.

BEGIN;

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS preferred_bank TEXT,
  ADD COLUMN IF NOT EXISTS institution_type TEXT,
  ADD COLUMN IF NOT EXISTS is_bank_agent BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS show_professional_tag BOOLEAN NOT NULL DEFAULT TRUE;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'profiles_institution_type_check'
      AND conrelid = 'public.profiles'::regclass
  ) THEN
    ALTER TABLE public.profiles
      ADD CONSTRAINT profiles_institution_type_check
      CHECK (
        institution_type IS NULL OR
        institution_type IN ('bank', 'forex_exchange', 'sacco', 'company')
      );
  END IF;
END $$;

COMMENT ON COLUMN public.profiles.preferred_bank IS
'User preferred bank/deposit bank. May also name the bank represented by a bank loan agent.';
COMMENT ON COLUMN public.profiles.institution_type IS
'Optional public professional account category: bank, forex_exchange, sacco, company.';
COMMENT ON COLUMN public.profiles.is_bank_agent IS
'True when the account holder is a bank loan agent.';
COMMENT ON COLUMN public.profiles.show_professional_tag IS
'User-controlled opt-out for showing professional tags in marketplace surfaces.';

-- Loan listings: add nullable tag fields for Pro viewers.
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
    ) THEN TRUE ELSE FALSE END                                               AS show_professional_tag
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

-- Lender offer history: add nullable tag fields for Pro viewers.
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
    ) THEN TRUE ELSE FALSE END                                               AS show_professional_tag
FROM  public.loan_offers lo
JOIN  public.loan_requests lr ON lr.id = lo.request_id
JOIN  public.countries c ON c.code = lr.country
JOIN  public.profiles p ON p.id = lo.lender_id
LEFT  JOIN public.kyc_verifications k ON k.user_id = lo.lender_id
LEFT  JOIN public.trust_aggregates ta ON ta.user_id = lo.lender_id
LEFT  JOIN public.contact_reveals cr ON cr.offer_id = lo.id;

-- Changing RETURNS TABLE requires dropping the old function signature first.
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
'Participant-scoped loan bid book. Exact terms are visible only to listing owners and offer-makers. Professional tag fields are returned only to active Pro users and only when the offer-maker opted in.';

-- Forex marketplace/tag support. These statements require the forex schema
-- from sql/patch_schema_v6.sql to already exist.
CREATE OR REPLACE VIEW public.v_forex_listings AS
SELECT
    fr.id                                                                     AS request_id,
    fr.currency_held,
    fr.currency_needed,
    fr.amount,
    fr.country,
    fr.settlement_preference,
    fr.is_urgent,
    fr.preferred_rate,
    fr.terms_locked_at,
    fr.status,
    fr.number_of_offers,
    CASE
        WHEN fr.number_of_offers = 0 THEN 'low'
        WHEN fr.number_of_offers <= 2 THEN 'medium'
        ELSE 'high'
    END                                                                       AS rate_coverage_tier,
    fr.listed_at,
    fr.expires_at,
    k.status                                                                  AS kyc_status,
    ta.rating_avg                                                             AS trust_rating_avg,
    COALESCE(ta.review_count, 0)                                              AS trust_review_count,
    COALESCE(ta.completed_deals_count, 0)                                     AS trust_completed_deals_count,
    COALESCE(ta.is_repeat_participant, FALSE)                                AS trust_is_repeat_participant,
    (p.phone_verified_at IS NOT NULL)                                        AS trust_phone_verified,
    ta.response_time_bucket                                                   AS trust_response_time_bucket,
    (k.status = 'approved')                                                   AS trust_is_verified,
    GREATEST(fr.expires_at - NOW(), INTERVAL '0')                            AS time_remaining,
    (fr.expires_at < NOW() + INTERVAL '24 hours')                            AS closing_soon_24h,
    (fr.expires_at < NOW() + INTERVAL '6 hours')                             AS closing_soon_6h,
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
    ) THEN TRUE ELSE FALSE END                                               AS show_professional_tag
FROM  public.forex_requests fr
JOIN  public.profiles p ON p.id = fr.requester_id
LEFT  JOIN public.kyc_verifications k ON k.user_id = fr.requester_id
LEFT  JOIN public.trust_aggregates ta ON ta.user_id = fr.requester_id
WHERE fr.status = 'active'
  AND (
    auth.uid() IS NULL OR fr.requester_id <> auth.uid()
  )
  AND (
    auth.uid() IS NULL OR NOT EXISTS (
      SELECT 1 FROM public.forex_offers fo
      WHERE fo.request_id = fr.id
        AND fo.offer_maker_id = auth.uid()
        AND fo.status IN ('pending', 'accepted')
    )
  );

CREATE OR REPLACE VIEW public.v_forex_offers WITH (security_invoker = true) AS
SELECT
    fo.offer_maker_id,
    fo.id                                                                     AS offer_id,
    fo.request_id,
    fr.currency_held,
    fr.currency_needed,
    fr.amount                                                                 AS requested_amount,
    fr.country,
    fr.settlement_preference,
    fo.rate_offered,
    fo.amount_available,
    fo.terms,
    fo.terms_locked_at,
    fo.status                                                                 AS offer_status,
    fo.offered_at,
    fo.accepted_at,
    ta.rating_avg                                                             AS trust_rating_avg,
    COALESCE(ta.review_count, 0)                                              AS trust_review_count,
    COALESCE(ta.completed_deals_count, 0)                                     AS trust_completed_deals_count,
    COALESCE(ta.is_repeat_participant, FALSE)                                AS trust_is_repeat_participant,
    (p.phone_verified_at IS NOT NULL)                                        AS trust_phone_verified,
    ta.response_time_bucket                                                   AS trust_response_time_bucket,
    (k.status = 'approved')                                                   AS trust_is_verified,
    fcr.status                                                                AS reveal_status,
    fcr.revealed_at,
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
    ) THEN TRUE ELSE FALSE END                                               AS show_professional_tag
FROM  public.forex_offers fo
JOIN  public.forex_requests fr ON fr.id = fo.request_id
JOIN  public.profiles p ON p.id = fo.offer_maker_id
LEFT  JOIN public.kyc_verifications k ON k.user_id = fo.offer_maker_id
LEFT  JOIN public.trust_aggregates ta ON ta.user_id = fo.offer_maker_id
LEFT  JOIN public.forex_contact_reveals fcr ON fcr.offer_id = fo.id;

DROP FUNCTION IF EXISTS public.get_public_forex_offers(UUID);

CREATE FUNCTION public.get_public_forex_offers(p_request_id UUID)
RETURNS TABLE (
    id UUID,
    request_id UUID,
    offer_maker_id TEXT,
    rate_offered NUMERIC,
    amount_available BIGINT,
    terms TEXT,
    terms_locked_at TIMESTAMP,
    status TEXT,
    offered_at TIMESTAMP,
    accepted_at TIMESTAMP,
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

    SELECT fr.requester_id = auth.uid() INTO v_is_owner
    FROM public.forex_requests fr
    WHERE fr.id = p_request_id;

    SELECT EXISTS (
        SELECT 1 FROM public.forex_offers own
        WHERE own.request_id = p_request_id
          AND own.offer_maker_id = auth.uid()
          AND own.status IN ('pending', 'accepted')
    ) INTO v_is_offer_maker;

    IF NOT COALESCE(v_is_owner, FALSE) AND NOT COALESCE(v_is_offer_maker, FALSE) THEN
        RETURN;
    END IF;

    IF COALESCE(v_is_owner, FALSE) THEN
        RETURN QUERY
        SELECT
            fo.id,
            fo.request_id,
            ('public-offer-' || ROW_NUMBER() OVER (ORDER BY fo.offered_at ASC))::TEXT AS offer_maker_id,
            fo.rate_offered,
            fo.amount_available,
            fo.terms,
            fo.terms_locked_at,
            fo.status::TEXT,
            fo.offered_at,
            fo.accepted_at,
            CASE WHEN v_is_pro AND p.show_professional_tag THEN p.preferred_bank ELSE NULL END,
            CASE WHEN v_is_pro AND p.show_professional_tag THEN p.institution_type ELSE NULL END,
            CASE WHEN v_is_pro AND p.show_professional_tag THEN p.is_bank_agent ELSE FALSE END,
            CASE WHEN v_is_pro AND p.show_professional_tag THEN TRUE ELSE FALSE END
        FROM public.forex_offers fo
        JOIN public.forex_requests fr ON fr.id = fo.request_id
        JOIN public.profiles p ON p.id = fo.offer_maker_id
        WHERE fo.request_id = p_request_id
          AND fo.status = 'pending'
          AND (fr.status = 'active' OR fr.requester_id = auth.uid())
        ORDER BY fo.offered_at DESC;
        RETURN;
    END IF;

    RETURN QUERY
    SELECT
        fo.id,
        fo.request_id,
        ('your-offer')::TEXT AS offer_maker_id,
        fo.rate_offered,
        fo.amount_available,
        fo.terms,
        fo.terms_locked_at,
        fo.status::TEXT,
        fo.offered_at,
        fo.accepted_at,
        CASE WHEN v_is_pro AND p.show_professional_tag THEN p.preferred_bank ELSE NULL END,
        CASE WHEN v_is_pro AND p.show_professional_tag THEN p.institution_type ELSE NULL END,
        CASE WHEN v_is_pro AND p.show_professional_tag THEN p.is_bank_agent ELSE FALSE END,
        CASE WHEN v_is_pro AND p.show_professional_tag THEN TRUE ELSE FALSE END
    FROM public.forex_offers fo
    JOIN public.profiles p ON p.id = fo.offer_maker_id
    WHERE fo.request_id = p_request_id
      AND fo.offer_maker_id = auth.uid()
      AND fo.status IN ('pending', 'accepted');
END;
$$;

COMMENT ON FUNCTION public.get_public_forex_offers(UUID) IS
'Participant-scoped forex bid book. Exact terms are visible only to request owners and offer-makers. Professional tag fields are returned only to active Pro users and only when the offer-maker opted in.';

GRANT SELECT ON public.v_loan_listings TO authenticated, anon;
GRANT SELECT ON public.v_lender_offers TO authenticated, anon;
GRANT SELECT ON public.v_forex_listings TO authenticated, anon;
GRANT SELECT ON public.v_forex_offers TO authenticated, anon;
GRANT EXECUTE ON FUNCTION public.get_public_listing_offers(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_public_forex_offers(UUID) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.get_public_listing_offers(UUID) FROM anon;
REVOKE EXECUTE ON FUNCTION public.get_public_forex_offers(UUID) FROM anon;

COMMIT;
