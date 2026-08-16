import { NextResponse } from "next/server";
import { createAdminClient } from "@/lib/supabase/admin";
import { requireAdmin } from "@/lib/supabase/require-admin";
import { CAMPAIGN_STATUS_OPTIONS } from "@/lib/admin/marketers";

export async function PATCH(request: Request, { params }: { params: Promise<{ id: string }> }) {
  const admin = await requireAdmin();
  if ("error" in admin) return admin.error;

  const { id } = await params;
  const body = await request.json().catch(() => ({}));
  const status = String(body.status ?? "");
  if (!CAMPAIGN_STATUS_OPTIONS.includes(status as any)) {
    return NextResponse.json({ error: "Invalid campaign status." }, { status: 400 });
  }

  const supabase = createAdminClient();
  const { data: before } = await supabase.from("referral_campaigns").select("*").eq("id", id).maybeSingle();
  const { error } = await supabase
    .from("referral_campaigns")
    .update({ status, updated_at: new Date().toISOString() })
    .eq("id", id);
  if (error) return NextResponse.json({ error: error.message }, { status: 500 });

  await supabase.from("audit_logs").insert({
    user_id: admin.user.id,
    event_type: status === "active" ? "campaign_activated" : status === "deactivated" ? "campaign_deactivated" : "campaign_updated",
    entity_type: "referral_campaigns",
    entity_id: id,
    action: "dashboard_update_campaign_status",
    previous_values: before ? { status: before.status } : null,
    new_values: { status },
  });

  return NextResponse.json({ ok: true });
}
