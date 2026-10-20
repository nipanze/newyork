-- ============================================
-- NIPANZE Seed Data  sql/seed.sql
-- Version: 5.1 (Country-organized, user counts matched across all countries)
-- Matches schema v5.0 exactly (countries table, profiles.country,
-- loan_requests.country, subscriptions.amount_minor_units, no
-- loan_offers.country -- country is always read through request_id).
-- ============================================
--
-- v5.1: every country now has the SAME number of users as Uganda (17),
-- mirroring Uganda's role mix so each country's block is a drop-in
-- parallel of the others:
--   8 active borrowers (free plan)
--   5 lenders (mix of 'lender' / 'pro' plans)
--   1 pending_verification borrower (tests the account-status gate)
--   2 admins (is_admin = TRUE)
--   1 test user
-- = 17 users per country x 8 countries (UG + KE, TZ, RW, BI, SS, CD, SO)
--   = 136 total seeded users.
--
-- Organization: Part A seeds users country-by-country (auth.users ->
-- profiles -> subscriptions), so any single country's users can be
-- inspected, reset, or re-run independently. Part B (marketplace data)
-- is separate because loan_offers can legitimately cross borders
-- (trg_fn_validate_offer allows this by default) -- a request seeded in
-- one country's block may carry an offer from a lender seeded in a
-- different country's block, so requests/offers/agreements/reveals are
-- grouped together afterward, by the request's country, in listing order.
--
-- Password for ALL accounts: Test1234!
--
-- FIXED UUIDs -- Uganda (unchanged from prior versions): ...0001-...0017
-- FIXED UUIDs -- new countries, 17 consecutive IDs each, in this order:
--   Kenya       ...0018-...0034   (borrowers 018-025, lenders 026-030, pending 031, admins 032-033, test 034)
--   Tanzania    ...0035-...0051   (borrowers 035-042, lenders 043-047, pending 048, admins 049-050, test 051)
--   Rwanda      ...0052-...0068   (borrowers 052-059, lenders 060-064, pending 065, admins 066-067, test 068)
--   Burundi     ...0069-...0085   (borrowers 069-076, lenders 077-081, pending 082, admins 083-084, test 085)
--   South Sudan ...0086-...0102   (borrowers 086-093, lenders 094-098, pending 099, admins 100-101, test 102)
--   DR Congo    ...0103-...0119   (borrowers 103-110, lenders 111-115, pending 116, admins 117-118, test 119)
--   Somalia     ...0120-...0136   (borrowers 120-127, lenders 128-132, pending 133, admins 134-135, test 136)
--
-- Each country's borrower[0] and lender[0] (first names in each list) are
-- the ones referenced in the marketplace demo data in Part B, so e.g.
-- Kenya's "Wanjiru Kamau" (...0018) and "Otieno Mwangi" (...0026) keep
-- their names and roles from earlier seed versions.
-- ============================================


-- ============================================================
-- PART A -- USERS, ORGANIZED BY COUNTRY
-- ============================================================
-- COUNTRY: UGANDA (UG)
-- ============================================

-- ---- UG: auth.users ----
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
('10000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'david.mukasa@gmail.com', crypt('Test1234!', gen_salt('bf')),
 NOW(), '2024-01-15 08:30:00', '2024-01-15 08:30:00', '{"provider":"email","providers":["email"]}', '{"full_name":"David Mukasa","country_code":"UG"}',
 FALSE, 'authenticated', 'authenticated', '', '', '', '', '', '', '', ''),
('10000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'sarah.namukasa@yahoo.com', crypt('Test1234!', gen_salt('bf')),
 NOW(), '2024-01-18 10:45:00', '2024-01-18 10:45:00', '{"provider":"email","providers":["email"]}', '{"full_name":"Sarah Namukasa","country_code":"UG"}',
 FALSE, 'authenticated', 'authenticated', '', '', '', '', '', '', '', ''),
('10000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000000', 'james.okello@outlook.com', crypt('Test1234!', gen_salt('bf')),
 NOW(), '2024-01-20 14:20:00', '2024-01-20 14:20:00', '{"provider":"email","providers":["email"]}', '{"full_name":"James Okello","country_code":"UG"}',
 FALSE, 'authenticated', 'authenticated', '', '', '', '', '', '', '', ''),
('10000000-0000-0000-0000-000000000004', '00000000-0000-0000-0000-000000000000', 'maria.nakato@gmail.com', crypt('Test1234!', gen_salt('bf')),
 NOW(), '2024-01-22 09:10:00', '2024-01-22 09:10:00', '{"provider":"email","providers":["email"]}', '{"full_name":"Maria Nakato","country_code":"UG"}',
 FALSE, 'authenticated', 'authenticated', '', '', '', '', '', '', '', ''),
('10000000-0000-0000-0000-000000000005', '00000000-0000-0000-0000-000000000000', 'robert.ssemwanga@gmail.com', crypt('Test1234!', gen_salt('bf')),
 NOW(), '2024-01-25 11:30:00', '2024-01-25 11:30:00', '{"provider":"email","providers":["email"]}', '{"full_name":"Robert Ssemwanga","country_code":"UG"}',
 FALSE, 'authenticated', 'authenticated', '', '', '', '', '', '', '', ''),
('10000000-0000-0000-0000-000000000006', '00000000-0000-0000-0000-000000000000', 'info@greenleafagro.co.ug', crypt('Test1234!', gen_salt('bf')),
 NOW(), '2024-02-18 09:20:00', '2024-02-18 09:20:00', '{"provider":"email","providers":["email"]}', '{"full_name":"Michael Semakula","country_code":"UG"}',
 FALSE, 'authenticated', 'authenticated', '', '', '', '', '', '', '', ''),
('10000000-0000-0000-0000-000000000007', '00000000-0000-0000-0000-000000000000', 'contact@kampalatech.ug', crypt('Test1234!', gen_salt('bf')),
 NOW(), '2024-02-20 11:40:00', '2024-02-20 11:40:00', '{"provider":"email","providers":["email"]}', '{"full_name":"Sandra Namutebi","country_code":"UG"}',
 FALSE, 'authenticated', 'authenticated', '', '', '', '', '', '', '', ''),
('10000000-0000-0000-0000-000000000008', '00000000-0000-0000-0000-000000000000', 'invest@pearlcapital.ug', crypt('Test1234!', gen_salt('bf')),
 NOW(), '2024-03-01 10:10:00', '2024-03-01 10:10:00', '{"provider":"email","providers":["email"]}', '{"full_name":"William Kasujja","country_code":"UG"}',
 FALSE, 'authenticated', 'authenticated', '', '', '', '', '', '', '', ''),
('10000000-0000-0000-0000-000000000009', '00000000-0000-0000-0000-000000000000', 'funds@victoriainvest.co.ug', crypt('Test1234!', gen_salt('bf')),
 NOW(), '2024-03-03 12:30:00', '2024-03-03 12:30:00', '{"provider":"email","providers":["email"]}', '{"full_name":"Catherine Namboze","country_code":"UG"}',
 FALSE, 'authenticated', 'authenticated', '', '', '', '', '', '', '', ''),
('10000000-0000-0000-0000-000000000010', '00000000-0000-0000-0000-000000000000', 'lending@equatorfinance.ug', crypt('Test1234!', gen_salt('bf')),
 NOW(), '2024-03-05 09:45:00', '2024-03-05 09:45:00', '{"provider":"email","providers":["email"]}', '{"full_name":"George Mulindwa","country_code":"UG"}',
 FALSE, 'authenticated', 'authenticated', '', '', '', '', '', '', '', ''),
('10000000-0000-0000-0000-000000000011', '00000000-0000-0000-0000-000000000000', 'frank.omondi@gmail.com', crypt('Test1234!', gen_salt('bf')),
 NOW(), '2024-03-08 14:15:00', '2024-03-08 14:15:00', '{"provider":"email","providers":["email"]}', '{"full_name":"Frank Omondi","country_code":"UG"}',
 FALSE, 'authenticated', 'authenticated', '', '', '', '', '', '', '', ''),
('10000000-0000-0000-0000-000000000012', '00000000-0000-0000-0000-000000000000', 'lucy.nambi@yahoo.com', crypt('Test1234!', gen_salt('bf')),
 NOW(), '2024-03-10 11:20:00', '2024-03-10 11:20:00', '{"provider":"email","providers":["email"]}', '{"full_name":"Lucy Nambi","country_code":"UG"}',
 FALSE, 'authenticated', 'authenticated', '', '', '', '', '', '', '', ''),
('10000000-0000-0000-0000-000000000013', '00000000-0000-0000-0000-000000000000', 'charles.mwesigwa@gmail.com', crypt('Test1234!', gen_salt('bf')),
 NOW(), '2024-03-12 16:40:00', '2024-03-12 16:40:00', '{"provider":"email","providers":["email"]}', '{"full_name":"Charles Mwesigwa","country_code":"UG"}',
 FALSE, 'authenticated', 'authenticated', '', '', '', '', '', '', '', ''),
('10000000-0000-0000-0000-000000000014', '00000000-0000-0000-0000-000000000000', 'alice.namuli@gmail.com', crypt('Test1234!', gen_salt('bf')),
 NOW(), '2026-01-25 09:15:00', '2026-01-25 09:15:00', '{"provider":"email","providers":["email"]}', '{"full_name":"Alice Namuli","country_code":"UG"}',
 FALSE, 'authenticated', 'authenticated', '', '', '', '', '', '', '', ''),
('10000000-0000-0000-0000-000000000015', '00000000-0000-0000-0000-000000000000', 'admin1@nipanze.ug', crypt('Test1234!', gen_salt('bf')),
 NOW(), '2024-01-01 08:00:00', '2024-01-01 08:00:00', '{"provider":"email","providers":["email"]}', '{"full_name":"Admin One","country_code":"UG"}',
 FALSE, 'authenticated', 'authenticated', '', '', '', '', '', '', '', ''),
('10000000-0000-0000-0000-000000000016', '00000000-0000-0000-0000-000000000000', 'admin2@nipanze.ug', crypt('Test1234!', gen_salt('bf')),
 NOW(), '2024-01-01 08:00:00', '2024-01-01 08:00:00', '{"provider":"email","providers":["email"]}', '{"full_name":"Admin Two","country_code":"UG"}',
 FALSE, 'authenticated', 'authenticated', '', '', '', '', '', '', '', ''),
('10000000-0000-0000-0000-000000000017', '00000000-0000-0000-0000-000000000000', 'test.user@gmail.com', crypt('Test1234!', gen_salt('bf')),
 NOW(), '2026-02-06 10:00:00', '2026-02-06 10:00:00', '{"provider":"email","providers":["email"]}', '{"full_name":"Test User","country_code":"UG"}',
 FALSE, 'authenticated', 'authenticated', '', '', '', '', '', '', '', '')
ON CONFLICT (id) DO NOTHING;

-- ---- UG: profiles / subscriptions fallback provisioning ----
-- (Guards against the on_auth_user_created trigger not firing if these
-- auth.users rows already existed from a prior run — see header note.)
INSERT INTO public.profiles (id, full_name, account_status, is_admin, country)
SELECT au.id, COALESCE(au.raw_user_meta_data->>'full_name', SPLIT_PART(au.email, '@', 1)), 'pending_verification', FALSE, 'UG'
FROM auth.users au
WHERE au.id::text LIKE '10000000-0000-0000-0000-0000000000%'
  AND au.id::text ~ '0000000000(0[1-9]|1[0-7])$'
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.subscriptions (user_id, plan, status, amount_minor_units)
SELECT au.id, 'free', 'active', 0
FROM auth.users au
WHERE au.id::text ~ '0000000000(0[1-9]|1[0-7])$'
ON CONFLICT (user_id) WHERE status = 'active' DO NOTHING;

-- ---- UG: profile details ----
UPDATE profiles SET full_name='David Mukasa', phone='+256701234567', district='Central', country='UG',
    employment_type='government_employee', employer_name='Uganda Revenue Authority', monthly_income=4500000, income_currency='UGX',
    account_status='active', created_at='2024-01-15 08:30:00'
WHERE id='10000000-0000-0000-0000-000000000001';

UPDATE profiles SET full_name='Sarah Namukasa', phone='+256702345678', district='Central', country='UG',
    employment_type='employed', employer_name='Stanbic Bank Uganda', monthly_income=3200000, income_currency='UGX',
    account_status='active', created_at='2024-01-18 10:45:00'
WHERE id='10000000-0000-0000-0000-000000000002';

UPDATE profiles SET full_name='James Okello', phone='+256703456789', district='Central', country='UG',
    employment_type='employed', employer_name='MTN Uganda', monthly_income=5800000, income_currency='UGX',
    account_status='active', created_at='2024-01-20 14:20:00'
WHERE id='10000000-0000-0000-0000-000000000003';

UPDATE profiles SET full_name='Maria Nakato', phone='+256704567890', district='Central', country='UG',
    employment_type='small_business_owner', employer_name='Nakato Boutique', monthly_income=2800000, income_currency='UGX',
    account_status='active', created_at='2024-01-22 09:10:00'
WHERE id='10000000-0000-0000-0000-000000000004';

UPDATE profiles SET full_name='Robert Ssemwanga', phone='+256705678901', district='Central', country='UG',
    employment_type='employed', employer_name='DFCU Bank', monthly_income=6500000, income_currency='UGX',
    account_status='active', created_at='2024-01-25 11:30:00'
WHERE id='10000000-0000-0000-0000-000000000005';

UPDATE profiles SET full_name='Michael Semakula', phone='+256711234567', district='Central', country='UG',
    employment_type='business_owner', employer_name='GreenLeaf Agro Solutions Ltd', monthly_income=15000000, income_currency='UGX',
    account_status='active', created_at='2024-02-18 09:20:00'
WHERE id='10000000-0000-0000-0000-000000000006';

UPDATE profiles SET full_name='Sandra Namutebi', phone='+256712345678', district='Central', country='UG',
    employment_type='business_owner', employer_name='Kampala Tech Innovations', monthly_income=12000000, income_currency='UGX',
    account_status='active', created_at='2024-02-20 11:40:00'
WHERE id='10000000-0000-0000-0000-000000000007';

UPDATE profiles SET full_name='William Kasujja', phone='+256716789012', district='Central', country='UG',
    employment_type='business_owner', employer_name='Pearl Capital Investment Fund', monthly_income=25000000, income_currency='UGX',
    account_status='active', created_at='2024-03-01 10:10:00'
WHERE id='10000000-0000-0000-0000-000000000008';

UPDATE profiles SET full_name='Catherine Namboze', phone='+256717890123', district='Central', country='UG',
    employment_type='business_owner', employer_name='Victoria Investment Group', monthly_income=22000000, income_currency='UGX',
    account_status='active', created_at='2024-03-03 12:30:00'
WHERE id='10000000-0000-0000-0000-000000000009';

UPDATE profiles SET full_name='George Mulindwa', phone='+256718901234', district='Central', country='UG',
    employment_type='business_owner', employer_name='Equator Finance Corporation', monthly_income=28000000, income_currency='UGX',
    account_status='active', created_at='2024-03-05 09:45:00'
WHERE id='10000000-0000-0000-0000-000000000010';

UPDATE profiles SET full_name='Frank Omondi', phone='+256719012345', district='Eastern', country='UG',
    employment_type='employed', employer_name='Bank of Africa', monthly_income=3300000, income_currency='UGX',
    account_status='active', created_at='2024-03-08 14:15:00'
WHERE id='10000000-0000-0000-0000-000000000011';

UPDATE profiles SET full_name='Lucy Nambi', phone='+256720123456', district='Central', country='UG',
    employment_type='employed', employer_name='National Social Security Fund', monthly_income=2900000, income_currency='UGX',
    account_status='active', created_at='2024-03-10 11:20:00'
WHERE id='10000000-0000-0000-0000-000000000012';

UPDATE profiles SET full_name='Charles Mwesigwa', phone='+256721234567', district='Western', country='UG',
    employment_type='employed', employer_name='Shell Uganda', monthly_income=5200000, income_currency='UGX',
    account_status='active', created_at='2024-03-12 16:40:00'
WHERE id='10000000-0000-0000-0000-000000000013';

-- Alice Namuli — pending_verification (tests the account-status gate)
UPDATE profiles SET full_name='Alice Namuli', phone='+256726789012', district='Central', country='UG',
    employment_type='employed', employer_name='Equity Bank', monthly_income=2700000, income_currency='UGX',
    account_status='pending_verification', created_at='2026-01-25 09:15:00'
WHERE id='10000000-0000-0000-0000-000000000014';

-- Admins (is_admin boolean is the only role concept — no `role` column)
UPDATE profiles SET full_name='Admin One', phone='+256700000001', district='Central', country='UG',
    account_status='active', is_admin=TRUE, created_at='2024-01-01 08:00:00'
WHERE id='10000000-0000-0000-0000-000000000015';

UPDATE profiles SET full_name='Admin Two', phone='+256700000002', district='Central', country='UG',
    account_status='active', is_admin=TRUE, created_at='2024-01-01 08:00:00'
WHERE id='10000000-0000-0000-0000-000000000016';

-- Test user — tests onboarding gate
UPDATE profiles SET full_name='Test User', phone='+256799999999', district='Central', country='UG',
    account_status='active', created_at='2026-02-06 10:00:00'
WHERE id='10000000-0000-0000-0000-000000000017';

-- ---- UG: KYC (optional; not required to post a request) ----
INSERT INTO kyc_verifications (
    id, user_id, status, national_id_type, national_id_number,
    national_id_front_url, national_id_back_url, selfie_url,
    id_verified, selfie_verified, verified_by,
    submitted_at, reviewed_at, expires_at, created_at
) VALUES
('a1000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', 'approved', 'national_id', 'CM88015KL234567', 'https://storage.nipanze.ug/kyc/user-001-id-front.jpg', 'https://storage.nipanze.ug/kyc/user-001-id-back.jpg', 'https://storage.nipanze.ug/kyc/user-001-selfie.jpg', TRUE, TRUE, '10000000-0000-0000-0000-000000000015', '2024-01-15 09:15:00', '2024-01-16 10:30:00', '2027-01-15 00:00:00', '2024-01-15 09:15:00'),
('a1000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000002', 'approved', 'national_id', 'CM92022NM345678', 'https://storage.nipanze.ug/kyc/user-002-id-front.jpg', 'https://storage.nipanze.ug/kyc/user-002-id-back.jpg', 'https://storage.nipanze.ug/kyc/user-002-selfie.jpg', TRUE, TRUE, '10000000-0000-0000-0000-000000000015', '2024-01-18 11:00:00', '2024-01-19 11:45:00', '2027-01-18 00:00:00', '2024-01-18 11:00:00'),
('a1000000-0000-0000-0000-000000000003', '10000000-0000-0000-0000-000000000003', 'approved', 'national_id', 'CM85011OK345679', 'https://storage.nipanze.ug/kyc/user-003-id-front.jpg', 'https://storage.nipanze.ug/kyc/user-003-id-back.jpg', 'https://storage.nipanze.ug/kyc/user-003-selfie.jpg', TRUE, TRUE, '10000000-0000-0000-0000-000000000016', '2024-01-20 14:30:00', '2024-01-21 09:30:00', '2027-01-20 00:00:00', '2024-01-20 14:30:00'),
('a1000000-0000-0000-0000-000000000004', '10000000-0000-0000-0000-000000000004', 'approved', 'national_id', 'CM90014NK567890', 'https://storage.nipanze.ug/kyc/user-004-id-front.jpg', 'https://storage.nipanze.ug/kyc/user-004-id-back.jpg', 'https://storage.nipanze.ug/kyc/user-004-selfie.jpg', TRUE, TRUE, '10000000-0000-0000-0000-000000000016', '2024-01-22 09:30:00', '2024-01-23 14:30:00', '2027-01-22 00:00:00', '2024-01-22 09:30:00'),
('a1000000-0000-0000-0000-000000000005', '10000000-0000-0000-0000-000000000005', 'approved', 'national_id', 'CM87030SS678901', 'https://storage.nipanze.ug/kyc/user-005-id-front.jpg', 'https://storage.nipanze.ug/kyc/user-005-id-back.jpg', 'https://storage.nipanze.ug/kyc/user-005-selfie.jpg', TRUE, TRUE, '10000000-0000-0000-0000-000000000015', '2024-01-25 11:45:00', '2024-01-25 16:00:00', '2027-01-25 00:00:00', '2024-01-25 11:45:00'),
('a1000000-0000-0000-0000-000000000006', '10000000-0000-0000-0000-000000000006', 'approved', 'national_id', 'CM80020SM456789', 'https://storage.nipanze.ug/kyc/user-006-id-front.jpg', 'https://storage.nipanze.ug/kyc/user-006-id-back.jpg', 'https://storage.nipanze.ug/kyc/user-006-selfie.jpg', TRUE, TRUE, '10000000-0000-0000-0000-000000000016', '2024-02-18 09:00:00', '2024-02-19 10:30:00', '2027-02-18 00:00:00', '2024-02-18 09:00:00'),
('a1000000-0000-0000-0000-000000000007', '10000000-0000-0000-0000-000000000007', 'approved', 'national_id', 'CM83015SN789012', 'https://storage.nipanze.ug/kyc/user-007-id-front.jpg', 'https://storage.nipanze.ug/kyc/user-007-id-back.jpg', 'https://storage.nipanze.ug/kyc/user-007-selfie.jpg', TRUE, TRUE, '10000000-0000-0000-0000-000000000015', '2024-02-20 10:00:00', '2024-02-21 11:00:00', '2027-02-20 00:00:00', '2024-02-20 10:00:00'),
('a1000000-0000-0000-0000-000000000008', '10000000-0000-0000-0000-000000000008', 'approved', 'national_id', 'CM75018WK890123', 'https://storage.nipanze.ug/kyc/user-008-id-front.jpg', 'https://storage.nipanze.ug/kyc/user-008-id-back.jpg', 'https://storage.nipanze.ug/kyc/user-008-selfie.jpg', TRUE, TRUE, '10000000-0000-0000-0000-000000000015', '2024-03-01 09:00:00', '2024-03-02 10:00:00', '2027-03-01 00:00:00', '2024-03-01 09:00:00'),
('a1000000-0000-0000-0000-000000000009', '10000000-0000-0000-0000-000000000009', 'approved', 'national_id', 'CM77012CN901234', 'https://storage.nipanze.ug/kyc/user-009-id-front.jpg', 'https://storage.nipanze.ug/kyc/user-009-id-back.jpg', 'https://storage.nipanze.ug/kyc/user-009-selfie.jpg', TRUE, TRUE, '10000000-0000-0000-0000-000000000016', '2024-03-03 11:00:00', '2024-03-04 11:00:00', '2027-03-03 00:00:00', '2024-03-03 11:00:00'),
('a1000000-0000-0000-0000-000000000010', '10000000-0000-0000-0000-000000000010', 'approved', 'national_id', 'CM79025GM012345', 'https://storage.nipanze.ug/kyc/user-010-id-front.jpg', 'https://storage.nipanze.ug/kyc/user-010-id-back.jpg', 'https://storage.nipanze.ug/kyc/user-010-selfie.jpg', TRUE, TRUE, '10000000-0000-0000-0000-000000000015', '2024-03-05 09:00:00', '2024-03-06 10:00:00', '2027-03-05 00:00:00', '2024-03-05 09:00:00'),
('a1000000-0000-0000-0000-000000000011', '10000000-0000-0000-0000-000000000011', 'approved', 'national_id', 'CM91114OM789012', 'https://storage.nipanze.ug/kyc/user-011-id-front.jpg', 'https://storage.nipanze.ug/kyc/user-011-id-back.jpg', 'https://storage.nipanze.ug/kyc/user-011-selfie.jpg', TRUE, TRUE, '10000000-0000-0000-0000-000000000016', '2024-03-08 09:30:00', '2024-03-09 14:00:00', '2027-03-08 00:00:00', '2024-03-08 09:30:00'),
('a1000000-0000-0000-0000-000000000012', '10000000-0000-0000-0000-000000000012', 'approved', 'national_id', 'CM88047NB890123', 'https://storage.nipanze.ug/kyc/user-012-id-front.jpg', 'https://storage.nipanze.ug/kyc/user-012-id-back.jpg', 'https://storage.nipanze.ug/kyc/user-012-selfie.jpg', TRUE, TRUE, '10000000-0000-0000-0000-000000000015', '2024-03-10 09:00:00', '2024-03-11 11:00:00', '2027-03-10 00:00:00', '2024-03-10 09:00:00'),
('a1000000-0000-0000-0000-000000000013', '10000000-0000-0000-0000-000000000013', 'approved', 'national_id', 'CM84021MW901234', 'https://storage.nipanze.ug/kyc/user-013-id-front.jpg', 'https://storage.nipanze.ug/kyc/user-013-id-back.jpg', 'https://storage.nipanze.ug/kyc/user-013-selfie.jpg', TRUE, TRUE, '10000000-0000-0000-0000-000000000016', '2024-03-12 12:00:00', '2024-03-13 15:00:00', '2027-03-12 00:00:00', '2024-03-12 12:00:00'),
('a1000000-0000-0000-0000-000000000014', '10000000-0000-0000-0000-000000000014', 'pending', 'national_id', 'CM93255NM789013', 'https://storage.nipanze.ug/kyc/user-014-id-front.jpg', 'https://storage.nipanze.ug/kyc/user-014-id-back.jpg', 'https://storage.nipanze.ug/kyc/user-014-selfie.jpg', FALSE, FALSE, NULL, '2026-01-25 10:30:00', NULL, NULL, '2026-01-25 10:30:00')
ON CONFLICT (user_id) DO NOTHING;

