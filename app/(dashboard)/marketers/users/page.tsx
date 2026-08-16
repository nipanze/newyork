import Link from "next/link";
import { Header } from "@/components/header";
import { AdminFilterForm } from "@/components/admin-filter-form";
import { MarketerNav } from "@/components/marketer-nav";
import { Pagination } from "@/components/pagination";
import { Badge } from "@/components/ui/badge";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { createAdminClient } from "@/lib/supabase/admin";
import { getPage, getPageSize, getParam, type DashboardSearchParams } from "@/lib/dashboard-filters";
import {
  MARKETER_STATUS_OPTIONS,
  asVariant,
  escapeIlike,
  getCampaignOptions,
  getCountryOptions,
  getMatchingProfileIds,
  getProfileSummaries,
  isMissingRelation,
  migrationMessage,
  safeNumber,
  statusOptions,
} from "@/lib/admin/marketers";
import { formatAmount, formatDateTime } from "@/lib/utils";

export const dynamic = "force-dynamic";

export default async function MarketerListPage({
  searchParams,
}: {
  searchParams: Promise<DashboardSearchParams>;
}) {
  const params = await searchParams;
  const supabase = createAdminClient();
  const page = getPage(params);
  const pageSize = getPageSize(params);
  const q = getParam(params, "q");
  const country = getParam(params, "country");
  const status = getParam(params, "status");
  const campaign = getParam(params, "campaign");
  const joinedFrom = getParam(params, "joinedFrom");
  const joinedTo = getParam(params, "joinedTo");
  const performance = getParam(params, "performance");
  const [countryOptions, campaigns, profileMatches] = await Promise.all([
    getCountryOptions(),
    getCampaignOptions(),
    getMatchingProfileIds(q),
  ]);

  if (profileMatches && profileMatches.size === 0 && !q.includes("@")) {
    return <EmptyShell params={params} countryOptions={countryOptions} campaignOptions={campaigns.options} page={page} pageSize={pageSize} />;
  }

  let query = supabase
    .from("referral_marketers")
    .select("id, profile_id, referral_code, status, default_campaign_id, joined_at, last_activity_at", { count: "exact" })
    .order("joined_at", { ascending: false });

  if (q) {
    const byCode = `referral_code.ilike.%${escapeIlike(q)}%`;
    query = profileMatches?.size ? query.or(`${byCode},profile_id.in.(${[...profileMatches].join(",")})`) : query.ilike("referral_code", `%${escapeIlike(q)}%`);
  }
  if (status) query = query.eq("status", status);
  if (campaign) query = query.eq("default_campaign_id", campaign);
  if (joinedFrom) query = query.gte("joined_at", `${joinedFrom}T00:00:00.000Z`);
  if (joinedTo) query = query.lte("joined_at", `${joinedTo}T23:59:59.999Z`);

  const from = (page - 1) * pageSize;
  const { data: marketers, count, error } = await query.range(from, from + pageSize - 1);
  if (isMissingRelation(error) || campaigns.missing) {
    return <MissingShell params={params} countryOptions={countryOptions} campaignOptions={campaigns.options} />;
  }

  const profiles = await getProfileSummaries((marketers ?? []).map((m) => m.profile_id));
  let rows = await Promise.all(
    (marketers ?? []).map(async (marketer) => {
      const [referrals, qualified, pendingRewards, rewards] = await Promise.all([
        supabase.from("referrals").select("id", { count: "exact", head: true }).eq("referrer_id", marketer.profile_id),
        supabase.from("referrals").select("id", { count: "exact", head: true }).eq("referrer_id", marketer.profile_id).eq("status", "qualified"),
        supabase.from("referral_rewards").select("id", { count: "exact", head: true }).eq("marketer_id", marketer.id).eq("status", "pending"),
        supabase.from("referral_rewards").select("amount, currency, status").eq("marketer_id", marketer.id),
      ]);
      const rewardRows = rewards.data ?? [];
      return {
        marketer,
        profile: profiles.get(marketer.profile_id),
        totalReferrals: referrals.count ?? 0,
        qualifiedReferrals: qualified.count ?? 0,
        pendingRewards: pendingRewards.count ?? 0,
        totalEarned: rewardRows.reduce((sum, r) => sum + safeNumber(r.amount), 0),
        totalPaid: rewardRows.filter((r) => r.status === "paid").reduce((sum, r) => sum + safeNumber(r.amount), 0),
        currency: rewardRows[0]?.currency,
      };
    })
  );

  if (country) rows = rows.filter((row) => row.profile?.country === country);
  if (performance === "qualified") rows = rows.filter((row) => row.qualifiedReferrals > 0);
  if (performance === "pending_rewards") rows = rows.filter((row) => row.pendingRewards > 0);

  return (
    <>
      <Header title="Marketers" description="Referral-agent roster and performance controls" />
      <main className="flex-1 space-y-4 overflow-y-auto p-6">
        <MarketerNav active="/marketers/users" />
        <Filters params={params} countryOptions={countryOptions} campaignOptions={campaigns.options} />
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Marketer</TableHead>
              <TableHead>Referral code</TableHead>
              <TableHead>Country</TableHead>
              <TableHead>Status</TableHead>
              <TableHead>Referrals</TableHead>
              <TableHead>Qualified</TableHead>
              <TableHead>Pending rewards</TableHead>
              <TableHead>Total earned</TableHead>
              <TableHead>Total paid</TableHead>
              <TableHead>Joined</TableHead>
              <TableHead>Last activity</TableHead>
              <TableHead />
            </TableRow>
          </TableHeader>
          <TableBody>
            {rows.map((row) => (
              <TableRow key={row.marketer.id}>
                <TableCell>
                  <p className="font-medium text-ink-900">{row.profile?.full_name ?? "Unnamed marketer"}</p>
                  <p className="text-xs text-ink-500">{row.profile?.email ?? row.profile?.phone ?? "no contact"}</p>
                </TableCell>
                <TableCell className="font-mono text-xs">{row.marketer.referral_code}</TableCell>
                <TableCell>{row.profile?.country ?? "—"}</TableCell>
                <TableCell><Badge variant={asVariant(row.marketer.status)}>{row.marketer.status.replaceAll("_", " ")}</Badge></TableCell>
                <TableCell>{row.totalReferrals}</TableCell>
                <TableCell>{row.qualifiedReferrals}</TableCell>
                <TableCell>{row.pendingRewards}</TableCell>
                <TableCell>{formatAmount(row.totalEarned, row.currency)}</TableCell>
                <TableCell>{formatAmount(row.totalPaid, row.currency)}</TableCell>
                <TableCell className="text-ink-500">{formatDateTime(row.marketer.joined_at)}</TableCell>
                <TableCell className="text-ink-500">{formatDateTime(row.marketer.last_activity_at)}</TableCell>
                <TableCell className="text-right">
                  <Link href={`/marketers/users/${row.marketer.id}`} className="text-xs font-medium text-ink-700 hover:underline">Manage</Link>
                </TableCell>
              </TableRow>
            ))}
            {!rows.length ? <TableRow><TableCell colSpan={12} className="py-10 text-center text-sm text-ink-500">No marketers match this filter.</TableCell></TableRow> : null}
          </TableBody>
        </Table>
        <Pagination page={page} pageSize={pageSize} total={count ?? 0} searchParams={params} basePath="/marketers/users" />
      </main>
    </>
  );
}

