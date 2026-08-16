import { NextResponse } from "next/server";
import { createAdminClient } from "@/lib/supabase/admin";
import { requireAdmin } from "@/lib/supabase/require-admin";
import { PAYOUT_STATUS_OPTIONS } from "@/lib/admin/marketers";

const EVENT_BY_STATUS: Record<string, string> = {
  approved: "payout_approved",
  paid: "payout_completed",
  failed: "payout_failed",
};

export async function PATCH(request: Request, { params }: { params: Promise<{ id: string }> }) {
  const admin = await requireAdmin();
  if ("error" in admin) return admin.error;

  const { id } = await params;
  const body = await request.json().catch(() => ({}));
  const status = String(body.status ?? "");
  if (!PAYOUT_STATUS_OPTIONS.includes(status as any)) {
    return NextResponse.json({ error: "Invalid payout status." }, { status: 400 });
  }

  const supabase = createAdminClient();
  const { data: before } = await supabase.from("referral_payouts").select("*").eq("id", id).maybeSingle();
  const now = new Date().toISOString();
  const update: Record<string, unknown> = { status, updated_at: now };
  if (status === "approved") {
    update.approved_at = now;
    update.approved_by = admin.user.id;
  }
  if (status === "paid") update.completed_at = now;

  const { error } = await supabase.from("referral_payouts").update(update).eq("id", id);
  if (error) return NextResponse.json({ error: error.message }, { status: 500 });

  await supabase.from("audit_logs").insert({
    user_id: admin.user.id,
    event_type: EVENT_BY_STATUS[status] ?? "payout_updated",
    entity_type: "referral_payouts",
    entity_id: id,
    action: "dashboard_update_payout_status",
    previous_values: before ? { status: before.status } : null,
    new_values: update,
  });

  return NextResponse.json({ ok: true });
}
