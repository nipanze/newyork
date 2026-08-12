import { NextResponse } from "next/server";
import { requireAdmin } from "@/lib/supabase/require-admin";
import { createAdminClient } from "@/lib/supabase/admin";

const VALID_MODERATION_ACTIONS = ["cancel", "mark_review", "restore"] as const;
type ModerationAction = (typeof VALID_MODERATION_ACTIONS)[number];

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

  const { data: req, error: fetchError } = await (supabaseAdmin as any)
    .from("forex_requests")
    .select("id, status, country")
    .eq("id", id)
    .single();

  if (fetchError || !req) {
    return NextResponse.json({ error: "Forex request not found." }, { status: 404 });
  }

  const typedAction = action as ModerationAction;
  const update: Record<string, unknown> = {};

  if (typedAction === "cancel") {
    update.status = "cancelled";
  }

  if (Object.keys(update).length > 0) {
    const { error } = await (supabaseAdmin as any)
      .from("forex_requests")
      .update(update)
      .eq("id", id);

    if (error) {
      return NextResponse.json({ error: error.message }, { status: 500 });
    }
  }

  await supabaseAdmin.from("audit_logs").insert({
    user_id: admin.user.id,
    event_type: "admin_moderation",
    entity_type: "forex_requests",
    entity_id: id,
    action: `dashboard_forex_${typedAction}`,
    description: note ?? null,
    new_values: Object.keys(update).length ? update : null,
  });

  return NextResponse.json({ ok: true });
}
