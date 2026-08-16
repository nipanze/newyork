-- ============================================
-- NIPANZE Database Schema
-- Version: 5.0 (Multi-Country Expansion + Pro Advanced Filters, on top of the
--               v4.1 Unified Marketplace Model — Non-Custodial Matchmaking Marketplace)
-- PostgreSQL 14+ · Flutter + Supabase
--
-- Non-custodial peer-to-peer loan listing marketplace.
-- Uganda-first, architected for the full East African Community (EAC) on one
-- shared schema. Basic borrowing is free. Premium borrowers can suggest terms.
-- Lender bids require a subscription.
-- Platform NEVER holds, tracks, or processes money between borrower and lender.
-- Contact details are revealed only after a locked contract is generated.
--
-- v4.1 change: removed role-based model. There is no stored borrower/lender
-- role. All marketplace capability comes from subscription_plan. The only
-- remaining role concept is is_admin (boolean), which governs platform
-- moderation and is unrelated to marketplace participation.
--
-- v4.1.1 fix: reordered two blocks that referenced objects before they
-- were defined (fixed as ordering bugs found during clean-schema replay):
--   1) CREATE SCHEMA IF NOT EXISTS private; moved to top of file, before
--      any private.* function definition.
--   2) trg_agreements_updated_at trigger moved from right after the
--      agreements table into the TRIGGERS section, after fn_set_updated_at()
--      is defined.
--
-- v4.2 addition: Pro Advanced Marketplace Filters — fn_income_bracket(),
-- v_marketplace_pro_filters view, and get_marketplace_pro_filtered() RPC.
-- Self-gated to callers with an active Pro subscription; returns zero rows
-- (view) or raises (RPC) for anyone else. Never exposes exact monthly
-- income or employer/bank names — only bucketed income and categorical
-- employment type.
--
-- v5.0 addition: Multi-Country Expansion. One shared schema now serves every
-- East African Community member state instead of Uganda only:
--   1) New `countries` reference table — code, name, currency_code,
--      phone_prefix, is_active. Seeded with all 8 EAC states (UG active,
--      the other 7 inactive until each clears its own launch checklist).
--      Created early in this file so `profiles` and `loan_requests` can
--      reference it via FK.
--   2) `profiles.country` — source of truth for a user's market, defaults
--      to 'UG', set from onboarding (phone-prefix suggestion, never
--      enforced) via handle_new_auth_user().
--   3) `loan_requests.country` — copied from the borrower's profile at
--      insert time by trg_fn_set_request_country(), then immutable
--      (same "locked after publish" pattern as suggested terms).
--   4) `loan_offers` gets NO country column — an offer's country is always
--      read through `request_id -> loan_requests.country`, so there is
--      exactly one source of truth, never two that can drift apart.
--   5) `system_settings.country` — nullable; NULL rows are global defaults,
--      non-null rows are per-market overrides. Composite unique constraint
--      on (setting_key, country).
--   6) `subscriptions.amount_ugx` renamed to `amount_minor_units` — the
--      currency is implied by the subscriber's `profiles.country`, not
--      hardcoded to UGX.
--   7) `v_loan_listings` and `v_lender_offers` now expose `country` and
--      `currency_code` (joined from `countries`) alongside every amount.
--      `v_marketplace_activity` is now groupable by `country`.
--   8) New `transactions` table (Stage 6 — Flutterwave or equivalent).
--      Scoped strictly to Nipanze's own revenue (subscriptions, and the
--      contact-unlock fee if that open decision is ever resolved to "yes").
--      NEVER touches P2P loan funds. Only a verified webhook may write
--      status = 'successful'; the client-side redirect is never trusted.
--   9) Cross-border offers are ALLOWED by default in this schema (no country
--      check in trg_fn_validate_offer) per the BUILD_PLAN.md recommendation.
--      A single clause can be added there later if product direction
--      changes to single-market-only offers.
--  10) Marketplace filtering by country is an APPLICATION-LAYER default
--      (MarketplaceRepository filters `v_loan_listings WHERE country =
--      :userCountry`), not an RLS boundary — "global browse" was the
--      chosen policy over hard per-country RLS isolation, to support
--      diaspora and cross-border lending. See BUILD_PLAN.md for the
--      documented subquery pattern if hard isolation is ever adopted.
-- ============================================


-- ============================================
-- EXTENSIONS
-- ============================================

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";


-- ============================================
-- SCHEMAS
-- private schema created early so any private.* function definition
-- later in this file (e.g. private.accept_offer_internal,
-- private.reveal_contact_internal, private.unlock_contact_internal,
-- private.is_admin) has somewhere to live.
-- ============================================

CREATE SCHEMA IF NOT EXISTS private;


-- ============================================
-- ENUMS
-- ============================================

CREATE TYPE account_status_enum AS ENUM (
    'active', 'suspended', 'pending_verification', 'deactivated'
);

CREATE TYPE kyc_status_enum AS ENUM (
    'not_submitted', 'pending', 'approved', 'rejected', 'expired'
);

CREATE TYPE employment_type_enum AS ENUM (
    'employed', 'government_employee', 'self_employed', 'small_business_owner', 'business_owner', 'student', 'other'
);

CREATE TYPE subscription_plan_enum AS ENUM (
    'free', 'lender', 'pro'
);

CREATE TYPE subscription_status_enum AS ENUM (
    'active', 'expired', 'cancelled', 'grace_period'
);

CREATE TYPE loan_status_enum AS ENUM (
    'active', 'contracted', 'expired', 'cancelled'
);

CREATE TYPE offer_status_enum AS ENUM (
    'pending', 'accepted', 'rejected', 'withdrawn', 'expired'
);

CREATE TYPE reveal_status_enum AS ENUM (
    'pending', 'revealed'
);

CREATE TYPE repayment_frequency_enum AS ENUM (
    'weekly', 'monthly', 'one_time'
);

CREATE TYPE agreement_status_enum AS ENUM (
    'pending', 'borrower_agreed', 'lender_agreed', 'locked'
);

CREATE TYPE notification_type_enum AS ENUM (
    'offer_received',
    'offer_accepted',
    'offer_rejected',
    'offer_withdrawn',
    'contact_revealed',
    'agreement_locked',
    'kyc_approved',
    'kyc_rejected',
    'closing_soon_24h',
    'closing_soon_6h',
    'watchlist_new_offer',
    'system'
);

CREATE TYPE audit_event_type_enum AS ENUM (
    'login', 'logout', 'register', 'password_reset',
    'token_refresh', 'token_reuse_detected',
    'login_failed', 'account_locked',
    'kyc_submitted', 'kyc_approved', 'kyc_rejected',
    'listing_created', 'listing_cancelled',
    'offer_placed', 'offer_withdrawn', 'offer_accepted',
    'agreement_locked',
    'contact_revealed', 'review_submitted',
    'subscription_changed',
    'transaction_completed',
    'admin_action'
);

CREATE TYPE setting_type_enum AS ENUM (
    'string', 'number', 'boolean', 'json'
);


-- ============================================
-- TABLE: countries  (v5.0 — new reference table)
-- One row per East African Community member state. Seeded with all 8 up
-- front; launching a market is `UPDATE countries SET is_active = TRUE`,
-- never a schema migration. profiles and loan_requests both FK to this
-- table, so it must exist before either is created.
-- ============================================

