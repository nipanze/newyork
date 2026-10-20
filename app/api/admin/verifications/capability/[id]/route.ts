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
    return NextResponse.json({ error: "A rejection reason is required when rejecting evidence." }, { status: 400 });
  }

  const supabaseAdmin = createAdminClient();

  // Try calling the RPC first using the authenticated admin's client
  const { error: rpcError } = await admin.supabase.rpc("admin_review_provider_capability_evidence", {
    p_evidence_id: id,
    p_action: decision,
    p_reject_reason: rejection_reason?.trim() || null,
    p_expires_at: expires_at || null,
  });

  if (!rpcError) {
    return NextResponse.json({ success: true });
  }

  // Fallback: If RPC does not exist or fails, apply updates using supabaseAdmin
  const { data: evidence, error: fetchError } = await supabaseAdmin
    .from("provider_capability_evidence")
    .select("id, provider_capability_id, requirement_key, status")
    .eq("id", id)
    .single();

  if (fetchError || !evidence) {
    return NextResponse.json({ error: "Provider capability evidence not found." }, { status: 404 });
  }

  const newStatus = decision === "approve" ? "approved" : decision === "reject" ? "rejected" : "expired";
  const now = new Date().toISOString();

  const { error: updateError } = await supabaseAdmin
    .from("provider_capability_evidence")
    .update({
      status: newStatus,
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

  // If approved, update provider capability verification_level & active status
  if (decision === "approve") {
    await supabaseAdmin
      .from("provider_capabilities")
      .update({
        verification_level: "provider_verified",
        is_active: true,
        verified_by: admin.user.id,
        verified_at: now,
      })
      .eq("id", evidence.provider_capability_id);
  }

  // Audit log
  await supabaseAdmin.from("audit_logs").insert({
    user_id: admin.user.id,
    event_type: "admin_action",
    entity_type: "provider_capability_evidence",
    entity_id: id,
    action: `review_evidence_${decision}`,
    new_values: {
      provider_capability_id: evidence.provider_capability_id,
      requirement_key: evidence.requirement_key,
      decision,
      rejection_reason: rejection_reason || null,
      reviewed_at: now,
    },
  });

  return NextResponse.json({ success: true });
}

