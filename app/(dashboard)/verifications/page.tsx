import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import { Header } from "@/components/header";
import { Card, CardContent } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { AdminFilterForm } from "@/components/admin-filter-form";
import { Pagination } from "@/components/pagination";
import { ProviderDocumentViewer } from "@/components/provider-document-viewer";
import { ProviderReviewActions } from "@/components/provider-review-actions";
import { formatDateTime } from "@/lib/utils";
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
};

export default async function VerificationsPage({
  searchParams,
}: {
  searchParams: Promise<DashboardSearchParams>;
}) {
  const params = await searchParams;
  const supabase = await createClient();
  const page = getPage(params);
  const pageSize = getPageSize(params);

  const activeTab = getParam(params, "tab") || "evidence";
  const statusQ = getParam(params, "status") || "pending";
  const from = (page - 1) * pageSize;

  const {
    data: { user },
  } = await supabase.auth.getUser();

  const { data: adminProfile } = await supabase
    .from("profiles")
    .select("full_name")
    .eq("id", user?.id ?? "")
    .single();

  // Metrics: counts of pending submissions
  const [{ count: pendingEvidenceCount }, { count: pendingCompanyCount }, { count: pendingRolesCount }] =
    await Promise.all([
      supabase.from("provider_capability_evidence").select("*", { count: "exact", head: true }).eq("status", "pending"),
      supabase.from("provider_company_verification_submissions").select("*", { count: "exact", head: true }).eq("status", "pending"),
      supabase.from("provider_role_qualification_claims").select("*", { count: "exact", head: true }).eq("status", "pending"),
    ]);

  let evidenceRows: any[] = [];
  let companyRows: any[] = [];
  let roleRows: any[] = [];
  let totalCount = 0;

  if (activeTab === "evidence") {
    let query = supabase
      .from("provider_capability_evidence")
      .select(
        `
        id, provider_capability_id, requirement_key, file_url, status,
        provider_type, reject_reason, expires_at, reviewed_at, created_at,
        provider_capabilities!inner (
          id, user_id, capability_slug,
          need_capabilities ( name, category_slug ),
          profiles ( id, full_name, phone, country )
        )
      `,
        { count: "exact" }
      )
      .order("created_at", { ascending: false });

    if (statusQ && statusQ !== "all") {
      query = query.eq("status", statusQ);
    }

    const { data, count } = await query.range(from, from + pageSize - 1);
    evidenceRows = data || [];
    totalCount = count || 0;
  } else if (activeTab === "company") {
    let query = supabase
      .from("provider_company_verification_submissions")
      .select(
        `
        user_id, category_slug, document_type, file_path, status,
        reject_reason, reviewed_at, created_at,
        profiles ( id, full_name, phone, country ),
        need_categories ( name, icon )
      `,
        { count: "exact" }
      )
      .order("created_at", { ascending: false });

    if (statusQ && statusQ !== "all") {
      query = query.eq("status", statusQ);
    }

    const { data, count } = await query.range(from, from + pageSize - 1);
    companyRows = data || [];
    totalCount = count || 0;
  } else if (activeTab === "roles") {
    let query = supabase
      .from("provider_role_qualification_claims")
      .select(
        `
        id, provider_capability_id, claim_key, evidence_url, status,
        reject_reason, expires_at, reviewed_at, created_at,
        provider_capabilities!inner (
          id, user_id, capability_slug,
          need_capabilities ( name ),
          profiles ( id, full_name, phone, country )
        )
      `,
        { count: "exact" }
      )
      .order("created_at", { ascending: false });

    if (statusQ && statusQ !== "all") {
      query = query.eq("status", statusQ);
    }

    const { data, count } = await query.range(from, from + pageSize - 1);
    roleRows = data || [];
    totalCount = count || 0;
  }

  return (
    <div className="flex-1 space-y-6 p-6">
      <Header
        title="Provider verification review"
        description="Verify individual capability proof, company documents, and role qualifications per policy."
        adminName={adminProfile?.full_name}
      />

      {/* Metric Cards */}
      <div className="grid gap-4 md:grid-cols-3">
        <Link href="/verifications?tab=evidence&status=pending">
          <Card className={`transition-colors hover:border-ink-400 ${activeTab === "evidence" ? "border-ink-800" : ""}`}>
            <CardContent className="pt-6">
              <div className="flex items-center justify-between">
                <span className="text-sm font-medium text-ink-600">Capability Evidence</span>
                {(pendingEvidenceCount ?? 0) > 0 && (
                  <Badge variant="signal">{pendingEvidenceCount} Pending</Badge>
                )}
              </div>
              <p className="mt-2 text-2xl font-bold text-ink-950">{pendingEvidenceCount ?? 0}</p>
              <p className="text-xs text-ink-500">Individual provider capability proof</p>
            </CardContent>
          </Card>
        </Link>

        <Link href="/verifications?tab=company&status=pending">
          <Card className={`transition-colors hover:border-ink-400 ${activeTab === "company" ? "border-ink-800" : ""}`}>
            <CardContent className="pt-6">
              <div className="flex items-center justify-between">
                <span className="text-sm font-medium text-ink-600">Company Documents</span>
                {(pendingCompanyCount ?? 0) > 0 && (
                  <Badge variant="signal">{pendingCompanyCount} Pending</Badge>
                )}
              </div>
              <p className="mt-2 text-2xl font-bold text-ink-950">{pendingCompanyCount ?? 0}</p>
              <p className="text-xs text-ink-500">Registration & business licences</p>
            </CardContent>
          </Card>
        </Link>

        <Link href="/verifications?tab=roles&status=pending">
          <Card className={`transition-colors hover:border-ink-400 ${activeTab === "roles" ? "border-ink-800" : ""}`}>
            <CardContent className="pt-6">
              <div className="flex items-center justify-between">
                <span className="text-sm font-medium text-ink-600">Role Qualifications</span>
                {(pendingRolesCount ?? 0) > 0 && (
                  <Badge variant="signal">{pendingRolesCount} Pending</Badge>
                )}
              </div>
              <p className="mt-2 text-2xl font-bold text-ink-950">{pendingRolesCount ?? 0}</p>
              <p className="text-xs text-ink-500">Specialized role claims & certificates</p>
            </CardContent>
          </Card>
        </Link>
      </div>

      {/* Tabs & Filters */}
      <div className="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between border-b border-paper-300 pb-3">
        <div className="flex gap-2">
          <Link
            href={`/verifications?tab=evidence&status=${statusQ}`}
            className={`rounded-md px-3 py-1.5 text-sm font-medium transition-colors ${
              activeTab === "evidence"
                ? "bg-ink-900 text-white"
                : "text-ink-600 hover:bg-paper-200"
            }`}
          >
            Capability Evidence ({pendingEvidenceCount ?? 0})
          </Link>
          <Link
            href={`/verifications?tab=company&status=${statusQ}`}
            className={`rounded-md px-3 py-1.5 text-sm font-medium transition-colors ${
              activeTab === "company"
                ? "bg-ink-900 text-white"
                : "text-ink-600 hover:bg-paper-200"
            }`}
          >
            Company Docs ({pendingCompanyCount ?? 0})
          </Link>
          <Link
            href={`/verifications?tab=roles&status=${statusQ}`}
            className={`rounded-md px-3 py-1.5 text-sm font-medium transition-colors ${
              activeTab === "roles"
                ? "bg-ink-900 text-white"
                : "text-ink-600 hover:bg-paper-200"
            }`}
          >
            Role Claims ({pendingRolesCount ?? 0})
          </Link>
        </div>

        <AdminFilterForm
          searchParams={params}
          resetHref={`/verifications?tab=${activeTab}`}
          fields={[
            {
              name: "status",
              label: "Status",
              type: "select",
              options: [
                { label: "Pending", value: "pending" },
                { label: "Approved", value: "approved" },
                { label: "Rejected", value: "rejected" },
                { label: "Expired", value: "expired" },
                { label: "All Statuses", value: "all" },
              ],
            },
          ]}
        />
      </div>

      {/* Evidence Table */}
      {activeTab === "evidence" && (
        <Card>
          <CardContent className="p-0">
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Provider</TableHead>
                  <TableHead>Capability</TableHead>
                  <TableHead>Type</TableHead>
                  <TableHead>Requirement</TableHead>
                  <TableHead>Document</TableHead>
                  <TableHead>Status</TableHead>
                  <TableHead>Submitted</TableHead>
                  <TableHead className="w-[280px]">Review</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {evidenceRows.length === 0 ? (
                  <TableRow>
                    <TableCell colSpan={8} className="py-8 text-center text-sm text-ink-500">
                      No capability evidence found for this filter.
                    </TableCell>
                  </TableRow>
                ) : (
                  evidenceRows.map((row) => {
                    const profile = row.provider_capabilities?.profiles;
                    const capability = row.provider_capabilities?.need_capabilities;
                    return (
                      <TableRow key={row.id}>
                        <TableCell>
                          <Link
                            href={`/users/${profile?.id}`}
                            className="font-medium text-ink-900 hover:underline"
                          >
                            {profile?.full_name || "Unnamed Provider"}
                          </Link>
                          <p className="text-xs text-ink-500">
                            {profile?.phone || "No phone"} · {profile?.country}
                          </p>
                        </TableCell>
                        <TableCell>
                          <span className="font-medium text-ink-900">
                            {capability?.name || row.provider_capabilities?.capability_slug}
                          </span>
                          <p className="text-xs text-ink-500 capitalize">
                            {capability?.category_slug?.replace(/_/g, " ")}
                          </p>
                        </TableCell>
                        <TableCell className="capitalize text-xs text-ink-700">
                          {row.provider_type || "both"}
                        </TableCell>
                        <TableCell className="text-xs text-ink-700 font-mono">
                          {row.requirement_key}
                        </TableCell>
                        <TableCell>
                          <ProviderDocumentViewer
                            bucket="provider-evidence"
                            filePath={row.file_url}
                            label="Evidence"
                          />
                        </TableCell>
                        <TableCell>
                          <Badge variant={STATUS_VARIANT[row.status] || "neutral"} className="capitalize">
                            {row.status}
                          </Badge>
                          {row.status === "rejected" && row.reject_reason && (
                            <p className="mt-1 text-[11px] text-clay-alert line-clamp-2" title={row.reject_reason}>
                              {row.reject_reason}
                            </p>
                          )}
                          {row.status === "approved" && row.expires_at && (
                            <p className="mt-1 text-[11px] text-ink-500">
                              Exp: {new Date(row.expires_at).toLocaleDateString()}
                            </p>
                          )}
                        </TableCell>
                        <TableCell className="text-xs text-ink-500">
                          {formatDateTime(row.created_at)}
                        </TableCell>
                        <TableCell>
                          <ProviderReviewActions
                            target={{ type: "capability", id: row.id }}
                            currentStatus={row.status}
                          />
                        </TableCell>
                      </TableRow>
                    );
                  })
                )}
              </TableBody>
            </Table>
          </CardContent>
        </Card>
      )}

      {/* Company Table */}
      {activeTab === "company" && (
        <Card>
          <CardContent className="p-0">
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Company / User</TableHead>
                  <TableHead>Category</TableHead>
                  <TableHead>Document Type</TableHead>
                  <TableHead>Document</TableHead>
                  <TableHead>Status</TableHead>
                  <TableHead>Submitted</TableHead>
                  <TableHead className="w-[280px]">Review</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {companyRows.length === 0 ? (
                  <TableRow>
                    <TableCell colSpan={7} className="py-8 text-center text-sm text-ink-500">
                      No company verification submissions found for this filter.
                    </TableCell>
                  </TableRow>
                ) : (
                  companyRows.map((row) => {
                    const profile = row.profiles;
                    const category = row.need_categories;
                    return (
                      <TableRow key={`${row.user_id}-${row.category_slug}-${row.document_type}`}>
                        <TableCell>
                          <Link
                            href={`/users/${profile?.id}`}
                            className="font-medium text-ink-900 hover:underline"
                          >
                            {profile?.full_name || "Company Provider"}
                          </Link>
                          <p className="text-xs text-ink-500">
                            {profile?.phone || "No phone"} · {profile?.country}
                          </p>
                        </TableCell>
                        <TableCell>
                          <span className="font-medium text-ink-900">
                            {category?.icon} {category?.name || row.category_slug}
                          </span>
                        </TableCell>
                        <TableCell className="capitalize text-xs text-ink-700">
                          {row.document_type === "business_registration"
                            ? "Registration Certificate"
                            : "Business Licence"}
                        </TableCell>
                        <TableCell>
                          <ProviderDocumentViewer
                            bucket="company-documents"
                            filePath={row.file_path}
                            label={row.document_type === "business_registration" ? "Reg Cert" : "Licence"}
                          />
                        </TableCell>
                        <TableCell>
                          <Badge variant={STATUS_VARIANT[row.status] || "neutral"} className="capitalize">
                            {row.status}
                          </Badge>
                          {row.status === "rejected" && row.reject_reason && (
                            <p className="mt-1 text-[11px] text-clay-alert line-clamp-2" title={row.reject_reason}>
                              {row.reject_reason}
                            </p>
                          )}
                        </TableCell>
                        <TableCell className="text-xs text-ink-500">
                          {formatDateTime(row.created_at)}
                        </TableCell>
                        <TableCell>
                          <ProviderReviewActions
                            target={{
                              type: "company",
                              userId: row.user_id,
                              categorySlug: row.category_slug,
                              documentType: row.document_type,
                            }}
                            currentStatus={row.status}
                          />
                        </TableCell>
                      </TableRow>
                    );
                  })
                )}
              </TableBody>
            </Table>
          </CardContent>
        </Card>
      )}

      {/* Role Claims Table */}
      {activeTab === "roles" && (
        <Card>
          <CardContent className="p-0">
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Provider</TableHead>
                  <TableHead>Role</TableHead>
                  <TableHead>Claim Key</TableHead>
                  <TableHead>Document</TableHead>
                  <TableHead>Status</TableHead>
                  <TableHead>Submitted</TableHead>
                  <TableHead className="w-[280px]">Review</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {roleRows.length === 0 ? (
                  <TableRow>
                    <TableCell colSpan={7} className="py-8 text-center text-sm text-ink-500">
                      No role qualification claims found for this filter.
                    </TableCell>
                  </TableRow>
                ) : (
                  roleRows.map((row) => {
                    const profile = row.provider_capabilities?.profiles;
                    const capability = row.provider_capabilities?.need_capabilities;
                    return (
                      <TableRow key={row.id}>
                        <TableCell>
                          <Link
                            href={`/users/${profile?.id}`}
                            className="font-medium text-ink-900 hover:underline"
                          >
                            {profile?.full_name || "Provider"}
                          </Link>
                          <p className="text-xs text-ink-500">
                            {profile?.phone || "No phone"} · {profile?.country}
                          </p>
                        </TableCell>
                        <TableCell>
                          <span className="font-medium text-ink-900">
                            {capability?.name || row.provider_capabilities?.capability_slug}
                          </span>
                        </TableCell>
                        <TableCell className="text-xs text-ink-700 font-mono">
                          {row.claim_key}
                        </TableCell>
                        <TableCell>
                          <ProviderDocumentViewer
                            bucket="provider-evidence"
                            filePath={row.evidence_url}
                            label="Claim Evidence"
                          />
                        </TableCell>
                        <TableCell>
                          <Badge variant={STATUS_VARIANT[row.status] || "neutral"} className="capitalize">
                            {row.status}
                          </Badge>
                          {row.status === "rejected" && row.reject_reason && (
                            <p className="mt-1 text-[11px] text-clay-alert line-clamp-2" title={row.reject_reason}>
                              {row.reject_reason}
                            </p>
                          )}
                          {row.status === "approved" && row.expires_at && (
                            <p className="mt-1 text-[11px] text-ink-500">
                              Exp: {new Date(row.expires_at).toLocaleDateString()}
                            </p>
                          )}
                        </TableCell>
                        <TableCell className="text-xs text-ink-500">
                          {formatDateTime(row.created_at)}
                        </TableCell>
                        <TableCell>
                          <ProviderReviewActions
                            target={{ type: "role", id: row.id }}
                            currentStatus={row.status}
                          />
                        </TableCell>
                      </TableRow>
                    );
                  })
                )}
              </TableBody>
            </Table>
          </CardContent>
        </Card>
      )}

      <Pagination
        page={page}
        pageSize={pageSize}
        total={totalCount}
        searchParams={params}
        basePath="/verifications"
      />
    </div>
  );
}
