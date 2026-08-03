import { createClient } from "@/lib/supabase/server";
import { Header } from "@/components/header";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { formatAmount, formatDateTime } from "@/lib/utils";
import { notFound } from "next/navigation";
import Link from "next/link";

export const dynamic = "force-dynamic";

export default async function ForexDetailPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const supabase = await createClient();

  const [{ data: request }, { data: offers }] = await Promise.all([
    (supabase as any).from("forex_requests").select("*").eq("id", id).single(),
    (supabase as any)
      .from("forex_offers")
      .select("id, offerer_id, offered_rate, offered_amount, status, offered_at")
      .eq("request_id", id)
      .order("offered_at", { ascending: false }),
  ]);

  if (!request) notFound();

  const { data: owner } = await (supabase as any)
    .from("profiles")
    .select("id, full_name, country")
    .eq("id", request.user_id)
    .single();

  return (
    <>
      <Header
        title={`${request.from_currency} → ${request.to_currency}`}
        description={`${request.country} · ${request.status}`}
      />
      <main className="flex-1 space-y-6 overflow-y-auto p-6">
        <div className="grid grid-cols-1 gap-6 lg:grid-cols-3">
          <Card className="lg:col-span-2">
            <CardHeader>
              <CardTitle>Request details</CardTitle>
            </CardHeader>
            <CardContent className="grid grid-cols-2 gap-4 pt-0 text-sm">
              <Field label="From" value={request.from_currency} />
              <Field label="To" value={request.to_currency} />
              <Field label="Amount" value={formatAmount(request.amount, request.from_currency)} />
              <Field
                label="Desired rate"
                value={request.exchange_rate != null ? Number(request.exchange_rate).toFixed(4) : "—"}
              />
              <Field label="Market" value={request.country} />
              <Field label="Status" value={<Badge variant="neutral">{request.status}</Badge>} />
              <Field label="Listed" value={formatDateTime(request.listed_at)} />
              <Field label="Expires" value={formatDateTime(request.expires_at)} />
            </CardContent>
          </Card>

          <Card>
            <CardHeader>
              <CardTitle>Owner</CardTitle>
            </CardHeader>
            <CardContent className="pt-0 text-sm">
              {owner ? (
                <Link href={`/users/${owner.id}`} className="font-medium text-ink-900 hover:underline">
                  {owner.full_name ?? owner.id}
                </Link>
              ) : (
                "—"
              )}
            </CardContent>
          </Card>
        </div>

        <Card>
          <CardHeader>
            <CardTitle>Offers ({offers?.length ?? 0})</CardTitle>
          </CardHeader>
          <CardContent className="space-y-2 pt-0">
            {offers?.length ? (
              offers.map((offer: any) => (
                <div
                  key={offer.id}
                  className="flex items-center justify-between rounded-md border border-paper-200 px-3 py-2.5 text-sm"
                >
                  <span className="font-tabular text-ink-900">
                    {formatAmount(offer.offered_amount, undefined)} @ {Number(offer.offered_rate).toFixed(4)}
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
