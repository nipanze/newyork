import { createClient } from "@/lib/supabase/server";
import { Header } from "@/components/header";
import { StatCard } from "@/components/stat-card";
import { AdminFilterForm } from "@/components/admin-filter-form";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { formatAmount, formatDateTime } from "@/lib/utils";
import { buildQueryString, getParam, type DashboardSearchParams } from "@/lib/dashboard-filters";
import {
  ArrowLeftRight,
  BadgeCheck,
  Globe2,
  HandCoins,
  Receipt,
  ShieldCheck,
  Users,
  UserX,
} from "lucide-react";
import Link from "next/link";

export const dynamic = "force-dynamic";

const STATUS_VARIANT: Record<string, "confirm" | "signal" | "alert" | "neutral"> = {
  active: "confirm",
  pending_verification: "signal",
  suspended: "alert",
  deactivated: "neutral",
};

export default async function DashboardOverviewPage({
  searchParams,
}: {
  searchParams: Promise<DashboardSearchParams>;
}) {
  const params = await searchParams;
  const supabase = await createClient();
  const country = getParam(params, "country");
  const module = getParam(params, "module");
  const fromDate = getParam(params, "from");
  const toDate = getParam(params, "to");

  const {
    data: { user },
  } = await supabase.auth.getUser();

  const applyDateRange = <T extends any>(query: T, column: string) => {
    let scoped = query as any;
    if (fromDate) scoped = scoped.gte(column, `${fromDate}T00:00:00.000Z`);
    if (toDate) scoped = scoped.lte(column, `${toDate}T23:59:59.999Z`);
    return scoped as T;
  };

  let totalAccountsQuery = supabase.from("profiles").select("id", { count: "exact", head: true });
  let activeAccountsQuery = supabase
    .from("profiles")
    .select("id", { count: "exact", head: true })
    .eq("account_status", "active");
  let suspendedAccountsQuery = supabase
    .from("profiles")
    .select("id", { count: "exact", head: true })
    .eq("account_status", "suspended");
  let pendingKycQuery = supabase
    .from("kyc_verifications")
    .select("id", { count: "exact", head: true })
    .eq("status", "pending");
  let approvedKycQuery = supabase
    .from("kyc_verifications")
    .select("id", { count: "exact", head: true })
    .eq("status", "approved");
  let activeLoanQuery = supabase
    .from("loan_requests")
    .select("id", { count: "exact", head: true })
    .eq("status", "active");
  let recentLoansQuery = supabase
    .from("loan_requests")
    .select("id, title, country, requested_amount, status, listed_at")
    .order("listed_at", { ascending: false })
    .limit(5);
  let latestUsersQuery = supabase
    .from("profiles")
    .select("id, full_name, phone, country, account_status, created_at")
    .order("created_at", { ascending: false })
    .limit(5);
  let latestKycQuery = supabase
    .from("kyc_verifications")
    .select("id, user_id, status, national_id_type, submitted_at")
    .eq("status", "pending")
    .order("submitted_at", { ascending: true })
    .limit(5);
  let auditQuery = supabase
    .from("audit_logs")
    .select("id, user_id, event_type, action, entity_type, entity_id, created_at")
    .order("created_at", { ascending: false })
    .limit(6);

  if (country) {
    totalAccountsQuery = totalAccountsQuery.eq("country", country);
    activeAccountsQuery = activeAccountsQuery.eq("country", country);
    suspendedAccountsQuery = suspendedAccountsQuery.eq("country", country);
    activeLoanQuery = activeLoanQuery.eq("country", country);
    recentLoansQuery = recentLoansQuery.eq("country", country);
    latestUsersQuery = latestUsersQuery.eq("country", country);
  }

  totalAccountsQuery = applyDateRange(totalAccountsQuery, "created_at");
  activeAccountsQuery = applyDateRange(activeAccountsQuery, "created_at");
  suspendedAccountsQuery = applyDateRange(suspendedAccountsQuery, "created_at");
  pendingKycQuery = applyDateRange(pendingKycQuery, "submitted_at");
  approvedKycQuery = applyDateRange(approvedKycQuery, "submitted_at");
  activeLoanQuery = applyDateRange(activeLoanQuery, "listed_at");
  recentLoansQuery = applyDateRange(recentLoansQuery, "listed_at");
  latestUsersQuery = applyDateRange(latestUsersQuery, "created_at");
  latestKycQuery = applyDateRange(latestKycQuery, "submitted_at");
  auditQuery = applyDateRange(auditQuery, "created_at");

  const [
    { count: userCount },
    { count: activeUserCount },
    { count: suspendedUserCount },
    { count: activeLoanCount },
    { count: pendingKycCount },
    { count: approvedKycCount },
    { count: activeCountryCount },
    { count: forexCountryCount },
    { data: recentLoans },
    { data: latestUsers },
    { data: latestKyc },
    { data: auditLogs },
    { data: countries },
    { data: subscriptions },
    { data: profile },
    { data: allCountriesRaw },
  ] = await Promise.all([
    totalAccountsQuery,
    activeAccountsQuery,
    suspendedAccountsQuery,
    activeLoanQuery,
    pendingKycQuery,
    approvedKycQuery,
    supabase.from("countries").select("code", { count: "exact", head: true }).eq("is_active", true),
    (supabase as any)
      .from("countries")
      .select("code", { count: "exact", head: true })
      .eq("forex_enabled", true),
    recentLoansQuery,
    latestUsersQuery,
    latestKycQuery,
    auditQuery,
    supabase.from("countries").select("code, name").order("code"),
    supabase.from("subscriptions").select("plan, status").eq("status", "active"),
    supabase.from("profiles").select("full_name").eq("id", user!.id).single(),
    supabase.from("countries").select("code, name, is_active, forex_enabled").order("name"),
  ]);

  const forexRequests =
    module === "loans"
      ? { count: 0, data: [] as any[] }
      : await getForexOverview(supabase, { country, fromDate, toDate });

  const planCounts = (subscriptions ?? []).reduce(
    (acc, sub) => {
      const plan = sub.plan as "free" | "lender" | "pro";
      if (plan in acc) acc[plan] += 1;
      return acc;
    },
    { free: 0, lender: 0, pro: 0 }
  );

  const countryOptions = [
    { label: "All countries", value: "" },
    ...((countries ?? []).map((c) => ({ label: `${c.name} (${c.code})`, value: c.code })) ?? []),
  ];
  const showLoans = module !== "forex";
  const showForex = module !== "loans";

  // Markets needing attention: inactive countries that still have active loan listings
  const allCountriesData = allCountriesRaw ?? [];
  const inactiveCountryCodes = new Set(allCountriesData.filter((c: any) => !c.is_active).map((c: any) => c.code));
  const { data: activeLoansPerCountry } = await supabase
    .from("loan_requests")
    .select("country")
    .eq("status", "active");
  const loansInInactiveMarkets = (activeLoansPerCountry ?? []).filter((l) =>
    inactiveCountryCodes.has(l.country)
  );
  const marketsNeedingAttention = allCountriesData.filter(
    (c: any) => !c.is_active && loansInInactiveMarkets.some((l) => l.country === c.code)
  );

  return (
    <>
      <Header
        title="Overview"
        description="Marketplace health across every active market"
        adminName={profile?.full_name}
      />
      <main className="flex-1 space-y-6 overflow-y-auto p-6">
        <AdminFilterForm
          resetHref="/dashboard"
          searchParams={params}
          fields={[
            { name: "country", label: "Country", type: "select", options: countryOptions },
            {
              name: "module",
              label: "Module",
              type: "select",
              options: [
                { label: "All modules", value: "" },
                { label: "Loans", value: "loans" },
                { label: "Forex", value: "forex" },
              ],
            },
            { name: "from", label: "From", type: "date" },
            { name: "to", label: "To", type: "date" },
          ]}
        />

        <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-4">
          <StatCard label="Total accounts" value={userCount ?? 0} icon={Users} />
          <StatCard label="Active accounts" value={activeUserCount ?? 0} icon={BadgeCheck} tone="confirm" />
          <StatCard label="Suspended accounts" value={suspendedUserCount ?? 0} icon={UserX} tone={suspendedUserCount ? "alert" : "neutral"} />
          <StatCard label="Active loan listings" value={activeLoanCount ?? 0} icon={HandCoins} />
          <StatCard
            label="KYC pending review"
            value={pendingKycCount ?? 0}
            icon={ShieldCheck}
            tone={pendingKycCount ? "signal" : "neutral"}
            hint={pendingKycCount ? "Needs attention" : "All caught up"}
          />
          <StatCard label="KYC approved" value={approvedKycCount ?? 0} icon={ShieldCheck} tone="confirm" />
          <StatCard label="Active forex requests" value={forexRequests.count} icon={ArrowLeftRight} />
          <StatCard label="Active markets" value={activeCountryCount ?? 0} icon={Globe2} />
          <StatCard label="Forex markets" value={forexCountryCount ?? 0} icon={Globe2} />
        </div>

        <div className="grid grid-cols-1 gap-4 lg:grid-cols-3">
          <Card>
            <CardHeader>
              <CardTitle>Subscriptions</CardTitle>
            </CardHeader>
            <CardContent className="grid grid-cols-3 gap-3 pt-0 text-sm">
              <MiniStat label="Free" value={planCounts.free} />
              <MiniStat label="Lender" value={planCounts.lender} />
              <MiniStat label="Pro" value={planCounts.pro} />
            </CardContent>
          </Card>

          <Card className="lg:col-span-2">
            <CardHeader>
              <CardTitle>Quick controls</CardTitle>
            </CardHeader>
            <CardContent className="flex flex-wrap gap-2 pt-0">
              <QuickLink href={`/users?${buildQueryString(params, { page: 1 })}`}>Accounts</QuickLink>
              <QuickLink href={`/kyc?${buildQueryString(params, { status: "pending", page: 1 })}`}>Pending KYC</QuickLink>
              <QuickLink href={`/loans?${buildQueryString(params, { status: "active", page: 1 })}`}>Active Loans</QuickLink>
              <QuickLink href={`/forex?${buildQueryString(params, { status: "active", page: 1 })}`}>Active Forex</QuickLink>
              <QuickLink href="/countries">Markets & Pricing</QuickLink>
              <QuickLink href="/audit-logs">Audit Logs</QuickLink>
            </CardContent>
          </Card>
        </div>

        <div className="grid grid-cols-1 gap-4 xl:grid-cols-2">
          <QueueCard title="Latest accounts" href={`/users?${buildQueryString(params, { page: 1 })}`}>
            {latestUsers?.length ? (
              latestUsers.map((latestUser) => (
                <RowLink key={latestUser.id} href={`/users/${latestUser.id}`}>
                  <div>
                    <p className="text-sm font-medium text-ink-900">{latestUser.full_name ?? "Unnamed account"}</p>
                    <p className="text-xs text-ink-500">
                      {latestUser.phone ?? "no phone"} · {latestUser.country} · {formatDateTime(latestUser.created_at)}
                    </p>
                  </div>
                  <Badge variant={STATUS_VARIANT[latestUser.account_status as keyof typeof STATUS_VARIANT] ?? "neutral"}>
                    {latestUser.account_status}
                  </Badge>
                </RowLink>
              ))
            ) : (
              <EmptyQueue>No new accounts match this filter.</EmptyQueue>
            )}
          </QueueCard>

          <QueueCard title="Pending KYC" href="/kyc">
            {latestKyc?.length ? (
              latestKyc.map((kyc) => (
                <RowLink key={kyc.id} href={`/kyc/${kyc.id}`}>
                  <div>
                    <p className="text-sm font-medium text-ink-900">{kyc.user_id}</p>
                    <p className="text-xs text-ink-500">
                      {kyc.national_id_type ?? "ID type not set"} · {formatDateTime(kyc.submitted_at)}
                    </p>
                  </div>
                  <Badge variant="signal">{kyc.status}</Badge>
                </RowLink>
              ))
            ) : (
              <EmptyQueue>No pending KYC submissions.</EmptyQueue>
            )}
          </QueueCard>
        </div>

        <div className="grid grid-cols-1 gap-4 xl:grid-cols-2">
          {showLoans ? (
            <QueueCard title="Recent loan listings" href={`/loans?${buildQueryString(params, { page: 1 })}`}>
              {recentLoans?.length ? (
                recentLoans.map((loan) => (
                  <RowLink key={loan.id} href={`/loans/${loan.id}`}>
                    <div>
                      <p className="text-sm font-medium text-ink-900">{loan.title}</p>
                      <p className="text-xs text-ink-500">
                        {loan.country} · {formatDateTime(loan.listed_at)}
                      </p>
                    </div>
                    <div className="flex items-center gap-3">
                      <span className="font-tabular text-sm text-ink-700">
                        {formatAmount(loan.requested_amount, undefined)}
                      </span>
                      <Badge variant={loan.status === "active" ? "confirm" : "neutral"}>{loan.status}</Badge>
                    </div>
                  </RowLink>
                ))
              ) : (
                <EmptyQueue>No loan listings match this filter.</EmptyQueue>
              )}
            </QueueCard>
          ) : null}

          {showForex ? (
            <QueueCard title="Recent forex requests" href={`/forex?${buildQueryString(params, { page: 1 })}`}>
              {forexRequests.data.length ? (
                forexRequests.data.map((req: any) => (
                  <RowLink key={req.id} href={`/forex/${req.id}`}>
                    <div>
                      <p className="text-sm font-medium text-ink-900">
                        {req.currency_held ?? req.from_currency ?? "?"} to {req.currency_needed ?? req.to_currency ?? "?"}
                      </p>
                      <p className="text-xs text-ink-500">
                        {req.country} · {formatDateTime(req.listed_at)}
                      </p>
                    </div>
                    <Badge variant={req.status === "active" ? "confirm" : "neutral"}>{req.status}</Badge>
                  </RowLink>
                ))
              ) : (
                <EmptyQueue>No forex requests match this filter.</EmptyQueue>
              )}
            </QueueCard>
          ) : null}
        </div>

        <QueueCard title="Recent audit events" href="/audit-logs">
          {auditLogs?.length ? (
            auditLogs.map((log) => (
              <RowLink key={log.id} href="/audit-logs">
                <div>
                  <p className="text-sm font-medium text-ink-900">{log.action ?? log.event_type}</p>
                  <p className="text-xs text-ink-500">
                    {log.entity_type ?? "system"} · {log.entity_id ?? "—"} · {formatDateTime(log.created_at)}
                  </p>
                </div>
                <Badge variant="outline">{log.event_type}</Badge>
              </RowLink>
            ))
          ) : (
            <EmptyQueue>No audit events match this filter.</EmptyQueue>
          )}
        </QueueCard>

        {marketsNeedingAttention.length > 0 && (
          <QueueCard title="Markets needing attention" href="/countries">
            {marketsNeedingAttention.map((c: any) => (
              <RowLink key={c.code} href="/countries">
                <div>
                  <p className="text-sm font-medium text-ink-900">{c.name} ({c.code})</p>
                  <p className="text-xs text-ink-500">
                    Market is inactive but has active loan listings
                  </p>
                </div>
                <Badge variant="alert">inactive</Badge>
              </RowLink>
            ))}
          </QueueCard>
        )}

        <Card>
          <CardHeader>
            <CardTitle className="flex items-center gap-2">
              <Receipt className="h-4 w-4" /> Reminder
            </CardTitle>
          </CardHeader>
          <CardContent className="pt-0 text-sm text-ink-700">
            This console is read/act on the same Supabase project as the Flutter app. Nipanze
            never holds, pools, or moves funds between borrowers and lenders — actions here are
            limited to moderation (accounts, KYC, listings, markets, settings), never to
            payments between users.
          </CardContent>
        </Card>
      </main>
    </>
  );
}