-- ---- UG: subscriptions (upgrade lenders; borrowers stay on free) ----
UPDATE subscriptions SET plan='lender', status='active', amount_minor_units=35000,  started_at='2024-02-18 10:00:00', expires_at='2028-02-18 10:00:00', auto_renew=TRUE  WHERE user_id='10000000-0000-0000-0000-000000000006';
UPDATE subscriptions SET plan='lender', status='active', amount_minor_units=35000,  started_at='2024-02-20 12:00:00', expires_at='2028-02-20 12:00:00', auto_renew=TRUE  WHERE user_id='10000000-0000-0000-0000-000000000007';
UPDATE subscriptions SET plan='pro',    status='active', amount_minor_units=150000, started_at='2024-03-01 11:00:00', expires_at='2028-03-01 11:00:00', auto_renew=TRUE  WHERE user_id='10000000-0000-0000-0000-000000000008';
UPDATE subscriptions SET plan='pro',    status='active', amount_minor_units=150000, started_at='2024-03-03 13:00:00', expires_at='2028-03-03 13:00:00', auto_renew=TRUE  WHERE user_id='10000000-0000-0000-0000-000000000009';
UPDATE subscriptions SET plan='lender', status='active', amount_minor_units=35000,  started_at='2024-03-05 10:00:00', expires_at='2028-03-05 10:00:00', auto_renew=TRUE  WHERE user_id='10000000-0000-0000-0000-000000000010';
UPDATE subscriptions SET plan='pro',    status='active', amount_minor_units=150000, started_at='2024-01-20 15:00:00', expires_at='2028-01-20 15:00:00', auto_renew=TRUE  WHERE user_id='10000000-0000-0000-0000-000000000003';
UPDATE subscriptions SET plan='lender', status='active', amount_minor_units=35000,  started_at='2024-01-25 12:00:00', expires_at='2028-01-25 12:00:00', auto_renew=TRUE  WHERE user_id='10000000-0000-0000-0000-000000000005';
-- remaining UG borrowers (001, 002, 004, 011, 012, 013, 014, 017) stay free — no update needed


-- ============================================
-- ============================================
-- COUNTRY: KENYA (KE) — 17 users, mirrors Uganda's structure
-- 8 active borrowers, 5 lenders (lender/pro), 1 pending-verification borrower,
-- 2 admins, 1 test user.
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
('10000000-0000-0000-0000-000000000018', '00000000-0000-0000-0000-000000000000', 'wanjiru.kamau@nipanze-ke.test', crypt('Test1234!', gen_salt('bf')), NOW(), '2026-02-10 08:00:00', '2026-02-10 08:00:00', '{"provider":"email","providers":["email"]}', '{"full_name":"Wanjiru Kamau","country_code":"KE"}', FALSE, 'authenticated', 'authenticated', '', '', '', '', '', '', '', ''),
('10000000-0000-0000-0000-000000000019', '00000000-0000-0000-0000-000000000000', 'njoroge.kariuki@nipanze-ke.test', crypt('Test1234!', gen_salt('bf')), NOW(), '2026-02-11 08:03:00', '2026-02-11 08:03:00', '{"provider":"email","providers":["email"]}', '{"full_name":"Njoroge Kariuki","country_code":"KE"}', FALSE, 'authenticated', 'authenticated', '', '', '', '', '', '', '', ''),
('10000000-0000-0000-0000-000000000020', '00000000-0000-0000-0000-000000000000', 'achieng.odhiambo@nipanze-ke.test', crypt('Test1234!', gen_salt('bf')), NOW(), '2026-02-12 08:06:00', '2026-02-12 08:06:00', '{"provider":"email","providers":["email"]}', '{"full_name":"Achieng Odhiambo","country_code":"KE"}', FALSE, 'authenticated', 'authenticated', '', '', '', '', '', '', '', ''),
('10000000-0000-0000-0000-000000000021', '00000000-0000-0000-0000-000000000000', 'chebet.korir@nipanze-ke.test', crypt('Test1234!', gen_salt('bf')), NOW(), '2026-02-13 08:09:00', '2026-02-13 08:09:00', '{"provider":"email","providers":["email"]}', '{"full_name":"Chebet Korir","country_code":"KE"}', FALSE, 'authenticated', 'authenticated', '', '', '', '', '', '', '', ''),
('10000000-0000-0000-0000-000000000022', '00000000-0000-0000-0000-000000000000', 'mutua.kilonzo@nipanze-ke.test', crypt('Test1234!', gen_salt('bf')), NOW(), '2026-02-14 08:12:00', '2026-02-14 08:12:00', '{"provider":"email","providers":["email"]}', '{"full_name":"Mutua Kilonzo","country_code":"KE"}', FALSE, 'authenticated', 'authenticated', '', '', '', '', '', '', '', ''),
('10000000-0000-0000-0000-000000000023', '00000000-0000-0000-0000-000000000000', 'wambui.gathoni@nipanze-ke.test', crypt('Test1234!', gen_salt('bf')), NOW(), '2026-02-15 08:15:00', '2026-02-15 08:15:00', '{"provider":"email","providers":["email"]}', '{"full_name":"Wambui Gathoni","country_code":"KE"}', FALSE, 'authenticated', 'authenticated', '', '', '', '', '', '', '', ''),
('10000000-0000-0000-0000-000000000024', '00000000-0000-0000-0000-000000000000', 'omondi.owino@nipanze-ke.test', crypt('Test1234!', gen_salt('bf')), NOW(), '2026-02-16 08:18:00', '2026-02-16 08:18:00', '{"provider":"email","providers":["email"]}', '{"full_name":"Omondi Owino","country_code":"KE"}', FALSE, 'authenticated', 'authenticated', '', '', '', '', '', '', '', ''),
('10000000-0000-0000-0000-000000000025', '00000000-0000-0000-0000-000000000000', 'nyambura.macharia@nipanze-ke.test', crypt('Test1234!', gen_salt('bf')), NOW(), '2026-02-17 08:21:00', '2026-02-17 08:21:00', '{"provider":"email","providers":["email"]}', '{"full_name":"Nyambura Macharia","country_code":"KE"}', FALSE, 'authenticated', 'authenticated', '', '', '', '', '', '', '', ''),
('10000000-0000-0000-0000-000000000026', '00000000-0000-0000-0000-000000000000', 'otieno.mwangi@nipanze-ke.test', crypt('Test1234!', gen_salt('bf')), NOW(), '2026-02-18 08:24:00', '2026-02-18 08:24:00', '{"provider":"email","providers":["email"]}', '{"full_name":"Otieno Mwangi","country_code":"KE"}', FALSE, 'authenticated', 'authenticated', '', '', '', '', '', '', '', ''),
('10000000-0000-0000-0000-000000000027', '00000000-0000-0000-0000-000000000000', 'kiptoo.rotich@nipanze-ke.test', crypt('Test1234!', gen_salt('bf')), NOW(), '2026-02-19 08:27:00', '2026-02-19 08:27:00', '{"provider":"email","providers":["email"]}', '{"full_name":"Kiptoo Rotich","country_code":"KE"}', FALSE, 'authenticated', 'authenticated', '', '', '', '', '', '', '', ''),
('10000000-0000-0000-0000-000000000028', '00000000-0000-0000-0000-000000000000', 'wanjiku.muriithi@nipanze-ke.test', crypt('Test1234!', gen_salt('bf')), NOW(), '2026-02-20 08:30:00', '2026-02-20 08:30:00', '{"provider":"email","providers":["email"]}', '{"full_name":"Wanjiku Muriithi","country_code":"KE"}', FALSE, 'authenticated', 'authenticated', '', '', '', '', '', '', '', ''),
('10000000-0000-0000-0000-000000000029', '00000000-0000-0000-0000-000000000000', 'mburu.njuguna@nipanze-ke.test', crypt('Test1234!', gen_salt('bf')), NOW(), '2026-02-21 08:33:00', '2026-02-21 08:33:00', '{"provider":"email","providers":["email"]}', '{"full_name":"Mburu Njuguna","country_code":"KE"}', FALSE, 'authenticated', 'authenticated', '', '', '', '', '', '', '', ''),
('10000000-0000-0000-0000-000000000030', '00000000-0000-0000-0000-000000000000', 'adhiambo.onyango@nipanze-ke.test', crypt('Test1234!', gen_salt('bf')), NOW(), '2026-02-22 08:36:00', '2026-02-22 08:36:00', '{"provider":"email","providers":["email"]}', '{"full_name":"Adhiambo Onyango","country_code":"KE"}', FALSE, 'authenticated', 'authenticated', '', '', '', '', '', '', '', ''),
('10000000-0000-0000-0000-000000000031', '00000000-0000-0000-0000-000000000000', 'akinyi.otieno@nipanze-ke.test', crypt('Test1234!', gen_salt('bf')), NOW(), '2026-02-23 08:39:00', '2026-02-23 08:39:00', '{"provider":"email","providers":["email"]}', '{"full_name":"Akinyi Otieno","country_code":"KE"}', FALSE, 'authenticated', 'authenticated', '', '', '', '', '', '', '', ''),
('10000000-0000-0000-0000-000000000032', '00000000-0000-0000-0000-000000000000', 'admin.kenya.one@nipanze-ke.test', crypt('Test1234!', gen_salt('bf')), NOW(), '2026-02-24 08:42:00', '2026-02-24 08:42:00', '{"provider":"email","providers":["email"]}', '{"full_name":"Admin Kenya One","country_code":"KE"}', FALSE, 'authenticated', 'authenticated', '', '', '', '', '', '', '', ''),
('10000000-0000-0000-0000-000000000033', '00000000-0000-0000-0000-000000000000', 'admin.kenya.two@nipanze-ke.test', crypt('Test1234!', gen_salt('bf')), NOW(), '2026-02-10 08:45:00', '2026-02-10 08:45:00', '{"provider":"email","providers":["email"]}', '{"full_name":"Admin Kenya Two","country_code":"KE"}', FALSE, 'authenticated', 'authenticated', '', '', '', '', '', '', '', ''),
('10000000-0000-0000-0000-000000000034', '00000000-0000-0000-0000-000000000000', 'test.user.kenya@nipanze-ke.test', crypt('Test1234!', gen_salt('bf')), NOW(), '2026-02-11 08:48:00', '2026-02-11 08:48:00', '{"provider":"email","providers":["email"]}', '{"full_name":"Test User Kenya","country_code":"KE"}', FALSE, 'authenticated', 'authenticated', '', '', '', '', '', '', '', '')
ON CONFLICT (id) DO NOTHING;

-- Kenya: profiles (bulk upsert — sets full details regardless of whether
-- the on_auth_user_created trigger already created a bare row)
INSERT INTO public.profiles (
    id, full_name, phone, district, country, employment_type, employer_name,
    monthly_income, income_currency, phone_verified_at, account_status, is_admin, created_at
) VALUES
('10000000-0000-0000-0000-000000000018', 'Wanjiru Kamau', '+254710002466', 'Nairobi', 'KE', 'employed', 'Wanjiru Household Income', 150000, 'KES', NULL, 'active', FALSE, '2026-02-10 08:00:00'),
('10000000-0000-0000-0000-000000000019', 'Njoroge Kariuki', '+254710002603', 'Nairobi', 'KE', 'government_employee', 'Njoroge Household Income', 195000, 'KES', NULL, 'active', FALSE, '2026-02-10 08:00:00'),
('10000000-0000-0000-0000-000000000020', 'Achieng Odhiambo', '+254710002740', 'Nairobi', 'KE', 'self_employed', 'Achieng Household Income', 120000, 'KES', NULL, 'active', FALSE, '2026-02-10 08:00:00'),
('10000000-0000-0000-0000-000000000021', 'Chebet Korir', '+254710002877', 'Nairobi', 'KE', 'small_business_owner', 'Chebet Household Income', 165000, 'KES', NULL, 'active', FALSE, '2026-02-10 08:00:00'),
('10000000-0000-0000-0000-000000000022', 'Mutua Kilonzo', '+254710003014', 'Nairobi', 'KE', 'employed', 'Mutua Household Income', 135000, 'KES', NULL, 'active', FALSE, '2026-02-10 08:00:00'),
('10000000-0000-0000-0000-000000000023', 'Wambui Gathoni', '+254710003151', 'Nairobi', 'KE', 'government_employee', 'Wambui Household Income', 225000, 'KES', NULL, 'active', FALSE, '2026-02-10 08:00:00'),
('10000000-0000-0000-0000-000000000024', 'Omondi Owino', '+254710003288', 'Nairobi', 'KE', 'self_employed', 'Omondi Household Income', 105000, 'KES', NULL, 'active', FALSE, '2026-02-10 08:00:00'),
('10000000-0000-0000-0000-000000000025', 'Nyambura Macharia', '+254710003425', 'Nairobi', 'KE', 'small_business_owner', 'Nyambura Household Income', 180000, 'KES', NULL, 'active', FALSE, '2026-02-10 08:00:00'),
('10000000-0000-0000-0000-000000000026', 'Otieno Mwangi', '+254720003926', 'Nairobi', 'KE', 'business_owner', 'Otieno Capital Partners', 700000, 'KES', '2026-02-10 09:00:00', 'active', FALSE, '2026-02-10 08:05:00'),
('10000000-0000-0000-0000-000000000027', 'Kiptoo Rotich', '+254720004077', 'Nairobi', 'KE', 'business_owner', 'Kiptoo Capital Partners', 420000, 'KES', '2026-02-10 09:00:00', 'active', FALSE, '2026-02-10 08:05:00'),
('10000000-0000-0000-0000-000000000028', 'Wanjiku Muriithi', '+254720004228', 'Nairobi', 'KE', 'business_owner', 'Wanjiku Capital Partners', 1540000, 'KES', '2026-02-10 09:00:00', 'active', FALSE, '2026-02-10 08:05:00'),
('10000000-0000-0000-0000-000000000029', 'Mburu Njuguna', '+254720004379', 'Nairobi', 'KE', 'business_owner', 'Mburu Capital Partners', 560000, 'KES', '2026-02-10 09:00:00', 'active', FALSE, '2026-02-10 08:05:00'),
('10000000-0000-0000-0000-000000000030', 'Adhiambo Onyango', '+254720004530', 'Nairobi', 'KE', 'business_owner', 'Adhiambo Capital Partners', 1750000, 'KES', '2026-02-10 09:00:00', 'active', FALSE, '2026-02-10 08:05:00'),
('10000000-0000-0000-0000-000000000031', 'Akinyi Otieno', '+25473000000', 'Nairobi', 'KE', 'employed', 'Local Employer Ltd', 135000, 'KES', NULL, 'pending_verification', FALSE, '2026-02-10 08:10:00'),
('10000000-0000-0000-0000-000000000032', 'Admin Kenya One', '+254700000000', 'Nairobi', 'KE', NULL, NULL, NULL, 'KES', NULL, 'active', TRUE, '2026-01-01 08:00:00'),
('10000000-0000-0000-0000-000000000033', 'Admin Kenya Two', '+254700000001', 'Nairobi', 'KE', NULL, NULL, NULL, 'KES', NULL, 'active', TRUE, '2026-01-01 08:00:00'),
('10000000-0000-0000-0000-000000000034', 'Test User Kenya', '+254799999999', 'Nairobi', 'KE', NULL, NULL, NULL, 'KES', NULL, 'active', FALSE, '2026-02-10 08:15:00')
ON CONFLICT (id) DO UPDATE SET
    full_name = EXCLUDED.full_name, phone = EXCLUDED.phone, district = EXCLUDED.district,
    country = EXCLUDED.country, employment_type = EXCLUDED.employment_type,
    employer_name = EXCLUDED.employer_name, monthly_income = EXCLUDED.monthly_income,
    income_currency = EXCLUDED.income_currency, phone_verified_at = EXCLUDED.phone_verified_at,
    account_status = EXCLUDED.account_status, is_admin = EXCLUDED.is_admin;

-- Kenya: subscriptions (borrowers/pending/admins/test stay free; lenders upgraded)
INSERT INTO public.subscriptions (user_id, plan, status, amount_minor_units, started_at, expires_at, auto_renew) VALUES
('10000000-0000-0000-0000-000000000018', 'free', 'active', 0, '2026-02-10 08:00:00', NULL, TRUE),
('10000000-0000-0000-0000-000000000019', 'free', 'active', 0, '2026-02-10 08:00:00', NULL, TRUE),
('10000000-0000-0000-0000-000000000020', 'free', 'active', 0, '2026-02-10 08:00:00', NULL, TRUE),
('10000000-0000-0000-0000-000000000021', 'free', 'active', 0, '2026-02-10 08:00:00', NULL, TRUE),
('10000000-0000-0000-0000-000000000022', 'free', 'active', 0, '2026-02-10 08:00:00', NULL, TRUE),
('10000000-0000-0000-0000-000000000023', 'free', 'active', 0, '2026-02-10 08:00:00', NULL, TRUE),
('10000000-0000-0000-0000-000000000024', 'free', 'active', 0, '2026-02-10 08:00:00', NULL, TRUE),
('10000000-0000-0000-0000-000000000025', 'free', 'active', 0, '2026-02-10 08:00:00', NULL, TRUE),
('10000000-0000-0000-0000-000000000026', 'lender', 'active', 1633, '2026-02-10 09:00:00', '2028-02-10 09:00:00', TRUE),
('10000000-0000-0000-0000-000000000027', 'lender', 'active', 1633, '2026-02-10 09:00:00', '2028-02-10 09:00:00', TRUE),
('10000000-0000-0000-0000-000000000028', 'pro', 'active', 7000, '2026-02-10 09:00:00', '2028-02-10 09:00:00', TRUE),
('10000000-0000-0000-0000-000000000029', 'lender', 'active', 1633, '2026-02-10 09:00:00', '2028-02-10 09:00:00', TRUE),
('10000000-0000-0000-0000-000000000030', 'pro', 'active', 7000, '2026-02-10 09:00:00', '2028-02-10 09:00:00', TRUE),
('10000000-0000-0000-0000-000000000031', 'free', 'active', 0, '2026-02-10 08:10:00', NULL, TRUE),
('10000000-0000-0000-0000-000000000032', 'free', 'active', 0, '2024-01-01 08:00:00', NULL, TRUE),
('10000000-0000-0000-0000-000000000033', 'free', 'active', 0, '2024-01-01 08:00:00', NULL, TRUE),
('10000000-0000-0000-0000-000000000034', 'free', 'active', 0, '2026-02-10 08:15:00', NULL, TRUE)
ON CONFLICT (user_id) DO UPDATE SET
    plan = EXCLUDED.plan, status = EXCLUDED.status, amount_minor_units = EXCLUDED.amount_minor_units,
    started_at = EXCLUDED.started_at, expires_at = EXCLUDED.expires_at, auto_renew = EXCLUDED.auto_renew;

