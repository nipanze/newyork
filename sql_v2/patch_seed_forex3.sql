-- ============================================
-- NIPANZE — Patch v6.4: Multi-currency forex seed (popular EA + Africa pairs)
-- Paste into Supabase Cloud SQL Editor and run once. Idempotent.
--
-- Prerequisite: patch_schema_v6.sql and patch_seed_forex.sql (v6.2) must
-- already be applied. patch_seed_forex2.sql is optional.
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