CREATE TABLE countries (
    code           TEXT PRIMARY KEY,          -- ISO 3166-1 alpha-2
    name           TEXT NOT NULL,
    currency_code  TEXT NOT NULL,              -- ISO 4217
    phone_prefix   TEXT NOT NULL,              -- onboarding-time default suggestion only, never enforced
    is_active      BOOLEAN NOT NULL DEFAULT FALSE,
    created_at     TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE  countries IS
'Reference table for every EAC market Nipanze can operate in. is_active gates whether new
 listings/subscriptions can be created in that market; existing data and history are untouched
 when a market is paused. Adding a market is a data change, never a schema migration.';
COMMENT ON COLUMN countries.phone_prefix IS
'Onboarding-time default suggestion only (like GPS/IP). Never trusted as the enforced value —
 profiles.country, once set, is the source of truth.';

INSERT INTO countries (code, name, currency_code, phone_prefix, is_active) VALUES
    ('UG', 'Uganda',       'UGX', '+256', TRUE),
    ('KE', 'Kenya',        'KES', '+254', FALSE),
    ('TZ', 'Tanzania',     'TZS', '+255', FALSE),
    ('RW', 'Rwanda',       'RWF', '+250', FALSE),
    ('BI', 'Burundi',      'BIF', '+257', FALSE),
    ('SS', 'South Sudan',  'SSP', '+211', FALSE),
    ('CD', 'DR Congo',     'CDF', '+243', FALSE),
    ('SO', 'Somalia',      'SOS', '+252', FALSE);

CREATE INDEX idx_countries_is_active ON countries (is_active) WHERE is_active = TRUE;


-- ============================================
-- AUTH BRIDGE
-- Syncs auth.users → public.profiles on registration.
-- Also creates a free subscription automatically.
-- v5.0: also resolves the new user's country from onboarding metadata
-- (phone-prefix guess or explicit selection), falling back to 'UG' if
-- missing or not a known country code — never trusts an unvalidated value.
-- ============================================

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

CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW
    EXECUTE FUNCTION public.handle_new_auth_user();

COMMENT ON FUNCTION public.handle_new_auth_user IS
'Syncs auth.users → public.profiles on every registration, resolves the new profile''s country
 (defaulting to UG if the onboarding suggestion is missing or unrecognized), and provisions a
 free subscription. Free plan allows marketplace browsing and posting loan requests at no cost.';


-- ============================================
-- TABLE: profiles  (extends auth.users 1-to-1)
-- v4.1: no stored borrower/lender role. is_admin is the only role concept,
-- and it governs platform moderation only — never marketplace capability.
-- v5.0: carries `country`, the source of truth for which EAC market this
-- account belongs to. Required, defaults to 'UG', editable by the user.
-- ============================================

CREATE TABLE profiles (
    id               UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,

    full_name        TEXT,
    phone            TEXT UNIQUE,
    -- Public badge only; the phone number itself remains private until reveal.
    phone_verified_at TIMESTAMP,
    country          TEXT NOT NULL DEFAULT 'UG' REFERENCES countries(code),
    district         TEXT,
    street_address   TEXT,
    employment_type  employment_type_enum,
    employer_name    TEXT,
    monthly_income     BIGINT,
    income_currency    VARCHAR(3) NOT NULL DEFAULT 'UGX',  -- ISO 4217; derived from profiles.country
    preferred_bank      TEXT,
    institution_type    TEXT CHECK (
        institution_type IS NULL OR
        institution_type IN ('bank', 'forex_exchange', 'sacco', 'company')
    ),
    is_bank_agent       BOOLEAN NOT NULL DEFAULT FALSE,
    show_professional_tag BOOLEAN NOT NULL DEFAULT TRUE,

    -- Marketplace filter preferences (v4.5) — mirrors Advanced Filters defaults
    preferred_employment_types  TEXT[],
    preferred_income_bracket    TEXT,
    prefers_suggested_terms     BOOLEAN NOT NULL DEFAULT FALSE,
    prefers_verified_only       BOOLEAN NOT NULL DEFAULT FALSE,

    -- Free contact-unlock credits (welcome gift for free-plan users)
    free_unlocks_remaining      INT NOT NULL DEFAULT 1,

    account_status   account_status_enum NOT NULL DEFAULT 'pending_verification',
    is_admin         BOOLEAN NOT NULL DEFAULT FALSE,

    created_at       TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at       TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE  profiles IS 'Core user profile. Extends auth.users 1-to-1. One account supports both borrower and lender activity, in whichever EAC country the account belongs to.';
COMMENT ON COLUMN profiles.phone IS 'Masked until contact reveal is triggered post-offer-acceptance.';
COMMENT ON COLUMN profiles.phone_verified_at IS
'Timestamp of OTP verification. Only the verified status is exposed as a trust signal.';
COMMENT ON COLUMN profiles.country IS
'Source of truth for the account''s market. Editable by the user; loan_requests.country is
 copied from this value at post time and then frozen, so a later correction here never
 silently moves an already-published listing into a different market''s feed.';
COMMENT ON COLUMN profiles.monthly_income IS
'Free-text numeric income figure used only for fn_income_bracket() bucketing in Pro Advanced
 Filters — never exposed as an exact figure to any other user, regardless of plan or country.';
COMMENT ON COLUMN profiles.is_admin IS
'The only role in the system. Governs platform moderation access, unrelated to marketplace
 capability, which comes entirely from subscription_plan on the subscriptions table.';

CREATE INDEX idx_profiles_country ON profiles (country);


-- ============================================
-- TABLE: system_settings  (key-value, admin-managed)
-- v5.0: gains a nullable `country` column. NULL rows are global defaults;
-- non-null rows override a specific market. Composite-unique on
-- (setting_key, country) via a normalized expression index below, since a
-- plain UNIQUE on setting_key alone no longer holds once overrides exist.
-- ============================================

CREATE TABLE system_settings (
    setting_id    UUID         PRIMARY KEY DEFAULT uuid_generate_v4(),
    setting_key   VARCHAR(100) NOT NULL,
    country       TEXT         REFERENCES countries(code),   -- NULL = global default
    setting_value TEXT,
    setting_type  setting_type_enum NOT NULL DEFAULT 'string',
    category      VARCHAR(50),
    description   TEXT,
    is_public     BOOLEAN NOT NULL DEFAULT FALSE,
    created_at    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE  system_settings IS
'Platform configuration. All business limits read from here at runtime. A row with
 country IS NULL is the global default; a row with country set overrides that key for
 that market only. Resolve with: COALESCE(country-specific row, global row).';

-- Composite-unique on (setting_key, country), treating NULL country as a single
-- normalized value so at most one global-default row can exist per key.
CREATE UNIQUE INDEX uidx_system_settings_key_country
    ON system_settings (setting_key, COALESCE(country, '__global__'));


-- ============================================
-- DEFAULT SYSTEM SETTINGS
-- Global defaults (country IS NULL). Per-country overrides are inserted
-- later, per market, as each one is prepared for launch — see BUILD_PLAN.md
-- Stage 4.5/6.
-- ============================================

INSERT INTO system_settings (setting_key, setting_value, setting_type, category, description, is_public) VALUES
    ('min_loan_amount',         '100000',   'number',  'limits',      'Minimum loan request amount, in the request''s own currency (global default)', TRUE),
    ('max_loan_amount',         '50000000', 'number',  'limits',      'Maximum loan request amount, in the request''s own currency (global default)', TRUE),
    ('min_offer_amount',        '100000',   'number',  'limits',      'Minimum offer amount per lender, in the listing''s own currency (global default)', TRUE),
    ('max_concurrent_requests', '2',        'number',  'limits',      'Legacy fallback maximum active loan requests per borrower', TRUE),
    ('max_active_requests_free',   '2',     'number',  'limits',      'Maximum active loan requests for Free subscribers',      TRUE),
    ('max_active_requests_lender', '5',     'number',  'limits',      'Maximum active loan requests for Lender subscribers',    TRUE),
    ('max_active_requests_pro',    '15',    'number',  'limits',      'Maximum active loan requests for Pro subscribers',       TRUE),
    ('listing_duration_days',   '7',        'number',  'marketplace', 'Days a loan request stays listed before expiry',       TRUE),
    ('kyc_validity_months',     '12',       'number',  'compliance',  'Months until KYC expires and re-verification required', TRUE),
    ('platform_currency',       'UGX',      'string',  'general',     'Fallback/global-default operating currency (each market''s actual currency comes from countries.currency_code)', TRUE),
    ('market_interest_rate_baseline_pct', '10.0', 'number', 'marketplace', 'Global default market baseline interest rate percentage, controlled by admin.', TRUE),
    ('market_late_payment_rate_baseline_pct', '5.0', 'number', 'marketplace', 'Global default market baseline late-payment rate percentage, controlled by admin.', TRUE),
    ('auto_logout_minutes',     '30',       'number',  'security',    'Idle session timeout in minutes',                      FALSE),
    ('access_token_minutes',    '15',       'number',  'security',    'Access JWT TTL in minutes',                            FALSE),
    ('refresh_token_days',      '7',        'number',  'security',    'Refresh token TTL in days',                            FALSE);


-- ============================================
-- TABLE: subscriptions
-- Free plan → browse + post requests (no cost).
-- Lender plan → make offers (paid subscription required).
-- v5.0: amount_ugx renamed to amount_minor_units — currency is implied by
-- the subscriber's profiles.country, not hardcoded to UGX. Same plan tiers
-- and capabilities in every market; only the price differs.
-- ============================================

CREATE TABLE subscriptions (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id     UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,

    plan        subscription_plan_enum   NOT NULL DEFAULT 'free',
    status      subscription_status_enum NOT NULL DEFAULT 'active',

    started_at  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    expires_at  TIMESTAMP,
    amount_minor_units BIGINT NOT NULL DEFAULT 0,
    auto_renew  BOOLEAN NOT NULL DEFAULT TRUE,

    created_at  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE  subscriptions IS
'One active subscription per user. free = no cost, browse and post requests.
 lender or pro plan required to make offers. amount_minor_units is only meaningful
 alongside the subscriber''s profiles.country -> countries.currency_code; the plan
 tiers themselves are identical across every market, only the price is localized.';

-- Only one active subscription per user at a time
CREATE UNIQUE INDEX uidx_sub_active_user ON subscriptions (user_id) WHERE status = 'active';


-- ============================================
-- TABLE: kyc_verifications  (optional — admin-reviewed)
-- ============================================

CREATE TABLE kyc_verifications (
    id                    UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id               UUID UNIQUE NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,

    status                kyc_status_enum NOT NULL DEFAULT 'not_submitted',

    national_id_type      VARCHAR(50),
    national_id_number    VARCHAR(100),
    national_id_front_url VARCHAR(500),
    national_id_back_url  VARCHAR(500),
    selfie_url            VARCHAR(500),

    id_verified           BOOLEAN NOT NULL DEFAULT FALSE,
    selfie_verified       BOOLEAN NOT NULL DEFAULT FALSE,

    verified_by           UUID REFERENCES profiles(id) ON DELETE SET NULL,
    rejection_reason      TEXT,
    verification_notes    TEXT,

    submitted_at          TIMESTAMP,
    reviewed_at           TIMESTAMP,
    expires_at            TIMESTAMP,   -- set to submitted_at + kyc_validity_months on approval

    created_at            TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at            TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE kyc_verifications IS
'Optional KYC. Verification badge shown on borrower profile when approved.
 Not required to post a loan request — borrowing is free and open.
 national_id_type is free text specifically so it can absorb country-specific document
 types (e.g. Kenyan ID vs Ugandan national ID formats) without a schema change.';


-- ============================================
-- TABLE: loan_requests  (borrower listings)
-- Borrowers post structured funding requests for free.
-- Contact details are never exposed until an offer is accepted.
-- v5.0: carries `country`, copied from the borrower's profile at insert
-- time by trg_fn_set_request_country() and then frozen — the listing's
-- market never silently moves if the borrower's profile country is later
-- corrected.
-- ============================================

CREATE TABLE loan_requests (
    id                          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    borrower_id                 UUID NOT NULL REFERENCES profiles(id) ON DELETE RESTRICT,
    country                     TEXT NOT NULL REFERENCES countries(code),

    title                       TEXT NOT NULL,
    purpose                     TEXT NOT NULL,
    requested_amount            BIGINT NOT NULL CONSTRAINT chk_lr_amount_positive CHECK (requested_amount > 0),
    duration_months             INT NOT NULL
                                    CONSTRAINT chk_lr_duration CHECK (duration_months BETWEEN 1 AND 60),

    -- Borrower's income context. Stored for request review, but not exposed
    -- through the public marketplace listing view.
    income_source               TEXT NOT NULL,          -- e.g. 'Monthly salary from Kampala City Council'
    preferred_repayment_plan    TEXT NOT NULL           -- weekly, monthly, one_time
                                    CONSTRAINT chk_lr_repayment_plan
                                    CHECK (preferred_repayment_plan IN ('weekly', 'monthly', 'one_time')),
    repayment_amount_per_period BIGINT NOT NULL         -- e.g. 200000, in the request's own currency
                                    CONSTRAINT chk_lr_repayment_positive CHECK (repayment_amount_per_period > 0),
    repayment_timeline          TEXT NOT NULL,          -- e.g. '4 months starting March 2026'

    -- Borrower-declared collateral. Details/value/location are public risk
    -- signals only when has_collateral is true; value and location are optional.
    has_collateral              BOOLEAN NOT NULL DEFAULT FALSE,
    collateral_details          TEXT,
    collateral_estimated_value  BIGINT
                                    CONSTRAINT chk_lr_collateral_value_positive
                                    CHECK (collateral_estimated_value IS NULL OR collateral_estimated_value > 0),
    collateral_location         TEXT,

    -- Pro-tier term suggestions. These are optional, public, and
    -- locked by trigger at publish time.
    suggested_interest_rate_pct NUMERIC(5,2)
                                    CONSTRAINT chk_lr_suggested_interest_rate_range
                                    CHECK (suggested_interest_rate_pct IS NULL OR
                                           (suggested_interest_rate_pct >= 0 AND suggested_interest_rate_pct <= 100)),
    suggested_late_fee_pct      NUMERIC(5,2)
                                    CONSTRAINT chk_lr_suggested_late_fee_range
                                    CHECK (suggested_late_fee_pct IS NULL OR
                                           (suggested_late_fee_pct >= 0 AND suggested_late_fee_pct <= 100)),
    suggested_repayment_frequency TEXT
                                    CONSTRAINT chk_lr_suggested_repayment_frequency
                                    CHECK (suggested_repayment_frequency IS NULL OR
                                           suggested_repayment_frequency IN ('weekly', 'monthly', 'one_time')),
    suggested_installment_amount BIGINT
                                    CONSTRAINT chk_lr_suggested_installment_positive
                                    CHECK (suggested_installment_amount IS NULL OR suggested_installment_amount > 0),
    terms_locked_at             TIMESTAMP,

    district                    TEXT NOT NULL,

    -- Offer count only — no monetary aggregates (platform never tracks fund totals)
    number_of_offers            INT NOT NULL DEFAULT 0,

    status                      loan_status_enum NOT NULL DEFAULT 'active',

    listed_at                   TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    expires_at                  TIMESTAMP,              -- set by trigger on insert
    contracted_at               TIMESTAMP,
    cancelled_at                TIMESTAMP,

    views_count                 INT NOT NULL DEFAULT 0,

    created_at                  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE  loan_requests IS
'Borrower funding requests. Free to post. borrower_id masked on all public views.
 Income and repayment fields give lenders enough context to make an informed bid.
 Pro-tier term suggestions are locked on publish. country is copied from the
 borrower''s profile at insert time and frozen thereafter.';
COMMENT ON COLUMN loan_requests.borrower_id IS
'NEVER exposed in v_loan_listings or any marketplace query. Contact revealed only post-acceptance.';
COMMENT ON COLUMN loan_requests.country IS
'Set once by trg_fn_set_request_country() at insert, from the borrower''s profiles.country.
 Immutable thereafter — see trg_fn_lock_request_terms(), which also guards this column.';
COMMENT ON COLUMN loan_requests.number_of_offers IS
'Count of offers only. No monetary totals stored — platform is non-custodial.';

CREATE INDEX idx_lr_country        ON loan_requests (country);
CREATE INDEX idx_lr_country_status ON loan_requests (country, status);


-- ============================================
-- TABLE: loan_offers  (lender offers on a borrower request)
-- Lenders must have an active lender/pro subscription to make offers.
-- Lender identity is hidden from the borrower until the offer is accepted.
-- v5.0: deliberately gets NO country column. An offer's country is always
-- its parent request's country, read through request_id -> loan_requests.
-- Storing it a second time here would create a value that can drift from
-- its source of truth for no benefit. Cross-border offers (a lender in one
-- EAC country bidding on a request in another) are allowed by default —
-- see trg_fn_validate_offer() below, which has no country check.
-- ============================================

CREATE TABLE loan_offers (
    id                   UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    request_id           UUID NOT NULL REFERENCES loan_requests(id) ON DELETE CASCADE,
    lender_id            UUID NOT NULL REFERENCES profiles(id) ON DELETE RESTRICT,

    offer_amount         BIGINT NOT NULL CONSTRAINT chk_lo_amount_positive CHECK (offer_amount > 0),
    interest_rate_pct    NUMERIC(5,2) NOT NULL
                            CONSTRAINT chk_lo_interest_rate_range CHECK (interest_rate_pct >= 0 AND interest_rate_pct <= 100),
    late_fee_pct         NUMERIC(5,2) NOT NULL
                            CONSTRAINT chk_lo_late_fee_range CHECK (late_fee_pct >= 0 AND late_fee_pct <= 100),
    repayment_frequency  TEXT NOT NULL
                            CONSTRAINT chk_lo_repayment_frequency CHECK (repayment_frequency IN ('weekly', 'monthly', 'one_time')),
    installment_amount   BIGINT NOT NULL
                            CONSTRAINT chk_lo_installment_positive CHECK (installment_amount > 0),
    proposed_expectations TEXT,   -- optional: lender's additional terms or expectations
    terms_locked_at      TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,

    status               offer_status_enum NOT NULL DEFAULT 'pending',

    offered_at           TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    accepted_at          TIMESTAMP,
    withdrawn_at         TIMESTAMP,
    expires_at           TIMESTAMP,

    created_at           TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at           TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,

    -- a lender can have only one active offer per request
    UNIQUE (request_id, lender_id)
);

COMMENT ON COLUMN loan_offers.lender_id IS
'Internal FK. Lender identity hidden from borrower until the offer is accepted. May belong
 to a profile in a different EAC country than the listing — cross-border offers are allowed.';
COMMENT ON COLUMN loan_offers.offer_amount IS
'Proposed lending amount stated by lender, in the listing''s own currency
 (loan_offers.request_id -> loan_requests.country -> countries.currency_code).
 Platform never holds or moves this money.';
COMMENT ON COLUMN loan_offers.terms_locked_at IS
'Stage 4: lender bid terms are locked when the bid is submitted.';


-- ============================================
-- TABLE: watchlist
-- ============================================

CREATE TABLE watchlist (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id     UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    request_id  UUID NOT NULL REFERENCES loan_requests(id) ON DELETE CASCADE,
    added_at    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,

    UNIQUE (user_id, request_id)
);


-- ============================================
-- TABLE: contact_reveals
-- Post-acceptance contact sharing.
-- Triggered only after a borrower accepts a lender's offer.
-- Reveals legal name, phone, and email of both parties.
-- Logged in audit_logs. Irreversible once triggered.
-- Platform never discloses identity outside this flow, in any market.
-- ============================================

CREATE TABLE contact_reveals (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    offer_id    UUID NOT NULL REFERENCES loan_offers(id) ON DELETE CASCADE,
    request_id  UUID NOT NULL REFERENCES loan_requests(id) ON DELETE CASCADE,

    -- Which party triggered the reveal (must be the borrower who accepted)
    revealed_by UUID NOT NULL REFERENCES profiles(id) ON DELETE RESTRICT,

    status      reveal_status_enum NOT NULL DEFAULT 'pending',
    revealed_at TIMESTAMP,

    created_at  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,

    -- only one reveal record per accepted offer
    UNIQUE (offer_id)
);

COMMENT ON TABLE contact_reveals IS
'Opt-in identity disclosure triggered when a borrower accepts an offer.
 Reveals legal name, phone, and email of both parties.
 Irreversible once revealed. Enforced at the API layer, not just the UI.
 Platform never discloses identity outside this flow. No fee charged today — non-custodial.
 A flat, disclosed contact-unlock fee is a proposed, not-yet-committed change — see
 the transactions table and BUILD_PLAN.md.';


-- ============================================
-- TABLE: agreements
-- Structured locked loan agreement.
-- Auto-generated and locked after bid acceptance.
-- Contact reveal is available only after the contract is locked.
-- ============================================

CREATE TABLE agreements (
    id                          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    offer_id                    UUID NOT NULL UNIQUE REFERENCES loan_offers(id) ON DELETE CASCADE,
    request_id                  UUID NOT NULL REFERENCES loan_requests(id) ON DELETE CASCADE,

    -- Locked repayment terms copied from the accepted lender bid
    repayment_frequency         repayment_frequency_enum NOT NULL,
    repayment_amount            BIGINT NOT NULL CONSTRAINT chk_agr_repayment_positive CHECK (repayment_amount > 0),
    repayment_period            INT NOT NULL CONSTRAINT chk_agr_period_positive CHECK (repayment_period > 0),
    total_repayment_amount      BIGINT NOT NULL CONSTRAINT chk_agr_total_positive CHECK (total_repayment_amount > 0),
    late_payment_penalty_pct    NUMERIC(5,2) NOT NULL DEFAULT 0 CONSTRAINT chk_agr_penalty_range CHECK (late_payment_penalty_pct >= 0 AND late_payment_penalty_pct <= 100),

    -- Agreement text + snapshot (for audit trail)
    agreement_text              TEXT NOT NULL,
    agreement_snapshot          JSONB,  -- Full snapshot at lock time for immutability, includes currency_code

    -- Contract is generated locked by accept_offer.
    status                      agreement_status_enum NOT NULL DEFAULT 'locked',
    borrower_agreed_at          TIMESTAMP,
    lender_agreed_at            TIMESTAMP,
    locked_at                   TIMESTAMP,

    created_at                  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,

    -- only one agreement per accepted offer
    UNIQUE (offer_id)
);

COMMENT ON TABLE agreements IS
'Locked loan agreement. Auto-generated after bid acceptance.
 Late payment penalty applies only to missed installments, not the total loan.
 Agreement is read-only after generation (snapshot captured immediately, including currency_code
 so a generated contract never displays a bare number without its currency).
 All agreement events are logged in audit_logs for traceability.';

-- ============================================
-- TABLES: reviews and trust_aggregates
-- A "completed deal" means a locked agreement whose contact has been revealed.
-- It deliberately does not imply repayment, which happens off-platform.
-- Trust aggregates are GLOBAL per user, not per country — see BUILD_PLAN.md
-- "Multi-Country Expansion Model" for the rationale (reputation doesn't
-- reset at a border).
-- ============================================

CREATE TABLE reviews (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    contract_id UUID NOT NULL REFERENCES agreements(id) ON DELETE CASCADE,
    reviewer_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    reviewee_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    rating      SMALLINT NOT NULL CHECK (rating BETWEEN 1 AND 5),
    comment     TEXT CHECK (comment IS NULL OR char_length(comment) <= 500),
    created_at  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (contract_id, reviewer_id),
    CHECK (reviewer_id <> reviewee_id)
);

CREATE TABLE trust_aggregates (
    user_id                    UUID PRIMARY KEY REFERENCES profiles(id) ON DELETE CASCADE,
    rating_avg                 NUMERIC(3,2),
    review_count               INT NOT NULL DEFAULT 0,
    completed_deals_count      INT NOT NULL DEFAULT 0,
    is_repeat_participant      BOOLEAN NOT NULL DEFAULT FALSE,
    response_time_bucket       TEXT,
    success_rate               NUMERIC(5,2),
    reliability_score          INT,
    updated_at                 TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CHECK (response_time_bucket IN ('responds_quickly', 'responds_within_a_day', 'responds_slowly') OR response_time_bucket IS NULL),
    CHECK (reliability_score BETWEEN 0 AND 100 OR reliability_score IS NULL)
);

COMMENT ON TABLE reviews IS
'Immutable, one-per-party review for a completed on-platform deal. It never represents off-platform repayment behaviour.';
COMMENT ON TABLE trust_aggregates IS
'Cached, platform-scoped reputation aggregates. One row per user, GLOBAL across every EAC
 market they have participated in — never one row per user per country. Public fields and
 Pro-only analytical fields are exposed through separate views.';

-- Indexes
CREATE INDEX idx_agr_offer_id    ON agreements (offer_id);
CREATE INDEX idx_agr_request_id  ON agreements (request_id);
CREATE INDEX idx_agr_status      ON agreements (status);
CREATE INDEX idx_reviews_reviewee ON reviews (reviewee_id, created_at DESC);
CREATE INDEX idx_reviews_contract ON reviews (contract_id);

-- NOTE: trg_agreements_updated_at trigger moved to the TRIGGERS section
-- below (after fn_set_updated_at() is defined) — see "-- agreements" there.


-- ============================================
-- TABLE: notifications
-- ============================================

CREATE TABLE notifications (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id     UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,

    type        notification_type_enum NOT NULL,
    title       TEXT NOT NULL,
    body        TEXT NOT NULL,
    data        JSONB,

    is_read     BOOLEAN NOT NULL DEFAULT FALSE,
    read_at     TIMESTAMP,

    -- optional deep-link references
    request_id  UUID REFERENCES loan_requests(id)  ON DELETE SET NULL,
    offer_id    UUID REFERENCES loan_offers(id)     ON DELETE SET NULL,

    created_at  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);


-- ============================================
-- TABLE: audit_logs  (append-only; UPDATE/DELETE blocked by RLS)
-- ============================================

CREATE TABLE audit_logs (
    id           UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id      UUID REFERENCES profiles(id) ON DELETE SET NULL,

    event_type   audit_event_type_enum NOT NULL,
    entity_type  VARCHAR(50),
    entity_id    UUID,
    action       VARCHAR(100),
    description  TEXT,

    ip_address   INET,
    user_agent   TEXT,

    old_values   JSONB,
    new_values   JSONB,
    metadata     JSONB,

    created_at   TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE audit_logs IS 'Immutable audit trail. NEVER update or delete rows. Enforced by RLS.';


-- ============================================
-- TABLE: refresh_tokens  (manual rotation audit chain)
-- ============================================

CREATE TABLE refresh_tokens (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id     UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,

    token_hash  TEXT NOT NULL UNIQUE,   -- bcrypt hash of the actual token
    replaced_by UUID REFERENCES refresh_tokens(id) ON DELETE SET NULL,
    revoked     BOOLEAN NOT NULL DEFAULT FALSE,
    revoked_at  TIMESTAMP,

    issued_at   TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    expires_at  TIMESTAMP NOT NULL,

    ip_address  INET,
    user_agent  TEXT
);

COMMENT ON TABLE refresh_tokens IS
'Rotation chain: when a token is used, replaced_by is set to the new token id.
 If a revoked token is presented again, token_reuse_detected is logged to audit_logs.';


-- ============================================
-- TABLE: referrals
-- ============================================

CREATE TABLE referrals (
    id               UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    referrer_id      UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    referred_email   TEXT NOT NULL,
    referred_user_id UUID REFERENCES profiles(id) ON DELETE SET NULL,

    code             TEXT NOT NULL UNIQUE,
    is_activated     BOOLEAN NOT NULL DEFAULT FALSE,
    activated_at     TIMESTAMP,
    reward_applied   BOOLEAN NOT NULL DEFAULT FALSE,

    created_at       TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);


-- ============================================
-- TABLE: transactions  (Stage 6 — Flutterwave or equivalent aggregator)
-- Scoped STRICTLY to Nipanze's own revenue: subscription charges, and the
-- contact-unlock fee IF that open decision is ever resolved to "yes".
-- NEVER touches money between a borrower and a lender — that stays
-- entirely off-platform per Architecture Constraint #1. Only a verified
-- webhook may set status = 'successful'; the client-side redirect after
-- payment is never trusted to grant access on its own.
-- ============================================

CREATE TABLE transactions (
    id                       UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id                  UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,

    type                     TEXT NOT NULL CONSTRAINT chk_tx_type CHECK (type IN ('subscription', 'contact_unlock')),
    amount                   BIGINT NOT NULL CONSTRAINT chk_tx_amount_positive CHECK (amount > 0),
    currency_code            TEXT NOT NULL,
    country                  TEXT NOT NULL REFERENCES countries(code),   -- payer's country at time of charge

    provider                 TEXT NOT NULL DEFAULT 'flutterwave',        -- plain text, not enum, so a second processor can be added later
    provider_tx_ref          TEXT NOT NULL UNIQUE,                        -- idempotency key Nipanze generates, sent to the provider
    provider_tx_id           TEXT,                                        -- provider's own reference, populated on webhook confirm

    status                   TEXT NOT NULL DEFAULT 'pending'
                                CONSTRAINT chk_tx_status CHECK (status IN ('pending', 'successful', 'failed', 'reversed')),

    related_subscription_id  UUID REFERENCES subscriptions(id),
    related_reveal_id        UUID REFERENCES contact_reveals(id),

    webhook_verified_at      TIMESTAMP,   -- set only after the provider's webhook signature check passes

    created_at               TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at               TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE transactions IS
'Payment records for Nipanze''s own revenue only (subscriptions, and the contact-unlock fee
 if ever adopted) — never P2P loan funds. provider_tx_ref is generated by Nipanze before the
 charge is initiated so retries and webhook replays are idempotent. status only ever reaches
 ''successful'' via the signature-verified webhook handler (a service-role Edge Function),
 never via the client-side post-payment redirect. A user''s subscriptions.plan upgrades only
 after a linked transaction reaches ''successful'' — never optimistically.';
COMMENT ON COLUMN transactions.provider IS
'Plain text, not an enum, specifically so a second processor can be added later (e.g. a
 card-only fallback, or a different aggregator for a market Flutterwave covers thinly) without
 a schema migration.';

CREATE INDEX idx_tx_user_id  ON transactions (user_id);
CREATE INDEX idx_tx_status   ON transactions (status);
CREATE INDEX idx_tx_country  ON transactions (country);


-- ============================================
-- INDEXES
-- ============================================

-- profiles
CREATE INDEX idx_profiles_is_admin       ON profiles (is_admin) WHERE is_admin = TRUE;
CREATE INDEX idx_profiles_account_status ON profiles (account_status);

-- subscriptions
CREATE INDEX idx_sub_user_id  ON subscriptions (user_id);
CREATE INDEX idx_sub_plan     ON subscriptions (plan);
CREATE INDEX idx_sub_status   ON subscriptions (status);

-- kyc_verifications
CREATE INDEX idx_kyc_user_id ON kyc_verifications (user_id);
CREATE INDEX idx_kyc_status  ON kyc_verifications (status);

-- loan_requests
CREATE INDEX idx_lr_borrower_id   ON loan_requests (borrower_id);
CREATE INDEX idx_lr_status        ON loan_requests (status);
CREATE INDEX idx_lr_expires_at    ON loan_requests (expires_at);
CREATE INDEX idx_lr_district      ON loan_requests (district);
CREATE INDEX idx_lr_status_exp    ON loan_requests (status, expires_at);
CREATE INDEX idx_lr_active        ON loan_requests (status) WHERE status = 'active';

-- loan_offers
CREATE INDEX idx_lo_request_id    ON loan_offers (request_id);
CREATE INDEX idx_lo_lender_id     ON loan_offers (lender_id);
CREATE INDEX idx_lo_status        ON loan_offers (status);
CREATE INDEX idx_lo_req_status    ON loan_offers (request_id, status);
CREATE INDEX idx_lo_lender_status ON loan_offers (lender_id, status, offered_at DESC);

-- watchlist
CREATE INDEX idx_wl_user_id    ON watchlist (user_id);
CREATE INDEX idx_wl_request_id ON watchlist (request_id);

-- contact_reveals
CREATE INDEX idx_cr_offer_id   ON contact_reveals (offer_id);
CREATE INDEX idx_cr_request_id ON contact_reveals (request_id);

-- notifications
CREATE INDEX idx_notif_user_id   ON notifications (user_id);
CREATE INDEX idx_notif_user_read ON notifications (user_id, is_read);
CREATE INDEX idx_notif_created   ON notifications (created_at DESC);

-- audit_logs
CREATE INDEX idx_al_user_id    ON audit_logs (user_id);
CREATE INDEX idx_al_event_type ON audit_logs (event_type);
CREATE INDEX idx_al_entity     ON audit_logs (entity_type, entity_id);
CREATE INDEX idx_al_created    ON audit_logs (created_at DESC);

-- refresh_tokens
CREATE INDEX idx_rt_user_id ON refresh_tokens (user_id);
CREATE INDEX idx_rt_hash    ON refresh_tokens (token_hash);
CREATE INDEX idx_rt_expires ON refresh_tokens (expires_at);
CREATE INDEX idx_rt_active  ON refresh_tokens (user_id, expires_at) WHERE revoked = FALSE;


-- ============================================
-- FUNCTIONS: Pro Advanced Marketplace Filters (v4.2)
-- fn_income_bracket() buckets exact income into a coarse category so it can
-- be filtered on without ever exposing the exact monthly income figure.
-- ============================================

CREATE OR REPLACE FUNCTION fn_income_bracket(p_income BIGINT)
RETURNS TEXT
LANGUAGE sql IMMUTABLE
AS $$
    SELECT CASE
        WHEN p_income IS NULL THEN NULL
        WHEN p_income < 2000000  THEN 'under_2m'
        WHEN p_income < 5000000  THEN '2m_5m'
        WHEN p_income < 10000000 THEN '5m_10m'
        ELSE 'over_10m'
    END;
$$;

COMMENT ON FUNCTION fn_income_bracket(BIGINT) IS
'Buckets an exact monthly income figure into a coarse category (under_2m / 2m_5m / 5m_10m /
 over_10m) for Pro Advanced Filters. Never exposes the exact figure.';


-- ============================================
-- VIEWS
-- ============================================

-- --------------------------------------------
-- v_loan_listings
-- Anonymised public marketplace feed.
-- borrower_id, phone, email, full_name, and national ID are intentionally excluded.
-- Exposes enough structured context for lenders to make informed offers.
-- v5.0: now includes country and currency_code (joined from countries) so
-- every amount is shown alongside the currency it's denominated in.
-- --------------------------------------------
CREATE VIEW v_loan_listings AS
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
    -- KYC badge (status only — no personal verification documents)
    k.status                                                                  AS kyc_status,
    -- Public, privacy-safe trust signals for the request owner. GLOBAL across
    -- every EAC country the owner has participated in, not just this listing's market.
    ta.rating_avg                                                             AS trust_rating_avg,
    COALESCE(ta.review_count, 0)                                              AS trust_review_count,
    COALESCE(ta.completed_deals_count, 0)                                     AS trust_completed_deals_count,
    COALESCE(ta.is_repeat_participant, FALSE)                                AS trust_is_repeat_participant,
    (p.phone_verified_at IS NOT NULL)                                        AS trust_phone_verified,
    ta.response_time_bucket                                                   AS trust_response_time_bucket,
    (k.status = 'approved')                                                   AS trust_is_verified,
    -- time-remaining helpers
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
FROM  loan_requests   lr
JOIN  profiles p ON p.id = lr.borrower_id
JOIN  countries c ON c.code = lr.country
LEFT  JOIN kyc_verifications k ON k.user_id = lr.borrower_id
LEFT  JOIN trust_aggregates ta ON ta.user_id = lr.borrower_id
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

COMMENT ON VIEW v_loan_listings IS
'Anonymised marketplace feed across every EAC market. borrower_id, contact details, and
 private documents are never present. Repayment fields and Pro-tier suggestions help lenders
 make an informed bid without exposing income source. country/currency_code are always
 returned together with every amount. The Flutter client filters this feed to the user''s
 own country by default (MarketplaceRepository), with an explicit toggle to browse others —
 this view itself does not restrict by country, matching the "global browse" policy in
 BUILD_PLAN.md.';

-- Detail view for a single active loan listing.
-- Mirrors v_loan_listings but does not hide rows where the caller has already
-- made an offer; the marketplace feed still uses v_loan_listings.
CREATE VIEW v_loan_listing_details AS
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
FROM  loan_requests lr
JOIN  profiles p ON p.id = lr.borrower_id
JOIN  countries c ON c.code = lr.country
LEFT  JOIN kyc_verifications k ON k.user_id = lr.borrower_id
LEFT  JOIN trust_aggregates ta ON ta.user_id = lr.borrower_id
WHERE lr.status = 'active';

COMMENT ON VIEW v_loan_listing_details IS
'Single-listing detail view for active loan requests. Unlike v_loan_listings, it remains
 visible to users who already placed an offer, so the detail page can load after offer
 submission. Collateral and professional tags remain Pro-masked.';


-- --------------------------------------------
-- v_user_marketplace_activity
-- Dashboard view — one query covers both borrower requests and lender offers.
-- Used in the Positions / My Requests / My Offers screens.
-- --------------------------------------------
CREATE VIEW v_user_marketplace_activity WITH (security_invoker = true) AS
SELECT
    p.id                                                                      AS user_id,
    p.full_name,
    p.country,
    p.account_status,
    -- borrower side
    COUNT(DISTINCT lr.id) FILTER (
        WHERE lr.borrower_id = p.id AND lr.status = 'active'
    )                                                                         AS active_requests,
    COUNT(DISTINCT lr.id) FILTER (
        WHERE lr.borrower_id = p.id AND lr.status = 'contracted'
    )                                                                         AS contracted_as_borrower,
    COUNT(DISTINCT lr.id) FILTER (
        WHERE lr.borrower_id = p.id AND lr.status = 'expired'
    )                                                                         AS expired_requests,
    -- lender side
    COUNT(DISTINCT lo.id) FILTER (
        WHERE lo.lender_id = p.id AND lo.status = 'pending'
    )                                                                         AS pending_offers,
    COUNT(DISTINCT lo.id) FILTER (
        WHERE lo.lender_id = p.id AND lo.status = 'accepted'
    )                                                                         AS accepted_offers,
    -- subscription
    s.plan                                                                    AS subscription_plan,
    s.status                                                                  AS subscription_status,
    s.expires_at                                                              AS subscription_expires_at,
    -- kyc
    k.status                                                                  AS kyc_status
FROM  profiles          p
LEFT  JOIN subscriptions      s  ON s.user_id     = p.id AND s.status = 'active'
LEFT  JOIN kyc_verifications  k  ON k.user_id     = p.id
LEFT  JOIN loan_requests      lr ON lr.borrower_id = p.id
LEFT  JOIN loan_offers        lo ON lo.lender_id   = p.id
GROUP BY p.id, s.plan, s.status, s.expires_at, k.status;

COMMENT ON VIEW v_user_marketplace_activity IS
'Dashboard summary covering both borrower requests and lender offers for a single user account.';

-- --------------------------------------------
-- Trust profile views
-- These contain no contact details. The public view is intentionally readable
-- without marketplace participation; the Pro view adds only derived insights.
-- Both are GLOBAL — not scoped or filtered by country in any way.
-- --------------------------------------------
CREATE VIEW v_trust_profile_public AS
SELECT
    p.id AS user_id,
    ta.rating_avg,
    COALESCE(ta.review_count, 0) AS review_count,
    COALESCE(ta.completed_deals_count, 0) AS completed_deals_count,
    COALESCE(ta.is_repeat_participant, FALSE) AS is_repeat_participant,
    (p.phone_verified_at IS NOT NULL) AS phone_verified,
    ta.response_time_bucket,
    (k.status = 'approved') AS is_verified
FROM profiles p
LEFT JOIN trust_aggregates ta ON ta.user_id = p.id
LEFT JOIN kyc_verifications k ON k.user_id = p.id;

CREATE VIEW v_trust_profile_pro AS
SELECT
    tp.*,
    ta.success_rate,
    ta.reliability_score
FROM v_trust_profile_public tp
JOIN trust_aggregates ta ON ta.user_id = tp.user_id
WHERE EXISTS (
    SELECT 1 FROM subscriptions s
    WHERE s.user_id = auth.uid() AND s.status = 'active' AND s.plan = 'pro'
);


-- --------------------------------------------
-- v_lender_offers
-- Lender offer activity — for My Offers screen.
-- Does NOT expose borrower contact details.
-- v5.0: now includes country and currency_code, joined through the parent
-- listing (loan_offers has no country column of its own).
-- --------------------------------------------
CREATE VIEW v_lender_offers WITH (security_invoker = true) AS
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
    -- contact reveal status (only populated after acceptance)
    cr.status                                                                 AS reveal_status,
    cr.revealed_at
FROM  loan_offers     lo
JOIN  loan_requests   lr ON lr.id      = lo.request_id
JOIN  countries       c  ON c.code     = lr.country
JOIN  profiles        p  ON p.id       = lo.lender_id
LEFT  JOIN kyc_verifications k ON k.user_id = lo.lender_id
LEFT  JOIN trust_aggregates ta ON ta.user_id = lo.lender_id
LEFT  JOIN contact_reveals cr ON cr.offer_id = lo.id;

COMMENT ON VIEW v_lender_offers IS
'Lender offer history with reveal status. Borrower contact details not exposed until
 reveal_status = revealed. country/currency_code are read through the parent listing
 (loan_requests), never stored on loan_offers itself.';


-- --------------------------------------------
-- v_marketplace_activity
-- Marketplace-wide KPIs for admin dashboard.
-- v5.0: now includes country, so admin can filter or group KPIs per market
-- instead of only seeing a single blended global figure.
-- --------------------------------------------
CREATE VIEW v_marketplace_activity WITH (security_invoker = true) AS
SELECT
    DATE_TRUNC('month', lr.listed_at)                                        AS month,
    lr.country,
    COUNT(lr.id)                                                              AS total_listings,
    COUNT(lr.id) FILTER (WHERE lr.status = 'active')                        AS active_listings,
    COUNT(lr.id) FILTER (WHERE lr.status = 'contracted')                    AS contracted_listings,
    COUNT(lr.id) FILTER (WHERE lr.status = 'expired')                       AS expired_listings,
    COUNT(DISTINCT lo.id) FILTER (WHERE lo.status = 'pending')              AS pending_offers,
    COUNT(DISTINCT lo.id) FILTER (WHERE lo.status = 'accepted')             AS accepted_offers,
    ROUND(
        COUNT(DISTINCT lo.request_id) * 100.0 / NULLIF(COUNT(lr.id), 0), 1
    )                                                                         AS match_rate_pct,
    (SELECT COUNT(*) FROM subscriptions
     WHERE status = 'active' AND plan != 'free')                             AS active_paid_subscribers
FROM  loan_requests lr
LEFT  JOIN loan_offers lo ON lo.request_id = lr.id
GROUP BY DATE_TRUNC('month', lr.listed_at), lr.country
ORDER BY month DESC, lr.country;

COMMENT ON VIEW v_marketplace_activity IS
'Admin KPIs, filterable/groupable by country. No monetary aggregates — non-custodial, and
 amounts are never summed across markets with different currencies (see BUILD_PLAN.md).
 Match rate measures how many listings received at least one offer.
 active_paid_subscribers is intentionally global, not per-country, in this base view.';


-- --------------------------------------------
-- v_marketplace_pro_filters  (Pro Advanced Marketplace Filters, v4.2)
-- Self-gating view: returns zero rows for any caller without an active Pro
-- subscription. Never exposes exact monthly income or employer/bank names —
-- only bucketed income and categorical employment type.
-- --------------------------------------------
CREATE VIEW v_marketplace_pro_filters WITH (security_invoker = true) AS
SELECT
    lr.id                                       AS request_id,
    lr.country,
    p.employment_type,
    fn_income_bracket(p.monthly_income)         AS income_bracket,
    (lr.suggested_interest_rate_pct IS NOT NULL) AS has_suggested_terms,
    (k.status = 'approved')                      AS owner_verified
FROM  loan_requests lr
JOIN  profiles p ON p.id = lr.borrower_id
LEFT  JOIN kyc_verifications k ON k.user_id = lr.borrower_id
WHERE lr.status = 'active'
  AND EXISTS (
      SELECT 1 FROM subscriptions s
      WHERE s.user_id = auth.uid() AND s.status = 'active' AND s.plan = 'pro'
  );

COMMENT ON VIEW v_marketplace_pro_filters IS
'Pro-only filter signals (employment type, bucketed income, suggested-terms flag, owner
 verification status) for a listing. Self-gated: returns zero rows for any caller without an
 active Pro subscription, so the DB is the enforcement point, not the Flutter client.';


-- --------------------------------------------
-- get_public_listing_offers
-- Public anonymized order book for active listings.
-- Does not expose real lender_id values.
-- --------------------------------------------
CREATE OR REPLACE FUNCTION get_public_listing_offers(p_request_id UUID)
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
    accepted_at TIMESTAMP
)
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = ''
AS $$
DECLARE
    v_is_owner BOOLEAN := FALSE;
    v_is_offer_maker BOOLEAN := FALSE;
BEGIN
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
            lo.repayment_frequency,
            lo.installment_amount,
            lo.proposed_expectations,
            lo.terms_locked_at,
            lo.status::TEXT,
            lo.offered_at,
            lo.accepted_at
        FROM public.loan_offers lo
        JOIN public.loan_requests lr ON lr.id = lo.request_id
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
        lo.repayment_frequency,
        lo.installment_amount,
        lo.proposed_expectations,
        lo.terms_locked_at,
        lo.status::TEXT,
        lo.offered_at,
        lo.accepted_at
    FROM public.loan_offers lo
    WHERE lo.request_id = p_request_id
      AND lo.lender_id = auth.uid()
      AND lo.status IN ('pending', 'accepted');
END;
$$;

COMMENT ON FUNCTION get_public_listing_offers(UUID) IS
'Participant-scoped bid book. Listing owners and offer-makers receive exact terms; all other viewers receive only v_loan_listings aggregate coverage.';


-- --------------------------------------------
-- check_phone_registered
-- Helper RPC for phone onboarding. Checks if a phone number is registered.
-- Returns the associated user's email if found, otherwise NULL.
-- --------------------------------------------
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

GRANT EXECUTE ON FUNCTION public.check_phone_registered(TEXT) TO authenticated, anon;


-- --------------------------------------------
-- get_marketplace_pro_filtered
-- Applies Pro Advanced Filters on top of v_loan_listings. Raises if the
-- caller does not have an active Pro subscription, rather than silently
-- returning nothing, so client errors are explicit.
-- --------------------------------------------
CREATE OR REPLACE FUNCTION get_marketplace_pro_filtered(
    p_employment_type      employment_type_enum DEFAULT NULL,
    p_income_bracket       TEXT                  DEFAULT NULL,
    p_suggested_terms_only BOOLEAN               DEFAULT FALSE,
    p_verified_only        BOOLEAN               DEFAULT FALSE,
    p_country              TEXT                  DEFAULT NULL
)
RETURNS SETOF v_loan_listings
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM subscriptions
        WHERE user_id = auth.uid() AND status = 'active' AND plan = 'pro'
    ) THEN
        RAISE EXCEPTION 'NIPANZE_PRO_REQUIRED: Advanced marketplace filters require a Pro subscription.'
            USING ERRCODE = 'P0050';
    END IF;

    RETURN QUERY
    SELECT vl.*
    FROM v_loan_listings vl
    JOIN loan_requests lr ON lr.id = vl.request_id
    JOIN profiles p ON p.id = lr.borrower_id
    LEFT JOIN kyc_verifications k ON k.user_id = lr.borrower_id
    WHERE (p_employment_type IS NULL OR p.employment_type = p_employment_type)
      AND (p_income_bracket IS NULL OR fn_income_bracket(p.monthly_income) = p_income_bracket)
      AND (NOT p_suggested_terms_only OR lr.suggested_interest_rate_pct IS NOT NULL)
      AND (NOT p_verified_only OR k.status = 'approved')
      AND (p_country IS NULL OR vl.country = p_country);
END;
$$;

COMMENT ON FUNCTION get_marketplace_pro_filtered IS
'Pro-only marketplace filtering by employment type, bucketed income, suggested-terms
 presence, owner verification, and (optionally) country. Raises NIPANZE_PRO_REQUIRED for any
 caller without an active Pro subscription — the DB is the enforcement point, matching
 v_marketplace_pro_filters above.';


-- Rebuild a user's platform-scoped trust summary. This intentionally counts
-- only agreements that reached contact reveal, never repayment behaviour,
-- and is GLOBAL across every country the user has participated in.
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
    SELECT ROUND(AVG(rating)::NUMERIC, 2), COUNT(*)
      INTO v_rating, v_reviews
      FROM reviews WHERE reviewee_id = p_user_id;

    SELECT COUNT(*) INTO v_deals
    FROM agreements a
    JOIN loan_offers lo ON lo.id = a.offer_id
    JOIN loan_requests lr ON lr.id = a.request_id
    JOIN contact_reveals cr ON cr.offer_id = lo.id AND cr.status = 'revealed'
    WHERE lr.borrower_id = p_user_id OR lo.lender_id = p_user_id;

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
    ) response_times;

    v_bucket := CASE
        WHEN v_response_hours IS NULL THEN NULL
        WHEN v_response_hours <= 24 THEN 'responds_quickly'
        WHEN v_response_hours <= 72 THEN 'responds_within_a_day'
        ELSE 'responds_slowly'
    END;

    SELECT ROUND(
        100.0 * COUNT(*) FILTER (WHERE completed) / NULLIF(COUNT(*), 0), 2
    ) INTO v_success_rate
    FROM (
        SELECT lo.id,
               EXISTS (SELECT 1 FROM agreements a WHERE a.offer_id = lo.id) AS completed
        FROM loan_offers lo WHERE lo.lender_id = p_user_id
        UNION ALL
        SELECT lr.id,
               EXISTS (SELECT 1 FROM agreements a WHERE a.request_id = lr.id)
        FROM loan_requests lr WHERE lr.borrower_id = p_user_id
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

CREATE OR REPLACE FUNCTION public.submit_review(
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

    SELECT CASE WHEN lr.borrower_id = v_reviewer THEN lo.lender_id ELSE lr.borrower_id END
      INTO v_reviewee
    FROM agreements a
    JOIN loan_offers lo ON lo.id = a.offer_id
    JOIN loan_requests lr ON lr.id = a.request_id
    JOIN contact_reveals cr ON cr.offer_id = lo.id AND cr.status = 'revealed'
    WHERE a.id = p_contract_id
      AND (lr.borrower_id = v_reviewer OR lo.lender_id = v_reviewer);
    IF v_reviewee IS NULL THEN
        RAISE EXCEPTION 'NIPANZE_REVIEW_NOT_ELIGIBLE: Reviews require a completed on-platform deal.';
    END IF;

    INSERT INTO reviews (contract_id, reviewer_id, reviewee_id, rating, comment)
    VALUES (p_contract_id, v_reviewer, v_reviewee, p_rating, NULLIF(BTRIM(p_comment), ''))
    RETURNING id INTO v_review_id;
    PERFORM recompute_trust_aggregates(v_reviewee);
    INSERT INTO audit_logs (user_id, event_type, entity_type, entity_id, action)
    VALUES (v_reviewer, 'review_submitted', 'reviews', v_review_id, 'submit_review');
    RETURN v_review_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.trg_refresh_trust_from_reveal()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_borrower UUID; v_lender UUID;
BEGIN
    IF NEW.status = 'revealed' AND (TG_OP = 'INSERT' OR OLD.status IS DISTINCT FROM 'revealed') THEN
        SELECT lr.borrower_id, lo.lender_id INTO v_borrower, v_lender
        FROM loan_offers lo JOIN loan_requests lr ON lr.id = lo.request_id WHERE lo.id = NEW.offer_id;
        PERFORM recompute_trust_aggregates(v_borrower);
        PERFORM recompute_trust_aggregates(v_lender);
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_refresh_trust_on_reveal
AFTER INSERT OR UPDATE OF status ON contact_reveals
FOR EACH ROW EXECUTE FUNCTION trg_refresh_trust_from_reveal();


-- ============================================
-- FUNCTIONS (shared utilities)
-- ============================================

CREATE OR REPLACE FUNCTION fn_set_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql
SET search_path = public AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$;

-- Generate locked contract text from accepted bid terms.
-- v5.0: accepts a currency code so the contract text never displays a bare
-- number without stating what currency it's denominated in.
CREATE OR REPLACE FUNCTION fn_generate_locked_contract_text(
    p_borrower_name TEXT,
    p_lender_name TEXT,
    p_loan_amount BIGINT,
    p_interest_rate_pct NUMERIC,
    p_total_repayment BIGINT,
    p_repayment_frequency TEXT,
    p_installment_amount BIGINT,
    p_duration_months INT,
    p_late_fee_pct NUMERIC,
    p_currency_code TEXT DEFAULT 'UGX'
)
RETURNS TEXT LANGUAGE plpgsql STABLE AS $$
BEGIN
    RETURN FORMAT(
'LOAN AGREEMENT

PARTIES
Borrower: %s
Lender: %s

LOCKED TERMS
Loan amount: %s %s
Interest rate: %s%%
Total repayment amount: %s %s
Repayment schedule: %s
Installment amount: %s %s
Duration: %s months
Start date: %s
End date: %s

LATE PAYMENT RULE
A %s%% penalty applies only to a missed installment amount, not to the total loan balance.

DISCLAIMER
Nipanze provides this agreement for convenience only. The final obligation is solely between borrower and lender. Nipanze does not enforce repayment or hold funds.

Audit timestamp: %s',
        COALESCE(p_borrower_name, 'Borrower'),
        COALESCE(p_lender_name, 'Lender'),
        p_currency_code,
        p_loan_amount,
        p_interest_rate_pct,
        p_currency_code,
        p_total_repayment,
        p_repayment_frequency,
        p_currency_code,
        p_installment_amount,
        p_duration_months,
        CURRENT_DATE,
        CURRENT_DATE + (p_duration_months || ' months')::INTERVAL,
        p_late_fee_pct,
        NOW()
    );
END;
$$;


-- ============================================
-- TRIGGER FUNCTIONS
-- ============================================

-- Set expires_at on loan_request insert using system_settings.
-- Resolves the per-country override if one exists, falling back to the
-- global default (country IS NULL) otherwise.
CREATE OR REPLACE FUNCTION trg_fn_set_listing_expiry()
RETURNS TRIGGER LANGUAGE plpgsql
SET search_path = public AS $$
DECLARE
    v_days INT;
BEGIN
    SELECT setting_value::INT INTO v_days
    FROM system_settings
    WHERE setting_key = 'listing_duration_days'
      AND (country = NEW.country OR country IS NULL)
    ORDER BY country NULLS LAST
    LIMIT 1;

    NEW.expires_at := NOW() + (v_days || ' days')::INTERVAL;
    RETURN NEW;
END;
$$;


-- v5.0: copies country from the borrower's profile onto a new loan_requests
-- row at insert time. Same "locked at post time" pattern as term-locking —
-- once set here, trg_fn_lock_request_terms() below guards it from edits.
CREATE OR REPLACE FUNCTION trg_fn_set_request_country()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
BEGIN
    IF NEW.country IS NULL THEN
        SELECT country INTO NEW.country FROM profiles WHERE id = NEW.borrower_id;
    END IF;
    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION trg_fn_set_request_country IS
'v5.0: sets loan_requests.country from the borrower''s profiles.country at insert time,
 if not already supplied. Frozen thereafter by trg_fn_lock_request_terms().';


-- Block listing if account is not active
CREATE OR REPLACE FUNCTION trg_fn_require_active_account()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM profiles
        WHERE id = NEW.borrower_id AND account_status != 'active'
    ) THEN
        RAISE EXCEPTION 'NIPANZE_ACCOUNT_INACTIVE: Your account must be active to post a listing.'
            USING ERRCODE = 'P0001';
    END IF;
    RETURN NEW;
END;
$$;


-- Enforce plan-specific max concurrent active requests from system_settings.
-- Completed, contracted, expired, or cancelled requests do not count.
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
    WHERE borrower_id = NEW.borrower_id AND status = 'active';

    IF v_active_count >= v_max THEN
        RAISE EXCEPTION 'NIPANZE_MAX_REQUESTS: You have reached the maximum of % active listings.', v_max
            USING ERRCODE = 'P0002';
    END IF;

    RETURN NEW;
END;
$$;


-- Validate optional Pro-tier term suggestions before insert.
CREATE OR REPLACE FUNCTION trg_fn_validate_request_terms()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
DECLARE
    v_plan subscription_plan_enum;
    v_has_suggestions BOOLEAN;
BEGIN
    v_has_suggestions :=
        NEW.suggested_interest_rate_pct IS NOT NULL OR
        NEW.suggested_late_fee_pct IS NOT NULL OR
        NEW.suggested_repayment_frequency IS NOT NULL OR
        NEW.suggested_installment_amount IS NOT NULL;

    IF v_has_suggestions THEN
        SELECT plan INTO v_plan
        FROM subscriptions
        WHERE user_id = NEW.borrower_id AND status = 'active'
        ORDER BY created_at DESC
        LIMIT 1;

        IF v_plan IS DISTINCT FROM 'pro'::subscription_plan_enum THEN
            RAISE EXCEPTION 'NIPANZE_PRO_REQUIRED: A Pro subscription is required to suggest interest, late fee, or repayment terms.'
                USING ERRCODE = 'P0004';
        END IF;
    END IF;

    NEW.terms_locked_at := COALESCE(NEW.terms_locked_at, NOW());
    RETURN NEW;
END;
$$;


-- Lock request term suggestions AND country after publish.
CREATE OR REPLACE FUNCTION trg_fn_lock_request_terms()
RETURNS TRIGGER LANGUAGE plpgsql
SET search_path = public AS $$
BEGIN
    IF OLD.terms_locked_at IS NOT NULL AND (
        OLD.suggested_interest_rate_pct IS DISTINCT FROM NEW.suggested_interest_rate_pct OR
        OLD.suggested_late_fee_pct IS DISTINCT FROM NEW.suggested_late_fee_pct OR
        OLD.suggested_repayment_frequency IS DISTINCT FROM NEW.suggested_repayment_frequency OR
        OLD.suggested_installment_amount IS DISTINCT FROM NEW.suggested_installment_amount
    ) THEN
        RAISE EXCEPTION 'NIPANZE_REQUEST_TERMS_LOCKED: Terms cannot be edited after publish.'
            USING ERRCODE = 'P0005';
    END IF;

    IF OLD.country IS DISTINCT FROM NEW.country THEN
        RAISE EXCEPTION 'NIPANZE_REQUEST_COUNTRY_LOCKED: A listing''s country is frozen at publish time and cannot be changed.'
            USING ERRCODE = 'P0006';
    END IF;

    RETURN NEW;
END;
$$;


-- Validate a lender offer before insert.
-- v5.0: no country check — cross-border offers are ALLOWED by default per
-- BUILD_PLAN.md. To restrict to single-market offers only, add a clause
-- here comparing (SELECT country FROM profiles WHERE id = NEW.lender_id)
-- against v_listing.country.
CREATE OR REPLACE FUNCTION trg_fn_validate_offer()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
DECLARE
    v_listing    loan_requests%ROWTYPE;
    v_min_offer  BIGINT;
    v_plan       subscription_plan_enum;
BEGIN
    -- Check listing exists and is active
    SELECT * INTO v_listing FROM loan_requests WHERE id = NEW.request_id;

    IF v_listing.status != 'active' THEN
        RAISE EXCEPTION 'NIPANZE_LISTING_NOT_ACTIVE: This listing is no longer accepting bids.'
            USING ERRCODE = 'P0010';
    END IF;

    IF v_listing.expires_at < NOW() THEN
        RAISE EXCEPTION 'NIPANZE_LISTING_EXPIRED: This listing has expired.'
            USING ERRCODE = 'P0011';
    END IF;

    -- Cannot offer on your own request
    IF v_listing.borrower_id = NEW.lender_id THEN
        RAISE EXCEPTION 'NIPANZE_SELF_OFFER: You cannot make a bid on your own listing.'
            USING ERRCODE = 'P0012';
    END IF;

    -- Minimum offer amount (global default; per-country override takes precedence if present)
    SELECT setting_value::BIGINT INTO v_min_offer
    FROM system_settings
    WHERE setting_key = 'min_offer_amount'
      AND (country = v_listing.country OR country IS NULL)
    ORDER BY country NULLS LAST
    LIMIT 1;

    IF NEW.offer_amount < v_min_offer THEN
        RAISE EXCEPTION 'NIPANZE_MIN_OFFER: Bid amount must be at least %.', v_min_offer
            USING ERRCODE = 'P0013';
    END IF;

    -- Lender or Pro subscription required to make bids
    SELECT plan INTO v_plan
    FROM subscriptions
    WHERE user_id = NEW.lender_id AND status = 'active';

    IF v_plan NOT IN ('lender', 'pro') THEN
        RAISE EXCEPTION 'NIPANZE_SUBSCRIPTION_REQUIRED: A Lender or Pro subscription is required to make bids.'
            USING ERRCODE = 'P0014';
    END IF;

    IF NEW.interest_rate_pct IS NULL OR NEW.late_fee_pct IS NULL OR
       NEW.repayment_frequency IS NULL OR NEW.installment_amount IS NULL THEN
        RAISE EXCEPTION 'NIPANZE_BID_TERMS_REQUIRED: Interest, late fee, repayment schedule, and installment amount are required.'
            USING ERRCODE = 'P0016';
    END IF;

    NEW.terms_locked_at := COALESCE(NEW.terms_locked_at, NOW());
    RETURN NEW;
END;
$$;


-- Lock an accepted offer from further updates
CREATE OR REPLACE FUNCTION trg_fn_lock_accepted_offer()
RETURNS TRIGGER LANGUAGE plpgsql
SET search_path = public AS $$
BEGIN
    IF OLD.status = 'accepted' THEN
        RAISE EXCEPTION 'NIPANZE_OFFER_LOCKED: An accepted offer cannot be modified.'
            USING ERRCODE = 'P0015';
    END IF;
    RETURN NEW;
END;
$$;


-- Lock bid terms after submit. Status-only updates are still allowed.
CREATE OR REPLACE FUNCTION trg_fn_lock_offer_terms()
RETURNS TRIGGER LANGUAGE plpgsql
SET search_path = public AS $$
BEGIN
    IF OLD.terms_locked_at IS NOT NULL AND (
        OLD.offer_amount IS DISTINCT FROM NEW.offer_amount OR
        OLD.interest_rate_pct IS DISTINCT FROM NEW.interest_rate_pct OR
        OLD.late_fee_pct IS DISTINCT FROM NEW.late_fee_pct OR
        OLD.repayment_frequency IS DISTINCT FROM NEW.repayment_frequency OR
        OLD.installment_amount IS DISTINCT FROM NEW.installment_amount OR
        OLD.proposed_expectations IS DISTINCT FROM NEW.proposed_expectations
    ) THEN
        RAISE EXCEPTION 'NIPANZE_BID_TERMS_LOCKED: Bid terms cannot be edited after submit.'
            USING ERRCODE = 'P0017';
    END IF;
    RETURN NEW;
END;
$$;


-- Auto-expire an offer if expires_at has passed
CREATE OR REPLACE FUNCTION trg_fn_expire_offer()
RETURNS TRIGGER LANGUAGE plpgsql
SET search_path = public AS $$
BEGIN
    IF NEW.expires_at IS NOT NULL AND NEW.expires_at < CURRENT_TIMESTAMP AND NEW.status = 'pending' THEN
        NEW.status := 'expired'::offer_status_enum;
    END IF;
    RETURN NEW;
END;
$$;


-- Sync number_of_offers on loan_requests with pending offers.
CREATE OR REPLACE FUNCTION trg_fn_sync_offer_count()
RETURNS TRIGGER LANGUAGE plpgsql
SET search_path = public AS $$
DECLARE
    v_request_id UUID;
BEGIN
    v_request_id := COALESCE(NEW.request_id, OLD.request_id);

    UPDATE loan_requests lr
       SET number_of_offers = (
           SELECT COUNT(*)::INT
             FROM loan_offers lo
            WHERE lo.request_id = v_request_id
              AND lo.status = 'pending'
       )
     WHERE lr.id = v_request_id;

    RETURN COALESCE(NEW, OLD);
END;
$$;


-- ============================================
-- TRIGGERS
-- ============================================

-- countries
CREATE TRIGGER trg_countries_updated_at_noop
    BEFORE UPDATE ON countries
    FOR EACH ROW WHEN (FALSE)  -- placeholder no-op; countries has no updated_at column by design
    EXECUTE FUNCTION fn_set_updated_at();

-- profiles
CREATE TRIGGER trg_profiles_updated_at
    BEFORE UPDATE ON profiles
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

-- subscriptions
CREATE TRIGGER trg_subscriptions_updated_at
    BEFORE UPDATE ON subscriptions
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

-- kyc_verifications
CREATE TRIGGER trg_kyc_updated_at
    BEFORE UPDATE ON kyc_verifications
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

-- system_settings
CREATE TRIGGER trg_system_settings_updated_at
    BEFORE UPDATE ON system_settings
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

-- loan_requests
CREATE TRIGGER trg_set_request_country
    BEFORE INSERT ON loan_requests
    FOR EACH ROW EXECUTE FUNCTION trg_fn_set_request_country();

CREATE TRIGGER trg_require_active_account
    BEFORE INSERT ON loan_requests
    FOR EACH ROW EXECUTE FUNCTION trg_fn_require_active_account();

CREATE TRIGGER trg_max_concurrent_requests
    BEFORE INSERT ON loan_requests
    FOR EACH ROW EXECUTE FUNCTION trg_fn_max_concurrent_requests();

CREATE TRIGGER trg_set_listing_expiry
    BEFORE INSERT ON loan_requests
    FOR EACH ROW EXECUTE FUNCTION trg_fn_set_listing_expiry();

CREATE TRIGGER trg_validate_request_terms
    BEFORE INSERT ON loan_requests
    FOR EACH ROW EXECUTE FUNCTION trg_fn_validate_request_terms();

CREATE TRIGGER trg_lock_request_terms
    BEFORE UPDATE ON loan_requests
    FOR EACH ROW EXECUTE FUNCTION trg_fn_lock_request_terms();

CREATE TRIGGER trg_loan_requests_updated_at
    BEFORE UPDATE ON loan_requests
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

-- loan_offers
CREATE TRIGGER trg_expire_offer
    BEFORE INSERT OR UPDATE ON loan_offers
    FOR EACH ROW EXECUTE FUNCTION trg_fn_expire_offer();

CREATE TRIGGER trg_validate_offer
    BEFORE INSERT ON loan_offers
    FOR EACH ROW EXECUTE FUNCTION trg_fn_validate_offer();

CREATE TRIGGER trg_lock_accepted_offer
    BEFORE UPDATE ON loan_offers
    FOR EACH ROW
    WHEN (OLD.status = 'accepted')
    EXECUTE FUNCTION trg_fn_lock_accepted_offer();

CREATE TRIGGER trg_lock_offer_terms
    BEFORE UPDATE ON loan_offers
    FOR EACH ROW EXECUTE FUNCTION trg_fn_lock_offer_terms();

CREATE TRIGGER trg_sync_offer_count
    AFTER INSERT OR UPDATE OR DELETE ON loan_offers
    FOR EACH ROW EXECUTE FUNCTION trg_fn_sync_offer_count();

CREATE TRIGGER trg_loan_offers_updated_at
    BEFORE UPDATE ON loan_offers
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

-- agreements (moved here from right after CREATE TABLE agreements —
-- fn_set_updated_at() must exist first)
CREATE TRIGGER trg_agreements_updated_at
    BEFORE UPDATE ON agreements
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

-- transactions
CREATE TRIGGER trg_transactions_updated_at
    BEFORE UPDATE ON transactions
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();


-- ============================================
-- RPC: accept_offer  (Stage 4: Creates locked agreement)
-- Atomic: accepts the chosen bid, rejects competing pending bids,
-- marks listing contracted, creates a locked agreement snapshot,
-- and notifies both parties.
-- Contact details are NOT returned here — unlock_contact is the only
-- API that reveals contact details after the contract is locked.
-- v5.0: the agreement snapshot and contract text now carry currency_code,
-- resolved from the listing's country.
-- ============================================

CREATE OR REPLACE FUNCTION private.accept_offer_internal(
    p_request_id  UUID,
    p_offer_id    UUID,
    p_borrower_id UUID,
    p_caller_id   UUID
)
RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = '' AS $$
DECLARE
    v_listing public.loan_requests%ROWTYPE;
    v_offer public.loan_offers%ROWTYPE;
    v_borrower public.profiles%ROWTYPE;
    v_lender public.profiles%ROWTYPE;
    v_currency_code TEXT;
    v_agreement_id UUID;
    v_total_repayment BIGINT;
    v_agreement_text TEXT;
    v_snapshot JSONB;
BEGIN
    IF p_caller_id IS NULL OR p_caller_id != p_borrower_id THEN
        RAISE EXCEPTION 'NIPANZE_UNAUTHORIZED: Caller is not the borrower.'
            USING ERRCODE = 'P0021';
    END IF;

    SELECT * INTO v_listing FROM public.loan_requests WHERE id = p_request_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'NIPANZE_LISTING_NOT_FOUND' USING ERRCODE = 'P0020';
    END IF;
    IF v_listing.borrower_id != p_borrower_id THEN
        RAISE EXCEPTION 'NIPANZE_UNAUTHORIZED: Only the listing owner can accept a bid.'
            USING ERRCODE = 'P0021';
    END IF;
    IF v_listing.status != 'active' THEN
        RAISE EXCEPTION 'NIPANZE_LISTING_NOT_ACTIVE' USING ERRCODE = 'P0022';
    END IF;

    SELECT * INTO v_offer FROM public.loan_offers
     WHERE id = p_offer_id AND request_id = p_request_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'NIPANZE_OFFER_NOT_FOUND' USING ERRCODE = 'P0023';
    END IF;
    IF v_offer.status != 'pending' THEN
        RAISE EXCEPTION 'NIPANZE_OFFER_NOT_PENDING: This bid is no longer available.'
            USING ERRCODE = 'P0024';
    END IF;

    SELECT * INTO v_borrower FROM public.profiles WHERE id = p_borrower_id;
    SELECT * INTO v_lender FROM public.profiles WHERE id = v_offer.lender_id;
    SELECT currency_code INTO v_currency_code FROM public.countries WHERE code = v_listing.country;

    v_total_repayment := ROUND(v_offer.offer_amount * (1 + (v_offer.interest_rate_pct / 100.0)))::BIGINT;

    v_snapshot := JSONB_BUILD_OBJECT(
        'request_id', p_request_id,
        'offer_id', p_offer_id,
        'borrower_id', p_borrower_id,
        'lender_id', v_offer.lender_id,
        'country', v_listing.country,
        'currency_code', v_currency_code,
        'loan_amount', v_offer.offer_amount,
        'interest_rate_pct', v_offer.interest_rate_pct,
        'total_repayment_amount', v_total_repayment,
        'repayment_frequency', v_offer.repayment_frequency,
        'installment_amount', v_offer.installment_amount,
        'repayment_period', v_listing.duration_months,
        'late_fee_pct', v_offer.late_fee_pct,
        'late_fee_rule', 'Late fee applies only to missed installment amount, not total balance.',
        'start_date', CURRENT_DATE,
        'end_date', CURRENT_DATE + (v_listing.duration_months || ' months')::INTERVAL,
        'duration_months', v_listing.duration_months,
        'legal_disclaimer', 'Nipanze provides this agreement for convenience only. The final obligation is solely between borrower and lender. Nipanze does not enforce repayment or hold funds.',
        'locked_at', NOW()
    );

    v_agreement_text := public.fn_generate_locked_contract_text(
        v_borrower.full_name,
        v_lender.full_name,
        v_offer.offer_amount,
        v_offer.interest_rate_pct,
        v_total_repayment,
        v_offer.repayment_frequency,
        v_offer.installment_amount,
        v_listing.duration_months,
        v_offer.late_fee_pct,
        v_currency_code
    );

    UPDATE public.loan_offers SET status = 'accepted', accepted_at = NOW() WHERE id = p_offer_id;

    UPDATE public.loan_offers
       SET status = 'rejected', updated_at = NOW()
     WHERE request_id = p_request_id AND id != p_offer_id AND status = 'pending';

    UPDATE public.loan_requests
       SET status = 'contracted', contracted_at = NOW() WHERE id = p_request_id;

    INSERT INTO public.agreements (
        offer_id,
        request_id,
        repayment_frequency,
        repayment_amount,
        repayment_period,
        total_repayment_amount,
        late_payment_penalty_pct,
        agreement_text,
        agreement_snapshot,
        status,
        borrower_agreed_at,
        lender_agreed_at,
        locked_at
    )
    VALUES (
        p_offer_id,
        p_request_id,
        v_offer.repayment_frequency::public.repayment_frequency_enum,
        v_offer.installment_amount,
        v_listing.duration_months,
        v_total_repayment,
        v_offer.late_fee_pct,
        v_agreement_text,
        v_snapshot,
        'locked'::public.agreement_status_enum,
        NOW(),
        NOW(),
        NOW()
    )
    ON CONFLICT (offer_id) DO UPDATE
       SET repayment_period = EXCLUDED.repayment_period,
           total_repayment_amount = EXCLUDED.total_repayment_amount,
           agreement_text = EXCLUDED.agreement_text,
           agreement_snapshot = EXCLUDED.agreement_snapshot,
           status = 'locked'::public.agreement_status_enum,
           borrower_agreed_at = COALESCE(public.agreements.borrower_agreed_at, NOW()),
           lender_agreed_at = COALESCE(public.agreements.lender_agreed_at, NOW()),
           locked_at = COALESCE(public.agreements.locked_at, NOW())
    RETURNING id INTO v_agreement_id;

    INSERT INTO public.notifications (user_id, type, title, body, request_id, offer_id)
    VALUES
        (p_borrower_id, 'agreement_locked', 'Contract generated',
         'Your selected bid is locked into a contract. Unlock contact details to connect.',
         p_request_id, p_offer_id),
        (v_offer.lender_id, 'agreement_locked', 'Contract generated',
         'Your bid was accepted and locked into a contract. Contact unlock is now available.',
         p_request_id, p_offer_id);

    INSERT INTO public.audit_logs (user_id, event_type, entity_type, entity_id, action, new_values)
    VALUES
        (p_borrower_id, 'offer_accepted', 'loan_offers', p_offer_id, 'accept_offer', v_snapshot),
        (p_borrower_id, 'agreement_locked', 'agreements', v_agreement_id, 'generate_locked_contract', v_snapshot);

    RETURN v_agreement_id;
END;
$$;

GRANT EXECUTE ON FUNCTION private.accept_offer_internal(uuid, uuid, uuid, uuid) TO authenticated, service_role;

-- Wrapper: SECURITY INVOKER
CREATE OR REPLACE FUNCTION public.accept_offer(
    p_request_id  UUID,
    p_offer_id    UUID,
    p_borrower_id UUID
)
RETURNS UUID
LANGUAGE sql SECURITY INVOKER
SET search_path = public AS $$
    SELECT private.accept_offer_internal(p_request_id, p_offer_id, p_borrower_id, auth.uid());
$$;

REVOKE EXECUTE ON FUNCTION public.accept_offer(uuid, uuid, uuid) FROM public, anon;
GRANT  EXECUTE ON FUNCTION public.accept_offer(uuid, uuid, uuid) TO authenticated, service_role;

COMMENT ON FUNCTION public.accept_offer IS
'Atomically accepts a bid, rejects others, marks listing contracted, and creates a locked agreement.
 Returns agreement_id. Contact details are not exposed until unlock_contact() is called.
 Platform never holds or moves funds. The agreement snapshot and contract text include
 currency_code, resolved from the listing''s country.';


-- ============================================
-- RPC: reveal_contact
-- ============================================

CREATE OR REPLACE FUNCTION private.reveal_contact_internal(
    p_reveal_id   UUID,
    p_borrower_id UUID,
    p_caller_id   UUID
)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = '' AS $$
DECLARE
    v_reveal        public.contact_reveals%ROWTYPE;
    v_offer         public.loan_offers%ROWTYPE;
    v_borrower      public.profiles%ROWTYPE;
    v_lender        public.profiles%ROWTYPE;
    v_borrower_auth RECORD;
    v_lender_auth   RECORD;
    v_result        JSONB;
BEGIN
    -- Caller validation (must be the borrower)
    IF p_caller_id IS NULL OR p_caller_id != p_borrower_id THEN
        RAISE EXCEPTION 'NIPANZE_UNAUTHORIZED: Caller is not the borrower.'
            USING ERRCODE = 'P0031';
    END IF;

    SELECT * INTO v_reveal FROM public.contact_reveals WHERE id = p_reveal_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'NIPANZE_REVEAL_NOT_FOUND' USING ERRCODE = 'P0030';
    END IF;
    IF v_reveal.revealed_by != p_borrower_id THEN
        RAISE EXCEPTION 'NIPANZE_UNAUTHORIZED: Only the borrower who accepted can trigger reveal.'
            USING ERRCODE = 'P0031';
    END IF;
    IF v_reveal.status = 'revealed' THEN
        RAISE EXCEPTION 'NIPANZE_ALREADY_REVEALED: Contact details already revealed.'
            USING ERRCODE = 'P0032';
    END IF;

    SELECT * INTO v_offer    FROM public.loan_offers WHERE id = v_reveal.offer_id;
    SELECT * INTO v_borrower FROM public.profiles    WHERE id = p_borrower_id;
    SELECT * INTO v_lender   FROM public.profiles    WHERE id = v_offer.lender_id;

    -- auth.users requires service-role — SECURITY DEFINER gives this
    SELECT email INTO v_borrower_auth FROM auth.users WHERE id = p_borrower_id;
    SELECT email INTO v_lender_auth   FROM auth.users WHERE id = v_offer.lender_id;

    UPDATE public.contact_reveals SET status = 'revealed', revealed_at = NOW() WHERE id = p_reveal_id;

    v_result := JSONB_BUILD_OBJECT(
        'borrower', JSONB_BUILD_OBJECT(
            'full_name', v_borrower.full_name, 'phone', v_borrower.phone, 'email', v_borrower_auth.email),
        'lender', JSONB_BUILD_OBJECT(
            'full_name', v_lender.full_name, 'phone', v_lender.phone, 'email', v_lender_auth.email)
    );

    INSERT INTO public.notifications (user_id, type, title, body, request_id, offer_id)
    VALUES
        (p_borrower_id, 'contact_revealed', 'Contact details revealed',
         'You can now connect with your lender directly.', v_reveal.request_id, v_reveal.offer_id),
        (v_offer.lender_id, 'contact_revealed', 'Contact details revealed',
         'The borrower accepted your offer. You can now connect directly.', v_reveal.request_id, v_reveal.offer_id);

    INSERT INTO public.audit_logs (user_id, event_type, entity_type, entity_id, action, new_values)
    VALUES (p_borrower_id, 'contact_revealed', 'contact_reveals', p_reveal_id, 'reveal_contact',
        JSONB_BUILD_OBJECT(
            'offer_id',   v_reveal.offer_id,
            'request_id', v_reveal.request_id,
            'lender_id',  v_offer.lender_id,
            'revealed_at', NOW()
        ));

    RETURN v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION private.reveal_contact_internal(uuid, uuid, uuid) TO authenticated, service_role;

-- Wrapper: SECURITY INVOKER
CREATE OR REPLACE FUNCTION public.reveal_contact(
    p_reveal_id   UUID,
    p_borrower_id UUID
)
RETURNS JSONB
LANGUAGE sql SECURITY INVOKER
SET search_path = public AS $$
    SELECT private.reveal_contact_internal(p_reveal_id, p_borrower_id, auth.uid());
$$;

REVOKE EXECUTE ON FUNCTION public.reveal_contact(uuid, uuid) FROM public, anon;
GRANT  EXECUTE ON FUNCTION public.reveal_contact(uuid, uuid) TO authenticated, service_role;

COMMENT ON FUNCTION public.reveal_contact IS
'Reveals legal name, phone, and email of both borrower and lender after an offer is accepted.
 Enforced at API layer. Irreversible. Returns contact JSONB to the calling client.
 Platform never stores or retransmits these details after this point.';


-- ============================================
-- RPC: unlock_contact (Stage 4)
-- After contract generation, borrower unlocks contact details.
-- Creates contact_reveal record (or updates existing one to 'revealed').
-- ============================================

CREATE OR REPLACE FUNCTION private.unlock_contact_internal(
    p_agreement_id UUID,
    p_caller_id    UUID
)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = '' AS $$
DECLARE
    v_agreement  public.agreements%ROWTYPE;
    v_offer      public.loan_offers%ROWTYPE;
    v_reveal     public.contact_reveals%ROWTYPE;
    v_borrower   public.profiles%ROWTYPE;
    v_lender     public.profiles%ROWTYPE;
    v_borrower_auth RECORD;
    v_lender_auth RECORD;
    v_borrower_id UUID;
    v_lender_id UUID;
    v_result JSONB;
BEGIN
    SELECT * INTO v_agreement FROM public.agreements WHERE id = p_agreement_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'NIPANZE_AGREEMENT_NOT_FOUND' USING ERRCODE = 'P0041';
    END IF;

    IF v_agreement.status != 'locked' THEN
        RAISE EXCEPTION 'NIPANZE_AGREEMENT_NOT_LOCKED: Agreement must be locked before unlocking contact.'
            USING ERRCODE = 'P0045';
    END IF;

    SELECT * INTO v_offer FROM public.loan_offers WHERE id = v_agreement.offer_id;
    SELECT borrower_id INTO v_borrower_id FROM public.loan_requests WHERE id = v_agreement.request_id;
    v_lender_id := v_offer.lender_id;

    -- Caller validation (must be the borrower)
    IF p_caller_id != v_borrower_id THEN
        RAISE EXCEPTION 'NIPANZE_UNAUTHORIZED: Only the borrower can unlock contact details.'
            USING ERRCODE = 'P0046';
    END IF;

    -- Get profiles
    SELECT * INTO v_borrower FROM public.profiles WHERE id = v_borrower_id;
    SELECT * INTO v_lender FROM public.profiles WHERE id = v_lender_id;

    -- Get email from auth.users (requires SECURITY DEFINER)
    SELECT email INTO v_borrower_auth FROM auth.users WHERE id = v_borrower_id;
    SELECT email INTO v_lender_auth FROM auth.users WHERE id = v_lender_id;

    -- Get or create contact_reveal
    SELECT * INTO v_reveal FROM public.contact_reveals WHERE offer_id = v_agreement.offer_id;
    IF v_reveal IS NULL THEN
        INSERT INTO public.contact_reveals (offer_id, request_id, revealed_by, status, revealed_at)
        VALUES (v_agreement.offer_id, v_agreement.request_id, v_borrower_id, 'revealed', NOW())
        RETURNING * INTO v_reveal;
    ELSE
        UPDATE public.contact_reveals
           SET status = 'revealed', revealed_at = NOW()
         WHERE id = v_reveal.id;
        v_reveal.status := 'revealed';
        v_reveal.revealed_at := NOW();
    END IF;

    -- Result includes contact details
    v_result := JSONB_BUILD_OBJECT(
        'agreement_id', v_agreement.id,
        'revealed_at', v_reveal.revealed_at,
        'borrower', JSONB_BUILD_OBJECT(
            'full_name', v_borrower.full_name,
            'phone', v_borrower.phone,
            'email', v_borrower_auth.email
        ),
        'lender', JSONB_BUILD_OBJECT(
            'full_name', v_lender.full_name,
            'phone', v_lender.phone,
            'email', v_lender_auth.email
        )
    );

    -- Notify both parties
    INSERT INTO public.notifications (user_id, type, title, body, request_id, offer_id)
    VALUES
        (v_borrower_id, 'contact_revealed', 'Contact details unlocked',
         'You can now connect with your lender directly.',
         v_agreement.request_id, v_agreement.offer_id),
        (v_lender_id, 'contact_revealed', 'Borrower unlocked contact',
         'You can now connect with the borrower directly.',
         v_agreement.request_id, v_agreement.offer_id);

    -- Audit
    INSERT INTO public.audit_logs (user_id, event_type, entity_type, entity_id, action, new_values)
    VALUES (p_caller_id, 'contact_revealed', 'contact_reveals', v_reveal.id, 'unlock_contact',
        JSONB_BUILD_OBJECT(
            'agreement_id', p_agreement_id,
            'revealed_at', NOW()
        ));

    RETURN v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION private.unlock_contact_internal(uuid, uuid) TO authenticated, service_role;

-- Wrapper: SECURITY INVOKER
CREATE OR REPLACE FUNCTION public.unlock_contact(p_agreement_id UUID)
RETURNS JSONB
LANGUAGE sql SECURITY INVOKER
SET search_path = public AS $$
    SELECT private.unlock_contact_internal(p_agreement_id, auth.uid());
$$;

REVOKE EXECUTE ON FUNCTION public.unlock_contact(uuid) FROM public, anon;
GRANT  EXECUTE ON FUNCTION public.unlock_contact(uuid) TO authenticated, service_role;

COMMENT ON FUNCTION public.unlock_contact IS
'Borrower unlocks contact details after agreement is locked by bid acceptance.
 Reveals legal name, phone, and email of both parties. Irreversible. Returns contact JSONB.
 Platform never stores or retransmits these details after this point.';


-- ============================================
-- ROW-LEVEL SECURITY
-- ============================================

ALTER TABLE countries            ENABLE ROW LEVEL SECURITY;
ALTER TABLE system_settings      ENABLE ROW LEVEL SECURITY;
ALTER TABLE profiles             ENABLE ROW LEVEL SECURITY;
ALTER TABLE subscriptions        ENABLE ROW LEVEL SECURITY;
ALTER TABLE kyc_verifications    ENABLE ROW LEVEL SECURITY;
ALTER TABLE loan_requests        ENABLE ROW LEVEL SECURITY;
ALTER TABLE loan_offers          ENABLE ROW LEVEL SECURITY;
ALTER TABLE watchlist            ENABLE ROW LEVEL SECURITY;
ALTER TABLE contact_reveals      ENABLE ROW LEVEL SECURITY;
ALTER TABLE agreements           ENABLE ROW LEVEL SECURITY;
ALTER TABLE reviews              ENABLE ROW LEVEL SECURITY;
ALTER TABLE trust_aggregates     ENABLE ROW LEVEL SECURITY;
ALTER TABLE notifications        ENABLE ROW LEVEL SECURITY;
ALTER TABLE audit_logs           ENABLE ROW LEVEL SECURITY;
ALTER TABLE refresh_tokens       ENABLE ROW LEVEL SECURITY;
ALTER TABLE referrals            ENABLE ROW LEVEL SECURITY;
ALTER TABLE transactions         ENABLE ROW LEVEL SECURITY;


-- Helper function to safely fetch the current active user's subscription plan.
CREATE OR REPLACE FUNCTION public.get_my_subscription_plan()
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_plan TEXT;
BEGIN
    SELECT plan::TEXT INTO v_plan
    FROM public.subscriptions
    WHERE user_id = auth.uid()
      AND status = 'active'
    ORDER BY created_at DESC
    LIMIT 1;

    IF v_plan IS NULL THEN
        RETURN 'free';
    END IF;
    RETURN v_plan;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_my_subscription_plan() TO authenticated;


-- is_admin() lives in the `private` schema so it is NOT exposed
-- via the PostgREST REST API (/rpc/is_admin) but is still
-- callable by RLS policies and other SECURITY DEFINER functions.
-- (schema itself already created near the top of this file)

CREATE OR REPLACE FUNCTION private.is_admin()
RETURNS BOOLEAN LANGUAGE SQL SECURITY DEFINER STABLE
SET search_path = public AS $$
    SELECT EXISTS (
        SELECT 1 FROM profiles WHERE id = auth.uid() AND is_admin = TRUE
    );
$$;

GRANT USAGE  ON SCHEMA private TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION private.is_admin() TO authenticated, service_role;


-- countries — public reference data, readable by everyone; admin-only writes
CREATE POLICY "countries: public read"
    ON countries FOR SELECT TO authenticated, anon USING (TRUE);
CREATE POLICY "countries: admin write"
    ON countries FOR ALL TO authenticated USING (private.is_admin());

-- system_settings
CREATE POLICY "system_settings: authenticated read"
    ON system_settings FOR SELECT TO authenticated USING (is_public = TRUE OR private.is_admin());
CREATE POLICY "system_settings: admin write"
    ON system_settings FOR ALL TO authenticated USING (private.is_admin());

-- profiles
CREATE POLICY "profiles: own or admin read"
    ON profiles FOR SELECT TO authenticated
    USING (id = auth.uid() OR private.is_admin());
CREATE POLICY "profiles: own update"
    ON profiles FOR UPDATE TO authenticated
    USING (id = auth.uid()) WITH CHECK (id = auth.uid());

-- subscriptions
CREATE POLICY "subscriptions: own or admin read"
    ON subscriptions FOR SELECT TO authenticated
    USING (user_id = auth.uid() OR private.is_admin());
CREATE POLICY "subscriptions: own insert"
    ON subscriptions FOR INSERT TO authenticated
    WITH CHECK (user_id = auth.uid());
CREATE POLICY "subscriptions: own update"
    ON subscriptions FOR UPDATE TO authenticated
    USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());
CREATE POLICY "subscriptions: admin write"
    ON subscriptions FOR ALL TO authenticated USING (private.is_admin());


-- kyc_verifications
CREATE POLICY "kyc: own or admin read"
    ON kyc_verifications FOR SELECT TO authenticated
    USING (user_id = auth.uid() OR private.is_admin());
CREATE POLICY "kyc: own insert"
    ON kyc_verifications FOR INSERT TO authenticated
    WITH CHECK (user_id = auth.uid());
CREATE POLICY "kyc: own or admin update"
    ON kyc_verifications FOR UPDATE TO authenticated
    USING (user_id = auth.uid() OR private.is_admin());

-- loan_requests
-- NOTE: "global browse" policy (BUILD_PLAN.md) — this does NOT restrict
-- reads to the caller's own country. The Flutter client applies the
-- country default via MarketplaceRepository. If hard per-country RLS
-- isolation is ever adopted instead, add:
--   AND (country = (SELECT country FROM profiles WHERE id = auth.uid()) OR borrower_id = auth.uid() OR private.is_admin())
CREATE POLICY "loan_requests: marketplace read"
    ON loan_requests FOR SELECT TO authenticated
    USING (status = 'active' OR borrower_id = auth.uid() OR private.is_admin());
CREATE POLICY "loan_requests: own insert"
    ON loan_requests FOR INSERT TO authenticated
    WITH CHECK (borrower_id = auth.uid());
CREATE POLICY "loan_requests: own or admin update"
    ON loan_requests FOR UPDATE TO authenticated
    USING (borrower_id = auth.uid() OR private.is_admin());
CREATE POLICY "loan_requests: admin delete"
    ON loan_requests FOR DELETE TO authenticated USING (private.is_admin());

-- loan_offers
-- Borrowers see offers on their own listings; lenders see their own offers; admins see all.
-- No country restriction — cross-border offers are allowed by default (see trg_fn_validate_offer).
CREATE POLICY "loan_offers: relevant parties read"
    ON loan_offers FOR SELECT TO authenticated
    USING (
        lender_id = auth.uid()
        OR EXISTS (
            SELECT 1 FROM loan_requests lr
             WHERE lr.id = loan_offers.request_id AND lr.borrower_id = auth.uid()
        )
        OR private.is_admin()
    );
CREATE POLICY "loan_offers: lender insert"
    ON loan_offers FOR INSERT TO authenticated
    WITH CHECK (lender_id = auth.uid());
CREATE POLICY "loan_offers: lender withdraw or admin"
    ON loan_offers FOR UPDATE TO authenticated
    USING (
        (lender_id = auth.uid() AND status = 'pending')
        OR private.is_admin()
    );

-- watchlist
CREATE POLICY "watchlist: own rows"
    ON watchlist FOR ALL TO authenticated
    USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());

