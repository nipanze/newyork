import { createClient } from "@/lib/supabase/server";
import { Header } from "@/components/header";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { KycReviewActions } from "@/components/kyc-review-actions";
import { KycDocumentViewer } from "@/components/kyc-document-viewer";
import { formatDateTime } from "@/lib/utils";
import { notFound } from "next/navigation";
import Link from "next/link";

export const dynamic = "force-dynamic";

export default async function KycDetailPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const supabase = await createClient();

  const { data: kyc } = await supabase
    .from("kyc_verifications")
    .select("*")
    .eq("id", id)
    .single();

  if (!kyc) notFound();

  const { data: profile } = await supabase
    .from("profiles")
    .select("id, full_name, country, district, phone")
    .eq("id", kyc.user_id)
    .single();

  const statusVariant: Record<string, "confirm" | "signal" | "neutral" | "alert"> = {
    approved: "confirm",
    pending: "signal",
    rejected: "alert",
    expired: "neutral",
    not_submitted: "neutral",
  };

  return (
    <>
      <Header
        title={`KYC — ${profile?.full_name ?? kyc.user_id}`}
        description={`Submission ${id.slice(0, 8)}…`}
      />
      <main className="flex-1 space-y-6 overflow-y-auto p-6">
        <div className="grid grid-cols-1 gap-6 lg:grid-cols-3">
          {/* Details */}
          <Card className="lg:col-span-2">
            <CardHeader>
              <CardTitle>Verification details</CardTitle>
            </CardHeader>
            <CardContent className="grid grid-cols-2 gap-4 pt-0 text-sm">
              <Field label="Status" value={<Badge variant={statusVariant[kyc.status] ?? "neutral"}>{kyc.status}</Badge>} />
              <Field label="ID type" value={kyc.national_id_type ?? "—"} />
              <Field label="ID number" value={kyc.national_id_number ?? "—"} />
              <Field label="ID verified" value={kyc.id_verified ? "Yes" : "No"} />
              <Field label="Selfie verified" value={kyc.selfie_verified ? "Yes" : "No"} />
              <Field label="Submitted" value={formatDateTime(kyc.submitted_at)} />
              <Field label="Reviewed" value={formatDateTime(kyc.reviewed_at)} />
              <Field label="Expires" value={formatDateTime(kyc.expires_at)} />
              {kyc.rejection_reason && (
                <Field label="Rejection reason" value={kyc.rejection_reason} />
              )}
              {kyc.verification_notes && (
                <Field label="Notes" value={kyc.verification_notes} />
              )}
            </CardContent>
          </Card>

          {/* User */}
          <Card>
            <CardHeader>
              <CardTitle>User</CardTitle>
            </CardHeader>
            <CardContent className="space-y-2 pt-0 text-sm">
              {profile ? (
                <>
                  <Link href={`/users/${profile.id}`} className="font-medium text-ink-900 hover:underline">
                    {profile.full_name ?? profile.id}
                  </Link>
                  <p className="text-ink-500">{profile.country}{profile.district ? ` · ${profile.district}` : ""}</p>
                  <p className="text-ink-500">{profile.phone ?? "No phone"}</p>
                </>
              ) : (
                <p className="text-ink-500">—</p>
              )}
            </CardContent>
          </Card>
        </div>

        {/* Documents */}
        <Card>
          <CardHeader>
            <CardTitle>Documents</CardTitle>
          </CardHeader>
          <CardContent className="pt-0">
            <KycDocumentViewer
              frontUrl={kyc.national_id_front_url}
              backUrl={kyc.national_id_back_url}
              selfieUrl={kyc.selfie_url}
            />
          </CardContent>
        </Card>

        {/* Actions (only if pending) */}
        {kyc.status === "pending" && (
          <Card>
            <CardHeader>
              <CardTitle>Review decision</CardTitle>
            </CardHeader>
            <CardContent className="pt-0">
              <KycReviewActions kycId={kyc.id} />
            </CardContent>
          </Card>
        )}
      </main>
    </>
  );
}

function Field({ label, value }: { label: string; value: React.ReactNode }) {
  return (
    <div>
      <p className="text-xs font-medium uppercase tracking-wide text-ink-500">{label}</p>
      <div className="mt-0.5 text-ink-900">{value}</div>
    </div>
  );
}
