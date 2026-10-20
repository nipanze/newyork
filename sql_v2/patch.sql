-- ============================================
-- NIPANZE Combined Database Patch
--
-- Apply after sql/schema.sql and sql/seed.sql for an existing database.
-- This file consolidates the former sql/patch_*.sql fragments so the sql/
-- directory keeps the three main database scripts: schema.sql, seed.sql,
-- and patch.sql.
--
-- Sections are intentionally ordered so later patches can depend on objects
-- created by earlier sections.
-- ============================================


-- ============================================================
-- BEGIN MERGED SECTION: fix_permissions_patch.sql
-- ============================================================

-- ============================================================
-- FIX SCHEMA & RPC PERMISSIONS FOR SUPABASE CLOUD
-- Run this script in your Supabase SQL Editor (https://app.supabase.com)
-- to resolve "permission denied for schema public" (42501)
-- ============================================================

-- 1. Grant USAGE on public schema to all API roles
GRANT USAGE ON SCHEMA public TO authenticated, anon, service_role;

-- 2. Grant table permissions
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO authenticated, service_role;
GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA public TO anon;

-- 3. Grant sequence permissions
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO authenticated, anon, service_role;

-- 4. Re-create check_phone_registered function with SECURITY DEFINER and grant execution
CREATE OR REPLACE FUNCTION public.check_phone_registered(p_phone TEXT)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_email TEXT;
    v_digits TEXT;
BEGIN
    v_digits := regexp_replace(p_phone, '[^\d]', '', 'g');

    SELECT au.email INTO v_email
    FROM auth.users au
    LEFT JOIN public.profiles p ON p.id = au.id
    WHERE p.phone = p_phone
       OR au.phone = p_phone
       OR au.email = p_phone
       OR (v_digits <> '' AND (au.email = v_digits || '@nipanze.test' OR p.phone = '+' || v_digits))
    LIMIT 1;

    RETURN v_email;
END;
$$;

GRANT EXECUTE ON FUNCTION public.check_phone_registered(TEXT) TO authenticated, anon, service_role;

-- 4b. Re-create handle_new_auth_user function with SECURITY DEFINER
CREATE OR REPLACE FUNCTION public.handle_new_auth_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_country TEXT;
    v_phone TEXT;
BEGIN
    v_country := UPPER(COALESCE(NEW.raw_user_meta_data->>'country_code', 'UG'));
    IF NOT EXISTS (SELECT 1 FROM public.countries WHERE code = v_country) THEN
        v_country := 'UG';
    END IF;

    v_phone := COALESCE(NEW.raw_user_meta_data->>'phone', NEW.phone);

    INSERT INTO public.profiles (
        id, full_name, phone, account_status, is_admin, country
    )
    VALUES (
        NEW.id,
        COALESCE(NEW.raw_user_meta_data->>'full_name', SPLIT_PART(NEW.email, '@', 1)),
        v_phone,
        'pending_verification',
        FALSE,
        v_country
    )
    ON CONFLICT (id) DO UPDATE SET
        full_name = EXCLUDED.full_name,
        phone = COALESCE(EXCLUDED.phone, public.profiles.phone),
        country = COALESCE(EXCLUDED.country, public.profiles.country);

    -- Auto confirm mock email users for phone sign ups
    IF NEW.email LIKE '%@nipanze.test' AND NEW.email_confirmed_at IS NULL THEN
        UPDATE auth.users SET email_confirmed_at = NOW() WHERE id = NEW.id;
    END IF;

    -- Every new user gets a free subscription (can browse marketplace and post requests)
    INSERT INTO public.subscriptions (user_id, plan, status, amount_minor_units)
    VALUES (NEW.id, 'free', 'active', 0)
    ON CONFLICT (user_id) WHERE status = 'active' DO NOTHING;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW
    EXECUTE FUNCTION public.handle_new_auth_user();

-- 5. Profiles RLS Policies (ensure anon & authenticated can insert/update profile rows)
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view own or public profiles" ON public.profiles;
CREATE POLICY "Users can view own or public profiles"
  ON public.profiles FOR SELECT
  USING (true);

DROP POLICY IF EXISTS "Users can insert own profile" ON public.profiles;
CREATE POLICY "Users can insert own profile"
  ON public.profiles FOR INSERT
  WITH CHECK (true);

DROP POLICY IF EXISTS "Users can update own profile" ON public.profiles;
CREATE POLICY "Users can update own profile"
  ON public.profiles FOR UPDATE
  USING (auth.uid() = id OR auth.uid() IS NOT NULL);

-- 6. Subscriptions RLS Policies (ensure authenticated users can insert and update their own subscription rows)
ALTER TABLE public.subscriptions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "subscriptions: own or admin read" ON public.subscriptions;
DROP POLICY IF EXISTS "subscriptions: own read" ON public.subscriptions;
CREATE POLICY "subscriptions: own or admin read"
  ON public.subscriptions FOR SELECT TO authenticated
  USING (auth.uid() = user_id OR (private.is_admin() IS NOT NULL AND private.is_admin()));

DROP POLICY IF EXISTS "subscriptions: own insert" ON public.subscriptions;
CREATE POLICY "subscriptions: own insert"
  ON public.subscriptions FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "subscriptions: own update" ON public.subscriptions;
CREATE POLICY "subscriptions: own update"
  ON public.subscriptions FOR UPDATE TO authenticated
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

-- ============================================================
-- END MERGED SECTION: fix_permissions_patch.sql
-- ============================================================


-- ============================================================
-- BEGIN MERGED SECTION: patch_schema_v6.sql
-- ============================================================

-- ============================================
-- NIPANZE — Patch v5.0 → v6.0
-- Paste into Supabase Cloud SQL Editor and run once, top to bottom.
-- Idempotent: safe to re-run (uses IF NOT EXISTS / ON CONFLICT / DO blocks
-- / CREATE OR REPLACE throughout). Written against the v5.0 schema.sql you
-- shared — every object below either ALTERs an existing v5.0 object or
-- CREATEs a genuinely new one; nothing from v5.0 is dropped.
--
-- What this patch does, matching README.md / BUILD_PLAN.md v6.0:
--   PART 1 — Multi-Market fix: retires the 8-country EAC list, adopts the
--            7-market list (UG/KE/TZ/RW/NG/ZA/EG), adds countries.forex_enabled,
--            adds the new `currencies` table (7 market currencies + USD),
--            adds system_settings.allow_foreign_currency_loans.
--   PART 2 — Forex module (Stage 4.7): forex_requests, forex_offers,
--            forex_agreements, forex_contact_reveals — mirroring the
--            existing loan_requests/loan_offers/agreements/contact_reveals
--            pattern exactly (locked bidding, selective transparency,
--            country-locked-at-insert, no country column on offers).
--   PART 3 — Trust & reviews extended to be module-agnostic: reviews gains
--            a nullable forex_contract_id sibling to contract_id;
--            recompute_trust_aggregates() now unions loan + forex
--            completed deals into ONE global aggregate per user.
--   PART 4 — Watchlist/notifications made forex-aware (nullable FK columns
--            added, nothing existing removed).
--   PART 5 — RLS, Realtime publication, and grants for every new object.
--
-- Safe to run against real data: PART 1 will NOT delete a retired EAC
-- country row if it's still referenced by an existing profile or listing —
-- it pauses it (is_active/forex_enabled = FALSE) instead and raises a
-- NOTICE so you can migrate that data first if needed.
-- ============================================


-- ============================================
-- PART 1 — MULTI-MARKET FIX (8-country EAC → 7-market)
-- ============================================

-- 1.1 countries.forex_enabled — independent gate from is_active (lending)
ALTER TABLE countries ADD COLUMN IF NOT EXISTS forex_enabled BOOLEAN NOT NULL DEFAULT FALSE;

COMMENT ON COLUMN countries.forex_enabled IS
'v6.0: independent gate from is_active. is_active controls LENDING availability in this
 market; forex_enabled controls FOREX availability. A market can go live for one without
 the other — see currencies.forex_trading_enabled for the additional per-currency gate.';

-- 1.2 Retire Burundi / South Sudan / DR Congo / Somalia (the old EAC-only
-- scope). Only deletes if nothing references them yet; otherwise pauses them.
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM profiles WHERE country IN ('BI','SS','CD','SO'))
       AND NOT EXISTS (SELECT 1 FROM loan_requests WHERE country IN ('BI','SS','CD','SO'))
    THEN
        DELETE FROM countries WHERE code IN ('BI','SS','CD','SO');
        RAISE NOTICE 'Removed retired EAC-only countries (BI, SS, CD, SO) — no existing data referenced them.';
    ELSE
        UPDATE countries SET is_active = FALSE, forex_enabled = FALSE WHERE code IN ('BI','SS','CD','SO');
        RAISE NOTICE 'BI/SS/CD/SO still referenced by existing profiles/listings — paused (is_active/forex_enabled = FALSE) instead of deleted. Migrate that data manually if you want them fully removed.';
    END IF;
END $$;

-- 1.3 Add the three new v6.0 markets — Nigeria, South Africa, Egypt
INSERT INTO countries (code, name, currency_code, phone_prefix, is_active, forex_enabled) VALUES
    ('NG', 'Nigeria',      'NGN', '+234', FALSE, FALSE),
    ('ZA', 'South Africa', 'ZAR', '+27',  FALSE, FALSE),
    ('EG', 'Egypt',        'EGP', '+20',  FALSE, FALSE)
ON CONFLICT (code) DO NOTHING;

-- Sanity: countries should now be exactly the 7-market v6.0 list
-- (UG active for lending; KE/TZ/RW/NG/ZA/EG inactive until each clears
-- its own Stage 6 launch review; forex_enabled FALSE for all 7 for now).

-- 1.4 New table: currencies (v6.0)
CREATE TABLE IF NOT EXISTS currencies (
    code                    TEXT PRIMARY KEY,          -- ISO 4217
    name                    TEXT NOT NULL,
    is_market_currency      BOOLEAN NOT NULL DEFAULT FALSE,
    market_country          TEXT REFERENCES countries(code),
    forex_trading_enabled   BOOLEAN NOT NULL DEFAULT FALSE,
    created_at              TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chk_cur_market_country CHECK (
        (is_market_currency = FALSE AND market_country IS NULL) OR
        (is_market_currency = TRUE  AND market_country IS NOT NULL)
    )
);

COMMENT ON TABLE currencies IS
'v6.0 reference table, decoupled from countries on purpose. A currency existing here
 (usable for loans, denominated amounts, subscription billing) does NOT imply it is cleared
 for forex trading — that is the separate forex_trading_enabled flag, which defaults to FALSE
 for every currency, including the 7 market currencies, until independently reviewed.';

INSERT INTO currencies (code, name, is_market_currency, market_country, forex_trading_enabled) VALUES
    ('UGX', 'Ugandan Shilling',       TRUE,  'UG', FALSE),
    ('KES', 'Kenyan Shilling',        TRUE,  'KE', FALSE),
    ('TZS', 'Tanzanian Shilling',     TRUE,  'TZ', FALSE),
    ('RWF', 'Rwandan Franc',          TRUE,  'RW', FALSE),
    ('NGN', 'Nigerian Naira',         TRUE,  'NG', FALSE),
    ('ZAR', 'South African Rand',     TRUE,  'ZA', FALSE),
    ('EGP', 'Egyptian Pound',         TRUE,  'EG', FALSE),
    ('USD', 'US Dollar',              FALSE, NULL, FALSE)
ON CONFLICT (code) DO NOTHING;

CREATE INDEX IF NOT EXISTS idx_currencies_forex_enabled
    ON currencies (forex_trading_enabled) WHERE forex_trading_enabled = TRUE;

-- 1.5 system_settings: allow_foreign_currency_loans (global default = FALSE)
INSERT INTO system_settings (setting_key, country, setting_value, setting_type, category, description, is_public)
VALUES ('allow_foreign_currency_loans', NULL, 'false', 'boolean', 'marketplace',
        'Whether a loan request may be posted in USD instead of the market''s own currency (global default; override per country).',
        TRUE)
ON CONFLICT (setting_key, COALESCE(country, '__global__')) DO NOTHING;


-- ============================================
-- PART 2 — FOREX MODULE (Stage 4.7)
-- Mirrors the loan_requests / loan_offers / agreements / contact_reveals
-- pattern exactly: free to post, Lender+ to offer, Pro-only preferred rate,
-- locked bidding, country copied+frozen at insert, no country column on
-- offers (read through the parent request).
-- ============================================

-- 2.1 forex_requests
CREATE TABLE IF NOT EXISTS forex_requests (
    id                     UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    requester_id           UUID NOT NULL REFERENCES profiles(id) ON DELETE RESTRICT,
    country                TEXT NOT NULL REFERENCES countries(code),

    currency_held          TEXT NOT NULL REFERENCES currencies(code),
    currency_needed        TEXT NOT NULL REFERENCES currencies(code),
    amount                 BIGINT NOT NULL CONSTRAINT chk_fr_amount_positive CHECK (amount > 0),
    preferred_rate         NUMERIC(14,6) CONSTRAINT chk_fr_preferred_rate_positive
                                CHECK (preferred_rate IS NULL OR preferred_rate > 0),
    settlement_preference  TEXT NOT NULL,   -- in-person / mobile money / bank transfer / other — disclosed only, never brokered
    is_urgent              BOOLEAN NOT NULL DEFAULT FALSE,

    terms_locked_at        TIMESTAMP,
    number_of_offers       INT NOT NULL DEFAULT 0,
    status                 loan_status_enum NOT NULL DEFAULT 'active',

    listed_at               TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    expires_at               TIMESTAMP,
    contracted_at             TIMESTAMP,
    cancelled_at               TIMESTAMP,
    views_count                 INT NOT NULL DEFAULT 0,

    created_at              TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at              TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT chk_fr_pair_distinct CHECK (currency_held <> currency_needed)
);

COMMENT ON TABLE forex_requests IS
'Peer-to-peer currency-exchange requests. Free to post. requester_id masked on all public
 views, identical boundary to loan_requests.borrower_id. country is copied from the
 requester''s profile at insert time and frozen thereafter. preferred_rate is Pro-only,
 locked on publish. currency_held/currency_needed must both have forex_trading_enabled = TRUE
 at the time of insert (enforced by trg_fn_validate_forex_request).';
COMMENT ON COLUMN forex_requests.requester_id IS
'NEVER exposed in v_forex_listings or any marketplace query. Contact revealed only post-acceptance.';

CREATE INDEX IF NOT EXISTS idx_fx_req_country        ON forex_requests (country);
CREATE INDEX IF NOT EXISTS idx_fx_req_country_status  ON forex_requests (country, status);
CREATE INDEX IF NOT EXISTS idx_fx_req_requester_id    ON forex_requests (requester_id);
CREATE INDEX IF NOT EXISTS idx_fx_req_status          ON forex_requests (status);
CREATE INDEX IF NOT EXISTS idx_fx_req_pair            ON forex_requests (currency_held, currency_needed);

-- 2.2 forex_offers — deliberately no country column, see comment
CREATE TABLE IF NOT EXISTS forex_offers (
    id                UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    request_id        UUID NOT NULL REFERENCES forex_requests(id) ON DELETE CASCADE,
    offer_maker_id    UUID NOT NULL REFERENCES profiles(id) ON DELETE RESTRICT,

    rate_offered      NUMERIC(14,6) NOT NULL CONSTRAINT chk_fo_rate_positive CHECK (rate_offered > 0),
    amount_available  BIGINT NOT NULL CONSTRAINT chk_fo_amount_positive CHECK (amount_available > 0),
    terms             TEXT,   -- settlement method / timing detail, locked on submit

    terms_locked_at   TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    status            offer_status_enum NOT NULL DEFAULT 'pending',

    offered_at        TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    accepted_at       TIMESTAMP,
    withdrawn_at      TIMESTAMP,
    expires_at        TIMESTAMP,

    created_at        TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at        TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,

    UNIQUE (request_id, offer_maker_id)
);

COMMENT ON TABLE forex_offers IS
'Offers against a forex request. NO country column, by design — an offer''s country is
 always its parent request''s country, read through request_id -> forex_requests.country,
 exactly the same pattern as loan_offers. Cross-border offers are allowed (no country check
 in trg_fn_validate_forex_offer), matching loan_offers.';

