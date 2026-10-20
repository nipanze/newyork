-- Nipanze Admin Portal: Marketer / Referral Department
-- Additive patch. Keeps marketer rewards separate from P2P loan and forex funds.

CREATE TABLE IF NOT EXISTS public.referral_campaigns (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name TEXT NOT NULL,
    description TEXT,
    country TEXT REFERENCES public.countries(code),
    start_date DATE,
    end_date DATE,
    status TEXT NOT NULL DEFAULT 'draft'
        CONSTRAINT chk_referral_campaign_status CHECK (status IN ('draft', 'active', 'paused', 'ended', 'deactivated')),
    qualification_event TEXT NOT NULL DEFAULT 'verified_referral',
    reward_type TEXT NOT NULL DEFAULT 'fixed'
        CONSTRAINT chk_referral_campaign_reward_type CHECK (reward_type IN ('fixed', 'tiered', 'manual')),
    reward_amount BIGINT NOT NULL DEFAULT 0
        CONSTRAINT chk_referral_campaign_reward_amount CHECK (reward_amount >= 0),
    reward_currency TEXT NOT NULL DEFAULT 'UGX',
    max_reward_per_referral BIGINT,
    campaign_budget BIGINT,
    max_referrals INTEGER,
    eligible_plans TEXT[] NOT NULL DEFAULT ARRAY['free','lender','pro']::TEXT[],
    terms TEXT,
    created_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS public.referral_marketers (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    profile_id UUID NOT NULL UNIQUE REFERENCES public.profiles(id) ON DELETE CASCADE,
    referral_code TEXT NOT NULL UNIQUE,
    status TEXT NOT NULL DEFAULT 'active'
        CONSTRAINT chk_referral_marketer_status CHECK (status IN ('new', 'active', 'suspended', 'deactivated', 'under_review')),
    default_campaign_id UUID REFERENCES public.referral_campaigns(id) ON DELETE SET NULL,
    joined_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    last_activity_at TIMESTAMP,
    risk_status TEXT NOT NULL DEFAULT 'clear'
        CONSTRAINT chk_referral_marketer_risk_status CHECK (risk_status IN ('clear', 'review', 'flagged')),
    risk_reason TEXT,
    metadata JSONB NOT NULL DEFAULT '{}'::JSONB,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

ALTER TABLE public.referrals
    ADD COLUMN IF NOT EXISTS campaign_id UUID REFERENCES public.referral_campaigns(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS source TEXT,
    ADD COLUMN IF NOT EXISTS country TEXT REFERENCES public.countries(code),
    ADD COLUMN IF NOT EXISTS status TEXT NOT NULL DEFAULT 'registered'
        CONSTRAINT chk_referrals_status CHECK (status IN ('clicked', 'registered', 'verified', 'qualified', 'rejected', 'fraud_hold')),
    ADD COLUMN IF NOT EXISTS verified_at TIMESTAMP,
    ADD COLUMN IF NOT EXISTS qualifying_event TEXT,
    ADD COLUMN IF NOT EXISTS qualified_at TIMESTAMP,
    ADD COLUMN IF NOT EXISTS fraud_status TEXT NOT NULL DEFAULT 'clear'
        CONSTRAINT chk_referrals_fraud_status CHECK (fraud_status IN ('clear', 'review', 'flagged', 'cleared')),
    ADD COLUMN IF NOT EXISTS fraud_reason TEXT,
    ADD COLUMN IF NOT EXISTS metadata JSONB NOT NULL DEFAULT '{}'::JSONB;

CREATE TABLE IF NOT EXISTS public.referral_rewards (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    marketer_id UUID NOT NULL REFERENCES public.referral_marketers(id) ON DELETE CASCADE,
    referral_id UUID REFERENCES public.referrals(id) ON DELETE SET NULL,
    campaign_id UUID REFERENCES public.referral_campaigns(id) ON DELETE SET NULL,
    referred_user_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    reward_type TEXT NOT NULL DEFAULT 'fixed',
    amount BIGINT NOT NULL CONSTRAINT chk_referral_reward_amount CHECK (amount >= 0),
    currency TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'pending'
        CONSTRAINT chk_referral_reward_status CHECK (status IN ('pending', 'approved', 'rejected', 'paid', 'cancelled', 'fraud_hold')),
    reason TEXT,
    approved_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    approved_at TIMESTAMP,
    rejected_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    rejected_at TIMESTAMP,
    paid_at TIMESTAMP,
    campaign_reward_snapshot JSONB NOT NULL DEFAULT '{}'::JSONB,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS public.referral_payouts (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    marketer_id UUID NOT NULL REFERENCES public.referral_marketers(id) ON DELETE CASCADE,
    amount BIGINT NOT NULL CONSTRAINT chk_referral_payout_amount CHECK (amount >= 0),
    currency TEXT NOT NULL,
    payout_method TEXT,
    payout_destination_ref TEXT,
    status TEXT NOT NULL DEFAULT 'requested'
        CONSTRAINT chk_referral_payout_status CHECK (status IN ('requested', 'under_review', 'approved', 'processing', 'paid', 'failed', 'cancelled')),
    failure_reason TEXT,
    requested_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    approved_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    approved_at TIMESTAMP,
    completed_at TIMESTAMP,
    metadata JSONB NOT NULL DEFAULT '{}'::JSONB,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS public.referral_events (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    marketer_id UUID REFERENCES public.referral_marketers(id) ON DELETE SET NULL,
    referral_id UUID REFERENCES public.referrals(id) ON DELETE SET NULL,
    campaign_id UUID REFERENCES public.referral_campaigns(id) ON DELETE SET NULL,
    event_type TEXT NOT NULL,
    actor_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    metadata JSONB NOT NULL DEFAULT '{}'::JSONB,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_referral_marketers_profile ON public.referral_marketers(profile_id);
CREATE INDEX IF NOT EXISTS idx_referral_marketers_status ON public.referral_marketers(status);
CREATE INDEX IF NOT EXISTS idx_referral_marketers_campaign ON public.referral_marketers(default_campaign_id);
CREATE INDEX IF NOT EXISTS idx_referrals_referrer ON public.referrals(referrer_id);
CREATE INDEX IF NOT EXISTS idx_referrals_campaign ON public.referrals(campaign_id);
CREATE INDEX IF NOT EXISTS idx_referrals_status ON public.referrals(status);
CREATE INDEX IF NOT EXISTS idx_referral_rewards_marketer ON public.referral_rewards(marketer_id);
CREATE INDEX IF NOT EXISTS idx_referral_rewards_status ON public.referral_rewards(status);
CREATE INDEX IF NOT EXISTS idx_referral_payouts_marketer ON public.referral_payouts(marketer_id);
CREATE INDEX IF NOT EXISTS idx_referral_payouts_status ON public.referral_payouts(status);
CREATE INDEX IF NOT EXISTS idx_referral_events_referral ON public.referral_events(referral_id);

ALTER TABLE public.referral_campaigns ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.referral_marketers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.referral_rewards ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.referral_payouts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.referral_events ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "referral_campaigns: admin read" ON public.referral_campaigns;
CREATE POLICY "referral_campaigns: admin read" ON public.referral_campaigns
    FOR SELECT TO authenticated USING (private.is_admin());
DROP POLICY IF EXISTS "referral_campaigns: admin write" ON public.referral_campaigns;
CREATE POLICY "referral_campaigns: admin write" ON public.referral_campaigns
    FOR ALL TO authenticated USING (private.is_admin()) WITH CHECK (private.is_admin());

DROP POLICY IF EXISTS "referral_marketers: own or admin read" ON public.referral_marketers;
CREATE POLICY "referral_marketers: own or admin read" ON public.referral_marketers
    FOR SELECT TO authenticated USING (profile_id = auth.uid() OR private.is_admin());
DROP POLICY IF EXISTS "referral_marketers: admin write" ON public.referral_marketers;
CREATE POLICY "referral_marketers: admin write" ON public.referral_marketers
    FOR ALL TO authenticated USING (private.is_admin()) WITH CHECK (private.is_admin());

DROP POLICY IF EXISTS "referral_rewards: own or admin read" ON public.referral_rewards;
CREATE POLICY "referral_rewards: own or admin read" ON public.referral_rewards
    FOR SELECT TO authenticated USING (
        private.is_admin()
        OR EXISTS (
            SELECT 1 FROM public.referral_marketers rm
            WHERE rm.id = referral_rewards.marketer_id AND rm.profile_id = auth.uid()
        )
    );
DROP POLICY IF EXISTS "referral_rewards: admin write" ON public.referral_rewards;
CREATE POLICY "referral_rewards: admin write" ON public.referral_rewards
    FOR ALL TO authenticated USING (private.is_admin()) WITH CHECK (private.is_admin());

DROP POLICY IF EXISTS "referral_payouts: own or admin read" ON public.referral_payouts;
CREATE POLICY "referral_payouts: own or admin read" ON public.referral_payouts
    FOR SELECT TO authenticated USING (
        private.is_admin()
        OR EXISTS (
            SELECT 1 FROM public.referral_marketers rm
            WHERE rm.id = referral_payouts.marketer_id AND rm.profile_id = auth.uid()
        )
    );
DROP POLICY IF EXISTS "referral_payouts: admin write" ON public.referral_payouts;
CREATE POLICY "referral_payouts: admin write" ON public.referral_payouts
    FOR ALL TO authenticated USING (private.is_admin()) WITH CHECK (private.is_admin());

DROP POLICY IF EXISTS "referral_events: admin read" ON public.referral_events;
CREATE POLICY "referral_events: admin read" ON public.referral_events
    FOR SELECT TO authenticated USING (private.is_admin());
DROP POLICY IF EXISTS "referral_events: admin insert" ON public.referral_events;
CREATE POLICY "referral_events: admin insert" ON public.referral_events
    FOR INSERT TO authenticated WITH CHECK (private.is_admin());

COMMENT ON TABLE public.referral_rewards IS
'Nipanze marketing expense records only. These are never P2P loan funds, repayments, forex settlements, or platform revenue.';
COMMENT ON TABLE public.referral_payouts IS
'Marketer payout workflow for Nipanze-owned rewards. Built for future payment-provider integration and kept separate from transactions.';

CREATE OR REPLACE VIEW public.marketers AS
SELECT
    rm.id,
    rm.profile_id AS user_id,
    rm.referral_code AS marketer_code,
    rm.status,
    0::NUMERIC AS commission_rate,
    rm.joined_at,
    (
        SELECT COUNT(*)
        FROM public.referrals r
        WHERE r.referrer_id = rm.profile_id
    )::INTEGER AS total_referrals,
    (
        SELECT COUNT(*)
        FROM public.referrals r
        WHERE r.referrer_id = rm.profile_id
          AND r.status = 'qualified'
    )::INTEGER AS successful_referrals,
    (
        SELECT COALESCE(SUM(rr.amount), 0)
        FROM public.referral_rewards rr
        WHERE rr.marketer_id = rm.id
          AND rr.status = 'pending'
    )::BIGINT AS pending_rewards,
    (
        SELECT COALESCE(SUM(rr.amount), 0)
        FROM public.referral_rewards rr
        WHERE rr.marketer_id = rm.id
    )::BIGINT AS total_rewards,
    rm.updated_at
FROM public.referral_marketers rm;

COMMENT ON VIEW public.marketers IS
'Compatibility view for the client app. A marketer is still a normal profiles user with one referral_marketers row.';
GRANT SELECT ON public.marketers TO authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Demo marketer data
-- ---------------------------------------------------------------------------
-- These rows turn existing seeded Nipanze accounts into marketers. They do not
-- create a second login or a new account type. Test accounts keep using the
-- auth.users login from sql/seed.sql, normally with password Test1234!.

INSERT INTO public.referral_campaigns (
    id, name, description, country, start_date, end_date, status,
    qualification_event, reward_type, reward_amount, reward_currency,
    max_reward_per_referral, campaign_budget, max_referrals, eligible_plans,
    terms, created_by, created_at, updated_at
) VALUES
(
    'f0000000-0000-0000-0000-000000000001',
    'Uganda Launch Referrals',
    'Reward active marketers when referred users register and complete the configured launch qualification.',
    'UG',
    '2026-01-01',
    '2026-12-31',
    'active',
    'kyc_approved',
    'fixed',
    20000,
    'UGX',
    20000,
    5000000,
    500,
    ARRAY['free','lender','pro']::TEXT[],
    'Demo campaign for Uganda marketer testing. Reward is paid only after qualification review.',
    '10000000-0000-0000-0000-000000000015',
    '2026-01-01 08:00:00',
    '2026-01-01 08:00:00'
),
(
    'f0000000-0000-0000-0000-000000000002',
    'Kenya Launch Referrals',
    'Country-aware marketer rewards for Kenya launch testing.',
    'KE',
    '2026-02-01',
    '2026-12-31',
    'active',
    'verified_registration',
    'fixed',
    750,
    'KES',
    750,
    300000,
    400,
    ARRAY['free','lender','pro']::TEXT[],
    'Demo campaign for Kenya marketer testing. Currency stays KES.',
    '10000000-0000-0000-0000-000000000032',
    '2026-02-01 08:00:00',
    '2026-02-01 08:00:00'
)
ON CONFLICT (id) DO UPDATE SET
    name = EXCLUDED.name,
    description = EXCLUDED.description,
    country = EXCLUDED.country,
    status = EXCLUDED.status,
    qualification_event = EXCLUDED.qualification_event,
    reward_type = EXCLUDED.reward_type,
    reward_amount = EXCLUDED.reward_amount,
    reward_currency = EXCLUDED.reward_currency,
    max_reward_per_referral = EXCLUDED.max_reward_per_referral,
    campaign_budget = EXCLUDED.campaign_budget,
    max_referrals = EXCLUDED.max_referrals,
    eligible_plans = EXCLUDED.eligible_plans,
    terms = EXCLUDED.terms,
    updated_at = EXCLUDED.updated_at;

INSERT INTO public.referral_marketers (
    id, profile_id, referral_code, status, default_campaign_id,
    joined_at, last_activity_at, risk_status, risk_reason, metadata,
    created_at, updated_at
) VALUES
(
    'f1000000-0000-0000-0000-000000000001',
    '10000000-0000-0000-0000-000000000001',
    'NIP-DAVID',
    'active',
    'f0000000-0000-0000-0000-000000000001',
    '2026-01-05 09:00:00',
    '2026-02-08 16:20:00',
    'clear',
    NULL,
    '{"demo": true, "login_email": "david.mukasa@gmail.com"}'::JSONB,
    '2026-01-05 09:00:00',
    '2026-02-08 16:20:00'
),
(
    'f1000000-0000-0000-0000-000000000002',
    '10000000-0000-0000-0000-000000000003',
    'NIP-JAMES',
    'active',
    'f0000000-0000-0000-0000-000000000001',
    '2026-01-08 10:30:00',
    '2026-02-09 13:15:00',
    'review',
    'Higher than usual signup velocity in one district; demo review item.',
    '{"demo": true, "login_email": "james.okello@outlook.com"}'::JSONB,
    '2026-01-08 10:30:00',
    '2026-02-09 13:15:00'
),
(
    'f1000000-0000-0000-0000-000000000003',
    '10000000-0000-0000-0000-000000000018',
    'NIP-WANJIRU',
    'active',
    'f0000000-0000-0000-0000-000000000002',
    '2026-02-10 09:30:00',
    '2026-02-18 18:45:00',
    'clear',
    NULL,
    '{"demo": true, "login_email": "wanjiru.kamau@nipanze-ke.test"}'::JSONB,
    '2026-02-10 09:30:00',
    '2026-02-18 18:45:00'
),
(
    'f1000000-0000-0000-0000-000000000004',
    '10000000-0000-0000-0000-000000000017',
    'NIP-TESTUG',
    'new',
    'f0000000-0000-0000-0000-000000000001',
    '2026-02-06 11:00:00',
    '2026-02-06 11:00:00',
    'clear',
    NULL,
    '{"demo": true, "login_email": "test.user@gmail.com"}'::JSONB,
    '2026-02-06 11:00:00',
    '2026-02-06 11:00:00'
)
ON CONFLICT (profile_id) DO UPDATE SET
    referral_code = EXCLUDED.referral_code,
    status = EXCLUDED.status,
    default_campaign_id = EXCLUDED.default_campaign_id,
    joined_at = EXCLUDED.joined_at,
    last_activity_at = EXCLUDED.last_activity_at,
    risk_status = EXCLUDED.risk_status,
    risk_reason = EXCLUDED.risk_reason,
    metadata = EXCLUDED.metadata,
    updated_at = EXCLUDED.updated_at;

UPDATE public.referrals
SET campaign_id = 'f0000000-0000-0000-0000-000000000001',
    source = COALESCE(source, 'demo_seed'),
    country = COALESCE(country, 'UG'),
    status = CASE
        WHEN id IN ('e5000000-0000-0000-0000-000000000001', 'e5000000-0000-0000-0000-000000000003') THEN 'qualified'
        WHEN id = 'e5000000-0000-0000-0000-000000000004' THEN 'registered'
        ELSE status
    END,
    verified_at = CASE WHEN is_activated THEN COALESCE(verified_at, activated_at) ELSE verified_at END,
    qualifying_event = CASE
        WHEN id IN ('e5000000-0000-0000-0000-000000000001', 'e5000000-0000-0000-0000-000000000003') THEN 'kyc_approved'
        ELSE qualifying_event
    END,
    qualified_at = CASE
        WHEN id IN ('e5000000-0000-0000-0000-000000000001', 'e5000000-0000-0000-0000-000000000003') THEN COALESCE(qualified_at, activated_at)
        ELSE qualified_at
    END
WHERE id IN (
    'e5000000-0000-0000-0000-000000000001',
    'e5000000-0000-0000-0000-000000000003',
    'e5000000-0000-0000-0000-000000000004'
);

UPDATE public.referrals
SET campaign_id = 'f0000000-0000-0000-0000-000000000002',
    source = COALESCE(source, 'demo_seed'),
    country = COALESCE(country, 'KE'),
    status = 'qualified',
    verified_at = COALESCE(verified_at, activated_at),
    qualifying_event = 'verified_registration',
    qualified_at = COALESCE(qualified_at, activated_at)
WHERE id = 'e5000000-0000-0000-0000-000000000005';

INSERT INTO public.referral_rewards (
    id, marketer_id, referral_id, campaign_id, referred_user_id,
    reward_type, amount, currency, status, reason, approved_by,
    approved_at, paid_at, campaign_reward_snapshot, created_at, updated_at
) VALUES
(
    'f2000000-0000-0000-0000-000000000001',
    'f1000000-0000-0000-0000-000000000001',
    'e5000000-0000-0000-0000-000000000001',
    'f0000000-0000-0000-0000-000000000001',
    '10000000-0000-0000-0000-000000000011',
    'fixed',
    20000,
    'UGX',
    'paid',
    'Qualified after KYC approval.',
    '10000000-0000-0000-0000-000000000015',
    '2026-02-01 10:00:00',
    '2026-02-03 14:00:00',
    '{"campaign": "Uganda Launch Referrals", "amount": 20000, "currency": "UGX", "qualification_event": "kyc_approved"}'::JSONB,
    '2026-02-01 09:00:00',
    '2026-02-03 14:00:00'
),
(
    'f2000000-0000-0000-0000-000000000002',
    'f1000000-0000-0000-0000-000000000002',
    'e5000000-0000-0000-0000-000000000003',
    'f0000000-0000-0000-0000-000000000001',
    '10000000-0000-0000-0000-000000000013',
    'fixed',
    20000,
    'UGX',
    'pending',
    'Qualified referral awaiting reward approval.',
    NULL,
    NULL,
    NULL,
    '{"campaign": "Uganda Launch Referrals", "amount": 20000, "currency": "UGX", "qualification_event": "kyc_approved"}'::JSONB,
    '2026-02-04 09:00:00',
    '2026-02-04 09:00:00'
),
(
    'f2000000-0000-0000-0000-000000000003',
    'f1000000-0000-0000-0000-000000000003',
    'e5000000-0000-0000-0000-000000000005',
    'f0000000-0000-0000-0000-000000000002',
    '10000000-0000-0000-0000-000000000026',
    'fixed',
    750,
    'KES',
    'approved',
    'Kenya launch referral verified.',
    '10000000-0000-0000-0000-000000000032',
    '2026-02-18 15:30:00',
    NULL,
    '{"campaign": "Kenya Launch Referrals", "amount": 750, "currency": "KES", "qualification_event": "verified_registration"}'::JSONB,
    '2026-02-18 12:00:00',
    '2026-02-18 15:30:00'
)
ON CONFLICT (id) DO UPDATE SET
    marketer_id = EXCLUDED.marketer_id,
    referral_id = EXCLUDED.referral_id,
    campaign_id = EXCLUDED.campaign_id,
    referred_user_id = EXCLUDED.referred_user_id,
    reward_type = EXCLUDED.reward_type,
    amount = EXCLUDED.amount,
    currency = EXCLUDED.currency,
    status = EXCLUDED.status,
    reason = EXCLUDED.reason,
    approved_by = EXCLUDED.approved_by,
    approved_at = EXCLUDED.approved_at,
    paid_at = EXCLUDED.paid_at,
    campaign_reward_snapshot = EXCLUDED.campaign_reward_snapshot,
    updated_at = EXCLUDED.updated_at;

INSERT INTO public.referral_payouts (
    id, marketer_id, amount, currency, payout_method, payout_destination_ref,
    status, requested_at, approved_by, approved_at, completed_at,
    failure_reason, metadata, created_at, updated_at
) VALUES
(
    'f3000000-0000-0000-0000-000000000001',
    'f1000000-0000-0000-0000-000000000001',
    20000,
    'UGX',
    'mobile_money',
    '+256701234567',
    'paid',
    '2026-02-02 09:00:00',
    '10000000-0000-0000-0000-000000000015',
    '2026-02-02 11:00:00',
    '2026-02-03 14:00:00',
    NULL,
    '{"demo": true, "provider_ready": false}'::JSONB,
    '2026-02-02 09:00:00',
    '2026-02-03 14:00:00'
),
(
    'f3000000-0000-0000-0000-000000000002',
    'f1000000-0000-0000-0000-000000000003',
    750,
    'KES',
    'mobile_money',
    '+254710002466',
    'approved',
    '2026-02-19 09:00:00',
    '10000000-0000-0000-0000-000000000032',
    '2026-02-19 11:00:00',
    NULL,
    NULL,
    '{"demo": true, "provider_ready": false}'::JSONB,
    '2026-02-19 09:00:00',
    '2026-02-19 11:00:00'
)
ON CONFLICT (id) DO UPDATE SET
    marketer_id = EXCLUDED.marketer_id,
    amount = EXCLUDED.amount,
    currency = EXCLUDED.currency,
    payout_method = EXCLUDED.payout_method,
    payout_destination_ref = EXCLUDED.payout_destination_ref,
    status = EXCLUDED.status,
    requested_at = EXCLUDED.requested_at,
    approved_by = EXCLUDED.approved_by,
    approved_at = EXCLUDED.approved_at,
    completed_at = EXCLUDED.completed_at,
    failure_reason = EXCLUDED.failure_reason,
    metadata = EXCLUDED.metadata,
    updated_at = EXCLUDED.updated_at;

INSERT INTO public.referral_events (
    id, marketer_id, referral_id, campaign_id, event_type, actor_id, metadata, created_at
) VALUES
('f4000000-0000-0000-0000-000000000001', 'f1000000-0000-0000-0000-000000000001', 'e5000000-0000-0000-0000-000000000001', 'f0000000-0000-0000-0000-000000000001', 'referral_qualified', '10000000-0000-0000-0000-000000000015', '{"demo": true}'::JSONB, '2026-02-01 09:00:00'),
('f4000000-0000-0000-0000-000000000002', 'f1000000-0000-0000-0000-000000000002', 'e5000000-0000-0000-0000-000000000003', 'f0000000-0000-0000-0000-000000000001', 'referral_flagged_for_review', '10000000-0000-0000-0000-000000000015', '{"demo": true, "reason": "velocity review"}'::JSONB, '2026-02-04 09:30:00'),
('f4000000-0000-0000-0000-000000000003', 'f1000000-0000-0000-0000-000000000003', 'e5000000-0000-0000-0000-000000000005', 'f0000000-0000-0000-0000-000000000002', 'reward_approved', '10000000-0000-0000-0000-000000000032', '{"demo": true}'::JSONB, '2026-02-18 15:30:00')
ON CONFLICT (id) DO NOTHING;
