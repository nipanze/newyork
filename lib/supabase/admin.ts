import { createClient as createSupabaseClient } from "@supabase/supabase-js";
import type { Database } from "@/lib/types";

/**
 * Service-role client. SERVER-ONLY — never import this from a Client
 * Component or expose SUPABASE_SERVICE_ROLE_KEY to the browser.
 *
 * Bypasses RLS, so every route handler that uses this must independently
 * verify the caller is an authenticated admin (see requireAdmin() in
 * lib/supabase/require-admin.ts) before doing anything with it.
 */
export function createAdminClient() {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL || "https://placeholder.supabase.co";
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY || "placeholder-service-key";

  return createSupabaseClient<Database>(
    url,
    key,
    {
      auth: {
        autoRefreshToken: false,
        persistSession: false,
      },
    }
  );
}
