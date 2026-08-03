import { createClient } from "@/lib/supabase/server";
import { Header } from "@/components/header";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { formatAmount, formatDateTime } from "@/lib/utils";
import { notFound } from "next/navigation";
import Link from "next/link";

export const dynamic = "force-dynamic";

export default async function LoanDetailPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const supabase = await createClient();

  const [{ data: loan }, { data: offers }] = await Promise.all([
    supabase.from("loan_requests").select("*").eq("id", id).single(),
    supabase
      .from("loan_offers")
      .select("id, lender_id, offer_amount, interest_rate_pct, status, offered_at")
      .eq("request_id", id)
      .order("offered_at", { ascending: false }),
  ]);

  if (!loan) notFound();

  const { data: borrower } = await supabase
    .from("profiles")
    .select("id, full_name, country")
    .eq("id", loan.borrower_id)
    .single();

  return (
    <>
      <Header title={loan.title} description={`${loan.country} · ${loan.district}`} />
      <main className="flex-1 space-y-6 overflow-y-auto p-6">
        <div className="grid grid-cols-1 gap-6 lg:grid-cols-3">
          <Card className="lg:col-span-2">
            <CardHeader>
              <CardTitle>Request details</CardTitle>
            </CardHeader>
            <CardContent className="grid grid-cols-2 gap-4 pt-0 text-sm">
              <Field label="Purpose" value={loan.purpose} />
              <Field label="Requested amount" value={formatAmount(loan.requested_amount, undefined)} />
              <Field label="Duration" value={`${loan.duration_months} months`} />
              <Field label="Repayment plan" value={loan.preferred_repayment_plan} />
              <Field
                label="Repayment / period"
                value={formatAmount(loan.repayment_amount_per_period, undefined)}
              />
              <Field label="Status" value={<Badge variant="neutral">{loan.status}</Badge>} />
              <Field label="Listed" value={formatDateTime(loan.listed_at)} />
              <Field label="Expires" value={formatDateTime(loan.expires_at)} />
            </CardContent>
          </Card>

          <Card>
            <CardHeader>
              <CardTitle>Owner</CardTitle>
            </CardHeader>
            <CardContent className="pt-0 text-sm">
              {borrower ? (
                <Link href={`/users/${borrower.id}`} className="font-medium text-ink-900 hover:underline">
                  {borrower.full_name ?? borrower.id}
                </Link>
              ) : (
                "—"
              )}
              <p className="mt-1 text-xs text-ink-500">Contact details stay hidden until a contract unlocks — this console never surfaces them either.</p>
            </CardContent>
          </Card>
        </div>

        <Card>
          <CardHeader>
            <CardTitle>Offers ({offers?.length ?? 0})</CardTitle>
          </CardHeader>
          <CardContent className="space-y-2 pt-0">
            {offers?.length ? (
              offers.map((offer) => (
                <div
                  key={offer.id}
                  className="flex items-center justify-between rounded-md border border-paper-200 px-3 py-2.5 text-sm"
                >
                  <span className="font-tabular text-ink-900">
                    {formatAmount(offer.offer_amount, undefined)} @ {offer.interest_rate_pct}%
                  </span>
                  <span className="text-ink-500">{formatDateTime(offer.offered_at)}</span>
                  <Badge variant={offer.status === "accepted" ? "confirm" : "neutral"}>
                    {offer.status}
                  </Badge>
                </div>
              ))
            ) : (
              <p className="text-sm text-ink-500">No offers on this listing yet.</p>
            )}
          </CardContent>
        </Card>
      </main>
    </>
  );
}

function Field({ label, value }: { label: string; value: React.ReactNode }) {
  return (
    <div>
      <p className="text-xs font-medium uppercase tracking-wide text-ink-500">{label}</p>
      <div className="mt-0.5 text-ink-900">{value}</div>
    </div>
  );
}