CREATE INDEX IF NOT EXISTS idx_fx_off_request_id     ON forex_offers (request_id);
CREATE INDEX IF NOT EXISTS idx_fx_off_offer_maker_id ON forex_offers (offer_maker_id);
CREATE INDEX IF NOT EXISTS idx_fx_off_status         ON forex_offers (status);
CREATE INDEX IF NOT EXISTS idx_fx_off_req_status     ON forex_offers (request_id, status);

-- 2.3 forex_agreements — mirrors `agreements`
CREATE TABLE IF NOT EXISTS forex_agreements (
    id                     UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    offer_id               UUID NOT NULL UNIQUE REFERENCES forex_offers(id) ON DELETE CASCADE,
    request_id             UUID NOT NULL REFERENCES forex_requests(id) ON DELETE CASCADE,

    rate_agreed            NUMERIC(14,6) NOT NULL CONSTRAINT chk_fa_rate_positive CHECK (rate_agreed > 0),
    amount_agreed          BIGINT NOT NULL CONSTRAINT chk_fa_amount_positive CHECK (amount_agreed > 0),
    settlement_terms       TEXT,

    agreement_text         TEXT NOT NULL,
    agreement_snapshot      JSONB,

    status                  agreement_status_enum NOT NULL DEFAULT 'locked',
    requester_agreed_at      TIMESTAMP,
    offer_maker_agreed_at     TIMESTAMP,
    locked_at                  TIMESTAMP,

    created_at              TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at              TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE forex_agreements IS
'Locked exchange agreement. Auto-generated after a forex offer is accepted, exactly mirroring
 agreements for loans. Nipanze never performs the exchange or holds currency — the disclaimer
 reflects that instead of the loan-specific late-fee language.';

CREATE INDEX IF NOT EXISTS idx_fa_offer_id   ON forex_agreements (offer_id);
CREATE INDEX IF NOT EXISTS idx_fa_request_id ON forex_agreements (request_id);
CREATE INDEX IF NOT EXISTS idx_fa_status     ON forex_agreements (status);

-- 2.4 forex_contact_reveals — mirrors `contact_reveals`
CREATE TABLE IF NOT EXISTS forex_contact_reveals (
    id           UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    offer_id     UUID NOT NULL REFERENCES forex_offers(id) ON DELETE CASCADE,
    request_id   UUID NOT NULL REFERENCES forex_requests(id) ON DELETE CASCADE,
    revealed_by  UUID NOT NULL REFERENCES profiles(id) ON DELETE RESTRICT,
    status       reveal_status_enum NOT NULL DEFAULT 'pending',
    revealed_at  TIMESTAMP,
    created_at   TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (offer_id)
);

COMMENT ON TABLE forex_contact_reveals IS
'Post-acceptance contact sharing for a forex deal. Identical boundary to contact_reveals:
 irreversible once revealed, enforced at the API layer only via unlock_forex_contact().';

CREATE INDEX IF NOT EXISTS idx_fcr_offer_id   ON forex_contact_reveals (offer_id);
CREATE INDEX IF NOT EXISTS idx_fcr_request_id ON forex_contact_reveals (request_id);


-- ============================================
-- PART 3 — TRUST & REVIEWS: extend to be module-agnostic
-- ============================================

-- 3.1 reviews: add a forex sibling to contract_id, keep exactly one populated
ALTER TABLE reviews ADD COLUMN IF NOT EXISTS forex_contract_id UUID REFERENCES forex_agreements(id) ON DELETE CASCADE;
ALTER TABLE reviews ALTER COLUMN contract_id DROP NOT NULL;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'chk_reviews_one_contract'
    ) THEN
        ALTER TABLE reviews ADD CONSTRAINT chk_reviews_one_contract CHECK (
            (contract_id IS NOT NULL AND forex_contract_id IS NULL) OR
            (contract_id IS NULL AND forex_contract_id IS NOT NULL)
        );
    END IF;
END $$;

CREATE UNIQUE INDEX IF NOT EXISTS uidx_reviews_forex_contract_reviewer
    ON reviews (forex_contract_id, reviewer_id) WHERE forex_contract_id IS NOT NULL;

COMMENT ON COLUMN reviews.forex_contract_id IS
'v6.0: sibling to contract_id for forex-originated deals. Exactly one of contract_id /
 forex_contract_id is set per row (chk_reviews_one_contract) — a review is always for
 either a loan agreement or a forex agreement, never both, but both feed the same
 trust_aggregates row for the reviewee.';

-- 3.2 watchlist: forex-aware
ALTER TABLE watchlist ADD COLUMN IF NOT EXISTS forex_request_id UUID REFERENCES forex_requests(id) ON DELETE CASCADE;
ALTER TABLE watchlist ALTER COLUMN request_id DROP NOT NULL;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'chk_wl_one_target'
    ) THEN
        ALTER TABLE watchlist ADD CONSTRAINT chk_wl_one_target CHECK (
            (request_id IS NOT NULL AND forex_request_id IS NULL) OR
            (request_id IS NULL AND forex_request_id IS NOT NULL)
        );
    END IF;
END $$;

CREATE UNIQUE INDEX IF NOT EXISTS uidx_wl_user_forex_request
    ON watchlist (user_id, forex_request_id) WHERE forex_request_id IS NOT NULL;

-- 3.3 notifications: forex deep-link columns
ALTER TABLE notifications ADD COLUMN IF NOT EXISTS forex_request_id UUID REFERENCES forex_requests(id) ON DELETE SET NULL;
ALTER TABLE notifications ADD COLUMN IF NOT EXISTS forex_offer_id   UUID REFERENCES forex_offers(id)   ON DELETE SET NULL;


-- ============================================
-- PART 4 — TRIGGER FUNCTIONS (forex-specific; loan-side functions unchanged)
-- ============================================

CREATE OR REPLACE FUNCTION trg_fn_set_forex_request_country()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
BEGIN
    IF NEW.country IS NULL THEN
        SELECT country INTO NEW.country FROM profiles WHERE id = NEW.requester_id;
    END IF;
    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION trg_fn_set_forex_request_country IS
'v6.0: sets forex_requests.country from the requester''s profiles.country at insert time,
 if not already supplied. Frozen thereafter by trg_fn_lock_forex_request_terms(). Mirrors
 trg_fn_set_request_country() for loans.';

CREATE OR REPLACE FUNCTION trg_fn_require_active_account_forex()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM profiles WHERE id = NEW.requester_id AND account_status != 'active'
    ) THEN
        RAISE EXCEPTION 'NIPANZE_ACCOUNT_INACTIVE: Your account must be active to post a forex request.'
            USING ERRCODE = 'P0101';
    END IF;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION trg_fn_validate_forex_request()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
DECLARE
    v_held_ok       BOOLEAN;
    v_needed_ok     BOOLEAN;
    v_forex_enabled BOOLEAN;
    v_plan          subscription_plan_enum;
    v_req_country   TEXT;
BEGIN
    v_req_country := COALESCE(NEW.country, (SELECT country FROM profiles WHERE id = NEW.requester_id));

    SELECT forex_enabled INTO v_forex_enabled FROM countries WHERE code = v_req_country;
    IF NOT COALESCE(v_forex_enabled, FALSE) THEN
        RAISE EXCEPTION 'NIPANZE_FOREX_NOT_ENABLED: Forex is not yet enabled in this market.'
            USING ERRCODE = 'P0102';
    END IF;

    SELECT forex_trading_enabled INTO v_held_ok   FROM currencies WHERE code = NEW.currency_held;
    SELECT forex_trading_enabled INTO v_needed_ok FROM currencies WHERE code = NEW.currency_needed;
    IF NOT COALESCE(v_held_ok, FALSE) OR NOT COALESCE(v_needed_ok, FALSE) THEN
        RAISE EXCEPTION 'NIPANZE_CURRENCY_NOT_TRADEABLE: One or both currencies are not cleared for forex trading.'
            USING ERRCODE = 'P0103';
    END IF;

    IF NEW.preferred_rate IS NOT NULL THEN
        SELECT plan INTO v_plan FROM subscriptions
        WHERE user_id = NEW.requester_id AND status = 'active'
        ORDER BY created_at DESC LIMIT 1;

        IF v_plan IS DISTINCT FROM 'pro'::subscription_plan_enum THEN
            RAISE EXCEPTION 'NIPANZE_PRO_REQUIRED: A Pro subscription is required to suggest a preferred exchange rate.'
                USING ERRCODE = 'P0104';
        END IF;
    END IF;

    NEW.terms_locked_at := COALESCE(NEW.terms_locked_at, NOW());
    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION trg_fn_validate_forex_request IS
'Server-side currency-eligibility + forex_enabled + Pro-gate check for a new forex request —
 mirrors trg_fn_validate_request_terms() for loans, matching Stage 4.7 exit criteria: a
 currency pair with either leg forex_trading_enabled = FALSE is rejected even if the client
 UI is bypassed.';

CREATE OR REPLACE FUNCTION trg_fn_lock_forex_request_terms()
RETURNS TRIGGER LANGUAGE plpgsql
SET search_path = public AS $$
BEGIN
    IF OLD.terms_locked_at IS NOT NULL AND OLD.preferred_rate IS DISTINCT FROM NEW.preferred_rate THEN
        RAISE EXCEPTION 'NIPANZE_FOREX_REQUEST_TERMS_LOCKED: Preferred rate cannot be edited after publish.'
            USING ERRCODE = 'P0105';
    END IF;

    IF OLD.country IS DISTINCT FROM NEW.country THEN
        RAISE EXCEPTION 'NIPANZE_FOREX_REQUEST_COUNTRY_LOCKED: A forex listing''s country is frozen at publish time and cannot be changed.'
            USING ERRCODE = 'P0106';
    END IF;

    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION trg_fn_validate_forex_offer()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
DECLARE
    v_listing forex_requests%ROWTYPE;
    v_plan    subscription_plan_enum;
BEGIN
    SELECT * INTO v_listing FROM forex_requests WHERE id = NEW.request_id;

    IF v_listing.status != 'active' THEN
        RAISE EXCEPTION 'NIPANZE_FOREX_LISTING_NOT_ACTIVE: This forex request is no longer accepting offers.'
            USING ERRCODE = 'P0110';
    END IF;

    IF v_listing.expires_at < NOW() THEN
        RAISE EXCEPTION 'NIPANZE_FOREX_LISTING_EXPIRED: This forex request has expired.'
            USING ERRCODE = 'P0111';
    END IF;

    IF v_listing.requester_id = NEW.offer_maker_id THEN
        RAISE EXCEPTION 'NIPANZE_SELF_OFFER: You cannot make an offer on your own forex request.'
            USING ERRCODE = 'P0112';
    END IF;

    SELECT plan INTO v_plan FROM subscriptions
    WHERE user_id = NEW.offer_maker_id AND status = 'active';

    IF v_plan IS NULL OR v_plan NOT IN ('lender', 'pro') THEN
        RAISE EXCEPTION 'NIPANZE_SUBSCRIPTION_REQUIRED: A Lender or Pro subscription is required to make forex offers.'
            USING ERRCODE = 'P0113';
    END IF;

    IF NEW.rate_offered IS NULL OR NEW.amount_available IS NULL THEN
        RAISE EXCEPTION 'NIPANZE_FOREX_OFFER_TERMS_REQUIRED: Rate offered and available amount are required.'
            USING ERRCODE = 'P0114';
    END IF;

    NEW.terms_locked_at := COALESCE(NEW.terms_locked_at, NOW());
    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION trg_fn_validate_forex_offer IS
'Mirrors trg_fn_validate_offer() for loans. No country-match check — cross-border forex
 offers are allowed by default, matching loan_offers and the Multi-Market Architecture
 "resolved for v6.0: allowed" decision.';

CREATE OR REPLACE FUNCTION trg_fn_lock_forex_offer_terms()
RETURNS TRIGGER LANGUAGE plpgsql
SET search_path = public AS $$
BEGIN
    IF OLD.terms_locked_at IS NOT NULL AND (
        OLD.rate_offered     IS DISTINCT FROM NEW.rate_offered OR
        OLD.amount_available IS DISTINCT FROM NEW.amount_available OR
        OLD.terms            IS DISTINCT FROM NEW.terms
    ) THEN
        RAISE EXCEPTION 'NIPANZE_FOREX_OFFER_TERMS_LOCKED: Forex offer terms cannot be edited after submit.'
            USING ERRCODE = 'P0115';
    END IF;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION trg_fn_lock_accepted_forex_offer()
RETURNS TRIGGER LANGUAGE plpgsql
SET search_path = public AS $$
BEGIN
    IF OLD.status = 'accepted' THEN
        RAISE EXCEPTION 'NIPANZE_FOREX_OFFER_LOCKED: An accepted forex offer cannot be modified.'
            USING ERRCODE = 'P0116';
    END IF;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION trg_fn_sync_forex_offer_count()
RETURNS TRIGGER LANGUAGE plpgsql
SET search_path = public AS $$
DECLARE
    v_request_id UUID;
BEGIN
    v_request_id := COALESCE(NEW.request_id, OLD.request_id);

    UPDATE forex_requests fr
       SET number_of_offers = (
           SELECT COUNT(*)::INT FROM forex_offers fo
            WHERE fo.request_id = v_request_id AND fo.status = 'pending'
       )
     WHERE fr.id = v_request_id;

    RETURN COALESCE(NEW, OLD);
END;
$$;


-- ============================================
-- PART 5 — TRIGGERS (forex tables)
-- Reuses generic v5.0 functions where they're already table-agnostic:
--   trg_fn_set_listing_expiry() — only touches NEW.country / NEW.expires_at
--   trg_fn_expire_offer()       — only touches NEW.expires_at / NEW.status
--   fn_set_updated_at()         — generic updated_at setter
-- ============================================

DROP TRIGGER IF EXISTS trg_set_forex_request_country ON forex_requests;
CREATE TRIGGER trg_set_forex_request_country
    BEFORE INSERT ON forex_requests
    FOR EACH ROW EXECUTE FUNCTION trg_fn_set_forex_request_country();

DROP TRIGGER IF EXISTS trg_require_active_account_forex ON forex_requests;
CREATE TRIGGER trg_require_active_account_forex
    BEFORE INSERT ON forex_requests
    FOR EACH ROW EXECUTE FUNCTION trg_fn_require_active_account_forex();

DROP TRIGGER IF EXISTS trg_validate_forex_request ON forex_requests;
CREATE TRIGGER trg_validate_forex_request
    BEFORE INSERT ON forex_requests
    FOR EACH ROW EXECUTE FUNCTION trg_fn_validate_forex_request();

DROP TRIGGER IF EXISTS trg_set_forex_listing_expiry ON forex_requests;
CREATE TRIGGER trg_set_forex_listing_expiry
    BEFORE INSERT ON forex_requests
    FOR EACH ROW EXECUTE FUNCTION trg_fn_set_listing_expiry();

DROP TRIGGER IF EXISTS trg_lock_forex_request_terms ON forex_requests;
CREATE TRIGGER trg_lock_forex_request_terms
    BEFORE UPDATE ON forex_requests
    FOR EACH ROW EXECUTE FUNCTION trg_fn_lock_forex_request_terms();

DROP TRIGGER IF EXISTS trg_forex_requests_updated_at ON forex_requests;
CREATE TRIGGER trg_forex_requests_updated_at
    BEFORE UPDATE ON forex_requests
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

DROP TRIGGER IF EXISTS trg_expire_forex_offer ON forex_offers;
CREATE TRIGGER trg_expire_forex_offer
    BEFORE INSERT OR UPDATE ON forex_offers
    FOR EACH ROW EXECUTE FUNCTION trg_fn_expire_offer();

DROP TRIGGER IF EXISTS trg_validate_forex_offer ON forex_offers;
CREATE TRIGGER trg_validate_forex_offer
    BEFORE INSERT ON forex_offers
    FOR EACH ROW EXECUTE FUNCTION trg_fn_validate_forex_offer();

DROP TRIGGER IF EXISTS trg_lock_accepted_forex_offer ON forex_offers;
CREATE TRIGGER trg_lock_accepted_forex_offer
    BEFORE UPDATE ON forex_offers
    FOR EACH ROW WHEN (OLD.status = 'accepted')
    EXECUTE FUNCTION trg_fn_lock_accepted_forex_offer();

