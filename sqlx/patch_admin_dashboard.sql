-- ============================================
-- NIPANZE — Patch: Admin Dashboard Tables
-- File: sql/patch_admin_dashboard.sql
-- Apply ONCE in Supabase Cloud SQL Editor (top to bottom).
-- Idempotent: all blocks use IF NOT EXISTS / CREATE OR REPLACE / ON CONFLICT.
--
-- What this patch adds:
--   1. admin_invitations — controlled admin-seat onboarding table.
--   2. Admin dashboard views (all gated by private.is_admin()):
--      · v_admin_users        — all accounts with email, KYC, plan
--      · v_admin_kyc_queue    — pending KYC reviews, oldest first
--      · v_admin_transactions — platform revenue ledger
--      · v_admin_audit_log    — full audit trail with actor email
--      · v_admin_overview_kpis— single-row headline stats
--   3. RPC: admin_invite_user(email)  — admin generates invitation token
--   4. RPC: admin_promote_user(token) — invitee consumes token → is_admin
--   5. Seed: admin@nipanze.ug / Test1234! with is_admin = TRUE
-- ============================================


-- ============================================
-- 1. TABLE: admin_invitations
-- ============================================

CREATE TABLE IF NOT EXISTS public.admin_invitations (
    id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    invited_email TEXT NOT NULL,
    token         TEXT NOT NULL UNIQUE DEFAULT encode(gen_random_bytes(32), 'hex'),
    invited_by    UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    accepted_by   UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    accepted_at   TIMESTAMP,
    expires_at    TIMESTAMP NOT NULL DEFAULT NOW() + INTERVAL '7 days',
    revoked       BOOLEAN NOT NULL DEFAULT FALSE,
    revoked_at    TIMESTAMP,
    created_at    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE public.admin_invitations IS
'Controlled admin-seat invitation chain. An existing admin calls admin_invite_user() to
 create a row here. The invitee calls admin_promote_user(token) to gain is_admin = TRUE.
 Tokens expire after 7 days. Prevents self-promotion via the REST API.';

ALTER TABLE public.admin_invitations ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename='admin_invitations' AND policyname='admin_invitations: admin read'
  ) THEN
    CREATE POLICY "admin_invitations: admin read"
        ON public.admin_invitations FOR SELECT TO authenticated
        USING (private.is_admin());
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename='admin_invitations' AND policyname='admin_invitations: service role write'
  ) THEN
    CREATE POLICY "admin_invitations: service role write"
        ON public.admin_invitations FOR ALL TO service_role
        USING (TRUE) WITH CHECK (TRUE);
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_ai_email   ON public.admin_invitations (invited_email);
CREATE INDEX IF NOT EXISTS idx_ai_token   ON public.admin_invitations (token);
CREATE INDEX IF NOT EXISTS idx_ai_pending ON public.admin_invitations (expires_at, revoked, accepted_at)
    WHERE revoked = FALSE AND accepted_at IS NULL;


-- ============================================
-- 2. ADMIN DASHBOARD VIEWS
-- ============================================

-- v_admin_users
CREATE OR REPLACE VIEW public.v_admin_users
WITH (security_invoker = true) AS
SELECT
    p.id                                            AS user_id,
    au.email,
    p.full_name,
    p.phone,
    p.country,
    p.district,
    p.account_status,
    p.is_admin,
    p.employment_type,
    p.phone_verified_at IS NOT NULL                 AS phone_verified,
    k.status                                        AS kyc_status,
    k.submitted_at                                  AS kyc_submitted_at,
    k.reviewed_at                                   AS kyc_reviewed_at,
    k.expires_at                                    AS kyc_expires_at,
    s.plan                                          AS subscription_plan,
    s.status                                        AS subscription_status,
    s.expires_at                                    AS subscription_expires_at,
    ta.rating_avg,
    COALESCE(ta.review_count, 0)                    AS review_count,
    COALESCE(ta.completed_deals_count, 0)           AS completed_deals,
    COALESCE(lr_counts.active_requests, 0)          AS active_loan_requests,
    COALESCE(lo_counts.pending_offers, 0)           AS pending_loan_offers,
    p.created_at                                    AS registered_at,
    p.updated_at
FROM public.profiles p
JOIN auth.users au ON au.id = p.id
LEFT JOIN public.kyc_verifications k   ON k.user_id  = p.id
LEFT JOIN public.subscriptions     s   ON s.user_id  = p.id AND s.status = 'active'
LEFT JOIN public.trust_aggregates  ta  ON ta.user_id = p.id
LEFT JOIN LATERAL (
    SELECT COUNT(*) FILTER (WHERE status = 'active') AS active_requests
    FROM public.loan_requests WHERE borrower_id = p.id
) lr_counts ON TRUE
LEFT JOIN LATERAL (
    SELECT COUNT(*) FILTER (WHERE status = 'pending') AS pending_offers
    FROM public.loan_offers WHERE lender_id = p.id
) lo_counts ON TRUE
WHERE private.is_admin();

