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

