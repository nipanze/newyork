import Link from "next/link";
import { Header } from "@/components/header";
import { AdminFilterForm } from "@/components/admin-filter-form";
import { MarketerNav } from "@/components/marketer-nav";
import { MarketerActions } from "@/components/marketer-actions";
import { Pagination } from "@/components/pagination";
import { Badge } from "@/components/ui/badge";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { createAdminClient } from "@/lib/supabase/admin";
import { getPage, getPageSize, getParam, type DashboardSearchParams } from "@/lib/dashboard-filters";
import { REWARD_STATUS_OPTIONS, asVariant, getCampaignOptions, getProfileSummaries, isMissingRelation, migrationMessage, statusOptions } from "@/lib/admin/marketers";
import { formatAmount, formatDateTime } from "@/lib/utils";

export const dynamic = "force-dynamic";

export default async function RewardsPage({ searchParams }: { searchParams: Promise<DashboardSearchParams> }) {
  const params = await searchParams;
  const supabase = createAdminClient();
  const page = getPage(params);
  const pageSize = getPageSize(params);
  const status = getParam(params, "status");
  const campaign = getParam(params, "campaign");
  const fromQ = getParam(params, "from");
  const toQ = getParam(params, "to");
  const campaigns = await getCampaignOptions();

  let query = supabase.from("referral_rewards").select("*", { count: "exact" }).order("created_at", { ascending: false });
  if (status) query = query.eq("status", status);
  if (campaign) query = query.eq("campaign_id", campaign);
  if (fromQ) query = query.gte("created_at", `${fromQ}T00:00:00.000Z`);
  if (toQ) query = query.lte("created_at", `${toQ}T23:59:59.999Z`);
  const from = (page - 1) * pageSize;
  const { data, count, error } = await query.range(from, from + pageSize - 1);
  const { data: marketers } = data?.length ? await supabase.from("referral_marketers").select("id, profile_id, referral_code").in("id", data.map((r) => r.marketer_id)) : { data: [] };
  const marketerById = new Map((marketers ?? []).map((m) => [m.id, m]));
  const profiles = await getProfileSummaries((marketers ?? []).map((m) => m.profile_id).concat((data ?? []).map((r) => r.referred_user_id).filter(Boolean) as string[]));

  return (
    <>
      <Header title="Referral rewards" description="Nipanze-owned marketing rewards, separate from P2P funds and platform revenue" />
      <main className="flex-1 space-y-4 overflow-y-auto p-6">
        <MarketerNav active="/marketers/rewards" />
        <AdminFilterForm resetHref="/marketers/rewards" searchParams={params} fields={[
          { name: "campaign", label: "Campaign", type: "select", options: campaigns.options },
          { name: "status", label: "Status", type: "select", options: statusOptions(REWARD_STATUS_OPTIONS, "All statuses") },
          { name: "from", label: "Created from", type: "date" },
          { name: "to", label: "Created to", type: "date" },
        ]} />
        {isMissingRelation(error) || campaigns.missing ? <p className="rounded-md border border-paper-300 bg-white p-4 text-sm text-ink-600">{migrationMessage()}</p> : (
          <>
            <Table>
              <TableHeader><TableRow><TableHead>Reward ID</TableHead><TableHead>Marketer</TableHead><TableHead>Referred user</TableHead><TableHead>Campaign</TableHead><TableHead>Type</TableHead><TableHead>Amount</TableHead><TableHead>Status</TableHead><TableHead>Created</TableHead><TableHead>Approved</TableHead><TableHead>Paid</TableHead><TableHead>Actions</TableHead></TableRow></TableHeader>
              <TableBody>
                {(data ?? []).map((reward) => {
                  const marketer = marketerById.get(reward.marketer_id);
                  return <TableRow key={reward.id}>
                    <TableCell className="font-mono text-xs">{reward.id.slice(0, 8)}</TableCell>
                    <TableCell>{marketer ? profiles.get(marketer.profile_id)?.full_name ?? marketer.referral_code : "—"}</TableCell>
                    <TableCell>{reward.referred_user_id ? profiles.get(reward.referred_user_id)?.full_name ?? reward.referred_user_id.slice(0, 8) : "—"}</TableCell>
                    <TableCell>{reward.campaign_id?.slice(0, 8) ?? "—"}</TableCell>
                    <TableCell>{reward.reward_type}</TableCell>
                    <TableCell>{formatAmount(reward.amount, reward.currency)}</TableCell>
                    <TableCell><Badge variant={asVariant(reward.status)}>{reward.status.replaceAll("_", " ")}</Badge></TableCell>
                    <TableCell className="text-ink-500">{formatDateTime(reward.created_at)}</TableCell>
                    <TableCell className="text-ink-500">{formatDateTime(reward.approved_at)}</TableCell>
                    <TableCell className="text-ink-500">{formatDateTime(reward.paid_at)}</TableCell>
                    <TableCell><MarketerActions endpoint={`/api/admin/marketers/rewards/${reward.id}`} actions={[
                      { label: "Approve", value: "approved", variant: "confirm", confirm: "Approve this reward?" },
                      { label: "Reject", value: "rejected", variant: "destructive", confirm: "Reject this reward?" },
                      { label: "Fraud hold", value: "fraud_hold", variant: "destructive", confirm: "Place this reward on fraud hold?" },
                      { label: "Mark paid", value: "paid", variant: "confirm", confirm: "Only continue if the payout process has verified payment. Mark paid?" },
                    ]} /></TableCell>
                  </TableRow>;
                })}
                {!data?.length ? <TableRow><TableCell colSpan={11} className="py-10 text-center text-sm text-ink-500">No rewards match this filter.</TableCell></TableRow> : null}
              </TableBody>
            </Table>
            <Pagination page={page} pageSize={pageSize} total={count ?? 0} searchParams={params} basePath="/marketers/rewards" />
          </>
        )}
      </main>
    </>
  );
}
