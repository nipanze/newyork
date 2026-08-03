import { NextResponse } from "next/server";
import { requireAdmin } from "@/lib/supabase/require-admin";
import { createAdminClient } from "@/lib/supabase/admin";
import type { AccountStatus } from "@/lib/types";

const VALID_STATUSES: AccountStatus[] = [
  "active",
  "suspended",
  "pending_verification",
  "deactivated",
];

export async function PATCH(request: Request, { params }: { params: Promise<{ id: string }> }) {
  const admin = await requireAdmin();
  if ("error" in admin) return admin.error;

  const { id } = await params;
  const body = await request.json().catch(() => ({}));
  const { account_status, is_admin } = body as { account_status?: string; is_admin?: boolean };

  const update: Record<string, unknown> = {};

  if (account_status !== undefined) {
    if (!VALID_STATUSES.includes(account_status as AccountStatus)) {
      return NextResponse.json({ error: "Invalid account_status." }, { status: 400 });
    }
    update.account_status = account_status;
  }

  if (is_admin !== undefined) {
    if (typeof is_admin !== "boolean") {
      return NextResponse.json({ error: "is_admin must be a boolean." }, { status: 400 });
    }
    if (id === admin.user.id && is_admin === false) {
      return NextResponse.json({ error: "You cannot revoke your own admin access." }, { status: 400 });
    }
    update.is_admin = is_admin;
  }

  if (Object.keys(update).length === 0) {
    return NextResponse.json({ error: "No changes supplied." }, { status: 400 });
  }

  // Uses the service-role client because RLS on `profiles` only allows a
  // user to update their own row — the admin here is updating someone
  // else's. requireAdmin() already confirmed the caller is an admin.
  const supabaseAdmin = createAdminClient();
  const { error } = await supabaseAdmin.from("profiles").update(update).eq("id", id);

  if (error) {
    return NextResponse.json({ error: error.message }, { status: 500 });
  }

  await supabaseAdmin.from("audit_logs").insert({
    user_id: admin.user.id,
    event_type: "admin_action",
    entity_type: "profiles",
    entity_id: id,
    action: "dashboard_update_account",
    new_values: update,
  });

  return NextResponse.json({ ok: true });
}
