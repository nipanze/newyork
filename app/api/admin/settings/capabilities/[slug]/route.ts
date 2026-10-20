import { NextResponse } from "next/server";
import { requireAdmin } from "@/lib/supabase/require-admin";
import { createAdminClient } from "@/lib/supabase/admin";

export async function PATCH(request: Request, { params }: { params: Promise<{ slug: string }> }) {
  const admin = await requireAdmin();
  if ("error" in admin) return admin.error;

  const { slug } = await params;
  const body = await request.json().catch(() => ({}));
  const { verification_policy, is_active } = body as {
    verification_policy?: "open" | "optional_proof" | "required_proof";
    is_active?: boolean;
  };

  const supabaseAdmin = createAdminClient();
  const updates: Record<string, unknown> = {};

  if (verification_policy) {
    if (!["open", "optional_proof", "required_proof"].includes(verification_policy)) {
      return NextResponse.json({ error: "Invalid verification policy." }, { status: 400 });
    }
    updates.verification_policy = verification_policy;
  }

  if (typeof is_active === "boolean") {
    updates.is_active = is_active;
  }

  if (Object.keys(updates).length === 0) {
    return NextResponse.json({ error: "No fields to update." }, { status: 400 });
  }

  const { error } = await supabaseAdmin
    .from("need_capabilities")
    .update(updates)
    .eq("slug", slug);

  if (error) {
    return NextResponse.json({ error: error.message }, { status: 500 });
  }

  await supabaseAdmin.from("audit_logs").insert({
    user_id: admin.user.id,
    event_type: "admin_action",
    entity_type: "need_capabilities",
    entity_id: slug,
    action: "update_capability_policy",
    new_values: updates,
  });

  return NextResponse.json({ success: true });
}

