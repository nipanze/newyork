import { NextResponse } from "next/server";
import { requireAdmin } from "@/lib/supabase/require-admin";
import { createAdminClient } from "@/lib/supabase/admin";

export async function POST(request: Request) {
  const admin = await requireAdmin();
  if ("error" in admin) return admin.error;

  const body = await request.json().catch(() => ({}));
  const { bucket, path } = body as { bucket?: string; path?: string };

  if (!bucket || !path) {
    return NextResponse.json({ error: "bucket and path are required" }, { status: 400 });
  }

  // Allowed verification buckets
  const allowedBuckets = ["provider-evidence", "verification-documents"];
  if (!allowedBuckets.includes(bucket)) {
    return NextResponse.json({ error: "Unauthorized bucket access" }, { status: 403 });
  }

  const supabaseAdmin = createAdminClient();
  const { data, error } = await supabaseAdmin.storage
    .from(bucket)
    .createSignedUrl(path.replace(/^\/+/, ""), 3600);

  if (error || !data?.signedUrl) {
    return NextResponse.json({ error: error?.message || "Failed to generate signed URL" }, { status: 500 });
  }

  return NextResponse.json({ signedUrl: data.signedUrl });
}