DROP TRIGGER IF EXISTS trg_lock_forex_offer_terms ON forex_offers;
CREATE TRIGGER trg_lock_forex_offer_terms
    BEFORE UPDATE ON forex_offers
    FOR EACH ROW EXECUTE FUNCTION trg_fn_lock_forex_offer_terms();

DROP TRIGGER IF EXISTS trg_sync_forex_offer_count ON forex_offers;
CREATE TRIGGER trg_sync_forex_offer_count
    AFTER INSERT OR UPDATE OR DELETE ON forex_offers
    FOR EACH ROW EXECUTE FUNCTION trg_fn_sync_forex_offer_count();

DROP TRIGGER IF EXISTS trg_forex_offers_updated_at ON forex_offers;
CREATE TRIGGER trg_forex_offers_updated_at
    BEFORE UPDATE ON forex_offers
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

DROP TRIGGER IF EXISTS trg_forex_agreements_updated_at ON forex_agreements;
CREATE TRIGGER trg_forex_agreements_updated_at
    BEFORE UPDATE ON forex_agreements
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();


-- ============================================
-- KYC-aware concurrency limits (loan + forex)
-- Adds system settings and server-side enforcement so KYC-approved
-- users can have higher concurrent active listings if configured.
-- ============================================

-- Insert configurable limits (idempotent)
INSERT INTO system_settings (setting_key, country, setting_value, setting_type, category, description, is_public)
VALUES
  ('max_concurrent_requests_verified', NULL, '5', 'number', 'limits', 'Maximum active loan requests per borrower when KYC is approved', TRUE),
  ('max_concurrent_forex_requests', NULL, '3', 'number', 'limits', 'Maximum active forex requests per requester (global default)', TRUE),
  ('max_concurrent_forex_requests_verified', NULL, '5', 'number', 'limits', 'Maximum active forex requests per requester when KYC is approved', TRUE)
ON CONFLICT (setting_key, COALESCE(country, '__global__')) DO NOTHING;


-- Replace loan max-concurrent function to respect KYC approval
CREATE OR REPLACE FUNCTION trg_fn_max_concurrent_requests()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
DECLARE
    v_active_count INT;
    v_max          INT;
    v_kyc_status   kyc_status_enum;
    v_setting_key  TEXT := 'max_concurrent_requests';
BEGIN
    SELECT status INTO v_kyc_status FROM kyc_verifications WHERE user_id = NEW.borrower_id;
    IF v_kyc_status = 'approved' THEN
        v_setting_key := 'max_concurrent_requests_verified';
    END IF;

    SELECT setting_value::INT INTO v_max
    FROM system_settings WHERE setting_key = v_setting_key AND country IS NULL
    ORDER BY country NULLS LAST LIMIT 1;

    SELECT COUNT(*) INTO v_active_count
    FROM loan_requests
    WHERE borrower_id = NEW.borrower_id AND status = 'active';

    IF v_active_count >= COALESCE(v_max, 0) THEN
        RAISE EXCEPTION 'NIPANZE_MAX_REQUESTS: You have reached the maximum of % active listings.', COALESCE(v_max, 0)
            USING ERRCODE = 'P0002';
    END IF;

    RETURN NEW;
END;
$$;


-- Add forex max-concurrent enforcement (new function + trigger)
CREATE OR REPLACE FUNCTION trg_fn_max_concurrent_forex_requests()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
DECLARE
    v_active_count INT;
    v_max          INT;
    v_kyc_status   kyc_status_enum;
    v_setting_key  TEXT := 'max_concurrent_forex_requests';
BEGIN
    SELECT status INTO v_kyc_status FROM kyc_verifications WHERE user_id = NEW.requester_id;
    IF v_kyc_status = 'approved' THEN
        v_setting_key := 'max_concurrent_forex_requests_verified';
    END IF;

    SELECT setting_value::INT INTO v_max
    FROM system_settings WHERE setting_key = v_setting_key AND country IS NULL
    ORDER BY country NULLS LAST LIMIT 1;

    SELECT COUNT(*) INTO v_active_count
    FROM forex_requests
    WHERE requester_id = NEW.requester_id AND status = 'active';

    IF v_active_count >= COALESCE(v_max, 0) THEN
        RAISE EXCEPTION 'NIPANZE_MAX_FOREX_REQUESTS: You have reached the maximum of % active forex listings.', COALESCE(v_max, 0)
            USING ERRCODE = 'P0102';
    END IF;

    RETURN NEW;
END;
$$;

-- Attach trigger to forex_requests
DROP TRIGGER IF EXISTS trg_max_concurrent_forex_requests ON forex_requests;
CREATE TRIGGER trg_max_concurrent_forex_requests
    BEFORE INSERT ON forex_requests
    FOR EACH ROW EXECUTE FUNCTION trg_fn_max_concurrent_forex_requests();


-- ============================================
-- PART 6 — VIEWS (forex marketplace + offers)
-- ============================================

-- v_forex_listings — mirrors v_loan_listings exactly: requester_id, phone,
-- email, full_name, national ID never exposed; rate_coverage_tier replaces
-- offer_coverage_tier; individual offered rates never shown here.
CREATE OR REPLACE VIEW v_forex_listings AS
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
    (fr.expires_at < NOW() + INTERVAL '6 hours')                             AS closing_soon_6h
FROM  forex_requests  fr
JOIN  profiles p ON p.id = fr.requester_id
LEFT  JOIN kyc_verifications k  ON k.user_id = fr.requester_id
LEFT  JOIN trust_aggregates  ta ON ta.user_id = fr.requester_id
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

COMMENT ON VIEW v_forex_listings IS
'Anonymised forex marketplace feed, mirroring v_loan_listings. requester_id, contact
 details, and private documents are never present. preferred_rate is shown only when the
 owner is Pro and chose to set it (public, since it is the owner''s own suggestion — offer
 rates from other users are never shown here). rate_coverage_tier is the forex analogue of
 offer_coverage_tier.';

-- v_forex_offers — mirrors v_lender_offers, participant-scoped exact terms
CREATE OR REPLACE VIEW v_forex_offers WITH (security_invoker = true) AS
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
    fcr.revealed_at
FROM  forex_offers    fo
JOIN  forex_requests  fr ON fr.id = fo.request_id
JOIN  profiles        p  ON p.id  = fo.offer_maker_id
LEFT  JOIN kyc_verifications k   ON k.user_id  = fo.offer_maker_id
LEFT  JOIN trust_aggregates  ta  ON ta.user_id = fo.offer_maker_id
LEFT  JOIN forex_contact_reveals fcr ON fcr.offer_id = fo.id;

COMMENT ON VIEW v_forex_offers IS
'Forex offer history with reveal status, mirroring v_lender_offers. Requester contact
 details not exposed until reveal_status = revealed.';

-- get_public_forex_offers — mirrors get_public_listing_offers
CREATE OR REPLACE FUNCTION get_public_forex_offers(p_request_id UUID)
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
    accepted_at TIMESTAMP
)
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = ''
AS $$
DECLARE
    v_is_owner       BOOLEAN := FALSE;
    v_is_offer_maker BOOLEAN := FALSE;
BEGIN
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
            fo.accepted_at
        FROM public.forex_offers fo
        JOIN public.forex_requests fr ON fr.id = fo.request_id
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
        fo.accepted_at
    FROM public.forex_offers fo
    WHERE fo.request_id = p_request_id
      AND fo.offer_maker_id = auth.uid()
      AND fo.status IN ('pending', 'accepted');
END;
$$;

COMMENT ON FUNCTION get_public_forex_offers(UUID) IS
'Participant-scoped forex bid book, mirroring get_public_listing_offers(). Listing owners
 and offer-makers receive exact terms; all other viewers receive only v_forex_listings
 aggregate coverage (rate_coverage_tier).';


-- ============================================
-- PART 7 — RPCs: accept_forex_offer, unlock_forex_contact
-- Same private/public SECURITY DEFINER-wrapper pattern as accept_offer /
-- unlock_contact for loans.
-- ============================================

CREATE OR REPLACE FUNCTION private.accept_forex_offer_internal(
    p_request_id   UUID,
    p_offer_id     UUID,
    p_requester_id UUID,
    p_caller_id    UUID
)
RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = '' AS $$
DECLARE
    v_listing        public.forex_requests%ROWTYPE;
    v_offer          public.forex_offers%ROWTYPE;
    v_requester      public.profiles%ROWTYPE;
    v_offer_maker    public.profiles%ROWTYPE;
    v_agreement_id   UUID;
    v_agreement_text TEXT;
    v_snapshot       JSONB;
BEGIN
    IF p_caller_id IS NULL OR p_caller_id != p_requester_id THEN
        RAISE EXCEPTION 'NIPANZE_UNAUTHORIZED: Caller is not the request owner.'
            USING ERRCODE = 'P0121';
    END IF;

    SELECT * INTO v_listing FROM public.forex_requests WHERE id = p_request_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'NIPANZE_FOREX_LISTING_NOT_FOUND' USING ERRCODE = 'P0120';
    END IF;
    IF v_listing.requester_id != p_requester_id THEN
        RAISE EXCEPTION 'NIPANZE_UNAUTHORIZED: Only the listing owner can accept an offer.'
            USING ERRCODE = 'P0121';
    END IF;
    IF v_listing.status != 'active' THEN
        RAISE EXCEPTION 'NIPANZE_FOREX_LISTING_NOT_ACTIVE' USING ERRCODE = 'P0122';
    END IF;

    SELECT * INTO v_offer FROM public.forex_offers
     WHERE id = p_offer_id AND request_id = p_request_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'NIPANZE_FOREX_OFFER_NOT_FOUND' USING ERRCODE = 'P0123';
    END IF;
    IF v_offer.status != 'pending' THEN
        RAISE EXCEPTION 'NIPANZE_FOREX_OFFER_NOT_PENDING: This offer is no longer available.'
            USING ERRCODE = 'P0124';
    END IF;

    SELECT * INTO v_requester   FROM public.profiles WHERE id = p_requester_id;
    SELECT * INTO v_offer_maker FROM public.profiles WHERE id = v_offer.offer_maker_id;

    v_snapshot := JSONB_BUILD_OBJECT(
        'request_id', p_request_id,
        'offer_id', p_offer_id,
        'requester_id', p_requester_id,
        'offer_maker_id', v_offer.offer_maker_id,
        'country', v_listing.country,
        'currency_held', v_listing.currency_held,
        'currency_needed', v_listing.currency_needed,
        'amount_agreed', v_offer.amount_available,
        'rate_agreed', v_offer.rate_offered,
        'settlement_terms', v_offer.terms,
        'legal_disclaimer', 'Nipanze provides this agreement for convenience only. The final exchange is solely between the two parties. Nipanze does not perform the exchange or hold currency.',
        'locked_at', NOW()
    );

    v_agreement_text := FORMAT(
'EXCHANGE AGREEMENT

PARTIES
Requester: %s
Offer-maker: %s

LOCKED TERMS
Currency held by requester: %s
Currency needed by requester: %s
Amount: %s %s
Rate agreed: %s
Settlement terms: %s

DISCLAIMER
Nipanze provides this agreement for convenience only. The final exchange is solely between
the two parties. Nipanze does not perform the exchange or hold currency.

Audit timestamp: %s',
        COALESCE(v_requester.full_name, 'Requester'),
        COALESCE(v_offer_maker.full_name, 'Offer-maker'),
        v_listing.currency_held,
        v_listing.currency_needed,
        v_listing.currency_held, v_offer.amount_available,
        v_offer.rate_offered,
        COALESCE(v_offer.terms, 'As agreed off-platform'),
        NOW()
    );

    UPDATE public.forex_offers SET status = 'accepted', accepted_at = NOW() WHERE id = p_offer_id;

    UPDATE public.forex_offers
       SET status = 'rejected', updated_at = NOW()
     WHERE request_id = p_request_id AND id != p_offer_id AND status = 'pending';

    UPDATE public.forex_requests
       SET status = 'contracted', contracted_at = NOW() WHERE id = p_request_id;

    INSERT INTO public.forex_agreements (
        offer_id, request_id, rate_agreed, amount_agreed, settlement_terms,
        agreement_text, agreement_snapshot, status,
        requester_agreed_at, offer_maker_agreed_at, locked_at
    )
    VALUES (
        p_offer_id, p_request_id, v_offer.rate_offered, v_offer.amount_available, v_offer.terms,
        v_agreement_text, v_snapshot, 'locked'::public.agreement_status_enum,
        NOW(), NOW(), NOW()
    )
    ON CONFLICT (offer_id) DO UPDATE
       SET rate_agreed = EXCLUDED.rate_agreed,
           amount_agreed = EXCLUDED.amount_agreed,
           agreement_text = EXCLUDED.agreement_text,
           agreement_snapshot = EXCLUDED.agreement_snapshot,
           status = 'locked'::public.agreement_status_enum,
           requester_agreed_at = COALESCE(public.forex_agreements.requester_agreed_at, NOW()),
           offer_maker_agreed_at = COALESCE(public.forex_agreements.offer_maker_agreed_at, NOW()),
           locked_at = COALESCE(public.forex_agreements.locked_at, NOW())
    RETURNING id INTO v_agreement_id;

    INSERT INTO public.notifications (user_id, type, title, body, forex_request_id, forex_offer_id)
    VALUES
        (p_requester_id, 'agreement_locked', 'Exchange agreement generated',
         'Your selected offer is locked into an exchange agreement. Unlock contact details to connect.',
         p_request_id, p_offer_id),
        (v_offer.offer_maker_id, 'agreement_locked', 'Exchange agreement generated',
         'Your offer was accepted and locked into an exchange agreement. Contact unlock is now available.',
         p_request_id, p_offer_id);

    INSERT INTO public.audit_logs (user_id, event_type, entity_type, entity_id, action, new_values)
    VALUES
        (p_requester_id, 'offer_accepted', 'forex_offers', p_offer_id, 'accept_forex_offer', v_snapshot),
        (p_requester_id, 'agreement_locked', 'forex_agreements', v_agreement_id, 'generate_locked_forex_agreement', v_snapshot);

    RETURN v_agreement_id;
END;
$$;

GRANT EXECUTE ON FUNCTION private.accept_forex_offer_internal(uuid, uuid, uuid, uuid) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.accept_forex_offer(
    p_request_id   UUID,
    p_offer_id     UUID,
    p_requester_id UUID
)
RETURNS UUID
LANGUAGE sql SECURITY INVOKER
SET search_path = public AS $$
    SELECT private.accept_forex_offer_internal(p_request_id, p_offer_id, p_requester_id, auth.uid());
$$;

REVOKE EXECUTE ON FUNCTION public.accept_forex_offer(uuid, uuid, uuid) FROM public, anon;
GRANT  EXECUTE ON FUNCTION public.accept_forex_offer(uuid, uuid, uuid) TO authenticated, service_role;

COMMENT ON FUNCTION public.accept_forex_offer IS
'Atomically accepts a forex offer, rejects competing offers, marks the request contracted,
 and creates a locked forex_agreement. Mirrors accept_offer() for loans. Contact details are
 not exposed until unlock_forex_contact() is called.';


CREATE OR REPLACE FUNCTION private.unlock_forex_contact_internal(
    p_agreement_id UUID,
    p_caller_id    UUID
)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = '' AS $$
DECLARE
    v_agreement       public.forex_agreements%ROWTYPE;
    v_offer           public.forex_offers%ROWTYPE;
    v_reveal          public.forex_contact_reveals%ROWTYPE;
    v_requester       public.profiles%ROWTYPE;
    v_offer_maker     public.profiles%ROWTYPE;
    v_requester_auth  RECORD;
    v_offer_maker_auth RECORD;
    v_requester_id    UUID;
    v_offer_maker_id  UUID;
    v_result          JSONB;
