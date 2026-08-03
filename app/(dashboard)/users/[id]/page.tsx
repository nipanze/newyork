import { createClient } from "@/lib/supabase/server";
import { Header } from "@/components/header";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { AccountActions } from "@/components/account-actions";
import { formatAmount, formatDateTime } from "@/lib/utils";
import { notFound } from "next/navigation";

export const dynamic = "force-dynamic";

export default async function UserDetailPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const supabase = await createClient();

  const [{ data: profile }, { data: subscription }, { data: kyc }, { data: loans }, { data: trust }] =
    await Promise.all([
      supabase.from("profiles").select("*").eq("id", id).single(),
      supabase.from("subscriptions").select("*").eq("user_id", id).eq("status", "active").maybeSingle(),
      supabase.from("kyc_verifications").select("*").eq("user_id", id).maybeSingle(),
      supabase
        .from("loan_requests")
        .select("id, title, status, requested_amount, country, listed_at")
        .eq("borrower_id", id)
        .order("listed_at", { ascending: false })
        .limit(5),
      supabase.from("v_trust_profile_public").select("*").eq("user_id", id).maybeSingle(),
    ]);

  if (!profile) notFound();

  return (
    <>
      <Header title={profile.full_name ?? "Unnamed account"} description={id} />
      <main className="flex-1 space-y-6 overflow-y-auto p-6">
        <div className="grid grid-cols-1 gap-6 lg:grid-cols-3">
          <Card className="lg:col-span-2">
            <CardHeader>
              <CardTitle>Profile</CardTitle>
            </CardHeader>
            <CardContent className="grid grid-cols-2 gap-4 pt-0 text-sm">
              <Field label="Phone" value={profile.phone ?? "—"} />
              <Field
                label="Phone verified"
                value={profile.phone_verified_at ? formatDateTime(profile.phone_verified_at) : "Not verified"}
              />
              <Field label="Country" value={profile.country} />
              <Field label="District" value={profile.district ?? "—"} />
              <Field label="Employment" value={profile.employment_type ?? "—"} />
              <Field label="Employer" value={profile.employer_name ?? "—"} />
              <Field
                label="Monthly income"
                value={formatAmount(profile.monthly_income, profile.income_currency)}
              />
              <Field label="Plan" value={subscription?.plan ?? "free"} />
              <Field label="Free unlocks left" value={String(profile.free_unlocks_remaining)} />
              <Field label="Joined" value={formatDateTime(profile.created_at)} />
            </CardContent>
          </Card>

          <Card>
            <CardHeader>
              <CardTitle>Actions</CardTitle>
            </CardHeader>
            <CardContent className="pt-0">
              <AccountActions
                userId={profile.id}
                currentStatus={profile.account_status}
                currentPlan={subscription?.plan ?? "free"}
                isAdmin={profile.is_admin}
              />
            </CardContent>
          </Card>
        </div>

        <div className="grid grid-cols-1 gap-6 lg:grid-cols-2">
          <Card>
            <CardHeader>
              <CardTitle>KYC</CardTitle>
            </CardHeader>
            <CardContent className="space-y-2 pt-0 text-sm">
              {kyc ? (
                <>
                  <Field label="Status" value={<Badge variant="neutral">{kyc.status}</Badge>} />
                  <Field label="ID type" value={kyc.national_id_type ?? "—"} />
                  <Field label="Submitted" value={formatDateTime(kyc.submitted_at)} />
                  <Field label="Reviewed" value={formatDateTime(kyc.reviewed_at)} />
                </>
              ) : (
                <p className="text-ink-500">No KYC submission on file.</p>
              )}
            </CardContent>
          </Card>

          <Card>
            <CardHeader>
              <CardTitle>Trust signals</CardTitle>
            </CardHeader>
            <CardContent className="space-y-2 pt-0 text-sm">
              <Field label="Rating" value={trust?.rating_avg ? `${trust.rating_avg} / 5` : "No reviews yet"} />
              <Field label="Completed deals" value={String(trust?.completed_deals_count ?? 0)} />
              <Field label="Repeat participant" value={trust?.is_repeat_participant ? "Yes" : "No"} />
              <Field label="Response time" value={trust?.response_time_bucket ?? "—"} />
            </CardContent>
          </Card>
        </div>

        <Card>
          <CardHeader>
            <CardTitle>Recent loan requests</CardTitle>
          </CardHeader>
          <CardContent className="space-y-2 pt-0">
            {loans?.length ? (
              loans.map((loan) => (
                <div
                  key={loan.id}
                  className="flex items-center justify-between rounded-md border border-paper-200 px-3 py-2.5 text-sm"
                >
                  <span className="font-medium text-ink-900">{loan.title}</span>
                  <span className="font-tabular text-ink-700">
                    {formatAmount(loan.requested_amount, undefined)}
                  </span>
                  <Badge variant="neutral">{loan.status}</Badge>
                </div>
              ))
            ) : (
              <p className="text-sm text-ink-500">No loan requests posted.</p>
            )}
          </CardContent>
        </Card>
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