async function getForexOverview(
  supabase: Awaited<ReturnType<typeof createClient>>,
  filters: { country?: string; fromDate?: string; toDate?: string }
) {
  let countQuery = (supabase as any)
    .from("forex_requests")
    .select("id", { count: "exact", head: true })
    .eq("status", "active");
  let dataQuery = (supabase as any)
    .from("forex_requests")
    .select("id, country, currency_held, currency_needed, amount, status, listed_at")
    .order("listed_at", { ascending: false })
    .limit(5);

  if (filters.country) {
    countQuery = countQuery.eq("country", filters.country);
    dataQuery = dataQuery.eq("country", filters.country);
  }
  if (filters.fromDate) {
    countQuery = countQuery.gte("listed_at", `${filters.fromDate}T00:00:00.000Z`);
    dataQuery = dataQuery.gte("listed_at", `${filters.fromDate}T00:00:00.000Z`);
  }
  if (filters.toDate) {
    countQuery = countQuery.lte("listed_at", `${filters.toDate}T23:59:59.999Z`);
    dataQuery = dataQuery.lte("listed_at", `${filters.toDate}T23:59:59.999Z`);
  }

  const [{ count, error: countError }, { data, error: dataError }] = await Promise.all([
    countQuery,
    dataQuery,
  ]);

  if (countError || dataError) {
    return { count: 0, data: [] as any[] };
  }

  return { count: count ?? 0, data: data ?? [] };
}