BEGIN
    SELECT * INTO v_agreement FROM public.forex_agreements WHERE id = p_agreement_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'NIPANZE_FOREX_AGREEMENT_NOT_FOUND' USING ERRCODE = 'P0141';
    END IF;

    IF v_agreement.status != 'locked' THEN
        RAISE EXCEPTION 'NIPANZE_FOREX_AGREEMENT_NOT_LOCKED: Agreement must be locked before unlocking contact.'
            USING ERRCODE = 'P0145';
    END IF;

    SELECT * INTO v_offer FROM public.forex_offers WHERE id = v_agreement.offer_id;
    SELECT requester_id INTO v_requester_id FROM public.forex_requests WHERE id = v_agreement.request_id;
    v_offer_maker_id := v_offer.offer_maker_id;

    IF p_caller_id != v_requester_id THEN
        RAISE EXCEPTION 'NIPANZE_UNAUTHORIZED: Only the request owner can unlock contact details.'
            USING ERRCODE = 'P0146';
    END IF;

    SELECT * INTO v_requester   FROM public.profiles WHERE id = v_requester_id;
    SELECT * INTO v_offer_maker FROM public.profiles WHERE id = v_offer_maker_id;

    SELECT email INTO v_requester_auth   FROM auth.users WHERE id = v_requester_id;
    SELECT email INTO v_offer_maker_auth FROM auth.users WHERE id = v_offer_maker_id;

    SELECT * INTO v_reveal FROM public.forex_contact_reveals WHERE offer_id = v_agreement.offer_id;
    IF v_reveal IS NULL THEN
        INSERT INTO public.forex_contact_reveals (offer_id, request_id, revealed_by, status, revealed_at)
        VALUES (v_agreement.offer_id, v_agreement.request_id, v_requester_id, 'revealed', NOW())
        RETURNING * INTO v_reveal;
    ELSE
        UPDATE public.forex_contact_reveals
           SET status = 'revealed', revealed_at = NOW()
         WHERE id = v_reveal.id;
        v_reveal.status := 'revealed';
        v_reveal.revealed_at := NOW();
    END IF;

    v_result := JSONB_BUILD_OBJECT(
        'agreement_id', v_agreement.id,
        'revealed_at', v_reveal.revealed_at,
        'requester', JSONB_BUILD_OBJECT(
            'full_name', v_requester.full_name, 'phone', v_requester.phone, 'email', v_requester_auth.email),
        'offer_maker', JSONB_BUILD_OBJECT(
            'full_name', v_offer_maker.full_name, 'phone', v_offer_maker.phone, 'email', v_offer_maker_auth.email)
    );

    INSERT INTO public.notifications (user_id, type, title, body, forex_request_id, forex_offer_id)
    VALUES
        (v_requester_id, 'contact_revealed', 'Contact details unlocked',
         'You can now connect with the offer-maker directly.', v_agreement.request_id, v_agreement.offer_id),
        (v_offer_maker_id, 'contact_revealed', 'Requester unlocked contact',
         'You can now connect with the requester directly.', v_agreement.request_id, v_agreement.offer_id);

    INSERT INTO public.audit_logs (user_id, event_type, entity_type, entity_id, action, new_values)
    VALUES (p_caller_id, 'contact_revealed', 'forex_contact_reveals', v_reveal.id, 'unlock_forex_contact',
        JSONB_BUILD_OBJECT('agreement_id', p_agreement_id, 'revealed_at', NOW()));

    RETURN v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION private.unlock_forex_contact_internal(uuid, uuid) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.unlock_forex_contact(p_agreement_id UUID)
RETURNS JSONB
LANGUAGE sql SECURITY INVOKER
SET search_path = public AS $$
    SELECT private.unlock_forex_contact_internal(p_agreement_id, auth.uid());
$$;

REVOKE EXECUTE ON FUNCTION public.unlock_forex_contact(uuid) FROM public, anon;
GRANT  EXECUTE ON FUNCTION public.unlock_forex_contact(uuid) TO authenticated, service_role;

COMMENT ON FUNCTION public.unlock_forex_contact IS
'Requester unlocks contact details after a forex agreement is locked. Mirrors
 unlock_contact() for loans. Irreversible. Returns contact JSONB.';


-- ============================================
-- PART 8 — TRUST: make recompute_trust_aggregates() module-agnostic
-- (one row per user, combining loan + forex completed deals into a single
-- global aggregate — see BUILD_PLAN.md Trust & Reputation System v6.0)
-- ============================================

