import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import { Header } from "@/components/header";
import { Card, CardContent } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { AdminFilterForm } from "@/components/admin-filter-form";
import { Pagination } from "@/components/pagination";
import { formatDateTime, formatCurrency } from "@/lib/utils";
import {
  getPage,
  getPageSize,
  getParam,
  type DashboardSearchParams,
} from "@/lib/dashboard-filters";

export const dynamic = "force-dynamic";

const STATUS_VARIANT: Record<string, "confirm" | "signal" | "alert" | "neutral"> = {
  active: "confirm",
  matched: "signal",
  expired: "neutral",
  cancelled: "alert",
};

export default async function NeedsPage({
  searchParams,
}: {
  searchParams: Promise<DashboardSearchParams>;
}) {
  const params = await searchParams;
  const supabase = await createClient();
  const page = getPage(params);
  const pageSize = getPageSize(params);
  const from = (page - 1) * pageSize;

  const queryQ = getParam(params, "query");
  const categoryQ = getParam(params, "category");
  const statusQ = getParam(params, "status");
  const countryQ = getParam(params, "country");

  const {
    data: { user },
  } = await supabase.auth.getUser();

  const { data: adminProfile } = await supabase
    .from("profiles")
    .select("full_name")
    .eq("id", user?.id ?? "")
    .single();

  // Metrics
  const [{ count: totalNeeds }, { count: activeNeeds }] = await Promise.all([
    supabase.from("needs_requests").select("*", { count: "exact", head: true }),
    supabase.from("needs_requests").select("*", { count: "exact", head: true }).eq("status", "active"),
  ]);

  let query = supabase
    .from("needs_requests")
    .select(
      `
      request_id, title, specification, category, category_slug, budget, currency,
      location, country, urgency, status, number_of_offers, listed_at, requester_id,
      profiles:requester_id ( id, full_name, phone )
    `,
      { count: "exact" }
    )
    .order("listed_at", { ascending: false });

  if (queryQ) {
    query = query.or(`title.ilike.%${queryQ}%,specification.ilike.%${queryQ}%`);
  }
  if (categoryQ) {
    query = query.eq("category_slug", categoryQ);
  }
  if (statusQ) {
    query = query.eq("status", statusQ);
  }
  if (countryQ) {
    query = query.eq("country", countryQ.toUpperCase());
  }

  const { data: needs, count } = await query.range(from, from + pageSize - 1);

  return (
    <div className="flex-1 space-y-6 p-6">
      <Header
        title="Needs Marketplace"
        description="Monitor user needs requests across all 5 non-financial categories, competing offers, and reveals."
        adminName={adminProfile?.full_name}
      />

      {/* Metrics */}
      <div className="grid gap-4 md:grid-cols-3">
        <Card>
          <CardContent className="pt-6">
            <span className="text-xs font-medium text-ink-500">Total Needs Requests</span>
            <p className="mt-2 text-2xl font-bold text-ink-950">{totalNeeds ?? 0}</p>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="pt-6">
            <span className="text-xs font-medium text-ink-500">Active Requests</span>
            <p className="mt-2 text-2xl font-bold text-teal-confirm">{activeNeeds ?? 0}</p>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="pt-6">
            <span className="text-xs font-medium text-ink-500">Current Filtered Results</span>
            <p className="mt-2 text-2xl font-bold text-ink-900">{count ?? 0}</p>
          </CardContent>
        </Card>
      </div>

      <div className="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between border-b border-paper-300 pb-3">
        <AdminFilterForm
          searchParams={params}
          resetHref="/needs"
          fields={[
            {
              name: "query",
              label: "Search Needs",
              type: "text",
              placeholder: "Title or specs...",
            },
            {
              name: "category",
              label: "Category",
              type: "select",
              options: [
                { label: "All Categories", value: "" },
                { label: "Travel & International", value: "travel_international" },
                { label: "Machinery & Equipment", value: "machinery_equipment" },
                { label: "Professional Services", value: "professional_services" },
                { label: "Transport & Logistics", value: "transport_logistics" },
                { label: "Specialized Products", value: "specialized_products" },
              ],
            },
            {
              name: "status",
              label: "Status",
              type: "select",
              options: [
                { label: "All Statuses", value: "" },
                { label: "Active", value: "active" },
                { label: "Matched", value: "matched" },
                { label: "Expired", value: "expired" },
                { label: "Cancelled", value: "cancelled" },
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
                <TableHead>Need Title</TableHead>
                <TableHead>Requester</TableHead>
                <TableHead>Category</TableHead>
                <TableHead>Budget</TableHead>
                <TableHead>Location</TableHead>
                <TableHead>Urgency</TableHead>
                <TableHead>Offers</TableHead>
                <TableHead>Status</TableHead>
                <TableHead>Listed</TableHead>
                <TableHead className="text-right">Action</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {!needs?.length ? (
                <TableRow>
                  <TableCell colSpan={10} className="py-8 text-center text-sm text-ink-500">
                    No needs requests found matching your filters.
                  </TableCell>
                </TableRow>
              ) : (
                needs.map((item: any) => {
                  const requester = Array.isArray(item.profiles) ? item.profiles[0] : item.profiles;
                  return (
                    <TableRow key={item.request_id}>
                      <TableCell className="max-w-[220px]">
                        <Link
                          href={`/needs/${item.request_id}`}
                          className="font-medium text-ink-900 hover:underline line-clamp-1"
                        >
                          {item.title}
                        </Link>
                        <p className="text-xs text-ink-500 line-clamp-1">{item.specification}</p>
                      </TableCell>
                      <TableCell>
                        {requester ? (
                          <Link
                            href={`/users/${requester.id}`}
                            className="text-xs font-medium text-ink-900 hover:underline"
                          >
                            {requester.full_name || "User"}
                          </Link>
                        ) : (
                          <span className="text-xs text-ink-400">Anonymous</span>
                        )}
                        <p className="text-[11px] text-ink-500">{requester?.phone || ""}</p>
                      </TableCell>
                      <TableCell className="text-xs font-medium capitalize">
                        {item.category || item.category_slug?.replace(/_/g, " ")}
                      </TableCell>
                      <TableCell className="text-xs font-semibold text-ink-900">
                        {formatCurrency(item.budget, item.currency || "UGX")}
                      </TableCell>
                      <TableCell className="text-xs text-ink-700">
                        {item.location ? `${item.location}, ` : ""}
                        {item.country}
                      </TableCell>
                      <TableCell className="text-xs capitalize text-ink-600">
                        {item.urgency || "Flexible"}
                      </TableCell>
                      <TableCell>
                        <Badge variant="neutral" className="text-xs font-medium">
                          {item.number_of_offers ?? 0} offers
                        </Badge>
                      </TableCell>
                      <TableCell>
                        <Badge variant={STATUS_VARIANT[item.status] || "neutral"} className="capitalize">
                          {item.status}
                        </Badge>
                      </TableCell>
                      <TableCell className="text-xs text-ink-500">
                        {formatDateTime(item.listed_at)}
                      </TableCell>
                      <TableCell className="text-right">
                        <Link
                          href={`/needs/${item.request_id}`}
                          className="text-xs font-medium text-ink-700 hover:text-ink-950 underline"
                        >
                          Inspect
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
        basePath="/needs"
      />
    </div>
  );
}
