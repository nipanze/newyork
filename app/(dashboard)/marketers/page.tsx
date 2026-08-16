import Link from "next/link";
import { Header } from "@/components/header";
import { AdminFilterForm } from "@/components/admin-filter-form";
import { MarketerNav } from "@/components/marketer-nav";
import { StatCard } from "@/components/stat-card";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { createAdminClient } from "@/lib/supabase/admin";
import { buildQueryString, getParam, type DashboardSearchParams } from "@/lib/dashboard-filters";
import {
  MARKETER_STATUS_OPTIONS,
  REFERRAL_STATUS_OPTIONS,
  REWARD_STATUS_OPTIONS,
  applyDateRange,
  asVariant,
  getCampaignOptions,
  getCountryOptions,
  getDateRange,
  isMissingRelation,
  migrationMessage,
  statusOptions,
} from "@/lib/admin/marketers";
import { BadgeCheck, Banknote, Megaphone, MousePointerClick, ShieldAlert, Users } from "lucide-react";
import { formatAmount, formatDateTime } from "@/lib/utils";

export const dynamic = "force-dynamic";

export default async function MarketersOverviewPage({
  searchParams,
}: {
  searchParams: Promise<DashboardSearchParams>;
}) {
  const params = await searchParams;
  const supabase = createAdminClient();
  const country = getParam(params, "country");
  const campaign = getParam(params, "campaign");
  const marketerStatus = getParam(params, "marketerStatus");
  const referralStatus = getParam(params, "referralStatus");
  const rewardStatus = getParam(params, "rewardStatus");
  const { from, to } = getDateRange(params);
  const [countryOptions, campaigns] = await Promise.all([getCountryOptions(), getCampaignOptions()]);

  let marketersQuery = supabase
    .from("referral_marketers")
    .select("id, profile_id, referral_code, status, joined_at, last_activity_at, default_campaign_id", { count: "exact" })
    .order("joined_at", { ascending: false })
    .limit(6);
  if (marketerStatus) marketersQuery = marketersQuery.eq("status", marketerStatus);
  if (campaign) marketersQuery = marketersQuery.eq("default_campaign_id", campaign);
  marketersQuery = applyDateRange(marketersQuery, "joined_at", from, to);

  const { data: marketers, count: totalMarketers, error: marketerError } = await marketersQuery;
  if (isMissingRelation(marketerError) || campaigns.missing) {
    return <MissingDepartment params={params} countryOptions={countryOptions} />;
  }

  const marketerIds = (marketers ?? []).map((m) => m.id);
  const profileIds = (marketers ?? []).map((m) => m.profile_id);
  const { data: profiles } = profileIds.length
    ? await supabase.from("profiles").select("id, full_name, country").in("id", profileIds)
    : { data: [] };
  const profileById = new Map((profiles ?? []).map((p) => [p.id, p]));

  const [
    { count: activeMarketers },
    { count: newMarketers },
    referrals,
    { count: registeredReferrals },
    { count: verifiedReferrals },
    { count: qualifiedReferrals },
    rewards,
    { count: activeCampaigns },
    { count: riskCount },
  ] = await Promise.all([
    supabase.from("referral_marketers").select("id", { count: "exact", head: true }).eq("status", "active"),
    applyDateRange(supabase.from("referral_marketers").select("id", { count: "exact", head: true }).eq("status", "new"), "joined_at", from, to),
    getFilteredReferrals({ supabase, country, campaign, status: referralStatus, from, to }),
    getFilteredReferrals({ supabase, country, campaign, status: "registered", from, to, head: true }),
    getFilteredReferrals({ supabase, country, campaign, status: "verified", from, to, head: true }),
    getFilteredReferrals({ supabase, country, campaign, status: "qualified", from, to, head: true }),
    getFilteredRewards({ supabase, campaign, status: rewardStatus, from, to }),
    supabase.from("referral_campaigns").select("id", { count: "exact", head: true }).eq("status", "active"),
    supabase.from("referral_marketers").select("id", { count: "exact", head: true }).in("risk_status", ["review", "flagged"]),
  ]);

  const rewardRows = rewards.data ?? [];
  const totals = (rewardRows as Array<{ status: string; amount: number | null; currency: string | null }>).reduce(
    (acc: { pending: number; approved: number; paid: number; value: number; currency: string | null }, reward) => {
      acc.pending += reward.status === "pending" ? 1 : 0;
      acc.approved += reward.status === "approved" ? 1 : 0;
      acc.paid += reward.status === "paid" ? 1 : 0;
      acc.value += Number(reward.amount ?? 0);
      acc.currency = acc.currency ?? reward.currency;
      return acc;
    },
    { pending: 0, approved: 0, paid: 0, value: 0, currency: null as string | null }
  );

  return (
    <>
      <Header title="Marketers" description="Referral agents, campaigns, rewards, payouts, and risk controls" />
      <main className="flex-1 space-y-6 overflow-y-auto p-6">
        <MarketerNav active="/marketers" />
        <AdminFilterForm
          resetHref="/marketers"
          searchParams={params}
          fields={[
            { name: "country", label: "Country", type: "select", options: countryOptions },
            { name: "campaign", label: "Campaign", type: "select", options: campaigns.options },
            { name: "marketerStatus", label: "Marketer status", type: "select", options: statusOptions(MARKETER_STATUS_OPTIONS, "All marketers") },
            { name: "referralStatus", label: "Referral status", type: "select", options: statusOptions(REFERRAL_STATUS_OPTIONS, "All referrals") },
            { name: "rewardStatus", label: "Reward status", type: "select", options: statusOptions(REWARD_STATUS_OPTIONS, "All rewards") },
            { name: "from", label: "From", type: "date" },
            { name: "to", label: "To", type: "date" },
          ]}
        />

        <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 xl:grid-cols-4">
          <StatCard label="Total marketers" value={totalMarketers ?? 0} icon={Users} />
          <StatCard label="Active marketers" value={activeMarketers ?? 0} icon={BadgeCheck} tone="confirm" />
          <StatCard label="New marketers" value={newMarketers ?? 0} icon={Megaphone} tone="signal" />
          <StatCard label="Total referrals" value={referrals.count ?? 0} icon={MousePointerClick} />
          <StatCard label="Registered referrals" value={registeredReferrals ?? 0} icon={Users} />
          <StatCard label="Verified referrals" value={verifiedReferrals ?? 0} icon={BadgeCheck} tone="confirm" />
          <StatCard label="Qualified referrals" value={qualifiedReferrals ?? 0} icon={BadgeCheck} tone="confirm" />
          <StatCard label="Pending rewards" value={totals.pending} icon={Banknote} tone={totals.pending ? "signal" : "neutral"} />
          <StatCard label="Approved rewards" value={totals.approved} icon={Banknote} tone="confirm" />
          <StatCard label="Paid rewards" value={totals.paid} icon={Banknote} tone="confirm" />
          <StatCard label="Total reward value" value={formatAmount(totals.value, totals.currency ?? undefined)} icon={Banknote} />
          <StatCard label="Active campaigns" value={activeCampaigns ?? 0} icon={Megaphone} />
          <StatCard label="Risk reviews" value={riskCount ?? 0} icon={ShieldAlert} tone={riskCount ? "alert" : "neutral"} />
        </div>

        <div className="grid grid-cols-1 gap-4 lg:grid-cols-3">
          <Card className="lg:col-span-2">
            <CardHeader>
              <CardTitle>Recent marketers</CardTitle>
            </CardHeader>
            <CardContent className="space-y-2 pt-0">
              {(marketers ?? []).map((marketer) => {
                const profile = profileById.get(marketer.profile_id);
                return (
                  <Link key={marketer.id} href={`/marketers/users/${marketer.id}`} className="flex items-center justify-between rounded-md border border-paper-200 px-3 py-2 text-sm hover:bg-paper-100">
                    <span>
                      <span className="font-medium text-ink-900">{profile?.full_name ?? marketer.referral_code}</span>
                      <span className="ml-2 text-xs text-ink-500">{profile?.country ?? "—"} · {marketer.referral_code}</span>
                    </span>
                    <Badge variant={asVariant(marketer.status)}>{marketer.status.replaceAll("_", " ")}</Badge>
                  </Link>
                );
              })}
              {!marketers?.length ? <p className="text-sm text-ink-500">No marketers match this filter.</p> : null}
            </CardContent>
          </Card>

          <Card>
            <CardHeader>
              <CardTitle>Department controls</CardTitle>
            </CardHeader>
            <CardContent className="flex flex-col gap-2 pt-0">
              <Quick href={`/marketers/users?${buildQueryString(params, { page: 1 })}`}>Open marketer list</Quick>
              <Quick href={`/marketers/referrals?${buildQueryString(params, { page: 1 })}`}>Review referrals</Quick>
              <Quick href={`/marketers/rewards?${buildQueryString(params, { page: 1 })}`}>Manage rewards</Quick>
              <Quick href="/marketers/payouts">Payout queue</Quick>
              <Quick href="/marketers/campaigns">Campaign rules</Quick>
              <Quick href="/marketers/risk">Fraud/Risk</Quick>
            </CardContent>
          </Card>
        </div>
      </main>
    </>
  );
}

