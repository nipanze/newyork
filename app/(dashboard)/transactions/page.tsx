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
import { formatAmount, formatDateTime } from "@/lib/utils";
import type { TransactionStatus } from "@/lib/types";
import Link from "next/link";
import {
  getPage,
  getPageSize,
  getParam,
  type DashboardSearchParams,
} from "@/lib/dashboard-filters";
import { createAdminClient } from "@/lib/supabase/admin";

export const dynamic = "force-dynamic";

const STATUS_VARIANT: Record<TransactionStatus, "confirm" | "signal" | "alert" | "neutral"> = {
  successful: "confirm",
  pending: "signal",
  failed: "alert",
  reversed: "alert",
};

export default async function TransactionsPage({
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
  const typeQ = getParam(params, "type");
  const userQ = getParam(params, "user"); // pre-filter by user id from user detail page
  const userNameQ = getParam(params, "userName");
  const fromQ = getParam(params, "from");
  const toQ = getParam(params, "to");

  let allowedUserIds: string[] | null = null;
  if (userQ) {
    allowedUserIds = [userQ];
  } else if (userNameQ) {
    const supabaseAdmin = createAdminClient();
    const { data: matchedProfiles } = await supabaseAdmin
      .from("profiles")
      .select("id")
      .ilike("full_name", `%${userNameQ}%`);
    allowedUserIds = (matchedProfiles ?? []).map((p) => p.id);
  }

  const { data: countries } = await supabase.from("countries").select("code, name").order("code");
  const countryOptions = [
    { label: "All countries", value: "" },
    ...((countries ?? []).map((c) => ({ label: `${c.name} (${c.code})`, value: c.code }))),
  ];

  if (allowedUserIds && allowedUserIds.length === 0) {
    return (
      <>
        <Header
          title="Transactions"
          description="Nipanze's own revenue only — subscriptions and contact-unlock fees, never P2P funds"
        />
        <main className="flex-1 space-y-4 overflow-y-auto p-6">
          <AdminFilterForm resetHref="/transactions" searchParams={params} fields={buildFields(countryOptions)} />
          <p className="py-10 text-center text-sm text-ink-500">No users match the name filter.</p>
        </main>
      </>
    );
  }

  let query = supabase
    .from("transactions")
    .select("id, user_id, type, amount, currency_code, country, provider, status, created_at", {
      count: "exact",
    })
    .order("created_at", { ascending: false });

  if (countryQ) query = query.eq("country", countryQ);
  if (statusQ) query = query.eq("status", statusQ);
  if (typeQ) query = query.eq("type", typeQ);
  if (fromQ) query = query.gte("created_at", `${fromQ}T00:00:00.000Z`);
  if (toQ) query = query.lte("created_at", `${toQ}T23:59:59.999Z`);
  if (allowedUserIds) query = query.in("user_id", allowedUserIds);

  const from = (page - 1) * pageSize;
  const { data: transactions, count, error } = await query.range(from, from + pageSize - 1);

  // Resolve user profile names
  const userIds = [...new Set((transactions ?? []).map((t) => t.user_id).filter(Boolean))];
  const { data: userProfiles } = userIds.length
    ? await supabase.from("profiles").select("id, full_name").in("id", userIds)
    : { data: [] };
  const userById = new Map((userProfiles ?? []).map((p) => [p.id, p]));

  return (
    <>
      <Header
        title="Transactions"
        description="Nipanze's own revenue only — subscriptions and contact-unlock fees, never P2P funds"
      />
      <main className="flex-1 space-y-4 overflow-y-auto p-6">
        <AdminFilterForm resetHref="/transactions" searchParams={params} fields={buildFields(countryOptions)} />

        {error ? (
          <p className="text-sm text-ink-500">
            No `transactions` table found yet — this ships with Stage 6 (payments).
          </p>
        ) : (
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>User</TableHead>
                <TableHead>Type</TableHead>
                <TableHead>Amount</TableHead>
                <TableHead>Market</TableHead>
                <TableHead>Provider</TableHead>
                <TableHead>Status</TableHead>
                <TableHead>Date</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {transactions?.map((tx) => {
                const user = userById.get(tx.user_id);
                return (
                  <TableRow key={tx.id}>
                    <TableCell>
                      {user ? (
                        <Link href={`/users/${tx.user_id}`} className="text-xs font-medium text-ink-700 hover:underline">
                          {user.full_name ?? `${tx.user_id.slice(0, 8)}…`}
                        </Link>
                      ) : (
                        <span className="text-xs text-ink-500">{tx.user_id.slice(0, 8)}…</span>
                      )}
                    </TableCell>
                    <TableCell className="capitalize">{tx.type.replace("_", " ")}</TableCell>
                    <TableCell className="font-tabular">{formatAmount(tx.amount, tx.currency_code)}</TableCell>
                    <TableCell>{tx.country}</TableCell>
                    <TableCell className="capitalize">{tx.provider}</TableCell>
                    <TableCell>
                      <Badge variant={STATUS_VARIANT[tx.status as TransactionStatus]}>{tx.status}</Badge>
                    </TableCell>
                    <TableCell className="text-ink-500">{formatDateTime(tx.created_at)}</TableCell>
                  </TableRow>
                );
              })}
              {!transactions?.length && (
                <TableRow>
                  <TableCell colSpan={7} className="py-10 text-center text-sm text-ink-500">
                    No transactions match this filter.
                  </TableCell>
                </TableRow>
              )}
            </TableBody>
          </Table>
        )}

        <Pagination
          page={page}
          pageSize={pageSize}
          total={count ?? 0}
          searchParams={params}
          basePath="/transactions"
        />
      </main>
    </>
  );
}

function buildFields(countryOptions: { label: string; value: string }[]) {
  return [
    { name: "userName", label: "User name", placeholder: "Full name" },
    { name: "country", label: "Country", type: "select" as const, options: countryOptions },
    {
      name: "type",
      label: "Type",
      type: "select" as const,
      options: [
        { label: "All types", value: "" },
        { label: "Subscription", value: "subscription" },
        { label: "Contact unlock", value: "contact_unlock" },
      ],
    },
    {
      name: "status",
      label: "Status",
      type: "select" as const,
      options: [
        { label: "All statuses", value: "" },
        { label: "Successful", value: "successful" },
        { label: "Pending", value: "pending" },
        { label: "Failed", value: "failed" },
        { label: "Reversed", value: "reversed" },
      ],
    },
    { name: "from", label: "Date from", type: "date" as const },
    { name: "to", label: "Date to", type: "date" as const },
  ];
}