-- agreements
-- Only the matched parties (borrower / lender) can see the locked agreement.
CREATE POLICY "agreements: matched parties read"
    ON agreements FOR SELECT TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM loan_requests lr
             WHERE lr.id = agreements.request_id AND lr.borrower_id = auth.uid()
        )
        OR EXISTS (
            SELECT 1 FROM loan_offers lo
             WHERE lo.id = agreements.offer_id AND lo.lender_id = auth.uid()
        )
        OR private.is_admin()
    );
CREATE POLICY "agreements: service role insert"
    ON agreements FOR INSERT TO service_role WITH CHECK (TRUE);
CREATE POLICY "agreements: service role update"
    ON agreements FOR UPDATE TO service_role USING (TRUE) WITH CHECK (TRUE);
CREATE POLICY "agreements: admin all"
    ON agreements FOR ALL TO authenticated USING (private.is_admin());

-- Reviews are written only through submit_review(), which validates both
-- parties and the revealed agreement. Raw review data is readable only by
-- its author/admin; public reputation is exposed through the safe views.
CREATE POLICY "reviews: author or admin read"
    ON reviews FOR SELECT TO authenticated
    USING (reviewer_id = auth.uid() OR private.is_admin());
CREATE POLICY "reviews: no direct writes"
    ON reviews FOR ALL TO authenticated USING (FALSE) WITH CHECK (FALSE);
