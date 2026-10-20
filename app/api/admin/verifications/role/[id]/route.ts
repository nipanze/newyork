import { NextResponse } from "next/server";
import { requireAdmin } from "@/lib/supabase/require-admin";
import { createAdminClient } from "@/lib/supabase/admin";

export async function PATCH(request: Request, { params }: { params: Promise<{ id: string }> }) {
  const admin = await requireAdmin();
  if ("error" in admin) return admin.error;

  const { id } = await params;
  const body = await request.json().catch(() => ({}));
  const { decision, rejection_reason, expires_at } = body as {
    decision?: "approve" | "reject" | "expire";
    rejection_reason?: string;
    expires_at?: string | null;
  };

  if (!decision || !["approve", "reject", "expire"].includes(decision)) {
    return NextResponse.json({ error: "decision must be 'approve', 'reject', or 'expire'." }, { status: 400 });
  }

  if (decision === "reject" && !rejection_reason?.trim()) {
    return NextResponse.json({ error: "A rejection reason is required when rejecting a role claim." }, { status: 400 });
  }

  // Try RPC first
  const { error: rpcError } = await admin.supabase.rpc("admin_review_provider_role_qualification", {
    p_claim_id: id,
    p_action: decision,
    p_reject_reason: rejection_reason?.trim() || null,
    p_expires_at: expires_at || null,
  });

  if (!rpcError) {
    return NextResponse.json({ success: true });
  }

  // Fallback: direct update
  const supabaseAdmin = createAdminClient();
  const now = new Date().toISOString();

  const { error: updateError } = await supabaseAdmin
    .from("provider_role_qualification_claims")
    .update({
      status: decision === "approve" ? "approved" : decision === "reject" ? "rejected" : "expired",
      reject_reason: decision === "reject" ? rejection_reason?.trim() : null,
      expires_at: decision === "approve" ? expires_at ?? null : null,
      reviewed_by: admin.user.id,
      reviewed_at: now,
      updated_at: now,
    })
    .eq("id", id);

  if (updateError) {
    return NextResponse.json({ error: updateError.message }, { status: 500 });
  }

  await supabaseAdmin.from("audit_logs").insert({
    user_id: admin.user.id,
    event_type: "admin_action",
    entity_type: "provider_role_qualification_claim",
    entity_id: id,
    action: `review_role_claim_${decision}`,
    new_values: {
      decision,
      rejection_reason: rejection_reason || null,
      reviewed_at: now,
    },
  });

  return NextResponse.json({ success: true });
}

