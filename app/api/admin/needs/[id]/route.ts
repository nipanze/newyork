import { NextResponse } from "next/server";
import { requireAdmin } from "@/lib/supabase/require-admin";
import { createAdminClient } from "@/lib/supabase/admin";

export async function PATCH(request: Request, { params }: { params: Promise<{ id: string }> }) {
  const admin = await requireAdmin();
  if ("error" in admin) return admin.error;

  const { id } = await params;
  const body = await request.json().catch(() => ({}));
  const { action, reason } = body as { action?: "cancel" | "reactivate"; reason?: string };

  if (!action || !["cancel", "reactivate"].includes(action)) {
    return NextResponse.json({ error: "action must be 'cancel' or 'reactivate'." }, { status: 400 });
  }

  const supabaseAdmin = createAdminClient();
  const now = new Date().toISOString();

  const { data: need, error: fetchError } = await supabaseAdmin
    .from("needs_requests")
    .select("request_id, status")
    .eq("request_id", id)
    .single();

  if (fetchError || !need) {
    return NextResponse.json({ error: "Need request not found." }, { status: 404 });
  }

  const newStatus = action === "cancel" ? "cancelled" : "active";

  const { error: updateError } = await supabaseAdmin
    .from("needs_requests")
    .update({
      status: newStatus,
      cancelled_at: action === "cancel" ? now : null,
    })
    .eq("request_id", id);

  if (updateError) {
    return NextResponse.json({ error: updateError.message }, { status: 500 });
  }

  await supabaseAdmin.from("audit_logs").insert({
    user_id: admin.user.id,
    event_type: "admin_action",
    entity_type: "needs_requests",
    entity_id: id,
    action: `admin_${action}_need`,
    new_values: {
      action,
      reason: reason || null,
      updated_at: now,
    },
  });

  return NextResponse.json({ success: true, status: newStatus });
}