function Filters({ params, countryOptions, campaignOptions }: { params: DashboardSearchParams; countryOptions: any[]; campaignOptions: any[] }) {
  return (
    <AdminFilterForm
      resetHref="/marketers/users"
      searchParams={params}
      fields={[
        { name: "q", label: "Search", placeholder: "Name, phone, email, or code" },
        { name: "country", label: "Country", type: "select", options: countryOptions },
        { name: "status", label: "Status", type: "select", options: statusOptions(MARKETER_STATUS_OPTIONS, "All statuses") },
        { name: "campaign", label: "Campaign", type: "select", options: campaignOptions },
        { name: "joinedFrom", label: "Joined from", type: "date" },
        { name: "joinedTo", label: "Joined to", type: "date" },
        { name: "performance", label: "Performance", type: "select", options: [
          { label: "All performance", value: "" },
          { label: "Has qualified referrals", value: "qualified" },
          { label: "Has pending rewards", value: "pending_rewards" },
        ] },
      ]}
    />
  );
}

function MissingShell({ params, countryOptions, campaignOptions }: { params: DashboardSearchParams; countryOptions: any[]; campaignOptions: any[] }) {
  return (
    <>
      <Header title="Marketers" description="Referral-agent roster and performance controls" />
      <main className="flex-1 space-y-4 overflow-y-auto p-6">
        <MarketerNav active="/marketers/users" />
        <Filters params={params} countryOptions={countryOptions} campaignOptions={campaignOptions} />
        <p className="rounded-md border border-paper-300 bg-white p-4 text-sm text-ink-600">{migrationMessage()}</p>
      </main>
    </>
  );
}

function EmptyShell({ params, countryOptions, campaignOptions, page, pageSize }: any) {
  return (
    <>
      <Header title="Marketers" description="Referral-agent roster and performance controls" />
      <main className="flex-1 space-y-4 overflow-y-auto p-6">
        <MarketerNav active="/marketers/users" />
        <Filters params={params} countryOptions={countryOptions} campaignOptions={campaignOptions} />
        <p className="py-10 text-center text-sm text-ink-500">No marketers match this filter.</p>
        <Pagination page={page} pageSize={pageSize} total={0} searchParams={params} basePath="/marketers/users" />
      </main>
    </>
  );
}
