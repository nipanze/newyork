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