-- ============================================
-- COUNTRY: TANZANIA (TZ) — 17 users, mirrors Uganda's structure
-- 8 active borrowers, 5 lenders (lender/pro), 1 pending-verification borrower,
-- 2 admins, 1 test user.
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
('10000000-0000-0000-0000-000000000035', '00000000-0000-0000-0000-000000000000', 'amina.juma@nipanze-tz.test', crypt('Test1234!', gen_salt('bf')), NOW(), '2026-02-10 08:00:00', '2026-02-10 08:00:00', '{"provider":"email","providers":["email"]}', '{"full_name":"Amina Juma","country_code":"TZ"}', FALSE, 'authenticated', 'authenticated', '', '', '', '', '', '', '', ''),
('10000000-0000-0000-0000-000000000036', '00000000-0000-0000-0000-000000000000', 'mwakalinga.ndege@nipanze-tz.test', crypt('Test1234!', gen_salt('bf')), NOW(), '2026-02-11 08:03:00', '2026-02-11 08:03:00', '{"provider":"email","providers":["email"]}', '{"full_name":"Mwakalinga Ndege","country_code":"TZ"}', FALSE, 'authenticated', 'authenticated', '', '', '', '', '', '', '', ''),
('10000000-0000-0000-0000-000000000037', '00000000-0000-0000-0000-000000000000', 'hassan.mbwana@nipanze-tz.test', crypt('Test1234!', gen_salt('bf')), NOW(), '2026-02-12 08:06:00', '2026-02-12 08:06:00', '{"provider":"email","providers":["email"]}', '{"full_name":"Hassan Mbwana","country_code":"TZ"}', FALSE, 'authenticated', 'authenticated', '', '', '', '', '', '', '', ''),
('10000000-0000-0000-0000-000000000038', '00000000-0000-0000-0000-000000000000', 'fatuma.kisoma@nipanze-tz.test', crypt('Test1234!', gen_salt('bf')), NOW(), '2026-02-13 08:09:00', '2026-02-13 08:09:00', '{"provider":"email","providers":["email"]}', '{"full_name":"Fatuma Kisoma","country_code":"TZ"}', FALSE, 'authenticated', 'authenticated', '', '', '', '', '', '', '', ''),
('10000000-0000-0000-0000-000000000039', '00000000-0000-0000-0000-000000000000', 'juma.mwakisu@nipanze-tz.test', crypt('Test1234!', gen_salt('bf')), NOW(), '2026-02-14 08:12:00', '2026-02-14 08:12:00', '{"provider":"email","providers":["email"]}', '{"full_name":"Juma Mwakisu","country_code":"TZ"}', FALSE, 'authenticated', 'authenticated', '', '', '', '', '', '', '', ''),
('10000000-0000-0000-0000-000000000040', '00000000-0000-0000-0000-000000000000', 'neema.kileo@nipanze-tz.test', crypt('Test1234!', gen_salt('bf')), NOW(), '2026-02-15 08:15:00', '2026-02-15 08:15:00', '{"provider":"email","providers":["email"]}', '{"full_name":"Neema Kileo","country_code":"TZ"}', FALSE, 'authenticated', 'authenticated', '', '', '', '', '', '', '', ''),
('10000000-0000-0000-0000-000000000041', '00000000-0000-0000-0000-000000000000', 'salum.ally@nipanze-tz.test', crypt('Test1234!', gen_salt('bf')), NOW(), '2026-02-16 08:18:00', '2026-02-16 08:18:00', '{"provider":"email","providers":["email"]}', '{"full_name":"Salum Ally","country_code":"TZ"}', FALSE, 'authenticated', 'authenticated', '', '', '', '', '', '', '', ''),
('10000000-0000-0000-0000-000000000042', '00000000-0000-0000-0000-000000000000', 'zainab.rashidi@nipanze-tz.test', crypt('Test1234!', gen_salt('bf')), NOW(), '2026-02-17 08:21:00', '2026-02-17 08:21:00', '{"provider":"email","providers":["email"]}', '{"full_name":"Zainab Rashidi","country_code":"TZ"}', FALSE, 'authenticated', 'authenticated', '', '', '', '', '', '', '', ''),
('10000000-0000-0000-0000-000000000043', '00000000-0000-0000-0000-000000000000', 'baraka.mushi@nipanze-tz.test', crypt('Test1234!', gen_salt('bf')), NOW(), '2026-02-18 08:24:00', '2026-02-18 08:24:00', '{"provider":"email","providers":["email"]}', '{"full_name":"Baraka Mushi","country_code":"TZ"}', FALSE, 'authenticated', 'authenticated', '', '', '', '', '', '', '', ''),
('10000000-0000-0000-0000-000000000044', '00000000-0000-0000-0000-000000000000', 'godfrey.massawe@nipanze-tz.test', crypt('Test1234!', gen_salt('bf')), NOW(), '2026-02-19 08:27:00', '2026-02-19 08:27:00', '{"provider":"email","providers":["email"]}', '{"full_name":"Godfrey Massawe","country_code":"TZ"}', FALSE, 'authenticated', 'authenticated', '', '', '', '', '', '', '', ''),
('10000000-0000-0000-0000-000000000045', '00000000-0000-0000-0000-000000000000', 'rehema.chuma@nipanze-tz.test', crypt('Test1234!', gen_salt('bf')), NOW(), '2026-02-20 08:30:00', '2026-02-20 08:30:00', '{"provider":"email","providers":["email"]}', '{"full_name":"Rehema Chuma","country_code":"TZ"}', FALSE, 'authenticated', 'authenticated', '', '', '', '', '', '', '', ''),
('10000000-0000-0000-0000-000000000046', '00000000-0000-0000-0000-000000000000', 'emmanuel.sanga@nipanze-tz.test', crypt('Test1234!', gen_salt('bf')), NOW(), '2026-02-21 08:33:00', '2026-02-21 08:33:00', '{"provider":"email","providers":["email"]}', '{"full_name":"Emmanuel Sanga","country_code":"TZ"}', FALSE, 'authenticated', 'authenticated', '', '', '', '', '', '', '', ''),
('10000000-0000-0000-0000-000000000047', '00000000-0000-0000-0000-000000000000', 'halima.mnyapala@nipanze-tz.test', crypt('Test1234!', gen_salt('bf')), NOW(), '2026-02-22 08:36:00', '2026-02-22 08:36:00', '{"provider":"email","providers":["email"]}', '{"full_name":"Halima Mnyapala","country_code":"TZ"}', FALSE, 'authenticated', 'authenticated', '', '', '', '', '', '', '', ''),
('10000000-0000-0000-0000-000000000048', '00000000-0000-0000-0000-000000000000', 'fadhili.mrema@nipanze-tz.test', crypt('Test1234!', gen_salt('bf')), NOW(), '2026-02-23 08:39:00', '2026-02-23 08:39:00', '{"provider":"email","providers":["email"]}', '{"full_name":"Fadhili Mrema","country_code":"TZ"}', FALSE, 'authenticated', 'authenticated', '', '', '', '', '', '', '', ''),
('10000000-0000-0000-0000-000000000049', '00000000-0000-0000-0000-000000000000', 'admin.tanzania.one@nipanze-tz.test', crypt('Test1234!', gen_salt('bf')), NOW(), '2026-02-24 08:42:00', '2026-02-24 08:42:00', '{"provider":"email","providers":["email"]}', '{"full_name":"Admin Tanzania One","country_code":"TZ"}', FALSE, 'authenticated', 'authenticated', '', '', '', '', '', '', '', ''),
('10000000-0000-0000-0000-000000000050', '00000000-0000-0000-0000-000000000000', 'admin.tanzania.two@nipanze-tz.test', crypt('Test1234!', gen_salt('bf')), NOW(), '2026-02-10 08:45:00', '2026-02-10 08:45:00', '{"provider":"email","providers":["email"]}', '{"full_name":"Admin Tanzania Two","country_code":"TZ"}', FALSE, 'authenticated', 'authenticated', '', '', '', '', '', '', '', ''),
('10000000-0000-0000-0000-000000000051', '00000000-0000-0000-0000-000000000000', 'test.user.tanzania@nipanze-tz.test', crypt('Test1234!', gen_salt('bf')), NOW(), '2026-02-11 08:48:00', '2026-02-11 08:48:00', '{"provider":"email","providers":["email"]}', '{"full_name":"Test User Tanzania","country_code":"TZ"}', FALSE, 'authenticated', 'authenticated', '', '', '', '', '', '', '', '')
ON CONFLICT (id) DO NOTHING;

-- Tanzania: profiles (bulk upsert — sets full details regardless of whether
-- the on_auth_user_created trigger already created a bare row)
INSERT INTO public.profiles (
    id, full_name, phone, district, country, employment_type, employer_name,
    monthly_income, income_currency, phone_verified_at, account_status, is_admin, created_at
) VALUES
('10000000-0000-0000-0000-000000000035', 'Amina Juma', '+255710004795', 'Dar es Salaam', 'TZ', 'employed', 'Amina Household Income', 1800000, 'TZS', NULL, 'active', FALSE, '2026-02-10 08:00:00'),
('10000000-0000-0000-0000-000000000036', 'Mwakalinga Ndege', '+255710004932', 'Dar es Salaam', 'TZ', 'government_employee', 'Mwakalinga Household Income', 2340000, 'TZS', NULL, 'active', FALSE, '2026-02-10 08:00:00'),
('10000000-0000-0000-0000-000000000037', 'Hassan Mbwana', '+255710005069', 'Dar es Salaam', 'TZ', 'self_employed', 'Hassan Household Income', 1440000, 'TZS', NULL, 'active', FALSE, '2026-02-10 08:00:00'),
('10000000-0000-0000-0000-000000000038', 'Fatuma Kisoma', '+255710005206', 'Dar es Salaam', 'TZ', 'small_business_owner', 'Fatuma Household Income', 1980000, 'TZS', NULL, 'active', FALSE, '2026-02-10 08:00:00'),
('10000000-0000-0000-0000-000000000039', 'Juma Mwakisu', '+255710005343', 'Dar es Salaam', 'TZ', 'employed', 'Juma Household Income', 1620000, 'TZS', NULL, 'active', FALSE, '2026-02-10 08:00:00'),
('10000000-0000-0000-0000-000000000040', 'Neema Kileo', '+255710005480', 'Dar es Salaam', 'TZ', 'government_employee', 'Neema Household Income', 2700000, 'TZS', NULL, 'active', FALSE, '2026-02-10 08:00:00'),
('10000000-0000-0000-0000-000000000041', 'Salum Ally', '+255710005617', 'Dar es Salaam', 'TZ', 'self_employed', 'Salum Household Income', 1260000, 'TZS', NULL, 'active', FALSE, '2026-02-10 08:00:00'),
('10000000-0000-0000-0000-000000000042', 'Zainab Rashidi', '+255710005754', 'Dar es Salaam', 'TZ', 'small_business_owner', 'Zainab Household Income', 2160000, 'TZS', NULL, 'active', FALSE, '2026-02-10 08:00:00'),
('10000000-0000-0000-0000-000000000043', 'Baraka Mushi', '+255720006493', 'Dar es Salaam', 'TZ', 'business_owner', 'Baraka Capital Partners', 8500000, 'TZS', '2026-02-10 09:00:00', 'active', FALSE, '2026-02-10 08:05:00'),
('10000000-0000-0000-0000-000000000044', 'Godfrey Massawe', '+255720006644', 'Dar es Salaam', 'TZ', 'business_owner', 'Godfrey Capital Partners', 5100000, 'TZS', '2026-02-10 09:00:00', 'active', FALSE, '2026-02-10 08:05:00'),
('10000000-0000-0000-0000-000000000045', 'Rehema Chuma', '+255720006795', 'Dar es Salaam', 'TZ', 'business_owner', 'Rehema Capital Partners', 18700000, 'TZS', '2026-02-10 09:00:00', 'active', FALSE, '2026-02-10 08:05:00'),
('10000000-0000-0000-0000-000000000046', 'Emmanuel Sanga', '+255720006946', 'Dar es Salaam', 'TZ', 'business_owner', 'Emmanuel Capital Partners', 6800000, 'TZS', '2026-02-10 09:00:00', 'active', FALSE, '2026-02-10 08:05:00'),
('10000000-0000-0000-0000-000000000047', 'Halima Mnyapala', '+255720007097', 'Dar es Salaam', 'TZ', 'business_owner', 'Halima Capital Partners', 21250000, 'TZS', '2026-02-10 09:00:00', 'active', FALSE, '2026-02-10 08:05:00'),
('10000000-0000-0000-0000-000000000048', 'Fadhili Mrema', '+25573000000', 'Dar es Salaam', 'TZ', 'employed', 'Local Employer Ltd', 1620000, 'TZS', NULL, 'pending_verification', FALSE, '2026-02-10 08:10:00'),
('10000000-0000-0000-0000-000000000049', 'Admin Tanzania One', '+255700000000', 'Dar es Salaam', 'TZ', NULL, NULL, NULL, 'TZS', NULL, 'active', TRUE, '2026-01-01 08:00:00'),
('10000000-0000-0000-0000-000000000050', 'Admin Tanzania Two', '+255700000001', 'Dar es Salaam', 'TZ', NULL, NULL, NULL, 'TZS', NULL, 'active', TRUE, '2026-01-01 08:00:00'),
('10000000-0000-0000-0000-000000000051', 'Test User Tanzania', '+255799999999', 'Dar es Salaam', 'TZ', NULL, NULL, NULL, 'TZS', NULL, 'active', FALSE, '2026-02-10 08:15:00')
ON CONFLICT (id) DO UPDATE SET
    full_name = EXCLUDED.full_name, phone = EXCLUDED.phone, district = EXCLUDED.district,
    country = EXCLUDED.country, employment_type = EXCLUDED.employment_type,
    employer_name = EXCLUDED.employer_name, monthly_income = EXCLUDED.monthly_income,
    income_currency = EXCLUDED.income_currency, phone_verified_at = EXCLUDED.phone_verified_at,
    account_status = EXCLUDED.account_status, is_admin = EXCLUDED.is_admin;

-- Tanzania: subscriptions (borrowers/pending/admins/test stay free; lenders upgraded)
INSERT INTO public.subscriptions (user_id, plan, status, amount_minor_units, started_at, expires_at, auto_renew) VALUES
('10000000-0000-0000-0000-000000000035', 'free', 'active', 0, '2026-02-10 08:00:00', NULL, TRUE),
('10000000-0000-0000-0000-000000000036', 'free', 'active', 0, '2026-02-10 08:00:00', NULL, TRUE),
('10000000-0000-0000-0000-000000000037', 'free', 'active', 0, '2026-02-10 08:00:00', NULL, TRUE),
('10000000-0000-0000-0000-000000000038', 'free', 'active', 0, '2026-02-10 08:00:00', NULL, TRUE),
('10000000-0000-0000-0000-000000000039', 'free', 'active', 0, '2026-02-10 08:00:00', NULL, TRUE),
('10000000-0000-0000-0000-000000000040', 'free', 'active', 0, '2026-02-10 08:00:00', NULL, TRUE),
('10000000-0000-0000-0000-000000000041', 'free', 'active', 0, '2026-02-10 08:00:00', NULL, TRUE),
('10000000-0000-0000-0000-000000000042', 'free', 'active', 0, '2026-02-10 08:00:00', NULL, TRUE),
('10000000-0000-0000-0000-000000000043', 'lender', 'active', 19833, '2026-02-10 09:00:00', '2028-02-10 09:00:00', TRUE),
('10000000-0000-0000-0000-000000000044', 'lender', 'active', 19833, '2026-02-10 09:00:00', '2028-02-10 09:00:00', TRUE),
('10000000-0000-0000-0000-000000000045', 'pro', 'active', 85000, '2026-02-10 09:00:00', '2028-02-10 09:00:00', TRUE),
('10000000-0000-0000-0000-000000000046', 'lender', 'active', 19833, '2026-02-10 09:00:00', '2028-02-10 09:00:00', TRUE),
('10000000-0000-0000-0000-000000000047', 'pro', 'active', 85000, '2026-02-10 09:00:00', '2028-02-10 09:00:00', TRUE),
('10000000-0000-0000-0000-000000000048', 'free', 'active', 0, '2026-02-10 08:10:00', NULL, TRUE),
('10000000-0000-0000-0000-000000000049', 'free', 'active', 0, '2024-01-01 08:00:00', NULL, TRUE),
('10000000-0000-0000-0000-000000000050', 'free', 'active', 0, '2024-01-01 08:00:00', NULL, TRUE),
('10000000-0000-0000-0000-000000000051', 'free', 'active', 0, '2026-02-10 08:15:00', NULL, TRUE)
ON CONFLICT (user_id) DO UPDATE SET
    plan = EXCLUDED.plan, status = EXCLUDED.status, amount_minor_units = EXCLUDED.amount_minor_units,
    started_at = EXCLUDED.started_at, expires_at = EXCLUDED.expires_at, auto_renew = EXCLUDED.auto_renew;

-- ============================================
-- COUNTRY: RWANDA (RW) — 17 users, mirrors Uganda's structure
-- 8 active borrowers, 5 lenders (lender/pro), 1 pending-verification borrower,
-- 2 admins, 1 test user.
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
('10000000-0000-0000-0000-000000000052', '00000000-0000-0000-0000-000000000000', 'uwase.claudine@nipanze-rw.test', crypt('Test1234!', gen_salt('bf')), NOW(), '2026-02-10 08:00:00', '2026-02-10 08:00:00', '{"provider":"email","providers":["email"]}', '{"full_name":"Uwase Claudine","country_code":"RW"}', FALSE, 'authenticated', 'authenticated', '', '', '', '', '', '', '', ''),
('10000000-0000-0000-0000-000000000053', '00000000-0000-0000-0000-000000000000', 'mugisha.emmanuel@nipanze-rw.test', crypt('Test1234!', gen_salt('bf')), NOW(), '2026-02-11 08:03:00', '2026-02-11 08:03:00', '{"provider":"email","providers":["email"]}', '{"full_name":"Mugisha Emmanuel","country_code":"RW"}', FALSE, 'authenticated', 'authenticated', '', '', '', '', '', '', '', ''),
('10000000-0000-0000-0000-000000000054', '00000000-0000-0000-0000-000000000000', 'ingabire.solange@nipanze-rw.test', crypt('Test1234!', gen_salt('bf')), NOW(), '2026-02-12 08:06:00', '2026-02-12 08:06:00', '{"provider":"email","providers":["email"]}', '{"full_name":"Ingabire Solange","country_code":"RW"}', FALSE, 'authenticated', 'authenticated', '', '', '', '', '', '', '', ''),
('10000000-0000-0000-0000-000000000055', '00000000-0000-0000-0000-000000000000', 'habimana.eric@nipanze-rw.test', crypt('Test1234!', gen_salt('bf')), NOW(), '2026-02-13 08:09:00', '2026-02-13 08:09:00', '{"provider":"email","providers":["email"]}', '{"full_name":"Habimana Eric","country_code":"RW"}', FALSE, 'authenticated', 'authenticated', '', '', '', '', '', '', '', ''),
('10000000-0000-0000-0000-000000000056', '00000000-0000-0000-0000-000000000000', 'uwimana.alice@nipanze-rw.test', crypt('Test1234!', gen_salt('bf')), NOW(), '2026-02-14 08:12:00', '2026-02-14 08:12:00', '{"provider":"email","providers":["email"]}', '{"full_name":"Uwimana Alice","country_code":"RW"}', FALSE, 'authenticated', 'authenticated', '', '', '', '', '', '', '', ''),
('10000000-0000-0000-0000-000000000057', '00000000-0000-0000-0000-000000000000', 'nsengimana.jean@nipanze-rw.test', crypt('Test1234!', gen_salt('bf')), NOW(), '2026-02-15 08:15:00', '2026-02-15 08:15:00', '{"provider":"email","providers":["email"]}', '{"full_name":"Nsengimana Jean","country_code":"RW"}', FALSE, 'authenticated', 'authenticated', '', '', '', '', '', '', '', ''),
('10000000-0000-0000-0000-000000000058', '00000000-0000-0000-0000-000000000000', 'mukamana.diane@nipanze-rw.test', crypt('Test1234!', gen_salt('bf')), NOW(), '2026-02-16 08:18:00', '2026-02-16 08:18:00', '{"provider":"email","providers":["email"]}', '{"full_name":"Mukamana Diane","country_code":"RW"}', FALSE, 'authenticated', 'authenticated', '', '', '', '', '', '', '', ''),
('10000000-0000-0000-0000-000000000059', '00000000-0000-0000-0000-000000000000', 'bizimana.patrick@nipanze-rw.test', crypt('Test1234!', gen_salt('bf')), NOW(), '2026-02-17 08:21:00', '2026-02-17 08:21:00', '{"provider":"email","providers":["email"]}', '{"full_name":"Bizimana Patrick","country_code":"RW"}', FALSE, 'authenticated', 'authenticated', '', '', '', '', '', '', '', ''),
('10000000-0000-0000-0000-000000000060', '00000000-0000-0000-0000-000000000000', 'rugamba.innocent@nipanze-rw.test', crypt('Test1234!', gen_salt('bf')), NOW(), '2026-02-18 08:24:00', '2026-02-18 08:24:00', '{"provider":"email","providers":["email"]}', '{"full_name":"Rugamba Innocent","country_code":"RW"}', FALSE, 'authenticated', 'authenticated', '', '', '', '', '', '', '', ''),
('10000000-0000-0000-0000-000000000061', '00000000-0000-0000-0000-000000000000', 'mutesi.christine@nipanze-rw.test', crypt('Test1234!', gen_salt('bf')), NOW(), '2026-02-19 08:27:00', '2026-02-19 08:27:00', '{"provider":"email","providers":["email"]}', '{"full_name":"Mutesi Christine","country_code":"RW"}', FALSE, 'authenticated', 'authenticated', '', '', '', '', '', '', '', ''),
('10000000-0000-0000-0000-000000000062', '00000000-0000-0000-0000-000000000000', 'karangwa.vincent@nipanze-rw.test', crypt('Test1234!', gen_salt('bf')), NOW(), '2026-02-20 08:30:00', '2026-02-20 08:30:00', '{"provider":"email","providers":["email"]}', '{"full_name":"Karangwa Vincent","country_code":"RW"}', FALSE, 'authenticated', 'authenticated', '', '', '', '', '', '', '', ''),
('10000000-0000-0000-0000-000000000063', '00000000-0000-0000-0000-000000000000', 'nyiraneza.josiane@nipanze-rw.test', crypt('Test1234!', gen_salt('bf')), NOW(), '2026-02-21 08:33:00', '2026-02-21 08:33:00', '{"provider":"email","providers":["email"]}', '{"full_name":"Nyiraneza Josiane","country_code":"RW"}', FALSE, 'authenticated', 'authenticated', '', '', '', '', '', '', '', ''),
('10000000-0000-0000-0000-000000000064', '00000000-0000-0000-0000-000000000000', 'twagirayezu.faustin@nipanze-rw.test', crypt('Test1234!', gen_salt('bf')), NOW(), '2026-02-22 08:36:00', '2026-02-22 08:36:00', '{"provider":"email","providers":["email"]}', '{"full_name":"Twagirayezu Faustin","country_code":"RW"}', FALSE, 'authenticated', 'authenticated', '', '', '', '', '', '', '', ''),
('10000000-0000-0000-0000-000000000065', '00000000-0000-0000-0000-000000000000', 'ishimwe.sandrine@nipanze-rw.test', crypt('Test1234!', gen_salt('bf')), NOW(), '2026-02-23 08:39:00', '2026-02-23 08:39:00', '{"provider":"email","providers":["email"]}', '{"full_name":"Ishimwe Sandrine","country_code":"RW"}', FALSE, 'authenticated', 'authenticated', '', '', '', '', '', '', '', ''),
('10000000-0000-0000-0000-000000000066', '00000000-0000-0000-0000-000000000000', 'admin.rwanda.one@nipanze-rw.test', crypt('Test1234!', gen_salt('bf')), NOW(), '2026-02-24 08:42:00', '2026-02-24 08:42:00', '{"provider":"email","providers":["email"]}', '{"full_name":"Admin Rwanda One","country_code":"RW"}', FALSE, 'authenticated', 'authenticated', '', '', '', '', '', '', '', ''),
('10000000-0000-0000-0000-000000000067', '00000000-0000-0000-0000-000000000000', 'admin.rwanda.two@nipanze-rw.test', crypt('Test1234!', gen_salt('bf')), NOW(), '2026-02-10 08:45:00', '2026-02-10 08:45:00', '{"provider":"email","providers":["email"]}', '{"full_name":"Admin Rwanda Two","country_code":"RW"}', FALSE, 'authenticated', 'authenticated', '', '', '', '', '', '', '', ''),
('10000000-0000-0000-0000-000000000068', '00000000-0000-0000-0000-000000000000', 'test.user.rwanda@nipanze-rw.test', crypt('Test1234!', gen_salt('bf')), NOW(), '2026-02-11 08:48:00', '2026-02-11 08:48:00', '{"provider":"email","providers":["email"]}', '{"full_name":"Test User Rwanda","country_code":"RW"}', FALSE, 'authenticated', 'authenticated', '', '', '', '', '', '', '', '')
ON CONFLICT (id) DO NOTHING;

