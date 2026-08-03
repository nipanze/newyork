import { createBrowserClient } from "@supabase/ssr";
import type { Database } from "@/lib/types";

/**
 * Browser-side Supabase client. Uses the anon key + RLS, exactly like the
 * Flutter app — a signed-in admin can only do what their `profiles.is_admin`
 * row and the RLS policies in schema.sql already allow. Actions that must
 * bypass RLS (KYC approval, suspending an account, etc.) go through the
 * server-only client in lib/supabase/admin.ts via API routes instead.
 */
export function createClient() {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL || "https://placeholder.supabase.co";
  const key = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY || "placeholder-anon-key";

  return createBrowserClient<Database>(url, key);
}
