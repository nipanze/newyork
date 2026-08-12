import { createClient } from "@/lib/supabase/server";
import { Header } from "@/components/header";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { formatAmount, formatDateTime } from "@/lib/utils";
import { notFound } from "next/navigation";
import Link from "next/link";
import { ForexModerationActions } from "@/components/forex-moderation-actions";

export const dynamic = "force-dynamic";

export default async function ForexDetailPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const supabase = await createClient();

  const [{ data: request }, { data: offers }] = await Promise.all([
    (supabase as any).from("forex_requests").select("*").eq("id", id).single(),
    (supabase as any)
      .from("forex_offers")
      .select("*")
      .eq("request_id", id)
      .order("offered_at", { ascending: false }),
  ]);

  if (!request) notFound();

  const requesterId = request.requester_id ?? request.user_id;
  const { data: owner } = requesterId
    ? await (supabase as any)
        .from("profiles")
        .select("id, full_name, country")
        .eq("id", requesterId)
        .single()
    : { data: null };

  const fromCurr = request.currency_held ?? request.from_currency ?? "—";
  const toCurr = request.currency_needed ?? request.to_currency ?? "—";
  const rate = request.preferred_rate ?? request.exchange_rate;

  return (
    <>
      <Header
        title={`${fromCurr} → ${toCurr}`}
        description={`${request.country} · ${request.status}`}
      />
      <main className="flex-1 space-y-6 overflow-y-auto p-6">
        <div className="grid grid-cols-1 gap-6 lg:grid-cols-3">
          <Card className="lg:col-span-2">
            <CardHeader>
              <CardTitle>Request details</CardTitle>
            </CardHeader>
            <CardContent className="grid grid-cols-2 gap-4 pt-0 text-sm">
              <Field label="From" value={fromCurr} />
              <Field label="To" value={toCurr} />
              <Field label="Amount" value={formatAmount(request.amount, fromCurr)} />
              <Field
                label="Desired rate"
                value={rate != null ? Number(rate).toFixed(4) : "—"}
              />
              <Field label="Market" value={request.country} />
              <Field label="Status" value={<Badge variant="neutral">{request.status}</Badge>} />
              <Field label="Listed" value={formatDateTime(request.listed_at)} />
              <Field label="Expires" value={formatDateTime(request.expires_at)} />
            </CardContent>
          </Card>

          <Card>
            <CardHeader>
              <CardTitle>Owner & Actions</CardTitle>
            </CardHeader>
            <CardContent className="space-y-4 pt-0 text-sm">
              <div>
                <p className="text-xs font-medium uppercase tracking-wide text-ink-500">Owner</p>
                {owner ? (
                  <Link href={`/users/${owner.id}`} className="font-medium text-ink-900 hover:underline">
                    {owner.full_name ?? owner.id}
                  </Link>
                ) : (
                  "—"
                )}
              </div>

              <ForexModerationActions requestId={request.id} currentStatus={request.status} />
            </CardContent>
          </Card>
        </div>

        <Card>
          <CardHeader>
            <CardTitle>Offers ({offers?.length ?? 0})</CardTitle>
          </CardHeader>
          <CardContent className="space-y-2 pt-0">
            {offers?.length ? (
              offers.map((offer: any) => {
                const offerAmt = offer.amount_available ?? offer.offered_amount;
                const offerRate = offer.rate_offered ?? offer.offered_rate;

                return (
                  <div
                    key={offer.id}
                    className="flex items-center justify-between rounded-md border border-paper-200 px-3 py-2.5 text-sm"
                  >
                    <span className="font-tabular text-ink-900">
                      {formatAmount(offerAmt, undefined)} @ {offerRate != null ? Number(offerRate).toFixed(4) : "—"}
                    </span>
                    <span className="text-ink-500">{formatDateTime(offer.offered_at)}</span>
                    <Badge variant={offer.status === "accepted" ? "confirm" : "neutral"}>
                      {offer.status}
                    </Badge>
                  </div>
                );
              })
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

