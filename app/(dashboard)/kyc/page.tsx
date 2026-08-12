import { createClient } from "@/lib/supabase/server";
import { Header } from "@/components/header";
import { Card, CardContent } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { KycReviewActions } from "@/components/kyc-review-actions";
import { KycDocumentViewer } from "@/components/kyc-document-viewer";
import { AdminFilterForm } from "@/components/admin-filter-form";
import { Pagination } from "@/components/pagination";
import { formatDateTime } from "@/lib/utils";
import Link from "next/link";
import {
  getPage,
  getPageSize,
  getParam,
  type DashboardSearchParams,
} from "@/lib/dashboard-filters";

export const dynamic = "force-dynamic";

const STATUS_VARIANT: Record<string, "confirm" | "signal" | "alert" | "neutral"> = {
  approved: "confirm",
  pending: "signal",
  rejected: "alert",
  expired: "neutral",
  not_submitted: "neutral",
};

export default async function KycPage({
  searchParams,
}: {
  searchParams: Promise<DashboardSearchParams>;
}) {
  const params = await searchParams;
  const supabase = await createClient();
  const page = getPage(params);
  const pageSize = getPageSize(params);

  const nameQ = getParam(params, "name");
  const countryQ = getParam(params, "country");
  const statusQ = getParam(params, "status") || "pending";
  const docTypeQ = getParam(params, "docType");
  const fromQ = getParam(params, "from");
  const toQ = getParam(params, "to");

  let query = supabase
    .from("kyc_verifications")
    .select(
      "id, user_id, national_id_type, national_id_number, national_id_front_url, national_id_back_url, selfie_url, submitted_at, reviewed_at, status, rejection_reason",
      { count: "exact" }
    )
    .order("submitted_at", { ascending: true });

  if (statusQ) query = query.eq("status", statusQ);
  if (docTypeQ) query = query.ilike("national_id_type", `%${docTypeQ}%`);
  if (fromQ) query = query.gte("submitted_at", `${fromQ}T00:00:00.000Z`);
  if (toQ) query = query.lte("submitted_at", `${toQ}T23:59:59.999Z`);

  const from = (page - 1) * pageSize;
  const { data: pending, count } = await query.range(from, from + pageSize - 1);

  const userIds = (pending ?? []).map((k) => k.user_id);

  // Fetch profiles — filter by name/country if specified
  let profiles: { id: string; full_name: string | null; country: string; phone: string | null }[] = [];
  if (userIds.length) {
    let profileQuery = supabase
      .from("profiles")
      .select("id, full_name, country, phone")
      .in("id", userIds);
    if (countryQ) profileQuery = profileQuery.eq("country", countryQ);
    if (nameQ) profileQuery = profileQuery.ilike("full_name", `%${nameQ}%`);
    const { data } = await profileQuery;
    profiles = data ?? [];
  }

  const profileById = new Map((profiles).map((p) => [p.id, p]));

  // If name/country filters applied, only show KYC whose user matched
  const filteredKyc = (nameQ || countryQ)
    ? (pending ?? []).filter((k) => profileById.has(k.user_id))
    : (pending ?? []);

  const { data: countries } = await supabase.from("countries").select("code, name").order("code");
  const countryOptions = [
    { label: "All countries", value: "" },
    ...((countries ?? []).map((c) => ({ label: `${c.name} (${c.code})`, value: c.code }))),
  ];

  const total = (nameQ || countryQ) ? filteredKyc.length : (count ?? 0);

  return (
    <>
      <Header title="KYC review" description="Identity verification submissions" />
      <main className="flex-1 space-y-4 overflow-y-auto p-6">
        <AdminFilterForm
          resetHref="/kyc"
          searchParams={params}
          fields={[
            { name: "name", label: "Applicant name", placeholder: "Full name" },
            { name: "country", label: "Country", type: "select", options: countryOptions },
            {
              name: "status",
              label: "Status",
              type: "select",
              options: [
                { label: "Pending", value: "pending" },
                { label: "Approved", value: "approved" },
                { label: "Rejected", value: "rejected" },
                { label: "Expired", value: "expired" },
                { label: "All statuses", value: "" },
              ],
            },
            {
              name: "docType",
              label: "Document type",
              placeholder: "e.g. national_id",
            },
            { name: "from", label: "Submitted from", type: "date" },
            { name: "to", label: "Submitted to", type: "date" },
          ]}
        />

        <div className="space-y-3">
          {filteredKyc.length ? (
            filteredKyc.map((k) => {
              const profile = profileById.get(k.user_id);
              return (
                <Card key={k.id}>
                  <CardContent className="flex flex-wrap items-start justify-between gap-4 p-4">
                    <div className="flex-1 space-y-2">
                      <div>
                        <Link
                          href={`/kyc/${k.id}`}
                          className="font-medium text-ink-900 hover:underline"
                        >
                          {profile?.full_name ?? k.user_id}
                        </Link>
                        <p className="text-xs text-ink-500">
                          {profile?.country ?? "—"} · {profile?.phone ?? "no phone"} ·{" "}
                          {k.national_id_type ?? "ID type not set"} ·{" "}
                          {k.national_id_number ?? "no ID number"}
                        </p>
                        <p className="mt-0.5 text-xs text-ink-500">
                          Submitted {formatDateTime(k.submitted_at)}
                          {k.reviewed_at ? ` · Reviewed ${formatDateTime(k.reviewed_at)}` : ""}
                        </p>
                        {k.rejection_reason && (
                          <p className="mt-0.5 text-xs text-clay-alert">
                            Rejection reason: {k.rejection_reason}
                          </p>
                        )}
                      </div>
                      <KycDocumentViewer
                        frontUrl={k.national_id_front_url}
                        backUrl={k.national_id_back_url}
                        selfieUrl={k.selfie_url}
                      />
                    </div>
                    <div className="flex flex-col items-end gap-3 pt-1">
                      <Badge variant={STATUS_VARIANT[k.status] ?? "neutral"}>{k.status}</Badge>
                      <div className="flex items-center gap-2">
                        <Link
                          href={`/kyc/${k.id}`}
                          className="text-xs font-medium text-ink-700 hover:underline"
                        >
                          Open detail
                        </Link>
                        {profile && (
                          <Link
                            href={`/users/${profile.id}`}
                            className="text-xs font-medium text-ink-700 hover:underline"
                          >
                            View account
                          </Link>
                        )}
                      </div>
                      {k.status === "pending" && <KycReviewActions kycId={k.id} />}
                    </div>
                  </CardContent>
                </Card>
              );
            })
          ) : (
            <Card>
              <CardContent className="py-10 text-center text-sm text-ink-500">
                No KYC submissions match this filter.
              </CardContent>
            </Card>
          )}
        </div>

        <Pagination
          page={page}
          pageSize={pageSize}
          total={total}
          searchParams={params}
          basePath="/kyc"
        />
      </main>
    </>
  );
}
