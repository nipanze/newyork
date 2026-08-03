import { NextResponse } from "next/server";
import { requireAdmin } from "@/lib/supabase/require-admin";
import { createAdminClient } from "@/lib/supabase/admin";
import type { SubscriptionPlan } from "@/lib/types";

const VALID_PLANS: SubscriptionPlan[] = ["free", "lender", "pro"];

export async function PATCH(request: Request, { params }: { params: Promise<{ id: string }> }) {
  const admin = await requireAdmin();
  if ("error" in admin) return admin.error;

  const { id: userId } = await params;
  const body = await request.json().catch(() => ({}));
  const { plan } = body as { plan?: string };

  if (!plan || !VALID_PLANS.includes(plan as SubscriptionPlan)) {
    return NextResponse.json({ error: "Invalid plan specified." }, { status: 400 });
  }

  const supabaseAdmin = createAdminClient();

  // Mark any existing active subscription as cancelled
  await supabaseAdmin
    .from("subscriptions")
    .update({ status: "cancelled" })
    .eq("user_id", userId)
    .eq("status", "active");

  // Insert new active subscription
  const { error } = await supabaseAdmin.from("subscriptions").insert({
    user_id: userId,
    plan: plan as SubscriptionPlan,
    status: "active",
    started_at: new Date().toISOString(),
    amount_minor_units: 0,
    auto_renew: true,
  });

  if (error) {
    return NextResponse.json({ error: error.message }, { status: 500 });
  }

  await supabaseAdmin.from("audit_logs").insert({
    user_id: admin.user.id,
    event_type: "admin_action",
    entity_type: "subscriptions",
    entity_id: userId,
    action: "dashboard_update_user_plan",
    new_values: { plan },
  });

  return NextResponse.json({ ok: true });
}
