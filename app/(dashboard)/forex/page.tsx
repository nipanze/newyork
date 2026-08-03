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
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from "@/components/ui/card";
import { formatAmount, formatDate } from "@/lib/utils";
import { ArrowLeftRight } from "lucide-react";
import Link from "next/link";

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
  searchParams: Promise<{ country?: string; status?: string }>;
}) {
  const { country, status } = await searchParams;
  const supabase = await createClient();

  // Query defensively — falls back cleanly if the table hasn't been migrated yet.
  let query = (supabase as any)
    .from("forex_requests")
    .select("id, country, from_currency, to_currency, amount, exchange_rate, status, listed_at, expires_at, number_of_offers")
    .order("listed_at", { ascending: false })
    .limit(100);

  if (country) query = query.eq("country", country);
  if (status) query = query.eq("status", status);

  const [{ data: requests, error }, { data: countries }] = await Promise.all([
    query,
    supabase.from("countries").select("code, name").order("code"),
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
                The <code>forex_requests</code> table hasn&apos;t been migrated yet. Apply the
                Stage 4.7 migration in your mobile project&apos;s{" "}
                <code>sql/migrations/</code> directory, then reload.
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

  return (
    <>
      <Header title="Forex" description="Peer-to-peer currency exchange requests" />
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
              <TableHead>Pair</TableHead>
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
            {requests?.map((req: any) => (
              <TableRow key={req.id}>
                <TableCell>
                  <p className="font-medium text-ink-900">
                    {req.from_currency} → {req.to_currency}
                  </p>
                </TableCell>
                <TableCell>{req.country}</TableCell>
                <TableCell className="font-tabular">
                  {formatAmount(req.amount, req.from_currency)}
                </TableCell>
                <TableCell className="font-tabular">
                  {req.exchange_rate != null ? Number(req.exchange_rate).toFixed(4) : "—"}
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
                    View
                  </Link>
                </TableCell>
              </TableRow>
            ))}
            {!requests?.length && (
              <TableRow>
                <TableCell colSpan={8} className="py-10 text-center text-sm text-ink-500">
                  No forex requests match this filter.
                </TableCell>
              </TableRow>
            )}
          </TableBody>
        </Table>
      </main>
    </>
  );
}
