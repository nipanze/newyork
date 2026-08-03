import { createClient } from "@/lib/supabase/server";
import { Header } from "@/components/header";
import { Badge } from "@/components/ui/badge";
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
  searchParams: Promise<{ country?: string; status?: string }>;
}) {
  const { country, status } = await searchParams;
  const supabase = await createClient();

  let query = supabase
    .from("loan_requests")
    .select("id, title, country, district, requested_amount, status, number_of_offers, listed_at, expires_at")
    .order("listed_at", { ascending: false })
    .limit(100);

  if (country) query = query.eq("country", country);
  if (status) query = query.eq("status", status);

  const { data: loans } = await query;
  const { data: countries } = await supabase.from("countries").select("code, name").order("code");

  return (
    <>
      <Header title="Loans" description="Every loan listing across every active market" />
      <main className="flex-1 space-y-4 overflow-y-auto p-6">
        <form method="GET" className="flex flex-wrap gap-2">
          <select
            name="country"
            defaultValue={country ?? ""}
            className="h-9 rounded-md border border-paper-300 bg-white px-3 text-sm shadow-sm"
            onChange={(e) => (e.currentTarget.form as HTMLFormElement).submit()}
          >
            <option value="">All markets</option>
            {countries?.map((c) => (
              <option key={c.code} value={c.code}>
                {c.name}
              </option>
            ))}
          </select>
          <select
            name="status"
            defaultValue={status ?? ""}
            className="h-9 rounded-md border border-paper-300 bg-white px-3 text-sm shadow-sm"
            onChange={(e) => (e.currentTarget.form as HTMLFormElement).submit()}
          >
            <option value="">All statuses</option>
            <option value="active">Active</option>
            <option value="contracted">Contracted</option>
            <option value="expired">Expired</option>
            <option value="cancelled">Cancelled</option>
          </select>
          <button type="submit" className="h-9 rounded-md bg-ink-900 px-4 text-sm font-medium text-paper-50">
            Filter
          </button>
        </form>

        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Listing</TableHead>
              <TableHead>Market</TableHead>
              <TableHead>Amount</TableHead>
              <TableHead>Offers</TableHead>
              <TableHead>Status</TableHead>
              <TableHead>Listed</TableHead>
              <TableHead />
            </TableRow>
          </TableHeader>
          <TableBody>
            {loans?.map((loan) => (
              <TableRow key={loan.id}>
                <TableCell>
                  <p className="font-medium text-ink-900">{loan.title}</p>
                  <p className="text-xs text-ink-500">{loan.district}</p>
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
                    View
                  </Link>
                </TableCell>
              </TableRow>
            ))}
            {!loans?.length && (
              <TableRow>
                <TableCell colSpan={7} className="py-10 text-center text-sm text-ink-500">
                  No listings match this filter.
                </TableCell>
              </TableRow>
            )}
          </TableBody>
        </Table>
      </main>
    </>
  );
}