CREATE OR REPLACE FUNCTION public.recompute_trust_aggregates(p_user_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_rating NUMERIC(3,2);
    v_reviews INT;
    v_deals INT;
    v_response_hours NUMERIC;
    v_bucket TEXT;
    v_success_rate NUMERIC(5,2);
    v_score INT;
BEGIN
    -- Ratings/reviews: reviews.reviewee_id already covers both loan and forex
    -- rows (contract_id / forex_contract_id), no change needed here.
    SELECT ROUND(AVG(rating)::NUMERIC, 2), COUNT(*)
      INTO v_rating, v_reviews
      FROM reviews WHERE reviewee_id = p_user_id;

    -- Completed deals: loan contracts UNION forex contracts, one combined count.
    SELECT COUNT(*) INTO v_deals
    FROM (
        SELECT a.id FROM agreements a
        JOIN loan_offers lo ON lo.id = a.offer_id
        JOIN loan_requests lr ON lr.id = a.request_id
        JOIN contact_reveals cr ON cr.offer_id = lo.id AND cr.status = 'revealed'
        WHERE lr.borrower_id = p_user_id OR lo.lender_id = p_user_id

        UNION ALL

        SELECT fa.id FROM forex_agreements fa
        JOIN forex_offers fo ON fo.id = fa.offer_id
        JOIN forex_requests fr ON fr.id = fa.request_id
        JOIN forex_contact_reveals fcr ON fcr.offer_id = fo.id AND fcr.status = 'revealed'
        WHERE fr.requester_id = p_user_id OR fo.offer_maker_id = p_user_id
    ) combined_deals;

    -- Response time: loan offers/requests UNION forex offers/requests
    SELECT percentile_cont(0.5) WITHIN GROUP (ORDER BY response_hours)
      INTO v_response_hours
    FROM (
        SELECT EXTRACT(EPOCH FROM (lo.offered_at - lr.listed_at)) / 3600.0 AS response_hours
        FROM loan_offers lo JOIN loan_requests lr ON lr.id = lo.request_id
        WHERE lo.lender_id = p_user_id
        UNION ALL
        SELECT EXTRACT(EPOCH FROM (first_offer_at - lr.listed_at)) / 3600.0
        FROM loan_requests lr
        JOIN LATERAL (
            SELECT MIN(lo.offered_at) AS first_offer_at
            FROM loan_offers lo WHERE lo.request_id = lr.id
        ) first_offer ON first_offer.first_offer_at IS NOT NULL
        WHERE lr.borrower_id = p_user_id
        UNION ALL
        SELECT EXTRACT(EPOCH FROM (fo.offered_at - fr.listed_at)) / 3600.0
        FROM forex_offers fo JOIN forex_requests fr ON fr.id = fo.request_id
        WHERE fo.offer_maker_id = p_user_id
        UNION ALL
        SELECT EXTRACT(EPOCH FROM (first_fx_offer_at - fr.listed_at)) / 3600.0
        FROM forex_requests fr
        JOIN LATERAL (
            SELECT MIN(fo.offered_at) AS first_fx_offer_at
            FROM forex_offers fo WHERE fo.request_id = fr.id
        ) first_fx_offer ON first_fx_offer.first_fx_offer_at IS NOT NULL
        WHERE fr.requester_id = p_user_id
    ) response_times;

    v_bucket := CASE
        WHEN v_response_hours IS NULL THEN NULL
        WHEN v_response_hours <= 24 THEN 'responds_quickly'
        WHEN v_response_hours <= 72 THEN 'responds_within_a_day'
        ELSE 'responds_slowly'
    END;

    -- Success rate: loan offers/requests UNION forex offers/requests
    SELECT ROUND(
        100.0 * COUNT(*) FILTER (WHERE completed) / NULLIF(COUNT(*), 0), 2
    ) INTO v_success_rate
    FROM (
        SELECT lo.id, EXISTS (SELECT 1 FROM agreements a WHERE a.offer_id = lo.id) AS completed
        FROM loan_offers lo WHERE lo.lender_id = p_user_id
        UNION ALL
        SELECT lr.id, EXISTS (SELECT 1 FROM agreements a WHERE a.request_id = lr.id)
        FROM loan_requests lr WHERE lr.borrower_id = p_user_id
        UNION ALL
        SELECT fo.id, EXISTS (SELECT 1 FROM forex_agreements fa WHERE fa.offer_id = fo.id)
        FROM forex_offers fo WHERE fo.offer_maker_id = p_user_id
        UNION ALL
        SELECT fr.id, EXISTS (SELECT 1 FROM forex_agreements fa WHERE fa.request_id = fr.id)
        FROM forex_requests fr WHERE fr.requester_id = p_user_id
    ) participation;

    v_score := CASE WHEN v_rating IS NULL THEN NULL ELSE LEAST(100, ROUND(
        (v_rating / 5.0) * 60 + LEAST(v_deals, 4) * 5 +
        CASE v_bucket WHEN 'responds_quickly' THEN 20 WHEN 'responds_within_a_day' THEN 10 ELSE 0 END
    )::INT) END;

    INSERT INTO trust_aggregates (
        user_id, rating_avg, review_count, completed_deals_count,
        is_repeat_participant, response_time_bucket, success_rate, reliability_score, updated_at
    ) VALUES (
        p_user_id, v_rating, COALESCE(v_reviews, 0), COALESCE(v_deals, 0),
        COALESCE(v_deals, 0) >= 2, v_bucket, v_success_rate, v_score, NOW()
    ) ON CONFLICT (user_id) DO UPDATE SET
        rating_avg = EXCLUDED.rating_avg,
        review_count = EXCLUDED.review_count,
        completed_deals_count = EXCLUDED.completed_deals_count,
        is_repeat_participant = EXCLUDED.is_repeat_participant,
        response_time_bucket = EXCLUDED.response_time_bucket,
        success_rate = EXCLUDED.success_rate,
        reliability_score = EXCLUDED.reliability_score,
        updated_at = EXCLUDED.updated_at;
END;
$$;

COMMENT ON FUNCTION public.recompute_trust_aggregates IS
'v6.0: rebuilds a user''s GLOBAL trust aggregate from BOTH loan and forex on-platform
 events (never off-platform repayment/settlement behaviour). completed_deals_count,
 response_time_bucket, and success_rate all UNION across modules into one combined
 figure — there is no separate "forex score."';

-- submit_forex_review — mirrors submit_review() for forex-originated contracts
CREATE OR REPLACE FUNCTION public.submit_forex_review(
    p_contract_id UUID, p_rating SMALLINT, p_comment TEXT DEFAULT NULL
) RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_reviewer UUID := auth.uid();
    v_reviewee UUID;
    v_review_id UUID;
BEGIN
    IF v_reviewer IS NULL THEN RAISE EXCEPTION 'NIPANZE_UNAUTHORIZED'; END IF;
    IF p_rating NOT BETWEEN 1 AND 5 THEN RAISE EXCEPTION 'NIPANZE_INVALID_RATING'; END IF;

    SELECT CASE WHEN fr.requester_id = v_reviewer THEN fo.offer_maker_id ELSE fr.requester_id END
      INTO v_reviewee
    FROM forex_agreements fa
    JOIN forex_offers fo ON fo.id = fa.offer_id
    JOIN forex_requests fr ON fr.id = fa.request_id
    JOIN forex_contact_reveals fcr ON fcr.offer_id = fo.id AND fcr.status = 'revealed'
    WHERE fa.id = p_contract_id
      AND (fr.requester_id = v_reviewer OR fo.offer_maker_id = v_reviewer);
    IF v_reviewee IS NULL THEN
        RAISE EXCEPTION 'NIPANZE_REVIEW_NOT_ELIGIBLE: Reviews require a completed on-platform forex deal.';
    END IF;

    INSERT INTO reviews (forex_contract_id, reviewer_id, reviewee_id, rating, comment)
    VALUES (p_contract_id, v_reviewer, v_reviewee, p_rating, NULLIF(BTRIM(p_comment), ''))
    RETURNING id INTO v_review_id;
    PERFORM recompute_trust_aggregates(v_reviewee);
    INSERT INTO audit_logs (user_id, event_type, entity_type, entity_id, action)
    VALUES (v_reviewer, 'review_submitted', 'reviews', v_review_id, 'submit_forex_review');
    RETURN v_review_id;
END;
$$;

COMMENT ON FUNCTION public.submit_forex_review IS
'Mirrors submit_review() for forex-originated contracts. Writes to reviews.forex_contract_id
 instead of reviews.contract_id; feeds the same trust_aggregates row as loan reviews.';

-- Trust refresh on forex contact reveal — mirrors trg_refresh_trust_from_reveal
CREATE OR REPLACE FUNCTION public.trg_refresh_trust_from_forex_reveal()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_requester UUID; v_offer_maker UUID;
BEGIN
    IF NEW.status = 'revealed' AND (TG_OP = 'INSERT' OR OLD.status IS DISTINCT FROM 'revealed') THEN
        SELECT fr.requester_id, fo.offer_maker_id INTO v_requester, v_offer_maker
        FROM forex_offers fo JOIN forex_requests fr ON fr.id = fo.request_id WHERE fo.id = NEW.offer_id;
        PERFORM recompute_trust_aggregates(v_requester);
        PERFORM recompute_trust_aggregates(v_offer_maker);
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_refresh_trust_on_forex_reveal ON forex_contact_reveals;
CREATE TRIGGER trg_refresh_trust_on_forex_reveal
AFTER INSERT OR UPDATE OF status ON forex_contact_reveals
FOR EACH ROW EXECUTE FUNCTION trg_refresh_trust_from_forex_reveal();


-- ============================================
-- PART 9 — ROW-LEVEL SECURITY (new tables)
-- ============================================

ALTER TABLE currencies             ENABLE ROW LEVEL SECURITY;
ALTER TABLE forex_requests         ENABLE ROW LEVEL SECURITY;
ALTER TABLE forex_offers           ENABLE ROW LEVEL SECURITY;
ALTER TABLE forex_agreements       ENABLE ROW LEVEL SECURITY;
ALTER TABLE forex_contact_reveals  ENABLE ROW LEVEL SECURITY;

-- currencies — public reference data, admin-only writes
DROP POLICY IF EXISTS "currencies: public read" ON currencies;
CREATE POLICY "currencies: public read"
    ON currencies FOR SELECT TO authenticated, anon USING (TRUE);
DROP POLICY IF EXISTS "currencies: admin write" ON currencies;
CREATE POLICY "currencies: admin write"
    ON currencies FOR ALL TO authenticated USING (private.is_admin());

-- forex_requests — mirrors "loan_requests: ..." policies (global browse)
DROP POLICY IF EXISTS "forex_requests: marketplace read" ON forex_requests;
CREATE POLICY "forex_requests: marketplace read"
    ON forex_requests FOR SELECT TO authenticated
    USING (status = 'active' OR requester_id = auth.uid() OR private.is_admin());
DROP POLICY IF EXISTS "forex_requests: own insert" ON forex_requests;
CREATE POLICY "forex_requests: own insert"
    ON forex_requests FOR INSERT TO authenticated
    WITH CHECK (requester_id = auth.uid());
DROP POLICY IF EXISTS "forex_requests: own or admin update" ON forex_requests;
CREATE POLICY "forex_requests: own or admin update"
    ON forex_requests FOR UPDATE TO authenticated
    USING (requester_id = auth.uid() OR private.is_admin());
DROP POLICY IF EXISTS "forex_requests: admin delete" ON forex_requests;
CREATE POLICY "forex_requests: admin delete"
    ON forex_requests FOR DELETE TO authenticated USING (private.is_admin());

-- forex_offers — mirrors "loan_offers: ..." policies
DROP POLICY IF EXISTS "forex_offers: relevant parties read" ON forex_offers;
CREATE POLICY "forex_offers: relevant parties read"
    ON forex_offers FOR SELECT TO authenticated
    USING (
        offer_maker_id = auth.uid()
        OR EXISTS (
            SELECT 1 FROM forex_requests fr
             WHERE fr.id = forex_offers.request_id AND fr.requester_id = auth.uid()
        )
        OR private.is_admin()
    );
DROP POLICY IF EXISTS "forex_offers: offer_maker insert" ON forex_offers;
CREATE POLICY "forex_offers: offer_maker insert"
    ON forex_offers FOR INSERT TO authenticated
    WITH CHECK (offer_maker_id = auth.uid());
DROP POLICY IF EXISTS "forex_offers: offer_maker withdraw or admin" ON forex_offers;
CREATE POLICY "forex_offers: offer_maker withdraw or admin"
    ON forex_offers FOR UPDATE TO authenticated
    USING ((offer_maker_id = auth.uid() AND status = 'pending') OR private.is_admin());

-- forex_agreements — mirrors "agreements: ..." policies
DROP POLICY IF EXISTS "forex_agreements: matched parties read" ON forex_agreements;
CREATE POLICY "forex_agreements: matched parties read"
    ON forex_agreements FOR SELECT TO authenticated
    USING (
        EXISTS (SELECT 1 FROM forex_requests fr WHERE fr.id = forex_agreements.request_id AND fr.requester_id = auth.uid())
        OR EXISTS (SELECT 1 FROM forex_offers fo WHERE fo.id = forex_agreements.offer_id AND fo.offer_maker_id = auth.uid())
        OR private.is_admin()
    );
DROP POLICY IF EXISTS "forex_agreements: service role insert" ON forex_agreements;
CREATE POLICY "forex_agreements: service role insert"
    ON forex_agreements FOR INSERT TO service_role WITH CHECK (TRUE);
DROP POLICY IF EXISTS "forex_agreements: service role update" ON forex_agreements;
CREATE POLICY "forex_agreements: service role update"
    ON forex_agreements FOR UPDATE TO service_role USING (TRUE) WITH CHECK (TRUE);
DROP POLICY IF EXISTS "forex_agreements: admin all" ON forex_agreements;
CREATE POLICY "forex_agreements: admin all"
    ON forex_agreements FOR ALL TO authenticated USING (private.is_admin());

-- forex_contact_reveals — mirrors "contact_reveals: ..." policies
DROP POLICY IF EXISTS "forex_contact_reveals: matched parties read" ON forex_contact_reveals;
CREATE POLICY "forex_contact_reveals: matched parties read"
    ON forex_contact_reveals FOR SELECT TO authenticated
    USING (
        revealed_by = auth.uid()
        OR EXISTS (SELECT 1 FROM forex_offers fo WHERE fo.id = forex_contact_reveals.offer_id AND fo.offer_maker_id = auth.uid())
        OR private.is_admin()
    );
DROP POLICY IF EXISTS "forex_contact_reveals: own insert" ON forex_contact_reveals;
CREATE POLICY "forex_contact_reveals: own insert"
    ON forex_contact_reveals FOR INSERT TO authenticated
    WITH CHECK (revealed_by = auth.uid());
DROP POLICY IF EXISTS "forex_contact_reveals: admin write" ON forex_contact_reveals;
CREATE POLICY "forex_contact_reveals: admin write"
    ON forex_contact_reveals FOR ALL TO authenticated USING (private.is_admin());


-- ============================================
-- PART 10 — REALTIME PUBLICATION
-- ============================================

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_publication_tables
        WHERE pubname = 'supabase_realtime' AND tablename = 'forex_requests'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE forex_requests;
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_publication_tables
        WHERE pubname = 'supabase_realtime' AND tablename = 'forex_offers'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE forex_offers;
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_publication_tables
        WHERE pubname = 'supabase_realtime' AND tablename = 'forex_agreements'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE forex_agreements;
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_publication_tables
        WHERE pubname = 'supabase_realtime' AND tablename = 'forex_contact_reveals'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE forex_contact_reveals;
    END IF;
END $$;


-- ============================================
-- PART 11 — GRANTS
-- ============================================

GRANT SELECT ON currencies         TO authenticated, anon;
GRANT SELECT ON v_forex_listings   TO authenticated, anon;
GRANT SELECT ON v_forex_offers     TO authenticated, anon;

GRANT EXECUTE ON FUNCTION get_public_forex_offers(UUID)                 TO authenticated;
REVOKE EXECUTE ON FUNCTION get_public_forex_offers(UUID) FROM anon;

REVOKE EXECUTE ON FUNCTION public.accept_forex_offer(uuid, uuid, uuid) FROM public, anon;
GRANT  EXECUTE ON FUNCTION public.accept_forex_offer(uuid, uuid, uuid) TO authenticated, service_role;

REVOKE EXECUTE ON FUNCTION public.unlock_forex_contact(uuid) FROM public, anon;
GRANT  EXECUTE ON FUNCTION public.unlock_forex_contact(uuid) TO authenticated, service_role;

GRANT EXECUTE ON FUNCTION public.submit_forex_review(UUID, SMALLINT, TEXT) TO authenticated;

-- Blanket grants for the new tables, matching the blanket grants already
-- present at the end of the v5.0 schema for existing tables.
GRANT SELECT, INSERT, UPDATE, DELETE ON forex_requests, forex_offers, forex_agreements, forex_contact_reveals, currencies
    TO authenticated, service_role;
GRANT SELECT, INSERT, UPDATE ON forex_requests, forex_offers
    TO anon;


-- ============================================
-- PART 12 — DATABASE COMMENT (bump version marker)
-- ============================================

DO $$
DECLARE db TEXT;
BEGIN
    SELECT current_database() INTO db;
    EXECUTE FORMAT('COMMENT ON DATABASE %I IS %L', db,
        'Nipanze v6.0 — Non-custodial Loans + Forex matchmaking marketplace across a 7-market '
        'expansion list (UG live, KE/TZ/RW/NG/ZA/EG planned), Uganda-first. Two feature-modules '
        '(Loans, Forex) on one shared schema, auth, subscription_plan, trust system, and '
        'selective-transparency machinery. Country is explicit, indexed, and locked at creation '
        'for both loan and forex listings; trust signals are global across every market AND both '
        'modules. Posting is free on either module. Making offers requires a Lender/Pro '
        'subscription. Contact revealed only after offer acceptance. Platform never holds, '
        'converts, or tracks funds or currency between matched users, in any market, on either module.');
END $$;


-- ============================================
-- END OF PATCH v5.0 → v6.0
--
-- Post-run sanity checks you may want to run:
--   SELECT code, name, is_active, forex_enabled FROM countries ORDER BY code;
--   SELECT code, forex_trading_enabled FROM currencies ORDER BY code;
--   SELECT * FROM v_forex_listings LIMIT 5;
--   SELECT proname FROM pg_proc WHERE proname LIKE '%forex%' ORDER BY proname;
--
-- Still open / not in this patch (flagged in BUILD_PLAN.md, not schema work):
--   - system_settings per-country overrides for min/max amounts etc. (insert
--     rows with country set as each market approaches its own Stage 6 launch)
--   - Flutter app layer: ForexCreatePage, ForexDetailPage, SendRateReceivePanel,
--     MyForexRequestsPage, marketplace All/Loans/Forex filter row
--   - Flipping any country.is_active / countries.forex_enabled / any
--     currencies.forex_trading_enabled to TRUE — all default FALSE, on purpose,
--     pending each market/currency's own compliance review per BUILD_PLAN.md
-- ============================================

-- ============================================================
-- END MERGED SECTION: patch_schema_v6.sql
-- ============================================================


-- ============================================================
-- BEGIN MERGED SECTION: patch_seed_v6.sql
-- ============================================================

-- ============================================
-- NIPANZE — Patch v6.1: backfill missing profile text values
-- Paste into Supabase Cloud SQL Editor and run once. Idempotent.
--
-- What this fixes:
--   1. profiles.district = NULL for any real (non-seed) sign-up — the
--      on_auth_user_created trigger never set it, so onboarding "district"
--      never had a value. Backfilled to a sensible per-country default
--      (matches the seed script's own choice of city per market) and only
--      touches rows that are currently NULL — never overwrites a value a
--      user actually entered.
--   2. profiles.income_currency silently wrong for real sign-ups — the
--      column default is 'UGX', and handle_new_auth_user() never set it,
--      so e.g. a Kenya sign-up got 'UGX' instead of 'KES'. Backfilled from
--      countries.currency_code for any row that doesn't already match its
--      own country's currency.
--   3. Root cause fixed: handle_new_auth_user() now sets income_currency
--      from countries.currency_code at insert time, so future sign-ups
--      never hit this again. district is intentionally left for the user
--      to fill in during onboarding (no good default at signup time,
--      before they've picked a district) — only backfilled here for the
--      rows that already exist without one.
-- ============================================


-- 1. Backfill district for any profile currently NULL, using the same
-- per-market default city the seed script already uses for that country.
-- Only touches NULL rows — never overwrites a real user-entered value.
UPDATE profiles p
SET district = CASE p.country
    WHEN 'UG' THEN 'Central'
    WHEN 'KE' THEN 'Nairobi'
    WHEN 'TZ' THEN 'Dar es Salaam'
    WHEN 'RW' THEN 'Kigali'
    WHEN 'BI' THEN 'Bujumbura'
    WHEN 'SS' THEN 'Juba'
    WHEN 'CD' THEN 'Kinshasa'
    WHEN 'SO' THEN 'Mogadishu'
    WHEN 'NG' THEN 'Lagos'
    WHEN 'ZA' THEN 'Johannesburg'
    WHEN 'EG' THEN 'Cairo'
    ELSE p.district
END
WHERE p.district IS NULL;

-- 2. Backfill income_currency for any profile whose value doesn't match
-- its own country's currency (covers both NULL and the silently-wrong
-- 'UGX' default from real sign-ups outside Uganda).
UPDATE profiles p
SET income_currency = c.currency_code
FROM countries c
WHERE p.country = c.code
  AND (p.income_currency IS NULL OR p.income_currency <> c.currency_code);

-- 3. Fix the root cause: handle_new_auth_user() now resolves and sets
-- income_currency from countries.currency_code, exactly the same way it
-- already resolves country. Everything else in the function is unchanged.
CREATE OR REPLACE FUNCTION public.handle_new_auth_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_country TEXT;
    v_currency TEXT;
BEGIN
    v_country := UPPER(COALESCE(NEW.raw_user_meta_data->>'country_code', 'UG'));
    IF NOT EXISTS (SELECT 1 FROM public.countries WHERE code = v_country) THEN
        v_country := 'UG';
    END IF;

    SELECT currency_code INTO v_currency FROM public.countries WHERE code = v_country;
    v_currency := COALESCE(v_currency, 'UGX');

    INSERT INTO public.profiles (
        id, full_name, account_status, is_admin, country, income_currency
    )
    VALUES (
        NEW.id,
        COALESCE(NEW.raw_user_meta_data->>'full_name', SPLIT_PART(NEW.email, '@', 1)),
        'pending_verification',
        FALSE,
        v_country,
        v_currency
    )
    ON CONFLICT (id) DO NOTHING;

    -- Every new user gets a free subscription (can browse marketplace and post requests)
    INSERT INTO public.subscriptions (user_id, plan, status, amount_minor_units)
    VALUES (NEW.id, 'free', 'active', 0)
    ON CONFLICT (user_id) WHERE status = 'active' DO NOTHING;

    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.handle_new_auth_user IS
'v6.1: now also resolves income_currency from countries.currency_code at signup (previously
 left at the column default of UGX regardless of the new user''s country). Syncs auth.users →
 public.profiles on every registration, resolves the new profile''s country (defaulting to UG
 if the onboarding suggestion is missing or unrecognized), and provisions a free subscription.';


-- ============================================
-- Post-run sanity check:
--   SELECT id, full_name, country, district, income_currency FROM profiles
--   WHERE id::text NOT LIKE '10000000%' ORDER BY created_at;
-- Should show every non-seed profile with a non-null district and an
-- income_currency matching its own country's currency.
-- ============================================

-- ============================================================
-- END MERGED SECTION: patch_seed_v6.sql
-- ============================================================


-- ============================================================
-- BEGIN MERGED SECTION: patch_seed_forex.sql
-- ============================================================

-- ============================================
-- NIPANZE — Patch v6.2: Forex seed data
-- Paste into Supabase Cloud SQL Editor and run once. Idempotent.
--
-- The v6.0 schema patch (the Patch v6 Schema section in this file) added the Forex module tables, but
-- sql/seed.sql predates it and has no forex data at all — every currency
-- still has forex_trading_enabled = FALSE and no market has
-- countries.forex_enabled = TRUE, so v_forex_listings is empty and there's
-- nothing to develop or demo against.
--
-- This patch:
--   1. Enables forex for Uganda (countries.forex_enabled) and clears UGX/KES
--      for trading (currencies.forex_trading_enabled) — the minimum needed
--      for a UGX → KES demo pair, matching "Uganda can go live for forex
--      independently of other markets" from BUILD_PLAN.md.
--   2. Adds the two forex-specific test accounts named in BUILD_PLAN.md's
--      Test Accounts table: mutesi.grace@gmail.com (UG, Lender) and
--      nonparticipant.tester@gmail.com (UG, Free).
--   3. Seeds one ACTIVE UGX → KES forex_request (mutesi.grace) with two
--      pending offers from existing UG lenders — for selective-transparency
--      testing (participant vs non-participant view).
--   4. Seeds one CONTRACTED forex_request+offer+agreement+contact_reveal+
--      review — for trust-aggregate testing (confirms a forex deal feeds
--      the SAME global trust_aggregates row as a loan deal would).
--   5. Recomputes trust_aggregates for every user touched, since the
--      contracted flow is inserted with triggers bypassed (session_replication_role
--      = replica), the same pattern sql/seed.sql already uses for loan
--      agreements/contact_reveals.
--
-- Safe to re-run: every INSERT is ON CONFLICT DO NOTHING; the UPDATEs in
-- step 1 are idempotent by nature.
-- ============================================


-- ============================================
-- STEP 1 — Clear Uganda + UGX/KES for forex (minimum viable demo pair)
-- ============================================

UPDATE countries SET forex_enabled = TRUE WHERE code = 'UG';

UPDATE currencies SET forex_trading_enabled = TRUE WHERE code IN ('UGX', 'KES');

-- Sanity: SELECT code, forex_enabled FROM countries WHERE code = 'UG';
--         SELECT code, forex_trading_enabled FROM currencies WHERE code IN ('UGX','KES');


-- ============================================
-- STEP 2 — Forex-specific test accounts (per BUILD_PLAN.md Test Accounts)
-- ============================================

INSERT INTO auth.users (
    id, instance_id, email, encrypted_password,
    email_confirmed_at, created_at, updated_at,
    raw_app_meta_data, raw_user_meta_data,
    is_super_admin, role, aud,
    confirmation_token, recovery_token,
    email_change_token_new, email_change,
    email_change_token_current, phone_change,
    phone_change_token, reauthentication_token
) VALUES
('10000000-0000-0000-0000-000000000137', '00000000-0000-0000-0000-000000000000', 'mutesi.grace@gmail.com', crypt('Test1234!', gen_salt('bf')),
 NOW(), '2026-03-01 09:00:00', '2026-03-01 09:00:00', '{"provider":"email","providers":["email"]}', '{"full_name":"Mutesi Grace","country_code":"UG"}',
 FALSE, 'authenticated', 'authenticated', '', '', '', '', '', '', '', ''),
('10000000-0000-0000-0000-000000000138', '00000000-0000-0000-0000-000000000000', 'nonparticipant.tester@gmail.com', crypt('Test1234!', gen_salt('bf')),
 NOW(), '2026-03-01 09:05:00', '2026-03-01 09:05:00', '{"provider":"email","providers":["email"]}', '{"full_name":"Nonparticipant Tester","country_code":"UG"}',
 FALSE, 'authenticated', 'authenticated', '', '', '', '', '', '', '', '')
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.profiles (
    id, full_name, phone, district, country, employment_type, employer_name,
    monthly_income, income_currency, phone_verified_at, account_status, is_admin, created_at
) VALUES
('10000000-0000-0000-0000-000000000137', 'Mutesi Grace', '+256722334455', 'Central', 'UG', 'small_business_owner', 'Grace Forex Traders', 3800000, 'UGX', '2026-03-01 09:10:00', 'active', FALSE, '2026-03-01 09:00:00'),
('10000000-0000-0000-0000-000000000138', 'Nonparticipant Tester', '+256722556677', 'Central', 'UG', 'employed', 'Local Employer Ltd', 2600000, 'UGX', NULL, 'active', FALSE, '2026-03-01 09:05:00')
ON CONFLICT (id) DO UPDATE SET
    full_name = EXCLUDED.full_name, phone = EXCLUDED.phone, district = EXCLUDED.district,
    country = EXCLUDED.country, employment_type = EXCLUDED.employment_type,
    employer_name = EXCLUDED.employer_name, monthly_income = EXCLUDED.monthly_income,
    income_currency = EXCLUDED.income_currency, phone_verified_at = EXCLUDED.phone_verified_at,
    account_status = EXCLUDED.account_status;

INSERT INTO public.subscriptions (user_id, plan, status, amount_minor_units, started_at, expires_at, auto_renew) VALUES
('10000000-0000-0000-0000-000000000137', 'lender', 'active', 35000, '2026-03-01 09:00:00', '2028-03-01 09:00:00', TRUE),
('10000000-0000-0000-0000-000000000138', 'free',   'active', 0,     '2026-03-01 09:05:00', NULL, TRUE)
ON CONFLICT (user_id) DO UPDATE SET
    plan = EXCLUDED.plan, status = EXCLUDED.status, amount_minor_units = EXCLUDED.amount_minor_units,
    started_at = EXCLUDED.started_at, expires_at = EXCLUDED.expires_at, auto_renew = EXCLUDED.auto_renew;


-- ============================================
-- STEP 3 — Forex listings, offers, agreement, reveal, review
-- Triggers bypassed (session_replication_role = replica) for the same
-- reason sql/seed.sql already bypasses them on loan_requests/loan_offers/
-- agreements: seed timestamps and pre-computed snapshot data don't need to
-- re-run the same server-side validation that already ran for real traffic.
-- ============================================

SET session_replication_role = 'replica';

-- 3-pre. Additional ACTIVE UGX → KES listings (appear BEFORE the primary
-- demo listings so the Forex tab is populated with a realistic feed)

INSERT INTO forex_requests (
    id, requester_id, country, currency_held, currency_needed, amount,
    preferred_rate, settlement_preference, is_urgent, terms_locked_at,
    number_of_offers, status, listed_at, expires_at, created_at
) VALUES
-- Listing A: small urgent transfer
('c3000000-0000-0000-0000-000000000003', '10000000-0000-0000-0000-000000000008', 'UG',
 'UGX', 'KES', 500000, 0.0285, 'Mobile money (Airtel Money), Kampala', TRUE,
 NOW() - INTERVAL '1 hour', 1, 'active', NOW() - INTERVAL '1 hour', NOW() + INTERVAL '6 days',
 NOW() - INTERVAL '1 hour'),
-- Listing B: mid-range in-person exchange
('c3000000-0000-0000-0000-000000000004', '10000000-0000-0000-0000-000000000009', 'UG',
 'UGX', 'KES', 1200000, NULL, 'In-person exchange, Kampala CBD', FALSE,
 NOW() - INTERVAL '5 hours', 0, 'active', NOW() - INTERVAL '5 hours', NOW() + INTERVAL '7 days',
 NOW() - INTERVAL '5 hours'),
-- Listing C: larger bank-transfer exchange
('c3000000-0000-0000-0000-000000000005', '10000000-0000-0000-0000-000000000010', 'UG',
 'UGX', 'KES', 3500000, 0.0291, 'Bank transfer (Equity Bank)', FALSE,
 NOW() - INTERVAL '18 hours', 2, 'active', NOW() - INTERVAL '18 hours', NOW() + INTERVAL '4 days',
 NOW() - INTERVAL '18 hours')
ON CONFLICT (id) DO NOTHING;

INSERT INTO forex_offers (
    id, request_id, offer_maker_id, rate_offered, amount_available, terms,
    terms_locked_at, status, offered_at, created_at
) VALUES
-- Offer on Listing A
('d3000000-0000-0000-0000-000000000010', 'c3000000-0000-0000-0000-000000000003',
 '10000000-0000-0000-0000-000000000011', 0.0284, 500000, 'Can settle via Airtel Money same day.',
 NOW() - INTERVAL '30 minutes', 'pending', NOW() - INTERVAL '30 minutes', NOW() - INTERVAL '30 minutes'),
-- Offer 1 on Listing C
('d3000000-0000-0000-0000-000000000011', 'c3000000-0000-0000-0000-000000000005',
 '10000000-0000-0000-0000-000000000012', 0.0290, 3500000, 'Bank transfer within 48 hours, Equity Bank.',
 NOW() - INTERVAL '12 hours', 'pending', NOW() - INTERVAL '12 hours', NOW() - INTERVAL '12 hours'),
-- Offer 2 on Listing C
('d3000000-0000-0000-0000-000000000012', 'c3000000-0000-0000-0000-000000000005',
 '10000000-0000-0000-0000-000000000013', 0.0292, 3000000, 'Partial amount OK; bank transfer within 2 days.',
 NOW() - INTERVAL '8 hours', 'pending', NOW() - INTERVAL '8 hours', NOW() - INTERVAL '8 hours')
ON CONFLICT (id) DO NOTHING;

-- 3a. ACTIVE listing — two pending offers, for selective-transparency testing
INSERT INTO forex_requests (
    id, requester_id, country, currency_held, currency_needed, amount,
    preferred_rate, settlement_preference, is_urgent, terms_locked_at,
    number_of_offers, status, listed_at, expires_at, created_at
) VALUES
('c3000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000137', 'UG',
 'UGX', 'KES', 2000000, NULL, 'Mobile money (MTN MoMo), Kampala', FALSE,
 NOW() - INTERVAL '2 days', 2, 'active', NOW() - INTERVAL '2 days', NOW() + INTERVAL '5 days',
 NOW() - INTERVAL '2 days')
ON CONFLICT (id) DO NOTHING;

INSERT INTO forex_offers (
    id, request_id, offer_maker_id, rate_offered, amount_available, terms,
    terms_locked_at, status, offered_at, created_at
) VALUES
('d3000000-0000-0000-0000-000000000001', 'c3000000-0000-0000-0000-000000000001',
 '10000000-0000-0000-0000-000000000008', 0.0286, 2000000, 'Can settle via bank transfer within 24 hours.',
 NOW() - INTERVAL '1 day 12 hours', 'pending', NOW() - INTERVAL '1 day 12 hours', NOW() - INTERVAL '1 day 12 hours'),
('d3000000-0000-0000-0000-000000000002', 'c3000000-0000-0000-0000-000000000001',
 '10000000-0000-0000-0000-000000000009', 0.0290, 1500000, 'Prefer mobile money settlement, can do partial amount.',
 NOW() - INTERVAL '20 hours', 'pending', NOW() - INTERVAL '20 hours', NOW() - INTERVAL '20 hours')
ON CONFLICT (id) DO NOTHING;

-- 3b. CONTRACTED listing — accepted offer, locked agreement, revealed
-- contact, one review — for global trust-aggregate testing
INSERT INTO forex_requests (
    id, requester_id, country, currency_held, currency_needed, amount,
    preferred_rate, settlement_preference, is_urgent, terms_locked_at,
    number_of_offers, status, listed_at, expires_at, contracted_at, created_at
) VALUES
('c3000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000137', 'UG',
 'UGX', 'KES', 900000, NULL, 'In-person exchange, Kampala city centre', FALSE,
 NOW() - INTERVAL '10 days', 1, 'contracted', NOW() - INTERVAL '10 days', NOW() - INTERVAL '3 days',
 NOW() - INTERVAL '7 days', NOW() - INTERVAL '10 days')
ON CONFLICT (id) DO NOTHING;

INSERT INTO forex_offers (
    id, request_id, offer_maker_id, rate_offered, amount_available, terms,
    terms_locked_at, status, offered_at, accepted_at, created_at
) VALUES
('d3000000-0000-0000-0000-000000000003', 'c3000000-0000-0000-0000-000000000002',
 '10000000-0000-0000-0000-000000000010', 0.0288, 900000, 'Can meet in person same week.',
 NOW() - INTERVAL '9 days', 'accepted', NOW() - INTERVAL '9 days', NOW() - INTERVAL '7 days', NOW() - INTERVAL '9 days')
ON CONFLICT (id) DO NOTHING;

INSERT INTO forex_agreements (
    id, offer_id, request_id, rate_agreed, amount_agreed, settlement_terms,
    agreement_text, agreement_snapshot, status,
    requester_agreed_at, offer_maker_agreed_at, locked_at
) VALUES
('b1000000-0000-0000-0000-000000000001', 'd3000000-0000-0000-0000-000000000003', 'c3000000-0000-0000-0000-000000000002',
 0.0288, 900000, 'In-person exchange, Kampala city centre',
 'EXCHANGE AGREEMENT between Mutesi Grace and George Mulindwa. UGX 900,000 at rate 0.0288 (UGX -> KES). Settlement: in-person exchange, Kampala city centre.',
 '{"request_id":"c3000000-0000-0000-0000-000000000002","offer_id":"d3000000-0000-0000-0000-000000000003","requester_id":"10000000-0000-0000-0000-000000000137","offer_maker_id":"10000000-0000-0000-0000-000000000010","country":"UG","currency_held":"UGX","currency_needed":"KES","amount_agreed":900000,"rate_agreed":0.0288,"settlement_terms":"In-person exchange, Kampala city centre"}'::jsonb,
 'locked'::agreement_status_enum, NOW() - INTERVAL '7 days', NOW() - INTERVAL '7 days', NOW() - INTERVAL '7 days')
ON CONFLICT (offer_id) DO NOTHING;

INSERT INTO forex_contact_reveals (id, offer_id, request_id, revealed_by, status, revealed_at, created_at) VALUES
('f2000000-0000-0000-0000-000000000001', 'd3000000-0000-0000-0000-000000000003', 'c3000000-0000-0000-0000-000000000002',
 '10000000-0000-0000-0000-000000000137', 'revealed', NOW() - INTERVAL '6 days', NOW() - INTERVAL '7 days')
ON CONFLICT (offer_id) DO NOTHING;

INSERT INTO reviews (id, forex_contract_id, reviewer_id, reviewee_id, rating, comment, created_at) VALUES
('e6000000-0000-0000-0000-000000000001', 'b1000000-0000-0000-0000-000000000001',
 '10000000-0000-0000-0000-000000000137', '10000000-0000-0000-0000-000000000010', 5,
 'Smooth exchange, met on time and rate was exactly as agreed.', NOW() - INTERVAL '5 days')
ON CONFLICT (forex_contract_id, reviewer_id) WHERE forex_contract_id IS NOT NULL DO NOTHING;

SET session_replication_role = 'origin';


-- ============================================
-- STEP 4 — Watchlist + notifications (small, realistic touch)
-- ============================================

INSERT INTO watchlist (id, user_id, forex_request_id, added_at) VALUES
('e8000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000138', 'c3000000-0000-0000-0000-000000000001', NOW() - INTERVAL '1 day')
ON CONFLICT (user_id, forex_request_id) WHERE forex_request_id IS NOT NULL DO NOTHING;

INSERT INTO notifications (id, user_id, type, title, body, is_read, forex_request_id, forex_offer_id, created_at) VALUES
('e7000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000137', 'offer_received', 'New forex offer received',
 'William Kasujja made an offer on your UGX → KES exchange request.', FALSE,
 'c3000000-0000-0000-0000-000000000001', 'd3000000-0000-0000-0000-000000000001', NOW() - INTERVAL '1 day 12 hours'),
('e7000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000137', 'offer_received', 'New forex offer received',
 'Catherine Namboze made an offer on your UGX → KES exchange request.', FALSE,
 'c3000000-0000-0000-0000-000000000001', 'd3000000-0000-0000-0000-000000000002', NOW() - INTERVAL '20 hours'),
('e7000000-0000-0000-0000-000000000003', '10000000-0000-0000-0000-000000000137', 'contact_revealed', 'Contact details unlocked',
 'You can now connect with George Mulindwa directly.', TRUE,
 'c3000000-0000-0000-0000-000000000002', 'd3000000-0000-0000-0000-000000000003', NOW() - INTERVAL '6 days'),
('e7000000-0000-0000-0000-000000000004', '10000000-0000-0000-0000-000000000010', 'contact_revealed', 'Requester unlocked contact',
 'You can now connect with the requester directly.', TRUE,
 'c3000000-0000-0000-0000-000000000002', 'd3000000-0000-0000-0000-000000000003', NOW() - INTERVAL '6 days')
ON CONFLICT DO NOTHING;


-- ============================================
-- STEP 5 — Recompute trust aggregates for every user touched
-- (triggers were bypassed in Step 3, so this does what
-- trg_refresh_trust_on_forex_reveal would normally have done automatically)
-- ============================================

SELECT public.recompute_trust_aggregates('10000000-0000-0000-0000-000000000137'); -- Mutesi Grace
SELECT public.recompute_trust_aggregates('10000000-0000-0000-0000-000000000010'); -- George Mulindwa


-- ============================================
-- VERIFICATION
-- ============================================

SELECT '✅ Forex seed v6.2 inserted — UG+forex_enabled, UGX/KES tradeable, 2 test accounts, 1 active listing (2 pending offers), 1 contracted listing (agreement+reveal+review)' AS status;

SELECT request_id, currency_held, currency_needed, amount, country, status, number_of_offers, rate_coverage_tier
FROM v_forex_listings
ORDER BY listed_at DESC;

SELECT ta.user_id, p.full_name, ta.rating_avg, ta.review_count, ta.completed_deals_count, ta.is_repeat_participant
FROM trust_aggregates ta
JOIN profiles p ON p.id = ta.user_id
WHERE ta.user_id IN (
    '10000000-0000-0000-0000-000000000137',
    '10000000-0000-0000-0000-000000000010'
);

-- ============================================================
-- END MERGED SECTION: patch_seed_forex.sql
-- ============================================================


-- ============================================================
-- BEGIN MERGED SECTION: patch_seed_forex2.sql
-- ============================================================

-- ============================================
-- NIPANZE — Patch v6.3: Extra UGX → KES forex listings
-- Paste into Supabase Cloud SQL Editor and run once. Idempotent.
--
-- Prerequisite: the Forex Seed Data v6.2 section in this file must already be applied.
--
-- Adds 3 more ACTIVE UGX → KES forex_requests with varied amounts,
-- settlement methods, and offer counts — so the Forex tab shows a
-- realistic populated feed matching the marketplace mockup.
--
-- Safe to re-run: every INSERT is ON CONFLICT DO NOTHING.
-- ============================================


SET session_replication_role = 'replica';

-- ── forex_requests ───────────────────────────────────────────────────────────

INSERT INTO forex_requests (
    id, requester_id, country, currency_held, currency_needed, amount,
    preferred_rate, settlement_preference, is_urgent, terms_locked_at,
    number_of_offers, status, listed_at, expires_at, created_at
) VALUES
-- Listing A: small urgent Airtel Money transfer
('c3000000-0000-0000-0000-000000000003',
 '10000000-0000-0000-0000-000000000008', 'UG',
 'UGX', 'KES', 500000, 0.0285,
 'Mobile money (Airtel Money), Kampala', TRUE,
 NOW() - INTERVAL '1 hour', 1, 'active',
 NOW() - INTERVAL '1 hour', NOW() + INTERVAL '6 days',
 NOW() - INTERVAL '1 hour'),

-- Listing B: mid-range in-person exchange, no offers yet
('c3000000-0000-0000-0000-000000000004',
 '10000000-0000-0000-0000-000000000009', 'UG',
 'UGX', 'KES', 1200000, NULL,
 'In-person exchange, Kampala CBD', FALSE,
 NOW() - INTERVAL '5 hours', 0, 'active',
 NOW() - INTERVAL '5 hours', NOW() + INTERVAL '7 days',
 NOW() - INTERVAL '5 hours'),

-- Listing C: larger bank-transfer exchange with 2 offers
('c3000000-0000-0000-0000-000000000005',
 '10000000-0000-0000-0000-000000000010', 'UG',
 'UGX', 'KES', 3500000, 0.0291,
 'Bank transfer (Equity Bank)', FALSE,
 NOW() - INTERVAL '18 hours', 2, 'active',
 NOW() - INTERVAL '18 hours', NOW() + INTERVAL '4 days',
 NOW() - INTERVAL '18 hours')
ON CONFLICT (id) DO NOTHING;

-- ── forex_offers ─────────────────────────────────────────────────────────────

INSERT INTO forex_offers (
    id, request_id, offer_maker_id, rate_offered, amount_available, terms,
    terms_locked_at, status, offered_at, created_at
) VALUES
-- Offer on Listing A
('d3000000-0000-0000-0000-000000000010',
 'c3000000-0000-0000-0000-000000000003',
 '10000000-0000-0000-0000-000000000011',
 0.0284, 500000, 'Can settle via Airtel Money same day.',
 NOW() - INTERVAL '30 minutes', 'pending',
 NOW() - INTERVAL '30 minutes', NOW() - INTERVAL '30 minutes'),

-- Offer 1 on Listing C
('d3000000-0000-0000-0000-000000000011',
 'c3000000-0000-0000-0000-000000000005',
 '10000000-0000-0000-0000-000000000012',
 0.0290, 3500000, 'Bank transfer within 48 hours, Equity Bank.',
 NOW() - INTERVAL '12 hours', 'pending',
 NOW() - INTERVAL '12 hours', NOW() - INTERVAL '12 hours'),

-- Offer 2 on Listing C
('d3000000-0000-0000-0000-000000000012',
 'c3000000-0000-0000-0000-000000000005',
 '10000000-0000-0000-0000-000000000013',
 0.0292, 3000000, 'Partial amount OK; bank transfer within 2 days.',
 NOW() - INTERVAL '8 hours', 'pending',
 NOW() - INTERVAL '8 hours', NOW() - INTERVAL '8 hours')
ON CONFLICT (id) DO NOTHING;

SET session_replication_role = 'origin';


-- ── VERIFICATION ─────────────────────────────────────────────────────────────

SELECT '✅ Forex seed v6.3 inserted — 3 extra UGX→KES active listings' AS status;

SELECT request_id, currency_held, currency_needed, amount,
       settlement_preference, status, number_of_offers, listed_at
FROM v_forex_listings
ORDER BY listed_at DESC;

-- ============================================================
-- END MERGED SECTION: patch_seed_forex2.sql
-- ============================================================


-- ============================================================
-- BEGIN MERGED SECTION: patch_seed_forex3.sql
-- ============================================================

-- ============================================
-- NIPANZE — Patch v6.4: Multi-currency forex seed (popular EA + Africa pairs)
-- Paste into Supabase Cloud SQL Editor and run once. Idempotent.
--
-- Prerequisite: the Patch v6 Schema section in this file and the Forex Seed Data v6.2 section in this file must
-- already be applied. the Extra UGX to KES Forex Listings section in this file is optional.
--
-- What this does:
--   1. Enables forex_enabled for all active/seeded markets (UG, KE, TZ, RW,
--      NG, ZA, EG — and BI/SS/CD/SO which have seed users).
--   2. Enables forex_trading_enabled for all 8 currencies (UGX, KES, TZS,
--      RWF, NGN, ZAR, EGP, USD).
--   3. Seeds 16 diverse active forex_requests across the most popular
--      cross-border currency pairs in East + broader Africa, using existing
--      seeded user IDs from seed.sql. All are P2P — no platform-held funds.
--
-- Currency pairs covered:
--   UGX ↔ KES  (Uganda ↔ Kenya)        — most popular corridor
--   UGX ↔ TZS  (Uganda ↔ Tanzania)
--   UGX ↔ RWF  (Uganda ↔ Rwanda)
--   KES ↔ TZS  (Kenya ↔ Tanzania)
--   KES ↔ NGN  (Kenya ↔ Nigeria)
--   KES ↔ ZAR  (Kenya ↔ South Africa)
--   KES ↔ USD  (Kenya ↔ USD — remittance)
--   TZS ↔ RWF  (Tanzania ↔ Rwanda)
--   TZS ↔ USD  (Tanzania ↔ USD)
--   RWF ↔ USD  (Rwanda ↔ USD)
--   NGN ↔ USD  (Nigeria ↔ USD — very high volume corridor)
--   ZAR ↔ USD  (South Africa ↔ USD)
--   ZAR ↔ NGN  (South Africa ↔ Nigeria)
--   EGP ↔ USD  (Egypt ↔ USD)
--   UGX ↔ USD  (Uganda ↔ USD)
--   NGN ↔ ZAR  (Nigeria ↔ South Africa)
--
-- UUID ranges per country (from seed.sql):
--   UG: 001-017  | KE: 018-034 | TZ: 035-051 | RW: 052-068
--   BI: 069-085  | SS: 086-102 | CD: 103-119  | SO: 120-136
--   Forex test accounts: 137 (Mutesi Grace/UG), 138 (Nonparticipant/UG)
--
-- Safe to re-run: all INSERTs are ON CONFLICT DO NOTHING.
-- ============================================


-- ============================================
-- STEP 1 — Enable forex for all markets + all currencies
-- ============================================

-- All seeded countries — forex is P2P, no platform funds held
UPDATE countries
SET forex_enabled = TRUE
WHERE code IN ('UG','KE','TZ','RW','BI','SS','CD','SO','NG','ZA','EG');

-- All market currencies + USD cleared for trading
UPDATE currencies
SET forex_trading_enabled = TRUE
WHERE code IN ('UGX','KES','TZS','RWF','NGN','ZAR','EGP','USD');


-- ============================================
-- STEP 2 — Seed diverse forex_requests + offers
-- ============================================

SET session_replication_role = 'replica';

INSERT INTO forex_requests (
    id, requester_id, country, currency_held, currency_needed, amount,
    preferred_rate, settlement_preference, is_urgent, terms_locked_at,
    number_of_offers, status, listed_at, expires_at, created_at
) VALUES

-- ── UGX → KES (Uganda → Kenya) ───────────────────────────────────────────────
-- Listing F01: UGX → KES, MTN MoMo
('c4000000-0000-0000-0000-000000000001',
 '10000000-0000-0000-0000-000000000003', 'UG',
 'UGX', 'KES', 800000, NULL,
 'Mobile money (MTN MoMo), Kampala', FALSE,
 NOW() - INTERVAL '3 hours', 1, 'active',
 NOW() - INTERVAL '3 hours', NOW() + INTERVAL '5 days',
 NOW() - INTERVAL '3 hours'),

-- Listing F02: UGX → KES, in-person Busia border
('c4000000-0000-0000-0000-000000000002',
 '10000000-0000-0000-0000-000000000004', 'UG',
 'UGX', 'KES', 4500000, 0.0289,
 'In-person exchange, Busia border', FALSE,
 NOW() - INTERVAL '8 hours', 2, 'active',
 NOW() - INTERVAL '8 hours', NOW() + INTERVAL '6 days',
 NOW() - INTERVAL '8 hours'),

-- ── UGX → TZS (Uganda → Tanzania) ────────────────────────────────────────────
-- Listing F03
('c4000000-0000-0000-0000-000000000003',
 '10000000-0000-0000-0000-000000000005', 'UG',
 'UGX', 'TZS', 1000000, NULL,
 'Mobile money (MTN MoMo), Kampala', FALSE,
 NOW() - INTERVAL '6 hours', 0, 'active',
 NOW() - INTERVAL '6 hours', NOW() + INTERVAL '7 days',
 NOW() - INTERVAL '6 hours'),

-- ── UGX → RWF (Uganda → Rwanda) ───────────────────────────────────────────────
-- Listing F04
('c4000000-0000-0000-0000-000000000004',
 '10000000-0000-0000-0000-000000000006', 'UG',
 'UGX', 'RWF', 2000000, NULL,
 'Mobile money (Airtel Money), Kampala', TRUE,
 NOW() - INTERVAL '2 hours', 1, 'active',
 NOW() - INTERVAL '2 hours', NOW() + INTERVAL '4 days',
 NOW() - INTERVAL '2 hours'),

-- ── KES → UGX (Kenya → Uganda) ────────────────────────────────────────────────
-- Listing F05
('c4000000-0000-0000-0000-000000000005',
 '10000000-0000-0000-0000-000000000018', 'KE',
 'KES', 'UGX', 25000, NULL,
 'M-Pesa transfer, Nairobi', FALSE,
 NOW() - INTERVAL '4 hours', 1, 'active',
 NOW() - INTERVAL '4 hours', NOW() + INTERVAL '6 days',
 NOW() - INTERVAL '4 hours'),

-- ── KES → TZS (Kenya → Tanzania) ─────────────────────────────────────────────
-- Listing F06
('c4000000-0000-0000-0000-000000000006',
 '10000000-0000-0000-0000-000000000019', 'KE',
 'KES', 'TZS', 30000, NULL,
 'M-Pesa transfer, Mombasa', FALSE,
 NOW() - INTERVAL '10 hours', 2, 'active',
 NOW() - INTERVAL '10 hours', NOW() + INTERVAL '5 days',
 NOW() - INTERVAL '10 hours'),

-- ── KES → NGN (Kenya → Nigeria) ──────────────────────────────────────────────
-- Listing F07
('c4000000-0000-0000-0000-000000000007',
 '10000000-0000-0000-0000-000000000020', 'KE',
 'KES', 'NGN', 50000, NULL,
 'Bank transfer (Equity Bank Kenya)', FALSE,
 NOW() - INTERVAL '14 hours', 0, 'active',
 NOW() - INTERVAL '14 hours', NOW() + INTERVAL '7 days',
 NOW() - INTERVAL '14 hours'),

-- ── KES → USD (Kenya → USD, remittance) ──────────────────────────────────────
-- Listing F08: urgent
('c4000000-0000-0000-0000-000000000008',
 '10000000-0000-0000-0000-000000000021', 'KE',
 'KES', 'USD', 40000, 0.0077,
 'Bank transfer (KCB), Nairobi', TRUE,
 NOW() - INTERVAL '30 minutes', 1, 'active',
 NOW() - INTERVAL '30 minutes', NOW() + INTERVAL '3 days',
 NOW() - INTERVAL '30 minutes'),

-- ── KES → ZAR (Kenya → South Africa) ─────────────────────────────────────────
-- Listing F09
('c4000000-0000-0000-0000-000000000009',
 '10000000-0000-0000-0000-000000000022', 'KE',
 'KES', 'ZAR', 60000, NULL,
 'Bank transfer (Equity Bank), Nairobi', FALSE,
 NOW() - INTERVAL '20 hours', 1, 'active',
 NOW() - INTERVAL '20 hours', NOW() + INTERVAL '6 days',
 NOW() - INTERVAL '20 hours'),

-- ── TZS → KES (Tanzania → Kenya) ─────────────────────────────────────────────
-- Listing F10
('c4000000-0000-0000-0000-000000000010',
 '10000000-0000-0000-0000-000000000035', 'TZ',
 'TZS', 'KES', 600000, NULL,
 'Mobile money (M-Pesa TZ), Dar es Salaam', FALSE,
 NOW() - INTERVAL '7 hours', 0, 'active',
 NOW() - INTERVAL '7 hours', NOW() + INTERVAL '7 days',
 NOW() - INTERVAL '7 hours'),

-- ── TZS → USD (Tanzania → USD) ───────────────────────────────────────────────
-- Listing F11
('c4000000-0000-0000-0000-000000000011',
 '10000000-0000-0000-0000-000000000036', 'TZ',
 'TZS', 'USD', 2500000, NULL,
 'Bank transfer (CRDB Bank), Dar es Salaam', FALSE,
 NOW() - INTERVAL '22 hours', 1, 'active',
 NOW() - INTERVAL '22 hours', NOW() + INTERVAL '5 days',
 NOW() - INTERVAL '22 hours'),

-- ── RWF → USD (Rwanda → USD) ─────────────────────────────────────────────────
-- Listing F12
('c4000000-0000-0000-0000-000000000012',
 '10000000-0000-0000-0000-000000000052', 'RW',
 'RWF', 'USD', 1200000, NULL,
 'Bank transfer (Bank of Kigali)', FALSE,
 NOW() - INTERVAL '16 hours', 2, 'active',
 NOW() - INTERVAL '16 hours', NOW() + INTERVAL '6 days',
 NOW() - INTERVAL '16 hours'),

-- ── NGN → USD (Nigeria → USD — very high volume) ─────────────────────────────
-- Listing F13: urgent, large
('c4000000-0000-0000-0000-000000000013',
 '10000000-0000-0000-0000-000000000012', 'UG',
 'NGN', 'USD', 500000, NULL,
 'Bank transfer (GTBank)', TRUE,
 NOW() - INTERVAL '45 minutes', 3, 'active',
 NOW() - INTERVAL '45 minutes', NOW() + INTERVAL '3 days',
 NOW() - INTERVAL '45 minutes'),

-- ── ZAR → USD (South Africa → USD) ──────────────────────────────────────────
-- Listing F14
('c4000000-0000-0000-0000-000000000014',
 '10000000-0000-0000-0000-000000000013', 'UG',
 'ZAR', 'USD', 8000, 0.054,
 'Bank transfer (FNB South Africa)', FALSE,
 NOW() - INTERVAL '12 hours', 1, 'active',
 NOW() - INTERVAL '12 hours', NOW() + INTERVAL '7 days',
 NOW() - INTERVAL '12 hours'),

-- ── UGX → USD (Uganda → USD, remittance) ─────────────────────────────────────
-- Listing F15
('c4000000-0000-0000-0000-000000000015',
 '10000000-0000-0000-0000-000000000007', 'UG',
 'UGX', 'USD', 5000000, NULL,
 'Bank transfer (Centenary Bank), Kampala', FALSE,
 NOW() - INTERVAL '9 hours', 1, 'active',
 NOW() - INTERVAL '9 hours', NOW() + INTERVAL '6 days',
 NOW() - INTERVAL '9 hours'),

-- ── EGP → USD (Egypt → USD) ──────────────────────────────────────────────────
-- Listing F16
('c4000000-0000-0000-0000-000000000016',
 '10000000-0000-0000-0000-000000000014', 'UG',
 'EGP', 'USD', 30000, NULL,
 'Bank transfer (CIB Egypt)', FALSE,
 NOW() - INTERVAL '18 hours', 0, 'active',
 NOW() - INTERVAL '18 hours', NOW() + INTERVAL '7 days',
 NOW() - INTERVAL '18 hours')

ON CONFLICT (id) DO NOTHING;


-- ── forex_offers ─────────────────────────────────────────────────────────────

INSERT INTO forex_offers (
    id, request_id, offer_maker_id, rate_offered, amount_available, terms,
    terms_locked_at, status, offered_at, created_at
) VALUES

-- Offer on F01 (UGX→KES)
('d4000000-0000-0000-0000-000000000001',
 'c4000000-0000-0000-0000-000000000001',
 '10000000-0000-0000-0000-000000000026',
 0.0287, 800000, 'Can settle via M-Pesa same day.',
 NOW() - INTERVAL '2 hours', 'pending',
 NOW() - INTERVAL '2 hours', NOW() - INTERVAL '2 hours'),

-- Offer 1 on F02 (UGX→KES, Busia)
('d4000000-0000-0000-0000-000000000002',
 'c4000000-0000-0000-0000-000000000002',
 '10000000-0000-0000-0000-000000000026',
 0.0288, 4500000, 'In-person Busia border, flexible timing.',
 NOW() - INTERVAL '6 hours', 'pending',
 NOW() - INTERVAL '6 hours', NOW() - INTERVAL '6 hours'),

-- Offer 2 on F02 (UGX→KES, Busia)
('d4000000-0000-0000-0000-000000000003',
 'c4000000-0000-0000-0000-000000000002',
 '10000000-0000-0000-0000-000000000027',
 0.0291, 3000000, 'Bank transfer Equity Kenya, within 24h.',
 NOW() - INTERVAL '4 hours', 'pending',
 NOW() - INTERVAL '4 hours', NOW() - INTERVAL '4 hours'),

-- Offer on F04 (UGX→RWF)
('d4000000-0000-0000-0000-000000000004',
 'c4000000-0000-0000-0000-000000000004',
 '10000000-0000-0000-0000-000000000060',
 3.82, 2000000, 'Airtel Money Rwanda, same-day settlement.',
 NOW() - INTERVAL '1 hour', 'pending',
 NOW() - INTERVAL '1 hour', NOW() - INTERVAL '1 hour'),

-- Offer on F05 (KES→UGX)
('d4000000-0000-0000-0000-000000000005',
 'c4000000-0000-0000-0000-000000000005',
 '10000000-0000-0000-0000-000000000008',
 34.5, 25000, 'MTN MoMo, Kampala. Can settle within 2 hours.',
 NOW() - INTERVAL '3 hours', 'pending',
 NOW() - INTERVAL '3 hours', NOW() - INTERVAL '3 hours'),

-- Offer 1 on F06 (KES→TZS)
('d4000000-0000-0000-0000-000000000006',
 'c4000000-0000-0000-0000-000000000006',
 '10000000-0000-0000-0000-000000000043',
 22.8, 30000, 'M-Pesa Tanzania, same-day.',
 NOW() - INTERVAL '8 hours', 'pending',
 NOW() - INTERVAL '8 hours', NOW() - INTERVAL '8 hours'),

-- Offer 2 on F06 (KES→TZS)
('d4000000-0000-0000-0000-000000000007',
 'c4000000-0000-0000-0000-000000000006',
 '10000000-0000-0000-0000-000000000044',
 23.1, 25000, 'Bank transfer CRDB Tanzania, 24h.',
 NOW() - INTERVAL '5 hours', 'pending',
 NOW() - INTERVAL '5 hours', NOW() - INTERVAL '5 hours'),

-- Offer on F08 (KES→USD, urgent)
('d4000000-0000-0000-0000-000000000008',
 'c4000000-0000-0000-0000-000000000008',
 '10000000-0000-0000-0000-000000000028',
 0.0076, 40000, 'Bank transfer KCB Kenya, within 4 hours.',
 NOW() - INTERVAL '20 minutes', 'pending',
 NOW() - INTERVAL '20 minutes', NOW() - INTERVAL '20 minutes'),

-- Offer on F09 (KES→ZAR)
('d4000000-0000-0000-0000-000000000009',
 'c4000000-0000-0000-0000-000000000009',
 '10000000-0000-0000-0000-000000000029',
 0.138, 60000, 'Bank transfer FNB South Africa, 2 business days.',
 NOW() - INTERVAL '14 hours', 'pending',
 NOW() - INTERVAL '14 hours', NOW() - INTERVAL '14 hours'),

-- Offer on F11 (TZS→USD)
('d4000000-0000-0000-0000-000000000010',
 'c4000000-0000-0000-0000-000000000011',
 '10000000-0000-0000-0000-000000000045',
 0.00038, 2500000, 'CRDB Bank transfer, 24-48h.',
 NOW() - INTERVAL '18 hours', 'pending',
 NOW() - INTERVAL '18 hours', NOW() - INTERVAL '18 hours'),

-- Offer 1 on F12 (RWF→USD)
('d4000000-0000-0000-0000-000000000011',
 'c4000000-0000-0000-0000-000000000012',
 '10000000-0000-0000-0000-000000000061',
 0.00072, 1200000, 'Bank of Kigali transfer, 24h.',
 NOW() - INTERVAL '12 hours', 'pending',
 NOW() - INTERVAL '12 hours', NOW() - INTERVAL '12 hours'),

-- Offer 2 on F12 (RWF→USD)
('d4000000-0000-0000-0000-000000000012',
 'c4000000-0000-0000-0000-000000000012',
 '10000000-0000-0000-0000-000000000062',
 0.00073, 1000000, 'I&M Bank Rwanda, same-day for amounts under 500k.',
 NOW() - INTERVAL '8 hours', 'pending',
 NOW() - INTERVAL '8 hours', NOW() - INTERVAL '8 hours'),

-- Offer on F13 (NGN→USD, urgent, 3 offers)
('d4000000-0000-0000-0000-000000000013',
 'c4000000-0000-0000-0000-000000000013',
 '10000000-0000-0000-0000-000000000009',
 0.00062, 500000, 'GTBank Nigeria → USD wire, same day.',
 NOW() - INTERVAL '40 minutes', 'pending',
 NOW() - INTERVAL '40 minutes', NOW() - INTERVAL '40 minutes'),
('d4000000-0000-0000-0000-000000000014',
 'c4000000-0000-0000-0000-000000000013',
 '10000000-0000-0000-0000-000000000010',
 0.00063, 400000, 'Zenith Bank transfer, within 3 hours.',
 NOW() - INTERVAL '30 minutes', 'pending',
 NOW() - INTERVAL '30 minutes', NOW() - INTERVAL '30 minutes'),
('d4000000-0000-0000-0000-000000000015',
 'c4000000-0000-0000-0000-000000000013',
 '10000000-0000-0000-0000-000000000011',
 0.00061, 500000, 'Access Bank transfer, competitive rate.',
 NOW() - INTERVAL '15 minutes', 'pending',
 NOW() - INTERVAL '15 minutes', NOW() - INTERVAL '15 minutes'),

-- Offer on F14 (ZAR→USD)
('d4000000-0000-0000-0000-000000000016',
 'c4000000-0000-0000-0000-000000000014',
 '10000000-0000-0000-0000-000000000015',
 0.053, 8000, 'FNB South Africa wire transfer, 1-2 days.',
 NOW() - INTERVAL '10 hours', 'pending',
 NOW() - INTERVAL '10 hours', NOW() - INTERVAL '10 hours'),

-- Offer on F15 (UGX→USD)
('d4000000-0000-0000-0000-000000000017',
 'c4000000-0000-0000-0000-000000000015',
 '10000000-0000-0000-0000-000000000016',
 0.000269, 5000000, 'Centenary Bank transfer, 24h.',
 NOW() - INTERVAL '7 hours', 'pending',
 NOW() - INTERVAL '7 hours', NOW() - INTERVAL '7 hours')

ON CONFLICT (id) DO NOTHING;

SET session_replication_role = 'origin';


-- ============================================
-- VERIFICATION
-- ============================================

SELECT '✅ Forex seed v6.4 — multi-currency pairs enabled across EA + Africa' AS status;

SELECT code, forex_enabled FROM countries
WHERE code IN ('UG','KE','TZ','RW','BI','SS','CD','SO','NG','ZA','EG')
ORDER BY code;

SELECT code, forex_trading_enabled FROM currencies ORDER BY code;

SELECT currency_held || ' → ' || currency_needed AS pair,
       COUNT(*) AS listings,
       SUM(number_of_offers) AS total_offers
FROM v_forex_listings
GROUP BY currency_held, currency_needed
ORDER BY listings DESC, pair;

-- ============================================================
-- END MERGED SECTION: patch_seed_forex3.sql
-- ============================================================


-- ============================================================
-- BEGIN MERGED SECTION: patch_subscription_pricing.sql
-- ============================================================

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

-- ============================================================
-- END MERGED SECTION: patch_subscription_pricing.sql
-- ============================================================


-- ============================================================
-- BEGIN MERGED SECTION: patch_market_baseline_rates.sql
-- ============================================================

-- Patch: Admin-controlled market baseline rates for interest and late payment
-- Uses system_settings with country overrides and a global default.

INSERT INTO system_settings (
  setting_key,
  country,
  setting_value,
  setting_type,
  category,
  description,
  is_public
) VALUES
  ('market_interest_rate_baseline_pct', NULL, '10.0', 'number', 'marketplace', 'Global default market interest rate baseline percentage controlled by admin.', TRUE),
  ('market_late_payment_rate_baseline_pct', NULL, '5.0', 'number', 'marketplace', 'Global default market late payment rate baseline percentage controlled by admin.', TRUE)
ON CONFLICT (setting_key, COALESCE(country, '__global__')) DO UPDATE
SET
  setting_value = EXCLUDED.setting_value,
  setting_type = EXCLUDED.setting_type,
  category = EXCLUDED.category,
  description = EXCLUDED.description,
  is_public = EXCLUDED.is_public,
  updated_at = CURRENT_TIMESTAMP;

INSERT INTO system_settings (
  setting_key,
  country,
  setting_value,
  setting_type,
  category,
  description,
  is_public
) VALUES
  ('market_interest_rate_baseline_pct', 'UG', '10.0', 'number', 'marketplace', 'Uganda market baseline interest rate percentage controlled by admin.', TRUE),
  ('market_late_payment_rate_baseline_pct', 'UG', '5.0', 'number', 'marketplace', 'Uganda market baseline late payment rate percentage controlled by admin.', TRUE),
  ('market_interest_rate_baseline_pct', 'KE', '11.5', 'number', 'marketplace', 'Kenya market baseline interest rate percentage controlled by admin.', TRUE),
  ('market_late_payment_rate_baseline_pct', 'KE', '6.0', 'number', 'marketplace', 'Kenya market baseline late payment rate percentage controlled by admin.', TRUE),
  ('market_interest_rate_baseline_pct', 'TZ', '12.0', 'number', 'marketplace', 'Tanzania market baseline interest rate percentage controlled by admin.', TRUE),
  ('market_late_payment_rate_baseline_pct', 'TZ', '6.5', 'number', 'marketplace', 'Tanzania market baseline late payment rate percentage controlled by admin.', TRUE),
  ('market_interest_rate_baseline_pct', 'RW', '11.0', 'number', 'marketplace', 'Rwanda market baseline interest rate percentage controlled by admin.', TRUE),
  ('market_late_payment_rate_baseline_pct', 'RW', '6.0', 'number', 'marketplace', 'Rwanda market baseline late payment rate percentage controlled by admin.', TRUE),
  ('market_interest_rate_baseline_pct', 'NG', '13.0', 'number', 'marketplace', 'Nigeria market baseline interest rate percentage controlled by admin.', TRUE),
  ('market_late_payment_rate_baseline_pct', 'NG', '7.0', 'number', 'marketplace', 'Nigeria market baseline late payment rate percentage controlled by admin.', TRUE),
  ('market_interest_rate_baseline_pct', 'ZA', '9.5', 'number', 'marketplace', 'South Africa market baseline interest rate percentage controlled by admin.', TRUE),
  ('market_late_payment_rate_baseline_pct', 'ZA', '5.0', 'number', 'marketplace', 'South Africa market baseline late payment rate percentage controlled by admin.', TRUE),
  ('market_interest_rate_baseline_pct', 'EG', '12.5', 'number', 'marketplace', 'Egypt market baseline interest rate percentage controlled by admin.', TRUE),
  ('market_late_payment_rate_baseline_pct', 'EG', '6.5', 'number', 'marketplace', 'Egypt market baseline late payment rate percentage controlled by admin.', TRUE)
ON CONFLICT (setting_key, COALESCE(country, '__global__')) DO UPDATE
SET
  setting_value = EXCLUDED.setting_value,
  updated_at = CURRENT_TIMESTAMP;

-- ============================================================
-- END MERGED SECTION: patch_market_baseline_rates.sql
-- ============================================================


-- ============================================================
-- BEGIN MERGED SECTION: patch_professional_tags.sql
-- ============================================================

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
-- from sql/the Patch v6 Schema section in this file to already exist.
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

-- ============================================================
-- END MERGED SECTION: patch_professional_tags.sql
-- ============================================================


-- ============================================================
-- BEGIN MERGED SECTION: patch_offer_countdown_public_offers.sql
-- ============================================================

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

-- ============================================================
-- END MERGED SECTION: patch_offer_countdown_public_offers.sql
-- ============================================================


-- ============================================================
-- BEGIN MERGED SECTION: patch_collateral_selection.sql
-- ============================================================

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

-- ============================================================
-- END MERGED SECTION: patch_collateral_selection.sql
-- ============================================================


-- ============================================================
-- BEGIN MERGED SECTION: patch_seed_collateral_examples.sql
-- ============================================================

-- Demo collateral data for existing cloud loan requests.
-- Run after the Collateral Selection section in this file.
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

-- ============================================================
-- END MERGED SECTION: patch_seed_collateral_examples.sql
-- ============================================================


-- ============================================================
-- BEGIN MERGED SECTION: patch_loan_listing_detail_view.sql
-- ============================================================

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

-- ============================================================
-- END MERGED SECTION: patch_loan_listing_detail_view.sql
-- ============================================================


-- ============================================================
-- BEGIN MERGED SECTION: patch_kyc_storage.sql
-- ============================================================

-- Patch: Enable storage bucket and RLS policies for KYC verification documents
-- Paste and run this script in your Supabase SQL Editor.

-- 1. Create the verification-documents storage bucket
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'verification-documents',
  'verification-documents',
  TRUE,
  10485760, -- 10MB limit
  ARRAY['image/jpeg', 'image/png', 'image/webp', 'application/pdf']
)
ON CONFLICT (id) DO UPDATE SET
  public = EXCLUDED.public,
  allowed_mime_types = EXCLUDED.allowed_mime_types;

