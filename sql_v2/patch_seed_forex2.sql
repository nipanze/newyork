-- ============================================
-- NIPANZE — Patch v6.3: Extra UGX → KES forex listings
-- Paste into Supabase Cloud SQL Editor and run once. Idempotent.
--
-- Prerequisite: patch_seed_forex.sql (v6.2) must already be applied.
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
