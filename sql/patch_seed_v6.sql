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