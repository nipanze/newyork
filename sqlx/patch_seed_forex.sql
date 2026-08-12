-- ============================================
-- NIPANZE — Patch v6.2: Forex seed data
-- Paste into Supabase Cloud SQL Editor and run once. Idempotent.
--
-- The v6.0 schema patch (patch_v6.sql) added the Forex module tables, but
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