CREATE POLICY "trust aggregates: admin only"
    ON trust_aggregates FOR SELECT TO authenticated USING (private.is_admin());

-- contact_reveals
-- Only the parties on the matched offer (borrower / lender) can see the reveal record.
CREATE POLICY "contact_reveals: matched parties read"
    ON contact_reveals FOR SELECT TO authenticated
    USING (
        revealed_by = auth.uid()
        OR EXISTS (
            SELECT 1 FROM loan_offers lo
             WHERE lo.id = contact_reveals.offer_id AND lo.lender_id = auth.uid()
        )
        OR private.is_admin()
    );
CREATE POLICY "contact_reveals: own insert"
    ON contact_reveals FOR INSERT TO authenticated
    WITH CHECK (revealed_by = auth.uid());
CREATE POLICY "contact_reveals: admin write"
    ON contact_reveals FOR ALL TO authenticated USING (private.is_admin());

-- notifications
CREATE POLICY "notifications: own rows"
    ON notifications FOR SELECT TO authenticated USING (user_id = auth.uid());
CREATE POLICY "notifications: own mark read"
    ON notifications FOR UPDATE TO authenticated
    USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());
CREATE POLICY "notifications: admin write"
    ON notifications FOR ALL TO authenticated USING (private.is_admin());

-- audit_logs  (append-only — UPDATE and DELETE are blocked)
CREATE POLICY "audit_logs: own or admin read"
    ON audit_logs FOR SELECT TO authenticated
    USING (user_id = auth.uid() OR private.is_admin());
