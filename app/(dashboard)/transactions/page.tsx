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
import { formatAmount, formatDateTime } from "@/lib/utils";
import type { TransactionStatus } from "@/lib/types";

export const dynamic = "force-dynamic";

const STATUS_VARIANT: Record<TransactionStatus, "confirm" | "signal" | "alert" | "neutral"> = {
  successful: "confirm",
  pending: "signal",
  failed: "alert",
  reversed: "alert",
};

export default async function TransactionsPage() {
  const supabase = await createClient();

  const { data: transactions, error } = await supabase
    .from("transactions")
    .select("id, user_id, type, amount, currency_code, country, provider, status, created_at")
    .order("created_at", { ascending: false })
    .limit(100);

  return (
    <>
      <Header
        title="Transactions"
        description="Nipanze's own revenue only — subscriptions and contact-unlock fees, never P2P funds"
      />
      <main className="flex-1 space-y-4 overflow-y-auto p-6">
        {error ? (
          <p className="text-sm text-ink-500">
            No `transactions` table found yet — this ships with Stage 6 (payments).
          </p>
        ) : (
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Type</TableHead>
                <TableHead>Amount</TableHead>
                <TableHead>Market</TableHead>
                <TableHead>Provider</TableHead>
                <TableHead>Status</TableHead>
                <TableHead>Date</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {transactions?.map((tx) => (
                <TableRow key={tx.id}>
                  <TableCell className="capitalize">{tx.type.replace("_", " ")}</TableCell>
                  <TableCell className="font-tabular">{formatAmount(tx.amount, tx.currency_code)}</TableCell>
                  <TableCell>{tx.country}</TableCell>
                  <TableCell className="capitalize">{tx.provider}</TableCell>
                  <TableCell>
                    <Badge variant={STATUS_VARIANT[tx.status]}>{tx.status}</Badge>
                  </TableCell>
                  <TableCell className="text-ink-500">{formatDateTime(tx.created_at)}</TableCell>
                </TableRow>
              ))}
              {!transactions?.length && (
                <TableRow>
                  <TableCell colSpan={6} className="py-10 text-center text-sm text-ink-500">
                    No transactions recorded yet.
                  </TableCell>
                </TableRow>
              )}
            </TableBody>
          </Table>
        )}
      </main>
    </>
  );
}
