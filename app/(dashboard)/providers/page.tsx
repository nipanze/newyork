import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import { Header } from "@/components/header";
import { Card, CardContent } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { AdminFilterForm } from "@/components/admin-filter-form";
import { Pagination } from "@/components/pagination";
import { formatDateTime } from "@/lib/utils";
import {
  getPage,
  getPageSize,
  getParam,
  type DashboardSearchParams,
} from "@/lib/dashboard-filters";

export const dynamic = "force-dynamic";

export default async function ProvidersPage({
  searchParams,
}: {
  searchParams: Promise<DashboardSearchParams>;
}) {
  const params = await searchParams;
  const supabase = await createClient();
  const page = getPage(params);
  const pageSize = getPageSize(params);
  const from = (page - 1) * pageSize;

  const typeQ = getParam(params, "type");
  const nameQ = getParam(params, "name");
  const countryQ = getParam(params, "country");

  const {
    data: { user },
  } = await supabase.auth.getUser();

  const { data: adminProfile } = await supabase
    .from("profiles")
    .select("full_name")
    .eq("id", user?.id ?? "")
    .single();

  // Query distinct users who have provider capabilities or category profiles
  let query = supabase
    .from("profiles")
    .select(
      `
      id, full_name, phone, country, district, account_status, created_at,
      provider_category_profiles ( category_slug, provider_type, updated_at ),
      provider_capabilities ( id, capability_slug, verification_level, is_active, identity_type ),
      provider_company_profiles ( category_slug, company_name, registration_number )
    `,
      { count: "exact" }
    )
    .not("provider_capabilities", "is", null);

  if (nameQ) {
    query = query.ilike("full_name", `%${nameQ}%`);
  }
  if (countryQ) {
    query = query.eq("country", countryQ.toUpperCase());
  }

  const { data: providersRaw, count } = await query
    .order("created_at", { ascending: false })
    .range(from, from + pageSize - 1);

  // Filter in memory if typeQ specified
  let providers = (providersRaw || []).filter((p) => {
    if (!typeQ) return true;
    return p.provider_category_profiles?.some(
      (pcp: any) => pcp.provider_type === typeQ
    );
  });

  return (
    <div className="flex-1 space-y-6 p-6">
      <Header
        title="Service Providers"
        description="Inspect registered individual and company providers, capabilities, and business registrations."
        adminName={adminProfile?.full_name}
      />

      <div className="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between border-b border-paper-300 pb-3">
        <div className="flex items-center gap-2">
          <Badge variant="neutral" className="text-sm px-3 py-1">
            Total Providers: {count ?? 0}
          </Badge>
        </div>

        <AdminFilterForm
          searchParams={params}
          resetHref="/providers"
          fields={[
            {
              name: "name",
              label: "Search Name",
              type: "text",
              placeholder: "Provider name...",
            },
            {
              name: "type",
              label: "Provider Type",
              type: "select",
              options: [
                { label: "All Types", value: "" },
                { label: "Individual", value: "individual" },
                { label: "Company", value: "company" },
              ],
            },
            {
              name: "country",
              label: "Country",
              type: "text",
              placeholder: "e.g. UG, KE",
            },
          ]}
        />
      </div>

      <Card>
        <CardContent className="p-0">
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Provider Name</TableHead>
                <TableHead>Country / Location</TableHead>
                <TableHead>Active Identities</TableHead>
                <TableHead>Company Details</TableHead>
                <TableHead>Capabilities</TableHead>
                <TableHead>Joined</TableHead>
                <TableHead className="text-right">Action</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {providers.length === 0 ? (
                <TableRow>
                  <TableCell colSpan={7} className="py-8 text-center text-sm text-ink-500">
                    No providers found matching your criteria.
                  </TableCell>
                </TableRow>
              ) : (
                providers.map((p) => {
                  const caps = p.provider_capabilities || [];
                  const verifiedCaps = caps.filter((c: any) => c.verification_level === "provider_verified");
                  const activeCaps = caps.filter((c: any) => c.is_active);
                  const companyProfiles = p.provider_company_profiles || [];

                  return (
                    <TableRow key={p.id}>
                      <TableCell>
                        <Link
                          href={`/providers/${p.id}`}
                          className="font-medium text-ink-900 hover:underline"
                        >
                          {p.full_name || "Unnamed Provider"}
                        </Link>
                        <p className="text-xs text-ink-500">{p.phone || "No phone"}</p>
                      </TableCell>
                      <TableCell className="text-xs text-ink-700">
                        {p.district ? `${p.district}, ` : ""}
                        {p.country}
                      </TableCell>
                      <TableCell>
                        <div className="flex flex-wrap gap-1">
                          {p.provider_category_profiles?.length ? (
                            p.provider_category_profiles.map((pcp: any) => (
                              <Badge
                                key={pcp.category_slug}
                                variant={pcp.provider_type === "company" ? "confirm" : "neutral"}
                                className="text-[11px] capitalize"
                              >
                                {pcp.category_slug.replace(/_/g, " ")}: {pcp.provider_type}
                              </Badge>
                            ))
                          ) : (
                            <span className="text-xs text-ink-400">None set</span>
                          )}
                        </div>
                      </TableCell>
                      <TableCell className="text-xs text-ink-700">
                        {companyProfiles.length > 0 ? (
                          <div>
                            <p className="font-medium">{companyProfiles[0].company_name || "Company"}</p>
                            {companyProfiles[0].registration_number && (
                              <p className="font-mono text-[11px] text-ink-500">
                                Reg: {companyProfiles[0].registration_number}
                              </p>
                            )}
                          </div>
                        ) : (
                          <span className="text-xs text-ink-400">—</span>
                        )}
                      </TableCell>
                      <TableCell>
                        <div className="text-xs">
                          <span className="font-medium text-ink-900">{activeCaps.length}</span> active
                          <span className="text-ink-400"> / {caps.length} total</span>
                          {verifiedCaps.length > 0 && (
                            <Badge variant="confirm" className="ml-1.5 text-[10px] py-0 px-1.5">
                              {verifiedCaps.length} verified
                            </Badge>
                          )}
                        </div>
                      </TableCell>
                      <TableCell className="text-xs text-ink-500">
                        {formatDateTime(p.created_at)}
                      </TableCell>
                      <TableCell className="text-right">
                        <Link
                          href={`/providers/${p.id}`}
                          className="text-xs font-medium text-ink-700 hover:text-ink-950 underline"
                        >
                          View Details
                        </Link>
                      </TableCell>
                    </TableRow>
                  );
                })
              )}
            </TableBody>
          </Table>
        </CardContent>
      </Card>

      <Pagination
        page={page}
        pageSize={pageSize}
        total={count ?? 0}
        searchParams={params}
        basePath="/providers"
      />
    </div>
  );
}