CREATE POLICY "audit_logs: insert only"
    ON audit_logs FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid());
CREATE POLICY "audit_logs: no update"
    ON audit_logs FOR UPDATE TO authenticated USING (FALSE);
CREATE POLICY "audit_logs: no delete"
    ON audit_logs FOR DELETE TO authenticated USING (FALSE);

-- refresh_tokens
CREATE POLICY "refresh_tokens: own or admin read"
    ON refresh_tokens FOR SELECT TO authenticated
    USING (user_id = auth.uid() OR private.is_admin());
CREATE POLICY "refresh_tokens: own insert"
    ON refresh_tokens FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid());
CREATE POLICY "refresh_tokens: own update"
    ON refresh_tokens FOR UPDATE TO authenticated USING (user_id = auth.uid());

-- referrals
CREATE POLICY "referrals: own or admin read"
    ON referrals FOR SELECT TO authenticated
    USING (referrer_id = auth.uid() OR private.is_admin());
CREATE POLICY "referrals: own insert"
    ON referrals FOR INSERT TO authenticated WITH CHECK (referrer_id = auth.uid());
CREATE POLICY "referrals: admin write"
    ON referrals FOR ALL TO authenticated USING (private.is_admin());

-- transactions — own or admin read; all writes go through the service-role
-- webhook Edge Function, never directly from the Flutter client.
CREATE POLICY "transactions: own or admin read"
    ON transactions FOR SELECT TO authenticated
    USING (user_id = auth.uid() OR private.is_admin());