function MiniStat({ label, value }: { label: string; value: number }) {
  return (
    <div className="rounded-md border border-paper-200 px-3 py-2">
      <p className="text-xs text-ink-500">{label}</p>
      <p className="font-tabular text-lg font-semibold text-ink-900">{value}</p>
    </div>
  );
}

function QuickLink({ href, children }: { href: string; children: React.ReactNode }) {
  return (
    <Link
      href={href}
      className="inline-flex h-8 items-center rounded-md border border-paper-300 px-3 text-xs font-medium text-ink-700 hover:bg-paper-100"
    >
      {children}
    </Link>
  );
}

function QueueCard({
  title,
  href,
  children,
}: {
  title: string;
  href: string;
  children: React.ReactNode;
}) {
  return (
    <Card>
      <CardHeader className="flex-row items-center justify-between space-y-0">
        <CardTitle>{title}</CardTitle>
        <Link href={href} className="text-xs font-medium text-ink-700 hover:underline">
          View all
        </Link>
      </CardHeader>
      <CardContent className="space-y-2 pt-1">{children}</CardContent>
    </Card>
  );
}

function RowLink({ href, children }: { href: string; children: React.ReactNode }) {
  return (
    <Link
      href={href}
      className="flex items-center justify-between gap-3 rounded-md border border-paper-200 px-3 py-2.5 hover:bg-paper-50"
    >
      {children}
    </Link>
  );
}

function EmptyQueue({ children }: { children: React.ReactNode }) {
  return <p className="py-6 text-center text-sm text-ink-500">{children}</p>;
}