COMMENT ON VIEW public.v_admin_users IS
'Admin-only: all user accounts with auth email, profile, KYC, subscription, marketplace
 activity. Returns zero rows for non-admins (private.is_admin() gate).';

GRANT SELECT ON public.v_admin_users TO authenticated, service_role;


-- v_admin_kyc_queue
CREATE OR REPLACE VIEW public.v_admin_kyc_queue
WITH (security_invoker = true) AS
SELECT
    k.id                    AS kyc_id,
    k.user_id,
    au.email                AS user_email,
    p.full_name,
    p.country,
    k.status,
    k.national_id_type,
    k.national_id_number,
    k.national_id_front_url,
    k.national_id_back_url,
    k.selfie_url,
    k.id_verified,
    k.selfie_verified,
    k.rejection_reason,
    k.verification_notes,
    k.submitted_at,
    k.reviewed_at,
    k.expires_at,
    reviewer.full_name      AS reviewed_by_name,
    k.created_at
FROM public.kyc_verifications k
JOIN public.profiles  p        ON p.id  = k.user_id
JOIN auth.users       au       ON au.id = k.user_id
LEFT JOIN public.profiles reviewer ON reviewer.id = k.verified_by
WHERE private.is_admin()
ORDER BY
    CASE k.status WHEN 'pending' THEN 0 ELSE 1 END,
    k.submitted_at ASC NULLS LAST;

COMMENT ON VIEW public.v_admin_kyc_queue IS
'Admin KYC review queue — pending submissions first, sorted oldest-first. Requires is_admin.';

GRANT SELECT ON public.v_admin_kyc_queue TO authenticated, service_role;


-- v_admin_transactions
CREATE OR REPLACE VIEW public.v_admin_transactions
WITH (security_invoker = true) AS
SELECT
    t.id,
    t.user_id,
    au.email                AS user_email,
    p.full_name,
    t.type,
    t.amount,
    t.currency_code,
    t.country,
    t.provider,
    t.provider_tx_ref,
    t.provider_tx_id,
    t.status,
    t.webhook_verified_at,
    t.related_subscription_id,
    t.related_reveal_id,
    t.created_at,
    t.updated_at
FROM public.transactions t
JOIN public.profiles p  ON p.id  = t.user_id
JOIN auth.users      au ON au.id = t.user_id
WHERE private.is_admin()
ORDER BY t.created_at DESC;

COMMENT ON VIEW public.v_admin_transactions IS
'Admin revenue ledger. Subscription charges and contact-unlock fees only. Requires is_admin.';

GRANT SELECT ON public.v_admin_transactions TO authenticated, service_role;


-- v_admin_audit_log
CREATE OR REPLACE VIEW public.v_admin_audit_log
WITH (security_invoker = true) AS
SELECT
    al.id,
    al.user_id,
    au.email                AS actor_email,
    p.full_name             AS actor_name,
    al.event_type,
    al.entity_type,
    al.entity_id,
    al.action,
    al.description,
    al.ip_address,
    al.user_agent,
    al.old_values,
    al.new_values,
    al.metadata,
    al.created_at
FROM public.audit_logs al
LEFT JOIN public.profiles p  ON p.id  = al.user_id
LEFT JOIN auth.users      au ON au.id = al.user_id
WHERE private.is_admin()
ORDER BY al.created_at DESC;

COMMENT ON VIEW public.v_admin_audit_log IS
'Full audit trail with actor email. Append-only table. Requires is_admin.';

GRANT SELECT ON public.v_admin_audit_log TO authenticated, service_role;


