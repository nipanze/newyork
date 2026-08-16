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
