import Link from "next/link";
import { notFound } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { Header } from "@/components/header";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { ProviderDocumentViewer } from "@/components/provider-document-viewer";
import { ProviderReviewActions } from "@/components/provider-review-actions";
import { formatDateTime } from "@/lib/utils";
import { ArrowLeft, Building2, User, ShieldCheck } from "lucide-react";

export const dynamic = "force-dynamic";

export default async function ProviderDetailPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;
  const supabase = await createClient();

  const {
    data: { user: currentUser },
  } = await supabase.auth.getUser();

  const { data: adminProfile } = await supabase
    .from("profiles")
    .select("full_name")
    .eq("id", currentUser?.id ?? "")
    .single();

  // Fetch provider profile
  const { data: profile } = await supabase
    .from("profiles")
    .select("*")
    .eq("id", id)
    .single();

  if (!profile) {
    notFound();
  }

  // Fetch all related provider data
  const [
    { data: categoryProfiles },
    { data: companyProfiles },
    { data: presentations },
    { data: capabilities },
    { data: companySubmissions },
  ] = await Promise.all([
    supabase
      .from("provider_category_profiles")
      .select("*, need_categories ( name, icon )")
      .eq("user_id", id),
    supabase
      .from("provider_company_profiles")
      .select("*, need_categories ( name, icon )")
      .eq("user_id", id),
    supabase
      .from("provider_identity_presentations")
      .select("*")
      .eq("user_id", id),
    supabase
      .from("provider_capabilities")
      .select(`
        *,
        need_capabilities ( name, category_slug, verification_policy ),
        provider_capability_evidence ( id, requirement_key, file_url, status, reject_reason, expires_at, created_at )
      `)
      .eq("user_id", id),
    supabase
      .from("provider_company_verification_submissions")
      .select("*, need_categories ( name, icon )")
      .eq("user_id", id),
  ]);

  return (
    <div className="flex-1 space-y-6 p-6">
      <div className="flex items-center gap-3">
        <Link
          href="/providers"
          className="inline-flex items-center gap-1 text-xs text-ink-500 hover:text-ink-800"
        >
          <ArrowLeft className="h-3 w-3" /> Back to Providers
        </Link>
        <span className="text-ink-300">|</span>
        <Link
          href={`/users/${profile.id}`}
          className="text-xs text-ink-500 hover:text-ink-800"
        >
          View Account Profile
        </Link>
      </div>

      <Header
        title={profile.full_name || "Provider Detail"}
        description={`Provider ID: ${profile.id} · ${profile.country} · ${profile.phone || "No phone"}`}
        adminName={adminProfile?.full_name}
      />

      {/* Overview Cards */}
      <div className="grid gap-4 md:grid-cols-4">
        <Card>
          <CardContent className="pt-6">
            <span className="text-xs font-medium text-ink-500">Account Status</span>
            <div className="mt-2 flex items-center gap-2">
              <Badge variant={profile.account_status === "active" ? "confirm" : "alert"}>
                {profile.account_status}
              </Badge>
              {profile.phone_verified_at && (
                <Badge variant="neutral" className="text-[10px]">Phone Verified</Badge>
              )}
            </div>
          </CardContent>
        </Card>

        <Card>
          <CardContent className="pt-6">
            <span className="text-xs font-medium text-ink-500">Active Categories</span>
            <p className="mt-2 text-xl font-bold text-ink-950">
              {categoryProfiles?.length ?? 0}
            </p>
          </CardContent>
        </Card>

        <Card>
          <CardContent className="pt-6">
            <span className="text-xs font-medium text-ink-500">Declared Capabilities</span>
            <p className="mt-2 text-xl font-bold text-ink-950">
              {capabilities?.filter((c) => c.is_active).length ?? 0}
              <span className="text-xs font-normal text-ink-500"> / {capabilities?.length ?? 0} total</span>
            </p>
          </CardContent>
        </Card>

        <Card>
          <CardContent className="pt-6">
            <span className="text-xs font-medium text-ink-500">Verified Capabilities</span>
            <p className="mt-2 text-xl font-bold text-teal-confirm">
              {capabilities?.filter((c) => c.verification_level === "provider_verified").length ?? 0}
            </p>
          </CardContent>
        </Card>
      </div>

      {/* Category Identities & Presentations */}
      <Card>
        <CardHeader>
          <CardTitle className="text-sm font-semibold text-ink-900 flex items-center gap-2">
            <User className="h-4 w-4" /> Category Identities & Presentations
          </CardTitle>
        </CardHeader>
        <CardContent className="p-0">
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Category</TableHead>
                <TableHead>Active Identity</TableHead>
                <TableHead>Display Presentation</TableHead>
                <TableHead>Representative</TableHead>
                <TableHead>Identity Switched At</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {!categoryProfiles?.length ? (
                <TableRow>
                  <TableCell colSpan={5} className="py-6 text-center text-xs text-ink-500">
                    No active category profiles registered.
                  </TableCell>
                </TableRow>
              ) : (
                categoryProfiles.map((cp) => {
                  const pres = presentations?.find(
                    (p) => p.category_slug === cp.category_slug && p.identity_type === cp.provider_type
                  );
                  return (
                    <TableRow key={cp.category_slug}>
                      <TableCell className="font-medium text-ink-900">
                        {cp.need_categories?.icon} {cp.need_categories?.name || cp.category_slug}
                      </TableCell>
                      <TableCell>
                        <Badge
                          variant={cp.provider_type === "company" ? "confirm" : "neutral"}
                          className="capitalize"
                        >
                          {cp.provider_type === "company" ? <Building2 className="mr-1 h-3 w-3 inline" /> : null}
                          {cp.provider_type}
                        </Badge>
                      </TableCell>
                      <TableCell className="text-xs text-ink-700">
                        {pres?.display_name || profile.full_name || "Personal name"}
                        <span className="ml-1 text-ink-400">({pres?.display_mode || "personal"})</span>
                      </TableCell>
                      <TableCell className="text-xs text-ink-600">
                        {pres?.representative_name || "—"}
                      </TableCell>
                      <TableCell className="text-xs text-ink-500">
                        {cp.identity_changed_at ? formatDateTime(cp.identity_changed_at) : "Initial"}
                      </TableCell>
                    </TableRow>
                  );
                })
              )}
            </TableBody>
          </Table>
        </CardContent>
      </Card>

      {/* Company Profiles */}
      {companyProfiles && companyProfiles.length > 0 && (
        <Card>
          <CardHeader>
            <CardTitle className="text-sm font-semibold text-ink-900 flex items-center gap-2">
              <Building2 className="h-4 w-4" /> Company Information (Private to Admins)
            </CardTitle>
          </CardHeader>
          <CardContent className="p-0">
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Category</TableHead>
                  <TableHead>Company Name</TableHead>
                  <TableHead>Registration Number</TableHead>
                  <TableHead>Team Size</TableHead>
                  <TableHead>Years in Business</TableHead>
                  <TableHead>Service Areas</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {companyProfiles.map((comp) => (
                  <TableRow key={comp.category_slug}>
                    <TableCell className="font-medium text-ink-900">
                      {comp.need_categories?.icon} {comp.need_categories?.name || comp.category_slug}
                    </TableCell>
                    <TableCell className="font-medium text-ink-900">
                      {comp.company_name || "—"}
                    </TableCell>
                    <TableCell className="font-mono text-xs text-ink-700">
                      {comp.registration_number || "—"}
                    </TableCell>
                    <TableCell className="text-xs text-ink-700">
                      {comp.team_size || "—"}
                    </TableCell>
                    <TableCell className="text-xs text-ink-700">
                      {comp.years_in_business || "—"}
                    </TableCell>
                    <TableCell className="text-xs text-ink-700">
                      {comp.service_areas?.length ? comp.service_areas.join(", ") : "—"}
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          </CardContent>
        </Card>
      )}

      {/* Company Verification Submissions */}
      {companySubmissions && companySubmissions.length > 0 && (
        <Card>
          <CardHeader>
            <CardTitle className="text-sm font-semibold text-ink-900 flex items-center gap-2">
              <ShieldCheck className="h-4 w-4" /> Company Verification Submissions
            </CardTitle>
          </CardHeader>
          <CardContent className="p-0">
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Category</TableHead>
                  <TableHead>Document Type</TableHead>
                  <TableHead>Document</TableHead>
                  <TableHead>Status</TableHead>
                  <TableHead>Submitted</TableHead>
                  <TableHead className="w-[280px]">Review</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {companySubmissions.map((sub) => (
                  <TableRow key={`${sub.category_slug}-${sub.document_type}`}>
                    <TableCell className="font-medium text-ink-900">
                      {sub.need_categories?.icon} {sub.need_categories?.name || sub.category_slug}
                    </TableCell>
                    <TableCell className="text-xs capitalize text-ink-700">
                      {sub.document_type.replace(/_/g, " ")}
                    </TableCell>
                    <TableCell>
                      <ProviderDocumentViewer
                        bucket="company-documents"
                        filePath={sub.file_path}
                        label="View Document"
                      />
                    </TableCell>
                    <TableCell>
                      <Badge
                        variant={sub.status === "approved" ? "confirm" : sub.status === "rejected" ? "alert" : "signal"}
                        className="capitalize"
                      >
                        {sub.status}
                      </Badge>
                      {sub.status === "rejected" && sub.reject_reason && (
                        <p className="mt-1 text-[11px] text-clay-alert line-clamp-2">
                          {sub.reject_reason}
                        </p>
                      )}
                    </TableCell>
                    <TableCell className="text-xs text-ink-500">
                      {formatDateTime(sub.created_at)}
                    </TableCell>
                    <TableCell>
                      <ProviderReviewActions
                        target={{
                          type: "company",
                          userId: sub.user_id,
                          categorySlug: sub.category_slug,
                          documentType: sub.document_type,
                        }}
                        currentStatus={sub.status}
                      />
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          </CardContent>
        </Card>
      )}

      {/* Provider Capabilities List */}
      <Card>
        <CardHeader>
          <CardTitle className="text-sm font-semibold text-ink-900">
            Declared Capabilities & Proof
          </CardTitle>
        </CardHeader>
        <CardContent className="p-0">
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Capability</TableHead>
                <TableHead>Policy</TableHead>
                <TableHead>Identity Type</TableHead>
                <TableHead>Status</TableHead>
                <TableHead>Verification Level</TableHead>
                <TableHead>Submitted Evidence</TableHead>
                <TableHead className="w-[280px]">Review Evidence</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {!capabilities?.length ? (
                <TableRow>
                  <TableCell colSpan={7} className="py-6 text-center text-xs text-ink-500">
                    No capabilities declared by this provider.
                  </TableCell>
                </TableRow>
              ) : (
                capabilities.map((cap) => {
                  const ev = cap.provider_capability_evidence?.[0];
                  return (
                    <TableRow key={cap.id}>
                      <TableCell>
                        <span className="font-medium text-ink-900">
                          {cap.need_capabilities?.name || cap.capability_slug}
                        </span>
                        <p className="text-[11px] text-ink-500 capitalize">
                          {cap.need_capabilities?.category_slug?.replace(/_/g, " ")}
                        </p>
                      </TableCell>
                      <TableCell className="text-xs capitalize font-mono text-ink-600">
                        {cap.need_capabilities?.verification_policy || "open"}
                      </TableCell>
                      <TableCell className="text-xs capitalize text-ink-700">
                        {cap.identity_type || "individual"}
                      </TableCell>
                      <TableCell>
                        <Badge variant={cap.is_active ? "confirm" : "neutral"}>
                          {cap.is_active ? "Active" : "Inactive"}
                        </Badge>
                      </TableCell>
                      <TableCell>
                        <Badge
                          variant={cap.verification_level === "provider_verified" ? "confirm" : "neutral"}
                        >
                          {cap.verification_level === "provider_verified" ? "Verified" : "Self-declared"}
                        </Badge>
                      </TableCell>
                      <TableCell>
                        {ev ? (
                          <div>
                            <ProviderDocumentViewer
                              bucket="provider-evidence"
                              filePath={ev.file_url}
                              label={ev.requirement_key}
                            />
                            <div className="mt-1">
                              <Badge
                                variant={ev.status === "approved" ? "confirm" : ev.status === "rejected" ? "alert" : "signal"}
                                className="text-[10px] capitalize"
                              >
                                {ev.status}
                              </Badge>
                            </div>
                          </div>
                        ) : (
                          <span className="text-xs text-ink-400">No proof submitted</span>
                        )}
                      </TableCell>
                      <TableCell>
                        {ev ? (
                          <ProviderReviewActions
                            target={{ type: "capability", id: ev.id }}
                            currentStatus={ev.status}
                          />
                        ) : (
                          <span className="text-xs text-ink-400">—</span>
                        )}
                      </TableCell>
                    </TableRow>
                  );
                })
              )}
            </TableBody>
          </Table>
        </CardContent>
      </Card>
    </div>
  );
}

