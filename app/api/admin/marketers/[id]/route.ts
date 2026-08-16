import { NextResponse } from "next/server";
import { createAdminClient } from "@/lib/supabase/admin";
import { requireAdmin } from "@/lib/supabase/require-admin";
import { MARKETER_STATUS_OPTIONS } from "@/lib/admin/marketers";

export async function PATCH(request: Request, { params }: { params: Promise<{ id: string }> }) {
  const admin = await requireAdmin();
  if ("error" in admin) return admin.error;

  const { id } = await params;
  const body = await request.json().catch(() => ({}));
  const status = String(body.status ?? "");

  if (!MARKETER_STATUS_OPTIONS.includes(status as any)) {
    return NextResponse.json({ error: "Invalid marketer status." }, { status: 400 });
  }

  const supabase = createAdminClient();
  const { data: before } = await supabase.from("referral_marketers").select("*").eq("id", id).maybeSingle();
  const { error } = await supabase
    .from("referral_marketers")
    .update({ status, updated_at: new Date().toISOString(), last_activity_at: new Date().toISOString() })
    .eq("id", id);

  if (error) return NextResponse.json({ error: error.message }, { status: 500 });

  await supabase.from("audit_logs").insert({
    user_id: admin.user.id,
    event_type: status === "active" ? "marketer_activated" : `marketer_${status}`,
    entity_type: "referral_marketers",
    entity_id: id,
    action: "dashboard_update_marketer_status",
    previous_values: before ? { status: before.status } : null,
    new_values: { status },
  });

  return NextResponse.json({ ok: true });
}
