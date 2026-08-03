import { NextResponse } from "next/server";
import { requireAdmin } from "@/lib/supabase/require-admin";
import { createAdminClient } from "@/lib/supabase/admin";

export async function PATCH(request: Request, { params }: { params: Promise<{ id: string }> }) {
  const admin = await requireAdmin();
  if ("error" in admin) return admin.error;

  const { id } = await params;
  const body = await request.json().catch(() => ({}));
  const { setting_value } = body as { setting_value?: string };

  if (setting_value === undefined) {
    return NextResponse.json({ error: "setting_value is required." }, { status: 400 });
  }

  const supabaseAdmin = createAdminClient();
  const { error } = await supabaseAdmin
    .from("system_settings")
    .update({ setting_value })
    .eq("setting_id", id);

  if (error) {
    return NextResponse.json({ error: error.message }, { status: 500 });
  }

  await supabaseAdmin.from("audit_logs").insert({
    user_id: admin.user.id,
    event_type: "admin_action",
    entity_type: "system_settings",
    entity_id: id,
    action: "dashboard_update_setting",
    new_values: { setting_value },
  });

  return NextResponse.json({ ok: true });
}
