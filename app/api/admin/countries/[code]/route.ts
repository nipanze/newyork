import { NextResponse } from "next/server";
import { requireAdmin } from "@/lib/supabase/require-admin";
import { createAdminClient } from "@/lib/supabase/admin";

export async function PATCH(request: Request, { params }: { params: Promise<{ code: string }> }) {
  const admin = await requireAdmin();
  if ("error" in admin) return admin.error;

  const { code } = await params;
  const body = await request.json().catch(() => ({}));
  const { is_active, forex_enabled } = body as { is_active?: boolean; forex_enabled?: boolean };

  const update: Record<string, unknown> = {};
  if (is_active !== undefined) update.is_active = is_active;
  if (forex_enabled !== undefined) update.forex_enabled = forex_enabled;

  if (Object.keys(update).length === 0) {
    return NextResponse.json({ error: "No changes supplied." }, { status: 400 });
  }

  const supabaseAdmin = createAdminClient();
  const { error } = await supabaseAdmin.from("countries").update(update).eq("code", code);

  if (error) {
    // forex_enabled will 500 here until the Stage 4.7 migration adds the
    // column — surfaced as a normal error rather than a crash.
    return NextResponse.json({ error: error.message }, { status: 500 });
  }

  await supabaseAdmin.from("audit_logs").insert({
    user_id: admin.user.id,
    event_type: "admin_action",
    entity_type: "countries",
    entity_id: null,
    action: `dashboard_toggle_country:${code}`,
    new_values: update,
  });

  return NextResponse.json({ ok: true });
}