CREATE POLICY "transactions: service role write"
    ON transactions FOR ALL TO service_role USING (TRUE) WITH CHECK (TRUE);


-- ============================================
-- REALTIME PUBLICATIONS
-- ============================================

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
        CREATE PUBLICATION supabase_realtime;
    END IF;
END $$;

ALTER PUBLICATION supabase_realtime ADD TABLE loan_requests;
ALTER PUBLICATION supabase_realtime ADD TABLE loan_offers;
ALTER PUBLICATION supabase_realtime ADD TABLE agreements;
ALTER PUBLICATION supabase_realtime ADD TABLE notifications;
ALTER PUBLICATION supabase_realtime ADD TABLE contact_reveals;


-- ============================================
-- DATABASE COMMENT
-- ============================================

DO $$
DECLARE db TEXT;
BEGIN
    SELECT current_database() INTO db;
    EXECUTE FORMAT('COMMENT ON DATABASE %I IS %L', db,
        'Nipanze v5.0 — Non-custodial loan listing matchmaking marketplace across the East '
        'African Community, Uganda-first. Unified marketplace: no stored borrower/lender role, '
        'capability comes from subscription_plan. Country is explicit, indexed, and locked at '
        'creation for listings; trust signals are global, not per-country. Borrowing is free. '
        'Lender offers require a subscription. Contact revealed only after offer acceptance. '
        'Platform never holds or tracks funds between borrower and lender, in any market.');