function MissingDepartment({ params, countryOptions }: { params: DashboardSearchParams; countryOptions: any[] }) {
  return (
    <>
      <Header title="Marketers" description="Referral agents, campaigns, rewards, payouts, and risk controls" />
      <main className="flex-1 space-y-4 overflow-y-auto p-6">
        <MarketerNav active="/marketers" />
        <AdminFilterForm resetHref="/marketers" searchParams={params} fields={[{ name: "country", label: "Country", type: "select", options: countryOptions }]} />
        <p className="rounded-md border border-paper-300 bg-white p-4 text-sm text-ink-600">{migrationMessage()}</p>
      </main>
    </>
  );
}

function Quick({ href, children }: { href: string; children: React.ReactNode }) {
  return <Link href={href} className="rounded-md border border-paper-300 px-3 py-2 text-sm font-medium text-ink-700 hover:bg-paper-100">{children}</Link>;
}

async function getFilteredReferrals({ supabase, country, campaign, status, from, to, head }: any) {
  let query = supabase.from("referrals").select("id", { count: "exact", head: Boolean(head) });
  if (country) query = query.eq("country", country);
  if (campaign) query = query.eq("campaign_id", campaign);
  if (status) query = query.eq("status", status);
  return applyDateRange(query, "created_at", from, to);
}

async function getFilteredRewards({ supabase, campaign, status, from, to }: any) {
  let query = supabase.from("referral_rewards").select("id, status, amount, currency").limit(1000);
  if (campaign) query = query.eq("campaign_id", campaign);
  if (status) query = query.eq("status", status);
  return applyDateRange(query, "created_at", from, to);
}