-- Rwanda: profiles (bulk upsert — sets full details regardless of whether
-- the on_auth_user_created trigger already created a bare row)
INSERT INTO public.profiles (
    id, full_name, phone, district, country, employment_type, employer_name,
    monthly_income, income_currency, phone_verified_at, account_status, is_admin, created_at
) VALUES
('10000000-0000-0000-0000-000000000052', 'Uwase Claudine', '+250710007124', 'Kigali', 'RW', 'employed', 'Uwase Household Income', 750000, 'RWF', NULL, 'active', FALSE, '2026-02-10 08:00:00'),
('10000000-0000-0000-0000-000000000053', 'Mugisha Emmanuel', '+250710007261', 'Kigali', 'RW', 'government_employee', 'Mugisha Household Income', 975000, 'RWF', NULL, 'active', FALSE, '2026-02-10 08:00:00'),
('10000000-0000-0000-0000-000000000054', 'Ingabire Solange', '+250710007398', 'Kigali', 'RW', 'self_employed', 'Ingabire Household Income', 600000, 'RWF', NULL, 'active', FALSE, '2026-02-10 08:00:00'),
('10000000-0000-0000-0000-000000000055', 'Habimana Eric', '+250710007535', 'Kigali', 'RW', 'small_business_owner', 'Habimana Household Income', 825000, 'RWF', NULL, 'active', FALSE, '2026-02-10 08:00:00'),
('10000000-0000-0000-0000-000000000056', 'Uwimana Alice', '+250710007672', 'Kigali', 'RW', 'employed', 'Uwimana Household Income', 675000, 'RWF', NULL, 'active', FALSE, '2026-02-10 08:00:00'),
('10000000-0000-0000-0000-000000000057', 'Nsengimana Jean', '+250710007809', 'Kigali', 'RW', 'government_employee', 'Nsengimana Household Income', 1125000, 'RWF', NULL, 'active', FALSE, '2026-02-10 08:00:00'),
('10000000-0000-0000-0000-000000000058', 'Mukamana Diane', '+250710007946', 'Kigali', 'RW', 'self_employed', 'Mukamana Household Income', 525000, 'RWF', NULL, 'active', FALSE, '2026-02-10 08:00:00'),
('10000000-0000-0000-0000-000000000059', 'Bizimana Patrick', '+250710008083', 'Kigali', 'RW', 'small_business_owner', 'Bizimana Household Income', 900000, 'RWF', NULL, 'active', FALSE, '2026-02-10 08:00:00'),
('10000000-0000-0000-0000-000000000060', 'Rugamba Innocent', '+250720009060', 'Kigali', 'RW', 'business_owner', 'Rugamba Capital Partners', 3800000, 'RWF', '2026-02-10 09:00:00', 'active', FALSE, '2026-02-10 08:05:00'),
('10000000-0000-0000-0000-000000000061', 'Mutesi Christine', '+250720009211', 'Kigali', 'RW', 'business_owner', 'Mutesi Capital Partners', 2280000, 'RWF', '2026-02-10 09:00:00', 'active', FALSE, '2026-02-10 08:05:00'),
('10000000-0000-0000-0000-000000000062', 'Karangwa Vincent', '+250720009362', 'Kigali', 'RW', 'business_owner', 'Karangwa Capital Partners', 8360000, 'RWF', '2026-02-10 09:00:00', 'active', FALSE, '2026-02-10 08:05:00'),
('10000000-0000-0000-0000-000000000063', 'Nyiraneza Josiane', '+250720009513', 'Kigali', 'RW', 'business_owner', 'Nyiraneza Capital Partners', 3040000, 'RWF', '2026-02-10 09:00:00', 'active', FALSE, '2026-02-10 08:05:00'),
('10000000-0000-0000-0000-000000000064', 'Twagirayezu Faustin', '+250720009664', 'Kigali', 'RW', 'business_owner', 'Twagirayezu Capital Partners', 9500000, 'RWF', '2026-02-10 09:00:00', 'active', FALSE, '2026-02-10 08:05:00'),
('10000000-0000-0000-0000-000000000065', 'Ishimwe Sandrine', '+25073000000', 'Kigali', 'RW', 'employed', 'Local Employer Ltd', 675000, 'RWF', NULL, 'pending_verification', FALSE, '2026-02-10 08:10:00'),
('10000000-0000-0000-0000-000000000066', 'Admin Rwanda One', '+250700000000', 'Kigali', 'RW', NULL, NULL, NULL, 'RWF', NULL, 'active', TRUE, '2026-01-01 08:00:00'),
('10000000-0000-0000-0000-000000000067', 'Admin Rwanda Two', '+250700000001', 'Kigali', 'RW', NULL, NULL, NULL, 'RWF', NULL, 'active', TRUE, '2026-01-01 08:00:00'),
('10000000-0000-0000-0000-000000000068', 'Test User Rwanda', '+250799999999', 'Kigali', 'RW', NULL, NULL, NULL, 'RWF', NULL, 'active', FALSE, '2026-02-10 08:15:00')
ON CONFLICT (id) DO UPDATE SET
    full_name = EXCLUDED.full_name, phone = EXCLUDED.phone, district = EXCLUDED.district,
    country = EXCLUDED.country, employment_type = EXCLUDED.employment_type,
    employer_name = EXCLUDED.employer_name, monthly_income = EXCLUDED.monthly_income,
    income_currency = EXCLUDED.income_currency, phone_verified_at = EXCLUDED.phone_verified_at,
    account_status = EXCLUDED.account_status, is_admin = EXCLUDED.is_admin;

-- Rwanda: subscriptions (borrowers/pending/admins/test stay free; lenders upgraded)
INSERT INTO public.subscriptions (user_id, plan, status, amount_minor_units, started_at, expires_at, auto_renew) VALUES
('10000000-0000-0000-0000-000000000052', 'free', 'active', 0, '2026-02-10 08:00:00', NULL, TRUE),
('10000000-0000-0000-0000-000000000053', 'free', 'active', 0, '2026-02-10 08:00:00', NULL, TRUE),
('10000000-0000-0000-0000-000000000054', 'free', 'active', 0, '2026-02-10 08:00:00', NULL, TRUE),
('10000000-0000-0000-0000-000000000055', 'free', 'active', 0, '2026-02-10 08:00:00', NULL, TRUE),
('10000000-0000-0000-0000-000000000056', 'free', 'active', 0, '2026-02-10 08:00:00', NULL, TRUE),
('10000000-0000-0000-0000-000000000057', 'free', 'active', 0, '2026-02-10 08:00:00', NULL, TRUE),
('10000000-0000-0000-0000-000000000058', 'free', 'active', 0, '2026-02-10 08:00:00', NULL, TRUE),
('10000000-0000-0000-0000-000000000059', 'free', 'active', 0, '2026-02-10 08:00:00', NULL, TRUE),
('10000000-0000-0000-0000-000000000060', 'lender', 'active', 8866, '2026-02-10 09:00:00', '2028-02-10 09:00:00', TRUE),
('10000000-0000-0000-0000-000000000061', 'lender', 'active', 8866, '2026-02-10 09:00:00', '2028-02-10 09:00:00', TRUE),
('10000000-0000-0000-0000-000000000062', 'pro', 'active', 38000, '2026-02-10 09:00:00', '2028-02-10 09:00:00', TRUE),
('10000000-0000-0000-0000-000000000063', 'lender', 'active', 8866, '2026-02-10 09:00:00', '2028-02-10 09:00:00', TRUE),
('10000000-0000-0000-0000-000000000064', 'pro', 'active', 38000, '2026-02-10 09:00:00', '2028-02-10 09:00:00', TRUE),
('10000000-0000-0000-0000-000000000065', 'free', 'active', 0, '2026-02-10 08:10:00', NULL, TRUE),
('10000000-0000-0000-0000-000000000066', 'free', 'active', 0, '2024-01-01 08:00:00', NULL, TRUE),
('10000000-0000-0000-0000-000000000067', 'free', 'active', 0, '2024-01-01 08:00:00', NULL, TRUE),
('10000000-0000-0000-0000-000000000068', 'free', 'active', 0, '2026-02-10 08:15:00', NULL, TRUE)
ON CONFLICT (user_id) DO UPDATE SET
    plan = EXCLUDED.plan, status = EXCLUDED.status, amount_minor_units = EXCLUDED.amount_minor_units,
    started_at = EXCLUDED.started_at, expires_at = EXCLUDED.expires_at, auto_renew = EXCLUDED.auto_renew;

-- ============================================
-- COUNTRY: BURUNDI (BI) — 17 users, mirrors Uganda's structure
-- 8 active borrowers, 5 lenders (lender/pro), 1 pending-verification borrower,
-- 2 admins, 1 test user.
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
('10000000-0000-0000-0000-000000000069', '00000000-0000-0000-0000-000000000000', 'ndayishimiye.aline@nipanze-bi.test', crypt('Test1234!', gen_salt('bf')), NOW(), '2026-02-10 08:00:00', '2026-02-10 08:00:00', '{"provider":"email","providers":["email"]}', '{"full_name":"Ndayishimiye Aline","country_code":"BI"}', FALSE, 'authenticated', 'authenticated', '', '', '', '', '', '', '', ''),
('10000000-0000-0000-0000-000000000070', '00000000-0000-0000-0000-000000000000', 'nkurunziza.gilbert@nipanze-bi.test', crypt('Test1234!', gen_salt('bf')), NOW(), '2026-02-11 08:03:00', '2026-02-11 08:03:00', '{"provider":"email","providers":["email"]}', '{"full_name":"Nkurunziza Gilbert","country_code":"BI"}', FALSE, 'authenticated', 'authenticated', '', '', '', '', '', '', '', ''),
('10000000-0000-0000-0000-000000000071', '00000000-0000-0000-0000-000000000000', 'niyonzima.chantal@nipanze-bi.test', crypt('Test1234!', gen_salt('bf')), NOW(), '2026-02-12 08:06:00', '2026-02-12 08:06:00', '{"provider":"email","providers":["email"]}', '{"full_name":"Niyonzima Chantal","country_code":"BI"}', FALSE, 'authenticated', 'authenticated', '', '', '', '', '', '', '', ''),
('10000000-0000-0000-0000-000000000072', '00000000-0000-0000-0000-000000000000', 'bigirimana.willy@nipanze-bi.test', crypt('Test1234!', gen_salt('bf')), NOW(), '2026-02-13 08:09:00', '2026-02-13 08:09:00', '{"provider":"email","providers":["email"]}', '{"full_name":"Bigirimana Willy","country_code":"BI"}', FALSE, 'authenticated', 'authenticated', '', '', '', '', '', '', '', ''),
('10000000-0000-0000-0000-000000000073', '00000000-0000-0000-0000-000000000000', 'nizigiyimana.solange@nipanze-bi.test', crypt('Test1234!', gen_salt('bf')), NOW(), '2026-02-14 08:12:00', '2026-02-14 08:12:00', '{"provider":"email","providers":["email"]}', '{"full_name":"Nizigiyimana Solange","country_code":"BI"}', FALSE, 'authenticated', 'authenticated', '', '', '', '', '', '', '', ''),
('10000000-0000-0000-0000-000000000074', '00000000-0000-0000-0000-000000000000', 'hakizimana.eric@nipanze-bi.test', crypt('Test1234!', gen_salt('bf')), NOW(), '2026-02-15 08:15:00', '2026-02-15 08:15:00', '{"provider":"email","providers":["email"]}', '{"full_name":"Hakizimana Eric","country_code":"BI"}', FALSE, 'authenticated', 'authenticated', '', '', '', '', '', '', '', ''),
('10000000-0000-0000-0000-000000000075', '00000000-0000-0000-0000-000000000000', 'nduwimana.aisha@nipanze-bi.test', crypt('Test1234!', gen_salt('bf')), NOW(), '2026-02-16 08:18:00', '2026-02-16 08:18:00', '{"provider":"email","providers":["email"]}', '{"full_name":"Nduwimana Aisha","country_code":"BI"}', FALSE, 'authenticated', 'authenticated', '', '', '', '', '', '', '', ''),
('10000000-0000-0000-0000-000000000076', '00000000-0000-0000-0000-000000000000', 'ntahonkiriye.fabrice@nipanze-bi.test', crypt('Test1234!', gen_salt('bf')), NOW(), '2026-02-17 08:21:00', '2026-02-17 08:21:00', '{"provider":"email","providers":["email"]}', '{"full_name":"Ntahonkiriye Fabrice","country_code":"BI"}', FALSE, 'authenticated', 'authenticated', '', '', '', '', '', '', '', ''),
('10000000-0000-0000-0000-000000000077', '00000000-0000-0000-0000-000000000000', 'nshimirimana.pacifique@nipanze-bi.test', crypt('Test1234!', gen_salt('bf')), NOW(), '2026-02-18 08:24:00', '2026-02-18 08:24:00', '{"provider":"email","providers":["email"]}', '{"full_name":"Nshimirimana Pacifique","country_code":"BI"}', FALSE, 'authenticated', 'authenticated', '', '', '', '', '', '', '', ''),
('10000000-0000-0000-0000-000000000078', '00000000-0000-0000-0000-000000000000', 'ndikumana.alexis@nipanze-bi.test', crypt('Test1234!', gen_salt('bf')), NOW(), '2026-02-19 08:27:00', '2026-02-19 08:27:00', '{"provider":"email","providers":["email"]}', '{"full_name":"Ndikumana Alexis","country_code":"BI"}', FALSE, 'authenticated', 'authenticated', '', '', '', '', '', '', '', ''),
('10000000-0000-0000-0000-000000000079', '00000000-0000-0000-0000-000000000000', 'nizeyimana.beatrice@nipanze-bi.test', crypt('Test1234!', gen_salt('bf')), NOW(), '2026-02-20 08:30:00', '2026-02-20 08:30:00', '{"provider":"email","providers":["email"]}', '{"full_name":"Nizeyimana Beatrice","country_code":"BI"}', FALSE, 'authenticated', 'authenticated', '', '', '', '', '', '', '', ''),
('10000000-0000-0000-0000-000000000080', '00000000-0000-0000-0000-000000000000', 'nsabimana.olivier@nipanze-bi.test', crypt('Test1234!', gen_salt('bf')), NOW(), '2026-02-21 08:33:00', '2026-02-21 08:33:00', '{"provider":"email","providers":["email"]}', '{"full_name":"Nsabimana Olivier","country_code":"BI"}', FALSE, 'authenticated', 'authenticated', '', '', '', '', '', '', '', ''),
('10000000-0000-0000-0000-000000000081', '00000000-0000-0000-0000-000000000000', 'ntirampeba.clarisse@nipanze-bi.test', crypt('Test1234!', gen_salt('bf')), NOW(), '2026-02-22 08:36:00', '2026-02-22 08:36:00', '{"provider":"email","providers":["email"]}', '{"full_name":"Ntirampeba Clarisse","country_code":"BI"}', FALSE, 'authenticated', 'authenticated', '', '', '', '', '', '', '', ''),
('10000000-0000-0000-0000-000000000082', '00000000-0000-0000-0000-000000000000', 'irakoze.divine@nipanze-bi.test', crypt('Test1234!', gen_salt('bf')), NOW(), '2026-02-23 08:39:00', '2026-02-23 08:39:00', '{"provider":"email","providers":["email"]}', '{"full_name":"Irakoze Divine","country_code":"BI"}', FALSE, 'authenticated', 'authenticated', '', '', '', '', '', '', '', ''),
('10000000-0000-0000-0000-000000000083', '00000000-0000-0000-0000-000000000000', 'admin.burundi.one@nipanze-bi.test', crypt('Test1234!', gen_salt('bf')), NOW(), '2026-02-24 08:42:00', '2026-02-24 08:42:00', '{"provider":"email","providers":["email"]}', '{"full_name":"Admin Burundi One","country_code":"BI"}', FALSE, 'authenticated', 'authenticated', '', '', '', '', '', '', '', ''),
('10000000-0000-0000-0000-000000000084', '00000000-0000-0000-0000-000000000000', 'admin.burundi.two@nipanze-bi.test', crypt('Test1234!', gen_salt('bf')), NOW(), '2026-02-10 08:45:00', '2026-02-10 08:45:00', '{"provider":"email","providers":["email"]}', '{"full_name":"Admin Burundi Two","country_code":"BI"}', FALSE, 'authenticated', 'authenticated', '', '', '', '', '', '', '', ''),
('10000000-0000-0000-0000-000000000085', '00000000-0000-0000-0000-000000000000', 'test.user.burundi@nipanze-bi.test', crypt('Test1234!', gen_salt('bf')), NOW(), '2026-02-11 08:48:00', '2026-02-11 08:48:00', '{"provider":"email","providers":["email"]}', '{"full_name":"Test User Burundi","country_code":"BI"}', FALSE, 'authenticated', 'authenticated', '', '', '', '', '', '', '', '')
ON CONFLICT (id) DO NOTHING;

-- Burundi: profiles (bulk upsert — sets full details regardless of whether
-- the on_auth_user_created trigger already created a bare row)
INSERT INTO public.profiles (
    id, full_name, phone, district, country, employment_type, employer_name,
    monthly_income, income_currency, phone_verified_at, account_status, is_admin, created_at
) VALUES
('10000000-0000-0000-0000-000000000069', 'Ndayishimiye Aline', '+257710009453', 'Bujumbura', 'BI', 'employed', 'Ndayishimiye Household Income', 850000, 'BIF', NULL, 'active', FALSE, '2026-02-10 08:00:00'),
('10000000-0000-0000-0000-000000000070', 'Nkurunziza Gilbert', '+257710009590', 'Bujumbura', 'BI', 'government_employee', 'Nkurunziza Household Income', 1105000, 'BIF', NULL, 'active', FALSE, '2026-02-10 08:00:00'),
('10000000-0000-0000-0000-000000000071', 'Niyonzima Chantal', '+257710009727', 'Bujumbura', 'BI', 'self_employed', 'Niyonzima Household Income', 680000, 'BIF', NULL, 'active', FALSE, '2026-02-10 08:00:00'),
('10000000-0000-0000-0000-000000000072', 'Bigirimana Willy', '+257710009864', 'Bujumbura', 'BI', 'small_business_owner', 'Bigirimana Household Income', 935000, 'BIF', NULL, 'active', FALSE, '2026-02-10 08:00:00'),
('10000000-0000-0000-0000-000000000073', 'Nizigiyimana Solange', '+257710010001', 'Bujumbura', 'BI', 'employed', 'Nizigiyimana Household Income', 765000, 'BIF', NULL, 'active', FALSE, '2026-02-10 08:00:00'),
('10000000-0000-0000-0000-000000000074', 'Hakizimana Eric', '+257710010138', 'Bujumbura', 'BI', 'government_employee', 'Hakizimana Household Income', 1275000, 'BIF', NULL, 'active', FALSE, '2026-02-10 08:00:00'),
('10000000-0000-0000-0000-000000000075', 'Nduwimana Aisha', '+257710010275', 'Bujumbura', 'BI', 'self_employed', 'Nduwimana Household Income', 595000, 'BIF', NULL, 'active', FALSE, '2026-02-10 08:00:00'),
('10000000-0000-0000-0000-000000000076', 'Ntahonkiriye Fabrice', '+257710010412', 'Bujumbura', 'BI', 'small_business_owner', 'Ntahonkiriye Household Income', 1020000, 'BIF', NULL, 'active', FALSE, '2026-02-10 08:00:00'),
('10000000-0000-0000-0000-000000000077', 'Nshimirimana Pacifique', '+257720011627', 'Bujumbura', 'BI', 'business_owner', 'Nshimirimana Capital Partners', 4700000, 'BIF', '2026-02-10 09:00:00', 'active', FALSE, '2026-02-10 08:05:00'),
('10000000-0000-0000-0000-000000000078', 'Ndikumana Alexis', '+257720011778', 'Bujumbura', 'BI', 'business_owner', 'Ndikumana Capital Partners', 2820000, 'BIF', '2026-02-10 09:00:00', 'active', FALSE, '2026-02-10 08:05:00'),
('10000000-0000-0000-0000-000000000079', 'Nizeyimana Beatrice', '+257720011929', 'Bujumbura', 'BI', 'business_owner', 'Nizeyimana Capital Partners', 10340000, 'BIF', '2026-02-10 09:00:00', 'active', FALSE, '2026-02-10 08:05:00'),
('10000000-0000-0000-0000-000000000080', 'Nsabimana Olivier', '+257720012080', 'Bujumbura', 'BI', 'business_owner', 'Nsabimana Capital Partners', 3760000, 'BIF', '2026-02-10 09:00:00', 'active', FALSE, '2026-02-10 08:05:00'),
('10000000-0000-0000-0000-000000000081', 'Ntirampeba Clarisse', '+257720012231', 'Bujumbura', 'BI', 'business_owner', 'Ntirampeba Capital Partners', 11750000, 'BIF', '2026-02-10 09:00:00', 'active', FALSE, '2026-02-10 08:05:00'),
('10000000-0000-0000-0000-000000000082', 'Irakoze Divine', '+25773000000', 'Bujumbura', 'BI', 'employed', 'Local Employer Ltd', 765000, 'BIF', NULL, 'pending_verification', FALSE, '2026-02-10 08:10:00'),
('10000000-0000-0000-0000-000000000083', 'Admin Burundi One', '+257700000000', 'Bujumbura', 'BI', NULL, NULL, NULL, 'BIF', NULL, 'active', TRUE, '2026-01-01 08:00:00'),
('10000000-0000-0000-0000-000000000084', 'Admin Burundi Two', '+257700000001', 'Bujumbura', 'BI', NULL, NULL, NULL, 'BIF', NULL, 'active', TRUE, '2026-01-01 08:00:00'),
('10000000-0000-0000-0000-000000000085', 'Test User Burundi', '+257799999999', 'Bujumbura', 'BI', NULL, NULL, NULL, 'BIF', NULL, 'active', FALSE, '2026-02-10 08:15:00')
ON CONFLICT (id) DO UPDATE SET
    full_name = EXCLUDED.full_name, phone = EXCLUDED.phone, district = EXCLUDED.district,
    country = EXCLUDED.country, employment_type = EXCLUDED.employment_type,
    employer_name = EXCLUDED.employer_name, monthly_income = EXCLUDED.monthly_income,
    income_currency = EXCLUDED.income_currency, phone_verified_at = EXCLUDED.phone_verified_at,
    account_status = EXCLUDED.account_status, is_admin = EXCLUDED.is_admin;

