-- ============================================
-- PATCH: Fix Subscriptions Table Unique Constraint
-- Fixes "duplicate key value violates unique constraint uidx_sub_user"
-- ============================================

-- Drop strict unique constraint / index on user_id if it exists
ALTER TABLE public.subscriptions DROP CONSTRAINT IF EXISTS uidx_sub_user;
DROP INDEX IF EXISTS public.uidx_sub_user;

-- Create partial unique index allowing only 1 active subscription per user
CREATE UNIQUE INDEX IF NOT EXISTS uidx_sub_active_user 
    ON public.subscriptions (user_id) 
    WHERE status = 'active';