END $$;


-- ============================================
-- STORAGE BUCKETS
-- ============================================
-- Create via Supabase CLI or dashboard:
--   supabase storage create verification-documents --public=false

-- ============================================
-- STORAGE RLS POLICIES: verification-documents
-- ============================================
-- Files are stored under <user_uuid>/<docType>_<timestamp>.<ext>
-- Policy: each user may only access their own folder.

-- Users can upload their own KYC documents
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'storage'
      AND tablename  = 'objects'
      AND policyname = 'Users can upload their own KYC documents'
  ) THEN
    CREATE POLICY "Users can upload their own KYC documents"
    ON storage.objects FOR INSERT
    TO authenticated
    WITH CHECK (
      bucket_id = 'verification-documents'
      AND (storage.foldername(name))[1] = auth.uid()::text
    );
  END IF;
END $$;

-- Users can read (view) their own KYC documents
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'storage'
      AND tablename  = 'objects'
      AND policyname = 'Users can view their own KYC documents'
  ) THEN
    CREATE POLICY "Users can view their own KYC documents"
    ON storage.objects FOR SELECT
    TO authenticated
    USING (
      bucket_id = 'verification-documents'
      AND (storage.foldername(name))[1] = auth.uid()::text
    );
  END IF;
END $$;

-- Users can replace (upsert) their own KYC documents
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'storage'
      AND tablename  = 'objects'
      AND policyname = 'Users can update their own KYC documents'
  ) THEN
    CREATE POLICY "Users can update their own KYC documents"
    ON storage.objects FOR UPDATE
    TO authenticated
    USING (
      bucket_id = 'verification-documents'
      AND (storage.foldername(name))[1] = auth.uid()::text
    );
  END IF;
