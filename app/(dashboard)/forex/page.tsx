import { createClient } from "@/lib/supabase/server";
import { Header } from "@/components/header";
import { Badge } from "@/components/ui/badge";
import { AdminFilterForm } from "@/components/admin-filter-form";
import { Pagination } from "@/components/pagination";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from "@/components/ui/card";
import { formatAmount, formatDate } from "@/lib/utils";
import { ArrowLeftRight } from "lucide-react";
import Link from "next/link";
import {
  getPage,
  getPageSize,
  getParam,
  type DashboardSearchParams,
} from "@/lib/dashboard-filters";
import { createAdminClient } from "@/lib/supabase/admin";

export const dynamic = "force-dynamic";

type ForexStatus = "active" | "contracted" | "expired" | "cancelled";

const STATUS_VARIANT: Record<ForexStatus, "confirm" | "neutral" | "signal" | "alert"> = {
  active: "confirm",
  contracted: "signal",
  expired: "neutral",
  cancelled: "alert",
};

export default async function ForexPage({
  searchParams,
}: {
  searchParams: Promise<DashboardSearchParams>;
}) {
  const params = await searchParams;
  const supabase = await createClient();
  const page = getPage(params);
  const pageSize = getPageSize(params);

  const countryQ = getParam(params, "country");
  const statusQ = getParam(params, "status");
  const currencyHeldQ = getParam(params, "currencyHeld");
  const currencyNeededQ = getParam(params, "currencyNeeded");
  const fromQ = getParam(params, "from");
  const toQ = getParam(params, "to");
  const requesterQ = getParam(params, "requester"); // pre-filter by user id from user detail page

  const requesterNameQ = getParam(params, "requesterName");
  const requesterPhoneQ = getParam(params, "requesterPhone");

  let allowedRequesterIds: string[] | null = null;

  if (requesterQ) {
    allowedRequesterIds = [requesterQ];
  } else if (requesterNameQ || requesterPhoneQ) {
    const supabaseAdmin = createAdminClient();
    let profileQuery = supabaseAdmin.from("profiles").select("id");
    if (requesterNameQ) profileQuery = profileQuery.ilike("full_name", `%${requesterNameQ}%`);
    if (requesterPhoneQ) profileQuery = profileQuery.ilike("phone", `%${requesterPhoneQ}%`);
    const { data: matchedProfiles } = await profileQuery;
    allowedRequesterIds = (matchedProfiles ?? []).map((p) => p.id);
  }

  const { data: countries } = await supabase.from("countries").select("code, name").order("code");
  const countryOptions = [
    { label: "All countries", value: "" },
    ...((countries ?? []).map((c) => ({ label: `${c.name} (${c.code})`, value: c.code }))),
  ];

  if (allowedRequesterIds && allowedRequesterIds.length === 0) {
    return (
      <>
        <Header title="Forex" description="Peer-to-peer currency exchange requests" />
        <main className="flex-1 space-y-4 overflow-y-auto p-6">
          <AdminFilterForm resetHref="/forex" searchParams={params} fields={buildFields(countryOptions)} />
          <p className="py-10 text-center text-sm text-ink-500">No requesters match the name/phone filter.</p>
        </main>
      </>
    );
  }

  let query = (supabase as any)
    .from("forex_requests")
    .select(
      "id, country, requester_id, user_id, currency_held, from_currency, currency_needed, to_currency, amount, preferred_rate, exchange_rate, status, listed_at, expires_at, number_of_offers",
      { count: "exact" }
    )
    .order("listed_at", { ascending: false });

  if (countryQ) query = query.eq("country", countryQ);
  if (statusQ) query = query.eq("status", statusQ);
  if (currencyHeldQ) query = query.ilike("currency_held", `%${currencyHeldQ}%`);
  if (currencyNeededQ) query = query.ilike("currency_needed", `%${currencyNeededQ}%`);
  if (fromQ) query = query.gte("listed_at", `${fromQ}T00:00:00.000Z`);
  if (toQ) query = query.lte("listed_at", `${toQ}T23:59:59.999Z`);
  if (allowedRequesterIds) {
    query = query.or(`requester_id.in.(${allowedRequesterIds.join(",")}),user_id.in.(${allowedRequesterIds.join(",")})`);
  }

  const from = (page - 1) * pageSize;
  const [{ data: requests, count, error }] = await Promise.all([
    query.range(from, from + pageSize - 1),
  ]);

  if (error) {
    return (
      <>
        <Header title="Forex" description="Peer-to-peer currency exchange requests" />
        <main className="flex-1 space-y-4 overflow-y-auto p-6">
          <Card>
            <CardHeader>
              <CardTitle className="flex items-center gap-2">
                <ArrowLeftRight className="h-4 w-4" /> Forex module not active yet
              </CardTitle>
              <CardDescription>
                The <code>forex_requests</code> table hasn&apos;t been migrated yet.
              </CardDescription>
            </CardHeader>
            <CardContent className="pt-0 text-sm text-ink-500">
              Error: {error.message}
            </CardContent>
          </Card>
        </main>
      </>
    );
  }

  // Resolve requester profiles
  const requesterIds = [
    ...new Set(
      (requests ?? []).map((r: any) => r.requester_id ?? r.user_id).filter(Boolean)
    ),
  ] as string[];
  const { data: requesterProfiles } = requesterIds.length
    ? await supabase.from("profiles").select("id, full_name, phone").in("id", requesterIds)
    : { data: [] };
  const requesterById = new Map((requesterProfiles ?? []).map((p) => [p.id, p]));

  return (
    <>
      <Header title="Forex" description="Peer-to-peer currency exchange requests" />
      <main className="flex-1 space-y-4 overflow-y-auto p-6">
        <AdminFilterForm resetHref="/forex" searchParams={params} fields={buildFields(countryOptions)} />

        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Pair</TableHead>
              <TableHead>Requester</TableHead>
              <TableHead>Market</TableHead>
              <TableHead>Amount</TableHead>
              <TableHead>Rate</TableHead>
              <TableHead>Offers</TableHead>
              <TableHead>Status</TableHead>
              <TableHead>Listed</TableHead>
              <TableHead />
            </TableRow>
          </TableHeader>
          <TableBody>
            {requests?.map((req: any) => {
              const fromCurr = req.currency_held ?? req.from_currency ?? "—";
              const toCurr = req.currency_needed ?? req.to_currency ?? "—";
              const rate = req.preferred_rate ?? req.exchange_rate;
              const reqId = req.requester_id ?? req.user_id;
              const requester = reqId ? requesterById.get(reqId) : null;

              return (
                <TableRow key={req.id}>
                  <TableCell>
                    <p className="font-medium text-ink-900">
                      {fromCurr} → {toCurr}
                    </p>
                  </TableCell>
                  <TableCell>
                    {requester ? (
                      <Link href={`/users/${reqId}`} className="text-xs font-medium text-ink-700 hover:underline">
                        {requester.full_name ?? requester.phone ?? reqId.slice(0, 8) + "…"}
                      </Link>
                    ) : reqId ? (
                      <span className="text-xs text-ink-500">{reqId.slice(0, 8)}…</span>
                    ) : (
                      "—"
                    )}
                  </TableCell>
                  <TableCell>{req.country}</TableCell>
                  <TableCell className="font-tabular">
                    {formatAmount(req.amount, fromCurr)}
                  </TableCell>
                  <TableCell className="font-tabular">
                    {rate != null ? Number(rate).toFixed(4) : "—"}
                  </TableCell>
                  <TableCell>{req.number_of_offers ?? 0}</TableCell>
                  <TableCell>
                    <Badge variant={STATUS_VARIANT[req.status as ForexStatus] ?? "neutral"}>
                      {req.status}
                    </Badge>
                  </TableCell>
                  <TableCell className="text-ink-500">{formatDate(req.listed_at)}</TableCell>
                  <TableCell className="text-right">
                    <Link
                      href={`/forex/${req.id}`}
                      className="text-xs font-medium text-ink-700 hover:underline"
                    >
                      Manage
                    </Link>
                  </TableCell>
                </TableRow>
              );
            })}
            {!requests?.length && (
              <TableRow>
                <TableCell colSpan={9} className="py-10 text-center text-sm text-ink-500">
                  No forex requests match this filter.
                </TableCell>
              </TableRow>
            )}
          </TableBody>
        </Table>

        <Pagination
          page={page}
          pageSize={pageSize}
          total={count ?? 0}
          searchParams={params}
          basePath="/forex"
        />
      </main>
    </>
  );
}

function buildFields(countryOptions: { label: string; value: string }[]) {
  return [
    { name: "requesterName", label: "Requester name", placeholder: "Full name" },
    { name: "requesterPhone", label: "Requester phone", placeholder: "+256…" },
    { name: "currencyHeld", label: "Currency held", placeholder: "UGX, USD..." },
    { name: "currencyNeeded", label: "Currency needed", placeholder: "KES, KES..." },
    { name: "country", label: "Country", type: "select" as const, options: countryOptions },
    {
      name: "status",
      label: "Status",
      type: "select" as const,
      options: [
        { label: "All statuses", value: "" },
        { label: "Active", value: "active" },
        { label: "Contracted", value: "contracted" },
        { label: "Expired", value: "expired" },
        { label: "Cancelled", value: "cancelled" },
      ],
    },
    { name: "from", label: "Listed from", type: "date" as const },
    { name: "to", label: "Listed to", type: "date" as const },
  ];
}