-- Burundi: subscriptions (borrowers/pending/admins/test stay free; lenders upgraded)
INSERT INTO public.subscriptions (user_id, plan, status, amount_minor_units, started_at, expires_at, auto_renew) VALUES
('10000000-0000-0000-0000-000000000069', 'free', 'active', 0, '2026-02-10 08:00:00', NULL, TRUE),
('10000000-0000-0000-0000-000000000070', 'free', 'active', 0, '2026-02-10 08:00:00', NULL, TRUE),
('10000000-0000-0000-0000-000000000071', 'free', 'active', 0, '2026-02-10 08:00:00', NULL, TRUE),
('10000000-0000-0000-0000-000000000072', 'free', 'active', 0, '2026-02-10 08:00:00', NULL, TRUE),
('10000000-0000-0000-0000-000000000073', 'free', 'active', 0, '2026-02-10 08:00:00', NULL, TRUE),
('10000000-0000-0000-0000-000000000074', 'free', 'active', 0, '2026-02-10 08:00:00', NULL, TRUE),
('10000000-0000-0000-0000-000000000075', 'free', 'active', 0, '2026-02-10 08:00:00', NULL, TRUE),
('10000000-0000-0000-0000-000000000076', 'free', 'active', 0, '2026-02-10 08:00:00', NULL, TRUE),
('10000000-0000-0000-0000-000000000077', 'lender', 'active', 10966, '2026-02-10 09:00:00', '2028-02-10 09:00:00', TRUE),
('10000000-0000-0000-0000-000000000078', 'lender', 'active', 10966, '2026-02-10 09:00:00', '2028-02-10 09:00:00', TRUE),
('10000000-0000-0000-0000-000000000079', 'pro', 'active', 47000, '2026-02-10 09:00:00', '2028-02-10 09:00:00', TRUE),
('10000000-0000-0000-0000-000000000080', 'lender', 'active', 10966, '2026-02-10 09:00:00', '2028-02-10 09:00:00', TRUE),
('10000000-0000-0000-0000-000000000081', 'pro', 'active', 47000, '2026-02-10 09:00:00', '2028-02-10 09:00:00', TRUE),
('10000000-0000-0000-0000-000000000082', 'free', 'active', 0, '2026-02-10 08:10:00', NULL, TRUE),
('10000000-0000-0000-0000-000000000083', 'free', 'active', 0, '2024-01-01 08:00:00', NULL, TRUE),
('10000000-0000-0000-0000-000000000084', 'free', 'active', 0, '2024-01-01 08:00:00', NULL, TRUE),
('10000000-0000-0000-0000-000000000085', 'free', 'active', 0, '2026-02-10 08:15:00', NULL, TRUE)
ON CONFLICT (user_id) DO UPDATE SET
    plan = EXCLUDED.plan, status = EXCLUDED.status, amount_minor_units = EXCLUDED.amount_minor_units,
    started_at = EXCLUDED.started_at, expires_at = EXCLUDED.expires_at, auto_renew = EXCLUDED.auto_renew;

-- ============================================
-- COUNTRY: SOUTH SUDAN (SS) — 17 users, mirrors Uganda's structure
-- 8 active borrowers, 5 lenders (lender/pro), 1 pending-verification borrower,
-- 2 admins, 1 test user.
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
('10000000-0000-0000-0000-000000000086', '00000000-0000-0000-0000-000000000000', 'akol.deng@nipanze-ss.test', crypt('Test1234!', gen_salt('bf')), NOW(), '2026-02-10 08:00:00', '2026-02-10 08:00:00', '{"provider":"email","providers":["email"]}', '{"full_name":"Akol Deng","country_code":"SS"}', FALSE, 'authenticated', 'authenticated', '', '', '', '', '', '', '', ''),
('10000000-0000-0000-0000-000000000087', '00000000-0000-0000-0000-000000000000', 'achol.mayen@nipanze-ss.test', crypt('Test1234!', gen_salt('bf')), NOW(), '2026-02-11 08:03:00', '2026-02-11 08:03:00', '{"provider":"email","providers":["email"]}', '{"full_name":"Achol Mayen","country_code":"SS"}', FALSE, 'authenticated', 'authenticated', '', '', '', '', '', '', '', ''),
('10000000-0000-0000-0000-000000000088', '00000000-0000-0000-0000-000000000000', 'garang.bior@nipanze-ss.test', crypt('Test1234!', gen_salt('bf')), NOW(), '2026-02-12 08:06:00', '2026-02-12 08:06:00', '{"provider":"email","providers":["email"]}', '{"full_name":"Garang Bior","country_code":"SS"}', FALSE, 'authenticated', 'authenticated', '', '', '', '', '', '', '', ''),
('10000000-0000-0000-0000-000000000089', '00000000-0000-0000-0000-000000000000', 'nyibol.kuot@nipanze-ss.test', crypt('Test1234!', gen_salt('bf')), NOW(), '2026-02-13 08:09:00', '2026-02-13 08:09:00', '{"provider":"email","providers":["email"]}', '{"full_name":"Nyibol Kuot","country_code":"SS"}', FALSE, 'authenticated', 'authenticated', '', '', '', '', '', '', '', ''),
('10000000-0000-0000-0000-000000000090', '00000000-0000-0000-0000-000000000000', 'deng.majok@nipanze-ss.test', crypt('Test1234!', gen_salt('bf')), NOW(), '2026-02-14 08:12:00', '2026-02-14 08:12:00', '{"provider":"email","providers":["email"]}', '{"full_name":"Deng Majok","country_code":"SS"}', FALSE, 'authenticated', 'authenticated', '', '', '', '', '', '', '', ''),
('10000000-0000-0000-0000-000000000091', '00000000-0000-0000-0000-000000000000', 'akech.aluel@nipanze-ss.test', crypt('Test1234!', gen_salt('bf')), NOW(), '2026-02-15 08:15:00', '2026-02-15 08:15:00', '{"provider":"email","providers":["email"]}', '{"full_name":"Akech Aluel","country_code":"SS"}', FALSE, 'authenticated', 'authenticated', '', '', '', '', '', '', '', ''),
('10000000-0000-0000-0000-000000000092', '00000000-0000-0000-0000-000000000000', 'malual.chol@nipanze-ss.test', crypt('Test1234!', gen_salt('bf')), NOW(), '2026-02-16 08:18:00', '2026-02-16 08:18:00', '{"provider":"email","providers":["email"]}', '{"full_name":"Malual Chol","country_code":"SS"}', FALSE, 'authenticated', 'authenticated', '', '', '', '', '', '', '', ''),
('10000000-0000-0000-0000-000000000093', '00000000-0000-0000-0000-000000000000', 'adut.manyang@nipanze-ss.test', crypt('Test1234!', gen_salt('bf')), NOW(), '2026-02-17 08:21:00', '2026-02-17 08:21:00', '{"provider":"email","providers":["email"]}', '{"full_name":"Adut Manyang","country_code":"SS"}', FALSE, 'authenticated', 'authenticated', '', '', '', '', '', '', '', ''),
('10000000-0000-0000-0000-000000000094', '00000000-0000-0000-0000-000000000000', 'nyandeng.malual@nipanze-ss.test', crypt('Test1234!', gen_salt('bf')), NOW(), '2026-02-18 08:24:00', '2026-02-18 08:24:00', '{"provider":"email","providers":["email"]}', '{"full_name":"Nyandeng Malual","country_code":"SS"}', FALSE, 'authenticated', 'authenticated', '', '', '', '', '', '', '', ''),
('10000000-0000-0000-0000-000000000095', '00000000-0000-0000-0000-000000000000', 'wek.ajak@nipanze-ss.test', crypt('Test1234!', gen_salt('bf')), NOW(), '2026-02-19 08:27:00', '2026-02-19 08:27:00', '{"provider":"email","providers":["email"]}', '{"full_name":"Wek Ajak","country_code":"SS"}', FALSE, 'authenticated', 'authenticated', '', '', '', '', '', '', '', ''),
('10000000-0000-0000-0000-000000000096', '00000000-0000-0000-0000-000000000000', 'achuoth.mabior@nipanze-ss.test', crypt('Test1234!', gen_salt('bf')), NOW(), '2026-02-20 08:30:00', '2026-02-20 08:30:00', '{"provider":"email","providers":["email"]}', '{"full_name":"Achuoth Mabior","country_code":"SS"}', FALSE, 'authenticated', 'authenticated', '', '', '', '', '', '', '', ''),
('10000000-0000-0000-0000-000000000097', '00000000-0000-0000-0000-000000000000', 'nyanchiew.gatkuoth@nipanze-ss.test', crypt('Test1234!', gen_salt('bf')), NOW(), '2026-02-21 08:33:00', '2026-02-21 08:33:00', '{"provider":"email","providers":["email"]}', '{"full_name":"Nyanchiew Gatkuoth","country_code":"SS"}', FALSE, 'authenticated', 'authenticated', '', '', '', '', '', '', '', ''),
('10000000-0000-0000-0000-000000000098', '00000000-0000-0000-0000-000000000000', 'riek.machot@nipanze-ss.test', crypt('Test1234!', gen_salt('bf')), NOW(), '2026-02-22 08:36:00', '2026-02-22 08:36:00', '{"provider":"email","providers":["email"]}', '{"full_name":"Riek Machot","country_code":"SS"}', FALSE, 'authenticated', 'authenticated', '', '', '', '', '', '', '', ''),
('10000000-0000-0000-0000-000000000099', '00000000-0000-0000-0000-000000000000', 'ayen.lual@nipanze-ss.test', crypt('Test1234!', gen_salt('bf')), NOW(), '2026-02-23 08:39:00', '2026-02-23 08:39:00', '{"provider":"email","providers":["email"]}', '{"full_name":"Ayen Lual","country_code":"SS"}', FALSE, 'authenticated', 'authenticated', '', '', '', '', '', '', '', ''),
('10000000-0000-0000-0000-000000000100', '00000000-0000-0000-0000-000000000000', 'admin.south.sudan.one@nipanze-ss.test', crypt('Test1234!', gen_salt('bf')), NOW(), '2026-02-24 08:42:00', '2026-02-24 08:42:00', '{"provider":"email","providers":["email"]}', '{"full_name":"Admin South Sudan One","country_code":"SS"}', FALSE, 'authenticated', 'authenticated', '', '', '', '', '', '', '', ''),
('10000000-0000-0000-0000-000000000101', '00000000-0000-0000-0000-000000000000', 'admin.south.sudan.two@nipanze-ss.test', crypt('Test1234!', gen_salt('bf')), NOW(), '2026-02-10 08:45:00', '2026-02-10 08:45:00', '{"provider":"email","providers":["email"]}', '{"full_name":"Admin South Sudan Two","country_code":"SS"}', FALSE, 'authenticated', 'authenticated', '', '', '', '', '', '', '', ''),
('10000000-0000-0000-0000-000000000102', '00000000-0000-0000-0000-000000000000', 'test.user.south.sudan@nipanze-ss.test', crypt('Test1234!', gen_salt('bf')), NOW(), '2026-02-11 08:48:00', '2026-02-11 08:48:00', '{"provider":"email","providers":["email"]}', '{"full_name":"Test User South Sudan","country_code":"SS"}', FALSE, 'authenticated', 'authenticated', '', '', '', '', '', '', '', '')
ON CONFLICT (id) DO NOTHING;

-- South Sudan: profiles (bulk upsert — sets full details regardless of whether
-- the on_auth_user_created trigger already created a bare row)
INSERT INTO public.profiles (
    id, full_name, phone, district, country, employment_type, employer_name,
    monthly_income, income_currency, phone_verified_at, account_status, is_admin, created_at
) VALUES
('10000000-0000-0000-0000-000000000086', 'Akol Deng', '+211710011782', 'Juba', 'SS', 'employed', 'Akol Household Income', 300000, 'SSP', NULL, 'active', FALSE, '2026-02-10 08:00:00'),
('10000000-0000-0000-0000-000000000087', 'Achol Mayen', '+211710011919', 'Juba', 'SS', 'government_employee', 'Achol Household Income', 390000, 'SSP', NULL, 'active', FALSE, '2026-02-10 08:00:00'),
('10000000-0000-0000-0000-000000000088', 'Garang Bior', '+211710012056', 'Juba', 'SS', 'self_employed', 'Garang Household Income', 240000, 'SSP', NULL, 'active', FALSE, '2026-02-10 08:00:00'),
('10000000-0000-0000-0000-000000000089', 'Nyibol Kuot', '+211710012193', 'Juba', 'SS', 'small_business_owner', 'Nyibol Household Income', 330000, 'SSP', NULL, 'active', FALSE, '2026-02-10 08:00:00'),
('10000000-0000-0000-0000-000000000090', 'Deng Majok', '+211710012330', 'Juba', 'SS', 'employed', 'Deng Household Income', 270000, 'SSP', NULL, 'active', FALSE, '2026-02-10 08:00:00'),
('10000000-0000-0000-0000-000000000091', 'Akech Aluel', '+211710012467', 'Juba', 'SS', 'government_employee', 'Akech Household Income', 450000, 'SSP', NULL, 'active', FALSE, '2026-02-10 08:00:00'),
('10000000-0000-0000-0000-000000000092', 'Malual Chol', '+211710012604', 'Juba', 'SS', 'self_employed', 'Malual Household Income', 210000, 'SSP', NULL, 'active', FALSE, '2026-02-10 08:00:00'),
('10000000-0000-0000-0000-000000000093', 'Adut Manyang', '+211710012741', 'Juba', 'SS', 'small_business_owner', 'Adut Household Income', 360000, 'SSP', NULL, 'active', FALSE, '2026-02-10 08:00:00'),
('10000000-0000-0000-0000-000000000094', 'Nyandeng Malual', '+211720014194', 'Juba', 'SS', 'business_owner', 'Nyandeng Capital Partners', 1600000, 'SSP', '2026-02-10 09:00:00', 'active', FALSE, '2026-02-10 08:05:00'),
('10000000-0000-0000-0000-000000000095', 'Wek Ajak', '+211720014345', 'Juba', 'SS', 'business_owner', 'Wek Capital Partners', 960000, 'SSP', '2026-02-10 09:00:00', 'active', FALSE, '2026-02-10 08:05:00'),
('10000000-0000-0000-0000-000000000096', 'Achuoth Mabior', '+211720014496', 'Juba', 'SS', 'business_owner', 'Achuoth Capital Partners', 3520000, 'SSP', '2026-02-10 09:00:00', 'active', FALSE, '2026-02-10 08:05:00'),
('10000000-0000-0000-0000-000000000097', 'Nyanchiew Gatkuoth', '+211720014647', 'Juba', 'SS', 'business_owner', 'Nyanchiew Capital Partners', 1280000, 'SSP', '2026-02-10 09:00:00', 'active', FALSE, '2026-02-10 08:05:00'),
('10000000-0000-0000-0000-000000000098', 'Riek Machot', '+211720014798', 'Juba', 'SS', 'business_owner', 'Riek Capital Partners', 4000000, 'SSP', '2026-02-10 09:00:00', 'active', FALSE, '2026-02-10 08:05:00'),
('10000000-0000-0000-0000-000000000099', 'Ayen Lual', '+21173000000', 'Juba', 'SS', 'employed', 'Local Employer Ltd', 270000, 'SSP', NULL, 'pending_verification', FALSE, '2026-02-10 08:10:00'),
('10000000-0000-0000-0000-000000000100', 'Admin South Sudan One', '+211700000000', 'Juba', 'SS', NULL, NULL, NULL, 'SSP', NULL, 'active', TRUE, '2026-01-01 08:00:00'),
('10000000-0000-0000-0000-000000000101', 'Admin South Sudan Two', '+211700000001', 'Juba', 'SS', NULL, NULL, NULL, 'SSP', NULL, 'active', TRUE, '2026-01-01 08:00:00'),
('10000000-0000-0000-0000-000000000102', 'Test User South Sudan', '+211799999999', 'Juba', 'SS', NULL, NULL, NULL, 'SSP', NULL, 'active', FALSE, '2026-02-10 08:15:00')
ON CONFLICT (id) DO UPDATE SET
    full_name = EXCLUDED.full_name, phone = EXCLUDED.phone, district = EXCLUDED.district,
    country = EXCLUDED.country, employment_type = EXCLUDED.employment_type,
    employer_name = EXCLUDED.employer_name, monthly_income = EXCLUDED.monthly_income,
    income_currency = EXCLUDED.income_currency, phone_verified_at = EXCLUDED.phone_verified_at,
    account_status = EXCLUDED.account_status, is_admin = EXCLUDED.is_admin;

-- South Sudan: subscriptions (borrowers/pending/admins/test stay free; lenders upgraded)
INSERT INTO public.subscriptions (user_id, plan, status, amount_minor_units, started_at, expires_at, auto_renew) VALUES
('10000000-0000-0000-0000-000000000086', 'free', 'active', 0, '2026-02-10 08:00:00', NULL, TRUE),
('10000000-0000-0000-0000-000000000087', 'free', 'active', 0, '2026-02-10 08:00:00', NULL, TRUE),
('10000000-0000-0000-0000-000000000088', 'free', 'active', 0, '2026-02-10 08:00:00', NULL, TRUE),
('10000000-0000-0000-0000-000000000089', 'free', 'active', 0, '2026-02-10 08:00:00', NULL, TRUE),
('10000000-0000-0000-0000-000000000090', 'free', 'active', 0, '2026-02-10 08:00:00', NULL, TRUE),
('10000000-0000-0000-0000-000000000091', 'free', 'active', 0, '2026-02-10 08:00:00', NULL, TRUE),
('10000000-0000-0000-0000-000000000092', 'free', 'active', 0, '2026-02-10 08:00:00', NULL, TRUE),
('10000000-0000-0000-0000-000000000093', 'free', 'active', 0, '2026-02-10 08:00:00', NULL, TRUE),
('10000000-0000-0000-0000-000000000094', 'lender', 'active', 3733, '2026-02-10 09:00:00', '2028-02-10 09:00:00', TRUE),
('10000000-0000-0000-0000-000000000095', 'lender', 'active', 3733, '2026-02-10 09:00:00', '2028-02-10 09:00:00', TRUE),
('10000000-0000-0000-0000-000000000096', 'pro', 'active', 16000, '2026-02-10 09:00:00', '2028-02-10 09:00:00', TRUE),
('10000000-0000-0000-0000-000000000097', 'lender', 'active', 3733, '2026-02-10 09:00:00', '2028-02-10 09:00:00', TRUE),
('10000000-0000-0000-0000-000000000098', 'pro', 'active', 16000, '2026-02-10 09:00:00', '2028-02-10 09:00:00', TRUE),
('10000000-0000-0000-0000-000000000099', 'free', 'active', 0, '2026-02-10 08:10:00', NULL, TRUE),
('10000000-0000-0000-0000-000000000100', 'free', 'active', 0, '2024-01-01 08:00:00', NULL, TRUE),
('10000000-0000-0000-0000-000000000101', 'free', 'active', 0, '2024-01-01 08:00:00', NULL, TRUE),
('10000000-0000-0000-0000-000000000102', 'free', 'active', 0, '2026-02-10 08:15:00', NULL, TRUE)
ON CONFLICT (user_id) DO UPDATE SET
    plan = EXCLUDED.plan, status = EXCLUDED.status, amount_minor_units = EXCLUDED.amount_minor_units,
    started_at = EXCLUDED.started_at, expires_at = EXCLUDED.expires_at, auto_renew = EXCLUDED.auto_renew;

