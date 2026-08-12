import { NextResponse } from "next/server";
import { requireAdmin } from "@/lib/supabase/require-admin";
import { createAdminClient } from "@/lib/supabase/admin";

const VALID_MODERATION_ACTIONS = ["cancel", "mark_review", "restore"] as const;
type ModerationAction = (typeof VALID_MODERATION_ACTIONS)[number];

const ACTION_STATUS: Record<ModerationAction, string> = {
  cancel: "cancelled",
  mark_review: "active", // keeps active but adds admin note
  restore: "active",
};

export async function PATCH(request: Request, { params }: { params: Promise<{ id: string }> }) {
  const admin = await requireAdmin();
  if ("error" in admin) return admin.error;

  const { id } = await params;
  const body = await request.json().catch(() => ({}));
  const { action, note } = body as { action?: string; note?: string };

  if (!action || !VALID_MODERATION_ACTIONS.includes(action as ModerationAction)) {
    return NextResponse.json(
      { error: `action must be one of: ${VALID_MODERATION_ACTIONS.join(", ")}` },
      { status: 400 }
    );
  }

  const supabaseAdmin = createAdminClient();

  const { data: loan, error: fetchError } = await supabaseAdmin
    .from("loan_requests")
    .select("id, status, title, borrower_id")
    .eq("id", id)
    .single();

  if (fetchError || !loan) {
    return NextResponse.json({ error: "Loan request not found." }, { status: 404 });
  }

  const typedAction = action as ModerationAction;
  const newStatus = ACTION_STATUS[typedAction];

  const update: Record<string, unknown> = {};
  if (typedAction === "cancel") {
    update.status = "cancelled";
  }
  // mark_review and restore don't change status but still write an audit record

  if (Object.keys(update).length > 0) {
    const { error } = await supabaseAdmin
      .from("loan_requests")
      .update(update)
      .eq("id", id);

    if (error) {
      return NextResponse.json({ error: error.message }, { status: 500 });
    }
  }

  await supabaseAdmin.from("audit_logs").insert({
    user_id: admin.user.id,
    event_type: "admin_moderation",
    entity_type: "loan_requests",
    entity_id: id,
    action: `dashboard_loan_${typedAction}`,
    description: note ?? null,
    new_values: Object.keys(update).length ? update : null,
  });

  return NextResponse.json({ ok: true });
}