-- v_admin_overview_kpis
CREATE OR REPLACE VIEW public.v_admin_overview_kpis
WITH (security_invoker = true) AS
SELECT
    COUNT(DISTINCT p.id)                                                        AS total_users,
    COUNT(DISTINCT p.id) FILTER (WHERE p.account_status = 'active')            AS active_users,
    COUNT(DISTINCT p.id) FILTER (WHERE p.account_status = 'suspended')         AS suspended_users,
    COUNT(DISTINCT p.id) FILTER (WHERE p.account_status = 'pending_verification') AS pending_users,
    COUNT(DISTINCT p.id) FILTER (WHERE p.is_admin)                             AS admin_count,
    COUNT(DISTINCT k.id) FILTER (WHERE k.status = 'pending')                   AS kyc_pending,
    COUNT(DISTINCT k.id) FILTER (WHERE k.status = 'approved')                  AS kyc_approved,
    COUNT(DISTINCT k.id) FILTER (WHERE k.status = 'rejected')                  AS kyc_rejected,
    COUNT(DISTINCT s.id) FILTER (WHERE s.status='active' AND s.plan='lender')  AS lender_subscribers,
    COUNT(DISTINCT s.id) FILTER (WHERE s.status='active' AND s.plan='pro')     AS pro_subscribers,
    COUNT(DISTINCT lr.id) FILTER (WHERE lr.status = 'active')                  AS active_listings,
    COUNT(DISTINCT lr.id) FILTER (WHERE lr.status = 'contracted')              AS contracted_listings,
    COUNT(DISTINCT lr.id) FILTER (WHERE lr.status = 'expired')                 AS expired_listings,
    COUNT(DISTINCT lo.id) FILTER (WHERE lo.status = 'pending')                 AS pending_offers,
    COUNT(DISTINCT lo.id) FILTER (WHERE lo.status = 'accepted')                AS accepted_offers,
    COUNT(DISTINCT t.id)  FILTER (WHERE t.status = 'successful')               AS successful_transactions,
    COUNT(DISTINCT t.id)  FILTER (WHERE t.status = 'pending')                  AS pending_transactions,
    COUNT(DISTINCT t.id)  FILTER (WHERE t.status = 'failed')                   AS failed_transactions,
    NOW()                                                                       AS computed_at
FROM public.profiles p
LEFT JOIN public.kyc_verifications k  ON k.user_id     = p.id
LEFT JOIN public.subscriptions     s  ON s.user_id     = p.id AND s.status = 'active'
LEFT JOIN public.loan_requests     lr ON lr.borrower_id = p.id
LEFT JOIN public.loan_offers       lo ON lo.lender_id   = p.id
LEFT JOIN public.transactions      t  ON t.user_id      = p.id
WHERE private.is_admin();

COMMENT ON VIEW public.v_admin_overview_kpis IS
'Single-row dashboard headline KPIs. Count-only (no cross-currency amounts). Requires is_admin.';

GRANT SELECT ON public.v_admin_overview_kpis TO authenticated, service_role;


-- ============================================
-- 3. RPC: admin_invite_user(p_email TEXT)
-- ============================================

