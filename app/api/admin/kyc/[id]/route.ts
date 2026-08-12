import { NextResponse } from "next/server";
import { requireAdmin } from "@/lib/supabase/require-admin";
import { createAdminClient } from "@/lib/supabase/admin";

export async function PATCH(request: Request, { params }: { params: Promise<{ id: string }> }) {
  const admin = await requireAdmin();
  if ("error" in admin) return admin.error;

  const { id } = await params;
  const body = await request.json().catch(() => ({}));
  const { decision, rejection_reason } = body as {
    decision?: "approve" | "reject" | "expire";
    rejection_reason?: string;
  };

  if (decision !== "approve" && decision !== "reject" && decision !== "expire") {
    return NextResponse.json({ error: "decision must be 'approve', 'reject', or 'expire'." }, { status: 400 });
  }

  const supabaseAdmin = createAdminClient();

  const { data: kyc, error: fetchError } = await supabaseAdmin
    .from("kyc_verifications")
    .select("id, submitted_at")
    .eq("id", id)
    .single();

  if (fetchError || !kyc) {
    return NextResponse.json({ error: "KYC record not found." }, { status: 404 });
  }

  const newStatus = decision === "approve" ? "approved" : decision === "reject" ? "rejected" : "expired";
  const expiresAt =
    decision === "approve"
      ? new Date(new Date().setMonth(new Date().getMonth() + 12)).toISOString()
      : null;

  const { error } = await supabaseAdmin
    .from("kyc_verifications")
    .update({
      status: newStatus,
      id_verified: decision === "approve",
      selfie_verified: decision === "approve",
      verified_by: admin.user.id,
      rejection_reason: decision === "reject" ? rejection_reason ?? null : null,
      reviewed_at: new Date().toISOString(),
      expires_at: expiresAt,
    })
    .eq("id", id);

  if (error) {
    return NextResponse.json({ error: error.message }, { status: 500 });
  }

  await supabaseAdmin.from("audit_logs").insert({
    user_id: admin.user.id,
    event_type: decision === "approve" ? "kyc_approved" : decision === "reject" ? "kyc_rejected" : "kyc_expired",
    entity_type: "kyc_verifications",
    entity_id: id,
    action: `dashboard_${decision}_kyc`,
  });

  return NextResponse.json({ ok: true });
}
