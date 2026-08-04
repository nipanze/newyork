-- ============================================
-- PATCH: Subscription Pricing Per Currency / Market
-- Allows admin to configure monthly subscription fees (lender, pro)
-- for every active or supported currency market.
-- ============================================

CREATE TABLE IF NOT EXISTS public.subscription_prices (
    id                 UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    country_code       TEXT NOT NULL REFERENCES public.countries(code) ON DELETE CASCADE,
    currency_code      TEXT NOT NULL,
    plan               public.subscription_plan_enum NOT NULL, -- 'lender', 'pro'
    price_amount       NUMERIC(12, 2) NOT NULL DEFAULT 0,
    price_minor_units  BIGINT NOT NULL DEFAULT 0,
    created_at         TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at         TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uidx_subscription_prices_country_plan UNIQUE (country_code, plan)
);

COMMENT ON TABLE public.subscription_prices IS
'Stores country/currency specific pricing for paid subscription plans (lender, pro). Admin managed.';

-- Indexes
CREATE INDEX IF NOT EXISTS idx_subscription_prices_country ON public.subscription_prices (country_code);

-- Updated_at trigger
CREATE OR REPLACE FUNCTION public.update_subscription_prices_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_subscription_prices_updated_at ON public.subscription_prices;
CREATE TRIGGER trg_subscription_prices_updated_at
    BEFORE UPDATE ON public.subscription_prices
    FOR EACH ROW
    EXECUTE FUNCTION public.update_subscription_prices_updated_at();

-- RLS Policies & Grants
ALTER TABLE public.subscription_prices ENABLE ROW LEVEL SECURITY;

-- Grants
GRANT ALL ON TABLE public.subscription_prices TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.subscription_prices TO authenticated;
GRANT SELECT ON TABLE public.subscription_prices TO anon;

DROP POLICY IF EXISTS "subscription_prices: public read" ON public.subscription_prices;
CREATE POLICY "subscription_prices: public read"
    ON public.subscription_prices FOR SELECT
    TO authenticated, anon
    USING (TRUE);

DROP POLICY IF EXISTS "subscription_prices: admin write" ON public.subscription_prices;
CREATE POLICY "subscription_prices: admin write"
    ON public.subscription_prices FOR ALL
    TO authenticated
    USING (private.is_admin());

-- Seed default pricing for supported EAC markets
INSERT INTO public.subscription_prices (country_code, currency_code, plan, price_amount, price_minor_units) VALUES
    ('UG', 'UGX', 'lender', 19900, 19900),
    ('UG', 'UGX', 'pro',    49900, 49900),
    ('KE', 'KES', 'lender', 690,   690),
    ('KE', 'KES', 'pro',    1790,  1790),
    ('TZ', 'TZS', 'lender', 12900, 12900),
    ('TZ', 'TZS', 'pro',    32900, 32900),
    ('RW', 'RWF', 'lender', 6500,  6500),
    ('RW', 'RWF', 'pro',    16500, 16500),
    ('BI', 'BIF', 'lender', 15000, 15000),
    ('BI', 'BIF', 'pro',    38000, 38000),
    ('SS', 'SSP', 'lender', 2500,  2500),
    ('SS', 'SSP', 'pro',    6500,  6500),
    ('CD', 'CDF', 'lender', 14000, 14000),
    ('CD', 'CDF', 'pro',    35000, 35000),
    ('SO', 'SOS', 'lender', 3000,  3000),
    ('SO', 'SOS', 'pro',    7500,  7500)
ON CONFLICT (country_code, plan) DO UPDATE SET
    price_amount = EXCLUDED.price_amount,
    price_minor_units = EXCLUDED.price_minor_units,
    currency_code = EXCLUDED.currency_code;