-- ============================================
-- COUNTRY: DR CONGO (CD) — 17 users, mirrors Uganda's structure
-- 8 active borrowers, 5 lenders (lender/pro), 1 pending-verification borrower,
-- 2 admins, 1 test user.
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
('10000000-0000-0000-0000-000000000103', '00000000-0000-0000-0000-000000000000', 'mbuyi.ilunga@nipanze-cd.test', crypt('Test1234!', gen_salt('bf')), NOW(), '2026-02-10 08:00:00', '2026-02-10 08:00:00', '{"provider":"email","providers":["email"]}', '{"full_name":"Mbuyi Ilunga","country_code":"CD"}', FALSE, 'authenticated', 'authenticated', '', '', '', '', '', '', '', ''),
('10000000-0000-0000-0000-000000000104', '00000000-0000-0000-0000-000000000000', 'kabongo.tshimanga@nipanze-cd.test', crypt('Test1234!', gen_salt('bf')), NOW(), '2026-02-11 08:03:00', '2026-02-11 08:03:00', '{"provider":"email","providers":["email"]}', '{"full_name":"Kabongo Tshimanga","country_code":"CD"}', FALSE, 'authenticated', 'authenticated', '', '', '', '', '', '', '', ''),
('10000000-0000-0000-0000-000000000105', '00000000-0000-0000-0000-000000000000', 'mwamba.kalala@nipanze-cd.test', crypt('Test1234!', gen_salt('bf')), NOW(), '2026-02-12 08:06:00', '2026-02-12 08:06:00', '{"provider":"email","providers":["email"]}', '{"full_name":"Mwamba Kalala","country_code":"CD"}', FALSE, 'authenticated', 'authenticated', '', '', '', '', '', '', '', ''),
('10000000-0000-0000-0000-000000000106', '00000000-0000-0000-0000-000000000000', 'ntumba.kasongo@nipanze-cd.test', crypt('Test1234!', gen_salt('bf')), NOW(), '2026-02-13 08:09:00', '2026-02-13 08:09:00', '{"provider":"email","providers":["email"]}', '{"full_name":"Ntumba Kasongo","country_code":"CD"}', FALSE, 'authenticated', 'authenticated', '', '', '', '', '', '', '', ''),
('10000000-0000-0000-0000-000000000107', '00000000-0000-0000-0000-000000000000', 'kalenga.mutombo@nipanze-cd.test', crypt('Test1234!', gen_salt('bf')), NOW(), '2026-02-14 08:12:00', '2026-02-14 08:12:00', '{"provider":"email","providers":["email"]}', '{"full_name":"Kalenga Mutombo","country_code":"CD"}', FALSE, 'authenticated', 'authenticated', '', '', '', '', '', '', '', ''),
('10000000-0000-0000-0000-000000000108', '00000000-0000-0000-0000-000000000000', 'lukusa.ngoy@nipanze-cd.test', crypt('Test1234!', gen_salt('bf')), NOW(), '2026-02-15 08:15:00', '2026-02-15 08:15:00', '{"provider":"email","providers":["email"]}', '{"full_name":"Lukusa Ngoy","country_code":"CD"}', FALSE, 'authenticated', 'authenticated', '', '', '', '', '', '', '', ''),
('10000000-0000-0000-0000-000000000109', '00000000-0000-0000-0000-000000000000', 'mujinga.banza@nipanze-cd.test', crypt('Test1234!', gen_salt('bf')), NOW(), '2026-02-16 08:18:00', '2026-02-16 08:18:00', '{"provider":"email","providers":["email"]}', '{"full_name":"Mujinga Banza","country_code":"CD"}', FALSE, 'authenticated', 'authenticated', '', '', '', '', '', '', '', ''),
('10000000-0000-0000-0000-000000000110', '00000000-0000-0000-0000-000000000000', 'kasongo.ilunga@nipanze-cd.test', crypt('Test1234!', gen_salt('bf')), NOW(), '2026-02-17 08:21:00', '2026-02-17 08:21:00', '{"provider":"email","providers":["email"]}', '{"full_name":"Kasongo Ilunga","country_code":"CD"}', FALSE, 'authenticated', 'authenticated', '', '', '', '', '', '', '', ''),
('10000000-0000-0000-0000-000000000111', '00000000-0000-0000-0000-000000000000', 'kalonji.mukendi@nipanze-cd.test', crypt('Test1234!', gen_salt('bf')), NOW(), '2026-02-18 08:24:00', '2026-02-18 08:24:00', '{"provider":"email","providers":["email"]}', '{"full_name":"Kalonji Mukendi","country_code":"CD"}', FALSE, 'authenticated', 'authenticated', '', '', '', '', '', '', '', ''),
('10000000-0000-0000-0000-000000000112', '00000000-0000-0000-0000-000000000000', 'tshibangu.mbayo@nipanze-cd.test', crypt('Test1234!', gen_salt('bf')), NOW(), '2026-02-19 08:27:00', '2026-02-19 08:27:00', '{"provider":"email","providers":["email"]}', '{"full_name":"Tshibangu Mbayo","country_code":"CD"}', FALSE, 'authenticated', 'authenticated', '', '', '', '', '', '', '', ''),
('10000000-0000-0000-0000-000000000113', '00000000-0000-0000-0000-000000000000', 'mutombo.kanyinda@nipanze-cd.test', crypt('Test1234!', gen_salt('bf')), NOW(), '2026-02-20 08:30:00', '2026-02-20 08:30:00', '{"provider":"email","providers":["email"]}', '{"full_name":"Mutombo Kanyinda","country_code":"CD"}', FALSE, 'authenticated', 'authenticated', '', '', '', '', '', '', '', ''),
('10000000-0000-0000-0000-000000000114', '00000000-0000-0000-0000-000000000000', 'nkulu.ngalula@nipanze-cd.test', crypt('Test1234!', gen_salt('bf')), NOW(), '2026-02-21 08:33:00', '2026-02-21 08:33:00', '{"provider":"email","providers":["email"]}', '{"full_name":"Nkulu Ngalula","country_code":"CD"}', FALSE, 'authenticated', 'authenticated', '', '', '', '', '', '', '', ''),
('10000000-0000-0000-0000-000000000115', '00000000-0000-0000-0000-000000000000', 'ilunga.mwepu@nipanze-cd.test', crypt('Test1234!', gen_salt('bf')), NOW(), '2026-02-22 08:36:00', '2026-02-22 08:36:00', '{"provider":"email","providers":["email"]}', '{"full_name":"Ilunga Mwepu","country_code":"CD"}', FALSE, 'authenticated', 'authenticated', '', '', '', '', '', '', '', ''),
('10000000-0000-0000-0000-000000000116', '00000000-0000-0000-0000-000000000000', 'kanku.mbuyi@nipanze-cd.test', crypt('Test1234!', gen_salt('bf')), NOW(), '2026-02-23 08:39:00', '2026-02-23 08:39:00', '{"provider":"email","providers":["email"]}', '{"full_name":"Kanku Mbuyi","country_code":"CD"}', FALSE, 'authenticated', 'authenticated', '', '', '', '', '', '', '', ''),
('10000000-0000-0000-0000-000000000117', '00000000-0000-0000-0000-000000000000', 'admin.dr.congo.one@nipanze-cd.test', crypt('Test1234!', gen_salt('bf')), NOW(), '2026-02-24 08:42:00', '2026-02-24 08:42:00', '{"provider":"email","providers":["email"]}', '{"full_name":"Admin DR Congo One","country_code":"CD"}', FALSE, 'authenticated', 'authenticated', '', '', '', '', '', '', '', ''),
('10000000-0000-0000-0000-000000000118', '00000000-0000-0000-0000-000000000000', 'admin.dr.congo.two@nipanze-cd.test', crypt('Test1234!', gen_salt('bf')), NOW(), '2026-02-10 08:45:00', '2026-02-10 08:45:00', '{"provider":"email","providers":["email"]}', '{"full_name":"Admin DR Congo Two","country_code":"CD"}', FALSE, 'authenticated', 'authenticated', '', '', '', '', '', '', '', ''),
('10000000-0000-0000-0000-000000000119', '00000000-0000-0000-0000-000000000000', 'test.user.dr.congo@nipanze-cd.test', crypt('Test1234!', gen_salt('bf')), NOW(), '2026-02-11 08:48:00', '2026-02-11 08:48:00', '{"provider":"email","providers":["email"]}', '{"full_name":"Test User DR Congo","country_code":"CD"}', FALSE, 'authenticated', 'authenticated', '', '', '', '', '', '', '', '')
ON CONFLICT (id) DO NOTHING;

-- DR Congo: profiles (bulk upsert — sets full details regardless of whether
-- the on_auth_user_created trigger already created a bare row)
INSERT INTO public.profiles (
    id, full_name, phone, district, country, employment_type, employer_name,
    monthly_income, income_currency, phone_verified_at, account_status, is_admin, created_at
) VALUES
('10000000-0000-0000-0000-000000000103', 'Mbuyi Ilunga', '+243710014111', 'Kinshasa', 'CD', 'employed', 'Mbuyi Household Income', 1100000, 'CDF', NULL, 'active', FALSE, '2026-02-10 08:00:00'),
('10000000-0000-0000-0000-000000000104', 'Kabongo Tshimanga', '+243710014248', 'Kinshasa', 'CD', 'government_employee', 'Kabongo Household Income', 1430000, 'CDF', NULL, 'active', FALSE, '2026-02-10 08:00:00'),
('10000000-0000-0000-0000-000000000105', 'Mwamba Kalala', '+243710014385', 'Kinshasa', 'CD', 'self_employed', 'Mwamba Household Income', 880000, 'CDF', NULL, 'active', FALSE, '2026-02-10 08:00:00'),
('10000000-0000-0000-0000-000000000106', 'Ntumba Kasongo', '+243710014522', 'Kinshasa', 'CD', 'small_business_owner', 'Ntumba Household Income', 1210000, 'CDF', NULL, 'active', FALSE, '2026-02-10 08:00:00'),
('10000000-0000-0000-0000-000000000107', 'Kalenga Mutombo', '+243710014659', 'Kinshasa', 'CD', 'employed', 'Kalenga Household Income', 990000, 'CDF', NULL, 'active', FALSE, '2026-02-10 08:00:00'),
('10000000-0000-0000-0000-000000000108', 'Lukusa Ngoy', '+243710014796', 'Kinshasa', 'CD', 'government_employee', 'Lukusa Household Income', 1650000, 'CDF', NULL, 'active', FALSE, '2026-02-10 08:00:00'),
('10000000-0000-0000-0000-000000000109', 'Mujinga Banza', '+243710014933', 'Kinshasa', 'CD', 'self_employed', 'Mujinga Household Income', 770000, 'CDF', NULL, 'active', FALSE, '2026-02-10 08:00:00'),
('10000000-0000-0000-0000-000000000110', 'Kasongo Ilunga', '+243710015070', 'Kinshasa', 'CD', 'small_business_owner', 'Kasongo Household Income', 1320000, 'CDF', NULL, 'active', FALSE, '2026-02-10 08:00:00'),
('10000000-0000-0000-0000-000000000111', 'Kalonji Mukendi', '+243720016761', 'Kinshasa', 'CD', 'business_owner', 'Kalonji Capital Partners', 6000000, 'CDF', '2026-02-10 09:00:00', 'active', FALSE, '2026-02-10 08:05:00'),
('10000000-0000-0000-0000-000000000112', 'Tshibangu Mbayo', '+243720016912', 'Kinshasa', 'CD', 'business_owner', 'Tshibangu Capital Partners', 3600000, 'CDF', '2026-02-10 09:00:00', 'active', FALSE, '2026-02-10 08:05:00'),
('10000000-0000-0000-0000-000000000113', 'Mutombo Kanyinda', '+243720017063', 'Kinshasa', 'CD', 'business_owner', 'Mutombo Capital Partners', 13200000, 'CDF', '2026-02-10 09:00:00', 'active', FALSE, '2026-02-10 08:05:00'),
('10000000-0000-0000-0000-000000000114', 'Nkulu Ngalula', '+243720017214', 'Kinshasa', 'CD', 'business_owner', 'Nkulu Capital Partners', 4800000, 'CDF', '2026-02-10 09:00:00', 'active', FALSE, '2026-02-10 08:05:00'),
('10000000-0000-0000-0000-000000000115', 'Ilunga Mwepu', '+243720017365', 'Kinshasa', 'CD', 'business_owner', 'Ilunga Capital Partners', 15000000, 'CDF', '2026-02-10 09:00:00', 'active', FALSE, '2026-02-10 08:05:00'),
('10000000-0000-0000-0000-000000000116', 'Kanku Mbuyi', '+24373000000', 'Kinshasa', 'CD', 'employed', 'Local Employer Ltd', 990000, 'CDF', NULL, 'pending_verification', FALSE, '2026-02-10 08:10:00'),
('10000000-0000-0000-0000-000000000117', 'Admin DR Congo One', '+243700000000', 'Kinshasa', 'CD', NULL, NULL, NULL, 'CDF', NULL, 'active', TRUE, '2026-01-01 08:00:00'),
('10000000-0000-0000-0000-000000000118', 'Admin DR Congo Two', '+243700000001', 'Kinshasa', 'CD', NULL, NULL, NULL, 'CDF', NULL, 'active', TRUE, '2026-01-01 08:00:00'),
('10000000-0000-0000-0000-000000000119', 'Test User DR Congo', '+243799999999', 'Kinshasa', 'CD', NULL, NULL, NULL, 'CDF', NULL, 'active', FALSE, '2026-02-10 08:15:00')
ON CONFLICT (id) DO UPDATE SET
    full_name = EXCLUDED.full_name, phone = EXCLUDED.phone, district = EXCLUDED.district,
    country = EXCLUDED.country, employment_type = EXCLUDED.employment_type,
    employer_name = EXCLUDED.employer_name, monthly_income = EXCLUDED.monthly_income,
    income_currency = EXCLUDED.income_currency, phone_verified_at = EXCLUDED.phone_verified_at,
    account_status = EXCLUDED.account_status, is_admin = EXCLUDED.is_admin;

-- DR Congo: subscriptions (borrowers/pending/admins/test stay free; lenders upgraded)
INSERT INTO public.subscriptions (user_id, plan, status, amount_minor_units, started_at, expires_at, auto_renew) VALUES
('10000000-0000-0000-0000-000000000103', 'free', 'active', 0, '2026-02-10 08:00:00', NULL, TRUE),
('10000000-0000-0000-0000-000000000104', 'free', 'active', 0, '2026-02-10 08:00:00', NULL, TRUE),
('10000000-0000-0000-0000-000000000105', 'free', 'active', 0, '2026-02-10 08:00:00', NULL, TRUE),
('10000000-0000-0000-0000-000000000106', 'free', 'active', 0, '2026-02-10 08:00:00', NULL, TRUE),
('10000000-0000-0000-0000-000000000107', 'free', 'active', 0, '2026-02-10 08:00:00', NULL, TRUE),
('10000000-0000-0000-0000-000000000108', 'free', 'active', 0, '2026-02-10 08:00:00', NULL, TRUE),
('10000000-0000-0000-0000-000000000109', 'free', 'active', 0, '2026-02-10 08:00:00', NULL, TRUE),
('10000000-0000-0000-0000-000000000110', 'free', 'active', 0, '2026-02-10 08:00:00', NULL, TRUE),
('10000000-0000-0000-0000-000000000111', 'lender', 'active', 14000, '2026-02-10 09:00:00', '2028-02-10 09:00:00', TRUE),
('10000000-0000-0000-0000-000000000112', 'lender', 'active', 14000, '2026-02-10 09:00:00', '2028-02-10 09:00:00', TRUE),
('10000000-0000-0000-0000-000000000113', 'pro', 'active', 60000, '2026-02-10 09:00:00', '2028-02-10 09:00:00', TRUE),
('10000000-0000-0000-0000-000000000114', 'lender', 'active', 14000, '2026-02-10 09:00:00', '2028-02-10 09:00:00', TRUE),
('10000000-0000-0000-0000-000000000115', 'pro', 'active', 60000, '2026-02-10 09:00:00', '2028-02-10 09:00:00', TRUE),
('10000000-0000-0000-0000-000000000116', 'free', 'active', 0, '2026-02-10 08:10:00', NULL, TRUE),
('10000000-0000-0000-0000-000000000117', 'free', 'active', 0, '2024-01-01 08:00:00', NULL, TRUE),
('10000000-0000-0000-0000-000000000118', 'free', 'active', 0, '2024-01-01 08:00:00', NULL, TRUE),
('10000000-0000-0000-0000-000000000119', 'free', 'active', 0, '2026-02-10 08:15:00', NULL, TRUE)
ON CONFLICT (user_id) DO UPDATE SET
    plan = EXCLUDED.plan, status = EXCLUDED.status, amount_minor_units = EXCLUDED.amount_minor_units,
    started_at = EXCLUDED.started_at, expires_at = EXCLUDED.expires_at, auto_renew = EXCLUDED.auto_renew;

-- ============================================
-- COUNTRY: SOMALIA (SO) — 17 users, mirrors Uganda's structure
-- 8 active borrowers, 5 lenders (lender/pro), 1 pending-verification borrower,
-- 2 admins, 1 test user.
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
('10000000-0000-0000-0000-000000000120', '00000000-0000-0000-0000-000000000000', 'hodan.ali@nipanze-so.test', crypt('Test1234!', gen_salt('bf')), NOW(), '2026-02-10 08:00:00', '2026-02-10 08:00:00', '{"provider":"email","providers":["email"]}', '{"full_name":"Hodan Ali","country_code":"SO"}', FALSE, 'authenticated', 'authenticated', '', '', '', '', '', '', '', ''),
('10000000-0000-0000-0000-000000000121', '00000000-0000-0000-0000-000000000000', 'abdirahman.yusuf@nipanze-so.test', crypt('Test1234!', gen_salt('bf')), NOW(), '2026-02-11 08:03:00', '2026-02-11 08:03:00', '{"provider":"email","providers":["email"]}', '{"full_name":"Abdirahman Yusuf","country_code":"SO"}', FALSE, 'authenticated', 'authenticated', '', '', '', '', '', '', '', ''),
('10000000-0000-0000-0000-000000000122', '00000000-0000-0000-0000-000000000000', 'fadumo.hassan@nipanze-so.test', crypt('Test1234!', gen_salt('bf')), NOW(), '2026-02-12 08:06:00', '2026-02-12 08:06:00', '{"provider":"email","providers":["email"]}', '{"full_name":"Fadumo Hassan","country_code":"SO"}', FALSE, 'authenticated', 'authenticated', '', '', '', '', '', '', '', ''),
('10000000-0000-0000-0000-000000000123', '00000000-0000-0000-0000-000000000000', 'cabdullahi.nur@nipanze-so.test', crypt('Test1234!', gen_salt('bf')), NOW(), '2026-02-13 08:09:00', '2026-02-13 08:09:00', '{"provider":"email","providers":["email"]}', '{"full_name":"Cabdullahi Nur","country_code":"SO"}', FALSE, 'authenticated', 'authenticated', '', '', '', '', '', '', '', ''),
('10000000-0000-0000-0000-000000000124', '00000000-0000-0000-0000-000000000000', 'sahra.mohamed@nipanze-so.test', crypt('Test1234!', gen_salt('bf')), NOW(), '2026-02-14 08:12:00', '2026-02-14 08:12:00', '{"provider":"email","providers":["email"]}', '{"full_name":"Sahra Mohamed","country_code":"SO"}', FALSE, 'authenticated', 'authenticated', '', '', '', '', '', '', '', ''),
('10000000-0000-0000-0000-000000000125', '00000000-0000-0000-0000-000000000000', 'mohamed.farah@nipanze-so.test', crypt('Test1234!', gen_salt('bf')), NOW(), '2026-02-15 08:15:00', '2026-02-15 08:15:00', '{"provider":"email","providers":["email"]}', '{"full_name":"Mohamed Farah","country_code":"SO"}', FALSE, 'authenticated', 'authenticated', '', '', '', '', '', '', '', ''),
('10000000-0000-0000-0000-000000000126', '00000000-0000-0000-0000-000000000000', 'halima.isse@nipanze-so.test', crypt('Test1234!', gen_salt('bf')), NOW(), '2026-02-16 08:18:00', '2026-02-16 08:18:00', '{"provider":"email","providers":["email"]}', '{"full_name":"Halima Isse","country_code":"SO"}', FALSE, 'authenticated', 'authenticated', '', '', '', '', '', '', '', ''),
('10000000-0000-0000-0000-000000000127', '00000000-0000-0000-0000-000000000000', 'bashir.aden@nipanze-so.test', crypt('Test1234!', gen_salt('bf')), NOW(), '2026-02-17 08:21:00', '2026-02-17 08:21:00', '{"provider":"email","providers":["email"]}', '{"full_name":"Bashir Aden","country_code":"SO"}', FALSE, 'authenticated', 'authenticated', '', '', '', '', '', '', '', ''),
('10000000-0000-0000-0000-000000000128', '00000000-0000-0000-0000-000000000000', 'abdullahi.warsame@nipanze-so.test', crypt('Test1234!', gen_salt('bf')), NOW(), '2026-02-18 08:24:00', '2026-02-18 08:24:00', '{"provider":"email","providers":["email"]}', '{"full_name":"Abdullahi Warsame","country_code":"SO"}', FALSE, 'authenticated', 'authenticated', '', '', '', '', '', '', '', ''),
('10000000-0000-0000-0000-000000000129', '00000000-0000-0000-0000-000000000000', 'cabdiraxman.warfaa@nipanze-so.test', crypt('Test1234!', gen_salt('bf')), NOW(), '2026-02-19 08:27:00', '2026-02-19 08:27:00', '{"provider":"email","providers":["email"]}', '{"full_name":"Cabdiraxman Warfaa","country_code":"SO"}', FALSE, 'authenticated', 'authenticated', '', '', '', '', '', '', '', ''),
('10000000-0000-0000-0000-000000000130', '00000000-0000-0000-0000-000000000000', 'ifrah.guuleed@nipanze-so.test', crypt('Test1234!', gen_salt('bf')), NOW(), '2026-02-20 08:30:00', '2026-02-20 08:30:00', '{"provider":"email","providers":["email"]}', '{"full_name":"Ifrah Guuleed","country_code":"SO"}', FALSE, 'authenticated', 'authenticated', '', '', '', '', '', '', '', ''),
('10000000-0000-0000-0000-000000000131', '00000000-0000-0000-0000-000000000000', 'xasan.nuur@nipanze-so.test', crypt('Test1234!', gen_salt('bf')), NOW(), '2026-02-21 08:33:00', '2026-02-21 08:33:00', '{"provider":"email","providers":["email"]}', '{"full_name":"Xasan Nuur","country_code":"SO"}', FALSE, 'authenticated', 'authenticated', '', '', '', '', '', '', '', ''),
('10000000-0000-0000-0000-000000000132', '00000000-0000-0000-0000-000000000000', 'zamzam.aweys@nipanze-so.test', crypt('Test1234!', gen_salt('bf')), NOW(), '2026-02-22 08:36:00', '2026-02-22 08:36:00', '{"provider":"email","providers":["email"]}', '{"full_name":"Zamzam Aweys","country_code":"SO"}', FALSE, 'authenticated', 'authenticated', '', '', '', '', '', '', '', ''),
('10000000-0000-0000-0000-000000000133', '00000000-0000-0000-0000-000000000000', 'ubax.farah@nipanze-so.test', crypt('Test1234!', gen_salt('bf')), NOW(), '2026-02-23 08:39:00', '2026-02-23 08:39:00', '{"provider":"email","providers":["email"]}', '{"full_name":"Ubax Farah","country_code":"SO"}', FALSE, 'authenticated', 'authenticated', '', '', '', '', '', '', '', ''),
('10000000-0000-0000-0000-000000000134', '00000000-0000-0000-0000-000000000000', 'admin.somalia.one@nipanze-so.test', crypt('Test1234!', gen_salt('bf')), NOW(), '2026-02-24 08:42:00', '2026-02-24 08:42:00', '{"provider":"email","providers":["email"]}', '{"full_name":"Admin Somalia One","country_code":"SO"}', FALSE, 'authenticated', 'authenticated', '', '', '', '', '', '', '', ''),
('10000000-0000-0000-0000-000000000135', '00000000-0000-0000-0000-000000000000', 'admin.somalia.two@nipanze-so.test', crypt('Test1234!', gen_salt('bf')), NOW(), '2026-02-10 08:45:00', '2026-02-10 08:45:00', '{"provider":"email","providers":["email"]}', '{"full_name":"Admin Somalia Two","country_code":"SO"}', FALSE, 'authenticated', 'authenticated', '', '', '', '', '', '', '', ''),
('10000000-0000-0000-0000-000000000136', '00000000-0000-0000-0000-000000000000', 'test.user.somalia@nipanze-so.test', crypt('Test1234!', gen_salt('bf')), NOW(), '2026-02-11 08:48:00', '2026-02-11 08:48:00', '{"provider":"email","providers":["email"]}', '{"full_name":"Test User Somalia","country_code":"SO"}', FALSE, 'authenticated', 'authenticated', '', '', '', '', '', '', '', '')
ON CONFLICT (id) DO NOTHING;

