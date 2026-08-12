import { createClient } from "@/lib/supabase/server";
import { Header } from "@/components/header";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { AccountActions } from "@/components/account-actions";
import { formatAmount, formatDateTime } from "@/lib/utils";
import { notFound } from "next/navigation";
import { createAdminClient } from "@/lib/supabase/admin";
import Link from "next/link";

export const dynamic = "force-dynamic";

export default async function UserDetailPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const supabase = await createClient();
  const supabaseAdmin = createAdminClient();

  const [
    { data: profile },
    { data: authUser },
    { data: subscription },
    { data: kyc },
    { data: loans },
    { data: trust },
    { data: auditLogs },
    { data: loanOffers },
    forexRequests,
    forexOffers,
    transactions,
  ] =
    await Promise.all([
      supabase.from("profiles").select("*").eq("id", id).single(),
      supabaseAdmin.auth.admin.getUserById(id),
      supabase.from("subscriptions").select("*").eq("user_id", id).eq("status", "active").maybeSingle(),
      supabase.from("kyc_verifications").select("*").eq("user_id", id).maybeSingle(),
      supabase
        .from("loan_requests")
        .select("id, title, status, requested_amount, country, listed_at")
        .eq("borrower_id", id)
        .order("listed_at", { ascending: false })
        .limit(5),
      supabase.from("v_trust_profile_public").select("*").eq("user_id", id).maybeSingle(),
      supabase
        .from("audit_logs")
        .select("id, event_type, action, entity_type, entity_id, created_at")
        .or(`user_id.eq.${id},entity_id.eq.${id}`)
        .order("created_at", { ascending: false })
        .limit(6),
      supabase
        .from("loan_offers")
        .select("id, request_id, offer_amount, interest_rate_pct, status, offered_at")
        .eq("lender_id", id)
        .order("offered_at", { ascending: false })
        .limit(5),
      getForexRequestsForUser(supabase, id),
      getForexOffersForUser(supabase, id),
      getTransactionsForUser(supabase, id),
    ]);

  if (!profile) notFound();

  return (
    <>
      <Header title={profile.full_name ?? "Unnamed account"} description={id} />
      <main className="flex-1 space-y-6 overflow-y-auto p-6">
        <div className="grid grid-cols-1 gap-6 lg:grid-cols-3">
          <Card className="lg:col-span-2">
            <CardHeader>
              <CardTitle>Profile</CardTitle>
            </CardHeader>
            <CardContent className="grid grid-cols-2 gap-4 pt-0 text-sm">
              <Field label="Email" value={authUser.user?.email ?? "—"} />
              <Field label="Phone" value={profile.phone ?? "—"} />
              <Field
                label="Phone verified"
                value={profile.phone_verified_at ? formatDateTime(profile.phone_verified_at) : "Not verified"}
              />
              <Field label="Country" value={profile.country} />
              <Field label="District" value={profile.district ?? "—"} />
              <Field label="Employment" value={profile.employment_type ?? "—"} />
              <Field label="Employer" value={profile.employer_name ?? "—"} />
              <Field
                label="Monthly income"
                value={formatAmount(profile.monthly_income, profile.income_currency)}
              />
              <Field label="Plan" value={subscription?.plan ?? "free"} />
              <Field label="Free unlocks left" value={String(profile.free_unlocks_remaining)} />
              <Field label="Joined" value={formatDateTime(profile.created_at)} />
            </CardContent>
          </Card>

          <Card>
            <CardHeader>
              <CardTitle>Actions</CardTitle>
            </CardHeader>
            <CardContent className="pt-0">
              <AccountActions
                userId={profile.id}
                currentStatus={profile.account_status}
                currentPlan={subscription?.plan ?? "free"}
                isAdmin={profile.is_admin}
              />
            </CardContent>
          </Card>
        </div>

        <div className="grid grid-cols-1 gap-6 lg:grid-cols-2">
          <Card>
            <CardHeader>
              <CardTitle className="flex items-center justify-between gap-3">
                KYC
                {kyc ? (
                  <Link href={`/kyc/${kyc.id}`} className="text-xs font-medium text-ink-700 hover:underline">
                    Open review
                  </Link>
                ) : null}
              </CardTitle>
            </CardHeader>
            <CardContent className="space-y-2 pt-0 text-sm">
              {kyc ? (
                <>
                  <Field label="Status" value={<Badge variant="neutral">{kyc.status}</Badge>} />
                  <Field label="ID type" value={kyc.national_id_type ?? "—"} />
                  <Field label="Submitted" value={formatDateTime(kyc.submitted_at)} />
                  <Field label="Reviewed" value={formatDateTime(kyc.reviewed_at)} />
                </>
              ) : (
                <p className="text-ink-500">No KYC submission on file.</p>
              )}
            </CardContent>
          </Card>

          <Card>
            <CardHeader>
              <CardTitle>Trust signals</CardTitle>
            </CardHeader>
            <CardContent className="space-y-2 pt-0 text-sm">
              <Field label="Rating" value={trust?.rating_avg ? `${trust.rating_avg} / 5` : "No reviews yet"} />
              <Field label="Completed deals" value={String(trust?.completed_deals_count ?? 0)} />
              <Field label="Repeat participant" value={trust?.is_repeat_participant ? "Yes" : "No"} />
              <Field label="Response time" value={trust?.response_time_bucket ?? "—"} />
            </CardContent>
          </Card>
        </div>

        <div className="grid grid-cols-1 gap-6 lg:grid-cols-2">
          <Card>
            <CardHeader>
              <CardTitle className="flex items-center justify-between gap-3">
                Recent loan requests
                <Link href={`/loans?borrower=${id}`} className="text-xs font-medium text-ink-700 hover:underline">
                  View loan activity
                </Link>
              </CardTitle>
            </CardHeader>
            <CardContent className="space-y-2 pt-0">
              {loans?.length ? (
                loans.map((loan) => (
                  <ActivityRow key={loan.id} href={`/loans/${loan.id}`}>
                    <span className="font-medium text-ink-900">{loan.title}</span>
                    <span className="font-tabular text-ink-700">
                      {formatAmount(loan.requested_amount, undefined)}
                    </span>
                    <Badge variant="neutral">{loan.status}</Badge>
                  </ActivityRow>
                ))
              ) : (
                <p className="text-sm text-ink-500">No loan requests posted.</p>
              )}
            </CardContent>
          </Card>

          <Card>
            <CardHeader>
              <CardTitle className="flex items-center justify-between gap-3">
                Recent forex requests
                <Link href={`/forex?requester=${id}`} className="text-xs font-medium text-ink-700 hover:underline">
                  View forex activity
                </Link>
              </CardTitle>
            </CardHeader>
            <CardContent className="space-y-2 pt-0">
              {forexRequests.length ? (
                forexRequests.map((request: any) => (
                  <ActivityRow key={request.id} href={`/forex/${request.id}`}>
                    <span className="font-medium text-ink-900">
                      {request.currency_held ?? request.from_currency ?? "?"} to{" "}
                      {request.currency_needed ?? request.to_currency ?? "?"}
                    </span>
                    <span className="font-tabular text-ink-700">
                      {formatAmount(request.amount, request.currency_held ?? request.from_currency)}
                    </span>
                    <Badge variant="neutral">{request.status}</Badge>
                  </ActivityRow>
                ))
              ) : (
                <p className="text-sm text-ink-500">No forex requests posted.</p>
              )}
            </CardContent>
          </Card>
        </div>

        <div className="grid grid-cols-1 gap-6 lg:grid-cols-2">
          <Card>
            <CardHeader>
              <CardTitle>Offers made</CardTitle>
            </CardHeader>
            <CardContent className="space-y-2 pt-0">
              {loanOffers?.map((offer) => (
                <ActivityRow key={offer.id} href={`/loans/${offer.request_id}`}>
                  <span className="font-medium text-ink-900">Loan offer</span>
                  <span className="font-tabular text-ink-700">
                    {formatAmount(offer.offer_amount, undefined)} @ {offer.interest_rate_pct}%
                  </span>
                  <Badge variant={offer.status === "accepted" ? "confirm" : "neutral"}>{offer.status}</Badge>
                </ActivityRow>
              ))}
              {forexOffers.map((offer: any) => (
                <ActivityRow key={offer.id} href={`/forex/${offer.request_id}`}>
                  <span className="font-medium text-ink-900">Forex offer</span>
                  <span className="font-tabular text-ink-700">
                    {formatAmount(offer.amount_available ?? offer.offered_amount, undefined)}
                  </span>
                  <Badge variant={offer.status === "accepted" ? "confirm" : "neutral"}>{offer.status}</Badge>
                </ActivityRow>
              ))}
              {!loanOffers?.length && !forexOffers.length ? (
                <p className="text-sm text-ink-500">No offers made.</p>
              ) : null}
            </CardContent>
          </Card>

          <Card>
            <CardHeader>
              <CardTitle className="flex items-center justify-between gap-3">
                Transactions
                <Link href={`/transactions?user=${id}`} className="text-xs font-medium text-ink-700 hover:underline">
                  View transactions
                </Link>
              </CardTitle>
            </CardHeader>
            <CardContent className="space-y-2 pt-0">
              {transactions.length ? (
                transactions.map((tx: any) => (
                  <div
                    key={tx.id}
                    className="flex items-center justify-between rounded-md border border-paper-200 px-3 py-2.5 text-sm"
                  >
                    <span className="font-medium capitalize text-ink-900">{tx.type?.replace("_", " ")}</span>
                    <span className="font-tabular text-ink-700">{formatAmount(tx.amount, tx.currency_code)}</span>
                    <Badge variant={tx.status === "successful" ? "confirm" : tx.status === "pending" ? "signal" : "alert"}>
                      {tx.status}
                    </Badge>
                  </div>
                ))
              ) : (
                <p className="text-sm text-ink-500">No platform transactions recorded.</p>
              )}
            </CardContent>
          </Card>
        </div>

        <Card>
          <CardHeader>
            <CardTitle className="flex items-center justify-between gap-3">
              Recent audit events
              <Link href={`/audit-logs?target=${id}`} className="text-xs font-medium text-ink-700 hover:underline">
                View audit trail
              </Link>
            </CardTitle>
          </CardHeader>
          <CardContent className="space-y-2 pt-0">
            {auditLogs?.length ? (
              auditLogs.map((log) => (
                <div
                  key={log.id}
                  className="flex items-center justify-between rounded-md border border-paper-200 px-3 py-2.5 text-sm"
                >
                  <div>
                    <p className="font-medium text-ink-900">{log.action ?? log.event_type}</p>
                    <p className="text-xs text-ink-500">
                      {log.entity_type ?? "system"} · {log.entity_id ?? "—"} · {formatDateTime(log.created_at)}
                    </p>
                  </div>
                  <Badge variant="outline">{log.event_type}</Badge>
                </div>
              ))
            ) : (
              <p className="text-sm text-ink-500">No audit events found for this account.</p>
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

function ActivityRow({
  href,
  children,
}: {
  href: string;
  children: React.ReactNode;
}) {
  return (
    <Link
      href={href}
      className="flex items-center justify-between gap-3 rounded-md border border-paper-200 px-3 py-2.5 text-sm hover:bg-paper-50"
    >
      {children}
    </Link>
  );
}

async function getForexRequestsForUser(
  supabase: Awaited<ReturnType<typeof createClient>>,
  userId: string
) {
  const { data, error } = await (supabase as any)
    .from("forex_requests")
    .select("id, country, currency_held, currency_needed, amount, status, listed_at")
    .eq("requester_id", userId)
    .order("listed_at", { ascending: false })
    .limit(5);

  if (error) return [];
  return data ?? [];
}

async function getForexOffersForUser(
  supabase: Awaited<ReturnType<typeof createClient>>,
  userId: string
) {
  const { data, error } = await (supabase as any)
    .from("forex_offers")
    .select("id, request_id, amount_available, offered_amount, rate_offered, offered_rate, status, offered_at")
    .eq("offer_maker_id", userId)
    .order("offered_at", { ascending: false })
    .limit(5);

  if (error) return [];
  return data ?? [];
}

async function getTransactionsForUser(
  supabase: Awaited<ReturnType<typeof createClient>>,
  userId: string
) {
  const { data, error } = await supabase
    .from("transactions")
    .select("id, type, amount, currency_code, status, created_at")
    .eq("user_id", userId)
    .order("created_at", { ascending: false })
    .limit(5);

  if (error) return [];
  return data ?? [];
}