CREATE OR REPLACE FUNCTION public.admin_invite_user(p_email TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_caller_id UUID := auth.uid();
    v_token     TEXT;
    v_inv_id    UUID;
BEGIN
    IF NOT private.is_admin() THEN
        RAISE EXCEPTION 'NIPANZE_UNAUTHORIZED: Only admins can send admin invitations.'
            USING ERRCODE = 'P0060';
    END IF;

    IF EXISTS (
        SELECT 1 FROM admin_invitations
        WHERE invited_email = LOWER(TRIM(p_email))
          AND revoked = FALSE
          AND accepted_at IS NULL
          AND expires_at > NOW()
    ) THEN
        RAISE EXCEPTION 'NIPANZE_INVITATION_EXISTS: A pending invitation already exists for this email.'
            USING ERRCODE = 'P0061';
    END IF;

    v_token := encode(gen_random_bytes(32), 'hex');

    INSERT INTO admin_invitations (invited_email, token, invited_by, expires_at)
    VALUES (LOWER(TRIM(p_email)), v_token, v_caller_id, NOW() + INTERVAL '7 days')
    RETURNING id INTO v_inv_id;

    INSERT INTO audit_logs (user_id, event_type, entity_type, entity_id, action, new_values)
    VALUES (v_caller_id, 'admin_action', 'admin_invitations', v_inv_id, 'admin_invite_user',
        JSONB_BUILD_OBJECT('invited_email', LOWER(TRIM(p_email))));

    RETURN JSONB_BUILD_OBJECT(
        'invitation_id', v_inv_id,
        'invited_email', LOWER(TRIM(p_email)),
        'token', v_token,
        'expires_at', NOW() + INTERVAL '7 days',
        'note', 'Share this token privately. Invitee calls admin_promote_user(token).'
    );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.admin_invite_user(TEXT) FROM public, anon;
GRANT  EXECUTE ON FUNCTION public.admin_invite_user(TEXT) TO authenticated, service_role;

COMMENT ON FUNCTION public.admin_invite_user(TEXT) IS
'Admin creates a 7-day invitation token for p_email. Returns the token. Invitee must call
 admin_promote_user(token) while authenticated with that email.';


-- ============================================
-- 4. RPC: admin_promote_user(p_invitation_token TEXT)
-- ============================================

CREATE OR REPLACE FUNCTION public.admin_promote_user(p_invitation_token TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_caller_id    UUID := auth.uid();
    v_caller_email TEXT;
    v_inv          admin_invitations%ROWTYPE;
BEGIN
    IF v_caller_id IS NULL THEN
        RAISE EXCEPTION 'NIPANZE_UNAUTHORIZED: Must be authenticated.'
            USING ERRCODE = 'P0062';
    END IF;

    SELECT email INTO v_caller_email FROM auth.users WHERE id = v_caller_id;

    SELECT * INTO v_inv
    FROM admin_invitations
    WHERE token = TRIM(p_invitation_token)
      AND revoked = FALSE
      AND accepted_at IS NULL
      AND expires_at > NOW()
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'NIPANZE_INVALID_TOKEN: Token is invalid, expired, or already used.'
            USING ERRCODE = 'P0063';
    END IF;

    IF LOWER(v_caller_email) != LOWER(v_inv.invited_email) THEN
        RAISE EXCEPTION 'NIPANZE_EMAIL_MISMATCH: Invitation was issued to a different email.'
            USING ERRCODE = 'P0064';
    END IF;

    UPDATE profiles SET is_admin = TRUE, updated_at = NOW() WHERE id = v_caller_id;

    UPDATE admin_invitations
       SET accepted_by = v_caller_id, accepted_at = NOW()
     WHERE id = v_inv.id;

    INSERT INTO audit_logs (user_id, event_type, entity_type, entity_id, action, new_values)
    VALUES (v_caller_id, 'admin_action', 'profiles', v_caller_id, 'admin_promote_user',
        JSONB_BUILD_OBJECT('invitation_id', v_inv.id, 'promoted_at', NOW()));

    RETURN JSONB_BUILD_OBJECT(
        'user_id', v_caller_id,
        'email', v_caller_email,
        'is_admin', TRUE,
        'promoted_at', NOW()
    );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.admin_promote_user(TEXT) FROM public, anon;
GRANT  EXECUTE ON FUNCTION public.admin_promote_user(TEXT) TO authenticated, service_role;

COMMENT ON FUNCTION public.admin_promote_user(TEXT) IS
'Authenticated user consumes a valid invitation token and gains is_admin = TRUE.
 Token is atomically consumed — cannot be reused. Email must match invitation.';


-- ============================================
-- 5. SEED: admin@nipanze.ug / Test1234!
-- UUID: 00000000-0000-0000-0000-000000000001
-- "Platform operator" UUID block — never collides with test-user blocks.
-- Safe to run on any environment (dev/staging/prod).
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
) VALUES (
    '00000000-0000-0000-0000-000000000001',
    '00000000-0000-0000-0000-000000000000',
    'admin@nipanze.ug',
    crypt('Test1234!', gen_salt('bf')),
    NOW(),
    '2024-01-01 00:00:00',
    '2024-01-01 00:00:00',
    '{"provider":"email","providers":["email"]}',
    '{"full_name":"Nipanze Admin","country_code":"UG"}',
    FALSE, 'authenticated', 'authenticated',
    '', '', '', '', '', '', '', ''
)
ON CONFLICT (id) DO UPDATE
    SET encrypted_password = crypt('Test1234!', gen_salt('bf')),
        email_confirmed_at = COALESCE(auth.users.email_confirmed_at, NOW()),
        updated_at         = NOW();

-- Also handle conflict on email (if auth.users has a unique email constraint)
-- Run this only if the above ON CONFLICT (id) doesn't cover it in your Supabase version.
-- INSERT INTO auth.users ... ON CONFLICT (email) DO UPDATE is handled above via id.

INSERT INTO public.profiles (id, full_name, account_status, is_admin, country, created_at)
VALUES (
    '00000000-0000-0000-0000-000000000001',
    'Nipanze Admin',
    'active',
    TRUE,
    'UG',
    '2024-01-01 00:00:00'
)
ON CONFLICT (id) DO UPDATE
    SET full_name      = 'Nipanze Admin',
        account_status = 'active',
        is_admin       = TRUE,
        country        = 'UG',
        updated_at     = NOW();

INSERT INTO public.subscriptions (user_id, plan, status, amount_minor_units)
VALUES ('00000000-0000-0000-0000-000000000001', 'free', 'active', 0)
ON CONFLICT (user_id) WHERE status = 'active' DO NOTHING;


-- ============================================
-- END OF PATCH: patch_admin_dashboard.sql
-- ============================================
