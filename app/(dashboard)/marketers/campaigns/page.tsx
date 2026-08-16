import { Header } from "@/components/header";
import { AdminFilterForm } from "@/components/admin-filter-form";
import { MarketerNav } from "@/components/marketer-nav";
import { MarketerActions } from "@/components/marketer-actions";
import { Pagination } from "@/components/pagination";
import { Badge } from "@/components/ui/badge";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { createAdminClient } from "@/lib/supabase/admin";
import { getPage, getPageSize, getParam, type DashboardSearchParams } from "@/lib/dashboard-filters";
import { CAMPAIGN_STATUS_OPTIONS, asVariant, getCountryOptions, isMissingRelation, migrationMessage, statusOptions } from "@/lib/admin/marketers";
import { formatAmount, formatDateTime } from "@/lib/utils";

export const dynamic = "force-dynamic";

export default async function CampaignsPage({ searchParams }: { searchParams: Promise<DashboardSearchParams> }) {
  const params = await searchParams;
  const supabase = createAdminClient();
  const page = getPage(params);
  const pageSize = getPageSize(params);
  const country = getParam(params, "country");
  const status = getParam(params, "status");
  const countryOptions = await getCountryOptions();

  let query = supabase.from("referral_campaigns").select("*", { count: "exact" }).order("created_at", { ascending: false });
  if (country) query = query.eq("country", country);
  if (status) query = query.eq("status", status);
  const from = (page - 1) * pageSize;
  const { data, count, error } = await query.range(from, from + pageSize - 1);

  return (
    <>
      <Header title="Referral campaigns" description="Country-aware reward rules and historical reward snapshots" />
      <main className="flex-1 space-y-4 overflow-y-auto p-6">
        <MarketerNav active="/marketers/campaigns" />
        <AdminFilterForm resetHref="/marketers/campaigns" searchParams={params} fields={[
          { name: "country", label: "Country", type: "select", options: countryOptions },
          { name: "status", label: "Status", type: "select", options: statusOptions(CAMPAIGN_STATUS_OPTIONS, "All statuses") },
        ]} />
        {isMissingRelation(error) ? <p className="rounded-md border border-paper-300 bg-white p-4 text-sm text-ink-600">{migrationMessage()}</p> : (
          <>
            <Table>
              <TableHeader><TableRow><TableHead>Campaign</TableHead><TableHead>Country</TableHead><TableHead>Dates</TableHead><TableHead>Status</TableHead><TableHead>Qualification</TableHead><TableHead>Reward</TableHead><TableHead>Budget</TableHead><TableHead>Max referrals</TableHead><TableHead>Eligible plans</TableHead><TableHead>Updated</TableHead><TableHead>Actions</TableHead></TableRow></TableHeader>
              <TableBody>
                {(data ?? []).map((campaign) => (
                  <TableRow key={campaign.id}>
                    <TableCell><p className="font-medium text-ink-900">{campaign.name}</p><p className="text-xs text-ink-500">{campaign.description ?? "—"}</p></TableCell>
                    <TableCell>{campaign.country ?? "All"}</TableCell>
                    <TableCell className="text-xs text-ink-500">{campaign.start_date ?? "—"} → {campaign.end_date ?? "—"}</TableCell>
                    <TableCell><Badge variant={asVariant(campaign.status)}>{campaign.status}</Badge></TableCell>
                    <TableCell>{campaign.qualification_event}</TableCell>
                    <TableCell>{campaign.reward_type} · {formatAmount(campaign.reward_amount, campaign.reward_currency)}</TableCell>
                    <TableCell>{campaign.campaign_budget ? formatAmount(campaign.campaign_budget, campaign.reward_currency) : "—"}</TableCell>
                    <TableCell>{campaign.max_referrals ?? "—"}</TableCell>
                    <TableCell>{(campaign.eligible_plans ?? []).join(", ")}</TableCell>
                    <TableCell className="text-ink-500">{formatDateTime(campaign.updated_at)}</TableCell>
                    <TableCell><MarketerActions endpoint={`/api/admin/marketers/campaigns/${campaign.id}`} actions={[
                      { label: "Activate", value: "active", variant: "confirm", confirm: "Activate this campaign?" },
                      { label: "Pause", value: "paused", variant: "outline", confirm: "Pause this campaign?" },
                      { label: "End", value: "ended", variant: "destructive", confirm: "End this campaign?" },
                      { label: "Deactivate", value: "deactivated", variant: "destructive", confirm: "Deactivate this campaign?" },
                    ]} /></TableCell>
                  </TableRow>
                ))}
                {!data?.length ? <TableRow><TableCell colSpan={11} className="py-10 text-center text-sm text-ink-500">No campaigns match this filter. Campaign creation can be added on top of this rules table.</TableCell></TableRow> : null}
              </TableBody>
            </Table>
            <Pagination page={page} pageSize={pageSize} total={count ?? 0} searchParams={params} basePath="/marketers/campaigns" />
          </>
        )}
      </main>
    </>
  );
}