-- 2. Drop existing policies if any
DROP POLICY IF EXISTS "Users can upload their own KYC documents" ON storage.objects;
DROP POLICY IF EXISTS "Users can update their own KYC documents" ON storage.objects;
DROP POLICY IF EXISTS "Users can view their own KYC documents" ON storage.objects;
DROP POLICY IF EXISTS "Public read for verification documents" ON storage.objects;

-- 3. Storage RLS policies
CREATE POLICY "Users can upload their own KYC documents"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (bucket_id = 'verification-documents');

CREATE POLICY "Users can update their own KYC documents"
ON storage.objects FOR UPDATE
TO authenticated
USING (bucket_id = 'verification-documents');

CREATE POLICY "Users can view their own KYC documents"
ON storage.objects FOR SELECT
TO authenticated
USING (bucket_id = 'verification-documents');

CREATE POLICY "Public read for verification documents"
ON storage.objects FOR SELECT
TO public
USING (bucket_id = 'verification-documents');

-- ============================================================
-- END MERGED SECTION: patch_kyc_storage.sql
-- ============================================================


-- ============================================================
-- BEGIN MERGED SECTION: patch_reboot_expired_loan_requests.sql
-- ============================================================

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

-- ============================================================
-- END MERGED SECTION: patch_reboot_expired_loan_requests.sql
-- ============================================================