END $$;

-- Admins (service_role) can read all KYC documents for review
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'storage'
      AND tablename  = 'objects'
      AND policyname = 'Admins can view all KYC documents'
  ) THEN
    CREATE POLICY "Admins can view all KYC documents"
    ON storage.objects FOR SELECT
    TO service_role
    USING (bucket_id = 'verification-documents');
  END IF;
END $$;

-- ============================================
-- FUNCTION SECURITY (Disable public access for SECURITY DEFINER functions)
-- ============================================

-- Revoke public/authenticated/anon access on trigger/internal functions
REVOKE EXECUTE ON FUNCTION public.handle_new_auth_user() FROM public, authenticated, anon;
REVOKE EXECUTE ON FUNCTION public.trg_fn_require_active_account() FROM public, authenticated, anon;
REVOKE EXECUTE ON FUNCTION public.trg_fn_max_concurrent_requests() FROM public, authenticated, anon;
REVOKE EXECUTE ON FUNCTION public.trg_fn_validate_offer() FROM public, authenticated, anon;
REVOKE EXECUTE ON FUNCTION public.trg_fn_set_request_country() FROM public, authenticated, anon;

-- Revoke public/anon access on client-facing RPCs and restrict to authenticated/service_role
-- is_admin is in the private schema — only grant to authenticated for RLS use
REVOKE EXECUTE ON FUNCTION private.is_admin() FROM public, anon;
GRANT  EXECUTE ON FUNCTION private.is_admin() TO authenticated, service_role;

REVOKE EXECUTE ON FUNCTION public.accept_offer(uuid, uuid, uuid) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.accept_offer(uuid, uuid, uuid) TO authenticated, service_role;

REVOKE EXECUTE ON FUNCTION public.reveal_contact(uuid, uuid) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.reveal_contact(uuid, uuid) TO authenticated, service_role;

REVOKE EXECUTE ON FUNCTION public.get_my_subscription_plan() FROM public, anon;
GRANT EXECUTE ON FUNCTION public.get_my_subscription_plan() TO authenticated, service_role;

REVOKE EXECUTE ON FUNCTION get_marketplace_pro_filtered(employment_type_enum, TEXT, BOOLEAN, BOOLEAN, TEXT) FROM public, anon;
GRANT EXECUTE ON FUNCTION get_marketplace_pro_filtered(employment_type_enum, TEXT, BOOLEAN, BOOLEAN, TEXT) TO authenticated, service_role;


-- ============================================
-- VIEW: v_lender_rate_history
-- Safe, identity-preserving view for lender rate sparklines.
-- Exposes only numeric trend data — no borrower info, no PII.
-- ============================================
CREATE OR REPLACE VIEW public.v_lender_rate_history
WITH (security_invoker = true) AS
SELECT
    lender_id,
    interest_rate_pct,
    late_fee_pct,
    installment_amount,
    offered_at,
    ROW_NUMBER() OVER (
        PARTITION BY lender_id ORDER BY offered_at DESC
    ) AS rn
FROM public.loan_offers
WHERE status IN ('pending', 'accepted', 'rejected');


-- ============================================
-- RPC: consume_free_unlock()
-- Atomically decrements free_unlocks_remaining for the calling user.
-- Returns new remaining count. Raises NIPANZE_NO_FREE_UNLOCKS if count=0.
-- ============================================
CREATE OR REPLACE FUNCTION public.consume_free_unlock()
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user_id   UUID := auth.uid();
    v_remaining INT;
BEGIN
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'NIPANZE_UNAUTHORIZED';
    END IF;

    SELECT free_unlocks_remaining
      INTO v_remaining
      FROM profiles
     WHERE id = v_user_id
       FOR UPDATE;

    IF v_remaining IS NULL THEN
        RAISE EXCEPTION 'NIPANZE_PROFILE_NOT_FOUND';
    END IF;

    IF v_remaining <= 0 THEN
        RAISE EXCEPTION 'NIPANZE_NO_FREE_UNLOCKS';
    END IF;

    UPDATE profiles
       SET free_unlocks_remaining = free_unlocks_remaining - 1,
           updated_at             = NOW()
     WHERE id = v_user_id
    RETURNING free_unlocks_remaining INTO v_remaining;

    RETURN v_remaining;
END;
$$;

COMMENT ON FUNCTION public.consume_free_unlock() IS
'Atomically decrements free_unlocks_remaining for the calling authenticated user. '
'Returns new remaining count. Raises NIPANZE_NO_FREE_UNLOCKS if count is already 0.';


-- ============================================
-- END OF SCHEMA v5.0
-- ============================================
-- Grants for views
GRANT SELECT ON countries TO authenticated, anon;
GRANT SELECT ON v_loan_listings TO authenticated, anon;
GRANT SELECT ON v_loan_listing_details TO authenticated, anon;
GRANT SELECT ON v_user_marketplace_activity TO authenticated, anon;
GRANT SELECT ON v_lender_offers TO authenticated, anon;
GRANT SELECT ON v_marketplace_activity TO authenticated, anon;
GRANT SELECT ON v_marketplace_pro_filters TO authenticated;
GRANT SELECT ON v_trust_profile_public TO authenticated, anon;
GRANT SELECT ON v_trust_profile_pro TO authenticated;
GRANT EXECUTE ON FUNCTION fn_income_bracket(BIGINT) TO authenticated, anon;
GRANT EXECUTE ON FUNCTION public.submit_review(UUID, SMALLINT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.recompute_trust_aggregates(UUID) TO service_role;

-- Explicitly grant privileges on schema and tables
GRANT USAGE ON SCHEMA public TO authenticated, anon, service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO authenticated, service_role;
GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA public TO anon;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO authenticated, anon, service_role;
GRANT EXECUTE ON FUNCTION public.check_phone_registered(TEXT) TO authenticated, anon, service_role;

GRANT SELECT ON public.v_lender_rate_history TO authenticated;
GRANT EXECUTE ON FUNCTION public.consume_free_unlock() TO authenticated;
