import { NextResponse } from "next/server";
import { requireAdmin } from "@/lib/supabase/require-admin";
import { createAdminClient } from "@/lib/supabase/admin";

export async function PATCH(request: Request) {
  const admin = await requireAdmin();
  if ("error" in admin) return admin.error;

  const body = await request.json().catch(() => ({}));
  const { submission_id, decision, rejection_reason } = body as {
    submission_id?: string;
    decision?: "approve" | "reject";
    rejection_reason?: string;
  };

  if (!submission_id || !decision) {
    return NextResponse.json({ error: "submission_id and decision are required." }, { status: 400 });
  }

  if (decision !== "approve" && decision !== "reject") {
    return NextResponse.json({ error: "decision must be 'approve' or 'reject'." }, { status: 400 });
  }

  if (decision === "reject" && !rejection_reason?.trim()) {
    return NextResponse.json({ error: "A rejection reason is required when rejecting company verification." }, { status: 400 });
  }

  // Try RPC first
  const { error: rpcError } = await admin.supabase.rpc("admin_review_provider_company_document", {
    p_submission_id: submission_id,
    p_action: decision,
    p_reject_reason: rejection_reason?.trim() || null,
  });

  if (!rpcError) {
    return NextResponse.json({ success: true });
  }

  // Fallback: direct update with service client
  const supabaseAdmin = createAdminClient();
  const now = new Date().toISOString();

  const { data: updatedSubmission, error: updateError } = await supabaseAdmin
    .from("provider_company_verification_submissions")
    .update({
      status: decision === "approve" ? "approved" : "rejected",
      reject_reason: decision === "reject" ? rejection_reason?.trim() : null,
      reviewed_by: admin.user.id,
      reviewed_at: now,
      updated_at: now,
    })
    .eq("id", submission_id)
    .select("id")
    .maybeSingle();

  if (updateError) {
    return NextResponse.json({ error: updateError.message }, { status: 500 });
  }
  if (!updatedSubmission) {
    return NextResponse.json({ error: "Company document was not found." }, { status: 404 });
  }

  const { error: auditError } = await supabaseAdmin.from("audit_logs").insert({
    user_id: admin.user.id,
    event_type: "admin_action",
    entity_type: "provider_company_verification",
    action: `review_company_document_${decision}`,
    new_values: {
      submission_id,
      decision,
      rejection_reason: rejection_reason || null,
      reviewed_at: now,
    },
  });

  if (auditError) {
    return NextResponse.json({ error: auditError.message }, { status: 500 });
  }

  return NextResponse.json({ success: true });
}