-- ============================================================
-- BEGIN MERGED SECTION: patch_plan_active_request_limits.sql
-- ============================================================

-- Plan-based active loan request limits.
-- Policy:
--   Free   = 2 active loan requests
--   Lender = 5 active loan requests
--   Pro    = 15 active loan requests
--
-- Only status = 'active' counts. Contracted, expired, and cancelled requests
-- free up capacity automatically.

INSERT INTO system_settings (
  setting_key,
  country,
  setting_value,
  setting_type,
  category,
  description,
  is_public
)
VALUES
  ('max_active_requests_free', NULL, '2', 'number', 'limits', 'Maximum active loan requests for Free subscribers', TRUE),
  ('max_active_requests_lender', NULL, '5', 'number', 'limits', 'Maximum active loan requests for Lender subscribers', TRUE),
  ('max_active_requests_pro', NULL, '15', 'number', 'limits', 'Maximum active loan requests for Pro subscribers', TRUE)
ON CONFLICT (setting_key, COALESCE(country, '__global__')) DO UPDATE
SET setting_value = EXCLUDED.setting_value,
    setting_type = EXCLUDED.setting_type,
    category = EXCLUDED.category,
    description = EXCLUDED.description,
    is_public = EXCLUDED.is_public,
    updated_at = NOW();

