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
import { formatAmount, formatDate } from "@/lib/utils";
import Link from "next/link";
import type { LoanStatus } from "@/lib/types";
import {
  getPage,
  getPageSize,
  getParam,
  type DashboardSearchParams,
} from "@/lib/dashboard-filters";
import { createAdminClient } from "@/lib/supabase/admin";

export const dynamic = "force-dynamic";

const STATUS_VARIANT: Record<LoanStatus, "confirm" | "neutral" | "signal" | "alert"> = {
  active: "confirm",
  contracted: "signal",
  expired: "neutral",
  cancelled: "alert",
};

export default async function LoansPage({
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
  const titleQ = getParam(params, "q");
  const fromQ = getParam(params, "from");
  const toQ = getParam(params, "to");
  const borrowerQ = getParam(params, "borrower"); // pre-filter by user id from user detail page

  // If borrower name/phone/email filter supplied, resolve to IDs first via admin client
  const borrowerNameQ = getParam(params, "borrowerName");
  const borrowerPhoneQ = getParam(params, "borrowerPhone");

  let allowedBorrowerIds: string[] | null = null;

  if (borrowerQ) {
    allowedBorrowerIds = [borrowerQ];
  } else if (borrowerNameQ || borrowerPhoneQ) {
    const supabaseAdmin = createAdminClient();
    let profileQuery = supabaseAdmin.from("profiles").select("id");
    if (borrowerNameQ) profileQuery = profileQuery.ilike("full_name", `%${borrowerNameQ}%`);
    if (borrowerPhoneQ) profileQuery = profileQuery.ilike("phone", `%${borrowerPhoneQ}%`);
    const { data: matchedProfiles } = await profileQuery;
    allowedBorrowerIds = (matchedProfiles ?? []).map((p) => p.id);
    if (allowedBorrowerIds.length === 0) {
      // No matching borrowers — return empty
      const { data: countries } = await supabase.from("countries").select("code, name").order("code");
      const countryOptions = [
        { label: "All countries", value: "" },
        ...((countries ?? []).map((c) => ({ label: `${c.name} (${c.code})`, value: c.code }))),
      ];
      return (
        <>
          <Header title="Loans" description="Every loan listing across every active market" />
          <main className="flex-1 space-y-4 overflow-y-auto p-6">
            <AdminFilterForm resetHref="/loans" searchParams={params} fields={buildFields(countryOptions)} />
            <p className="py-10 text-center text-sm text-ink-500">No borrowers match the name/phone filter.</p>
          </main>
        </>
      );
    }
  }

  let query = supabase
    .from("loan_requests")
    .select("id, borrower_id, title, country, district, requested_amount, status, number_of_offers, listed_at, expires_at", {
      count: "exact",
    })
    .order("listed_at", { ascending: false });

  if (countryQ) query = query.eq("country", countryQ);
  if (statusQ) query = query.eq("status", statusQ);
  if (titleQ) query = query.ilike("title", `%${titleQ}%`);
  if (fromQ) query = query.gte("listed_at", `${fromQ}T00:00:00.000Z`);
  if (toQ) query = query.lte("listed_at", `${toQ}T23:59:59.999Z`);
  if (allowedBorrowerIds) query = query.in("borrower_id", allowedBorrowerIds);

  const from = (page - 1) * pageSize;
  const { data: loans, count } = await query.range(from, from + pageSize - 1);

  const { data: countries } = await supabase.from("countries").select("code, name").order("code");
  const countryOptions = [
    { label: "All countries", value: "" },
    ...((countries ?? []).map((c) => ({ label: `${c.name} (${c.code})`, value: c.code }))),
  ];

  // Resolve borrower names for display
  const borrowerIds = [...new Set((loans ?? []).map((l) => l.borrower_id))];
  const { data: borrowerProfiles } = borrowerIds.length
    ? await supabase.from("profiles").select("id, full_name, phone").in("id", borrowerIds)
    : { data: [] };
  const borrowerById = new Map((borrowerProfiles ?? []).map((p) => [p.id, p]));

  return (
    <>
      <Header title="Loans" description="Every loan listing across every active market" />
      <main className="flex-1 space-y-4 overflow-y-auto p-6">
        <AdminFilterForm resetHref="/loans" searchParams={params} fields={buildFields(countryOptions)} />

        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Listing</TableHead>
              <TableHead>Borrower</TableHead>
              <TableHead>Market</TableHead>
              <TableHead>Amount</TableHead>
              <TableHead>Offers</TableHead>
              <TableHead>Status</TableHead>
              <TableHead>Listed</TableHead>
              <TableHead />
            </TableRow>
          </TableHeader>
          <TableBody>
            {loans?.map((loan) => {
              const borrower = borrowerById.get(loan.borrower_id);
              return (
                <TableRow key={loan.id}>
                  <TableCell>
                    <p className="font-medium text-ink-900">{loan.title}</p>
                    <p className="text-xs text-ink-500">{loan.district}</p>
                  </TableCell>
                  <TableCell>
                    {borrower ? (
                      <Link href={`/users/${loan.borrower_id}`} className="text-xs font-medium text-ink-700 hover:underline">
                        {borrower.full_name ?? borrower.phone ?? loan.borrower_id.slice(0, 8) + "…"}
                      </Link>
                    ) : (
                      <span className="text-xs text-ink-500">{loan.borrower_id.slice(0, 8)}…</span>
                    )}
                  </TableCell>
                  <TableCell>{loan.country}</TableCell>
                  <TableCell className="font-tabular">
                    {formatAmount(loan.requested_amount, undefined)}
                  </TableCell>
                  <TableCell>{loan.number_of_offers}</TableCell>
                  <TableCell>
                    <Badge variant={STATUS_VARIANT[loan.status as LoanStatus]}>{loan.status}</Badge>
                  </TableCell>
                  <TableCell className="text-ink-500">{formatDate(loan.listed_at)}</TableCell>
                  <TableCell className="text-right">
                    <Link href={`/loans/${loan.id}`} className="text-xs font-medium text-ink-700 hover:underline">
                      Manage
                    </Link>
                  </TableCell>
                </TableRow>
              );
            })}
            {!loans?.length && (
              <TableRow>
                <TableCell colSpan={8} className="py-10 text-center text-sm text-ink-500">
                  No listings match this filter.
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
          basePath="/loans"
        />
      </main>
    </>
  );
}

function buildFields(countryOptions: { label: string; value: string }[]) {
  return [
    { name: "q", label: "Title search", placeholder: "Loan title…" },
    { name: "borrowerName", label: "Borrower name", placeholder: "Full name" },
    { name: "borrowerPhone", label: "Borrower phone", placeholder: "+256…" },
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