-- Somalia: profiles (bulk upsert — sets full details regardless of whether
-- the on_auth_user_created trigger already created a bare row)
INSERT INTO public.profiles (
    id, full_name, phone, district, country, employment_type, employer_name,
    monthly_income, income_currency, phone_verified_at, account_status, is_admin, created_at
) VALUES
('10000000-0000-0000-0000-000000000120', 'Hodan Ali', '+252710016440', 'Mogadishu', 'SO', 'employed', 'Hodan Household Income', 3800000, 'SOS', NULL, 'active', FALSE, '2026-02-10 08:00:00'),
('10000000-0000-0000-0000-000000000121', 'Abdirahman Yusuf', '+252710016577', 'Mogadishu', 'SO', 'government_employee', 'Abdirahman Household Income', 4940000, 'SOS', NULL, 'active', FALSE, '2026-02-10 08:00:00'),
('10000000-0000-0000-0000-000000000122', 'Fadumo Hassan', '+252710016714', 'Mogadishu', 'SO', 'self_employed', 'Fadumo Household Income', 3040000, 'SOS', NULL, 'active', FALSE, '2026-02-10 08:00:00'),
('10000000-0000-0000-0000-000000000123', 'Cabdullahi Nur', '+252710016851', 'Mogadishu', 'SO', 'small_business_owner', 'Cabdullahi Household Income', 4180000, 'SOS', NULL, 'active', FALSE, '2026-02-10 08:00:00'),
('10000000-0000-0000-0000-000000000124', 'Sahra Mohamed', '+252710016988', 'Mogadishu', 'SO', 'employed', 'Sahra Household Income', 3420000, 'SOS', NULL, 'active', FALSE, '2026-02-10 08:00:00'),
('10000000-0000-0000-0000-000000000125', 'Mohamed Farah', '+252710017125', 'Mogadishu', 'SO', 'government_employee', 'Mohamed Household Income', 5700000, 'SOS', NULL, 'active', FALSE, '2026-02-10 08:00:00'),
('10000000-0000-0000-0000-000000000126', 'Halima Isse', '+252710017262', 'Mogadishu', 'SO', 'self_employed', 'Halima Household Income', 2660000, 'SOS', NULL, 'active', FALSE, '2026-02-10 08:00:00'),
('10000000-0000-0000-0000-000000000127', 'Bashir Aden', '+252710017399', 'Mogadishu', 'SO', 'small_business_owner', 'Bashir Household Income', 4560000, 'SOS', NULL, 'active', FALSE, '2026-02-10 08:00:00'),
('10000000-0000-0000-0000-000000000128', 'Abdullahi Warsame', '+252720019328', 'Mogadishu', 'SO', 'business_owner', 'Abdullahi Capital Partners', 16000000, 'SOS', '2026-02-10 09:00:00', 'active', FALSE, '2026-02-10 08:05:00'),
('10000000-0000-0000-0000-000000000129', 'Cabdiraxman Warfaa', '+252720019479', 'Mogadishu', 'SO', 'business_owner', 'Cabdiraxman Capital Partners', 9600000, 'SOS', '2026-02-10 09:00:00', 'active', FALSE, '2026-02-10 08:05:00'),
('10000000-0000-0000-0000-000000000130', 'Ifrah Guuleed', '+252720019630', 'Mogadishu', 'SO', 'business_owner', 'Ifrah Capital Partners', 35200000, 'SOS', '2026-02-10 09:00:00', 'active', FALSE, '2026-02-10 08:05:00'),
('10000000-0000-0000-0000-000000000131', 'Xasan Nuur', '+252720019781', 'Mogadishu', 'SO', 'business_owner', 'Xasan Capital Partners', 12800000, 'SOS', '2026-02-10 09:00:00', 'active', FALSE, '2026-02-10 08:05:00'),
('10000000-0000-0000-0000-000000000132', 'Zamzam Aweys', '+252720019932', 'Mogadishu', 'SO', 'business_owner', 'Zamzam Capital Partners', 40000000, 'SOS', '2026-02-10 09:00:00', 'active', FALSE, '2026-02-10 08:05:00'),
('10000000-0000-0000-0000-000000000133', 'Ubax Farah', '+25273000000', 'Mogadishu', 'SO', 'employed', 'Local Employer Ltd', 3420000, 'SOS', NULL, 'pending_verification', FALSE, '2026-02-10 08:10:00'),
('10000000-0000-0000-0000-000000000134', 'Admin Somalia One', '+252700000000', 'Mogadishu', 'SO', NULL, NULL, NULL, 'SOS', NULL, 'active', TRUE, '2026-01-01 08:00:00'),
('10000000-0000-0000-0000-000000000135', 'Admin Somalia Two', '+252700000001', 'Mogadishu', 'SO', NULL, NULL, NULL, 'SOS', NULL, 'active', TRUE, '2026-01-01 08:00:00'),
('10000000-0000-0000-0000-000000000136', 'Test User Somalia', '+252799999999', 'Mogadishu', 'SO', NULL, NULL, NULL, 'SOS', NULL, 'active', FALSE, '2026-02-10 08:15:00')
ON CONFLICT (id) DO UPDATE SET
    full_name = EXCLUDED.full_name, phone = EXCLUDED.phone, district = EXCLUDED.district,
    country = EXCLUDED.country, employment_type = EXCLUDED.employment_type,
    employer_name = EXCLUDED.employer_name, monthly_income = EXCLUDED.monthly_income,
    income_currency = EXCLUDED.income_currency, phone_verified_at = EXCLUDED.phone_verified_at,
    account_status = EXCLUDED.account_status, is_admin = EXCLUDED.is_admin;

-- Somalia: subscriptions (borrowers/pending/admins/test stay free; lenders upgraded)
INSERT INTO public.subscriptions (user_id, plan, status, amount_minor_units, started_at, expires_at, auto_renew) VALUES
('10000000-0000-0000-0000-000000000120', 'free', 'active', 0, '2026-02-10 08:00:00', NULL, TRUE),
('10000000-0000-0000-0000-000000000121', 'free', 'active', 0, '2026-02-10 08:00:00', NULL, TRUE),
('10000000-0000-0000-0000-000000000122', 'free', 'active', 0, '2026-02-10 08:00:00', NULL, TRUE),
('10000000-0000-0000-0000-000000000123', 'free', 'active', 0, '2026-02-10 08:00:00', NULL, TRUE),
('10000000-0000-0000-0000-000000000124', 'free', 'active', 0, '2026-02-10 08:00:00', NULL, TRUE),
('10000000-0000-0000-0000-000000000125', 'free', 'active', 0, '2026-02-10 08:00:00', NULL, TRUE),
('10000000-0000-0000-0000-000000000126', 'free', 'active', 0, '2026-02-10 08:00:00', NULL, TRUE),
('10000000-0000-0000-0000-000000000127', 'free', 'active', 0, '2026-02-10 08:00:00', NULL, TRUE),
('10000000-0000-0000-0000-000000000128', 'lender', 'active', 37333, '2026-02-10 09:00:00', '2028-02-10 09:00:00', TRUE),
('10000000-0000-0000-0000-000000000129', 'lender', 'active', 37333, '2026-02-10 09:00:00', '2028-02-10 09:00:00', TRUE),
('10000000-0000-0000-0000-000000000130', 'pro', 'active', 160000, '2026-02-10 09:00:00', '2028-02-10 09:00:00', TRUE),
('10000000-0000-0000-0000-000000000131', 'lender', 'active', 37333, '2026-02-10 09:00:00', '2028-02-10 09:00:00', TRUE),
('10000000-0000-0000-0000-000000000132', 'pro', 'active', 160000, '2026-02-10 09:00:00', '2028-02-10 09:00:00', TRUE),
('10000000-0000-0000-0000-000000000133', 'free', 'active', 0, '2026-02-10 08:10:00', NULL, TRUE),
('10000000-0000-0000-0000-000000000134', 'free', 'active', 0, '2024-01-01 08:00:00', NULL, TRUE),
('10000000-0000-0000-0000-000000000135', 'free', 'active', 0, '2024-01-01 08:00:00', NULL, TRUE),
('10000000-0000-0000-0000-000000000136', 'free', 'active', 0, '2026-02-10 08:15:00', NULL, TRUE)
ON CONFLICT (user_id) DO UPDATE SET
    plan = EXCLUDED.plan, status = EXCLUDED.status, amount_minor_units = EXCLUDED.amount_minor_units,
    started_at = EXCLUDED.started_at, expires_at = EXCLUDED.expires_at, auto_renew = EXCLUDED.auto_renew;
-- ============================================================
-- PART B -- MARKETPLACE DATA (loan_requests, loan_offers,
-- agreements, contact_reveals). Grouped by the request's country,
-- but offers may legitimately come from a lender in a different
-- country -- cross-border bidding is allowed by default (v5.0).
-- ============================================================

SET session_replication_role = 'replica';
-- ---- loan_requests: UGANDA ----
INSERT INTO loan_requests (
    id, borrower_id, country, title, purpose, requested_amount, duration_months,
    income_source, preferred_repayment_plan, repayment_amount_per_period, repayment_timeline,
    district, status, listed_at, expires_at, contracted_at, number_of_offers, views_count, created_at
) VALUES
('c1000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', 'UG',
 'Home Renovation Loan', 'Kitchen and bathroom upgrade at family home in Kampala',
 5000000, 12, 'Salary — UGX 4,500,000', 'monthly', 450000, '12 months starting March 2024', 'Central',
 'contracted', '2024-02-01 09:00:00', NOW() + INTERVAL '10 days', NOW() + INTERVAL '10 days', 2, 87, '2024-02-01 08:45:00'),

('c1000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000002', 'UG',
 'Professional Certification', 'Financial management certification at Makerere University Business School',
 3500000, 12, 'Salary — UGX 3,200,000', 'monthly', 320000, '12 months starting April 2024', 'Central',
 'contracted', '2024-03-01 10:00:00', NOW() + INTERVAL '12 days', '2024-03-05 11:00:00', 1, 54, '2024-03-01 09:45:00'),

('c1000000-0000-0000-0000-000000000003', '10000000-0000-0000-0000-000000000003', 'UG',
 'Business Expansion — IT Equipment', 'Purchase servers and networking equipment for growing IT consultancy',
 8000000, 18, 'Salary — UGX 5,800,000', 'monthly', 500000, '18 months starting February 2026', 'Central',
 'active', NOW() - INTERVAL '2 days', NOW() + INTERVAL '15 days', NULL, 3, 112, NOW() - INTERVAL '2 days 15 minutes'),

('c1000000-0000-0000-0000-000000000004', '10000000-0000-0000-0000-000000000004', 'UG',
 'Boutique Inventory Stock', 'Pre-season clothing stock purchase for Nakato Boutique ahead of Easter season',
 3500000, 12, 'Business income — UGX 2,800,000', 'monthly', 320000, '12 months starting February 2026', 'Central',
 'active', NOW() - INTERVAL '3 days', NOW() + INTERVAL '14 days', NULL, 1, 35, NOW() - INTERVAL '3 days 15 minutes'),

('c1000000-0000-0000-0000-000000000005', '10000000-0000-0000-0000-000000000011', 'UG',
 'Medical Expense Cover', 'Surgery and recovery costs at Mulago National Referral Hospital',
 4500000, 18, 'Salary — UGX 3,300,000', 'monthly', 280000, '18 months starting February 2026', 'Eastern',
 'active', NOW() - INTERVAL '1 day', NOW() + INTERVAL '16 days', NULL, 1, 41, NOW() - INTERVAL '1 day 15 minutes'),

('c1000000-0000-0000-0000-000000000006', '10000000-0000-0000-0000-000000000012', 'UG',
 'Farm Equipment Purchase', 'Irrigation pump and tilling equipment for family farm in Wakiso district',
 6000000, 24, 'Salary — UGX 2,900,000', 'monthly', 280000, '24 months starting February 2026', 'Central',
 'active', NOW() - INTERVAL '4 days', NOW() + INTERVAL '13 days', NULL, 3, 18, NOW() - INTERVAL '4 days 15 minutes'),

('c1000000-0000-0000-0000-000000000007', '10000000-0000-0000-0000-000000000013', 'UG',
 'Vehicle Purchase — Delivery Van', 'Toyota Hiace for goods delivery business serving Mbarara and Kampala',
 9000000, 24, 'Salary — UGX 5,200,000', 'monthly', 420000, '24 months starting January 2026', 'Western',
 'active', NOW() - INTERVAL '5 days', NOW() + INTERVAL '15 days', NULL, 3, 67, NOW() - INTERVAL '5 days 15 minutes'),

('c1000000-0000-0000-0000-000000000008', '10000000-0000-0000-0000-000000000005', 'UG',
 'Business Working Capital', 'Short-term working capital to fulfil supplier contracts at DFCU Bank',
 7000000, 6, 'Salary — UGX 6,500,000', 'monthly', 1200000, '6 months starting February 2026', 'Central',
 'active', NOW() - INTERVAL '6 days 20 hours', NOW() + INTERVAL '14 days', NULL, 2, 29, NOW() - INTERVAL '6 days 21 hours');
-- ---- loan_requests: other EAC countries (one each, demonstrating cross-border marketplace) ----
INSERT INTO loan_requests (
    id, borrower_id, country, title, purpose, requested_amount, duration_months,
    income_source, preferred_repayment_plan, repayment_amount_per_period, repayment_timeline,
    district, status, listed_at, expires_at, contracted_at, number_of_offers, views_count, created_at
) VALUES
-- Kenya — contracted (accepted locally, one rejected cross-border offer)
('c2000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000018', 'KE',
 'Boda-boda Motorcycle Purchase', 'Buy a motorcycle for boda-boda transport business in Nairobi',
 150000, 12, 'Salary — KES 150,000', 'monthly', 14375, '12 months starting March 2026', 'Nairobi',
 'contracted', NOW() - INTERVAL '7 days', NOW() + INTERVAL '8 days', NOW() - INTERVAL '2 days', 2, 19, NOW() - INTERVAL '7 days 10 minutes'),

-- TZ — active, cross-border offer pending
('c2000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000035', 'TZ',
 'Tailoring Machine Purchase', 'Industrial sewing machine to expand a home tailoring business in Dar es Salaam',
 800000, 12, 'Salary — TZS 2,100,000', 'monthly', 71000, '12 months starting March 2026', 'Dar es Salaam',
 'active', NOW() - INTERVAL '6 days', NOW() + INTERVAL '9 days', NULL, 1, 18, NOW() - INTERVAL '6 days 10 minutes'),

-- RW — active, cross-border offer pending
('c2000000-0000-0000-0000-000000000003', '10000000-0000-0000-0000-000000000052', 'RW',
 'University Tuition Fees', 'Second-year tuition fees at a private university in Kigali',
 600000, 10, 'Salary — RWF 850,000', 'monthly', 67500, '10 months starting March 2026', 'Kigali',
 'active', NOW() - INTERVAL '5 days', NOW() + INTERVAL '10 days', NULL, 1, 17, NOW() - INTERVAL '5 days 10 minutes'),

-- BI — active, cross-border offer pending
('c2000000-0000-0000-0000-000000000004', '10000000-0000-0000-0000-000000000069', 'BI',
 'Retail Shop Stock Restock', 'Restocking a small retail shop in central Bujumbura ahead of a busy season',
 700000, 12, 'Salary — BIF 950,000', 'monthly', 64750, '12 months starting March 2026', 'Bujumbura',
 'active', NOW() - INTERVAL '4 days', NOW() + INTERVAL '11 days', NULL, 1, 16, NOW() - INTERVAL '4 days 10 minutes'),

-- SS — active, cross-border offer pending
('c2000000-0000-0000-0000-000000000005', '10000000-0000-0000-0000-000000000086', 'SS',
 'Water Borehole Drilling', 'Community borehole drilling to secure a clean water supply near Juba',
 250000, 18, 'Salary — SSP 300,000', 'monthly', 15500, '18 months starting March 2026', 'Juba',
 'active', NOW() - INTERVAL '3 days', NOW() + INTERVAL '12 days', NULL, 1, 15, NOW() - INTERVAL '3 days 10 minutes'),

-- CD — active, cross-border offer pending
('c2000000-0000-0000-0000-000000000006', '10000000-0000-0000-0000-000000000103', 'CD',
 'Generator Purchase for Shop', 'Backup generator to keep a small retail shop in Kinshasa running during outages',
 900000, 12, 'Salary — CDF 1,100,000', 'monthly', 83250, '12 months starting March 2026', 'Kinshasa',
 'active', NOW() - INTERVAL '2 days', NOW() + INTERVAL '13 days', NULL, 1, 14, NOW() - INTERVAL '2 days 10 minutes'),

-- SO — active, cross-border offer pending
('c2000000-0000-0000-0000-000000000007', '10000000-0000-0000-0000-000000000120', 'SO',
 'Sewing Equipment Expansion', 'Additional sewing machines and materials to grow a tailoring business in Mogadishu',
 3500000, 12, 'Salary — SOS 4,200,000', 'monthly', 340000, '12 months starting March 2026', 'Mogadishu',
 'active', NOW() - INTERVAL '1 days', NOW() + INTERVAL '14 days', NULL, 1, 13, NOW() - INTERVAL '1 days 10 minutes');

-- ---- loan_offers: other EAC countries (all cross-border by design) ----
INSERT INTO loan_offers (
    id, request_id, lender_id, offer_amount, interest_rate_pct, late_fee_pct,
    repayment_frequency, installment_amount, proposed_expectations,
    terms_locked_at, status, offered_at, accepted_at, created_at
) VALUES
-- Kenya listing: local lender accepted
('d2000000-0000-0000-0000-000000000001', 'c2000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000026',
 150000, 15.0, 2.0, 'monthly', 14375, 'Can fund the full motorcycle purchase at 15% per annum, monthly repayments.',
 NOW() - INTERVAL '7 days', 'accepted', NOW() - INTERVAL '7 days', NOW() - INTERVAL '2 days', NOW() - INTERVAL '7 days'),

-- Kenya listing: Tanzanian cross-border lender rejected
('d2000000-0000-0000-0000-000000000002', 'c2000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000043',
 150000, 16.5, 2.0, 'monthly', 14655, 'Willing to fund cross-border at 16.5% per annum.',
 NOW() - INTERVAL '6 days', 'rejected', NOW() - INTERVAL '6 days', NULL, NOW() - INTERVAL '6 days'),

-- TZ listing — cross-border offer from a RW lender
('d2000000-0000-0000-0000-000000000003', 'c2000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000060',
 800000, 13.0, 2.0, 'monthly', 75333, 'Cross-border offer at 13.0% per annum.',
 NOW() - INTERVAL '5 days', 'pending', NOW() - INTERVAL '5 days', NULL, NOW() - INTERVAL '5 days'),

-- RW listing — cross-border offer from a BI lender
('d2000000-0000-0000-0000-000000000004', 'c2000000-0000-0000-0000-000000000003', '10000000-0000-0000-0000-000000000077',
 600000, 12.5, 2.0, 'monthly', 67500, 'Cross-border offer at 12.5% per annum.',
 NOW() - INTERVAL '4 days', 'pending', NOW() - INTERVAL '4 days', NULL, NOW() - INTERVAL '4 days'),

-- BI listing — cross-border offer from a SS lender
('d2000000-0000-0000-0000-000000000005', 'c2000000-0000-0000-0000-000000000004', '10000000-0000-0000-0000-000000000094',
 700000, 14.0, 2.0, 'monthly', 66500, 'Cross-border offer at 14.0% per annum.',
 NOW() - INTERVAL '3 days', 'pending', NOW() - INTERVAL '3 days', NULL, NOW() - INTERVAL '3 days'),

-- SS listing — cross-border offer from a CD lender
('d2000000-0000-0000-0000-000000000006', 'c2000000-0000-0000-0000-000000000005', '10000000-0000-0000-0000-000000000111',
 250000, 17.0, 2.0, 'monthly', 16250, 'Cross-border offer at 17.0% per annum.',
 NOW() - INTERVAL '2 days', 'pending', NOW() - INTERVAL '2 days', NULL, NOW() - INTERVAL '2 days'),

-- CD listing — cross-border offer from a SO lender
('d2000000-0000-0000-0000-000000000007', 'c2000000-0000-0000-0000-000000000006', '10000000-0000-0000-0000-000000000128',
 900000, 15.5, 2.0, 'monthly', 86625, 'Cross-border offer at 15.5% per annum.',
 NOW() - INTERVAL '1 days', 'pending', NOW() - INTERVAL '1 days', NULL, NOW() - INTERVAL '1 days'),

-- SO listing — cross-border offer from a KE lender
('d2000000-0000-0000-0000-000000000008', 'c2000000-0000-0000-0000-000000000007', '10000000-0000-0000-0000-000000000026',
 3500000, 18.0, 2.0, 'monthly', 344166, 'Cross-border offer at 18.0% per annum.',
 NOW() - INTERVAL '0 days', 'pending', NOW() - INTERVAL '0 days', NULL, NOW() - INTERVAL '0 days');
-- ---- loan_offers: UGANDA (unchanged from prior seed) ----
INSERT INTO loan_offers (
    id, request_id, lender_id, offer_amount, interest_rate_pct, late_fee_pct,
    repayment_frequency, installment_amount, proposed_expectations,
    terms_locked_at, status, offered_at, accepted_at, created_at
) VALUES
('d1000000-0000-0000-0000-000000000001', 'c1000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000008',
 5000000, 11.0, 2.0, 'monthly', 462500, 'I can provide the full amount at 11% per annum. Monthly instalments work for me.',
 '2024-02-02 10:30:00', 'accepted', '2024-02-02 10:30:00', NOW() + INTERVAL '10 days', '2024-02-02 10:30:00'),

('d1000000-0000-0000-0000-000000000002', 'c1000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000009',
 5000000, 11.5, 2.0, 'monthly', 464583, 'Happy to lend the full amount. Expecting 11.5% per annum with monthly repayments.',
 '2024-02-03 09:00:00', 'rejected', '2024-02-03 09:00:00', NULL, '2024-02-03 09:00:00'),

('d1000000-0000-0000-0000-000000000003', 'c1000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000009',
 3500000, 14.0, 2.0, 'monthly', 332500, 'Willing to fund the full amount at 14% per annum. Monthly repayments as proposed.',
 '2024-03-02 11:00:00', 'accepted', '2024-03-02 11:00:00', '2024-03-05 11:00:00', '2024-03-02 11:00:00'),

('d1000000-0000-0000-0000-000000000004', 'c1000000-0000-0000-0000-000000000003', '10000000-0000-0000-0000-000000000008',
 8000000, 10.0, 2.0, 'monthly', 488888, 'Can cover the full amount at 10% per annum. Happy with 18-month monthly instalments.',
 '2026-01-21 11:20:00', 'pending', '2026-01-21 11:20:00', NULL, '2026-01-21 11:20:00'),

('d1000000-0000-0000-0000-000000000005', 'c1000000-0000-0000-0000-000000000003', '10000000-0000-0000-0000-000000000010',
 8000000, 10.5, 2.0, 'monthly', 491111, 'Offering full amount at 10.5% per annum. Monthly instalments over 18 months.',
 '2026-01-23 13:15:00', 'pending', '2026-01-23 13:15:00', NULL, '2026-01-23 13:15:00'),

('d1000000-0000-0000-0000-000000000010', 'c1000000-0000-0000-0000-000000000003', '10000000-0000-0000-0000-000000000009',
 3000000, 9.5, 2.0, 'monthly', 182500, 'Can contribute UGX 3M toward the equipment purchase at 9.5% per annum, repayable monthly.',
 '2026-01-24 08:40:00', 'pending', '2026-01-24 08:40:00', NULL, '2026-01-24 08:40:00'),

