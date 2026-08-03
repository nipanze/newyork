import { createClient } from "@/lib/supabase/server";

/**
 * Verifies the current request is from a signed-in user with
 * profiles.is_admin = TRUE. Returns the user + a plain (RLS-respecting)
 * server client on success, or a 401/403 Response to return as-is.
 *
 * is_admin is the only role in the schema (see schema.sql) — everything
 * else is subscription_plan, which is irrelevant to dashboard access.
 */
export async function requireAdmin() {
  const supabase = await createClient();

  const {
    data: { user },
    error: authError,
  } = await supabase.auth.getUser();

  if (authError || !user) {
    return { error: new Response("Unauthorized", { status: 401 }) } as const;
  }

  const { data: profile, error: profileError } = await supabase
    .from("profiles")
    .select("id, is_admin, full_name")
    .eq("id", user.id)
    .single();

  if (profileError || !profile?.is_admin) {
    return { error: new Response("Forbidden — admin access required", { status: 403 }) } as const;
  }

  return { user, profile, supabase } as const;
}