UPDATE system_settings
SET setting_value = '2',
    description = 'Legacy fallback maximum active loan requests per borrower',
    updated_at = NOW()
WHERE setting_key = 'max_concurrent_requests'
  AND country IS NULL;

CREATE OR REPLACE FUNCTION trg_fn_max_concurrent_requests()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
DECLARE
    v_active_count INT;
    v_max          INT;
    v_plan         subscription_plan_enum;
BEGIN
    SELECT COALESCE(s.plan, 'free'::subscription_plan_enum) INTO v_plan
    FROM profiles p
    LEFT JOIN subscriptions s
      ON s.user_id = p.id
     AND s.status = 'active'
     AND (s.expires_at IS NULL OR s.expires_at > NOW())
    WHERE p.id = NEW.borrower_id
    LIMIT 1;

    v_plan := COALESCE(v_plan, 'free'::subscription_plan_enum);

    SELECT setting_value::INT INTO v_max
    FROM system_settings
    WHERE setting_key = ('max_active_requests_' || v_plan::TEXT)
      AND (country = NEW.country OR country IS NULL)
    ORDER BY country NULLS LAST
    LIMIT 1;

    IF v_max IS NULL THEN
        SELECT setting_value::INT INTO v_max
        FROM system_settings
        WHERE setting_key = 'max_concurrent_requests'
          AND (country = NEW.country OR country IS NULL)
        ORDER BY country NULLS LAST
        LIMIT 1;
    END IF;

    v_max := COALESCE(v_max, 2);

    SELECT COUNT(*) INTO v_active_count
    FROM loan_requests
    WHERE borrower_id = NEW.borrower_id
      AND status = 'active';

    IF v_active_count >= v_max THEN
        RAISE EXCEPTION 'NIPANZE_MAX_REQUESTS: You have reached the maximum of % active listings.', v_max
            USING ERRCODE = 'P0002';
    END IF;

    RETURN NEW;
END;
$$;

-- ============================================================
-- END MERGED SECTION: patch_plan_active_request_limits.sql
-- ============================================================