('d1000000-0000-0000-0000-000000000006', 'c1000000-0000-0000-0000-000000000004', '10000000-0000-0000-0000-000000000006',
 3500000, 14.0, 2.0, 'monthly', 332500, 'Can fund the full requested amount at 14% per annum. Monthly repayments as stated.',
 '2026-01-27 10:30:00', 'pending', '2026-01-27 10:30:00', NULL, '2026-01-27 10:30:00'),

('d1000000-0000-0000-0000-000000000007', 'c1000000-0000-0000-0000-000000000005', '10000000-0000-0000-0000-000000000011',
 4500000, 14.5, 1.5, 'monthly', 286250, 'Prepared to lend the full amount at 14.5% per annum given the medical urgency.',
 '2026-01-28 09:15:00', 'pending', '2026-01-28 09:15:00', NULL, '2026-01-28 09:15:00'),

('d1000000-0000-0000-0000-000000000011', 'c1000000-0000-0000-0000-000000000006', '10000000-0000-0000-0000-000000000006',
 3000000, 12.0, 2.0, 'monthly', 140000, 'Can fund UGX 3M now for the pump purchase. Comfortable with the 24-month repayment timeline.',
 NOW() - INTERVAL '3 days 7 hours', 'pending', NOW() - INTERVAL '3 days 7 hours', NULL, NOW() - INTERVAL '3 days 7 hours'),

('d1000000-0000-0000-0000-000000000012', 'c1000000-0000-0000-0000-000000000006', '10000000-0000-0000-0000-000000000008',
 6000000, 13.0, 2.0, 'monthly', 282500, 'Can fund the full equipment amount if repayments begin as proposed in February.',
 NOW() - INTERVAL '2 days 18 hours', 'pending', NOW() - INTERVAL '2 days 18 hours', NULL, NOW() - INTERVAL '2 days 18 hours'),

('d1000000-0000-0000-0000-000000000013', 'c1000000-0000-0000-0000-000000000006', '10000000-0000-0000-0000-000000000010',
 4000000, 11.5, 2.0, 'monthly', 185833, 'Can cover UGX 4M for the tilling equipment, with monthly payments over 24 months.',
 NOW() - INTERVAL '1 day 9 hours', 'pending', NOW() - INTERVAL '1 day 9 hours', NULL, NOW() - INTERVAL '1 day 9 hours'),

('d1000000-0000-0000-0000-000000000008', 'c1000000-0000-0000-0000-000000000007', '10000000-0000-0000-0000-000000000006',
 9000000, 11.0, 2.0, 'monthly', 416250, 'Happy to fund the full van purchase. Expecting 11% per annum over 24 months.',
 NOW() - INTERVAL '4 days 23 hours', 'pending', NOW() - INTERVAL '4 days 23 hours', NULL, NOW() - INTERVAL '4 days 23 hours'),

('d1000000-0000-0000-0000-000000000014', 'c1000000-0000-0000-0000-000000000007', '10000000-0000-0000-0000-000000000008',
 3000000, 12.5, 2.0, 'monthly', 140625, 'Can offer UGX 3M as partial funding for the van deposit and initial repairs.',
 NOW() - INTERVAL '3 days 12 hours', 'pending', NOW() - INTERVAL '3 days 12 hours', NULL, NOW() - INTERVAL '3 days 12 hours'),

('d1000000-0000-0000-0000-000000000015', 'c1000000-0000-0000-0000-000000000007', '10000000-0000-0000-0000-000000000009',
 5000000, 11.5, 2.0, 'monthly', 232291, 'Can fund UGX 5M toward the van purchase with slightly faster monthly repayment preferred.',
 NOW() - INTERVAL '2 days 6 hours', 'pending', NOW() - INTERVAL '2 days 6 hours', NULL, NOW() - INTERVAL '2 days 6 hours'),

('d1000000-0000-0000-0000-000000000009', 'c1000000-0000-0000-0000-000000000008', '10000000-0000-0000-0000-000000000010',
 7000000, 9.5, 2.0, 'monthly', 1277500, 'Can provide full working capital at 9.5% per annum. Six monthly repayments.',
 NOW() - INTERVAL '2 hours', 'pending', NOW() - INTERVAL '2 hours', NULL, NOW() - INTERVAL '2 hours'),

('d1000000-0000-0000-0000-000000000016', 'c1000000-0000-0000-0000-000000000008', '10000000-0000-0000-0000-000000000008',
 3000000, 10.0, 2.0, 'monthly', 550000, 'Can cover UGX 3M of the working capital need if the supplier contract is confirmed.',
 NOW() - INTERVAL '45 minutes', 'pending', NOW() - INTERVAL '45 minutes', NULL, NOW() - INTERVAL '45 minutes');

-- ---- agreements: UGANDA (unchanged) + KENYA (cross-border-flow demo) ----
INSERT INTO public.agreements (
    id, offer_id, request_id, repayment_frequency, repayment_amount, repayment_period,
    total_repayment_amount, late_payment_penalty_pct, agreement_text, agreement_snapshot, status,
    borrower_agreed_at, lender_agreed_at, locked_at
) VALUES
('a9000000-0000-0000-0000-000000000001', 'd1000000-0000-0000-0000-000000000001', 'c1000000-0000-0000-0000-000000000001',
 'monthly'::public.repayment_frequency_enum, 462500, 12, 5550000, 2.00,
 'LOAN AGREEMENT between David Mukasa and William Kasujja. Principal: UGX 5,000,000 at 11% interest. Repayments: Monthly UGX 462,500.',
 '{"payment_frequency": "monthly", "payment_amount": 462500, "penalty_pct": 2.00, "repayment_period": 12, "total_repayment_amount": 5550000, "duration_months": 12, "loan_amount": 5000000, "interest_rate_pct": 11.0, "currency_code": "UGX"}'::jsonb,
 'locked'::public.agreement_status_enum, '2024-02-06 14:30:00', '2024-02-06 14:30:00', '2024-02-06 14:30:00'),

('a9000000-0000-0000-0000-000000000002', 'd1000000-0000-0000-0000-000000000003', 'c1000000-0000-0000-0000-000000000002',
 'monthly'::public.repayment_frequency_enum, 332500, 12, 3990000, 2.00,
 'LOAN AGREEMENT between Sarah Namukasa and Catherine Namboze. Principal: UGX 3,500,000 at 14% interest. Repayments: Monthly UGX 332,500.',
 '{"payment_frequency": "monthly", "payment_amount": 332500, "penalty_pct": 2.00, "repayment_period": 12, "total_repayment_amount": 3990000, "duration_months": 12, "loan_amount": 3500000, "interest_rate_pct": 14.0, "currency_code": "UGX"}'::jsonb,
 'locked'::public.agreement_status_enum, '2024-03-05 11:00:00', '2024-03-05 11:00:00', '2024-03-05 11:00:00'),

('a9000000-0000-0000-0000-000000000003', 'd2000000-0000-0000-0000-000000000001', 'c2000000-0000-0000-0000-000000000001',
 'monthly'::public.repayment_frequency_enum, 14375, 12, 172500, 2.00,
 'LOAN AGREEMENT between Wanjiru Kamau and Otieno Mwangi. Principal: KES 150,000 at 15% interest. Repayments: Monthly KES 14,375.',
 '{"payment_frequency": "monthly", "payment_amount": 14375, "penalty_pct": 2.00, "repayment_period": 12, "total_repayment_amount": 172500, "duration_months": 12, "loan_amount": 150000, "interest_rate_pct": 15.0, "currency_code": "KES"}'::jsonb,
 'locked'::public.agreement_status_enum, NOW() - INTERVAL '2 days', NOW() - INTERVAL '2 days', NOW() - INTERVAL '2 days');

SET session_replication_role = 'origin';

-- ---- contact_reveals ----
INSERT INTO contact_reveals (id, offer_id, request_id, revealed_by, status, revealed_at, created_at) VALUES
('f1000000-0000-0000-0000-000000000001', 'd1000000-0000-0000-0000-000000000001', 'c1000000-0000-0000-0000-000000000001',
 '10000000-0000-0000-0000-000000000001', 'revealed', NOW() + INTERVAL '13 days', '2024-02-06 14:31:00'),

('f1000000-0000-0000-0000-000000000002', 'd1000000-0000-0000-0000-000000000003', 'c1000000-0000-0000-0000-000000000002',
 '10000000-0000-0000-0000-000000000002', 'pending', NULL, '2024-03-05 11:01:00'),

('f1000000-0000-0000-0000-000000000003', 'd2000000-0000-0000-0000-000000000001', 'c2000000-0000-0000-0000-000000000001',
 '10000000-0000-0000-0000-000000000018', 'revealed', NOW() - INTERVAL '1 day', NOW() - INTERVAL '2 days')
ON CONFLICT (offer_id) DO NOTHING;

-- ============================================================
-- PART C -- WATCHLIST, NOTIFICATIONS, REFERRALS
-- ============================================================

INSERT INTO watchlist (id, user_id, request_id, added_at) VALUES
('e3000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000005', 'c1000000-0000-0000-0000-000000000003', '2026-01-21 08:00:00'),
('e3000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000008', 'c1000000-0000-0000-0000-000000000005', '2026-01-26 11:00:00'),
('e3000000-0000-0000-0000-000000000003', '10000000-0000-0000-0000-000000000009', 'c1000000-0000-0000-0000-000000000004', '2026-01-25 14:00:00'),
('e3000000-0000-0000-0000-000000000004', '10000000-0000-0000-0000-000000000007', 'c1000000-0000-0000-0000-000000000008', NOW() - INTERVAL '3 hours'),
('e3000000-0000-0000-0000-000000000005', '10000000-0000-0000-0000-000000000012', 'c1000000-0000-0000-0000-000000000003', '2026-01-22 10:00:00'),
('e3000000-0000-0000-0000-000000000006', '10000000-0000-0000-0000-000000000094', 'c2000000-0000-0000-0000-000000000006', NOW() - INTERVAL '1 day'),
('e3000000-0000-0000-0000-000000000007', '10000000-0000-0000-0000-000000000043', 'c2000000-0000-0000-0000-000000000007', NOW() - INTERVAL '12 hours')
ON CONFLICT (user_id, request_id) DO NOTHING;

INSERT INTO notifications (id, user_id, type, title, body, is_read, request_id, offer_id, created_at) VALUES
-- David Mukasa (UG) -- offer accepted, contact revealed
('e4000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', 'offer_accepted', 'Offer accepted',
 'You accepted Pearl Capital''s offer. Contact details have been shared.', TRUE, 'c1000000-0000-0000-0000-000000000001', 'd1000000-0000-0000-0000-000000000001', NOW() + INTERVAL '11 days'),
('e4000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000008', 'offer_accepted', 'Your offer was accepted',
 'David Mukasa accepted your offer. Contact details have been shared.', TRUE, 'c1000000-0000-0000-0000-000000000001', 'd1000000-0000-0000-0000-000000000001', NOW() + INTERVAL '11 days'),
('e4000000-0000-0000-0000-000000000003', '10000000-0000-0000-0000-000000000001', 'contact_revealed', 'Contact details revealed',
 'You can now connect with Pearl Capital Investment Fund directly.', TRUE, 'c1000000-0000-0000-0000-000000000001', 'd1000000-0000-0000-0000-000000000001', '2024-02-07 10:00:00'),
('e4000000-0000-0000-0000-000000000004', '10000000-0000-0000-0000-000000000008', 'contact_revealed', 'Contact details revealed',
 'The borrower has revealed contact details. You can now connect directly.', TRUE, 'c1000000-0000-0000-0000-000000000001', 'd1000000-0000-0000-0000-000000000001', '2024-02-07 10:00:00'),
-- Sarah Namukasa (UG) -- offer accepted, contact pending reveal
('e4000000-0000-0000-0000-000000000005', '10000000-0000-0000-0000-000000000002', 'offer_accepted', 'Offer accepted',
 'You accepted Victoria Investment Group''s offer. Reveal contact details to connect.', FALSE, 'c1000000-0000-0000-0000-000000000002', 'd1000000-0000-0000-0000-000000000003', '2024-03-05 11:01:00'),
('e4000000-0000-0000-0000-000000000006', '10000000-0000-0000-0000-000000000009', 'offer_accepted', 'Your offer was accepted',
 'Sarah Namukasa accepted your offer. Waiting for contact details to be revealed.', FALSE, 'c1000000-0000-0000-0000-000000000002', 'd1000000-0000-0000-0000-000000000003', '2024-03-05 11:01:00'),
-- James Okello (UG) -- offers received
('e4000000-0000-0000-0000-000000000007', '10000000-0000-0000-0000-000000000003', 'offer_received', 'New offer received',
 'Pearl Capital Investment Fund made an offer on your listing.', FALSE, 'c1000000-0000-0000-0000-000000000003', 'd1000000-0000-0000-0000-000000000004', '2026-01-21 11:21:00'),
('e4000000-0000-0000-0000-000000000008', '10000000-0000-0000-0000-000000000003', 'offer_received', 'New offer received',
 'Equator Finance Corporation made an offer on your listing.', FALSE, 'c1000000-0000-0000-0000-000000000003', 'd1000000-0000-0000-0000-000000000005', '2026-01-23 13:16:00'),
-- Maria Nakato (UG) -- offer received
('e4000000-0000-0000-0000-000000000009', '10000000-0000-0000-0000-000000000004', 'offer_received', 'New offer received',
 'GreenLeaf Agro Solutions made an offer on your listing.', FALSE, 'c1000000-0000-0000-0000-000000000004', 'd1000000-0000-0000-0000-000000000006', '2026-01-27 10:31:00'),
-- Robert Ssemwanga (UG) -- closing soon
('e4000000-0000-0000-0000-000000000010', '10000000-0000-0000-0000-000000000005', 'closing_soon_6h', 'Listing closing soon',
 'Your listing "Business Working Capital" closes in under 6 hours.', FALSE, 'c1000000-0000-0000-0000-000000000008', NULL, NOW() - INTERVAL '1 hour'),
-- David's second lender rejected
('e4000000-0000-0000-0000-000000000011', '10000000-0000-0000-0000-000000000009', 'offer_rejected', 'Your offer was not selected',
 'David Mukasa selected a different offer. Your offer on "Home Renovation Loan" was not chosen.', TRUE, 'c1000000-0000-0000-0000-000000000001', 'd1000000-0000-0000-0000-000000000002', NOW() + INTERVAL '12 days'),
-- Kenya — offer accepted, contact revealed (cross-border flow demo)
('e4000000-0000-0000-0000-000000000012', '10000000-0000-0000-0000-000000000018', 'offer_accepted', 'Offer accepted',
 'You accepted Otieno Mwangi''s offer. Contact details have been shared.', TRUE, 'c2000000-0000-0000-0000-000000000001', 'd2000000-0000-0000-0000-000000000001', NOW() - INTERVAL '2 days'),
('e4000000-0000-0000-0000-000000000013', '10000000-0000-0000-0000-000000000026', 'offer_accepted', 'Your offer was accepted',
 'Wanjiru Kamau accepted your offer. Contact details have been shared.', TRUE, 'c2000000-0000-0000-0000-000000000001', 'd2000000-0000-0000-0000-000000000001', NOW() - INTERVAL '2 days'),
('e4000000-0000-0000-0000-000000000014', '10000000-0000-0000-0000-000000000018', 'contact_revealed', 'Contact details revealed',
 'You can now connect with Otieno Mwangi directly.', TRUE, 'c2000000-0000-0000-0000-000000000001', 'd2000000-0000-0000-0000-000000000001', NOW() - INTERVAL '1 day'),
('e4000000-0000-0000-0000-000000000015', '10000000-0000-0000-0000-000000000026', 'contact_revealed', 'Contact details revealed',
 'The borrower has revealed contact details. You can now connect directly.', TRUE, 'c2000000-0000-0000-0000-000000000001', 'd2000000-0000-0000-0000-000000000001', NOW() - INTERVAL '1 day'),
('e4000000-0000-0000-0000-000000000016', '10000000-0000-0000-0000-000000000043', 'offer_rejected', 'Your offer was not selected',
 'Wanjiru Kamau selected a different offer. Your cross-border offer was not chosen.', TRUE, 'c2000000-0000-0000-0000-000000000001', 'd2000000-0000-0000-0000-000000000002', NOW() - INTERVAL '2 days'),
-- New-country offer_received notifications
('e4000000-0000-0000-0000-000000000017', '10000000-0000-0000-0000-000000000035', 'offer_received', 'New offer received',
 'A lender from Rwanda made a cross-border offer on your listing.', FALSE, 'c2000000-0000-0000-0000-000000000002', 'd2000000-0000-0000-0000-000000000003', NOW() - INTERVAL '6 days'),
('e4000000-0000-0000-0000-000000000018', '10000000-0000-0000-0000-000000000052', 'offer_received', 'New offer received',
 'A lender from Burundi made a cross-border offer on your listing.', FALSE, 'c2000000-0000-0000-0000-000000000003', 'd2000000-0000-0000-0000-000000000004', NOW() - INTERVAL '5 days'),
('e4000000-0000-0000-0000-000000000019', '10000000-0000-0000-0000-000000000069', 'offer_received', 'New offer received',
 'A lender from South Sudan made a cross-border offer on your listing.', FALSE, 'c2000000-0000-0000-0000-000000000004', 'd2000000-0000-0000-0000-000000000005', NOW() - INTERVAL '4 days'),
('e4000000-0000-0000-0000-000000000020', '10000000-0000-0000-0000-000000000086', 'offer_received', 'New offer received',
 'A lender from DR Congo made a cross-border offer on your listing.', FALSE, 'c2000000-0000-0000-0000-000000000005', 'd2000000-0000-0000-0000-000000000006', NOW() - INTERVAL '3 days'),
('e4000000-0000-0000-0000-000000000021', '10000000-0000-0000-0000-000000000103', 'offer_received', 'New offer received',
 'A lender from Somalia made a cross-border offer on your listing.', FALSE, 'c2000000-0000-0000-0000-000000000006', 'd2000000-0000-0000-0000-000000000007', NOW() - INTERVAL '2 days'),
('e4000000-0000-0000-0000-000000000022', '10000000-0000-0000-0000-000000000120', 'offer_received', 'New offer received',
 'A lender from Kenya made a cross-border offer on your listing.', FALSE, 'c2000000-0000-0000-0000-000000000007', 'd2000000-0000-0000-0000-000000000008', NOW() - INTERVAL '1 days')
ON CONFLICT DO NOTHING;

INSERT INTO referrals (id, referrer_id, referred_email, referred_user_id, code, is_activated, activated_at, reward_applied, created_at) VALUES
('e5000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', 'frank.omondi@gmail.com', '10000000-0000-0000-0000-000000000011', 'NIP-DAVID-01', TRUE, '2024-03-08 15:00:00', TRUE, '2024-03-01 10:00:00'),
('e5000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000008', 'lucy.nambi@yahoo.com', '10000000-0000-0000-0000-000000000012', 'NIP-PEARL-01', TRUE, '2024-03-10 12:00:00', TRUE, '2024-03-05 09:00:00'),
('e5000000-0000-0000-0000-000000000003', '10000000-0000-0000-0000-000000000003', 'charles.mwesigwa@gmail.com', '10000000-0000-0000-0000-000000000013', 'NIP-JAMES-01', TRUE, '2024-03-12 17:00:00', FALSE, '2024-03-08 11:00:00'),
('e5000000-0000-0000-0000-000000000004', '10000000-0000-0000-0000-000000000001', 'newuser@example.com', NULL, 'NIP-DAVID-02', FALSE, NULL, FALSE, '2026-01-20 09:00:00'),
('e5000000-0000-0000-0000-000000000005', '10000000-0000-0000-0000-000000000018', 'otieno.mwangi@nipanze-ke.test', '10000000-0000-0000-0000-000000000026', 'NIP-WANJIRU-01', TRUE, '2026-02-10 08:05:00', TRUE, '2026-02-09 12:00:00')
ON CONFLICT DO NOTHING;
-- ============================================================
-- PART D — VERIFICATION
-- ============================================================

SELECT c.code, c.name, c.currency_code, c.is_active, COUNT(p.id) AS user_count
FROM countries c
LEFT JOIN profiles p ON p.country = c.code AND p.id::text LIKE '10000000%'
GROUP BY c.code, c.name, c.currency_code, c.is_active
ORDER BY c.code;

SELECT table_name, record_count FROM (
    SELECT 'auth.users'           AS table_name, COUNT(*) AS record_count FROM auth.users           WHERE id::text LIKE '10000000%'
    UNION ALL SELECT 'profiles',                 COUNT(*) FROM profiles                              WHERE id::text LIKE '10000000%'
    UNION ALL SELECT 'subscriptions',            COUNT(*) FROM subscriptions
    UNION ALL SELECT 'kyc_verifications',        COUNT(*) FROM kyc_verifications
    UNION ALL SELECT 'loan_requests',            COUNT(*) FROM loan_requests
    UNION ALL SELECT 'loan_offers',              COUNT(*) FROM loan_offers
    UNION ALL SELECT 'agreements',               COUNT(*) FROM agreements
    UNION ALL SELECT 'contact_reveals',          COUNT(*) FROM contact_reveals
    UNION ALL SELECT 'watchlist',                COUNT(*) FROM watchlist
    UNION ALL SELECT 'notifications',            COUNT(*) FROM notifications
    UNION ALL SELECT 'referrals',                COUNT(*) FROM referrals
) t ORDER BY table_name;

SELECT p.country, p.full_name, au.email,
       au.email_confirmed_at IS NOT NULL AS confirmed,
       p.account_status, p.is_admin,
       s.plan AS subscription_plan, s.status AS subscription_status
FROM profiles p
LEFT JOIN auth.users  au ON au.id = p.id
LEFT JOIN subscriptions s ON s.user_id = p.id AND s.status = 'active'
WHERE p.id::text LIKE '10000000%'
ORDER BY p.country, p.created_at;

SELECT lr.country, lr.title, lr.district, lr.requested_amount,
       lr.repayment_amount_per_period, lr.number_of_offers, lr.status, lr.expires_at,
       (lr.expires_at < NOW() + INTERVAL '24 hours') AS closing_soon
FROM loan_requests lr
WHERE lr.status = 'active'
ORDER BY lr.country, lr.listed_at DESC;

SELECT lr.country AS listing_country, p_lender.country AS lender_country,
       lo.status AS offer_status, lo.offer_amount, lr.title AS listing_title,
       cr.status AS reveal_status
FROM loan_offers lo
JOIN loan_requests lr ON lr.id = lo.request_id
JOIN profiles p_lender ON p_lender.id = lo.lender_id
LEFT JOIN contact_reveals cr ON cr.offer_id = lo.id
ORDER BY lr.country, lo.offered_at;

SELECT '✅ Nipanze seed v5.1 inserted successfully — 8 countries x 17 users each (136 total), identical role structure per country, full cross-border marketplace demo, no schema mismatches' AS status;